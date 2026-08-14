// BookingsMonthCalendarPanel — Варіант D («Розгортний місяць»): an
// expandable month calendar layered OVER the existing day rail, replacing
// the master «Записи» screen's old month-switcher + rail arrangement.
//
// Approved design source (transcribed, not re-derived): `docs/signup-designs/
// MasterBookingsCalendar/lib/screens/variant_d_screen.dart` (+
// `widgets/day_rail.dart`, `widgets/month_calendar.dart`,
// `widgets/variant_scaffold.dart`'s `_TopRow`/`_DragHandle` shape). See that
// package's README for the `MonthCalendar` adaptations this panel switches
// on (`composeWeekdayBar` / `sixWeekRows` / `bookingCount` /
// `allowTapOnUnavailable`, plus `showHeader: false` added by this session's
// headerless-grid rework — all opt-in on the SHARED production
// `month_calendar.dart` — `SlotDateScreen` and `MasterSchedulePage` never set
// any of them and render byte-identically to before this panel existed).
//
// ## One source of truth — this widget owns NO date state
//
// [selectedDay] is the only date input. The visible month, the top row's
// label, and the rail's week page (via [railController], driven by the HOST
// through [BookingsDiscoveryView]'s `_showRailWeekOf`) are all derived from
// it. Two things this widget DOES own, both VIEW state the host never
// overrides: [_open], the drag/expand fraction — exactly as the approved
// design locks it, "the expand state is the only thing on the screen not
// derived from the selection" — and [_monthPage], whose resting page is
// itself a pure function of [selectedDay] and is resynced from it in
// [_BookingsMonthCalendarPanelState.didUpdateWidget], so it can hold no
// month the selection does not already imply.
//
// ## The timeline lives INSIDE this widget's subtree (mobile-perf HIGH
// follow-up, this session)
//
// The host used to keep the booking timeline as its OWN `Stack` sibling,
// painted UNDER this panel so the panel could grow over it without forcing a
// relayout — see [kBookingsMonthCalendarPanelCollapsedHeight]'s doc for that
// design's full history. The user rejected the resulting overlay: the
// approved design pushes the list DOWN as the calendar opens, it does not
// draw over it.
//
// Displacement was added WITHOUT reintroducing the relayout coupling by
// moving the composition in here rather than by exposing [_open] to the
// host. [timeline] is built ONCE by the host (a `RepaintBoundary`-wrapped
// subtree, same as before) and handed in as a `child:` — this widget lays it
// out in a `Positioned` box whose geometry (`top`/`left`/`right`/`bottom`)
// never changes, then repositions it EACH FRAME with `Transform.translate`
// inside an `AnimatedBuilder` driven by [_open], the same controller that
// already drives the panel's own visuals. Two widgets sharing one animation
// this way is not the same as leaking state: nothing here ever calls
// `setState` on the host, and the host never constructs, reads, or listens
// to [_open] — it only ever sees the panel's already-composed output. This
// was chosen over exposing [_open] as a `Listenable` the host drives its OWN
// `AnimatedBuilder` from (the alternative this fix was scoped to consider)
// because [_open] does not exist yet at the point the host's `build()`
// constructs its widget tree — it is created in `initState()`, one frame
// layer down — so handing it out would need an extra layer of indirection
// (a notifier-of-a-notifier) for no benefit: the translate only ever needs
// to happen alongside the panel's OWN per-frame visuals work, which already
// lives here. See [_BookingsMonthCalendarPanelState.build] for the resulting
// `Stack`/`Positioned`/`Transform.translate` wiring.
//
// Every tap resolves to exactly one of three callbacks the HOST supplies:
//   * [onSelectRailDay] — a rail-chip tap. The host's EXISTING debounced path
//     (`_BookingsDiscoveryViewState._selectDay`), unchanged by this widget —
//     preserves the 220ms rail-flick debounce.
//   * [onSelectDay] — a grid-cell tap or the «Сьогодні» pill. Both are single
//     deliberate actions, not a rapid-fire source like a rail flick, so the
//     host applies them immediately (`_selectImmediate`).
//   * [onStepMonth] — a resolved month step (a horizontal page turn on the
//     grid), carrying the signed month DELTA. This widget does no date
//     arithmetic of its own beyond deriving [_month] from [selectedDay] — the
//     host computes the actual target day (same day-of-month, clamped to the
//     target month's length) and funnels it through [_selectImmediate].
//
// ## The month+year label is PERMANENT, and the grid has no header of its own
//
// (user-requested, this session — "keep month and year in same place because
// now it disappears".) [_TopRow]'s label used to cross-fade OUT as the panel
// expanded, because `MonthCalendar`'s own `_MonthHeader` took over carrying
// the month name once the grid was legible. That made the one piece of text
// the master navigates by vanish mid-drag and reappear 40dp lower.
//
// It is now rendered unconditionally, in one anchor, at one size, in both
// resting states and every drag fraction between — and `MonthCalendar` is
// composed with `showHeader: false`, so the month name exists exactly ONCE on
// screen. That also retires the ‹ › chevrons outright: the locked requirement
// is "don't add any new buttons", and a horizontal page turn is now the only
// month-navigation mechanism. Two side effects worth naming: the expanded
// panel is 48dp shorter (see [kMonthCalendarExpandedHeight]'s doc), and the
// label is now the ONLY affordance teaching what the grid's horizontal swipe
// does — which is why it must never move.
//
// ## Gesture layering — two pagers, one vertical drag, no arbitration code
//
// The outer `GestureDetector` claims ONLY the vertical axis
// (`HitTestBehavior.deferToChild`); the rail (a horizontal `PageView`) and the
// month grid (another horizontal `PageView`) own the horizontal axis
// themselves. Flutter's gesture arena separates them by DIRECTION — a
// `VerticalDragGestureRecognizer` and a `HorizontalDragGestureRecognizer` in
// one arena each reject as soon as the pointer's dominant axis is the other
// one — so no hand-written arbitration is needed and none exists. This
// replaced a hand-rolled `onHorizontalDrag*` recogniser on the grid that
// accumulated `_swipeDx` and compared it against a distance/velocity pair:
// two competing horizontal paths, neither with real fling physics. The two
// pagers never compete with EACH OTHER either, because they are never both
// interactive: the grid layer is `IgnorePointer(ignoring: t < _kPanelHandoffT)`
// and the rail layer `IgnorePointer(ignoring: t >= _kPanelHandoffT)` — a
// strict-complement pair sharing ONE constant, so every `t` resolves to
// EXACTLY one interactive layer (never zero, never two): rail owns
// `[0, _kPanelHandoffT)`, grid owns `[_kPanelHandoffT, 1]`. mobile-perf
// MEDIUM fix (this session): the opacity curves and the two `ignoring`
// checks used to be tuned independently (rail opacity hit zero at 0.45,
// but stayed hit-testable past 0.5; the grid became hit-testable only at
// 0.5) — for `0.45 < t < 0.5` the rail was invisible yet still swallowed
// every tap/drag aimed at the grid, which was simultaneously non-interactive
// and already ~27-33% visible, and at exactly `t == 0.5` neither `t < 0.5`
// nor `t > 0.5` held so BOTH layers were interactive at once. Both defects
// are gap/overlap bugs from the two `IgnorePointer`s not sharing a single
// flip point; they cannot recur now that both read the same constant.
//
// Every day cell keeps its own `GestureDetector` as a descendant (never
// wrapped by an `AnimatedScale`/`Transform` at ITS root — see mobile-backlog's
// `project_animatedscale_root_breaks_tap_by_key` note), so taps stay
// reachable at every expand fraction; only the collapse/expand `SizedBox`
// height is animated, one level up.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/uk_calendar.dart';

import 'bookings_day_rail.dart';
import 'low_threshold_page_scroll_physics.dart';
import 'month_calendar.dart';

/// The calendar's two resting heights. Every value between is a live drag
/// position, never a state — see [_BookingsMonthCalendarPanelState._open].
const double _kCollapsedHeight = kBookingsDayRailHeight;
const double _kExpandedHeight = kMonthCalendarExpandedHeight;

/// Travel available to the drag, in logical pixels.
const double _kTravel = _kExpandedHeight - _kCollapsedHeight;

/// The panel's total height in its RESTING COLLAPSED state — [_TopRow] +
/// the collapsed rail band + [_DragHandle]. Constant, independent of
/// [_BookingsMonthCalendarPanelState._open].
///
/// mobile-perf HIGH fix (finding #2): the host (`BookingsDiscoveryView`)
/// used to lay this panel out as a non-flex `Column` sibling of the
/// timeline's `Expanded`, so the panel's live-changing height (every drag
/// frame, every settle tick) forced the timeline to relayout in step —
/// `RepaintBoundary` cannot fix this because the coupling is at LAYOUT
/// time, not paint time. Reserving the EXPANDED height instead was
/// considered and rejected: it would leave a permanent ~262dp dead gap
/// above the timeline in the panel's normal resting (collapsed) state,
/// trading a frame-rate win for a constant, highly visible layout
/// regression in the state the master actually lives in.
///
/// The fix, current shape: [timeline] gets a FIXED layout slot sized to
/// this COLLAPSED height (a `Positioned` in [_BookingsMonthCalendarPanelState
/// .build]'s `Stack`, offset by this constant + [VelvetSpacing.sm]) that
/// NEVER changes size during a drag or settle — its box constraints, and
/// therefore its own internal layout and scroll position, stay exactly as
/// stable as if the panel did not exist. Visual displacement — the list
/// moving down as the calendar opens, per the approved design — is done at
/// PAINT time instead: the timeline's `child:` is translated down by
/// `_kTravel * _open.value` with `Transform.translate` inside an
/// `AnimatedBuilder`, clipped to its own fixed box so the moving content
/// never paints over the panel above it or the nav bar below. An earlier
/// revision of this fix instead let the expanding panel draw OVER the
/// timeline rather than displace it, matching the "temporary overlay" framing
/// from the design's own porting note — the user rejected that in favour of
/// genuine displacement, which is what this constant + the `Positioned`/
/// `Transform.translate` pairing now implements.
const double kBookingsMonthCalendarPanelCollapsedHeight =
    kMonthCalendarHeaderHeight + // _TopRow's SizedBox
    2 * VelvetSpacing.xs + // _TopRow's Padding, top + bottom
    _kCollapsedHeight + // the rail band at rest
    4 + // _DragHandle's Padding, top
    4 + // _DragHandle's Container height
    VelvetSpacing.xs; // _DragHandle's Padding, bottom

/// Velocity threshold (logical px/s) above which the expand/collapse drag
/// resolves by direction alone rather than by end position — the approved
/// design's own figure.
const double _kDragFlingVelocity = 320;

/// The single expand-fraction [_open] flips hit-testing between the rail and
/// the grid — see "Gesture layering" above. Matches the rail's own opacity
/// curve (`railOpacity = (1 - t / 0.45).clamp(...)`, fully transparent at
/// `t == 0.45`) so the handoff never leaves the rail hit-testable while
/// invisible, and never leaves the grid hit-testable while it is still
/// mostly transparent (`gridOpacity` is already ~0.27 at this point and
/// rising). Both `IgnorePointer`s below MUST read this one constant as a
/// strict-complement pair (`>=` / `<`) — never two independent literals —
/// or the gap/overlap this constant fixed comes back.
const double _kPanelHandoffT = 0.45;

/// Months the grid's `PageView` spans either side of [BookingsMonthCalendarPanel
/// .today]'s own month — 50 years each way. `PageView.builder` is lazy, so the
/// only cost of a generous span is that a page index stays in range no matter
/// how far the master pages; nothing here is ever built for a month that is
/// not on (or adjacent to) the screen.
const int _kMonthPageSpan = 600;

class BookingsMonthCalendarPanel extends StatefulWidget {
  const BookingsMonthCalendarPanel({
    super.key,
    required this.railController,
    required this.railFirstWeekStart,
    required this.weekCount,
    required this.today,
    required this.selectedDay,
    required this.bookedDays,
    required this.onSelectRailDay,
    required this.onSelectDay,
    required this.onStepMonth,
    required this.timeline,
  });

  /// Drives which WEEK the collapsed rail shows. Owned (and paged) by the
  /// host — see [BookingsDayRail.controller].
  final PageController railController;

  /// The Monday the rail's first week page starts on. Threaded through rather
  /// than computed here, mirroring [BookingsDayRail]'s own parameter — the
  /// host owns the rail's span.
  final DateTime railFirstWeekStart;

  /// Number of rail week pages. Same threading rationale as
  /// [railFirstWeekStart].
  final int weekCount;

  final DateTime today;

  /// The ONLY date input — see the file header. Always set; there is no
  /// «Всі» / null-day state (Phase 7.11).
  final DateTime selectedDay;

  /// Filter-independent booked-day set (`bookedDaysProvider`) — feeds BOTH
  /// the rail's dots and the grid's density dots, unchanged source. The grid
  /// renders one dot per booked day (not a real per-day count — this set
  /// only carries membership, exactly like the rail's own single dot), per
  /// the approved design's porting note: "extend it to counts, or keep one
  /// dot."
  final Set<DateTime> bookedDays;

  /// A rail-chip tap — routes through the host's existing debounced path.
  final ValueChanged<DateTime> onSelectRailDay;

  /// A grid-cell tap or the «Сьогодні» pill — applied immediately.
  final ValueChanged<DateTime> onSelectDay;

  /// A resolved month step, as a signed month DELTA (`-1` previous, `1` next;
  /// a multi-page fling can resolve to a larger magnitude and the host's own
  /// `_stepMonth` handles any value). Never fires with `0`.
  final ValueChanged<int> onStepMonth;

  /// The booking timeline, built ONCE by the host — see the file header's
  /// "the timeline lives INSIDE this widget's subtree" section. Passed
  /// through as an `AnimatedBuilder` `child:`, so it is never rebuilt by a
  /// drag frame or the open/close settle; only its paint position moves.
  final Widget timeline;

  @override
  State<BookingsMonthCalendarPanel> createState() =>
      _BookingsMonthCalendarPanelState();
}

class _BookingsMonthCalendarPanelState extends State<BookingsMonthCalendarPanel>
    with SingleTickerProviderStateMixin {
  /// 0 = rail, 1 = full month. Every value in between is a live drag
  /// position, which is why this is an [AnimationController] driven by hand
  /// rather than a bool with an implicit animation — see the approved
  /// design's own `_open` doc. Confined entirely to THIS widget's subtree:
  /// nothing here ever calls `setState` on the host
  /// (`_BookingsDiscoveryViewState`), so a drag frame — or the 280ms settle
  /// animation — never rebuilds the timeline below. That is how this port
  /// achieves the retired `_focusedMonth` ValueNotifier's rebuild-scoping
  /// goal WITHOUT it: the isolation now comes from the animation living
  /// inside a separate widget/State, not from withholding a real selection
  /// change. A genuine month STEP (a settled horizontal page turn) DOES
  /// change the host's `_day` and therefore its query — which correctly
  /// rebuilds the timeline once, for the new day's data. That is required
  /// behaviour under the new "month step selects" contract, not a
  /// regression of the old label-only optimisation.
  late final AnimationController _open;

  /// The grid's month pager. Like [_open] this is a VIEW object, not date
  /// state: its resting page is always `_pageForMonth(_month)`, i.e. a pure
  /// function of [BookingsMonthCalendarPanel.selectedDay], and the two are
  /// kept in lockstep from both directions ([_onMonthPageChanged] pushes a
  /// user page turn OUT to the host as a selection; [didUpdateWidget] pulls
  /// any OTHER selection change — a rail tap, «Сьогодні» — back IN as a page
  /// jump). Nothing here ever remembers a month the selection does not
  /// already imply, which is what keeps the file header's "this widget owns
  /// NO date state" invariant true.
  late final PageController _monthPage;

  /// The month page index space's origin — [BookingsMonthCalendarPanel.today]'s
  /// month. Captured once: `today` is itself captured once by the host
  /// (`_BookingsDiscoveryViewState._today`) and never changes for this
  /// widget's lifetime, so a stored anchor cannot drift from a rebuilt one,
  /// and page indices stay stable across every rebuild.
  late final DateTime _anchorMonth;

  /// True from the instant the month pager's viewport starts moving until it
  /// has come completely to rest — the whole gesture INCLUDING the ballistic
  /// settle, not just the pointer-down window.
  ///
  /// mobile-perf HIGH fix (finding #1, secondary risk): [didUpdateWidget]
  /// resyncs the pager with `jumpToPage`, and `ScrollPositionWithSingleContext
  /// .jumpTo` opens with `goIdle()` — so a selection change arriving from the
  /// host mid-drag (a second pointer on «Сьогодні», a rail tap racing the
  /// gesture) would kill the master's live drag under their finger. While
  /// this flag is set the pull-IN half of the two-way sync stands down; the
  /// push-OUT half then repairs the desync for free, because
  /// [_resolveMonthPage] computes its delta against the CURRENT [_month] at
  /// settle time, so wherever the gesture lands becomes the selection. The
  /// pager can therefore never be left holding a month the host disagrees
  /// with — it is the pager that wins, one frame later, instead of the
  /// gesture being cancelled.
  bool _monthPagerScrolling = false;

  /// Whether the month pager's PAGE CONTENT (the real [MonthCalendar] grids)
  /// is mounted. False whenever the panel is fully collapsed.
  ///
  /// mobile-perf LOW fix (finding #3): a month grid is 31 keyed `_DayCell`s,
  /// each an `AnimatedContainer` — a `State`, an `AnimationController` and a
  /// `Ticker` apiece. `RenderOpacity` skips PAINT at α=0 but never build or
  /// layout, so at rest — the state the master actually lives in — every day
  /// tap and every `bookedDaysProvider` emission paid for a grid nobody could
  /// see.
  ///
  /// ⚠ WHY THE GATE IS ON THE CONTENT AND NOT ON THE PAGER. `Offstage` /
  /// `Visibility(visible: false)` / dropping the `PageView` itself all skip
  /// LAYOUT, which detaches [_monthPage] — `hasClients` goes false, `page`
  /// returns null, and [didUpdateWidget]'s early return then silently strands
  /// the pager on a stale month until the master pages by hand. This gate
  /// swaps only the per-page CHILD for a `SizedBox.shrink()`; the `PageView`,
  /// its viewport and its attached [_monthPage] stay mounted and laid out at
  /// every expand fraction, so `hasClients`/`page` are exactly as valid at
  /// rest as when expanded and the existing sync path needs no resync hook at
  /// all. Stranding is not handled — it is unreachable.
  bool _gridContentMounted = false;

  @override
  void initState() {
    super.initState();
    _open = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    // Flips [_gridContentMounted] on the 0 ↔ >0 boundary only — twice per
    // open/close cycle, not once per drag frame. The `setState` it issues is
    // confined to THIS `State`; the host is never rebuilt, which is what
    // `bookings_month_calendar_panel_test.dart` pins.
    _open.addListener(_onOpenChanged);
    _anchorMonth = DateTime(widget.today.year, widget.today.month);
    _monthPage = PageController(initialPage: _pageForMonth(_month));
  }

  void _onOpenChanged() {
    final bool next = _open.value > 0;
    if (next == _gridContentMounted) return;
    setState(() => _gridContentMounted = next);
  }

  @override
  void didUpdateWidget(covariant BookingsMonthCalendarPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only a selection change that crossed a MONTH boundary can desync the
    // pager — a rail tap inside the visible month must not jolt the grid.
    final DateTime previous = DateTime(
      oldWidget.selectedDay.year,
      oldWidget.selectedDay.month,
    );
    if (previous == _month || !_monthPage.hasClients) return;
    // Never yank the pager out from under a live gesture — see
    // [_monthPagerScrolling]'s doc for why standing down here cannot strand
    // the pager.
    if (_monthPagerScrolling) return;
    final int target = _pageForMonth(_month);
    // Already there — this is the echo of the user's OWN page turn coming
    // back through the host, so re-jumping would fight the settle animation.
    if ((_monthPage.page ?? target.toDouble()).round() == target) return;
    // `jumpToPage`, not `animateToPage`: the grid is usually invisible when
    // this fires (a rail tap happens with the panel collapsed), and an
    // animation the master cannot see is a frame budget spent on nothing.
    _monthPage.jumpToPage(target);
  }

  @override
  void dispose() {
    _monthPage.dispose();
    _open.removeListener(_onOpenChanged);
    _open.dispose();
    super.dispose();
  }

  /// Derived, never stored — the invariant this whole port is about.
  DateTime get _month =>
      DateTime(widget.selectedDay.year, widget.selectedDay.month);

  /// Months since year 0, so month arithmetic is plain integer arithmetic.
  static int _monthOrdinal(DateTime m) => m.year * 12 + (m.month - 1);

  /// [month]'s index in the grid pager. Clamped defensively: 600 months
  /// either side of [_anchorMonth] is 50 years, so a real master can never
  /// reach the edge, but `jumpToPage` asserts on an out-of-range index and a
  /// corrupt selection must not crash the screen.
  int _pageForMonth(DateTime month) =>
      (_monthOrdinal(month) - _monthOrdinal(_anchorMonth) + _kMonthPageSpan)
          .clamp(0, _kMonthPageCount - 1);

  DateTime _monthForPage(int page) => DateTime(
    _anchorMonth.year,
    _anchorMonth.month + (page - _kMonthPageSpan),
  );

  static const int _kMonthPageCount = 2 * _kMonthPageSpan + 1;

  void _toggle() {
    if (_open.value > 0.5) {
      _open.animateBack(0, curve: Curves.easeOutCubic);
    } else {
      _open.animateTo(1, curve: Curves.easeOutCubic);
    }
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _open.value = (_open.value + d.primaryDelta! / _kTravel).clamp(0.0, 1.0);
  }

  /// Velocity-aware settle: a decisive flick wins over position, a slow
  /// release falls to whichever end it is nearer.
  void _onDragEnd(DragEndDetails d) {
    final double v = d.primaryVelocity ?? 0;
    if (v.abs() > _kDragFlingVelocity) {
      if (v > 0) {
        _open.animateTo(1, curve: Curves.easeOut);
      } else {
        _open.animateBack(0, curve: Curves.easeOut);
      }
      return;
    }
    if (_open.value > 0.5) {
      _open.animateTo(1, curve: Curves.easeOut);
    } else {
      _open.animateBack(0, curve: Curves.easeOut);
    }
  }

  /// The month pager's scroll lifecycle — the ONE place a month step is
  /// resolved now that the grid's ‹ › chevrons are retired.
  ///
  /// ## Why a `ScrollEndNotification` and not `onPageChanged`
  ///
  /// mobile-perf HIGH fix (finding #1). `PageView.onPageChanged` does NOT
  /// fire on settle — it fires on every page-MIDPOINT CROSSING during the
  /// drag itself (`page_view.dart`: a `ScrollUpdateNotification` handler
  /// comparing `metrics.page.round()` against the last reported index). A
  /// month step SELECTS (see [BookingsMonthCalendarPanel.onStepMonth]), and
  /// the host applies a selection through `_selectImmediate`, which
  /// explicitly CANCELS the 220ms rail debounce — so it is not rate-limited
  /// by anything. One hesitant back-and-forth drag was measured emitting
  /// `[1, -1, 1, -1]` and ending on the month it started from: four
  /// selections, four `GET /bookings/me`, four `effectiveSchedule` fetches,
  /// and a visibly flickering month label, for a gesture that navigated
  /// nowhere. The hand-rolled `onHorizontalDrag*` recogniser this pager
  /// replaced fired at most once per gesture, so that was a regression, and a
  /// correctness one as much as a perf one — days the master never chose were
  /// being selected.
  ///
  /// `ScrollEndNotification` fires exactly once per gesture, at the end of
  /// the BALLISTIC settle: `ScrollPosition.beginActivity` calls
  /// `didEndScroll()` only on the transition from a scrolling activity to a
  /// non-scrolling one, and drag → ballistic is scrolling → scrolling. So one
  /// settled gesture is one `onStepMonth`, whatever route the finger took to
  /// get there, and the month lands where the gesture actually ended.
  ///
  /// `depth != 0` is dropped so a scrollable INSIDE a month page could never
  /// be mistaken for the pager itself.
  bool _onMonthPagerScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification) {
      _monthPagerScrolling = true;
    } else if (notification is ScrollEndNotification) {
      _monthPagerScrolling = false;
      _resolveMonthPage();
    }
    return false;
  }

  /// Turns the pager's settled page into a SELECTION, not merely a relabel:
  /// `onStepMonth` reaches the host's `_stepMonth`, which picks the same
  /// day-of-month in the target month (clamped to its length) and applies it
  /// through `_selectImmediate`. That is the locked "month stepping selects"
  /// contract this whole port exists to hold — pinned end-to-end by
  /// `integration_test/master_bookings_month_step_flow_test.dart`.
  ///
  /// The `delta == 0` early return is what makes the two-way sync loop-free:
  /// `ScrollPositionWithSingleContext.jumpTo` dispatches its own
  /// `didEndScroll()`, so the PROGRAMMATIC `jumpToPage` in [didUpdateWidget]
  /// reaches this method too — but it jumps to exactly `_pageForMonth(_month)`
  /// with `_month` already updated, so the delta is arithmetically guaranteed
  /// to be zero and no second selection is ever bounced back at the host.
  void _resolveMonthPage() {
    final double? page = _monthPage.hasClients ? _monthPage.page : null;
    if (page == null) return;
    final int delta = page.round() - _pageForMonth(_month);
    if (delta == 0) return;
    widget.onStepMonth(delta);
  }

  /// Accessibility state word for the composed grid's day cells — see
  /// [MonthCalendar.stateLabelResolver]'s doc for why the slot-picker's own
  /// "available"/"unavailable" wording cannot be reused here: [isAvailable]
  /// below means "not in the past", not "has bookable slots".
  String _stateLabel(
    AppLocalizations l10n, {
    required bool available,
    required bool selected,
  }) {
    if (selected) return l10n.bookingSelectedState;
    if (!available) return l10n.bookingsCalendarPastDayState;
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String monthLabel =
        '${monthNominative(widget.selectedDay.month)} '
        '${widget.selectedDay.year}';

    return Stack(
      children: <Widget>[
        // The timeline's FIXED layout slot — see
        // [kBookingsMonthCalendarPanelCollapsedHeight]'s doc. `top`/`left`/
        // `right`/`bottom` never change with `_open`, so this box's
        // constraints — and the timeline's own internal layout and scroll
        // position — are exactly as stable as if the panel did not exist.
        // Displacement is done at PAINT time only, inside the `ClipRect`:
        // the `Transform.translate` moves the already-laid-out content down
        // by `_kTravel * _open.value`, tracking the panel's own growing
        // bottom edge exactly (see `_toggle`'s sibling constants). The
        // `ClipRect` keeps the translated content from painting past this
        // box's own bounds — over the panel above, or below the screen —
        // regardless of the ancestor `Stack`'s own `clipBehavior`.
        Positioned(
          top: kBookingsMonthCalendarPanelCollapsedHeight + VelvetSpacing.sm,
          left: 0,
          right: 0,
          bottom: 0,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _open,
              builder: (BuildContext context, Widget? child) {
                return Transform.translate(
                  offset: Offset(0, _kTravel * _open.value),
                  child: child,
                );
              },
              child: widget.timeline,
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.deferToChild,
            onVerticalDragUpdate: _onDragUpdate,
            onVerticalDragEnd: _onDragEnd,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _TopRow(
                  label: monthLabel,
                  open: _open,
                  onToggle: _toggle,
                  todayActive: widget.selectedDay == widget.today,
                  onToday: () => widget.onSelectDay(widget.today),
                  l10n: l10n,
                ),
                // mobile-perf HIGH fix (finding #1): the two heavy subtrees
                // below — the 42-cell [MonthCalendar] grid and
                // [BookingsDayRail] — used to be constructed INSIDE this
                // builder closure, so every drag frame and every tick of the
                // 280ms settle tore both down and rebuilt them from scratch.
                // They now live behind their OWN nested `AnimatedBuilder`s
                // (below), each built ONCE here and passed through via
                // `child:` — mirroring [_TopRow]/[_DragHandle], which already
                // used this pattern. THIS outer builder only resizes the
                // collapse/expand [SizedBox] per frame; the `Stack` itself,
                // and everything under it, is the single `child` instance
                // reused across every tick.
                AnimatedBuilder(
                  animation: _open,
                  builder: (BuildContext context, Widget? child) {
                    final double t = _open.value;
                    return ClipRect(
                      child: SizedBox(
                        key: const Key('bookings-month-calendar'),
                        height: _kCollapsedHeight + _kTravel * t,
                        child: child,
                      ),
                    );
                  },
                  child: Stack(
                    children: <Widget>[
                      // The month is laid out at full height and revealed by
                      // the clip, so it slides out from under the top row
                      // instead of being squashed into the gap.
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: _kExpandedHeight,
                        child: AnimatedBuilder(
                          animation: _open,
                          // Overlapping cross-fade — the rail is gone by 0.45
                          // and the month is already legible by then, so no
                          // frame reads as an empty strip. Only this thin
                          // IgnorePointer/Opacity wrapper reads `_open.value`
                          // per frame; `child` (the grid) is built once
                          // below.
                          builder: (BuildContext context, Widget? child) {
                            final double t = _open.value;
                            final double gridOpacity = ((t - 0.25) / 0.75)
                                .clamp(0.0, 1.0);
                            return IgnorePointer(
                              key: const Key(
                                'bookings-month-calendar-grid-layer',
                              ),
                              ignoring: t < _kPanelHandoffT,
                              child: Opacity(
                                opacity: gridOpacity,
                                child: child,
                              ),
                            );
                          },
                          child: _monthPager(l10n),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: _kCollapsedHeight,
                        child: AnimatedBuilder(
                          animation: _open,
                          builder: (BuildContext context, Widget? child) {
                            final double t = _open.value;
                            final double railOpacity = (1 - t / 0.45).clamp(
                              0.0,
                              1.0,
                            );
                            return IgnorePointer(
                              key: const Key(
                                'bookings-month-calendar-rail-layer',
                              ),
                              ignoring: t >= _kPanelHandoffT,
                              child: Opacity(
                                opacity: railOpacity,
                                child: child,
                              ),
                            );
                          },
                          child: BookingsDayRail(
                            controller: widget.railController,
                            firstWeekStart: widget.railFirstWeekStart,
                            weekCount: widget.weekCount,
                            today: widget.today,
                            selectedDay: widget.selectedDay,
                            bookedDays: widget.bookedDays,
                            onSelectDay: widget.onSelectRailDay,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _DragHandle(open: _open, onTap: _toggle, l10n: l10n),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The month pager — one headerless [MonthCalendar] per page, snapping one
  /// month per horizontal swipe in either direction.
  ///
  /// A `PageView` rather than the hand-rolled `onHorizontalDrag*` recogniser
  /// it replaces: fling velocity, partial-drag rubber-band, mid-drag reversal
  /// and the settle animation all come from `PageScrollPhysics` for free,
  /// where the old code approximated exactly one of those four with a
  /// distance/velocity threshold pair and snapped instantly with no
  /// transition at all.
  Widget _monthPager(AppLocalizations l10n) {
    final int currentPage = _pageForMonth(_month);
    return NotificationListener<ScrollNotification>(
      onNotification: _onMonthPagerScroll,
      child: PageView.builder(
        key: const Key('bookings-month-calendar-grid'),
        controller: _monthPage,
        // `pageSnapping: false` — REQUIRED for `LowThresholdPageScrollPhysics`
        // to run at all, not merely a tuning knob. With the default `true`,
        // `PageView.build` composes `_kPagePhysics.applyTo(widget.physics)` —
        // i.e. it puts STOCK `PageScrollPhysics` on TOP of whatever
        // `physics:` is passed, burying our subclass as that stock
        // instance's `parent`. Stock `PageScrollPhysics.createBallisticSimulation`
        // fully reimplements the settle target itself and only ever calls
        // `super.createBallisticSimulation` (walking the parent chain) in
        // the out-of-range early return — every normal in-range settle
        // never reaches `parent.createBallisticSimulation` at all. So at the
        // default, our override was silent dead code: every settle ran the
        // STOCK 50% threshold and the paused-release fix never took effect.
        // Proven by an unconditional `throw` placed as the first line of
        // `createBallisticSimulation`: it never fired against this pager
        // with `pageSnapping` at its default, and fired immediately once set
        // to `false`. `LowThresholdPageScrollPhysics` reimplements the FULL
        // stock snapping contract itself (see its class doc), so the grid
        // still snaps to whole months exactly as before — only the commit
        // threshold changes, which was the entire intent of this fix.
        pageSnapping: false,
        // `BouncingScrollPhysics` parent unchanged: its rubber-band only
        // applies out of range, which a mid-span drag never is.
        physics: const LowThresholdPageScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        itemCount: _kMonthPageCount,
        // No `onPageChanged:` — see [_onMonthPagerScroll]'s doc. It fires on
        // every midpoint crossing DURING the drag, which made a single
        // hesitant gesture select (and fetch) four times over.
        itemBuilder: (BuildContext context, int page) {
          // The collapsed panel's grid is invisible (`Opacity(0)`) and
          // unreachable (`IgnorePointer`), so its 31 `AnimatedContainer` day
          // cells are built and laid out for nothing — see
          // [_gridContentMounted], including why the gate is here on the
          // CONTENT rather than on the `PageView` above it.
          if (!_gridContentMounted) return const SizedBox.shrink();
          final DateTime month = _monthForPage(page);
          // A `PageView` keeps NO cache extent at rest — `page_view.dart`
          // sets `cacheExtent: allowImplicitScrolling ? 1.0 : 0.0` and
          // `allowImplicitScrolling` defaults to `false` — so exactly one
          // month is alive between gestures. DURING A DRAG, though, two (and
          // momentarily three) months straddle the viewport and are all
          // built. That is fine for paint but not for accessibility: several
          // months of `booking-calendar-day-N` nodes in the semantics tree
          // would have a screen reader announce days that are not visible,
          // several times over, with colliding labels. Only the month the
          // selection actually names is ever exposed.
          return ExcludeSemantics(
            excluding: page != currentPage,
            child: MonthCalendar(
              key: ValueKey<int>(page),
              visibleMonth: month,
              today: widget.today,
              selected: widget.selectedDay,
              composeWeekdayBar: true,
              sixWeekRows: true,
              // User request (this session): the weekend cue on this
              // EXPANDED calendar moves from the muted day number to a
              // whole-column tinted band — see `MonthCalendar
              // .showWeekendColumnBand`'s doc.
              showWeekendColumnBand: true,
              // No header, no ‹ › chevrons — the month+year lives in `_TopRow`
              // permanently now and paging is the only navigation. See the file
              // header and [MonthCalendar.showHeader].
              showHeader: false,
              // ⚠ The one behavioural adaptation — every day stays tappable.
              // See [MonthCalendar.allowTapOnUnavailable]'s doc: the rail
              // directly underneath this grid already lets the master open any
              // past day, so refusing the tap here would make the two halves of
              // one control disagree.
              allowTapOnUnavailable: true,
              isAvailable: (DateTime d) => !d.isBefore(widget.today),
              bookingCount: (DateTime d) =>
                  widget.bookedDays.contains(d) ? 1 : 0,
              stateLabelResolver:
                  ({required bool available, required bool selected}) =>
                      _stateLabel(
                        l10n,
                        available: available,
                        selected: selected,
                      ),
              onSelectDay: widget.onSelectDay,
            ),
          );
        },
      ),
    );
  }
}

/// The row above the calendar: month + year with a dropdown chevron, and the
/// «Сьогодні» pill.
///
/// ## The label never moves and never fades (user-requested, this session)
///
/// It used to be wrapped in `if (t < 0.45) Opacity(...)`, cross-fading out as
/// the panel expanded because [MonthCalendar]'s own header took the month name
/// over at 40dp lower. The master's complaint was exactly that: the one label
/// they navigate by disappeared the moment they opened the thing they were
/// navigating.
///
/// It is now unconditional — same anchor, same [VelvetText.monthSwitcherLabel],
/// same baseline, at every value of [open] — and the grid is composed with
/// `showHeader: false`, so this is the SINGLE month readout on the screen.
/// With months now changing by a horizontal page turn rather than a tapped
/// chevron, a permanently-visible label is also the only thing that tells the
/// master the swipe landed, which is a second, independent reason it cannot
/// be allowed to animate.
///
/// Only the dropdown chevron reads [open] now, so only IT sits inside an
/// `AnimatedBuilder` — the label subtree is built once per real month change
/// and never per drag frame.
class _TopRow extends StatelessWidget {
  const _TopRow({
    required this.label,
    required this.open,
    required this.onToggle,
    required this.todayActive,
    required this.onToday,
    required this.l10n,
  });

  final String label;
  final Animation<double> open;
  final VoidCallback onToggle;
  final bool todayActive;
  final VoidCallback onToday;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.lg,
        vertical: VelvetSpacing.xs,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Semantics(
              button: true,
              label: l10n.bookingsMonthCalendarToggleSemantics(label),
              child: GestureDetector(
                key: const Key('bookings-month-calendar-toggle'),
                behavior: HitTestBehavior.opaque,
                onTap: onToggle,
                child: SizedBox(
                  height: kMonthCalendarHeaderHeight,
                  child: Row(
                    children: <Widget>[
                      // Unconditional, un-faded, un-translated — see the
                      // class doc. `Flexible` + ellipsis so a long month name
                      // at a large text scale yields to the chevron beside it
                      // instead of overflowing the row.
                      Flexible(
                        child: Text(
                          label,
                          key: const Key('bookings-month-calendar-label'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: VelvetText.monthSwitcherLabel,
                        ),
                      ),
                      const SizedBox(width: VelvetSpacing.xs),
                      AnimatedBuilder(
                        animation: open,
                        // `child:` — the icon itself is constant; only the
                        // rotation reads the animation, so a drag frame
                        // rebuilds one `Transform`, never the label above.
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 22,
                          color: BrandColors.accentDeep,
                        ),
                        builder: (BuildContext context, Widget? child) {
                          return Transform.rotate(
                            angle: open.value * math.pi,
                            child: child,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: VelvetSpacing.sm),
          _TodayPill(
            onTap: onToday,
            active: todayActive,
            label: l10n.scheduleTodayAction,
          ),
        ],
      ),
    );
  }
}

/// The «Сьогодні» pill. Renders already-pressed (inset) when the selection
/// IS today, so it doubles as a state readout — the approved design's
/// `SoftPill(active:)` behaviour, ported onto production's own bordered pill
/// shape (`_TodayButton`, pre-port): `NeumorphicShadows.extrudedSmall` is
/// deliberately NOT used for the raised state — this codebase's own
/// Impeller white-corner-wedge fix specifically targets an offset,
/// near-white extruded shadow on a rounded-rect/circle surface, which the
/// bordered recipe (`VelvetShadows.borderedButton` + a hairline border)
/// avoids. The pressed/active state uses `NeumorphicInset` instead — an
/// INSET (inward) shadow, already used throughout this feature
/// (`month_calendar.dart`'s `_MonthChevron`/trough) with no such artifact.
class _TodayPill extends StatelessWidget {
  const _TodayPill({
    required this.onTap,
    required this.active,
    required this.label,
  });

  final VoidCallback onTap;
  final bool active;
  final String label;

  static final BoxDecoration _raisedDecoration = BoxDecoration(
    color: BrandColors.base,
    borderRadius: BorderRadius.circular(VelvetRadii.pill),
    boxShadow: VelvetShadows.borderedButton,
    border: Border.all(color: BrandColors.accent.withValues(alpha: 0.18)),
  );

  @override
  Widget build(BuildContext context) {
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.sm + 2,
        vertical: 6,
      ),
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
    );

    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        key: const Key('master-bookings-today'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 32,
          child: active
              ? NeumorphicInset(
                  radius: VelvetRadii.pill,
                  child: Center(child: content),
                )
              : DecoratedBox(
                  decoration: _raisedDecoration,
                  child: Center(child: content),
                ),
        ),
      ),
    );
  }
}

/// The grab bar under the calendar. It is a second surface for the same
/// vertical drag (the recogniser lives on the parent), plus a tap target,
/// plus the only always-visible hint that the strip pulls down at all.
class _DragHandle extends StatelessWidget {
  const _DragHandle({
    required this.open,
    required this.onTap,
    required this.l10n,
  });

  final Animation<double> open;
  final VoidCallback onTap;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: l10n.bookingsMonthCalendarHandleSemantics,
      child: GestureDetector(
        key: const Key('bookings-month-calendar-handle'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: VelvetSpacing.xs),
          child: AnimatedBuilder(
            animation: open,
            builder: (BuildContext context, Widget? _) {
              // The bar widens as the month opens — a small, honest readout
              // of how far the drag has travelled.
              return Container(
                width: 34 + 16 * open.value,
                height: 4,
                decoration: BoxDecoration(
                  color: Color.lerp(
                    BrandColors.faint,
                    BrandColors.accent,
                    open.value,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
