// Phase 363 — «Сповіщення»: the in-app notification feed.
//
// Ported from the approved preview `docs/signup-designs/NotificationsFeed/`
// with the user's compact-card change (2026-09-30): each row is the app's
// compact raised row (see `widgets/notification_tile.dart`), not the preview's
// 24 dp card.
//
// Layout, top to bottom:
//   VelvetTopBar  «Сповіщення»
//   mark-all strip (unread count + «Позначити всі як прочитані»; hidden at 0)
//   the feed: day headers («Сьогодні» / «Вчора» / «Пн, 28 вересня») + rows
//
// States, all explicit: loading skeleton, list, empty, error (+ 429 cooldown),
// and a list footer (spinner / 429 cooldown / retry).
//
// SCOPE: per user, global across every salon an owner owns. Nothing here reads
// an "active salon".
//
// A row tap marks the row read (optimistically) and does NOT navigate yet —
// phase 364 adds the per-role deep links. Opening the screen never auto-marks
// anything read.
//
// COST OF A ROW FLIP (phase 363 audit): marking one row read replaces the
// feed's `items` list, which rebuilds this screen. Everything derived from the
// list — the day-grouped entries, the key→index map, the unread-loaded count —
// is memoised on the list's IDENTITY ([_Layout]), and every row widget is
// cached per item instance ([_rows]). A flip replaces the list, so the layout
// is rebuilt: O(n) bookkeeping (grouping, key map, unread count) in plain Dart,
// but exactly ONE row widget is rebuilt — every other row gets the very same
// cached widget back and Flutter skips its subtree. (A cheaper incremental
// patch was considered and rejected: n is bounded by the loaded pages and the
// bookkeeping is allocation-light; a second code path would have to stay in
// lockstep with [_Layout.build].)
//
// DAY HEADERS: «today» is held in state and recomputed on app resume and by a
// single timer that fires at the next Kyiv midnight, so a screen left open
// across midnight relabels «Сьогодні» / «Вчора» without a reload.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/core/widgets/app_refresh_indicator.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/my_bookings_states.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:beautica_mobile/shared/widgets/services_empty_state.dart';
import 'package:beautica_mobile/shared/widgets/velvet_top_bar.dart';

import '../domain/app_notification.dart';
import '../domain/notifications_feed_state.dart';
import 'notification_copy.dart';
import 'notifications_feed_notifier.dart';
import 'unread_notifications_notifier.dart';
import 'widgets/notification_feed_parts.dart';
import 'widgets/notification_tile.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  static const Key backKey = Key('notifications-back');
  static const Key listKey = Key('notifications-list');
  static const Key emptyKey = Key('notifications-empty');

  /// Rows shown in the loading skeleton.
  static const int _skeletonRows = 6;

  /// The midnight timer never sleeps longer than this, so the very last slice
  /// before midnight is always measured on the same side of any DST change
  /// (Kyiv changes at 03:00 / 04:00, never inside the final hour of a day).
  static const Duration _maxMidnightSlice = Duration(hours: 1);

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen>
    with WidgetsBindingObserver {
  late DateTime _today;
  Timer? _midnight;
  _Layout? _layout;
  final Map<String, _CachedRow> _rows = <String, _CachedRow>{};

  /// The latest strings, captured in [didChangeDependencies] so the layout memo
  /// can be refreshed from a listener, outside `build`.
  AppLocalizations? _l10n;

  /// Whether a memoised layout is being retained (tests: a feed that is gone
  /// must not keep the previous list alive).
  @visibleForTesting
  bool get debugHasLayout => _layout != null;

  /// How many built rows are cached.
  @visibleForTesting
  int get debugCachedRowCount => _rows.length;

  @override
  void initState() {
    super.initState();
    _today = kyivToday(ref.read(clockProvider));
    WidgetsBinding.instance.addObserver(this);
    _armMidnight();
    // The layout memo is updated HERE (and on a locale / day change), never
    // inside `build`. A listener runs before the rebuild it schedules.
    ref.listenManual<AsyncValue<NotificationsFeedState>>(
      notificationsFeedProvider,
      (_, _) => _refreshLayout(),
    );
    ref.listenManual<String?>(
      authProvider.select(authUserIdOrNull),
      (_, _) => _refreshLayout(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _l10n = AppLocalizations.of(context);
    _refreshLayout();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnight?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncToday();
    } else {
      // A backgrounded app must not wake for a header that nobody can see;
      // resuming re-reads the day and re-arms.
      _midnight?.cancel();
      _midnight = null;
    }
  }

  /// Re-reads Kyiv «today» and re-arms the midnight timer.
  void _syncToday() {
    if (!mounted) return;
    final DateTime today = kyivToday(ref.read(clockProvider));
    if (today != _today) {
      setState(() {
        _today = today;
        _refreshLayout();
      });
    }
    _armMidnight();
  }

  /// One timer, to (at most an hour before) the next Kyiv midnight. Wall-clock
  /// arithmetic on the Kyiv time of day — no `add(Duration(days: 1))` — and it
  /// re-arms from the fresh clock every time it fires, so an early or late fire
  /// self-corrects.
  void _armMidnight() {
    _midnight?.cancel();
    _midnight = null;
    final AppLifecycleState? lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    final DateTime wall = toBeauticaTime(ref.read(clockProvider)());
    final Duration sinceMidnight = Duration(
      hours: wall.hour,
      minutes: wall.minute,
      seconds: wall.second,
      milliseconds: wall.millisecond,
    );
    Duration delay = const Duration(hours: 24) - sinceMidnight;
    if (delay > NotificationsScreen._maxMidnightSlice) {
      delay = NotificationsScreen._maxMidnightSlice;
    }
    if (delay < const Duration(seconds: 1)) delay = const Duration(seconds: 1);
    _midnight = Timer(delay, _syncToday);
  }

  void _onBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RouteNames.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<NotificationsFeedState> async = ref.watch(
      notificationsFeedProvider,
    );
    final String? me = ref.watch(authProvider.select(authUserIdOrNull));
    // Never gate on `value == null` to detect a reload: an invalidate retains
    // the previous value, which is exactly what keeps the list on screen. But a
    // value that belongs to ANOTHER user (a user switch keeps the old value
    // while the new first page loads) is treated as "nothing loaded yet".
    final NotificationsFeedState? loaded = async.value;
    final NotificationsFeedState? feed =
        loaded != null && loaded.ownerUserId == me ? loaded : null;
    // Only the integer matters here: a poll that returns the same count must
    // not rebuild the screen.
    final int globalUnread = ref.watch(
      unreadNotificationsProvider.select((AsyncValue<int> v) => v.value ?? 0),
    );
    // Read-only here: the memo itself is maintained by [_refreshLayout]. The
    // fallback is a PURE rebuild, used only if a listener has not run yet.
    final _Layout? layout = feed == null || feed.items.isEmpty
        ? null
        : _memoised(l10n, feed.items) ??
              _Layout.build(l10n, feed.items, _today);
    final int loadedUnread = layout?.unreadLoaded ?? 0;
    final int unread = globalUnread > loadedUnread
        ? globalUnread
        : loadedUnread;

    return Scaffold(
      backgroundColor: BrandColors.base,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            VelvetTopBar(
              title: l10n.notificationsScreenTitle,
              backKey: NotificationsScreen.backKey,
              backSemanticLabel: l10n.salonProfileBackLabel,
              onBack: _onBack,
            ),
            if (layout != null)
              NotificationsMarkAllBar(unread: unread, onMarkAll: _markAll),
            Expanded(child: _body(l10n, async, feed, layout)),
          ],
        ),
      ),
    );
  }

  Widget _body(
    AppLocalizations l10n,
    AsyncValue<NotificationsFeedState> async,
    NotificationsFeedState? feed,
    _Layout? layout,
  ) {
    if (feed == null) {
      if (async.hasError) {
        return MyBookingsErrorState(
          error: async.error!,
          onRetry: () => ref.invalidate(notificationsFeedProvider),
        );
      }
      return ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: kMyBookingsListPadding,
        children: <Widget>[
          BookingsSkeleton(
            count: NotificationsScreen._skeletonRows,
            semanticsLabel: l10n.notificationsLoadingSemantics,
            rowBuilder: (BuildContext context, int index) =>
                NotificationsSkeletonRow(index: index),
          ),
        ],
      );
    }
    if (layout == null) {
      return ServicesEmptyState(
        key: NotificationsScreen.emptyKey,
        iconWidget: const AppIcon(
          BeauticaAssetIcons.notificationPlain,
          size: 40,
          color: BrandColors.faint,
        ),
        title: l10n.notificationsEmptyTitle,
        body: l10n.notificationsEmptyBody,
      );
    }
    return _list(feed, layout);
  }

  Widget _list(NotificationsFeedState feed, _Layout layout) {
    final bool isClient =
        ref.watch(authProvider.select(authUserRoleOrNull)) == UserRole.client;
    final DateTime Function() clock = ref.watch(clockProvider);
    final NotificationsFeed notifier = ref.read(
      notificationsFeedProvider.notifier,
    );
    final List<_Entry> entries = layout.entries;
    final bool footer =
        feed.hasMore || feed.loadingMore || feed.loadMoreFailure != null;

    return AppRefreshIndicator(
      onRefresh: () => _refresh(notifier),
      child: CustomScrollView(
        key: NotificationsScreen.listKey,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          SliverPadding(
            padding: kMyBookingsListPadding,
            // A lazy sliver list: rows are built as they scroll into view, so
            // an unbounded number of pages never builds every row.
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (BuildContext context, int index) {
                  if (index >= entries.length) {
                    return NotificationsLoadMoreFooter(
                      feed: feed,
                      now: clock(),
                      onLoadMore: notifier.loadMore,
                      onRetry: notifier.retryLoadMore,
                    );
                  }
                  final _Entry entry = entries[index];
                  final AppNotification? item = entry.item;
                  if (item == null) {
                    return NotificationsDayHeader(
                      key: entry.key,
                      label: entry.label!,
                    );
                  }
                  return _rowFor(entry, item, isClient, notifier);
                },
                childCount: entries.length + (footer ? 1 : 0),
                findChildIndexCallback: (Key key) => layout.indexByKey[key],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The row widget for [item], built once per item INSTANCE. Returning the
  /// identical widget makes the framework skip the element, so a flip of one
  /// row rebuilds that row only.
  Widget _rowFor(
    _Entry entry,
    AppNotification item,
    bool isClient,
    NotificationsFeed notifier,
  ) {
    final _CachedRow? cached = _rows[item.id];
    if (cached != null &&
        identical(cached.item, item) &&
        cached.isClient == isClient) {
      return cached.widget;
    }
    final Widget widget = Padding(
      key: entry.key,
      padding: const EdgeInsets.only(bottom: VelvetSpacing.sm),
      child: NotificationTile(
        key: Key('notification-tile-${item.id}'),
        item: item,
        isClient: isClient,
        onOpen: () => _markRead(notifier, item.id),
        onMarkRead: () => _markRead(notifier, item.id),
      ),
    );
    _rows[item.id] = _CachedRow(item, isClient, widget);
    return widget;
  }

  /// The memoised layout when it still matches [items], the Kyiv day and the
  /// locale; `null` otherwise. Pure: never writes.
  _Layout? _memoised(AppLocalizations l10n, List<AppNotification> items) {
    final _Layout? current = _layout;
    if (current != null &&
        identical(current.items, items) &&
        current.today == _today &&
        current.localeName == l10n.localeName) {
      return current;
    }
    return null;
  }

  /// Re-derives the memo from the CURRENT feed. Runs from listeners,
  /// [didChangeDependencies] and the day rollover — never from `build`.
  ///
  /// A feed that is gone (null / empty / owned by another user, e.g. a user
  /// switch while the screen is open) clears BOTH the layout and the cached
  /// rows so the previous user's list is not retained.
  void _refreshLayout() {
    final AppLocalizations? l10n = _l10n;
    if (l10n == null) return;
    final NotificationsFeedState? loaded = ref
        .read(notificationsFeedProvider)
        .value;
    final String? me = authUserIdOrNull(ref.read(authProvider));
    final List<AppNotification>? items =
        loaded != null && loaded.ownerUserId == me ? loaded.items : null;
    if (items == null || items.isEmpty) {
      _layout = null;
      _rows.clear();
      return;
    }
    _layoutFor(l10n, items);
  }

  /// Everything derived from [items], rebuilt only when the list instance, the
  /// Kyiv day or the locale changes.
  _Layout _layoutFor(AppLocalizations l10n, List<AppNotification> items) {
    final _Layout? memo = _memoised(l10n, items);
    if (memo != null) return memo;
    final _Layout next = _Layout.build(l10n, items, _today);
    // Drop cached rows of items that are no longer loaded.
    final Set<String> ids = <String>{
      for (final AppNotification n in items) n.id,
    };
    _rows.removeWhere((String id, _CachedRow _) => !ids.contains(id));
    return _layout = next;
  }

  Future<void> _refresh(NotificationsFeed notifier) async {
    try {
      await notifier.refresh();
    } on Failure catch (f) {
      if (mounted) showErrorSnack(context, f.userMessage(context));
    }
  }

  Future<void> _markRead(NotificationsFeed notifier, String id) async {
    final String failed = AppLocalizations.of(
      context,
    ).notificationsMarkReadFailed;
    final bool ok = await notifier.markRead(id);
    if (!ok && mounted) showErrorSnack(context, failed);
  }

  Future<void> _markAll() async {
    final String failed = AppLocalizations.of(
      context,
    ).notificationsMarkAllReadFailed;
    final bool ok = await ref
        .read(notificationsFeedProvider.notifier)
        .markAllRead();
    if (!ok && mounted) showErrorSnack(context, failed);
  }
}

/// Memoised derivations of one `items` list (see the file header).
final class _Layout {
  _Layout._({
    required this.items,
    required this.today,
    required this.localeName,
    required this.entries,
    required this.indexByKey,
    required this.unreadLoaded,
  });

  /// Day headers interleaved with rows, newest first. A row's day is the
  /// EUROPE/KYIV day of its `createdAt`, never the device's.
  factory _Layout.build(
    AppLocalizations l10n,
    List<AppNotification> items,
    DateTime today,
  ) {
    final List<_Entry> entries = <_Entry>[];
    DateTime? group;
    int unread = 0;
    for (final AppNotification item in items) {
      if (!item.read) unread++;
      final DateTime day = kyivDayOf(item.createdAt);
      if (group != day) {
        group = day;
        entries.add(
          _Entry.header(
            key: ValueKey<String>('notifications-day-${day.toIso8601String()}'),
            label: NotificationCopy.dayHeader(l10n, day, today),
          ),
        );
      }
      entries.add(
        _Entry.row(
          key: ValueKey<String>('notification-row-${item.id}'),
          item: item,
        ),
      );
    }
    return _Layout._(
      items: items,
      today: today,
      localeName: l10n.localeName,
      entries: entries,
      indexByKey: <Key, int>{
        for (int i = 0; i < entries.length; i++) entries[i].key: i,
      },
      unreadLoaded: unread,
    );
  }

  final List<AppNotification> items;
  final DateTime today;
  final String localeName;
  final List<_Entry> entries;
  final Map<Key, int> indexByKey;
  final int unreadLoaded;
}

/// One row widget plus what it was built from.
final class _CachedRow {
  const _CachedRow(this.item, this.isClient, this.widget);

  final AppNotification item;
  final bool isClient;
  final Widget widget;
}

/// One slot of the flattened list: a day header or a row.
final class _Entry {
  const _Entry.header({required this.key, required String this.label})
    : item = null;
  const _Entry.row({required this.key, required AppNotification this.item})
    : label = null;

  final Key key;
  final String? label;
  final AppNotification? item;
}
