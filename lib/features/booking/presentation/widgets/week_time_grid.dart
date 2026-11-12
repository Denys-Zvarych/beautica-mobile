// Phase 482 — WeekTimeGrid: the master's week as seven Kyiv day columns on
// ONE horizontal pager. Port of the MasterWeekBookings preview
// (`docs/signup-designs/MasterWeekBookings/lib/widgets/week_time_grid.dart`),
// pager / geometry half (phase 482) plus phase 483: off-hours / break /
// day-off hatching ([WeekColumnPainter]), the «Перерва» / «Вихідний» band
// labels, the per-day hours line under each header ([WeekDayHeader]) and the
// EXPLICIT_TIMES column (free declared times as `FreeTimeCard(column: true)`
// markers in «3 дні», the shipped [DeclaredTimeCards] list in «День»).
//
// Touch only: the preview's desktop `AnyPointerScrollBehavior` /
// `dragDevices` and its mouse / wheel paths are NOT ported.
//
// Geometry is the single-day `BookingsTimelineGrid`'s, read from the shared
// `timeline_geometry.dart`: card top = `(start − origin) / 60 × hourHeight`,
// hour hairlines in `faint`, half-hour hairlines at
// [BookingsTimelineGrid.halfHourLineColor], the ruler is the shipped
// [TimelineHourRuler] and the band sits [TimelineHourRuler
// .labelCenteringNudge] below the ruler's origin exactly as there.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart'
    show WorkInterval;
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart'
    show formatSlotTime;

import '../../domain/booking.dart';
import '../../domain/week_day_model.dart';
import 'bookings_day_rail.dart' show weekdayShortLabels;
import 'day_snap_scroll_physics.dart';
import 'declared_time_cards.dart';
import 'forwarded_scroll_drag.dart';
import 'master_booking_card.dart';
import 'timeline_density.dart';
import 'timeline_geometry.dart';
import 'timeline_hour_ruler.dart';
import 'week_column_painter.dart';

/// The week time grid: Mon–Sun as seven day columns on ONE horizontal pager,
/// [visibleColumns] of them on screen (3 for «3 дні», 1 for «День»). The
/// hour ruler on the left is pinned horizontally; the vertical scroll is ONE
/// scroll view shared by the ruler and every column, so hours always line up
/// across days. The column-header row is pinned above and follows the pager.
class WeekTimeGrid extends StatefulWidget {
  const WeekTimeGrid({
    required this.weekStart,
    required this.days,
    required this.today,
    required this.now,
    required this.pageController,
    required this.visibleColumns,
    required this.onBookingTap,
    required this.onTapHeader,
    required this.showsAllOccupancy,
    this.hourHeight,
    this.entrance,
    this.onTapEmpty,
    this.nowListenable,
    this.topMinute,
    super.key,
  }) : assert(
         visibleColumns == 1 || visibleColumns == 3,
         'visibleColumns is 3 («3 дні») or 1 («День»)',
       ),
       assert(days.length == kWeekGridDays, 'a week has seven days');

  /// The Monday date token of the shown week.
  final DateTime weekStart;

  /// Seven columns, Monday first (`buildWeekDays`).
  final List<WeekDayModel> days;

  /// The Kyiv date token of today — the now-line column, if in this week.
  final DateTime today;

  /// The current INSTANT (from `clockProvider`) — positions the now-line and
  /// gates the cards' own time-dependent affordances.
  final DateTime now;

  /// Owned by the screen (the week strip reads `page` from it). Build it with
  /// [WeekTimeGrid.controllerFor] so its `viewportFraction` matches
  /// [visibleColumns].
  final PageController pageController;

  /// 3 («3 дні») or 1 («День»).
  final int visibleColumns;

  /// Tap on a booking card.
  final ValueChanged<Booking> onBookingTap;

  /// Tap on a column header — index into [days] (0 = Monday).
  final ValueChanged<int> onTapHeader;

  /// Whether the week's bookings contain EVERY booking that occupies the
  /// master's clock — i.e. the query carries no status / service filter that
  /// could hide one (`BookingsDayQuery.showsAllOccupancy`'s predicate) AND
  /// the week was not truncated. CONTRACT: the caller passes
  /// `query.showsAllOccupancy && !state.isTruncated` — a truncated week
  /// (`BookingsWeekState.isTruncated`) has lost its late bookings, so a time
  /// they occupy would otherwise render as a false «Вільно». When
  /// `false` an EXPLICIT_TIMES day shows no «Вільно» marker: a free marker is
  /// a claim the list can no longer back (see `declared_time_cards.dart`'s
  /// "FREE CARDS ARE A CLAIM"). Required, never defaulted — a default of
  /// `true` would fail open.
  final bool showsAllOccupancy;

  /// One hour of vertical space; `null` = [hourHeightFor] (72 dp × text scale
  /// in «3 дні», the shipped 120 dp in «День»).
  final double? hourHeight;

  /// The one orchestrated load moment — 0→1 drives a column-staggered rise.
  /// Ignored under `MediaQuery.disableAnimations` (reduced motion).
  final Animation<double>? entrance;

  /// Phase 485 — a tap on free grid space (not on a card): the column's Kyiv
  /// day and the tapped minute since its midnight, rounded DOWN to the half
  /// hour. `null` (the default — every pre-485 caller and a read-only viewer)
  /// adds no tap layer at all. Never offered on a day-off column.
  final void Function(DateTime day, int minute)? onTapEmpty;

  /// Phase 485 — a live instant for the now-line and the now pill ONLY: a
  /// minute tick rebuilds those two, never the columns, cards or painters.
  /// [now] stays the build-time instant for the opening scroll and the
  /// cards (which offer no time-gated action here). `null` (the default)
  /// draws both from [now], exactly as before.
  final ValueListenable<DateTime>? nowListenable;

  /// Phase 485 — a host-owned holder of the Kyiv minute-of-day at the top of
  /// the vertical viewport. The grid writes it as the view scrolls; a grid
  /// mounted while it holds a value opens THERE instead of on its opening
  /// anchor — so a remount (the «День / 3 дні» toggle) keeps the hour the
  /// master was looking at. `null` (the default) — opening anchor, nothing
  /// written.
  final ValueNotifier<double?>? topMinute;

  /// Pager key — tests drag / fling it.
  static const Key pagerKey = Key('week-grid-pager');

  /// Header-row key — its drag is forwarded to the pager.
  static const Key headerRowKey = Key('week-grid-header-row');

  /// The shared vertical scroll view.
  static const Key verticalScrollKey = Key('week-grid-vertical');

  /// Today's now-line.
  static const Key nowLineKey = Key('week-grid-now-line');

  /// The now-time pill on the ruler.
  static const Key nowPillKey = Key('week-grid-now-pill');

  /// Column header `i` (0 = Monday).
  static Key headerKey(int i) => Key('week-grid-header-$i');

  /// Day column `i` (0 = Monday).
  static Key columnKey(int i) => Key('week-grid-column-$i');

  /// The card of booking [id].
  static Key cardKey(String id) => ValueKey<String>('week-grid-card-$id');

  /// Column [i]'s hours line under its header.
  static Key hoursKey(int i) => Key('week-grid-hours-$i');

  /// Column [i]'s ONE pinned «Вихідний» label.
  static Key dayOffLabelKey(int i) => Key('week-grid-day-off-$i');

  /// Column [i]'s «Перерва» label of the break starting at [startMinute].
  static Key breakLabelKey(int i, int startMinute) =>
      Key('week-grid-break-$i-$startMinute');

  /// Column [i]'s free declared-time marker at [minute] («3 дні»).
  static Key freeMarkerKey(int i, int minute) =>
      Key('week-grid-free-$i-$minute');

  /// Column [i]'s free-space tap layer ([onTapEmpty]).
  static Key emptyTapKey(int i) => Key('week-grid-empty-tap-$i');

  /// Column [i]'s declared-time list on an EXPLICIT_TIMES day («День»).
  static Key declaredListKey(int i) => Key('week-grid-declared-$i');

  /// «3 дні» hour band at text scale 1.0. Grows with the text scale so a
  /// 30-minute block keeps its range + name at ×1.3.
  static const double threeDayHourHeight = 72;

  /// Settle delay after a zero-velocity end before the snap to a day.
  static const Duration settleDelay = Duration(milliseconds: 180);

  /// Vertical gap between two back-to-back cards, and the column's own
  /// horizontal inset — the preview's 2 dp.
  static const double cardGap = 2;

  /// The band's offset below the ruler's origin — the single-day grid's
  /// [TimelineHourRuler.labelCenteringNudge], so each label centres on its
  /// line.
  static const double topPad = TimelineHourRuler.labelCenteringNudge;

  /// [hourHeight]'s default for [visibleColumns] at the ambient text scale.
  static double hourHeightFor(BuildContext context, int visibleColumns) =>
      visibleColumns == 1
      ? TimelineDensity.master.hourHeight
      : MediaQuery.textScalerOf(context).scale(threeDayHourHeight);

  /// The pinned header row's height — the «Чт 12» line plus the day's hours
  /// line («9:00–18:00» / «Вихідний» / «Свій час · 6»), grows with the text
  /// scale.
  static double headerHeightOf(BuildContext context) {
    final TextScaler ts = MediaQuery.textScalerOf(context);
    return VelvetSpacing.sm + ts.scale(11) * 1.4 + ts.scale(10) * 1.25;
  }

  /// A pager controller for [visibleColumns] with [firstVisibleDay] (0 =
  /// Monday) as the left-most column. A mode toggle builds a new one keeping
  /// the left-most visible day (phase decision D1).
  static PageController controllerFor({
    required int visibleColumns,
    int firstVisibleDay = 0,
  }) => PageController(
    viewportFraction: 1 / visibleColumns,
    initialPage: firstVisibleDay.clamp(0, kWeekGridDays - visibleColumns),
  );

  @override
  State<WeekTimeGrid> createState() => _WeekTimeGridState();
}

class _WeekTimeGridState extends State<WeekTimeGrid> {
  late final ScrollController _vertical;
  late PageController _headerController;
  Timer? _settle;
  final ForwardedScrollDrag _headerDrag = ForwardedScrollDrag();

  /// One [freeDeclaredTimes] memo per column (index = weekday) — a rebuild
  /// with identical inputs reuses the last merge.
  final List<FreeDeclaredTimesMemo> _freeTimes = <FreeDeclaredTimesMemo>[
    for (int i = 0; i < kWeekGridDays; i++) FreeDeclaredTimesMemo(),
  ];

  /// Pointers currently down on the grid. While any is down the user owns
  /// the position (a resting finger HOLDS it without scrolling), so the
  /// day snap waits; the last pointer up re-arms it.
  int _pointersDown = 0;

  int get _todayIndex {
    for (int i = 0; i < widget.days.length; i++) {
      if (widget.days[i].day == widget.today) return i;
    }
    return -1;
  }

  /// Snap-at-rest for «3 дні». The physics leaves a ZERO-velocity end alone
  /// (slow drag released in place), so input is never yanked back
  /// mid-gesture. Once scrolling has been idle for [WeekTimeGrid.settleDelay]
  /// the grid animates to the nearest day boundary. The only Timer here.
  bool _onPagerScroll(ScrollNotification n) {
    if (n.depth != 0 || widget.visibleColumns == 1) return false;
    if (n is ScrollStartNotification || n is ScrollUpdateNotification) {
      _settle?.cancel();
    } else if (n is ScrollEndNotification) {
      _settle?.cancel();
      _settle = Timer(WeekTimeGrid.settleDelay, _snapToDay);
    }
    return false;
  }

  void _onPointerDown(PointerDownEvent _) {
    _pointersDown++;
    _settle?.cancel();
  }

  void _onPointerUp(PointerEvent _) {
    _pointersDown = math.max(0, _pointersDown - 1);
    if (_pointersDown > 0 || widget.visibleColumns == 1) return;
    // A hold released without movement emits no ScrollEnd, so re-arm here.
    // A release that starts a fling is caught by [_snapToDay]'s
    // `isScrolling` check and re-armed by that fling's own end.
    _settle?.cancel();
    _settle = Timer(WeekTimeGrid.settleDelay, _snapToDay);
  }

  void _snapToDay() {
    final PageController c = widget.pageController;
    if (!mounted || !c.hasClients || _pointersDown > 0) return;
    final ScrollPosition p = c.position;
    if (p.isScrollingNotifier.value) return;
    final double extent = p.viewportDimension / widget.visibleColumns;
    final double target = ((p.pixels / extent).round() * extent)
        .clamp(p.minScrollExtent, p.maxScrollExtent)
        .toDouble();
    if ((target - p.pixels).abs() < 0.5) return;
    c.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void initState() {
    super.initState();
    _vertical = ScrollController()..addListener(_reportTopMinute);
    _headerController = _newHeaderController();
    widget.pageController.addListener(_syncHeader);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openAtStart());
  }

  /// Opens scrolled to an hour before now when today is in the week (so the
  /// now-line and the next bookings are on screen), else to the window's
  /// first content hour (one hour below its margin).
  ///
  /// [target] re-applies an earlier anchor minute ([_reanchor]); `null` =
  /// the carried [WeekTimeGrid.topMinute], else the opening rule.
  void _openAtStart({double? target}) {
    if (!mounted || !_vertical.hasClients) return;
    final WeekGridWindow window = weekGridWindow(widget.days);
    final double hourH = _hourHeight(context);
    final int origin = window.firstHour * 60;
    final double minute =
        target ??
        widget.topMinute?.value ??
        (_todayIndex >= 0
                ? minutesSinceDayStart(widget.now, kyivMidnight(widget.today)) -
                      60
                : origin + 60)
            .toDouble();
    final ScrollPosition v = _vertical.position;
    final double offset = ((minute - origin) / 60 * hourH)
        .clamp(v.minScrollExtent, v.maxScrollExtent)
        .toDouble();
    _opened = true;
    _anchorMinute = minute;
    _vertical.jumpTo(offset);
    _anchorOffset = offset;
    _reportTopMinute();
  }

  /// Writes the top-of-viewport minute to [WeekTimeGrid.topMinute] — only
  /// once the opening anchor ran, so the pre-anchor offset 0 never
  /// overwrites a carried value.
  void _reportTopMinute() {
    final ValueNotifier<double?>? holder = widget.topMinute;
    if (holder == null || !_opened || !_vertical.hasClients) return;
    holder.value =
        weekGridWindow(widget.days).firstHour * 60 +
        _vertical.position.pixels / _hourHeight(context) * 60;
  }

  /// The minute [_openAtStart] last anchored on (before clamping).
  double _anchorMinute = 0;

  /// Whether [_openAtStart] has run.
  bool _opened = false;

  /// The vertical offset [_openAtStart] last set; `null` once the view was
  /// re-anchored off it by [_reanchor].
  double? _anchorOffset;

  /// Keeps the view steady when the hour band changes under it — the
  /// window grows (a schedule landing after the bookings) or the hour height
  /// changes (the «День / 3 дні» toggle). Still on the opening anchor → the
  /// anchor is re-applied against the new band (it may have been clamped by
  /// the shorter one); scrolled by the user → the same wall-clock minute
  /// stays at the top. Runs after the frame, once the new extent is laid
  /// out. Nothing to do before the opening anchor ran — it reads the new
  /// band itself.
  void _reanchor(WeekTimeGrid old) {
    if (!_opened || !_vertical.hasClients) return;
    final double? anchor = _anchorOffset;
    final int oldFirst = weekGridWindow(old.days).firstHour;
    final int newFirst = weekGridWindow(widget.days).firstHour;
    final double oldHourH =
        old.hourHeight ??
        WeekTimeGrid.hourHeightFor(context, old.visibleColumns);
    final double newHourH = _hourHeight(context);
    if (oldFirst == newFirst && oldHourH == newHourH) return;
    final double pixels = _vertical.position.pixels;
    final bool onAnchor = anchor != null && (pixels - anchor).abs() < 0.5;
    final double topMinute = oldFirst * 60 + pixels / oldHourH * 60;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_vertical.hasClients) return;
      if (onAnchor) {
        _openAtStart(target: _anchorMinute);
        return;
      }
      final ScrollPosition v = _vertical.position;
      _vertical.jumpTo(
        ((topMinute - newFirst * 60) / 60 * newHourH)
            .clamp(v.minScrollExtent, v.maxScrollExtent)
            .toDouble(),
      );
      _anchorOffset = null;
    });
  }

  PageController _newHeaderController() => PageController(
    viewportFraction: 1 / widget.visibleColumns,
    initialPage: widget.pageController.hasClients
        ? (widget.pageController.page ?? 0).round()
        : widget.pageController.initialPage,
  );

  @override
  void didUpdateWidget(WeekTimeGrid old) {
    super.didUpdateWidget(old);
    if (old.pageController != widget.pageController ||
        old.visibleColumns != widget.visibleColumns) {
      _settle?.cancel();
      // A header drag in flight drives the OLD position — end it here so it
      // is neither re-routed to the new controller nor left dangling.
      _headerDrag.cancel();
      old.pageController.removeListener(_syncHeader);
      _headerController.dispose();
      _headerController = _newHeaderController();
      widget.pageController.addListener(_syncHeader);
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncHeader());
    }
    if (!identical(old.days, widget.days) ||
        old.visibleColumns != widget.visibleColumns ||
        old.hourHeight != widget.hourHeight) {
      _reanchor(old);
    }
  }

  void _syncHeader() {
    if (!_headerController.hasClients || !widget.pageController.hasClients) {
      return;
    }
    _headerController.jumpTo(widget.pageController.offset);
  }

  @override
  void dispose() {
    _settle?.cancel();
    _headerDrag.cancel();
    widget.pageController.removeListener(_syncHeader);
    _headerController.dispose();
    _vertical.dispose();
    super.dispose();
  }

  /// «День» on an EXPLICIT_TIMES day lays the shipped [DeclaredTimeCards]
  /// list (one fixed-footprint box per entry, NOT hour-mapped) over the
  /// column — the grid must be at least that tall so the last entry can be
  /// scrolled to. An upper bound of the list's entry count: every booking
  /// plus every declared time.
  double _declaredListFloor(BuildContext context) {
    int n = 0;
    for (final WeekDayModel d in widget.days) {
      final EffectiveDay? s = d.schedule;
      if (s == null || !s.isExplicitTimes) continue;
      n = math.max(n, d.bookings.length + s.times.length);
    }
    if (n == 0) return 0;
    return WeekTimeGrid.topPad +
        VelvetSpacing.sm +
        n * DeclaredTimeCards.entryExtentOf(context) +
        (n - 1) * DeclaredTimeCards.entryGap +
        VelvetSpacing.lg;
  }

  double _hourHeight(BuildContext context) =>
      widget.hourHeight ??
      WeekTimeGrid.hourHeightFor(context, widget.visibleColumns);

  // The header row is not its own scrollable — a drag on it is forwarded to
  // the GRID's scroll position (same physics, same fling + day snap).
  void _onHeaderDragStart(DragStartDetails d) {
    if (!widget.pageController.hasClients) return;
    _settle?.cancel();
    _headerDrag.start(widget.pageController, d);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<String> weekdays = weekdayShortLabels(l10n);
    final WeekGridWindow window = weekGridWindow(widget.days);
    final double hourH = _hourHeight(context);
    final int todayIndex = _todayIndex;
    final int totalHours = window.lastHour - window.firstHour;
    final bool exact = widget.visibleColumns > 1;
    final double rulerWidth = TimelineDensity.master.rulerWidth;
    final double gridH = math.max(
      WeekTimeGrid.topPad +
          totalHours * hourH +
          MediaQuery.textScalerOf(context).scale(11) * 1.4 +
          VelvetSpacing.lg,
      exact ? 0 : _declaredListFloor(context),
    );
    // The now-line's minute since today's Kyiv midnight for [now]; `null`
    // when today is not in this week or [now] is outside the window.
    int? nowMinuteOf(DateTime now) {
      if (todayIndex < 0) return null;
      final int m = minutesSinceDayStart(now, kyivMidnight(widget.today));
      return m >= window.firstHour * 60 && m <= window.lastHour * 60 ? m : null;
    }

    Widget? nowPill(DateTime now) => switch (nowMinuteOf(now)) {
      final int m => _NowPill(
        top: WeekTimeGrid.topPad + (m - window.firstHour * 60) / 60 * hourH,
        label: formatSlotTime(now),
      ),
      null => null,
    };
    final ValueListenable<DateTime>? liveNow = todayIndex >= 0
        ? widget.nowListenable
        : null;
    final bool animate =
        widget.entrance != null && !MediaQuery.disableAnimationsOf(context);

    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerUp,
      child: Column(
        children: <Widget>[
          // ── Pinned day headers, scrolled horizontally with the grid ───────
          SizedBox(
            height: WeekTimeGrid.headerHeightOf(context),
            child: Row(
              children: <Widget>[
                SizedBox(width: rulerWidth),
                Expanded(
                  child: GestureDetector(
                    key: WeekTimeGrid.headerRowKey,
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragStart: _onHeaderDragStart,
                    onHorizontalDragUpdate: _headerDrag.update,
                    onHorizontalDragEnd: _headerDrag.end,
                    onHorizontalDragCancel: _headerDrag.cancel,
                    // The header's `jumpTo` sync emits a Start/Update/End
                    // triple per grid frame — swallowed here so none reach
                    // listeners above the grid.
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (ScrollNotification _) => true,
                      child: PageView.builder(
                        controller: _headerController,
                        physics: const NeverScrollableScrollPhysics(),
                        padEnds: false,
                        itemCount: kWeekGridDays,
                        itemBuilder: (BuildContext context, int i) =>
                            WeekDayHeader(
                              key: WeekTimeGrid.headerKey(i),
                              label: l10n.weekGridDayHeader(
                                weekdays[i],
                                widget.days[i].day.day,
                              ),
                              semanticsLabel: i == todayIndex
                                  ? l10n.weekGridDayHeaderTodaySemantics(
                                      weekdays[i],
                                      widget.days[i].day.day,
                                    )
                                  : null,
                              schedule: widget.days[i].schedule,
                              hoursKey: WeekTimeGrid.hoursKey(i),
                              isToday: i == todayIndex,
                              onTap: () => widget.onTapHeader(i),
                            ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: BrandColors.accent.withValues(alpha: 0.15),
            ),
            child: const SizedBox(height: 1, width: double.infinity),
          ),
          // ── One vertical scroll for the ruler and all seven columns ────────
          Expanded(
            child: SingleChildScrollView(
              key: WeekTimeGrid.verticalScrollKey,
              controller: _vertical,
              child: SizedBox(
                height: gridH,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: rulerWidth,
                      height: gridH,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: <Widget>[
                          TimelineHourRuler(
                            firstHour: window.firstHour,
                            lastHour: window.lastHour,
                            hourHeight: hourH,
                          ),
                          if (liveNow != null)
                            ValueListenableBuilder<DateTime>(
                              valueListenable: liveNow,
                              builder:
                                  (BuildContext _, DateTime now, Widget? _) =>
                                      nowPill(now) ?? const SizedBox.shrink(),
                            )
                          else if (nowPill(widget.now) case final Widget pill)
                            pill,
                        ],
                      ),
                    ),
                    Expanded(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: _onPagerScroll,
                        child: PageView.builder(
                          key: WeekTimeGrid.pagerKey,
                          controller: widget.pageController,
                          padEnds: false,
                          // «3 дні»: free momentum across the whole week — a
                          // fling can run Mon→Sun in one gesture — settling on
                          // the nearest day boundary at rest. `pageSnapping`
                          // MUST be false or PageView wraps these physics in
                          // its own page physics (one day per swipe). «День»
                          // keeps one-day paging.
                          pageSnapping: !exact,
                          physics: exact
                              ? DaySnapScrollPhysics(
                                  visibleColumns: widget.visibleColumns,
                                  parent: const ClampingScrollPhysics(),
                                )
                              : null,
                          itemCount: kWeekGridDays,
                          itemBuilder: (BuildContext context, int i) {
                            final Widget column = _DayColumn(
                              key: WeekTimeGrid.columnKey(i),
                              index: i,
                              model: widget.days[i],
                              vertical: _vertical,
                              showsAllOccupancy: widget.showsAllOccupancy,
                              freeTimes: _freeTimes[i],
                              isToday: i == todayIndex,
                              nowMinuteOf: i == todayIndex ? nowMinuteOf : null,
                              nowListenable: liveNow,
                              now: widget.now,
                              firstHour: window.firstHour,
                              lastHour: window.lastHour,
                              hourHeight: hourH,
                              exactHeight: exact,
                              onBookingTap: widget.onBookingTap,
                              onTapEmpty: widget.onTapEmpty,
                            );
                            final Animation<double>? a = widget.entrance;
                            if (!animate || a == null) return column;
                            return _ColumnEntrance(
                              animation: a,
                              slot: (i - widget.pageController.initialPage)
                                  .clamp(0, 3),
                              child: column,
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Day header ────────────────────────────────────────────────────────────

/// «9:00» — hour without a leading zero (column-header hours only).
String _shortClock(int minute) =>
    '${minute ~/ 60}:${(minute % 60).toString().padLeft(2, '0')}';

/// The hours line under a week column header: «9:00–18:00» (first start –
/// last end), «Вихідний», or «Свій час · N» for an EXPLICIT_TIMES day;
/// `null` when the schedule is not loaded (the line stays empty).
String? weekDayHoursLabel(AppLocalizations l10n, EffectiveDay? schedule) {
  if (schedule == null) return null;
  if (schedule.isExplicitTimes) {
    return l10n.masterWeekCustomTimes(schedule.times.length);
  }
  if (isWeekDayOff(schedule)) return l10n.salonBookingsColumnDayOff;
  int start = schedule.intervals.first.startMinutes;
  int end = schedule.intervals.first.endMinutes;
  for (final WorkInterval w in schedule.intervals) {
    start = math.min(start, w.startMinutes);
    end = math.max(end, w.endMinutes);
  }
  return l10n.masterWeekHours(_shortClock(start), _shortClock(end));
}

/// One week column header: «Чт 12» (today: mocha + the shipped rail dot) and
/// the day's hours line under it ([weekDayHoursLabel]). A day off reads
/// muted. Tap → the host's day action.
class WeekDayHeader extends StatelessWidget {
  const WeekDayHeader({
    required this.label,
    required this.semanticsLabel,
    required this.schedule,
    required this.isToday,
    required this.onTap,
    this.hoursKey,
    super.key,
  });

  final String label;

  /// Today's spoken label («Чт 12, сьогодні»); `null` reads [label].
  final String? semanticsLabel;

  /// The day's resolved schedule; `null` = not loaded (no hours line text).
  final EffectiveDay? schedule;
  final bool isToday;
  final VoidCallback onTap;

  /// Key of the hours line `Text`.
  final Key? hoursKey;

  static const double _todayDot = 5;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final EffectiveDay? s = schedule;
    final bool dayOff = s != null && isWeekDayOff(s);
    final String? hours = weekDayHoursLabel(l10n, s);
    final String spoken = semanticsLabel ?? label;
    final Color labelColor = isToday
        ? BrandColors.accentDeep
        : dayOff
        ? BrandColors.muted
        : BrandColors.textSecondary;
    return Semantics(
      button: true,
      label: hours == null ? spoken : '$spoken, $hours',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VelvetRadii.field),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (isToday) ...<Widget>[
                  const _Dot(color: BrandColors.accentDeep, size: _todayDot),
                  const SizedBox(width: VelvetSpacing.xs),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VelvetText.weekColumnHeader.copyWith(
                      color: labelColor,
                      fontWeight: isToday ? FontWeight.w800 : FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              hours ?? '',
              key: hoursKey,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: VelvetText.weekColumnHours.copyWith(
                color: dayOff ? BrandColors.muted : BrandColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: DecoratedBox(
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    ),
  );
}

// ── Now pill on the ruler ─────────────────────────────────────────────────

class _NowPill extends StatelessWidget {
  const _NowPill({required this.top, required this.label});

  /// The now-line's y in the ruler's coordinates.
  final double top;
  final String label;

  static const double _halfHeight = 9;
  static const double _right = 2;

  @override
  Widget build(BuildContext context) => Positioned(
    top: top - _halfHeight,
    right: _right,
    child: DecoratedBox(
      key: WeekTimeGrid.nowPillKey,
      decoration: BoxDecoration(
        color: BrandColors.accentDeep,
        borderRadius: BorderRadius.circular(VelvetRadii.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VelvetSpacing.xs,
          vertical: _right,
        ),
        child: Text(label, style: VelvetText.nowPill),
      ),
    ),
  );
}

// ── Entrance (reduced motion skips it entirely) ───────────────────────────

class _ColumnEntrance extends StatefulWidget {
  const _ColumnEntrance({
    required this.animation,
    required this.slot,
    required this.child,
  });

  final Animation<double> animation;

  /// 0..3 — columns rise in left-to-right order, one sweep.
  final int slot;
  final Widget child;

  static const double _rise = 14;

  @override
  State<_ColumnEntrance> createState() => _ColumnEntranceState();
}

/// Builds the [CurvedAnimation] ONCE (and disposes it) — one per build
/// leaked a parent status listener each rebuild. Fade + slide are
/// transitions, so a frame repaints / re-translates without rebuilding.
class _ColumnEntranceState extends State<_ColumnEntrance> {
  late CurvedAnimation _curved;

  CurvedAnimation _curve() => CurvedAnimation(
    parent: widget.animation,
    curve: Interval(
      0.15 * widget.slot,
      math.min(1, 0.55 + 0.15 * widget.slot),
      curve: Curves.easeOutCubic,
    ),
  );

  @override
  void initState() {
    super.initState();
    _curved = _curve();
  }

  @override
  void didUpdateWidget(_ColumnEntrance old) {
    super.didUpdateWidget(old);
    if (old.animation != widget.animation || old.slot != widget.slot) {
      _curved.dispose();
      _curved = _curve();
    }
  }

  @override
  void dispose() {
    _curved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints c) {
      // SlideTransition offsets are fractions of the child's size; the
      // column is height-bounded by the grid, so this is the 14 dp rise.
      final double h = c.maxHeight;
      final double dy = h.isFinite && h > 0 ? _ColumnEntrance._rise / h : 0;
      // dim-decorative: one-shot load entrance; rests at opacity 1.
      return FadeTransition(
        opacity: _curved,
        child: SlideTransition(
          position: _curved.drive(
            Tween<Offset>(begin: Offset(0, dy), end: Offset.zero),
          ),
          child: widget.child,
        ),
      );
    },
  );
}

// ── One day column ────────────────────────────────────────────────────────

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.index,
    required this.model,
    required this.vertical,
    required this.showsAllOccupancy,
    required this.freeTimes,
    required this.isToday,
    required this.nowMinuteOf,
    required this.now,
    required this.firstHour,
    required this.lastHour,
    required this.hourHeight,
    required this.exactHeight,
    required this.onBookingTap,
    this.onTapEmpty,
    this.nowListenable,
    super.key,
  });

  /// 0 = Monday — keys only.
  final int index;
  final WeekDayModel model;

  /// The grid's shared vertical scroll — pins the day-off label.
  final ScrollController vertical;
  final bool showsAllOccupancy;

  /// This column's [freeDeclaredTimes] memo, owned by the grid's state.
  final FreeDeclaredTimesMemo freeTimes;
  final bool isToday;

  /// The now-line's minute for an instant (`null` = not drawn at that
  /// instant); `null` on every column but today's.
  final int? Function(DateTime now)? nowMinuteOf;

  /// See [WeekTimeGrid.nowListenable] — when set, only the now-line listens.
  final ValueListenable<DateTime>? nowListenable;
  final DateTime now;
  final int firstHour;
  final int lastHour;
  final double hourHeight;

  /// «3 дні» blocks fill their slot exactly; the «День» card treats the slot
  /// as a FLOOR (shipped `MasterBookingCard.minHeight` contract).
  final bool exactHeight;
  final ValueChanged<Booking> onBookingTap;

  /// See [WeekTimeGrid.onTapEmpty].
  final void Function(DateTime day, int minute)? onTapEmpty;

  /// Free-space taps round down to this many minutes.
  static const int _tapStepMinutes = 30;

  static const double _gap = WeekTimeGrid.cardGap;
  static const double _sidePad = WeekTimeGrid.cardGap;
  static const double _nowLineHeight = 2;
  static const double _nowDot = 7;

  /// Breathing room a «Перерва» pill needs inside its band.
  static const double _labelClearance = 6;

  double _y(int minute) =>
      WeekTimeGrid.topPad + (minute - firstHour * 60) / 60 * hourHeight;

  /// The half-hour (Kyiv minutes since midnight) a tap at column y [dy]
  /// falls in, clamped to the grid window.
  int _minuteAt(double dy) {
    final int raw =
        firstHour * 60 + ((dy - WeekTimeGrid.topPad) / hourHeight * 60).floor();
    final int clamped = raw.clamp(firstHour * 60, lastHour * 60 - 1);
    return clamped - clamped % _tapStepMinutes;
  }

  /// Kyiv minute of a declared time.
  static int _minuteOf(TimeOfDay t) => t.hour * 60 + t.minute;

  @override
  Widget build(BuildContext context) {
    final double scale = MediaQuery.textScalerOf(context).scale(1);
    final double labelH = _BandLabel.heightOf(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final int? Function(DateTime)? lineAt = nowMinuteOf;
    final ValueListenable<DateTime>? liveNow = lineAt == null
        ? null
        : nowListenable;
    final EffectiveDay? schedule = model.schedule;
    final bool explicit = schedule != null && schedule.isExplicitTimes;
    final bool dayOff = schedule != null && isWeekDayOff(schedule);
    // «День» on an EXPLICIT_TIMES day: the shipped declared-time list, not
    // hour-mapped cards (decision D2 — no second layout).
    final bool declaredList = explicit && !exactHeight;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double w = math.max(0, c.maxWidth - _sidePad * 2);
        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            // Its own layer: a card press, the entrance and the now-line
            // never repaint the hatch.
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: WeekColumnPainter(
                    day: model.day,
                    schedule: schedule,
                    firstHour: firstHour,
                    lastHour: lastHour,
                    hourHeight: hourHeight,
                    isToday: isToday,
                    topPad: WeekTimeGrid.topPad,
                  ),
                ),
              ),
            ),
            // Under every card, label and marker: a card tap still opens the
            // card. Absent without [onTapEmpty] and on a day off.
            if (onTapEmpty case final void Function(DateTime, int) onEmpty
                when !dayOff)
              Positioned.fill(
                child: GestureDetector(
                  key: WeekTimeGrid.emptyTapKey(index),
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (TapUpDetails d) =>
                      onEmpty(model.day, _minuteAt(d.localPosition.dy)),
                ),
              ),
            if (dayOff)
              _PinnedDayOffLabel(
                key: WeekTimeGrid.dayOffLabelKey(index),
                vertical: vertical,
                top: _y(firstHour * 60),
                bottom: _y(lastHour * 60),
                labelHeight: labelH,
                text: l10n.salonBookingsColumnDayOff,
              ),
            if (schedule != null)
              for (final MinuteRange b in weekBreaks(schedule))
                if (_y(b.end) - _y(b.start) >= labelH + _labelClearance)
                  Positioned(
                    key: WeekTimeGrid.breakLabelKey(index, b.start),
                    top: (_y(b.start) + _y(b.end)) / 2 - labelH / 2,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: _BandLabel(l10n.masterWeekBreakLabel),
                      ),
                    ),
                  ),
            if (declaredList)
              Positioned(
                top: WeekTimeGrid.topPad + VelvetSpacing.sm,
                left: _sidePad + VelvetSpacing.xs,
                right: _sidePad + VelvetSpacing.xs,
                child: DeclaredTimeCards(
                  key: WeekTimeGrid.declaredListKey(index),
                  declaredTimes: schedule.times,
                  bookings: model.bookings,
                  day: model.day,
                  showsAllOccupancy: showsAllOccupancy,
                  onTapBooking: onBookingTap,
                  embedded: true,
                ),
              ),
            // «3 дні» on an EXPLICIT_TIMES day: every still-free declared
            // time is a 30-minute marker at its start. Which times are free
            // is the shipped list's own merge (SCH-18) — never re-derived.
            if (explicit && exactHeight)
              for (final TimeOfDay t in freeTimes.of(
                schedule.times,
                model.bookings,
                model.day,
                showsAllOccupancy: showsAllOccupancy,
              ))
                Positioned(
                  key: WeekTimeGrid.freeMarkerKey(index, _minuteOf(t)),
                  top: _y(_minuteOf(t)) + _gap / 2,
                  left: _sidePad,
                  width: w,
                  height: math.max(0, hourHeight / 2 - _gap),
                  child: FreeTimeCard(time: t, column: true),
                ),
            // Bookings never overlap (BOOK-12: the backend rejects an
            // overlapping slot with 409 SLOT_TAKEN), so every card takes the
            // full column width — no lanes.
            if (!declaredList)
              for (int i = 0; i < model.bookings.length; i++)
                _placedCard(model.bookings[i], model.startMinutes[i], w, scale),
            if (liveNow != null && lineAt != null)
              ValueListenableBuilder<DateTime>(
                valueListenable: liveNow,
                builder: (BuildContext _, DateTime now, Widget? _) =>
                    _nowLine(lineAt(now)) ?? const SizedBox.shrink(),
              )
            else if (_nowLine(lineAt?.call(now)) case final Widget line)
              line,
          ],
        );
      },
    );
  }

  /// Today's now-line at minute [nowAt]; `null` draws nothing.
  Widget? _nowLine(int? nowAt) => nowAt == null
      ? null
      : Positioned(
          key: WeekTimeGrid.nowLineKey,
          top: _y(nowAt) - _nowLineHeight / 2,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Row(
              children: <Widget>[
                Transform.translate(
                  offset: const Offset(-_nowDot / 2, 0),
                  child: const _Dot(
                    color: BrandColors.accentDeep,
                    size: _nowDot,
                  ),
                ),
                const Expanded(
                  child: SizedBox(
                    height: _nowLineHeight,
                    child: ColoredBox(color: BrandColors.accentDeep),
                  ),
                ),
              ],
            ),
          ),
        );

  /// One card at its start. «3 дні»: exactly the slot (a tight height, so
  /// the column card's services fill it). «День»: the slot as a floor, never
  /// less than the card's natural height at this text scale — bounded
  /// either way, so the services wrap into whatever height the duration
  /// gives. Placed by `Positioned(top, height)`, NEVER `IntrinsicHeight`
  /// (the card reads its constraints — see `MasterBookingCard.column`).
  Widget _placedCard(Booking b, int startMinute, double width, double scale) {
    final double band = b.durationMinutes / 60 * hourHeight - _gap;
    final double top = _y(startMinute) + _gap / 2;
    void onTap() => onBookingTap(b);
    if (exactHeight) {
      return Positioned(
        top: top,
        left: _sidePad,
        width: width,
        height: math.max(0, band),
        child: MasterBookingCard(
          key: WeekTimeGrid.cardKey(b.id),
          booking: b,
          onTap: onTap,
          now: now,
          column: true,
          fillServices: true,
        ),
      );
    }
    final double slot = cardMinHeightFor(b.durationMinutes, hourHeight);
    final double height = math.max(
      slot,
      MasterBookingCard.naturalHeightFor(slot) * scale,
    );
    return Positioned(
      top: top,
      left: _sidePad,
      width: width,
      height: height,
      child: MasterBookingCard(
        key: WeekTimeGrid.cardKey(b.id),
        booking: b,
        onTap: onTap,
        now: now,
        minHeight: slot,
        fillServices: true,
      ),
    );
  }
}

/// ONE «Вихідний» per day-off column (decision D1), pinned to the vertical
/// centre of the VISIBLE part of the column: it follows the shared vertical
/// scroll, clamped to the grid so it never leaves the hatch.
///
/// Only this subtree listens to the scroll controller, and its own
/// [RepaintBoundary] + a paint-only [Transform] keep a scroll frame from
/// relaying out or repainting the column (its painter, its cards).
class _PinnedDayOffLabel extends StatelessWidget {
  const _PinnedDayOffLabel({
    required this.vertical,
    required this.top,
    required this.bottom,
    required this.labelHeight,
    required this.text,
    super.key,
  });

  final ScrollController vertical;

  /// The grid's top / bottom edge in column coordinates.
  final double top;
  final double bottom;
  final double labelHeight;
  final String text;

  /// Keeps the pill off the band's inset edges.
  static const double _edge = VelvetSpacing.xs;

  double _offset() {
    double centre = (top + bottom) / 2;
    if (vertical.hasClients && vertical.position.hasViewportDimension) {
      final ScrollPosition v = vertical.position;
      centre = v.pixels + v.viewportDimension / 2;
    }
    final double lo = top + _edge;
    final double hi = math.max(lo, bottom - labelHeight - _edge);
    return (centre - labelHeight / 2).clamp(lo, hi).toDouble();
  }

  @override
  Widget build(BuildContext context) => Positioned(
    top: 0,
    left: 0,
    right: 0,
    child: IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: vertical,
          builder: (BuildContext context, Widget? child) =>
              Transform.translate(offset: Offset(0, _offset()), child: child),
          // Its own layer under the per-scroll Transform: a scroll frame
          // re-composites the pill, never re-records it.
          child: Align(
            alignment: Alignment.topCenter,
            child: RepaintBoundary(child: _BandLabel(text)),
          ),
        ),
      ),
    ),
  );
}

/// «Вихідний» / «Перерва» — a small base-tone pill so the word stays legible
/// over the hatch.
class _BandLabel extends StatelessWidget {
  const _BandLabel(this.text);

  final String text;

  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: VelvetSpacing.xs + 2,
    vertical: 2,
  );

  /// The pill's height at the ambient text scale.
  static double heightOf(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(10) * 1.25 + _padding.vertical;

  static final BoxDecoration _decoration = BoxDecoration(
    color: BrandColors.base,
    borderRadius: BorderRadius.circular(VelvetRadii.pill),
    border: Border.all(color: BrandColors.shadowDarkCard),
  );

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: _decoration,
    child: Padding(
      padding: _padding,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: VelvetText.weekColumnHours.copyWith(
          color: BrandColors.textSecondary,
        ),
      ),
    ),
  );
}
