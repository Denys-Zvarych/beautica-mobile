// Phase 7.6 — the «Мої записи» day rail: a horizontally scrolling past↔future
// strip of day chips.
//
// Phase 7.11 (D3/R6) — the «Всі» chip is RETIRED. `BookingsDayQuery` (Phase
// 7.9) has no all-days/range mode any more — the screen is always scoped to
// exactly one Kyiv calendar day — so a chip that cleared the date narrowing
// entirely no longer has a query it could resolve to. [selectedDay] is now
// non-nullable for the same reason: there is no "nothing selected" state to
// represent.
//
// Phase 7.16 — the calendar escape hatch (`_CalendarButton`, opening
// `showBookingsDayPicker`) is RETIRED. Day selection is by scrolling the rail
// alone; the month switcher's prev/next and «Сьогодні» (added `bc08986`)
// already covered the long-distance jumps the button used to exist for,
// which made a second jump affordance redundant. `BookingsDayRail` no longer
// takes a `calendarActive`/`onOpenCalendar` pair, and the rail is a bare
// `ListView.builder` again — no pinned sibling.
//
// Варіант D port (`widgets/bookings_month_calendar_panel.dart`) — this rail
// is now ALSO the collapsed resting state of an expandable month calendar
// layered over it, replacing the month switcher named above.
//
// ## ⚠ A WEEK PAGER, not a continuous strip (user-requested, this session)
//
// The rail used to be a continuous `ListView.builder` over a ±180-day window
// with a fixed 62dp `itemExtent`, which meant it came to rest anywhere: a
// Wed→Tue span was as normal a resting state as a Mon→Sun one. The locked
// requirement now is "the days line represents the current WEEK, it should
// always start from Monday; scrolling moves to the next week, first day
// Monday and last Sunday".
//
// So this is a `PageView.builder` of WEEK pages: one page = exactly seven
// chips, Monday-first, each `Expanded` to `(width - 2 * VelvetSpacing.lg) / 7`.
// Three consequences worth stating, because each replaces a prior invariant:
//
//   * There is no `itemExtent` any more — the chip extent is WIDTH-DERIVED.
//     A fixed 75dp extent × 7 is 525dp, which does not fit the 320dp
//     narrow-phone floor at all; see [_DayChip] for how the chip's own
//     content stays inside a slot that narrow, at any text scale.
//   * The rail's horizontal inset (`VelvetSpacing.lg`) now matches
//     `MonthCalendar`'s own self-inset exactly, so the collapsed rail's seven
//     chips land on the SAME seven columns as the expanded grid's seven
//     day columns and `CalendarWeekdayBar`'s seven captions. The two halves
//     of one control finally share a column grid.
//   * Paging the rail is pure NAVIGATION and never changes the selection —
//     same as scrolling always was. Only a chip TAP selects
//     ([onSelectDay], routed through the host's 220ms debounce). A pager
//     that selected on settle would fire one query per week flick, which is
//     exactly what that debounce exists to prevent.
//
// Transcribed from `docs/signup-designs/SalonManagementDesign/lib/widgets/
// bookings_toolbar.dart` (`_DayRail`, `_DayChip`; the design's `_AllChip` is
// NOT transcribed post-7.11, and `_CalendarButton` is not transcribed
// post-7.16). The visual language is the design's verbatim: no chip
// background, selection carried by text colour alone, today underlined when
// unselected, a camel dot under any day that has bookings.
//
// ## ⚠ CALENDAR arithmetic, never `Duration(days: n)` — this WILL bite
//
// Every date in this file is derived with `DateTime(y, m, d + n)`, which
// normalises an out-of-range day component against the CALENDAR and always
// lands on local midnight. The design uses `firstDay.add(Duration(days: i))`,
// and that is the one line of it deliberately NOT transcribed.
//
// `DateTime.add` adds an absolute 24-hour block. Across a Europe/Kyiv DST
// transition — the last Sunday of March and of October — a chain of them
// lands on 01:00 or 23:00 instead of 00:00. `bookedDaysProvider` returns a
// `Set<DateTime>` of local midnights, so `contains()` on a 23:00 value MISSES:
// the dot silently vanishes for a day, twice a year, with no error and no
// crash. The same skew would then flow into the query bounds via `toApiDate`,
// filtering the list to the wrong day.
//
// `bookings_day_rail_test.dart` pins both transitions.
//
// ## Lazily built — the week span is years wide
//
// `PageView.builder` builds the visible page (and, during a drag, its
// neighbours) and nothing else, so the number of weeks the rail spans is
// nearly free. It is deliberately much wider than `bookedDaysProvider`'s own
// ±180-day dot window: since the expanded calendar's month pager can select
// ANY month, the rail must be able to show ANY selected week or the two
// controls desync the moment the master pages six months out. Days outside
// the dot window simply carry no dot — exactly what the expanded grid's own
// density dots already do for the same days, from the same set.
//
// A week's offset from [firstWeekStart] IS its `PageView.builder` page index
// ([railWeekIndex]) — there is no lead item of any kind (Phase 7.11 retired
// the «Всі» chip; Phase 7.16 retired the pinned calendar button).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart' show kyivDaysBetween;
import 'package:beautica_mobile/shared/widgets/calendar_grid.dart'
    show calendarDayIsDeemphasized, isWeekendWeekday, kCalendarDotColor;

import 'low_threshold_page_scroll_physics.dart';

/// Days per rail page — a calendar week, Monday through Sunday. Not a tuning
/// knob: [_WeekPage] lays out exactly this many `Expanded` slots and
/// [railWeekIndex] divides by it.
const int kRailWeekLength = 7;

/// Week pages the rail spans EITHER SIDE of the week containing today — five
/// years each way.
///
/// Deliberately much wider than `bookedDaysProvider`'s own ±180-day dot
/// window, which the retired continuous strip used to be bounded by. That
/// bound was fine while the rail was the only long-distance day control; it
/// is not fine now that the expanded grid's month pager can select any month,
/// because a selection the rail cannot reach leaves the two halves of one
/// control showing different weeks with no chip highlighted. Pages are built
/// lazily, so the extra span costs nothing; days outside the dot window
/// simply carry no dot, exactly as the expanded grid's own density dots
/// already behave for the same days from the same set.
const int kBookingsDayRailWeekSpan = 260;

/// Height of the rail strip — the design's own 70dp.
///
/// A previous pass bumped this to 78 (and shrank [_dayChipCaptionGap] to 10)
/// because the app's `VelvetText` styles carried line-height multipliers the
/// preview's raw `TextStyle`s did not, overflowing the design's 70dp by 17dp.
/// The 2026-07-19 pass that shrank `VelvetText.railDayNumber` to 12.6sp (from
/// 18sp) freed exactly the vertical room that 8dp bump existed to cover, so
/// both are restored to the design's own values here.
///
/// Public (not `_railHeight`) since Варіант D's `BookingsMonthCalendarPanel`
/// needs it as the calendar's COLLAPSED resting height, sized against the
/// same figure this rail actually renders at.
const double kBookingsDayRailHeight = 70;

/// Vertical gap between a day chip's weekday caption and its day number —
/// the design's own 16dp, restored alongside [kBookingsDayRailHeight]; see
/// its doc.
const double _dayChipCaptionGap = 16;

/// The width [_DayChip]'s glyph column is LAID OUT at, before the
/// [BoxFit.scaleDown] fit — the design's own 44dp, unchanged from the
/// pre-pager rail. It is not the rendered chip width: the rendered slot is
/// `(rail width - 2 * VelvetSpacing.lg) / 7`, which is 44.6dp at 360dp (so
/// the fit is a no-op there and the design renders exactly as drawn) and
/// 38.9dp at the 320dp floor (so the column scales to 0.88). See [_DayChip]'s
/// class doc.
const double _kChipIntrinsicWidth = 44;

/// Returns the day [offset] days after [from], by CALENDAR arithmetic.
///
/// The DST-safe replacement for `from.add(Duration(days: offset))` — see the
/// file header for what breaks otherwise. Exposed (not private) so the screen
/// and the tests derive rail dates through the exact same function the rail
/// itself uses.
DateTime railDayAt(DateTime from, int offset) =>
    DateTime(from.year, from.month, from.day + offset);

/// The number of CALENDAR days between date-only [from] and [to] (positive
/// when [to] is after [from]), independent of any DST transition crossed in
/// between.
///
/// `to.difference(from).inDays` is NOT safe for this and must not be used in
/// its place: `DateTime.difference` subtracts the two values' absolute
/// instants, so a spring-forward transition crossed between [from] and [to]
/// shortens the elapsed wall-clock span by exactly the skipped hour (e.g.
/// 180 calendar days becomes `4319:00:00`, 179 days 23 hours), and
/// `Duration.inDays` truncates rather than rounds — silently returning ONE
/// DAY FEWER than the calendar actually spans. On a device in an
/// Europe/Kyiv-observing zone this is not a rare edge case: the ±180-day
/// rail span crosses at least one of the two yearly transitions (last Sunday
/// of March / October) for the large majority of the year.
///
/// This function counts by first re-anchoring both dates in UTC, which never
/// observes DST — every calendar day is uniformly 24 hours there, so the
/// subtraction is always exact.
///
/// Exposed (not private) so both [railWeekIndex] and its tests derive a day
/// count through the exact same function, mirroring [railDayAt]'s pattern.
/// (It used to back the retired `_centreRailOn`'s pixel-offset math on the
/// continuous strip; the week pager needs the same arithmetic, one level up.)
///
/// Phase 284 PROMOTED the body of this function to
/// `shared/time/kyiv_day.dart`'s [kyivDaysBetween] and left this name as a
/// delegating alias — behaviour is byte-identical, every existing caller
/// (`railWeekIndex`, `bookings_day_rail_test.dart`,
/// `booked_days_notifier_test.dart`) is untouched. The promotion happened
/// because `shared/formatters/relative_date.dart` had hand-rolled the UNSAFE
/// `.difference(...).inDays` form two directories away and shipped the exact
/// off-by-one this doc warns about: the safe implementation was unreachable
/// from `shared/` without importing another feature's `presentation/`, which
/// the layering forbids. The date-token contract now owns it.
int calendarDayCount(DateTime from, DateTime to) => kyivDaysBetween(from, to);

/// The MONDAY of the calendar week containing [day], date-only.
///
/// `day.weekday` is 1 (Monday) … 7 (Sunday), so `1 - weekday` is the signed
/// offset back to that week's Monday — 0 on a Monday, -6 on a Sunday. Routed
/// through [railDayAt] (never `subtract(Duration(days:))`) for the DST reason
/// the file header spells out: a Sunday in the fall-back week would otherwise
/// resolve to 01:00 on its Monday, and every `Set<DateTime>` membership test
/// downstream would miss.
///
/// [day] MUST already be a local date-only value — a Kyiv day token from
/// `kyivToday`/`railDayAt`/`dateOnly`, never a raw UTC wire instant, whose
/// `.weekday` can name the wrong day (mobile-backlog `_DateStub`, `0eca0791`).
DateTime mondayOf(DateTime day) => railDayAt(day, 1 - day.weekday);

/// The rail page index for the week containing [day], counted from
/// [firstWeekStart] (itself a Monday — [mondayOf] its input if in doubt).
///
/// Exact by construction: both ends are Mondays, so [calendarDayCount] always
/// returns a multiple of [kRailWeekLength] and the truncating `~/` never
/// rounds — including for negative results, where Dart's `~/` truncates
/// toward zero and would otherwise disagree with floor.
int railWeekIndex(DateTime firstWeekStart, DateTime day) =>
    calendarDayCount(firstWeekStart, mondayOf(day)) ~/ kRailWeekLength;

/// Memoised weekday abbreviations, keyed by the [AppLocalizations] instance
/// they came from (perf P4).
///
/// The seven captions are fixed for a locale, but they were rebuilt into a
/// fresh `List<String>` on every rail `build()`. `AppLocalizations` is a
/// per-locale singleton, so identity is a sound cache key AND a correct
/// invalidation signal: switching locale hands `build` a different instance
/// and the list is recomputed. One list is retained, not one per locale ever
/// seen — a new key replaces the entry rather than growing a map.
List<String>? _weekdayShortCache;
AppLocalizations? _weekdayShortCacheKey;

List<String> _weekdayShorts(AppLocalizations l10n) {
  final List<String>? cached = _weekdayShortCache;
  if (cached != null && identical(_weekdayShortCacheKey, l10n)) return cached;
  final List<String> built = List<String>.unmodifiable(<String>[
    l10n.weekdayShortMon,
    l10n.weekdayShortTue,
    l10n.weekdayShortWed,
    l10n.weekdayShortThu,
    l10n.weekdayShortFri,
    l10n.weekdayShortSat,
    l10n.weekdayShortSun,
  ]);
  _weekdayShortCache = built;
  _weekdayShortCacheKey = l10n;
  return built;
}

/// Widget key for the day cell representing [day].
///
/// Keyed by the FULL date rather than the day-of-month: the rail spans 361
/// days, so a bare day number repeats up to a dozen times and `find.byKey`
/// would silently resolve to whichever month came first. Exposed so tests
/// address a cell through the same derivation the rail uses, instead of
/// re-spelling the key format and drifting from it.
Key dayChipKey(DateTime day) =>
    Key('master-bookings-day-chip-${toApiDate(day)}');

/// Widget key for the has-bookings dot on [day]. Present only when the day
/// carries a booking, so `findsNothing` is a meaningful assertion.
Key dayDotKey(DateTime day) => Key('master-bookings-day-dot-${toApiDate(day)}');

/// The week-paging day strip: exactly seven chips per page, Monday first,
/// Sunday last, snapping one whole week per swipe.
class BookingsDayRail extends StatefulWidget {
  const BookingsDayRail({
    super.key,
    required this.controller,
    required this.firstWeekStart,
    required this.weekCount,
    required this.today,
    required this.selectedDay,
    required this.bookedDays,
    required this.onSelectDay,
    this.onVisibleWeekChanged,
  });

  /// Drives which WEEK is on screen. A [PageController] rather than a bare
  /// [ScrollController] because the host pages by index
  /// ([PageController.animateToPage]) rather than by pixel offset — the whole
  /// point of the week pager is that the rail has no valid resting position
  /// between two weeks, so there is no offset for the host to compute.
  final PageController controller;

  /// The MONDAY the rail's first page starts on. The host derives it with
  /// [mondayOf]; nothing here re-derives it, so the page index the host jumps
  /// to and the dates this widget renders can never disagree.
  final DateTime firstWeekStart;

  /// Number of week pages. See the file header for why this is deliberately
  /// wider than `bookedDaysProvider`'s own dot window.
  final int weekCount;

  final DateTime today;

  /// The single selected day. Always set — Phase 7.11 retired the «Всі» /
  /// null-day state; the screen is always scoped to exactly one Kyiv calendar
  /// day, including on first open (`dateOnly(toBeauticaTime(DateTime.now()))`
  /// — see `bookings_discovery_view.dart`).
  final DateTime selectedDay;

  /// Date-only days carrying at least one booking — `bookedDaysProvider`.
  ///
  /// A `Set` because this is a membership test run for every visible cell on
  /// every scroll frame. **Filter-independent by design**: the dots describe
  /// where the master's work is, not what the current filter matches, so they
  /// must not evaporate as the user narrows. See `booked_days_notifier.dart`.
  final Set<DateTime> bookedDays;

  final ValueChanged<DateTime> onSelectDay;

  /// Fires with the MONDAY of the week page that just SETTLED — on a
  /// `ScrollEndNotification` only (mirroring [_lastSettledPage]'s haptic
  /// cue), never on a per-drag-frame `ScrollUpdateNotification`. A rail flick
  /// through several weeks therefore reports its LANDING week exactly once,
  /// not once per frame it swept past.
  ///
  /// Pure RELABELLING signal, nothing else: paging the rail is still pure
  /// navigation (see the file header's "Paging the rail is pure NAVIGATION
  /// and never changes the selection" — that guarantee is unchanged by this
  /// callback existing). This must never be wired to a selection or a fetch —
  /// [onSelectDay] remains the only path that does either. It exists solely
  /// so a host showing a month/week LABEL above this rail (`_TopRow` in
  /// `bookings_month_calendar_panel.dart`) can track which week is actually
  /// on screen instead of freezing on whatever week was last SELECTED.
  ///
  /// `null` is accepted (unlike [onSelectDay]) so every pre-existing call
  /// site — including direct `BookingsDayRail(...)` constructions in tests —
  /// keeps compiling without opting in.
  final ValueChanged<DateTime>? onVisibleWeekChanged;

  @override
  State<BookingsDayRail> createState() => _BookingsDayRailState();
}

class _BookingsDayRailState extends State<BookingsDayRail> {
  /// Whether a genuine finger drag has touched the scroll chain since the
  /// rail last settled to idle. Tracked off `ScrollUpdateNotification`, not
  /// `ScrollStartNotification`: `ScrollPosition.beginActivity` only fires
  /// Start/End on an `isScrolling` transition, and a real drag, its ballistic
  /// tail, AND a programmatic `animateToPage`/`jumpToPage` resync are ALL
  /// `isScrolling == true` — so a resync that interrupts an in-flight
  /// ballistic tail is a scrolling→scrolling collapse that fires NEITHER a
  /// new Start NOR an End, leaving a Start-snapshot approach stale.
  /// `ScrollUpdateNotification.dragDetails` has no such gap: it is reliably
  /// non-null on every frame of an actual user-driven drag no matter which
  /// activity preceded it.
  bool _draggedSinceLastSettle = false;

  /// Rounded page the rail last settled on. Seeded from
  /// `widget.controller.initialPage` in [initState] (kept in sync with
  /// [didUpdateWidget] if the controller identity changes) rather than left
  /// `null` until the first `ScrollEndNotification` — see the KNOWN
  /// PRODUCTION DEFECT this fixes, documented on the regression test group
  /// in `bookings_day_rail_test.dart`. A `null` baseline made
  /// `endRounded != _lastSettledPage` trivially true on the very first End
  /// this widget ever saw, so a spring-back as the first-ever interaction on
  /// a fresh mount fired a haptic for a gesture that went nowhere.
  ///
  /// `PageController.initialPage` — not `.page` — because `.page` is `null`
  /// until the controller has clients (i.e. until after the first frame),
  /// whereas `initialPage` is available synchronously in `initState`, before
  /// the `PageView` has attached. It is exactly the page the rail visually
  /// starts on (the host constructs the controller with
  /// `initialPage: railWeekIndex(...)` — see `bookings_discovery_view.dart`),
  /// so diffing the first genuine settle against it still correctly fires a
  /// haptic for a genuine first committed turn from a fresh mount.
  late int _lastSettledPage;

  @override
  void initState() {
    super.initState();
    _lastSettledPage = widget.controller.initialPage;
  }

  @override
  void didUpdateWidget(covariant BookingsDayRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new controller identity means a fresh pager attachment with its own
    // resting page, so the baseline must follow it rather than staying
    // pinned to the OLD controller's start — otherwise the first settle on
    // the new controller would be diffed against a page that has nothing to
    // do with where this rail now actually starts.
    if (!identical(widget.controller, oldWidget.controller)) {
      _lastSettledPage = widget.controller.initialPage;
    }
  }

  /// The rail's page-turn analogue of `bookings_month_calendar_panel.dart`'s
  /// `_onMonthPagerScroll`/`_resolveMonthPage` — same `depth != 0` guard —
  /// but this widget has no selection to resolve (paging the rail is pure
  /// navigation; see the file header), so the only thing it drives is the
  /// haptic cue.
  bool _onRailScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollUpdateNotification) {
      if (notification.dragDetails != null) {
        _draggedSinceLastSettle = true;
      }
    } else if (notification is ScrollEndNotification) {
      final double? endPage = _pageOf(notification.metrics);
      final int? endRounded = endPage?.round();
      // A committed turn only — diffing against the last SETTLED page (not a
      // Start-time snapshot) so a resync that interrupts an in-flight
      // ballistic tail is never misattributed. See [_draggedSinceLastSettle].
      if (_draggedSinceLastSettle &&
          endRounded != null &&
          endRounded != _lastSettledPage) {
        HapticFeedback.selectionClick();
      }
      _draggedSinceLastSettle = false;
      if (endRounded != null) {
        _lastSettledPage = endRounded;
        // Every settle, not gated on `_draggedSinceLastSettle` like the
        // haptic above: a programmatic resync (`_showRailWeekOf`'s
        // jumpToPage/animateToPage) ALSO ends on a `ScrollEndNotification`
        // (see `bookings_day_rail_test.dart`'s haptic CASE 3/3b), and the
        // host's label must stay correct through that path too — a chip tap
        // on a week the rail had drifted away from, or «Сьогодні», both
        // resync the rail programmatically and must not leave the label
        // frozen on the drifted-to week. The host de-dupes on an unchanged
        // month, so this costs nothing when the settle didn't move anything.
        widget.onVisibleWeekChanged?.call(
          railDayAt(widget.firstWeekStart, endRounded * kRailWeekLength),
        );
      }
    }
    return false;
  }

  /// Mirrors `PageMetrics.page` for a bare `ScrollMetrics` — every real
  /// `PageView` notification carries a `PageMetrics`, so the fallback only
  /// guards a metrics type this pager is never actually attached to.
  double? _pageOf(ScrollMetrics metrics) {
    if (metrics is PageMetrics) return metrics.page;
    return metrics.pixels / metrics.viewportDimension;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<String> weekdayShort = _weekdayShorts(l10n);

    return SizedBox(
      // The design's strip is 70dp. It is 78 here because the app's
      // `VelvetText` styles carry line-height multipliers the preview's raw
      // `TextStyle`s did not, so the same three-element column measures ~8dp
      // taller and overflowed the design's height by 17dp under the Phase 17.2
      // overflow guard. The chip's INTERNAL rhythm is unchanged; only the
      // container grew to fit the real type.
      height: kBookingsDayRailHeight,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onRailScroll,
        child: PageView.builder(
          key: const Key('master-bookings-day-rail'),
          // `pageSnapping: false` is NOT "snapping disabled" — it disables
          // only `PageView`'s own internal wiring shortcut. With the default
          // `pageSnapping: true`, `PageView.build` composes
          // `_kPagePhysics.applyTo(widget.physics)` — i.e. it puts STOCK
          // `PageScrollPhysics` on TOP of whatever `physics:` is passed here,
          // burying `LowThresholdPageScrollPhysics` as that stock instance's
          // `parent`. Stock `PageScrollPhysics.createBallisticSimulation`
          // fully reimplements the settle target itself and only ever calls
          // `super.createBallisticSimulation` (walking the parent chain) in
          // the out-of-range early return — for every normal, in-range
          // settle it NEVER reaches `parent.createBallisticSimulation` at
          // all. So with the default `true`, our override was silently
          // DEAD CODE: every settle in the app ran the STOCK 50% threshold,
          // and the whole point of this fix — the paused-release drag —
          // never took effect. Proven by an unconditional `throw` placed as
          // the first line of `createBallisticSimulation`: it never fired
          // through this widget with `pageSnapping` at its default, and
          // fired immediately once set to `false` here.
          // `pageSnapping: false` skips that internal composition and uses
          // `physics:` below directly (still wrapped by `PageView`'s
          // unrelated `_ForceImplicitScrollPhysics`, which does NOT override
          // `createBallisticSimulation` and so delegates to it correctly).
          // `LowThresholdPageScrollPhysics` reimplements the FULL stock
          // snapping contract itself (see its class doc), so the pager still
          // snaps to whole pages exactly as before — only the commit
          // threshold changes, which was the entire intent.
          pageSnapping: false,
          controller: widget.controller,
          // `LowThresholdPageScrollPhysics` (a `PageScrollPhysics`) over
          // `BouncingScrollPhysics` — snapping is the WHOLE contract here (a
          // Wed→Tue resting span is the bug), and the bouncing parent keeps
          // the rubber-band the rail has always had. That rubber-band is
          // also the only "there is more either side" signal a full-bleed
          // pager can give at rest without adding chrome, which the locked
          // design forbids. The lowered commit threshold is the same fix as
          // the month grid's — see `LowThresholdPageScrollPhysics`'s doc.
          physics: const LowThresholdPageScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          itemCount: widget.weekCount,
          itemBuilder: (BuildContext context, int weekIndex) {
            // CALENDAR arithmetic — see the file header. The page index IS
            // the week offset from `firstWeekStart` (see [railWeekIndex],
            // its exact inverse), so the first chip of every page is a
            // Monday by construction rather than by a runtime alignment
            // step.
            final DateTime weekStart = railDayAt(
              widget.firstWeekStart,
              weekIndex * kRailWeekLength,
            );
            return _WeekPage(
              weekStart: weekStart,
              today: widget.today,
              selectedDay: widget.selectedDay,
              bookedDays: widget.bookedDays,
              weekdayShort: weekdayShort,
              onSelectDay: widget.onSelectDay,
              l10n: l10n,
            );
          },
        ),
      ),
    );
  }
}

/// One rail page: seven equal-width day chips, Monday → Sunday.
///
/// Chip width is DERIVED (`Expanded`), never a constant: seven chips at the
/// retired 62dp `itemExtent` is 434dp and would overflow the 320dp
/// narrow-phone floor outright. The horizontal inset matches
/// `MonthCalendar`'s own `VelvetSpacing.lg` self-inset exactly, so these
/// seven slots share a column grid with the expanded month grid and
/// `CalendarWeekdayBar` above it.
class _WeekPage extends StatelessWidget {
  const _WeekPage({
    required this.weekStart,
    required this.today,
    required this.selectedDay,
    required this.bookedDays,
    required this.weekdayShort,
    required this.onSelectDay,
    required this.l10n,
  });

  /// The page's Monday, date-only.
  final DateTime weekStart;
  final DateTime today;
  final DateTime selectedDay;
  final Set<DateTime> bookedDays;
  final List<String> weekdayShort;
  final ValueChanged<DateTime> onSelectDay;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
      child: Row(
        // STRETCH, not the default `center`: it is what hands each chip a
        // TIGHT height, which is in turn what lets [_DayChip]'s `FittedBox`
        // know how much room it has to scale into. Under `center` the chip's
        // height constraint is loose and the column would simply overflow the
        // 70dp strip at a large text scale instead of shrinking to fit.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < kRailWeekLength; i++)
            Expanded(child: _chip(railDayAt(weekStart, i))),
        ],
      ),
    );
  }

  Widget _chip(DateTime d) {
    final String weekday = weekdayShort[d.weekday - 1];
    return _DayChip(
      // The FULL date, not the day-of-month. The rail spans years, so a day
      // number repeats endlessly — a `…-chip-20` key would match January's
      // 20th as readily as July's, and `find.byKey` silently takes the first.
      // That is not merely a test-ergonomics problem: it made a day-selection
      // test assert against 2026-01-20 while believing it had tapped
      // 2026-07-20.
      date: d,
      weekday: weekday,
      selected: selectedDay == d,
      isToday: d == today,
      // `d.isBefore(today)` is false for `d == today` by construction — today
      // is never "past" — but [_DayChip] restates that precedence explicitly
      // rather than leaning on this call site alone. See its doc.
      isPast: d.isBefore(today),
      hasBookings: bookedDays.contains(d),
      onTap: () => onSelectDay(d),
      semanticLabel: l10n.masterBookingsDaySemantics(weekday, d.day),
    );
  }
}

/// One day cell. No background decoration — selection is text colour only;
/// today (unselected) gets an accent underline; a camel dot marks bookings.
///
/// A day strictly before [isPast]'s referent (today), OR a Saturday/Sunday
/// (mobile-backlog D3), reads muted — the weekday caption and day number
/// desaturate to [BrandColors.weekendMuted], a near-neutral warm gray this
/// palette reserves for exactly this ACTIVE de-emphasized state (never a
/// cold blue-gray — see [BrandColors.weekendMuted]'s own doc). Precedence,
/// made explicit rather than left to fall out of evaluation order (encoded
/// once, shared with every other calendar surface, via
/// `calendar_grid.dart`'s `calendarDayIsDeemphasized`):
///   * SELECTED beats past AND weekend. A selected past or weekend day (the
///     master browsing history, or picking a Saturday) must still read as
///     selected — otherwise there is no visual confirmation of what is
///     currently open.
///   * TODAY is never past. [isPast] is `false` for `date == today` by the
///     caller's construction (`d.isBefore(today)`), so this falls out
///     naturally, but it is the reason [isToday]'s bold/underline treatment
///     never has to defend against [isPast] — the two are mutually
///     exclusive by definition, not by a runtime check here. TODAY CAN be a
///     weekend, though — the underline and the muted weekend tone are not
///     mutually exclusive and are expected to compose.
///
/// The has-bookings dot deliberately does NOT mute for past days — it stays
/// full [BrandColors.accent] regardless. The dot's whole job is to make the
/// rail scannable for "where is the work", and that is exactly as true
/// scrolling back through history as it is scrolling forward; muting it
/// would fight the ability to spot a past booked day at a glance.
///
/// ## Fitting seven chips into 320dp at 2.0 text scale
///
/// The chip's INTERNAL rhythm is the design's, unchanged and absolute:
/// a [_kChipIntrinsicWidth]-wide column of caption, [_dayChipCaptionGap],
/// day number, 4dp, dot. What changed with the week pager is that the SLOT
/// is no longer 62dp — it is `(width - 2 * VelvetSpacing.lg) / 7`, i.e.
/// 38.9dp at the 320dp floor, and the column is also ~89dp tall rather than
/// ~55dp once the OS text scale is at 2.0.
///
/// So the rhythm is laid out at its natural size and then scaled as ONE unit
/// by a [BoxFit.scaleDown] `FittedBox`: `scaleDown` never enlarges, so at
/// every width/scale combination that already fits (which includes every
/// pre-existing call site's default 1.0 scale on a ≥368dp screen) the factor
/// is exactly 1.0 and the rendered geometry is byte-identical to before the
/// pager landed. Only the combinations that used to OVERFLOW — narrow widths,
/// large text — shrink, proportionally, instead of clipping or throwing.
///
/// The keyed [GestureDetector] sits OUTSIDE the `FittedBox`, deliberately:
///   * it keeps the tap target the FULL slot (opaque over 38.9 × 70) rather
///     than only the scaled-down glyph column, so a narrow phone does not
///     also get smaller touch targets; and
///   * it keeps `find.byKey(dayChipKey(...))` resolving to a render object
///     with NO transform above it — see mobile-backlog's
///     `project_animatedscale_root_breaks_tap_by_key`, the failure mode where
///     a transform at a keyed widget's root drops it out of the hit-test path.
class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.date,
    required this.weekday,
    required this.selected,
    required this.isToday,
    required this.isPast,
    required this.hasBookings,
    required this.onTap,
    required this.semanticLabel,
  });

  final DateTime date;
  final String weekday;
  final bool selected;
  final bool isToday;

  /// Whether [date] is strictly before today. Never `true` for today itself
  /// — see the class doc's precedence note.
  final bool isPast;
  final bool hasBookings;
  final VoidCallback onTap;
  final String semanticLabel;

  /// Memoised weekday-caption styles, keyed by the resolved colour (mobile-perf
  /// LOW, 2026-07-22).
  ///
  /// [build] used to allocate two `TextStyle`s per chip on EVERY rail rebuild
  /// — and the rail rebuilds on every day selection, every `bookedDays`
  /// resolution and every scroll-driven `ListView` recycle. The permutation
  /// set is CLOSED and tiny: three weekday colours (`accentDeep` selected /
  /// `weekendMuted` past-or-weekend / `textSecondary` ordinary) and three
  /// number colours (`accent` / `weekendMuted` / `text`), so a keyed memo
  /// reaches its ceiling immediately and stops. Same pattern (and same
  /// reasoning) as `master_booking_card.dart`'s
  /// `TimelineStatusDot._decorationsByAccent`.
  ///
  /// Keyed by the RESOLVED colour rather than by the `selected`/`muted`
  /// booleans so it cannot drift from the resolution below if a token is
  /// remapped.
  static final Map<Color, TextStyle> _weekdayStyles = <Color, TextStyle>{};

  /// The day-number style memo. Keyed by `(colour, isToday && !selected)` —
  /// the today-but-unselected flag drives BOTH the weight step (w800 vs w700)
  /// and the accent underline, so it is part of the identity of the style,
  /// not an overlay on it. Six entries maximum (3 colours × 2 states).
  static final Map<(Color, bool), TextStyle> _numberStyles =
      <(Color, bool), TextStyle>{};

  /// The bound on both memos — 3 weekday colours, and 3 number colours × 2
  /// today-states. See [_weekdayStyleFor]'s assert.
  static const int _kWeekdayStyleCount = 3;
  static const int _kNumberStyleCount = 6;

  static TextStyle _weekdayStyleFor(Color color) {
    assert(
      _weekdayStyles.containsKey(color) ||
          _weekdayStyles.length < _kWeekdayStyleCount,
      '_DayChip._weekdayStyles grew past $_kWeekdayStyleCount entries — the '
      'weekday colour set is closed, so this means either a new state shipped '
      '(raise the bound) or a colour is being rebuilt per-instance, which '
      'would make this memo an unbounded leak instead of the fixed table it '
      'is meant to be.',
    );
    return _weekdayStyles.putIfAbsent(
      color,
      () => VelvetText.railWeekday.copyWith(color: color),
    );
  }

  static TextStyle _numberStyleFor(Color color, {required bool todayMark}) {
    assert(
      _numberStyles.containsKey((color, todayMark)) ||
          _numberStyles.length < _kNumberStyleCount,
      '_DayChip._numberStyles grew past $_kNumberStyleCount entries — see '
      '_weekdayStyleFor for why that bound is structural.',
    );
    return _numberStyles.putIfAbsent(
      (color, todayMark),
      () => VelvetText.railDayNumber.copyWith(
        color: color,
        fontWeight: todayMark ? FontWeight.w800 : FontWeight.w700,
        decoration: todayMark ? TextDecoration.underline : TextDecoration.none,
        decorationColor: BrandColors.accent,
        decorationThickness: 1.5,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Selection outranks pastness AND weekend — see the class doc and
    // `calendar_grid.dart`'s file header (mobile-backlog D3). A day is
    // de-emphasized when it's either in the past OR a Saturday/Sunday;
    // [calendarDayIsDeemphasized] is the one place that precedence — SELECTED
    // always wins — is encoded, shared with every other calendar surface.
    final bool muted = calendarDayIsDeemphasized(
      selected: selected,
      deemphasize: isPast || isWeekendWeekday(date.weekday),
    );
    // mobile-security MEDIUM+LOW (calendar-consolidation audit):
    // `BrandColors.muted` (2.69:1 on `BrandColors.base`) fails WCAG AA and,
    // unlike a genuinely disabled calendar-grid cell, WCAG 1.4.3's "inactive
    // component" exemption never covers it — every `_DayChip` stays tappable
    // (`GestureDetector(onTap: onTap, ...)` below is unconditional; scrolling
    // back through PAST days is explicitly the point, see the class doc), so
    // this ACTIVE de-emphasized state (covering both the past-day and the
    // weekend case this one boolean folds together) must clear AA on its
    // own — `BrandColors.weekendMuted` does (5.07:1).
    final Color weekdayColor = selected
        ? BrandColors.accentDeep
        : muted
        ? BrandColors.weekendMuted
        : BrandColors.textSecondary;
    final Color numberColor = selected
        ? BrandColors.accent
        : muted
        ? BrandColors.weekendMuted
        : BrandColors.text;

    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: GestureDetector(
        key: dayChipKey(date),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: FittedBox(
          // Never enlarges (that is what distinguishes `scaleDown` from
          // `contain`), so a slot with room to spare renders the design's own
          // metrics untouched — see the class doc.
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: _kChipIntrinsicWidth,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              // MIN, not the default `max`: the `FittedBox` above needs the
              // column's INTRINSIC height to compute a scale factor from. Left
              // at `max` the column would take the full (tight, 70dp) height
              // it was handed, the factor would always be 1.0 vertically, and
              // a 2.0-text-scale column would overflow exactly as it did
              // before this guard existed.
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(weekday, style: _weekdayStyleFor(weekdayColor)),
                const SizedBox(height: _dayChipCaptionGap),
                Text(
                  '${date.day}',
                  style: _numberStyleFor(
                    numberColor,
                    todayMark: isToday && !selected,
                  ),
                ),
                const SizedBox(height: 4),
                // Always laid out — transparent when there is no booking — so
                // a dot appearing never reflows the column. Deliberately NOT
                // gated on `muted`/`isPast` — see the class doc: the dot stays
                // full accent on a past day so history remains scannable.
                Container(
                  key: hasBookings ? dayDotKey(date) : null,
                  height: 5,
                  width: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // `kCalendarDotColor` — the SAME constant
                    // `CalendarDayCell`'s density dots use (mobile-backlog
                    // D5/D1), so this chip's dot cannot drift from the grid's
                    // even though it stays its own separate widget.
                    color: hasBookings ? kCalendarDotColor : Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
