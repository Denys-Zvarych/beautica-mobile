// Phase 360 — app-wide unread-notification count + foreground polling.
//
// One keepAlive source of truth for "is there anything new" (the bell dot,
// phase 361). No push: the count is refetched on `resumed`, every
// [pollIntervalProvider] while foregrounded, and on demand via [refresh].
//
// Locked rules:
//  * GLOBAL per user — no `salonId` family arg, no watch of any salon
//    provider. Switching salons causes no refetch / reset.
//  * Watches ONLY the settled user id (`authUserIdOrNull`), never a bare
//    `authProvider` — token refresh must not rebuild (and re-fetch) this.
//  * Concurrent [refresh] calls share ONE in-flight request (coalescing).
//  * 429 suspends polling for `Retry-After` (default 120 s), then resumes.
//  * Network / server / unexpected error keeps the last value; the next tick
//    retries.
//  * A fetch that was in flight across an optimistic mutation
//    ([setCount] / [decrement]) drops its (stale) result, and a [refresh]
//    issued after the mutation starts a fresh request instead of joining it.
//  * A stale (dropped) fetch schedules one follow-up [refresh] so the count
//    reconciles immediately rather than at the next tick.
//  * A `resumed`-triggered fetch is skipped within [kUnreadResumeMinGap] of the
//    last completed fetch (success or failure, not 429); a wall clock that
//    moved backwards never suppresses. Explicit [refresh] / ticks are exempt.
//  * A rebuild for the SAME user (e.g. poll-interval change) keeps the count.

import 'dart:async';
import 'dart:developer';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/errors/failures.dart';
import '../../../core/time/clock_provider.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../data/notification_repository.dart';

part 'unread_notifications_notifier.g.dart';

/// Foreground polling period. A provider so tests can shorten it.
const Duration kUnreadPollInterval = Duration(seconds: 60);

/// Back-off when a 429 carries no usable `Retry-After`.
const Duration kUnreadDefaultRetryAfter = Duration(seconds: 120);

/// Minimum gap between the last completed fetch attempt (success, Failure or
/// unexpected error; not a 429) and a resume-triggered one.
const Duration kUnreadResumeMinGap = Duration(seconds: 15);

/// Bounds applied to a server-supplied 429 `Retry-After` back-off.
const Duration kUnreadMinRetryAfter = Duration(seconds: 30);
const Duration kUnreadMaxRetryAfter = Duration(seconds: 3600);

@riverpod
Duration pollInterval(Ref ref) => kUnreadPollInterval;

/// Upper bound of the per-session poll jitter (production draws 0..this).
const Duration kUnreadPollJitterMax = Duration(seconds: 5);

/// Extra time added to every poll period so a fleet of clients that resumed
/// together does not hit `/notifications/unread-count` in lockstep. Defaults
/// to zero (tests stay exact); `main.dart` overrides it with a random
/// 0..[kUnreadPollJitterMax] draw for the running app.
@riverpod
Duration pollJitter(Ref ref) => Duration.zero;

@Riverpod(keepAlive: true)
class UnreadNotifications extends _$UnreadNotifications {
  Timer? _pollTimer;
  Timer? _backoffTimer;
  AppLifecycleListener? _lifecycle;
  Future<void>? _inFlight;
  int _inFlightVersion = 0;
  DateTime? _lastFetchAt;
  String? _userId;

  /// Last count emitted; survives a same-user rebuild (see [build]).
  int _count = 0;
  bool _foreground = true;
  bool _signedIn = false;

  /// Bumped on every rebuild so a fetch that outlives its session (logout /
  /// user switch) can never write into the new one.
  int _epoch = 0;

  /// Bumped by every optimistic mutation; a fetch started before a bump is
  /// stale and must not overwrite the mutated value.
  int _version = 0;

  @override
  FutureOr<int> build() {
    final String? userId = ref.watch(authProvider.select(authUserIdOrNull));
    final Duration interval = ref.watch(pollIntervalProvider);
    final int kept = (userId != null && userId == _userId) ? _count : 0;
    _epoch++;
    _inFlight = null;
    _lastFetchAt = null;
    _userId = userId;
    _pollTimer = null;
    _backoffTimer = null;
    _signedIn = userId != null;

    ref.onDispose(_teardown);

    _count = kept;
    if (userId == null) return 0;

    final AppLifecycleState? initial = WidgetsBinding.instance.lifecycleState;
    _foreground = initial == null || initial == AppLifecycleState.resumed;
    _lifecycle = AppLifecycleListener(
      onStateChange: (AppLifecycleState s) => _onLifecycle(s, interval),
    );
    if (_foreground) {
      _startPolling(interval);
      // Deferred: a provider must not mutate itself inside build().
      final int epoch = _epoch;
      Future<void>.microtask(() {
        if (ref.mounted && epoch == _epoch) unawaited(refresh());
      });
    }
    return kept;
  }

  /// Refetches the count. Concurrent calls share one request, unless an
  /// optimistic mutation happened since it started (then a fresh one is
  /// issued). No-op while signed out or suspended by a 429.
  Future<void> refresh() {
    if (!_signedIn || _backoffTimer != null) return Future<void>.value();
    final Future<void>? existing = _inFlight;
    if (existing != null && _inFlightVersion == _version) return existing;
    late final Future<void> request;
    request = _fetch().whenComplete(() {
      // A stale request must not clear a newer one (or a new session's).
      if (identical(_inFlight, request)) _inFlight = null;
    });
    _inFlight = request;
    _inFlightVersion = _version;
    return request;
  }

  /// Sets the count from a server response (mark-all-read → 0, feed page).
  /// [forUserId] is the user the caller captured when it issued the request;
  /// a late response for a previous user is dropped.
  void setCount(int count, {required String forUserId}) {
    if (!_signedIn || forUserId != _userId) return;
    _version++;
    _emit(count < 0 ? 0 : count);
  }

  /// Optimistic single mark-read. See [setCount] for [forUserId].
  void decrement({required String forUserId}) {
    if (!_signedIn || forUserId != _userId) return;
    _version++;
    _emit(_count > 0 ? _count - 1 : 0);
  }

  /// Undoes an optimistic [decrement] / [setCount] by DELTA, never by an
  /// absolute snapshot: a snapshot taken before two overlapping mutations
  /// would overwrite the one that succeeded. Guarded exactly like
  /// [decrement] (user id, `_version` bump).
  void increment({required String forUserId, int by = 1}) {
    if (!_signedIn || forUserId != _userId || by <= 0) return;
    _version++;
    _emit(_count + by);
  }

  void _emit(int count) {
    _count = count;
    state = AsyncData<int>(count);
  }

  Future<void> _fetch() async {
    final int epoch = _epoch;
    final int version = _version;
    try {
      final int count = await ref
          .read(notificationRepositoryProvider)
          .unreadCount();
      if (!ref.mounted || epoch != _epoch) return;
      // Stale: an optimistic mutation landed while this was in flight.
      if (version != _version) {
        // Reconcile now instead of waiting for the next tick. A normal
        // refresh: only a NEW mutation can make it stale again, so no loop.
        // Intentionally unawaited: an awaited refresh() must resolve before the reconcile completes.
        unawaited(refresh());
        return;
      }
      _lastFetchAt = ref.read(clockProvider)();
      _emit(count);
    } on NotificationsRateLimitedFailure catch (f) {
      if (!ref.mounted || epoch != _epoch) return;
      _suspendFor(f.retryAfterSeconds);
    } on Failure catch (f) {
      _markAttempt(epoch);
      // Keep the last value; the next tick retries.
      log(
        'unread count refresh failed: ${f.runtimeType}',
        name: 'feature.notifications.unread',
        level: 900,
      );
    } catch (e) {
      // Unexpected (non-Failure) error: never escape into an unawaited future.
      _markAttempt(epoch);
      log(
        'unread count refresh failed unexpectedly: ${e.runtimeType}',
        name: 'feature.notifications.unread',
        level: 900,
      );
    }
  }

  /// Records a completed-but-failed attempt so a failure streak does not
  /// refetch on every resume.
  void _markAttempt(int epoch) {
    if (!ref.mounted || epoch != _epoch) return;
    _lastFetchAt = ref.read(clockProvider)();
  }

  void _suspendFor(int? seconds) {
    _pollTimer?.cancel();
    _pollTimer = null;
    _backoffTimer?.cancel();
    final Duration wait = (seconds == null || seconds <= 0)
        ? kUnreadDefaultRetryAfter
        : Duration(
            seconds: seconds.clamp(
              kUnreadMinRetryAfter.inSeconds,
              kUnreadMaxRetryAfter.inSeconds,
            ),
          );
    final int epoch = _epoch;
    _backoffTimer = Timer(wait, () {
      if (!ref.mounted || epoch != _epoch) return;
      _backoffTimer = null;
      if (_foreground) {
        _startPolling(ref.read(pollIntervalProvider));
        unawaited(refresh());
      }
    });
  }

  void _onLifecycle(AppLifecycleState s, Duration interval) {
    if (!ref.mounted || !_signedIn) return;
    if (s == AppLifecycleState.resumed) {
      _foreground = true;
      if (_backoffTimer != null) return; // still suspended by a 429
      _startPolling(interval);
      final DateTime? last = _lastFetchAt;
      final DateTime now = ref.read(clockProvider)();
      // A backwards clock jump counts as "gap elapsed" (never suppress).
      if (last != null &&
          !now.isBefore(last) &&
          now.difference(last) < kUnreadResumeMinGap) {
        return; // resumed again moments after a completed fetch
      }
      unawaited(refresh());
    } else {
      _foreground = false;
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  void _startPolling(Duration interval) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      interval + ref.read(pollJitterProvider),
      (_) => unawaited(refresh()),
    );
  }

  void _teardown() {
    _pollTimer?.cancel();
    _backoffTimer?.cancel();
    _lifecycle?.dispose();
    _pollTimer = null;
    _backoffTimer = null;
    _lifecycle = null;
    _signedIn = false;
  }
}

/// The bell only needs the boolean.
@riverpod
bool hasUnreadNotifications(Ref ref) =>
    (ref.watch(unreadNotificationsProvider).value ?? 0) > 0;
