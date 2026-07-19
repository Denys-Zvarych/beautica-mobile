// Phase 7.11 — BookingsDiscoveryView: the shared «Записи» composition — day
// rail, timeline body, states — factored out of `master_bookings_screen.dart`
// so the salon-wide screen can drop it in later WITHOUT a rewrite.
//
// ## The reuse seam, honoured
//
// The approved design already factors this split (`docs/signup-designs/
// SalonManagementDesign/lib/screens/my_bookings_screen.dart` is a THIN
// wrapper over `BookingsDiscoveryScreen`, passing `showMasterFilter: false`;
// `bookings_toolbar.dart:1053-1094`'s `_CountToolbar` renders the teammate
// filter icon conditionally on that flag). This file mirrors it: three
// injection points, and only three —
//
//   1. [query] — the scope AND the seed filters, a [BookingsDayQuery] (Phase
//      7.9's sealed union). Today only `.masterOwn`; the salon phase adds
//      `.salon(...)` and `bookingsDayProvider` dispatches on the member. This
//      view never branches on scope — it reads [BookingsDayQuery.statuses] /
//      [BookingsDayQuery.serviceIds] off whatever member it was handed and
//      rebuilds through [BookingsDayQuery.of] on every change, which works
//      identically for either member because `.of()` is scope-agnostic.
//   2. [showMasterFilter] — gates the teammate-filter affordance in the
//      toolbar. **False here, always** — a single master's own list never
//      offers it. Nothing renders for it yet; the salon phase adds
//      `_MasterFilterSheet` behind this one flag. Do NOT build that sheet
//      here.
//   3. [onBookingTap] — navigation is the HOST's concern, keeping this widget
//      route-agnostic. No `Navigator`/`context.push` anywhere in this file.
//
// ## The day is NOT read from [query] — it is owned here, in Kyiv
//
// [query]'s own `day` field is deliberately NOT used as the initial
// selection. This view OWNS the selected day (locked decision — Phase
// 7.11's Step 1), and the day it opens on is `dateOnly(toBeauticaTime(
// DateTime.now()))` — Kyiv "today", not host "today" and not whatever `day`
// the caller happened to stamp on its seed query (the thin wrapper has no
// principled way to know Kyiv-today at construction time without doing this
// same derivation itself, so centralising it here is both correct AND the
// only single source of truth). [query]'s `statuses`/`serviceIds` DO seed
// this view's filter state — that half of "the scope AND the filters" is
// real.
//
// ## No more «Всі» / range mode
//
// `BookingsDayQuery` (Phase 7.9) carries exactly one Kyiv day — there is no
// all-days or range concept left to express. So:
//   * Exactly one day is selected at all times, including on first open.
//   * If today has no bookings, TODAY STAYS SELECTED — no auto-jump to the
//     nearest booked day. The master's overwhelmingly common intent is
//     "what's on today"; a silent jump makes an empty day indistinguishable
//     from a navigation bug. The dots (`bookedDaysProvider`, unchanged, still
//     filter-independent) show where the work actually is.
//   * The rail's calendar button survives — jumping past the ±180-day span is
//     still useful — but a picked range collapses to its START day at this
//     call site (`_openCalendar`); `date_range_calendar.dart` itself is
//     unmodified and out of this phase's scope.
//   * `BookingsFilterSheet`'s «Дата» section (Phase 7.7) is ALSO unmodified
//     and out of scope. Its `from`/`to` picks are deliberately DISCARDED in
//     `_applyFilters` below — see that method's doc — rather than reinstating
//     a range concept `BookingsDayQuery` can no longer express.
//
// ## Read the async value with `.asData?.value`, never `value == null`
//
// Riverpod's `ref.invalidate` retains the previous `.value` through the next
// `AsyncLoading`/`AsyncError` (seamless reload) — a `value == null` check
// never fires and silently stops detecting anything. This view avoids the
// whole hazard for the day-scoped fetch by dispatching on `.when()`, which
// never inspects `.value` directly; the one place that reads a retained value
// on purpose (`masterServiceCatalogProvider` in `_applyFilters`, mirroring
// the retired screen's S1 audit fix) uses `.asData?.value` explicitly.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';

import '../application/booked_days_notifier.dart';
import '../application/bookings_day_notifier.dart';
import 'package:beautica_mobile/features/services/data/master_service_catalog_provider.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';

import '../domain/booking.dart';
import '../domain/booking_status.dart';
import '../domain/bookings_day_query.dart';
import '../domain/bookings_day_state.dart';
import 'widgets/bookings_day_rail.dart';
import 'widgets/bookings_filter_sheet.dart';
import 'widgets/bookings_timeline_grid.dart';
import 'widgets/date_range_calendar.dart';
import 'widgets/master_bookings_states.dart';
import 'widgets/my_bookings_states.dart';

/// The shared «Записи» discovery composition: header, count toolbar, day
/// rail, timeline body, and the four async states. Parameterised over scope
/// so the salon-wide screen can reuse it verbatim — see the file header.
class BookingsDiscoveryView extends ConsumerStatefulWidget {
  const BookingsDiscoveryView({
    required this.query,
    required this.title,
    this.onBack,
    this.showMasterFilter = false,
    required this.onBookingTap,
    super.key,
  });

  /// The scope AND the seed filters — see the file header for exactly which
  /// half of this is actually used as a seed (statuses/serviceIds) versus
  /// re-derived (the day).
  final BookingsDayQuery query;

  final String title;

  /// The back affordance. `null` on a bottom-nav tab root (the master's own
  /// screen); non-null returns to a host shell's home tab.
  final VoidCallback? onBack;

  /// Whether the teammate («Майстер») filter section is offered. **False
  /// here, always** — a single master's own list never offers it. See the
  /// file header; do not build `_MasterFilterSheet` behind this flag in this
  /// phase.
  final bool showMasterFilter;

  /// Fires with the tapped booking. Navigation is the HOST's concern — no
  /// `Navigator`/`context.push` anywhere in this widget.
  final ValueChanged<Booking> onBookingTap;

  @override
  ConsumerState<BookingsDiscoveryView> createState() =>
      _BookingsDiscoveryViewState();
}

class _BookingsDiscoveryViewState extends ConsumerState<BookingsDiscoveryView> {
  /// The single source of truth for the selected day. Always set — there is
  /// no «Всі» / null-day state (Phase 7.11).
  late DateTime _day;

  late Set<BookingStatus> _statuses;
  late Set<String> _serviceIds;

  /// The live query, rebuilt through [BookingsDayQuery.of] on every change —
  /// the single mutation path, mirroring the retired screen's `_setQuery`
  /// discipline. Never built any other way (`.masterOwn(` directly is banned
  /// outside its declaring file by `scripts/forbid_raw_bookings_query.sh`).
  late BookingsDayQuery _liveQuery;

  final ScrollController _railController = ScrollController();

  /// Kyiv "today", captured once at open — not host "today". See the file
  /// header's "day is NOT read from query" section.
  late final DateTime _today;
  late final DateTime _railFirstDay;

  /// Debounces day-chip taps. A scroll-fling across the rail can land a dozen
  /// taps in under a second, and each one is a new family member and a new
  /// request; without this the flick costs 40 round trips.
  Timer? _dayDebounce;

  // Captured in initState so dispose() never touches `ref` (Riverpod 3.x
  // throws on a post-dispose `ref` read).
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    _today = dateOnly(toBeauticaTime(DateTime.now()));
    // CALENDAR arithmetic — `subtract(Duration(days: n))` would land on 23:00
    // or 01:00 across a Europe/Kyiv DST transition and skew every rail date
    // derived from it. See `bookings_day_rail.dart`'s header.
    _railFirstDay = railDayAt(_today, -kBookedDaysSpanDays);
    _day = _today;
    _statuses = widget.query.statuses.toSet();
    _serviceIds = widget.query.serviceIds.toSet();
    _liveQuery = BookingsDayQuery.of(
      day: _day,
      statuses: _statuses,
      serviceIds: _serviceIds,
    );
    _screenProtection = ref.read(screenProtectionProvider)..acquire();

    // Centre the rail on today once first layout has happened
    // (`position.viewportDimension` is 0 before it). Unlike the retired
    // screen's `_centreRailOnOpen`, this needs no async gate on
    // `bookedDaysProvider` resolving — the day to centre on is already known
    // synchronously (there is no "nearest booked day" search any more).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _centreRailOn(_day);
    });
  }

  @override
  void dispose() {
    _dayDebounce?.cancel();
    _screenProtection.release();
    _railController.dispose();
    super.dispose();
  }

  // ── Rail scrolling ──────────────────────────────────────────────────────

  /// Scrolls the rail so [day] sits in the middle of the viewport.
  void _centreRailOn(DateTime day, {bool animated = false}) {
    if (!_railController.hasClients) return;
    final ScrollPosition position = _railController.position;
    if (position.viewportDimension <= 0) return;

    // `calendarDayCount`, NEVER `.difference(...).inDays` — a plain
    // Duration-based day count is not DST-safe (see that function's doc):
    // it silently returns one day fewer whenever `_railFirstDay` and `day`
    // straddle a Europe/Kyiv DST transition, which is most of the year, and
    // mis-centres the rail by exactly one `kRailItemExtent` on open.
    final int dayIndex = calendarDayCount(_railFirstDay, dateOnly(day));
    // `[calendar]` alone leads the rail post-7.11 — see `kRailLeadItems`.
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

  // ── Query mutation ──────────────────────────────────────────────────────

  /// Rebuilds [_liveQuery] from the current [_day]/[_statuses]/[_serviceIds]
  /// — the ONE place that constructs the live query. Every mutator below goes
  /// through this rather than calling [BookingsDayQuery.of] itself.
  void _rebuildQuery() {
    _liveQuery = BookingsDayQuery.of(
      day: _day,
      statuses: _statuses,
      serviceIds: _serviceIds,
    );
  }

  /// Selecting a rail day (or a calendar pick — see [_openCalendar]) narrows
  /// to exactly that day. Debounced; see [_dayDebounce].
  void _selectDay(DateTime day) {
    _dayDebounce?.cancel();
    _dayDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      setState(() {
        _day = dateOnly(day);
        _rebuildQuery();
      });
    });
  }

  /// The «Скинути фільтри» escape hatch on the filter-empty state — clears
  /// status/service filters only. The day is navigation, not a filter (see
  /// [BookingsDayQuery.hasFilters]) and is deliberately left untouched: a
  /// master who narrowed by status on TODAY and hit a filter-empty result
  /// wants today's unfiltered list, not to be bounced back to a different day.
  void _clearAllFilters() {
    _dayDebounce?.cancel();
    setState(() {
      _statuses = <BookingStatus>{};
      _serviceIds = <String>{};
      _rebuildQuery();
    });
  }

  /// Opens the single/range calendar and narrows [_day] to whatever comes
  /// back.
  ///
  /// `BookingsDayQuery` (Phase 7.9) carries one Kyiv day, not a range, so a
  /// genuine range pick collapses to its START day here — `.of()` is DAY
  /// canonicalisation, not range support, and `date_range_calendar.dart`
  /// itself is unmodified and out of this phase's scope (it still resolves a
  /// `DateTimeRange` because the same picker also backs the filter sheet's
  /// «Дата» row). Dismissing the picker resolves `null` and changes nothing.
  Future<void> _openCalendar() async {
    _dayDebounce?.cancel();
    final DateTimeRange? picked = await showBookingsDateRangePicker(
      context,
      today: _today,
      initialRange: DateTimeRange(start: _day, end: _day),
    );
    if (!mounted || picked == null) return;
    final ({DateTime from, DateTime to}) bounds = normaliseBookingRange(picked);
    _selectDay(bounds.from);
  }

  /// Opens the filter sheet and applies whatever it resolves with.
  ///
  /// The sheet holds DRAFT state and resolves exactly once, on «Застосувати».
  /// Only `applied.statuses`/`applied.serviceIds` reach [_liveQuery] —
  /// `applied.from`/`applied.to` (the sheet's «Дата» section) are
  /// deliberately DISCARDED. `BookingsFilterSelection` still carries a date
  /// range because `bookings_filter_sheet.dart` is unmodified and out of this
  /// phase's scope; wiring its pick into a query that can no longer express a
  /// range would either crash or silently narrow to one arbitrary bound. The
  /// rail (and this method's own [_openCalendar]) remain the only day
  /// controls.
  Future<void> _applyFilters() async {
    _dayDebounce?.cancel();
    // `asData?.value`, NEVER `.value` — see the file header.
    final List<MasterService> services =
        ref.read(masterServiceCatalogProvider).asData?.value ??
        const <MasterService>[];
    final BookingsFilterSelection? applied = await BookingsFilterSheet.show(
      context,
      initial: BookingsFilterSelection(
        statuses: _statuses,
        serviceIds: _serviceIds,
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
    setState(() {
      _statuses = applied.statuses;
      _serviceIds = applied.serviceIds;
      _rebuildQuery();
    });
  }

  /// The count the header badge shows — ACTIVE FILTER GROUPS (day excluded;
  /// it is navigation, not a filter).
  int get _activeFilterCount => bookingsActiveFilterCount(
    hasStatuses: _statuses.isNotEmpty,
    hasServiceIds: _serviceIds.isNotEmpty,
    hasDates: false,
  );

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('master-bookings-screen'),
      backgroundColor: BrandColors.base,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Header(
              title: widget.title,
              onBack: widget.onBack,
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
                final AsyncValue<Set<DateTime>> bookedDaysAsync = ref.watch(
                  bookedDaysProvider,
                );
                final Set<DateTime> bookedDays =
                    bookedDaysAsync.value ?? const <DateTime>{};

                return BookingsDayRail(
                  controller: _railController,
                  firstDay: _railFirstDay,
                  dayCount: kBookedDaysSpanDays * 2 + 1,
                  today: _today,
                  selectedDay: _day,
                  bookedDays: bookedDays,
                  // No range mode survives Phase 7.11 — see the file header.
                  calendarActive: false,
                  onOpenCalendar: _openCalendar,
                  onSelectDay: _selectDay,
                );
              },
            ),
            const SizedBox(height: VelvetSpacing.sm),
            Expanded(
              child: Consumer(
                builder: (BuildContext context, WidgetRef ref, Widget? _) {
                  final AsyncValue<BookingsDayState> async = ref.watch(
                    bookingsDayProvider(_liveQuery),
                  );
                  return async.when(
                    // Bare, unscrolled `Column`s inside a scroll view — the
                    // shipped client screen hosts its own loading/error states
                    // the same way, and dropping either straight into an
                    // `Expanded` overflows the remaining height on a short
                    // device (Phase 17.2 overflow guard).
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
                              ref.invalidate(bookingsDayProvider(_liveQuery)),
                        ),
                      ],
                    ),
                    data: (BookingsDayState state) => _Loaded(
                      state: state,
                      hasFilters: _liveQuery.hasFilters,
                      day: _day,
                      onClearFilters: _clearAllFilters,
                      onBookingTap: widget.onBookingTap,
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

/// A zero-height subscription that keeps the «Послуга» option universe WARM —
/// carried verbatim from the retired screen. See that history for why this is
/// a widget rather than a one-shot `ref.read` in `initState`: the catalogue
/// provider is `keepAlive` and lazy, and an invalidated-but-unsubscribed
/// `keepAlive` provider defers its refetch to the next read, which would open
/// the filter sheet on `AsyncLoading` right after a service create/edit
/// invalidates it.
///
/// Deliberately renders zero height rather than being conditional on the
/// async state — a widget that came and went would relayout the column.
class _ServiceCatalogueWarmer extends ConsumerWidget {
  const _ServiceCatalogueWarmer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(masterServiceCatalogProvider);
    return const SizedBox.shrink();
  }
}

/// The loaded body — the count line, the truncation notice (if any), then the
/// timeline or one of the two empties.
class _Loaded extends StatelessWidget {
  const _Loaded({
    required this.state,
    required this.hasFilters,
    required this.day,
    required this.onClearFilters,
    required this.onBookingTap,
  });

  final BookingsDayState state;
  final bool hasFilters;
  final DateTime day;
  final VoidCallback onClearFilters;
  final ValueChanged<Booking> onBookingTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    if (state.isEmpty) {
      // The two empties are genuinely different situations — see
      // `master_bookings_states.dart`'s header. `hasFilters` is the whole
      // distinction: with no filter active, an empty result means this day is
      // free; with one, it means this filter matches nothing on this day.
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: hasFilters
                ? MasterBookingsNoResultsState(onClearFilters: onClearFilters)
                : const MasterBookingsEmptyState(),
          ),
        ],
      );
    }

    return Column(
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
                  // `totalElements`, NOT `items.length` — see
                  // `bookings_day_state.dart`'s header.
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
        // A genuinely reachable case, not a defensive one — see
        // `MasterBookingsTruncatedNotice`'s doc.
        if (state.isTruncated) const MasterBookingsTruncatedNotice(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              VelvetSpacing.lg,
              0,
              VelvetSpacing.lg,
              VelvetSpacing.xxl,
            ),
            child: BookingsTimelineGrid(
              bookings: state.items,
              day: day,
              onBookingTap: onBookingTap,
            ),
          ),
        ),
      ],
    );
  }
}

/// The screen header. `onBack` renders a back arrow when non-null; `null` on
/// a bottom-nav tab root (the master's own screen never sets it).
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.onBack,
    required this.activeFilterCount,
    required this.onOpenFilters,
  });

  final String title;
  final VoidCallback? onBack;
  final int activeFilterCount;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
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
            if (onBack != null) ...<Widget>[
              NeumorphicIconButton(
                key: const Key('bookings-discovery-back'),
                icon: Icons.arrow_back_ios_new_rounded,
                semanticLabel: l10n.bookingsDiscoveryBackSemantics,
                onTap: onBack!,
              ),
              const SizedBox(width: VelvetSpacing.md),
            ],
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
