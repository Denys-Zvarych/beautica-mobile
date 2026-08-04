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
//   * `BookingsFilterSheet`'s «Дата» section (Phase 7.7) is RETIRED too
//     (Phase 7.13) — the sheet now resolves only `statuses`/`serviceIds`, so
//     there is nothing date-shaped left for `_applyFilters` to discard.
//
// ## Phase 7.16 — the calendar jump is retired; day selection is by scroll
//
// The rail's calendar button (`_openCalendar`, opening `bookings_day_picker
// .dart`'s `showBookingsDayPicker`) is gone — judged redundant once the month
// switcher's prev/next and «Сьогодні» (`_prevMonth`/`_nextMonth`/`_goToToday`
// below, added `bc08986`) already covered the long-distance jumps a single-day
// picker used to exist for. `showBookingsDayPicker` and its widget were
// deleted outright rather than left as dead UI code — this button was their
// only production call site. [_selectDay]/[_applySelectedDay] are unaffected:
// a rail-chip tap is now the ONLY way [_day] changes (besides «Сьогодні»),
// but it still funnels through the same single mutation path.
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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/formatters/uk_calendar.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';

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

  /// The month currently shown by [_MonthSwitcher] (finding #4). Tracks
  /// [_day]'s month whenever a day is actually selected, but stepping
  /// prev/next moves ONLY this label + the rail's scroll position — never
  /// [_day] or the live query — mirroring the approved design's own
  /// `_focusedMonth`/`_prevMonth`/`_nextMonth`
  /// (`bookings_toolbar.dart:739-822`). See [_prevMonth]/[_nextMonth].
  ///
  /// A [ValueNotifier], NOT a plain `State` field (mobile-perf HIGH): because
  /// [_prevMonth]/[_nextMonth] deliberately change nothing but this LABEL, a
  /// `setState` for them rebuilt the entire subtree — `_Loaded` →
  /// [BookingsTimelineGrid] → `assignLanes` + up to 100 `MasterBookingCard`s
  /// (~212ms measured) — on the exact frame [_centreRailOn] starts its 320ms
  /// `animateTo`, stuttering the rail on its first frame. Routing the label
  /// through a [ValueListenableBuilder] in [_MonthSwitcher] confines the
  /// rebuild to the one `Text` that actually changed. [_goToToday] and
  /// [_applySelectedDay] keep their `setState` — they genuinely change the
  /// query — and simply assign this notifier alongside it.
  late final ValueNotifier<DateTime> _focusedMonth;

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
    // `clockProvider`, NOT a bare `DateTime.now()` (mobile-qa, 2026-07-22).
    // The Kyiv-vs-host distinction this line exists to make is only OBSERVABLE
    // at an instant when the two name different calendar days — roughly a 3h
    // window per day on a UTC runner — so the guard test for it was gated
    // behind a `skip:` that empirically never ran. Reading the injectable
    // clock seam lets that test pin "now" inside the skew window and assert
    // the landing query unconditionally. See `master_bookings_screen_test
    // .dart`'s "initial day" group. Behaviour in production is unchanged:
    // `clockProvider` resolves to `DateTime.now`.
    //
    // `kyivToday(clock)` IS `dateOnly(toBeauticaTime(clock()))`
    // (`shared/time/kyiv_day.dart:84,94`) — the canonical spelling, so `lib/`
    // has one name for this derivation rather than two.
    _today = kyivToday(ref.read(clockProvider));
    // CALENDAR arithmetic — `subtract(Duration(days: n))` would land on 23:00
    // or 01:00 across a Europe/Kyiv DST transition and skew every rail date
    // derived from it. See `bookings_day_rail.dart`'s header.
    _railFirstDay = railDayAt(_today, -kBookedDaysSpanDays);
    _day = _today;
    _focusedMonth = ValueNotifier<DateTime>(DateTime(_day.year, _day.month));
    _statuses = widget.query.statuses.toSet();
    _serviceIds = widget.query.serviceIds.toSet();
    _liveQuery = BookingsDayQuery.of(
      day: _day,
      statuses: _statuses,
      serviceIds: _serviceIds,
    );
    _screenProtection = ref.read(screenProtectionProvider)..acquire();

    // Align the rail to today-first once first layout has happened
    // (`position.viewportDimension` is 0 before it). Unlike the retired
    // screen's `_centreRailOnOpen`, this needs no async gate on
    // `bookedDaysProvider` resolving — the day to align on is already known
    // synchronously (there is no "nearest booked day" search any more).
    //
    // `_alignRailTodayFirst`, NOT `_centreRailOn` — the INITIAL resting
    // position is today-leftmost, not today-centred. See
    // `_alignRailTodayFirst`'s doc for why, and for why every OTHER
    // rail-scroll call site (`_prevMonth`/`_nextMonth`/`_goToToday`) keeps
    // centring unchanged.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _alignRailTodayFirst(_day);
    });
  }

  @override
  void dispose() {
    _dayDebounce?.cancel();
    _screenProtection.release();
    _railController.dispose();
    _focusedMonth.dispose();
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
    // The calendar button is a PINNED sibling of the day-chip `ListView`, not
    // a lead item inside it (`bookings_day_rail.dart`'s `BookingsDayRail
    // .build`) — so `dayIndex` IS the day's `ListView.builder` item index.
    // No lead-item offset (the retired `kRailLeadItems`) is added here.
    final double target =
        dayIndex * kRailItemExtent -
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

  /// Scrolls the rail so [day] renders as the FIRST (leftmost) visible day
  /// chip — the design decision this screen opens on: a master should land
  /// on "today, then what's ahead" rather than a centred view that spends
  /// half the viewport on days already past.
  ///
  /// Used ONLY for the rail's INITIAL resting position (`initState`'s
  /// post-frame callback). Every other rail-scroll call site —
  /// [_centreRailOn], via [_prevMonth]/[_nextMonth]/[_goToToday] — keeps
  /// centring: those are user-INITIATED jumps to a day that is not already
  /// on screen, where centring the target in the viewport (rather than
  /// pinning it to an edge) is the more legible landing spot. Only the
  /// screen's FIRST paint changes.
  ///
  /// Unlike [_centreRailOn] this needs no `viewportDimension` term — "flush
  /// left" does not depend on how much viewport there is, only on [day]'s
  /// day index and [kRailItemExtent]: scrolling exactly `dayIndex *
  /// kRailItemExtent` puts that day's leading edge at the same on-screen
  /// position the `ListView`'s own item 0 occupies at scroll offset zero
  /// (the list's own `padding` is trailing-only now, so [day] lands flush
  /// against whatever precedes the list — the pinned calendar button).
  ///
  /// The calendar button is a PINNED sibling of the day-chip `ListView`, not
  /// a lead item inside it (`bookings_day_rail.dart`'s `BookingsDayRail
  /// .build`) — it stays on screen at every scroll offset, including this
  /// one, so there is no lead-item offset to add here (see the retired
  /// `kRailLeadItems`): a day's index into [_railFirstDay] IS its
  /// `ListView.builder` item index.
  ///
  /// This deliberately does NOT touch [_railFirstDay]/`dayCount` — the rail
  /// keeps spanning the full today ± `kBookedDaysSpanDays` range; only the
  /// resting SCROLL POSITION moves. At this offset every day strictly before
  /// [day] scrolls out of the initial viewport — the calendar button does
  /// not, and remains reachable with zero scrolling — and nothing here
  /// shrinks the list to fake reachability (that would be the
  /// `_clampToRailSpan`/forward-only-range mistake this change must NOT
  /// make): every past day remains fully reachable by scrolling left —
  /// `maxScrollExtent` is untouched.
  void _alignRailTodayFirst(DateTime day) {
    if (!_railController.hasClients) return;
    final ScrollPosition position = _railController.position;
    if (position.viewportDimension <= 0) return;

    // Same DST-safe day-index derivation `_centreRailOn` uses — see that
    // method's doc for why `.difference(...).inDays` is unsafe here.
    final int dayIndex = calendarDayCount(_railFirstDay, dateOnly(day));
    final double target = dayIndex * kRailItemExtent;
    final double clamped = target.clamp(0.0, position.maxScrollExtent);
    _railController.jumpTo(clamped);
  }

  // ── Month switcher (findings #4/#5) ─────────────────────────────────────

  /// Clamps [day] into the rail's date bounds
  /// (`[_railFirstDay, _railFirstDay + kBookedDaysSpanDays * 2]`) — mirrors
  /// the approved design's `_firstOfMonth` clamp
  /// (`bookings_toolbar.dart:266-274`), generalised to any day rather than
  /// only a month's 1st.
  DateTime _clampToRailSpan(DateTime day) {
    final DateTime lastRailDay = railDayAt(
      _railFirstDay,
      kBookedDaysSpanDays * 2,
    );
    if (day.isBefore(_railFirstDay)) return _railFirstDay;
    if (day.isAfter(lastRailDay)) return lastRailDay;
    return day;
  }

  /// The first day of [month], clamped into the rail's span — the target the
  /// rail recentres on when the switcher steps a month.
  DateTime _firstOfMonthClamped(DateTime month) =>
      _clampToRailSpan(DateTime(month.year, month.month));

  /// Steps [_focusedMonth] back one month and recentres the rail on it.
  /// Deliberately does NOT touch [_day] or [_liveQuery] — a pure RAIL-SCROLL
  /// affordance, exactly like the design's own `_prevMonth`: "stepping a
  /// month should move the rail, not just relabel" is satisfied by
  /// [_centreRailOn], not by re-selecting a day.
  ///
  /// NO `setState` (mobile-perf HIGH) — see [_focusedMonth]'s doc. The only
  /// thing this changes is the switcher's label, so it assigns the notifier
  /// and lets the [ValueListenableBuilder] repaint that one `Text` instead of
  /// rebuilding the timeline on the same frame the rail starts animating.
  void _prevMonth() {
    final DateTime current = _focusedMonth.value;
    final DateTime prev = DateTime(current.year, current.month - 1);
    final DateTime target = _firstOfMonthClamped(prev);
    _focusedMonth.value = DateTime(target.year, target.month);
    _centreRailOn(target, animated: true);
  }

  /// Steps [_focusedMonth] forward one month and recentres the rail on it.
  /// See [_prevMonth] for why [_day]/[_liveQuery] are untouched and why this
  /// does not `setState`.
  void _nextMonth() {
    final DateTime current = _focusedMonth.value;
    final DateTime next = DateTime(current.year, current.month + 1);
    final DateTime target = _firstOfMonthClamped(next);
    _focusedMonth.value = DateTime(target.year, target.month);
    _centreRailOn(target, animated: true);
  }

  /// «Сьогодні» (finding #5) — unlike prev/next, this DOES jump the actual
  /// selection: it re-selects today (mirroring [_applySelectedDay]) and
  /// resets the switcher's label to today's month, then recentres the rail.
  void _goToToday() {
    _dayDebounce?.cancel();
    _focusedMonth.value = DateTime(_today.year, _today.month);
    setState(() {
      _day = _today;
      _rebuildQuery();
    });
    _centreRailOn(_today, animated: true);
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

  /// Selecting a rail day narrows to exactly that day. Debounced; see
  /// [_dayDebounce] — a rail flick can land a dozen taps in under a second,
  /// and each one is a new family member and a new request without this.
  void _selectDay(DateTime day) {
    _dayDebounce?.cancel();
    _dayDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      _applySelectedDay(day);
    });
  }

  /// The single mutation a rail-day selection resolves to — sets [_day] and
  /// rebuilds [_liveQuery]. Called after [_dayDebounce] elapses
  /// ([_selectDay]). [_goToToday] mirrors this shape directly rather than
  /// calling it, since it also has to move the rail's scroll position.
  void _applySelectedDay(DateTime day) {
    final DateTime selected = dateOnly(day);
    _focusedMonth.value = DateTime(selected.year, selected.month);
    setState(() {
      _day = selected;
      _rebuildQuery();
    });
  }

  /// The «Скинути фільтри» escape hatch on the filter-empty state — clears
  /// status/service filters. The day is navigation, not a filter (see
  /// [BookingsDayQuery.hasFilters]) and is deliberately left untouched: a
  /// master who narrowed by status on TODAY and hit a filter-empty result
  /// wants today's unfiltered list, not to be bounced back to a different
  /// day.
  void _clearAllFilters() {
    _dayDebounce?.cancel();
    setState(() {
      _statuses = <BookingStatus>{};
      _serviceIds = <String>{};
      _rebuildQuery();
    });
  }

  /// Opens the filter sheet and applies whatever it resolves with.
  ///
  /// The sheet holds DRAFT state and resolves exactly once, on «Застосувати».
  /// `applied.statuses`/`applied.serviceIds` are the whole of what it can
  /// resolve with (Phase 7.13 retired the sheet's «Дата» section along with
  /// `BookingsFilterSelection.from`/`.to` — there is nothing date-shaped left
  /// to discard). The rail, the month switcher, and «Сьогодні» remain the
  /// only day controls (Phase 7.16 retired the calendar jump).
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
  );

  /// Finding #6 — the header's "+" add-booking affordance.
  ///
  /// There is no independent-master "create a booking for a walk-in client"
  /// route anywhere in this app yet — `RouteNames.bookingNew` is the CLIENT's
  /// own "book a master" flow (wrong direction: it would walk a MASTER
  /// through booking themselves as a client). Rather than wire this to a
  /// route that means something else, or invent a new backend call, this
  /// shows the same transient-SnackBar "coming soon" pattern the app already
  /// uses for other unscoped affordances (e.g.
  /// `reschedule_navigation.dart`'s `bookingRescheduleUnavailable`,
  /// `SalonBookingComingSoonScreen`'s placeholder copy).
  ///
  /// ZERO-ARG ON PURPOSE (mobile-perf LOW): it reads `context` off the
  /// `State` so the call site can pass the TEAR-OFF (`onAdd:
  /// _showAddComingSoon`) rather than a fresh `() => _showAddComingSoon(
  /// context)` closure per build. Dart canonicalises instance-method
  /// tear-offs, so the resulting `VoidCallback` is `identical` across
  /// rebuilds — which saves ONE closure allocation per build and keeps
  /// `_Header`'s `onAdd` field stable. It does NOT let `_Header` skip its
  /// subtree: `build` constructs a fresh `_Header(...)` every time, and a
  /// `StatelessWidget` element only short-circuits when the NEW widget
  /// instance is `identical` to the old one (`Element.update`'s first check)
  /// — a claim an earlier revision of this comment made and that was simply
  /// false. Keep the tear-off for the allocation, not for a skip that never
  /// happened; do not reintroduce the `BuildContext` parameter.
  void _showAddComingSoon() {
    final AppLocalizations l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l10n.masterBookingsAddComingSoon)));
  }

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
              onAdd: _showAddComingSoon,
            ),
            const _ServiceCatalogueWarmer(),
            _MonthSwitcher(
              month: _focusedMonth,
              onPrev: _prevMonth,
              onNext: _nextMonth,
              onToday: _goToToday,
            ),
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

  /// `_liveQuery.hasFilters` — whether a status/service filter is active.
  final bool hasFilters;
  final DateTime day;
  final VoidCallback onClearFilters;
  final ValueChanged<Booking> onBookingTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<Booking> items = state.items;

    // `state.isEmpty` (the day has nothing at all) necessarily makes `items`
    // empty too, and a status/service filter that matches nothing on this
    // day also lands here. Which COPY renders is entirely `hasFilters`' job
    // — see that field's doc.
    if (items.isEmpty) {
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
                  // `totalElements` is the SERVER's whole-day count — see
                  // `bookings_day_state.dart`'s header; it equals
                  // `items.length` for a fully-materialised day.
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
              bookings: items,
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
    required this.onAdd,
  });

  final String title;
  final VoidCallback? onBack;
  final int activeFilterCount;
  final VoidCallback onOpenFilters;

  /// Finding #6 — the add-booking affordance. Always shown: unlike the
  /// design's salon-wide screen (where this is admin/owner-gated), THIS
  /// screen only ever renders for the independent master's own bookings, the
  /// one scope the design always shows it for.
  final VoidCallback onAdd;

  // Hoisted — `Color.withValues` and `BorderRadius.circular` are not const,
  // so this can't be `static const`, but resolving once at class-load time
  // avoids a fresh allocation on every header rebuild (mirrors the same fix
  // pattern used throughout `master_booking_card.dart`).
  static final BoxDecoration _addButtonDecoration = BoxDecoration(
    color: BrandColors.accentDeep,
    // A rounded-rect, NOT `shape: BoxShape.circle` — the Impeller-GLES
    // circle+shadow artifact (resolved 34db74f / the guarded avatars in
    // `impeller_circle_shadow_guard_test.dart`) is specifically triggered by
    // pairing `BoxShape.circle` with a `boxShadow`. A `BorderRadius.circular`
    // of half the side length renders visually identical on a square box
    // while routing through Impeller's correct RRect blur path.
    borderRadius: BorderRadius.circular(20),
    boxShadow: const <BoxShadow>[
      BoxShadow(color: Color(0x506A4A28), offset: Offset(0, 3), blurRadius: 8),
    ],
  );

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
            const SizedBox(width: VelvetSpacing.sm),
            Semantics(
              button: true,
              label: l10n.masterBookingsAddSemantics,
              child: GestureDetector(
                key: const Key('master-bookings-add'),
                onTap: onAdd,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  height: 40,
                  width: 40,
                  decoration: _addButtonDecoration,
                  child: const Icon(
                    Icons.add_rounded,
                    color: BrandColors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Month switcher (findings #4/#5) — a nav row above the day rail.
// ===========================================================================

/// A compact "‹ Липень 2026 ›" navigator plus a «Сьогодні» jump action, sat
/// between the header and the day rail. Transcribed from the approved
/// design's `_MonthSwitcher` (`bookings_toolbar.dart:739-822`); see
/// `_BookingsDiscoveryViewState._prevMonth`/`_nextMonth`/`_goToToday` for why
/// stepping the month moves only the rail's scroll position, never the
/// selected day or the live query.
///
/// Takes a [ValueListenable] rather than a bare `DateTime` (mobile-perf HIGH
/// — see `_BookingsDiscoveryViewState._focusedMonth`): the label is the ONLY
/// thing a prev/next step changes, so it is the only thing that rebuilds.
class _MonthSwitcher extends StatelessWidget {
  const _MonthSwitcher({
    required this.month,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });

  final ValueListenable<DateTime> month;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.lg,
        vertical: VelvetSpacing.xs,
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            key: const Key('master-bookings-month-prev'),
            icon: const Icon(Icons.chevron_left_rounded),
            color: BrandColors.accent,
            onPressed: onPrev,
            tooltip: l10n.schedulePrevMonth,
          ),
          Expanded(
            child: ValueListenableBuilder<DateTime>(
              valueListenable: month,
              builder: (BuildContext context, DateTime value, Widget? _) =>
                  Text(
                    '${monthNominative(value.month)} ${value.year}',
                    textAlign: TextAlign.center,
                    style: VelvetText.monthSwitcherLabel,
                  ),
            ),
          ),
          IconButton(
            key: const Key('master-bookings-month-next'),
            icon: const Icon(Icons.chevron_right_rounded),
            color: BrandColors.accent,
            onPressed: onNext,
            tooltip: l10n.scheduleNextMonth,
          ),
          const SizedBox(width: VelvetSpacing.sm),
          _TodayButton(onTap: onToday, label: l10n.scheduleTodayAction),
        ],
      ),
    );
  }
}

/// The «Сьогодні» pill — jumps the rail (and the actual selection) back to
/// today. `borderedButton`, NOT `extrudedSmall`/`extrudedButton`: this is a
/// NEW rounded-rect surface in the booking feature, and every other such
/// surface added since the white-corner-wedge fix (`MasterBookingCard`; the
/// rail's own now-retired `_CalendarButton` was another) deliberately uses
/// the non-offset bordered recipe instead of an offset near-white extruded
/// pair.
class _TodayButton extends StatelessWidget {
  const _TodayButton({required this.onTap, required this.label});

  final VoidCallback onTap;
  final String label;

  static final BoxDecoration _decoration = BoxDecoration(
    color: BrandColors.base,
    borderRadius: BorderRadius.circular(VelvetRadii.pill),
    boxShadow: VelvetShadows.borderedButton,
    border: Border.all(color: BrandColors.accent.withValues(alpha: 0.18)),
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        key: const Key('master-bookings-today'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.sm + 2),
          decoration: _decoration,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.today_rounded,
                size: 15,
                color: BrandColors.accentDeep,
              ),
              const SizedBox(width: 4),
              Text(label, style: VelvetText.monthSwitcherTodayLabel),
            ],
          ),
        ),
      ),
    );
  }
}
