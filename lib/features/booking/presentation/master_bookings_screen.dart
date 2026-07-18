// Phase 7.6 — «Мої записи» for the independent master.
//
// Composition transcribed from `docs/signup-designs/SalonManagementDesign/`
// (`screens/my_bookings_screen.dart` → `widgets/bookings_toolbar.dart`'s
// `BookingsDiscoveryScreen`), with the preview's two sanctioned substitutions:
// the in-memory `List<DemoBooking>` becomes the Phase 7.1 providers, and
// `showMasterFilter: false` drops the teammate filter entirely (a single
// master's own list never offers it).
//
// ## The server owns filtering, ordering and paging — this screen owns NONE
//
// The preview's `_visible` getter and its `sort()` (`bookings_toolbar.dart:
// 315-347`) are NOT ported. They exist because the preview has no server.
// Phase 7.1 moved every one of them onto `MasterBookingsQuery`, and porting
// them back would be actively wrong: re-sorting only the rows paged in SO FAR
// reshuffles already-viewed rows on every load-more. There is no comparator
// and no `.where()` over `items` anywhere in this file. The list is rendered
// in server order, verbatim.
//
// ## ONE date field, not a `_day` + a `_range`
//
// The preview holds `DateTime? _day` and `DateTimeRange? _range` as two
// independent fields and reconciles them at four call sites
// (`selectedDay: _range == null ? _day : null`, `_range = null` on a chip tap,
// …). That is how they get out of sync. Here there is exactly one source of
// truth — `_query.from`/`_query.to` — and the rail's single-day selection is
// simply the case where `from == to`. A range supersedes a day for free,
// because there is nothing to supersede.
//
// ## The list is a CARD LIST, not the preview's `_TimelineGrid`
//
// This is the one deliberate divergence from the approved preview, and it is
// forced by the data layer rather than chosen. See `_BookingsList`'s doc.
//
// ## Phase 7.7 — filter and the range calendar
//
// Filled in exactly at the seams Phase 7.6 left: `_openCalendar` and
// `_applyFilters`, plus the header's trailing slot. Nothing structural changed
// — both still resolve to ONE new `MasterBookingsQuery` handed to `_setQuery`,
// and the two `Consumer`s below are untouched.
//
// The sheets are pure widgets that RESOLVE with a value; neither touches a
// provider. That is what keeps `_setQuery` the single mutation path (see its
// doc for what a bypass costs) and what lets the filter sheet be tested
// without a provider container.
//
// ## Phase 7.8 — sorting retired
//
// The sort button, its sheet and `_applySort` are gone, and
// `MasterBookingsQuery` no longer carries a `sort`. The ordering is now fixed
// in `MasterBookingsNotifier`. The approved design never shipped a sort sheet
// — the four sorts came from the phase docs — and Phase 7.9 replaces this
// body with the design's timeline grid, where a card's POSITION is its time
// and no ordering could move it.
//
// SEC: this screen renders client names and, through the detail it pushes,
// free-text notes — a heavier PII surface than the client-side «Мої записи».
// It acquires the app-wide `ScreenProtectionManager` for its lifetime,
// mirroring `my_bookings_screen.dart`, `HomeHubScreen`, `PassportScreen` and
// `BookingConfirmScreen`.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';

import '../application/booked_days_notifier.dart';
import '../application/master_bookings_notifier.dart';
import 'package:beautica_mobile/features/services/data/master_service_catalog_provider.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';

import '../domain/booking.dart';
import '../domain/master_bookings_query.dart';
import '../domain/master_bookings_state.dart';
import 'widgets/bookings_day_rail.dart';
import 'widgets/bookings_filter_sheet.dart';
import 'widgets/date_range_calendar.dart';
import 'widgets/master_booking_card.dart';
import 'widgets/master_bookings_states.dart';
import 'widgets/my_bookings_states.dart';

/// How close to the end of the list the prefetch fires — roughly a screenful,
/// so the next page has usually landed by the time the master reaches it.
const double _prefetchThreshold = 400;

/// Vertical gap between two booking cards. Was `ListView.separated`'s
/// separator; now leading padding on every row but the first (see
/// [_BookingsList]).
const double _cardGap = VelvetSpacing.sm + 2;

/// The independent master's own booking list.
class MasterBookingsScreen extends ConsumerStatefulWidget {
  const MasterBookingsScreen({super.key});

  @override
  ConsumerState<MasterBookingsScreen> createState() =>
      _MasterBookingsScreenState();
}

class _MasterBookingsScreenState extends ConsumerState<MasterBookingsScreen> {
  /// The single source of truth for every server-side filter.
  /// Always built through `MasterBookingsQuery.of` — never `.raw`, which skips
  /// the date normalisation that keeps the provider family bounded (guarded by
  /// `scripts/forbid_raw_bookings_query.sh`).
  MasterBookingsQuery _query = MasterBookingsQuery.of();

  final ScrollController _railController = ScrollController();
  final ScrollController _listController = ScrollController();

  late final DateTime _today;
  late final DateTime _railFirstDay;

  /// Debounces day-chip taps. A scroll-fling across the rail can land a dozen
  /// taps in under a second, and each one is a new family member and a new
  /// request; without this the flick costs 40 round trips.
  Timer? _dayDebounce;

  /// Guards `_centreRailOnNearestBooking` so the rail auto-centres exactly
  /// once, on first arrival. Without it, every `bookedDaysProvider` refresh
  /// (or a return from the detail screen inside the 30-minute TTL) would yank
  /// the rail back under the master's thumb mid-scroll.
  bool _didAutoCentre = false;

  // Captured in initState so dispose() never touches `ref` (Riverpod 3.x
  // throws on a post-dispose `ref` read).
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    _today = dateOnly(DateTime.now());
    // CALENDAR arithmetic — `subtract(Duration(days: n))` would land on 23:00
    // or 01:00 across a Europe/Kyiv DST transition and skew every rail date
    // derived from it. See `bookings_day_rail.dart`'s header.
    _railFirstDay = railDayAt(_today, -kBookedDaysSpanDays);
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
    _listController.addListener(_onListScroll);
  }

  @override
  void dispose() {
    _dayDebounce?.cancel();
    _screenProtection.release();
    _listController.removeListener(_onListScroll);
    _listController.dispose();
    _railController.dispose();
    super.dispose();
  }

  // ── Rail scrolling ──────────────────────────────────────────────────────

  /// Scrolls the rail so [day] sits in the middle of the viewport.
  ///
  /// Ported from the design's `_centreRailOn`. Must run AFTER first layout —
  /// `position.viewportDimension` is 0 before it, so a pre-layout call
  /// computes a nonsense target and silently no-ops.
  void _centreRailOn(DateTime day, {bool animated = false}) {
    if (!_railController.hasClients) return;
    final ScrollPosition position = _railController.position;
    if (position.viewportDimension <= 0) return;

    final int dayIndex = dateOnly(day).difference(_railFirstDay).inDays;
    // `[calendar][Всі]` lead the rail — this offset is why the centring lands
    // on the right cell. See `kRailLeadItems`.
    final int itemIndex = kRailLeadItems + dayIndex;
    final double target =
        itemIndex * kRailItemExtent -
        position.viewportDimension / 2 +
        kRailItemExtent / 2;
    final double clamped = target.clamp(0.0, position.maxScrollExtent);

    if (animated) {
      _railController.animateTo(
        clamped,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
    } else {
      _railController.jumpTo(clamped);
    }
  }

  /// Opens the rail centred on the nearest BOOKED day — the design's "open on
  /// content" behaviour — falling back to TODAY when the master has none.
  ///
  /// Deliberately not centred on today unconditionally: a master whose next
  /// appointment is three weeks out would open on an empty stretch of rail and
  /// have to scroll to find their own work.
  ///
  /// The today fallback is not a formality. The rail's first cell is
  /// `today − 180 days`, so scroll offset 0 is SIX MONTHS AGO — a master with
  /// no bookings (or whose booked-days fetch failed) would otherwise open the
  /// screen looking at last January. Gating the auto-centre on a non-empty set
  /// is what caused exactly that, so this runs as soon as the provider
  /// RESOLVES, empty or not.
  void _centreRailOnOpen(Set<DateTime> bookedDays) {
    if (_didAutoCentre) return;
    _didAutoCentre = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _centreRailOn(_nearestBookedDay(bookedDays) ?? _today);
    });
  }

  /// The first booked day that is not in the past; else the most recent past
  /// one; else `null`.
  DateTime? _nearestBookedDay(Set<DateTime> bookedDays) {
    if (bookedDays.isEmpty) return null;
    final List<DateTime> sorted = bookedDays.toList()..sort();
    for (final DateTime d in sorted) {
      if (!d.isBefore(_today)) return d;
    }
    return sorted.last;
  }

  // ── Query mutation ──────────────────────────────────────────────────────

  /// Swaps in a new query. Always goes through here so the prefetch latch is
  /// re-armed: the new query renders a DIFFERENT (usually shorter) list, and a
  /// latch left `true` from the old one would suppress the first legitimate
  /// `loadMore` on the new one.
  void _setQuery(MasterBookingsQuery next) {
    setState(() {
      _query = next;
      _nearEnd = false;
    });
  }

  /// Selecting a rail day narrows to exactly that day — `from == to` — and
  /// therefore clears any active range for free (there is only one date field
  /// to set). Debounced; see [_dayDebounce].
  void _selectDay(DateTime day) {
    _dayDebounce?.cancel();
    _dayDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      _setQuery(
        MasterBookingsQuery.of(
          statuses: _query.statuses.toSet(),
          serviceIds: _query.serviceIds.toSet(),
          from: day,
          to: day,
        ),
      );
    });
  }

  /// «Всі» — clears the date narrowing only, keeping status/service filters.
  /// It is a DATE control, not a reset-everything button.
  void _selectAllDays() {
    _dayDebounce?.cancel();
    _setQuery(
      MasterBookingsQuery.of(
        statuses: _query.statuses.toSet(),
        serviceIds: _query.serviceIds.toSet(),
      ),
    );
  }

  /// The «Скинути фільтри» escape hatch on the filter-empty state — clears
  /// every filter, returning the query to its landing state.
  void _clearAllFilters() {
    _dayDebounce?.cancel();
    _setQuery(MasterBookingsQuery.of());
    _centreRailOn(_today, animated: true);
  }

  /// Opens the single/range calendar and narrows the DATE bounds to whatever
  /// comes back.
  ///
  /// A range SUPERSEDES the rail's single-day selection for free, because
  /// there is only one date field to write — see the file header. Dismissing
  /// the picker resolves `null` and changes nothing; it is not a clear.
  Future<void> _openCalendar() async {
    _dayDebounce?.cancel();
    final DateTime? from = _query.from;
    final DateTime? to = _query.to;
    final DateTimeRange? picked = await showBookingsDateRangePicker(
      context,
      today: _today,
      initialRange: (from == null || to == null)
          ? null
          : DateTimeRange(start: from, end: to),
    );
    if (!mounted || picked == null) return;
    final ({DateTime from, DateTime to}) bounds = normaliseBookingRange(picked);
    _setQuery(
      MasterBookingsQuery.of(
        statuses: _query.statuses.toSet(),
        serviceIds: _query.serviceIds.toSet(),
        from: bounds.from,
        to: bounds.to,
      ),
    );
  }

  /// Opens the filter sheet and applies whatever it resolves with.
  ///
  /// The sheet holds DRAFT state and resolves exactly once, on «Застосувати» —
  /// so this fires one query change for one user decision, not one per
  /// checkbox. Dismissing resolves `null` and leaves the query untouched.
  Future<void> _applyFilters() async {
    _dayDebounce?.cancel();
    // `asData?.value`, NEVER `.value`.
    //
    // SEC: `AsyncValue.value` returns RETAINED previous data in `AsyncLoading`
    // AND `AsyncError`, not only in `AsyncData`. `logout()` deliberately does
    // not invalidate feature providers (cycle avoidance —
    // `auth_notifier.dart`), so this provider is re-run by the repository swap
    // and lands in `AsyncError(UnauthorizedFailure)` still holding the PREVIOUS
    // master's catalogue. On a shared device the next master would then see
    // account A's service names in their own filter sheet — and durably so, for
    // the whole session, if B's own refetch also fails (offline / 5xx).
    // `asData` is null in both non-data states regardless of what is retained.
    //
    // Degrading to an empty list is correct here: the sheet omits the whole
    // «Послуга» section rather than rendering an empty one.
    final List<MasterService> services =
        ref.read(masterServiceCatalogProvider).asData?.value ??
        const <MasterService>[];
    final BookingsFilterSelection? applied = await BookingsFilterSheet.show(
      context,
      initial: BookingsFilterSelection(
        statuses: _query.statuses.toSet(),
        serviceIds: _query.serviceIds.toSet(),
        from: _query.from,
        to: _query.to,
      ),
      services: services,
      onPickDates: (BuildContext sheetContext, DateTimeRange? current) =>
          showBookingsDateRangePicker(
            sheetContext,
            today: _today,
            initialRange: current,
          ),
    );
    if (!mounted || applied == null) return;
    _setQuery(
      MasterBookingsQuery.of(
        statuses: applied.statuses,
        serviceIds: applied.serviceIds,
        from: applied.from,
        to: applied.to,
      ),
    );
  }

  /// The count the header badge shows — ACTIVE FILTER GROUPS.
  ///
  /// Counted off `_query`'s already-canonical lists via the SAME
  /// [bookingsActiveFilterCount] the sheet's own `activeCount` uses, so the two
  /// can never disagree about what "active" means. It previously built a
  /// throwaway [BookingsFilterSelection], which copied both collections into
  /// fresh `Set`s (`serviceIds` up to 50) on every screen `build()` — an
  /// allocation per frame to answer a question three `isNotEmpty` reads already
  /// answer (perf P8).
  int get _activeFilterCount => bookingsActiveFilterCount(
    hasStatuses: _query.statuses.isNotEmpty,
    hasServiceIds: _query.serviceIds.isNotEmpty,
    hasDates: _query.from != null || _query.to != null,
  );

  // ── Infinite scroll ─────────────────────────────────────────────────────

  /// Whether the list is currently inside the prefetch zone. Latches the
  /// threshold so `loadMore` fires on the CROSSING, not on every frame spent
  /// past it (perf P2).
  bool _nearEnd = false;

  void _onListScroll() {
    if (!_listController.hasClients) return;
    final ScrollPosition p = _listController.position;
    // Prefetch a screenful early so the next page is usually already there by
    // the time the master reaches the end.
    final bool nearEnd = p.pixels >= p.maxScrollExtent - _prefetchThreshold;

    if (!nearEnd) {
      // Retreated out of the zone — re-arm. This is what makes the latch
      // correct rather than a one-shot: the zone is re-entered on every page,
      // because each appended page pushes `maxScrollExtent` back out.
      _nearEnd = false;
      return;
    }
    if (_nearEnd) return; // already inside the zone; already asked once
    _nearEnd = true;

    // `loadMore` is itself a no-op when a fetch is in flight, when there is no
    // data yet, or when the stream is exhausted — so this stays CORRECT
    // without the latch. The latch is about cost, not correctness: firing per
    // scroll frame allocated a `Future` and did a provider-container lookup on
    // the hot path every frame, which at 120Hz is 120 of each per second for
    // the whole time the master rests near the end of the list.
    unawaited(ref.read(masterBookingsProvider(_query).notifier).loadMore());
  }

  void _openDetail(String bookingId) {
    // `context.push`, never `context.go` — the detail must pop back onto the
    // still-scrolled list. (And note the go_router gotcha: this push yields an
    // `ImperativeRouteMatch` that is dropped from
    // `currentConfiguration.fullPath`, so nav-detection reads the PARENT
    // path — see `RouteNames.masterBookingDetail`.)
    context.push(RouteNames.masterBookingDetail(bookingId));
  }

  // ── Build ───────────────────────────────────────────────────────────────
  //
  // Perf P1 — NEITHER provider is watched at screen scope. `_Header` and
  // `BookingsDayRail` read nothing from `masterBookingsProvider`, but watching
  // it here rebuilt both on every list emission; during a paginating fling
  // that is TWICE per page (`isLoadingMore` false→true→false), each time
  // re-running the rail's `itemBuilder` for its whole visible window. The two
  // providers now sit in the two `Consumer`s that actually consume them, so a
  // list emission rebuilds only the list and a booked-days emission rebuilds
  // only the rail.

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    // A range is active when the two bounds differ; a single rail day is the
    // `from == to` case. One field, no reconciliation. See the file header.
    final bool rangeActive =
        _query.from != null && _query.to != null && _query.from != _query.to;
    final DateTime? selectedDay = rangeActive ? null : _query.from;

    return Scaffold(
      key: const Key('master-bookings-screen'),
      backgroundColor: BrandColors.base,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Header(
              title: l10n.masterBookingsTitle,
              activeFilterCount: _activeFilterCount,
              onOpenFilters: _applyFilters,
            ),
            const _ServiceCatalogueWarmer(),
            const SizedBox(height: VelvetSpacing.sm),
            Consumer(
              builder: (BuildContext context, WidgetRef ref, Widget? _) {
                // Filter-INDEPENDENT by design — the dots describe where the
                // master's work is, not what the current filter matches, so
                // they must not evaporate as the user narrows.
                // `bookedDaysProvider` takes no query for exactly this reason;
                // see `booked_days_notifier.dart`.
                final AsyncValue<Set<DateTime>> bookedDaysAsync = ref.watch(
                  bookedDaysProvider,
                );
                final Set<DateTime> bookedDays =
                    bookedDaysAsync.value ?? const <DateTime>{};

                // Centre once the set has RESOLVED — `hasValue`, not
                // `isNotEmpty`. An empty resolution is a real answer ("no
                // bookings"), and it must still move the rail off its
                // `today − 180` origin. Note `hasValue` also covers the
                // seamless-reload case where a refresh retains the previous
                // value.
                if (bookedDaysAsync.hasValue) {
                  _centreRailOnOpen(bookedDays);
                } else if (bookedDaysAsync.hasError) {
                  // The dots are a navigational hint, not a correctness gate —
                  // a failed booked-days fetch must not strand the rail in the
                  // far past.
                  _centreRailOnOpen(const <DateTime>{});
                }

                return BookingsDayRail(
                  controller: _railController,
                  firstDay: _railFirstDay,
                  dayCount: kBookedDaysSpanDays * 2 + 1,
                  today: _today,
                  selectedDay: selectedDay,
                  bookedDays: bookedDays,
                  calendarActive: rangeActive,
                  onOpenCalendar: _openCalendar,
                  onSelectAll: _selectAllDays,
                  onSelectDay: _selectDay,
                );
              },
            ),
            const SizedBox(height: VelvetSpacing.sm),
            Expanded(
              child: Consumer(
                builder: (BuildContext context, WidgetRef ref, Widget? _) {
                  final AsyncValue<MasterBookingsState> async = ref.watch(
                    masterBookingsProvider(_query),
                  );
                  return async.when(
                    // Both the skeleton and the error state are bare, unscrolled
                    // `Column`s — the shipped client screen hosts them inside a
                    // `ListView` for exactly this reason, and dropping either
                    // straight into an `Expanded` overflows the remaining height
                    // (the Phase 17.2 guard catches it as a transient
                    // first-frame RenderFlex overflow). The scroll view also keeps
                    // the states usable at large text scales and on short devices.
                    loading: () => ListView(
                      key: const Key('master-bookings-skeleton'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        VelvetSpacing.lg,
                        0,
                        VelvetSpacing.lg,
                        VelvetSpacing.xxl,
                      ),
                      children: const <Widget>[BookingsSkeleton()],
                    ),
                    error: (Object e, StackTrace _) => ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        VelvetSpacing.lg,
                        0,
                        VelvetSpacing.lg,
                        VelvetSpacing.xxl,
                      ),
                      children: <Widget>[
                        MyBookingsErrorState(
                          error: e,
                          onRetry: () =>
                              ref.invalidate(masterBookingsProvider(_query)),
                        ),
                      ],
                    ),
                    data: (MasterBookingsState state) => _Loaded(
                      state: state,
                      hasFilters: _query.hasFilters,
                      controller: _listController,
                      onClearFilters: _clearAllFilters,
                      onOpenDetail: _openDetail,
                      onRefresh: () => ref
                          .read(masterBookingsProvider(_query).notifier)
                          .refresh(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A zero-height subscription that keeps the «Послуга» option universe WARM.
///
/// ## Why a widget rather than a `ref.read` in `initState`
///
/// `masterServiceCatalogProvider` is `keepAlive` and lazy, and `_applyFilters`
/// only ever `ref.read`s it — so it needs someone to have STARTED it before the
/// sheet opens, or the first open of every session finds `AsyncLoading` and
/// silently renders no «Послуга» section.
///
/// A one-shot `ref.read` in `initState` starts it, but only ONCE. It does not
/// subscribe, and an unsubscribed `keepAlive` provider does not rebuild when it
/// is invalidated — Riverpod drops the state and defers the refetch to the next
/// read. So after a service create/edit/delete (Phase 7.7 audit S2, which added
/// exactly that invalidation) the next sheet open would kick the fetch off and
/// then read `AsyncLoading` in the same turn, showing NO services at all. That
/// is strictly worse than the stale list the invalidation was added to fix.
///
/// Watching keeps the provider subscribed, so an invalidation refetches
/// immediately and the result is in place by the time the master reaches the
/// sheet.
///
/// ## …and why it is not a `ref.watch` at screen scope
///
/// Perf P1 (Phase 7.6): watching anything in `build` rebuilds the header AND
/// the rail on every emission, which is exactly what the two `Consumer`s below
/// exist to prevent. Isolating the subscription in its own leaf means an
/// emission rebuilds a `SizedBox.shrink()` and nothing else.
///
/// Deliberately renders zero height rather than being conditional on the async
/// state — a widget that came and went would relayout the column.
class _ServiceCatalogueWarmer extends ConsumerWidget {
  const _ServiceCatalogueWarmer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(masterServiceCatalogProvider);
    return const SizedBox.shrink();
  }
}

/// The loaded body — the count line, then the list or one of the two empties.
class _Loaded extends StatelessWidget {
  const _Loaded({
    required this.state,
    required this.hasFilters,
    required this.controller,
    required this.onClearFilters,
    required this.onOpenDetail,
    required this.onRefresh,
  });

  final MasterBookingsState state;
  final bool hasFilters;
  final ScrollController controller;
  final VoidCallback onClearFilters;
  final ValueChanged<String> onOpenDetail;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    if (state.isEmpty) {
      // The two empties are genuinely different situations — see
      // `master_bookings_states.dart`'s header. `hasFilters` is the whole
      // distinction: with no filter active, an empty result means the master
      // has no bookings; with one, it means this filter matches none.
      return RefreshIndicator(
        onRefresh: onRefresh,
        color: BrandColors.accentDeep,
        child: ListView(
          // AlwaysScrollable so pull-to-refresh still works on a short
          // (non-overflowing) empty state — otherwise the gesture is dead on
          // exactly the screen where the master most wants to retry.
          physics: const AlwaysScrollableScrollPhysics(),
          children: <Widget>[
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.6,
              child: hasFilters
                  ? MasterBookingsNoResultsState(onClearFilters: onClearFilters)
                  : const MasterBookingsEmptyState(),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: BrandColors.accentDeep,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              VelvetSpacing.lg,
              0,
              VelvetSpacing.lg,
              VelvetSpacing.sm,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    // `totalElements`, NOT `items.length` — the count must
                    // describe the whole filtered result set, not merely the
                    // pages fetched so far.
                    l10n.masterBookingsCount(state.totalElements),
                    key: const Key('master-bookings-count'),
                    style: VelvetText.label(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _BookingsList(
              state: state,
              controller: controller,
              onOpenDetail: onOpenDetail,
            ),
          ),
        ],
      ),
    );
  }
}

/// The paged card list.
///
/// ## Why this is a card list and not the preview's `_TimelineGrid`
///
/// The approved preview renders the loaded body as `_TimelineGrid`
/// (`bookings_toolbar.dart:1336`) — a Google-Calendar-style day grid whose
/// cards are absolutely positioned by start time into greedy non-overlapping
/// lanes. It is transcribed here as a vertical list instead, for two reasons
/// that both still hold as of Phase 7.8:
///
///   1. **It cannot be paginated.** Absolute positioning needs `firstHour` and
///      `latestEnd` across the WHOLE set; page 2 arriving can change both and
///      relayout every card already on screen. The preview gets away with it
///      because its list is in memory and complete.
///   2. **It is single-day by construction.** The preview opens with a day
///      pre-selected, so its grid holds one day. Under «Всі» or a range it
///      stacks bookings from different days on the same hour rows — visible in
///      the preview as a latent bug, and this screen's default view is not
///      day-scoped.
///
/// A third reason — "a timeline cannot express a price sort" — was retired
/// with sorting itself in Phase 7.8, and its disappearance is what unblocks
/// the grid.
///
/// **Phase 7.9 resolves both remaining reasons and replaces this widget**: it
/// swaps `MasterBookingsQuery` for a day-scoped `BookingsDayQuery` with its own
/// unpaged fetch, which is exactly the "explicit day selection" this divergence
/// was always waiting on.
///
/// The design's `BookingCard` visual language is preserved verbatim (see
/// `master_booking_card.dart`); it is the CONTAINER that differs.
class _BookingsList extends StatelessWidget {
  const _BookingsList({
    required this.state,
    required this.controller,
    required this.onOpenDetail,
  });

  final MasterBookingsState state;
  final ScrollController controller;
  final ValueChanged<String> onOpenDetail;

  @override
  Widget build(BuildContext context) {
    // +1 slot for the load-more spinner when a page is in flight.
    final int extra = state.isLoadingMore ? 1 : 0;

    // `ListView.builder` with an inline leading gap, NOT `ListView.separated`
    // (perf P5). `.separated` doubles the child count — it interleaves a
    // separate element per row and drives both through one delegate — so an
    // unbounded paginating list pays an extra element, key and RenderObject
    // per booking. That is immaterial at one page and measurable past a few
    // hundred rows, which this list reaches by construction. The gap is
    // rendered as leading padding on every row but the first, which is
    // visually identical to a separator between rows.
    return ListView.builder(
      key: const Key('master-bookings-list'),
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        0,
        VelvetSpacing.lg,
        VelvetSpacing.xxl,
      ),
      itemCount: state.items.length + extra,
      itemBuilder: (BuildContext context, int index) {
        final Widget child;
        if (index >= state.items.length) {
          child = const MyBookingsLoadMoreSpinner();
        } else {
          // Rendered in SERVER order, verbatim — no comparator anywhere. See
          // the file header.
          final Booking booking = state.items[index];
          child = MasterBookingCard(
            booking: booking,
            onTap: () => onOpenDetail(booking.id),
          );
        }
        if (index == 0) return child;
        return Padding(
          padding: const EdgeInsets.only(top: _cardGap),
          child: child,
        );
      },
    );
  }
}

/// The screen header. `onBack` is deliberately absent: in the master's shell
/// this is a bottom-nav tab ROOT, and the design explicitly allows a null back
/// affordance there ("null on a bottom-nav tab root with no back arrow"). The
/// preview's back arrow returns to a Салон home tab that does not exist in the
/// independent-master shell.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.activeFilterCount,
    required this.onOpenFilters,
  });

  final String title;
  final int activeFilterCount;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: BrandColors.accent.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          VelvetSpacing.lg,
          VelvetSpacing.md,
          VelvetSpacing.lg,
          VelvetSpacing.sm,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                style: VelvetText.masterBookingsTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: VelvetSpacing.sm),
            BookingsFilterButton(
              activeCount: activeFilterCount,
              onTap: onOpenFilters,
            ),
          ],
        ),
      ),
    );
  }
}
