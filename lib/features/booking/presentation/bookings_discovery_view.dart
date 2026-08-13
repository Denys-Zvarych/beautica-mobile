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
// ## CANCELLED/DECLINED are hidden by default — on the WIRE, not after
//
// Locked product decision (2026-08-13): a provider's day list opens showing
// only live work. Two sets, deliberately kept apart:
//
//   * `_statuses` — the MASTER's selection. Empty until they tick a group in
//     the filter sheet. Drives `_activeFilterCount` (so an untouched screen
//     shows NO funnel badge) and `_hasUserFilters` (so an empty day still
//     reads «Немає записів», not «…за цим фільтром»).
//   * the WIRE set — what `_rebuildQuery` puts on the query, resolved from
//     `_statuses` by `BookingStatus.dayListWireStatuses` inside
//     `BookingsDayQuery.dayList`. Empty selection →
//     `BookingStatus.visibleInDayListByDefault` (= `filterable` − {CANCELLED,
//     DECLINED}); every group ticked → the EMPTY set, which omits `status`
//     from the request entirely so a status the backend gained after this
//     build shipped is still reachable (it would otherwise be excluded by the
//     server's `status IN (...)` even under "select all"); anything else →
//     `_statuses` verbatim, so ticking «Скасовані» sends exactly CANCELLED +
//     DECLINED and they re-appear.
//
// The mapping is NOT idempotent and is applied exactly once, at query
// construction — the `State` holds the raw selection and never a wire set.
// `BookingsDayQuery.dayList` is also what the two post-write invalidation
// sites build through (`booking_calendar_invalidation.dart`,
// `booking_confirm_screen.dart`), so they target the member this screen
// actually watches; see that factory's doc for the stale-data bug that came
// of them drifting apart.
//
// NOT_COMPLETED stays visible — it is the master's own no-show record and it
// feeds the two-sided client rating.
//
// Server-side is load-bearing, not a preference: `BookingsDayNotifier` fetches
// the day in ONE `size: 100` request with no paging, so cancelled rows
// consuming that budget could silently truncate live ones. Every downstream
// consumer — the header count, `BookingsTimelineGrid`, `DeclaredTimeCards` —
// reads `state.items`/`state.totalElements`, which are now the SERVER's
// already-narrowed list and count, so all of them agree by construction with
// no per-branch filtering added anywhere.
//
// `booking_lane_layout.dart`'s pass 2 (cancelled-vs-replacement overlap) is
// therefore unexercised by DEFAULT but still fully live whenever the filter
// re-shows cancelled bookings. Do not delete it, do not collapse it to a
// single pass.
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
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/formatters/uk_calendar.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';

import '../application/booked_days_notifier.dart';
import '../application/bookings_day_notifier.dart';
import 'package:beautica_mobile/features/services/data/master_service_catalog_provider.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/effective_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';

import '../domain/booking.dart';
import '../domain/booking_status.dart';
import '../domain/bookings_day_query.dart';
import '../domain/bookings_day_state.dart';
import 'widgets/bookings_day_rail.dart';
import 'widgets/bookings_filter_sheet.dart';
import 'widgets/bookings_timeline_grid.dart';
import 'widgets/declared_time_cards.dart';
import 'widgets/master_bookings_states.dart';
import 'widgets/my_bookings_states.dart';
import 'widgets/schedule_timeline_window.dart';

/// The shared «Записи» discovery composition: header, count toolbar, day
/// rail, timeline body, and the four async states. Parameterised over scope
/// so the salon-wide screen can reuse it verbatim — see the file header.
class BookingsDiscoveryView extends ConsumerStatefulWidget {
  const BookingsDiscoveryView({
    required this.query,
    required this.title,
    this.onBack,
    this.showMasterFilter = false,
    this.useScheduleWindow = false,
    this.onAddWorkingHours,
    required this.onBookingTap,
    super.key,
  }) : assert(
         !useScheduleWindow || onAddWorkingHours != null,
         'onAddWorkingHours is required whenever useScheduleWindow is true '
         '— the "no working hours" empty state always needs somewhere to '
         'route its CTA.',
       );

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

  /// ═══════════════════════════════════════════════════════════════════════
  /// WORKING-HOURS WINDOW (the master's own booking timeline only)
  /// ═══════════════════════════════════════════════════════════════════════
  /// Whether the timeline's vertical bounds come from the master's WORKING
  /// HOURS for the selected day (via `effectiveScheduleProvider`) instead of
  /// from the day's bookings, and whether a day with NO working hours
  /// replaces the timeline with [MasterBookingsNoWorkingHoursState].
  ///
  /// `false` (the default, and every OTHER call site — the reuse-seam test
  /// included) keeps this view's ORIGINAL behaviour byte-for-byte: the
  /// booking-derived window `BookingsTimelineGrid` has always used, and no
  /// dependency on `effectiveScheduleProvider` at all (the provider is never
  /// even watched). Set `true` ONLY by `MasterBookingsScreen` — a single
  /// independent master's own list is the one scope where "which hours does
  /// THIS person work" is unambiguous; a future salon-wide consumer (the
  /// `showMasterFilter` reuse seam) would need its own per-teammate answer to
  /// that question before ever setting this `true`, so it stays `false` there
  /// until that is built. See `_Loaded` for the branching this drives.
  final bool useScheduleWindow;

  /// Required whenever [useScheduleWindow] is `true` (see the constructor
  /// assert) — the "no working hours" empty state's CTA fires this with the
  /// selected day so the HOST can route to the schedule editor with that date
  /// pre-selected. Navigation stays the host's concern, same as
  /// [onBookingTap]/[onBack] — no `context.go`/`context.push` in this file.
  final ValueChanged<DateTime>? onAddWorkingHours;

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

  /// The USER's status selection — what the filter sheet resolved with, and
  /// EMPTY until the master picks a group. Deliberately the RAW selection, NOT
  /// the set that goes on the wire: the default cancelled/declined exclusion is
  /// a rendering default, not a filter the master chose, so it must never light
  /// up the funnel badge ([_activeFilterCount]) or flip the empty state's copy
  /// to «Немає записів за цим фільтром» ([_hasUserFilters]).
  ///
  /// The wire mapping is applied exactly once, by [BookingsDayQuery.dayList] in
  /// [_rebuildQuery] — it is not idempotent, so this field must never hold an
  /// already-resolved wire set. See [BookingStatus.dayListWireStatuses].
  late Set<BookingStatus> _statuses;
  late Set<String> _serviceIds;

  /// Whether the MASTER narrowed the list — the empty state's copy switch and
  /// the funnel badge both key off this, never off
  /// [BookingsDayQuery.hasFilters], which is a wire-shape question: `true` even
  /// on an untouched screen (the default exclusion is on the query) and `false`
  /// when every group is ticked (the maximal filter is genuinely unfiltered).
  bool get _hasUserFilters => _statuses.isNotEmpty || _serviceIds.isNotEmpty;

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

  /// Memoises [bookingsInsideScheduleWindow]'s result across rebuilds where
  /// the inputs haven't actually changed — mobile-perf MEDIUM fix (this
  /// session). `_Loaded` is a `StatelessWidget` (deliberately, see its class
  /// doc) and calls this via [_visibleBookingsFor] instead of the free
  /// function directly, so a rebuild triggered by `effectiveScheduleProvider`
  /// re-fetching with an UNCHANGED resolved window (see
  /// `effective_schedule_notifier.dart:78`) reuses the SAME list instance
  /// instead of reallocating one — which is what lets
  /// [BookingsTimelineGrid]'s `identical(widget.bookings,
  /// oldWidget.bookings)` gate (`didUpdateWidget`) short-circuit again.
  ///
  /// Single-slot, not a per-day map: a day switch is a genuine cache miss
  /// anyway ([BookingsDayState.items] changes identity as soon as
  /// `bookingsDayProvider` re-fetches for the new day), so there is nothing
  /// to gain from keeping more than the last result.
  List<Booking>? _cachedVisibleSource;
  DateTime? _cachedVisibleDay;
  int? _cachedVisibleFirstMinute;
  int? _cachedVisibleWindowEndMinute;
  bool? _cachedVisibleIsExplicitTimes;
  List<Booking> _cachedVisibleResult = const <Booking>[];

  /// See [_cachedVisibleSource]'s doc. Compares [items] by IDENTITY (a list
  /// [BookingsDayState] only ever hands out fresh on a genuine re-fetch) and
  /// [window] by its three VALUE fields — [ScheduleTimelineWindow] has no
  /// `==` override and a fresh instance is constructed on every schedule
  /// resolve regardless of whether the working hours actually changed (see
  /// `_Loaded.build`'s `data:` branch), so comparing by reference would
  /// never hit.
  List<Booking> _visibleBookingsFor(
    List<Booking> items,
    DateTime day,
    ScheduleTimelineWindow window,
  ) {
    if (identical(_cachedVisibleSource, items) &&
        _cachedVisibleDay == day &&
        _cachedVisibleFirstMinute == window.firstMinute &&
        _cachedVisibleWindowEndMinute == window.windowEndMinute &&
        _cachedVisibleIsExplicitTimes == window.isExplicitTimes) {
      return _cachedVisibleResult;
    }
    final List<Booking> visible = bookingsInsideScheduleWindow(
      items,
      day,
      window,
    );
    _cachedVisibleSource = items;
    _cachedVisibleDay = day;
    _cachedVisibleFirstMinute = window.firstMinute;
    _cachedVisibleWindowEndMinute = window.windowEndMinute;
    _cachedVisibleIsExplicitTimes = window.isExplicitTimes;
    _cachedVisibleResult = visible;
    return visible;
  }

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
    // Through [_rebuildQuery], NOT a second inline `BookingsDayQuery.of` — it
    // is the one place that folds the default status exclusion onto the wire
    // (via [BookingsDayQuery.dayList]), and a landing query built any other way
    // would skip it.
    _rebuildQuery();
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
  /// through this rather than building a query itself.
  ///
  /// [BookingsDayQuery.dayList], never [BookingsDayQuery.of]: the default
  /// cancelled/declined exclusion lives on the WIRE and is owned by that
  /// factory, which the two post-write invalidation sites also build through
  /// so they target the member this screen actually watches. Passing
  /// [_statuses] RAW is load-bearing — the mapping is not idempotent. The UI's
  /// own notion of "is a filter active" stays [_hasUserFilters].
  void _rebuildQuery() {
    _liveQuery = BookingsDayQuery.dayList(
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
  /// status/service filters back to the DEFAULT view (which still excludes
  /// CANCELLED/DECLINED via [BookingsDayQuery.dayList]; "cleared" means "the
  /// master chose nothing", not "show everything" — the latter is ticking
  /// every group in the sheet, which is a different wire set entirely). The day
  /// is navigation, not a filter, and is deliberately left untouched: a master
  /// who narrowed by status on TODAY and hit a filter-empty result wants
  /// today's unfiltered list, not to be bounced back to a different day.
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
  ///
  /// Reads [_statuses] (the master's own selection), never the resolved WIRE
  /// set. Both ends of that mapping would give the wrong answer: the default
  /// cancelled/declined exclusion is not a decision the master made, so an
  /// untouched screen must report **0** and show no badge; and ticking every
  /// group resolves to an EMPTY wire set, which must still report **1** and
  /// show the badge — the master narrowed nothing away, but they did make a
  /// choice, and the funnel is how they find their way back out of it.
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
  /// shows the same transient-VelvetSnack "coming soon" pattern the app
  /// already uses for other unscoped affordances (e.g.
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
    // This screen (via `MasterBookingsScreen`) always renders the master's
    // own `VelvetBottomNavBar` as its `bottomNavigationBar` — never
    // suppressed — so the bottom-anchored snack needs `bottomInset` to clear
    // it; see `VelvetSizes.bottomNavClearanceMaster`'s doc.
    showInfoSnack(
      context,
      l10n.masterBookingsAddComingSoon,
      bottomInset: VelvetSizes.bottomNavClearanceMaster,
    );
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

                  // mobile-perf MEDIUM fix (this session): watched HERE,
                  // ALONGSIDE `bookingsDayProvider` rather than from inside
                  // `_Loaded` (which only ever mounts once `async` resolves
                  // to `data:`) — so the two fetches fire in PARALLEL on
                  // every day change instead of the schedule round trip
                  // waiting on the bookings one to finish first. `null` when
                  // `useScheduleWindow` is `false`: the provider is still
                  // NEVER watched for any other caller — the doc'd invariant
                  // on `BookingsDiscoveryView.useScheduleWindow` is
                  // unchanged, just enforced one level up.
                  final AsyncValue<List<EffectiveDay>>? scheduleAsync =
                      widget.useScheduleWindow
                      ? ref.watch(
                          effectiveScheduleProvider(
                            ScheduleRange(from: _day, to: _day),
                          ),
                        )
                      : null;

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
                      // [_hasUserFilters], NOT `_liveQuery.hasFilters` — the
                      // live query always carries statuses now (the default
                      // exclusion), so reading it here would render the
                      // «Немає записів за цим фільтром» copy on a screen the
                      // master never filtered.
                      hasFilters: _hasUserFilters,
                      day: _day,
                      useScheduleWindow: widget.useScheduleWindow,
                      scheduleAsync: scheduleAsync,
                      visibleBookingsFor: _visibleBookingsFor,
                      onClearFilters: _clearAllFilters,
                      onBookingTap: widget.onBookingTap,
                      onAddWorkingHours: widget.onAddWorkingHours,
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
/// timeline or one of three empties.
///
/// [StatelessWidget] again (mobile-perf MEDIUM fix, this session): this used
/// to be a [ConsumerWidget] purely to `ref.watch(effectiveScheduleProvider
/// (...))` itself — which meant that watch could only ever start once the
/// OUTER `Consumer`'s `bookingsDayProvider` had already resolved to `data:`
/// (this widget is constructed nowhere else), serialising two independent
/// network round trips that have nothing to do with each other. The outer
/// `Consumer` now watches both providers side by side and hands the schedule
/// fetch's [AsyncValue] in as [scheduleAsync] instead — see that `Consumer`'s
/// builder. When [useScheduleWindow] is `false`, [scheduleAsync] is `null`
/// and the provider was never watched at all, exactly as before.
class _Loaded extends StatelessWidget {
  const _Loaded({
    required this.state,
    required this.hasFilters,
    required this.day,
    required this.useScheduleWindow,
    required this.scheduleAsync,
    required this.visibleBookingsFor,
    required this.onClearFilters,
    required this.onBookingTap,
    required this.onAddWorkingHours,
  }) : assert(
         !useScheduleWindow || scheduleAsync != null,
         'scheduleAsync must be set whenever useScheduleWindow is true — '
         'the outer Consumer always watches effectiveScheduleProvider in '
         'that case.',
       );

  final BookingsDayState state;

  /// `_BookingsDiscoveryViewState._hasUserFilters` — whether the MASTER
  /// narrowed the list. Deliberately NOT `_liveQuery.hasFilters`: the live
  /// query carries a status set on an untouched screen (the default
  /// cancelled/declined exclusion) and NO status set when every group is
  /// ticked, so that getter answers the opposite question at both ends. See
  /// `_statuses`' doc on the `State` and [BookingStatus.dayListWireStatuses].
  final bool hasFilters;
  final DateTime day;

  /// `widget.useScheduleWindow` — see that field's doc on
  /// [BookingsDiscoveryView].
  final bool useScheduleWindow;

  /// The master's working-hours fetch for [day] — watched by the OUTER
  /// `Consumer`, in PARALLEL with `bookingsDayProvider`, so the two round
  /// trips race instead of serialising (see the class doc). `null` iff
  /// [useScheduleWindow] is `false` (constructor assert); non-null and
  /// dispatched on via `.when()` otherwise, exactly as this widget used to
  /// dispatch on its own `ref.watch` result.
  final AsyncValue<List<EffectiveDay>>? scheduleAsync;

  /// `_BookingsDiscoveryViewState._visibleBookingsFor` — mobile-perf MEDIUM
  /// fix (this session). `_Loaded` is a [StatelessWidget] and has nowhere of
  /// its own to remember the last filtered list across a rebuild, so the
  /// memo lives in the `State` above and is handed in as a callback instead
  /// — keeps this widget itself unchanged (still a pure function of its
  /// constructor args), it just no longer calls
  /// [bookingsInsideScheduleWindow] directly. See that method's doc for why
  /// the cache lives there rather than here.
  final List<Booking> Function(
    List<Booking> items,
    DateTime day,
    ScheduleTimelineWindow window,
  )
  visibleBookingsFor;

  final VoidCallback onClearFilters;
  final ValueChanged<Booking> onBookingTap;

  /// `widget.onAddWorkingHours` — non-null whenever [useScheduleWindow] is
  /// `true` (the constructor assert on [BookingsDiscoveryView] guarantees
  /// it), unused otherwise.
  final ValueChanged<DateTime>? onAddWorkingHours;

  @override
  Widget build(BuildContext context) {
    if (!useScheduleWindow) {
      return _body(context, window: null);
    }

    // No `!` (repo style) — the constructor assert above guarantees
    // non-null whenever `useScheduleWindow` is true, which is the only way
    // this line runs; the `??` is a documented, release-mode safety net for
    // that invariant, not an expected path.
    final AsyncValue<List<EffectiveDay>> schedule =
        scheduleAsync ?? const AsyncValue<List<EffectiveDay>>.loading();

    return schedule.when(
      // Never flash the gray state while the schedule is still resolving —
      // render exactly as `useScheduleWindow: false` would, using the
      // legacy booking-derived window, until a genuine verdict lands.
      loading: () => _body(context, window: null),
      // Same fallback on error — an unreachable schedule endpoint must not
      // read as "no working hours" to the master.
      error: (Object _, StackTrace _) => _body(context, window: null),
      data: (List<EffectiveDay> days) {
        final EffectiveDay? resolved = _effectiveDayFor(days, day);
        final ScheduleTimelineWindow? window = resolved == null
            ? null
            : scheduleWindowFor(resolved);
        // `resolved == null` is checked ALONGSIDE `window == null` purely for
        // flow-typing (repo style forbids `!`): by construction `window` is
        // null whenever `resolved` is (see the ternary above), so this OR
        // never changes which real-world days land here — it only lets the
        // analyzer promote [resolved] to non-null below, alongside [window].
        if (window == null || resolved == null) {
          // No `!` (repo style) — the constructor assert on
          // [BookingsDiscoveryView] guarantees [onAddWorkingHours] is set
          // whenever [useScheduleWindow] is `true`, which is the only way
          // this branch is ever reached; the `??` fallback is a documented,
          // release-mode safety net for that invariant, not an expected path.
          final ValueChanged<DateTime> addWorkingHours =
              onAddWorkingHours ??
              (DateTime _) => throw StateError(
                'onAddWorkingHours must be set when useScheduleWindow is '
                'true — see BookingsDiscoveryView\'s constructor assert.',
              );
          return MasterBookingsNoWorkingHoursState(
            dayOff: resolved?.source == EffectiveSource.overrideDayOff,
            onAddHours: () => addWorkingHours(day),
          );
        }

        // ═══════════════════════════════════════════════════════════════
        // EXPLICIT_TIMES days — a UNION list of declared-time cards, never
        // a filtered grid. See `declared_time_cards.dart`'s header for the
        // full correctness contract. Gated on [EffectiveDay.isExplicitTimes]
        // alone — every INTERVAL day falls through to the unchanged
        // `bookingsInsideScheduleWindow` + `BookingsTimelineGrid` path below.
        //
        // `state.items` is handed through UNFILTERED (never
        // `bookingsInsideScheduleWindow` — that predicate is a GRID concept
        // and would silently drop a booking whose start does not match any
        // declared time), so both the header count ([_body]'s `count`) and
        // the rendered card set come from the exact same list and can never
        // disagree — the same invariant `visibleBookingsFor` protects for
        // INTERVAL days, held here by construction instead.
        if (resolved.isExplicitTimes) {
          return _body(
            context,
            window: window,
            visibleItems: state.items,
            declaredTimes: resolved.times,
          );
        }

        // mobile-security HIGH fix (this session): the ONE filtering
        // computation — see `bookingsInsideScheduleWindow`'s doc. Its result
        // feeds BOTH the header count and the grid's card set below
        // ([_body]), so the two can never read different numbers.
        //
        // `visibleBookingsFor`, NOT `bookingsInsideScheduleWindow` directly
        // (mobile-perf MEDIUM fix, this session) — see [visibleBookingsFor]'s
        // doc: this keeps the result's identity stable across a rebuild
        // where `state.items` and the resolved window haven't changed.
        final List<Booking> visible = visibleBookingsFor(
          state.items,
          day,
          window,
        );
        return _body(context, window: window, visibleItems: visible);
      },
    );
  }

  /// The resolved [EffectiveDay] matching [day] out of [days] (a single-day
  /// range normally returns exactly one entry, but this scans defensively
  /// rather than assuming index 0). `null` when the range genuinely does not
  /// cover [day] — treated exactly like an unresolved/no-hours day by [build]
  /// (falls through to the "no working hours" state) rather than crashing.
  static EffectiveDay? _effectiveDayFor(List<EffectiveDay> days, DateTime day) {
    for (final EffectiveDay d in days) {
      if (d.date.year == day.year &&
          d.date.month == day.month &&
          d.date.day == day.day) {
        return d;
      }
    }
    return null;
  }

  /// The count line, the truncation notice, then the timeline or the
  /// filter-aware empty pair. [window] is `null` for every call site that
  /// predates this feature (and for `useScheduleWindow: true`'s
  /// loading/error/fallback branches); non-null only once a real
  /// working-hours window has resolved, in which case it is threaded through
  /// to [BookingsTimelineGrid] to bound the grid.
  ///
  /// [visibleItems] — mobile-security HIGH fix (this session): the master's
  /// own bookings, already filtered to [window] by
  /// [bookingsInsideScheduleWindow] (see [build]'s `data:` branch) — EXCEPT
  /// on an EXPLICIT_TIMES day (see [declaredTimes]), where it is [state.
  /// items] handed through UNFILTERED, since `DeclaredTimeCards` unions
  /// rather than filters. `null` for every call site above where no window
  /// has resolved (legacy path, loading, error) — in which case this uses
  /// `state.items`/`state.totalElements` exactly as before this feature, so
  /// the `useScheduleWindow: false` behaviour is provably untouched.
  /// Non-null drives BOTH the rendered count and the timeline body's own
  /// bookings from the SAME list, so they cannot disagree.
  ///
  /// [declaredTimes] — non-null ONLY when [build]'s `data:` branch resolved
  /// an EXPLICIT_TIMES [EffectiveDay] ([EffectiveDay.times]). When set, this
  /// renders `DeclaredTimeCards` instead of `BookingsTimelineGrid` — see
  /// `declared_time_cards.dart`'s header for the full contract. `null` for
  /// every INTERVAL-day call site, which keeps rendering the grid exactly as
  /// before this feature.
  Widget _body(
    BuildContext context, {
    required ScheduleTimelineWindow? window,
    List<Booking>? visibleItems,
    List<TimeOfDay>? declaredTimes,
  }) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<Booking> items = visibleItems ?? state.items;
    // `totalElements` is the SERVER's whole-day count (see
    // `bookings_day_state.dart`'s header) — kept ONLY as the legacy/loading/
    // error fallback. Once a window has resolved, `visibleItems!.length` is
    // what actually renders below, so that is what the header must say.
    final int count = visibleItems?.length ?? state.totalElements;

    // `state.isEmpty` (the day has nothing at all) necessarily makes
    // `state.items` empty too, and a status/service filter that matches
    // nothing on this day also lands here — as does a day whose bookings
    // exist but ALL fall outside the resolved working-hours window. Which
    // COPY renders is entirely `hasFilters`' job — see that field's doc.
    // Reachable regardless of [window]: a working day with genuinely zero
    // (visible) bookings is "no bookings", not "no working hours" (that
    // verdict is [build]'s job, decided BEFORE this method is ever called —
    // see the class doc).
    //
    // BUG FIX (user-reported) — gated on `window == null` now, not on
    // `items.isEmpty` alone. Once a real working-hours window has resolved,
    // the master's day HAS hours — an empty result (zero bookings, bookings
    // that all fall outside the window, or a filter matching nothing) must
    // still render the hour ruler AND gridlines, just with no cards on them,
    // so the master can see the shape of their working day even when it's
    // empty. Locked product decision: no accompanying empty-state text in
    // that case — just the grid. `window == null` covers every call site
    // that predates this feature (`useScheduleWindow: false`, and
    // `useScheduleWindow: true`'s own loading/error fallbacks — see [build]),
    // which keep the illustrated empty states exactly as before.
    if (items.isEmpty && window == null) {
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
                  l10n.masterBookingsCount(count),
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
        // `MasterBookingsTruncatedNotice`'s doc. Gated on `state.isTruncated`
        // alone (the server's own ">100 bookings this day" signal), same as
        // always — [visibleItems] narrows WHICH of those bookings render, it
        // says nothing about whether the day overflowed the server's page.
        if (state.isTruncated) const MasterBookingsTruncatedNotice(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              VelvetSpacing.lg,
              0,
              VelvetSpacing.lg,
              VelvetSpacing.xxl,
            ),
            child: declaredTimes != null
                ? DeclaredTimeCards(
                    declaredTimes: declaredTimes,
                    bookings: items,
                    day: day,
                    onTapBooking: onBookingTap,
                  )
                : BookingsTimelineGrid(
                    bookings: items,
                    day: day,
                    onBookingTap: onBookingTap,
                    scheduleFirstMinute: window?.firstMinute,
                    scheduleWindowEndMinute: window?.windowEndMinute,
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
