// Phase 14.3 — «МОЇ ЗАПИСИ», the Записи branch of the CLIENT shell.
//
// Ported from `docs/signup-designs/MyBookings/lib/screens/my_bookings_screen.dart`.
// Layout: the three-position soft-switch tab bar (Майбутні / Минулі /
// Скасовані) directly under the shell-owned top chrome, then a per-tab
// pull-to-refresh + infinite-scroll list. NO screen-owned top bar / back
// button — this is a client-shell BRANCH ROOT, and the shell already hosts
// the single top bar (wordmark · bell · burger) across every branch (see
// `client_shell.dart`'s file header on why that bar was hoisted out of the
// per-screen bodies); the preview's own back+title bar existed only because
// it is a standalone app with no shell to sit inside.
//
// Each tab is backed by its own `myBookingsProvider(tab)` — a paginated
// `AsyncNotifier` fanning one fetch per status the tab covers (see
// `my_bookings_notifier.dart`'s file header for why: `GET /bookings/me`
// takes only ONE status filter, but Минулі and Скасовані each cover two).
//
// SEC: bookings are PII (who you see, when, where, what you paid, plus
// free-text notes) — this screen acquires the app-wide
// [ScreenProtectionManager] for its lifetime, mirroring the
// acquire-in-`initState`/release-in-`dispose` pattern every other PII screen
// in this app uses (`HomeHubScreen`, `PassportScreen`, `PublicMasterProfileScreen`,
// …). Closes the mobile-backlog "client_shell has no FLAG_SECURE" row's THIRD
// and final trigger (14.3, after 13.7/13.8) — see that row for the other two.
// That row's NAME is now historical: FLAG_SECURE was removed app-wide on
// 2026-08-20 by product decision (screenshots are allowed). The acquire here
// still stands, but what it buys is the iOS app-switcher blur and the shared
// reference count — see the header of `lib/core/security/screen_protection.dart`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/routing/route_names.dart';

import '../application/my_bookings_notifier.dart';
import '../domain/booking.dart';
import '../domain/booking_tab.dart';
import 'widgets/booking_card.dart';
import 'widgets/bookings_empty_state.dart';
import 'widgets/bookings_tab_bar.dart';
import 'widgets/my_bookings_states.dart';

/// The client's bookings list — the Записи tab of the client shell.
class MyBookingsScreen extends ConsumerStatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  ConsumerState<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends ConsumerState<MyBookingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Derived from `_tabController.index`, updated ONLY when the index flips (not
  // per animation frame). Drives the tab bar's active-state rebuild off the
  // once-per-settle index change instead of the every-frame controller
  // animation — the tab bar's own AnimatedAlign still renders the slide.
  late final ValueNotifier<int> _activeIndex;

  // Captured in initState so dispose() never touches `ref` (Riverpod 3.x
  // throws on a post-dispose `ref` read).
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: BookingTab.values.length,
      vsync: this,
    );
    _activeIndex = ValueNotifier<int>(_tabController.index);
    _tabController.addListener(_syncActiveIndex);
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  void _syncActiveIndex() {
    if (_activeIndex.value != _tabController.index) {
      _activeIndex.value = _tabController.index;
    }
  }

  @override
  void dispose() {
    _screenProtection.release();
    _tabController.removeListener(_syncActiveIndex);
    _activeIndex.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _openDetails(String bookingId) {
    context.push(RouteNames.bookingDetail(bookingId));
  }

  void _onFindMaster() => context.go(RouteNames.clientSearch);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('client-branch-bookings'),
      backgroundColor: BrandColors.base,
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              VelvetSpacing.lg,
              VelvetSpacing.lg,
              VelvetSpacing.lg,
              VelvetSpacing.sm,
            ),
            child: ValueListenableBuilder<int>(
              valueListenable: _activeIndex,
              builder: (BuildContext context, int index, Widget? child) {
                return MyBookingsTabBar(
                  active: BookingTab.values[index],
                  onChanged: (BookingTab tab) {
                    _tabController.animateTo(BookingTab.values.indexOf(tab));
                  },
                );
              },
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: <Widget>[
                for (final BookingTab tab in BookingTab.values)
                  _BookingsTabView(
                    key: PageStorageKey<BookingTab>(tab),
                    tab: tab,
                    onOpenDetails: _openDetails,
                    onFindMaster: _onFindMaster,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One tab's pull-to-refresh + infinite-scroll list.
class _BookingsTabView extends ConsumerStatefulWidget {
  const _BookingsTabView({
    super.key,
    required this.tab,
    required this.onOpenDetails,
    required this.onFindMaster,
  });

  final BookingTab tab;
  final void Function(String bookingId) onOpenDetails;
  final VoidCallback onFindMaster;

  @override
  ConsumerState<_BookingsTabView> createState() => _BookingsTabViewState();
}

class _BookingsTabViewState extends ConsumerState<_BookingsTabView> {
  /// Pixels-from-bottom threshold that triggers the next-page fetch.
  static const double _loadMoreThreshold = 320;

  final ScrollController _scrollController = ScrollController();

  // Cheap scroll-listener guards, refreshed from the watched provider each
  // build — mirrors `search_results_screen.dart`'s identical idiom.
  bool _hasMore = false;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _isLoadingMore) return;
    if (!_scrollController.hasClients) return;
    final ScrollPosition pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - _loadMoreThreshold) {
      // The notifier itself guards against double-fetch + last-page no-op.
      ref.read(myBookingsProvider(widget.tab).notifier).loadMore();
    }
  }

  Future<void> _refresh() =>
      ref.read(myBookingsProvider(widget.tab).notifier).refresh();

  @override
  Widget build(BuildContext context) {
    final AsyncValue<MyBookingsState> async = ref.watch(
      myBookingsProvider(widget.tab),
    );
    final MyBookingsState? data = async.value;
    _hasMore = data?.hasMore ?? false;
    _isLoadingMore = data?.isLoadingMore ?? false;

    return RefreshIndicator(
      onRefresh: _refresh,
      color: BrandColors.accentDeep,
      backgroundColor: BrandColors.base,
      child: async.when(
        loading: () => ListView(
          key: const Key('my-bookings-skeleton'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: kMyBookingsListPadding,
          children: const <Widget>[BookingsSkeleton()],
        ),
        error: (Object e, StackTrace _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: kMyBookingsListPadding,
          children: <Widget>[
            MyBookingsErrorState(
              error: e,
              onRetry: () => ref.invalidate(myBookingsProvider(widget.tab)),
            ),
          ],
        ),
        data: (MyBookingsState state) {
          if (state.items.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: kMyBookingsListPadding,
              children: <Widget>[
                BookingsEmptyState(
                  onFindMaster: widget.tab == BookingTab.upcoming
                      ? widget.onFindMaster
                      : null,
                ),
              ],
            );
          }
          // One card per service — a multi-service visit's rows share an
          // `appointmentId`, but that carries no rendering weight here: each
          // row is its own ordinary `BookingCard`, acting on its own booking.
          // `GET /bookings/me` already returns the tab's whole status set
          // sorted by `startAt` server-side (see `MyBookingsNotifier`'s file
          // header), so a visit's legs land in their natural chronological
          // position among any other bookings with no client-side re-sort.
          final List<Booking> items = state.items;
          final int extra = state.hasMore ? 1 : 0;
          return ListView.separated(
            key: ValueKey<String>('my-bookings-list-${widget.tab.name}'),
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: kMyBookingsListPadding,
            itemCount: items.length + extra,
            separatorBuilder: (BuildContext context, int i) =>
                const SizedBox(height: VelvetSpacing.md),
            itemBuilder: (BuildContext context, int i) {
              if (i >= items.length) {
                return const MyBookingsLoadMoreSpinner();
              }
              final Booking booking = items[i];
              return RepaintBoundary(
                key: ValueKey<String>(booking.id),
                child: BookingCard(
                  booking: booking,
                  onOpenDetails: () => widget.onOpenDetails(booking.id),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
