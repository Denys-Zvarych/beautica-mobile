// Phase 363 — the paged «Сповіщення» feed.
//
// Locked rules (phase 363 spec):
//  * PER USER, global across every salon an owner owns — no `salonId` family
//    argument and no watch of any salon provider. Watches ONLY the settled user
//    id (`authUserIdOrNull`), never a bare `authProvider`, so a token refresh
//    does not rebuild (and refetch) the feed.
//  * 20 rows per page. [loadMore] is guarded three ways — in flight, no more
//    pages, a recorded failure — so a footer rebuilt many times while visible
//    can never become a request loop. A failure is cleared only by an explicit
//    [retryLoadMore] (the footer's button, or its cooldown elapsing).
//  * PAGING IS OFFSET-BASED (`GET /notifications` takes only `page` + `size`;
//    the OpenAPI snapshot has no cursor), so the feed is NOT shift-proof:
//    a row inserted at the top pushes rows DOWN into the next page (the id
//    dedupe in [loadMore] absorbs the duplicate), while a row deleted above
//    the loaded window would pull one row UP across a page boundary and skip
//    it. The only deleter is the 90-day retention job, which removes the OLDEST
//    rows — the tail, never a row above the loaded window — so the skip is
//    accepted; pull-to-refresh re-reads from page 0 and recovers anything.
//  * A refresh that lands while a next page is in flight bumps an epoch: the
//    stale page is dropped (never appended) and the footer stays busy until it
//    settles, so the refresh cannot cause a duplicate page request.
//  * OWNERSHIP: every state carries the `ownerUserId` it was loaded for; a
//    state owned by a previous user is never actionable (no-op).
//  * [refresh] coalesces; it also nudges `UnreadNotifications.refresh()`,
//    which coalesces on its own.
//  * Mark-read is OPTIMISTIC: the row flips and the bell count drops in the
//    same frame, the PATCH follows, and a failure rolls both back. A 404 (the
//    item was deleted, or is not ours) is "done", never an error.
//  * STALE-USER GUARD (phase 360 security INFO-1): every
//    `UnreadNotifications.setCount` / `decrement` passes the user id captured
//    when the request was ISSUED, never one read after an `await`, so a late
//    response that belongs to a user who has since logged out is dropped by
//    the count notifier.

import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/errors/failures.dart';
import '../../../core/time/clock_provider.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../data/notification_repository.dart';
import '../domain/app_notification.dart';
import '../domain/notifications_feed_state.dart';
import 'unread_notifications_notifier.dart';

part 'notifications_feed_notifier.g.dart';

@riverpod
class NotificationsFeed extends _$NotificationsFeed {
  String? _userId;
  Future<void>? _refreshing;

  /// Bumped whenever the first page REPLACES the list (refresh landing, or a
  /// rebuild). A [loadMore] that started under an older epoch is stale: its
  /// page was computed against a list that no longer exists, so it is dropped.
  int _epoch = 0;

  /// A next-page request is on the wire. Survives a refresh (which replaces the
  /// list) so a footer rebuilt by that refresh cannot start a SECOND request
  /// for the same page while the first is still in flight.
  bool _loadMoreInFlight = false;

  /// Ids flipped to read optimistically and not yet settled. A refresh or page
  /// that lands while one is in flight must not flip it back to unread.
  final Set<String> _pendingRead = <String>{};

  /// How long a row marked read in this session keeps winning over a server
  /// page that may have been READ before the PATCH committed.
  static const Duration _recentReadWindow = Duration(minutes: 2);

  /// Ids marked read locally (single or mark-all) and settled, with the time
  /// they were marked. A refresh / page result can only UPGRADE these rows:
  /// its GET may have begun before the PATCH committed, so its `read: false`
  /// is stale. There is no "mark unread" endpoint, so holding a row read is
  /// always correct.
  final Map<String, DateTime> _recentlyRead = <String, DateTime>{};

  /// Bumped when a mark-all SUCCEEDS. A single mark-read issued under an
  /// older generation is superseded: the server already holds that row read,
  /// so its late failure must neither un-read the row nor touch the count.
  int _markAllGeneration = 0;

  /// The `upTo` of each SUCCEEDED mark-all, keyed by the generation it created.
  /// A superseded single mark-read is only "covered" when a mark-all issued
  /// after it reached the row's `createdAt`; a row newer than every such
  /// `upTo` was never marked server-side and must roll back.
  final Map<int, DateTime?> _markAllUpTo = <int, DateTime?>{};

  /// The [_markAllGeneration] each in-flight single mark-read was issued
  /// under. Only entries of [_markAllUpTo] NEWER than the oldest of these can
  /// still be consulted, so the rest are pruned ([_pruneMarkAllUpTo]).
  final Map<String, int> _pendingIssuedGeneration = <String, int>{};

  /// How many `upTo` entries are retained (tests: bounded by the prune).
  @visibleForTesting
  int get debugMarkAllUpToCount => _markAllUpTo.length;

  /// Drops `upTo` entries no in-flight single can reference: generations at or
  /// below the oldest pending single's issued generation. With none pending,
  /// only the latest is kept.
  void _pruneMarkAllUpTo() {
    if (_markAllUpTo.isEmpty) return;
    if (_pendingIssuedGeneration.isEmpty) {
      final int latest = _markAllGeneration;
      _markAllUpTo.removeWhere((int g, DateTime? _) => g != latest);
      return;
    }
    int oldest = _pendingIssuedGeneration.values.first;
    for (final int g in _pendingIssuedGeneration.values) {
      if (g < oldest) oldest = g;
    }
    _markAllUpTo.removeWhere((int g, DateTime? _) => g <= oldest);
  }

  /// The ids held read after settling (tests: growth is bounded by the sweep
  /// in [_noteRead]).
  @visibleForTesting
  Set<String> get debugRecentlyReadIds => _recentlyRead.keys.toSet();

  @override
  Future<NotificationsFeedState> build() async {
    final String? userId = ref.watch(authProvider.select(authUserIdOrNull));
    final NotificationRepository repo = ref.watch(
      notificationRepositoryProvider,
    );
    _userId = userId;
    _refreshing = null;
    _epoch++;
    _loadMoreInFlight = false;
    _pendingRead.clear();
    _recentlyRead.clear();
    _markAllUpTo.clear();
    _pendingIssuedGeneration.clear();
    if (userId == null) {
      return const NotificationsFeedState(
        items: <AppNotification>[],
        nextPage: 0,
        hasMore: false,
      );
    }
    final NotificationPage page = await repo.fetchPage(
      page: 0,
      size: kNotificationsPageSize,
    );
    return _fromFirstPage(page);
  }

  NotificationsFeedState _fromFirstPage(NotificationPage page) =>
      NotificationsFeedState(
        items: _applyPending(page.items),
        nextPage: page.page + 1,
        hasMore: page.hasNext,
        // A next-page request still on the wire keeps the footer "busy" until
        // it settles, so the refresh cannot hand out a second request for it.
        loadingMore: _loadMoreInFlight,
        ownerUserId: _userId,
      );

  List<AppNotification> _applyPending(List<AppNotification> items) {
    if (_pendingRead.isEmpty && _recentlyRead.isEmpty) return items;
    return <AppNotification>[
      for (final AppNotification n in items)
        _isHeldRead(n.id) ? n.copyWith(read: true) : n,
    ];
  }

  bool _isHeldRead(String id) {
    if (_pendingRead.contains(id)) return true;
    final DateTime? at = _recentlyRead[id];
    if (at == null) return false;
    if (ref.read(clockProvider)().difference(at) > _recentReadWindow) {
      _recentlyRead.remove(id);
      return false;
    }
    return true;
  }

  void _noteRead(Iterable<String> ids) {
    final DateTime now = ref.read(clockProvider)();
    // Sweep expired holds so the map is bounded by what was marked inside one
    // window, not by the session.
    _recentlyRead.removeWhere(
      (String _, DateTime at) => now.difference(at) > _recentReadWindow,
    );
    for (final String id in ids) {
      _recentlyRead[id] = now;
    }
  }

  /// Re-fetches the first page and replaces the list. Concurrent calls share
  /// one request. Throws the [Failure] when a list is already on screen (the
  /// caller shows a snackbar and the list stays); with no list it becomes the
  /// error state instead.
  Future<void> refresh() {
    final Future<void>? existing = _refreshing;
    if (existing != null) return existing;
    final Future<void> request = _refresh().whenComplete(() {
      _refreshing = null;
    });
    _refreshing = request;
    return request;
  }

  Future<void> _refresh() async {
    final String? userId = _userId;
    if (userId == null) return;
    // Nudges the bell count; coalesces inside the notifier.
    unawaited(ref.read(unreadNotificationsProvider.notifier).refresh());
    try {
      final NotificationPage page = await ref
          .read(notificationRepositoryProvider)
          .fetchPage(page: 0, size: kNotificationsPageSize);
      if (!ref.mounted || userId != _userId) return;
      // The list is replaced: any next-page result computed against the old
      // one is stale (see [_epoch]).
      _epoch++;
      state = AsyncData<NotificationsFeedState>(_fromFirstPage(page));
    } on Failure catch (f, st) {
      if (!ref.mounted || userId != _userId) return;
      _log('refresh failed: ${f.runtimeType}');
      if (state.value == null) {
        state = AsyncError<NotificationsFeedState>(f, st);
        return;
      }
      rethrow;
    }
  }

  /// Requests the next page when one exists and nothing forbids it.
  Future<void> loadMore() async {
    final NotificationsFeedState? current = state.value;
    final String? userId = _userId;
    if (current == null ||
        userId == null ||
        current.ownerUserId != userId ||
        current.loadingMore ||
        _loadMoreInFlight ||
        // A refresh is about to replace the list and reset `nextPage`; a page
        // requested now would be computed against the list being discarded.
        _refreshing != null ||
        !current.hasMore ||
        current.loadMoreFailure != null) {
      return;
    }
    final int epoch = _epoch;
    _loadMoreInFlight = true;
    state = AsyncData<NotificationsFeedState>(
      current.copyWith(loadingMore: true),
    );
    try {
      final NotificationPage page = await ref
          .read(notificationRepositoryProvider)
          .fetchPage(page: current.nextPage, size: kNotificationsPageSize);
      if (!ref.mounted || userId != _userId) return;
      if (epoch != _epoch) return _settleStaleLoadMore();
      _loadMoreInFlight = false;
      final NotificationsFeedState latest = state.value ?? current;
      final Set<String> known = <String>{
        for (final AppNotification n in latest.items) n.id,
      };
      state = AsyncData<NotificationsFeedState>(
        latest.copyWith(
          items: <AppNotification>[
            ...latest.items,
            ..._applyPending(
              page.items
                  .where((AppNotification n) => !known.contains(n.id))
                  .toList(growable: false),
            ),
          ],
          nextPage: page.page + 1,
          hasMore: page.hasNext,
          loadingMore: false,
          loadMoreFailure: null,
          loadMoreRetryNotBefore: null,
        ),
      );
    } on Failure catch (f) {
      if (!ref.mounted || userId != _userId) return;
      if (epoch != _epoch) return _settleStaleLoadMore();
      _loadMoreInFlight = false;
      _log('loadMore failed: ${f.runtimeType}');
      final NotificationsFeedState latest = state.value ?? current;
      state = AsyncData<NotificationsFeedState>(
        latest.copyWith(
          loadingMore: false,
          loadMoreFailure: f,
          loadMoreRetryNotBefore: switch (f) {
            NotificationsRateLimitedFailure(:final int? retryAfterSeconds)
                when retryAfterSeconds != null && retryAfterSeconds > 0 =>
              ref
                  .read(clockProvider)()
                  .add(
                    // The server's number is untrusted: clamp it to the same
                    // UX window the count poller uses (30 s .. 1 h).
                    Duration(
                      seconds: retryAfterSeconds.clamp(
                        kUnreadMinRetryAfter.inSeconds,
                        kUnreadMaxRetryAfter.inSeconds,
                      ),
                    ),
                  ),
            _ => null,
          },
        ),
      );
    }
  }

  /// A next-page request that outlived a refresh: its result (or failure) is
  /// dropped, the footer is released, and its rebuild lets a still-visible
  /// footer ask for the page again against the REFRESHED list.
  void _settleStaleLoadMore() {
    _loadMoreInFlight = false;
    final NotificationsFeedState? latest = state.value;
    if (latest == null || !latest.loadingMore) return;
    state = AsyncData<NotificationsFeedState>(
      latest.copyWith(loadingMore: false),
    );
  }

  /// Clears a recorded next-page failure and tries again. Called by the
  /// footer's retry button and by its cooldown elapsing.
  Future<void> retryLoadMore() async {
    final NotificationsFeedState? current = state.value;
    if (current == null ||
        current.ownerUserId != _userId ||
        current.loadMoreFailure == null) {
      return;
    }
    state = AsyncData<NotificationsFeedState>(
      current.copyWith(loadMoreFailure: null, loadMoreRetryNotBefore: null),
    );
    await loadMore();
  }

  /// Marks one row read. Returns `false` only when the request FAILED and the
  /// row was rolled back (the caller shows the snackbar); `true` otherwise,
  /// including an already-read row and a 404.
  Future<bool> markRead(String id) async {
    final NotificationsFeedState? current = state.value;
    final String? userId = _userId;
    // A state owned by a previous user (kept on screen by Riverpod while the
    // new user's first page loads) is never actionable.
    if (current == null || userId == null || current.ownerUserId != userId) {
      return true;
    }
    final int index = current.items.indexWhere(
      (AppNotification n) => n.id == id,
    );
    if (index < 0 || current.items[index].read) return true;

    final UnreadNotifications unread = ref.read(
      unreadNotificationsProvider.notifier,
    );
    // `decrement` floors at zero, so it only moved the count when it was > 0;
    // the rollback undoes exactly that, by delta (never an absolute snapshot,
    // which would erase a concurrent row's decrement).
    final bool decremented =
        (ref.read(unreadNotificationsProvider).value ?? 0) > 0;
    final int generation = _markAllGeneration;
    final DateTime createdAt = current.items[index].createdAt;
    _setRead(<String>{id}, true);
    _pendingRead.add(id);
    _pendingIssuedGeneration[id] = generation;
    unread.decrement(forUserId: userId);
    try {
      await ref.read(notificationRepositoryProvider).markRead(id);
      _settleRead(id, userId);
      return true;
    } on NotFoundFailure {
      // Deleted (or not ours): there is nothing to keep unread. Treat as done.
      _settleRead(id, userId);
      return true;
    } catch (e) {
      // Any other failure (the repository throws typed Failures; a stray
      // exception must still roll the optimistic flip back).
      _log('markRead failed: ${e.runtimeType}');
      _pendingRead.remove(id);
      if (_coveredByLaterMarkAll(generation, createdAt)) {
        // A mark-all that reached this row succeeded after this request was
        // issued: the server already holds the row read. Neither un-read it
        // nor touch the count.
        if (ref.mounted && userId == _userId) _noteRead(<String>[id]);
        return true;
      }
      // Not covered (no newer mark-all, or the row is newer than its `upTo`):
      // the normal rollback, and the row stops being held read.
      _recentlyRead.remove(id);
      // Rolled back with the id captured BEFORE the await; the count notifier
      // drops it if that user has gone.
      if (decremented) unread.increment(forUserId: userId);
      if (generation != _markAllGeneration) {
        // A mark-all intervened but did not cover this row, and its recount
        // (applied before this rollback) excluded the row, so the increment
        // above can leave the bell at +1. `increment` bumps the count
        // notifier's version, so this refresh starts fresh rather than
        // coalescing with a stale in-flight fetch.
        unawaited(unread.refresh());
      }
      if (ref.mounted && userId == _userId) _setRead(<String>{id}, false);
      return false;
    } finally {
      _pendingIssuedGeneration.remove(id);
      _pruneMarkAllUpTo();
    }
  }

  /// Marks every loaded row read (`upTo` = the newest loaded `createdAt`),
  /// then re-reads the true count. Returns `false` when the request failed and
  /// everything was rolled back.
  Future<bool> markAllRead() async {
    final NotificationsFeedState? current = state.value;
    final String? userId = _userId;
    if (current == null || userId == null || current.ownerUserId != userId) {
      return true;
    }
    final DateTime? upTo = current.newestCreatedAt;
    final Set<String> ids = <String>{
      for (final AppNotification n in current.items)
        if (!n.read) n.id,
    };
    final UnreadNotifications unread = ref.read(
      unreadNotificationsProvider.notifier,
    );
    final int countBefore = ref.read(unreadNotificationsProvider).value ?? 0;
    if (ids.isEmpty && countBefore == 0) return true;

    _setRead(ids, true);
    _pendingRead.addAll(ids);
    unread.setCount(0, forUserId: userId);
    final NotificationRepository repo = ref.read(
      notificationRepositoryProvider,
    );
    try {
      await repo.markAllRead(upTo: upTo);
    } catch (e) {
      _log('markAllRead failed: ${e.runtimeType}');
      _pendingRead.removeAll(ids);
      // By delta, not `setCount(countBefore)`: rows marked/rolled back on
      // their own while this PATCH was open keep their own adjustments. Delta
      // also works offline, which is exactly when this failure happens.
      unread.increment(forUserId: userId, by: countBefore);
      // The delta can over-count (a poll after `setCount(0)` may have
      // re-emitted the old number; a timed-out PATCH may have committed), so
      // reconcile with the server right away.
      unawaited(unread.refresh());
      if (ref.mounted && userId == _userId) {
        _setRead(ids, false);
        // On a timeout the server may have committed: do not trust the local
        // flip-back, re-read the feed. A failure here (offline) keeps the
        // rolled-back list on screen.
        unawaited(refresh().then<void>((_) {}, onError: (Object _) {}));
      }
      return false;
    }
    _markAllGeneration++;
    _markAllUpTo[_markAllGeneration] = upTo;
    _pruneMarkAllUpTo();
    _pendingRead.removeAll(ids);
    if (ref.mounted && userId == _userId) {
      // Everything loaded up to `upTo` is now read server-side — including a
      // row a single mark-read rolled back while this PATCH was open.
      final NotificationsFeedState? now = state.value;
      final Set<String> covered = <String>{
        ...ids,
        for (final AppNotification n in now?.items ?? const <AppNotification>[])
          if (upTo != null && !n.createdAt.isAfter(upTo)) n.id,
      };
      _noteRead(covered);
      _setRead(covered, true);
    }
    // Rows newer than `upTo` (arrived meanwhile) stay unread, so the count is
    // re-read rather than assumed to be zero.
    try {
      final int remaining = await repo.unreadCount();
      unread.setCount(remaining, forUserId: userId);
    } catch (e) {
      _log('unread recount failed: ${e.runtimeType}');
      unawaited(unread.refresh());
    }
    return true;
  }

  /// Whether a mark-all that succeeded AFTER a single mark-read was issued
  /// (under [issuedGeneration]) reached a row created at [createdAt].
  bool _coveredByLaterMarkAll(int issuedGeneration, DateTime createdAt) {
    for (final MapEntry<int, DateTime?> e in _markAllUpTo.entries) {
      final DateTime? upTo = e.value;
      if (e.key > issuedGeneration &&
          upTo != null &&
          !createdAt.isAfter(upTo)) {
        return true;
      }
    }
    return false;
  }

  /// A single mark-read settled (or 404'd): the row stays read, and keeps
  /// winning over a page whose GET began before the PATCH committed.
  void _settleRead(String id, String userId) {
    _pendingRead.remove(id);
    if (ref.mounted && userId == _userId) _noteRead(<String>[id]);
  }

  void _setRead(Set<String> ids, bool read) {
    if (!ref.mounted) return;
    final NotificationsFeedState? current = state.value;
    if (current == null || ids.isEmpty) return;
    state = AsyncData<NotificationsFeedState>(
      current.copyWith(
        items: <AppNotification>[
          for (final AppNotification n in current.items)
            ids.contains(n.id) ? n.copyWith(read: read) : n,
        ],
      ),
    );
  }

  void _log(String message) =>
      log(message, name: 'feature.notifications.feed', level: 900);
}
