// Phase 484 — WeekStrip: Mon–Sun in one row that never scrolls, with a
// recessed «window» under exactly the days the week grid shows. Port of the
// MasterWeekBookings preview
// (`docs/signup-designs/MasterWeekBookings/lib/widgets/week_strip.dart`).
//
// THE ONE BOLD ELEMENT of the week header: the window is 3 cells wide in
// «3 дні», 1 in «День», and follows the grid's pager in real time — it is an
// `AnimatedBuilder` on the SHARED `PageController` (phase 482's contract),
// so a scroll frame repaints only the window, never a `setState`.
//
// Tap a day → [WeekStrip.onTapDay] (the host scrolls the grid there). Drag
// along the strip → a real drag on the grid's position ([ForwardedScrollDrag],
// shared with the grid's header row), one cell of finger travel = one day; the
// release velocity is handed to the grid's own physics, which settles. The
// strip never reacts to the position other than by painting the window, so
// there is no grid → strip → controller loop. ‹ › at the edges step weeks.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';

import '../../domain/booking.dart';
import '../../domain/booking_status.dart';
import '../../domain/week_day_model.dart';
import 'bookings_day_rail.dart' show weekdayShortLabels;
import 'forwarded_scroll_drag.dart';
import 'week_column_painter.dart' show isWeekDayOff;
import 'week_nav_bar.dart' show WeekStepButton;

/// Whether [status] counts toward the strip's per-day number. Cancelled and
/// declined bookings stay on the grid (struck through) but are not counted.
bool countsInWeekStrip(BookingStatus status) => switch (status) {
  BookingStatus.confirmed => true,
  BookingStatus.completed => true,
  BookingStatus.notCompleted => true,
  BookingStatus.cancelled => false,
  BookingStatus.declined => false,
  // A status this build does not know is still a booking on the grid.
  BookingStatus.unknown => true,
};

/// The strip's seven counts, Monday first — live bookings only (see
/// [countsInWeekStrip]).
List<int> weekStripCounts(List<WeekDayModel> days) =>
    List<int>.unmodifiable(<int>[
      for (final WeekDayModel d in days)
        d.bookings.where((Booking b) => countsInWeekStrip(b.status)).length,
    ]);

/// The strip's seven day-off flags, Monday first. A day whose schedule was
/// not loaded is not a day off.
List<bool> weekStripDayOff(List<WeekDayModel> days) =>
    List<bool>.unmodifiable(<bool>[
      for (final WeekDayModel d in days)
        switch (d.schedule) {
          final s? => isWeekDayOff(s),
          null => false,
        },
    ]);

/// Widget key of the strip cell for [day].
Key weekStripDayKey(DateTime day) => Key('week-strip-day-${toApiDate(day)}');

/// Widget key of the count under [day]; present only when it has a count.
Key weekStripCountKey(DateTime day) =>
    Key('week-strip-count-${toApiDate(day)}');

/// Widget key of the day-off ring under [day].
Key weekStripDayOffKey(DateTime day) =>
    Key('week-strip-day-off-${toApiDate(day)}');

/// Days in the strip.
const int _kDays = 7;

class WeekStrip extends StatelessWidget {
  const WeekStrip({
    super.key,
    required this.weekStart,
    required this.today,
    required this.counts,
    required this.dayOff,
    required this.pageController,
    required this.visibleColumns,
    required this.onTapDay,
    required this.onPrevWeek,
    required this.onNextWeek,
  }) : assert(counts.length == _kDays && dayOff.length == _kDays);

  /// The week's Monday date token.
  final DateTime weekStart;

  /// The Kyiv date token of today (may be outside the week).
  final DateTime today;

  /// Live bookings per day, Monday first — see [weekStripCounts].
  final List<int> counts;

  /// Day-off flags, Monday first — see [weekStripDayOff].
  final List<bool> dayOff;

  /// The week grid's pager (phase 482): page = the left-most visible day.
  final PageController pageController;

  /// 3 in «3 дні», 1 in «День» — the window's width in cells.
  final int visibleColumns;

  /// Tap on a day, as its index (0 = Monday).
  final ValueChanged<int> onTapDay;
  final VoidCallback onPrevWeek;
  final VoidCallback onNextWeek;

  static const Key windowKey = Key('week-strip-window');

  /// The layer that isolates the moving window from the boundary above.
  static const Key windowLayerKey = Key('week-strip-window-layer');

  /// The inset's own layer, reused as-is while the window translates.
  static const Key windowInsetLayerKey = Key('week-strip-window-inset-layer');
  static const Key daysKey = Key('week-strip-days');

  /// Settle animation for a host that scrolls the grid to a tapped day.
  static const Duration settleDuration = Duration(milliseconds: 220);

  /// The strip's height at the ambient text scale — grows with it instead of
  /// clipping.
  static double heightOf(BuildContext context) {
    final TextScaler ts = MediaQuery.textScalerOf(context);
    return 14 + ts.scale(11) * 1.4 + ts.scale(12.6) * 1.15 + ts.scale(10) * 1.2;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        WeekStepButton(forward: false, onTap: onPrevWeek),
        Expanded(
          child: _Days(
            key: daysKey,
            weekStart: weekStart,
            today: today,
            counts: counts,
            dayOff: dayOff,
            pageController: pageController,
            visibleColumns: visibleColumns,
            onTapDay: onTapDay,
          ),
        ),
        WeekStepButton(forward: true, onTap: onNextWeek),
      ],
    );
  }
}

class _Days extends StatefulWidget {
  const _Days({
    super.key,
    required this.weekStart,
    required this.today,
    required this.counts,
    required this.dayOff,
    required this.pageController,
    required this.visibleColumns,
    required this.onTapDay,
  });

  final DateTime weekStart;
  final DateTime today;
  final List<int> counts;
  final List<bool> dayOff;
  final PageController pageController;
  final int visibleColumns;
  final ValueChanged<int> onTapDay;

  @override
  State<_Days> createState() => _DaysState();
}

class _DaysState extends State<_Days> {
  final ForwardedScrollDrag _drag = ForwardedScrollDrag();

  PageController get pageController => widget.pageController;
  int get visibleColumns => widget.visibleColumns;

  @override
  void didUpdateWidget(_Days old) {
    super.didUpdateWidget(old);
    // A scrub in flight drives the OLD position — end it, never re-route it.
    if (old.pageController != widget.pageController) _drag.cancel();
  }

  @override
  void dispose() {
    _drag.cancel();
    super.dispose();
  }

  /// The pager's page, or its initial page while it has no laid-out client.
  double get _page {
    final PageController c = pageController;
    if (c.positions.length == 1 && c.position.hasContentDimensions) {
      return c.page ?? c.initialPage.toDouble();
    }
    return c.initialPage.toDouble();
  }

  /// Strip px → grid px: one cell of finger travel = one day of grid travel,
  /// in the window's direction (finger right → pixels up, hence negative).
  double _scale(double cellW) {
    if (pageController.positions.length != 1 || cellW <= 0) return 0;
    final ScrollPosition p = pageController.position;
    return -(p.viewportDimension / visibleColumns) / cellW;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<String> weekdays = weekdayShortLabels(l10n);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double cellW = c.maxWidth / _kDays;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (DragStartDetails d) =>
              _drag.start(pageController, d),
          onHorizontalDragUpdate: (DragUpdateDetails d) =>
              _drag.update(d, scale: _scale(cellW)),
          onHorizontalDragEnd: (DragEndDetails d) =>
              _drag.end(d, scale: _scale(cellW)),
          onHorizontalDragCancel: _drag.cancel,
          child: SizedBox(
            height: WeekStrip.heightOf(context),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  // The moving window gets its own layer so a scroll frame
                  // never repaints the boundary above the strip.
                  child: RepaintBoundary(
                    key: WeekStrip.windowLayerKey,
                    child: AnimatedBuilder(
                      animation: pageController,
                      // A scroll frame only re-translates the fixed-width
                      // window; the inset's cached layer is reused as-is.
                      builder: (BuildContext context, Widget? child) =>
                          Transform.translate(
                            offset: Offset(_page * cellW + 2, 0),
                            child: child,
                          ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: cellW * visibleColumns - 4,
                          height: double.infinity,
                          child: const RepaintBoundary(
                            key: WeekStrip.windowInsetLayerKey,
                            child: NeumorphicInset(
                              key: WeekStrip.windowKey,
                              radius: VelvetRadii.field,
                              animatedRing: false,
                              child: SizedBox.expand(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // The days never change with the scroll position — their own
                // layer keeps a moving window from repainting them.
                RepaintBoundary(
                  child: Row(
                    children: <Widget>[
                      for (int i = 0; i < _kDays; i++)
                        SizedBox(width: cellW, child: _cell(l10n, weekdays, i)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _cell(AppLocalizations l10n, List<String> weekdays, int i) {
    final DateTime date = kyivAddDays(widget.weekStart, i);
    return _StripDay(
      date: date,
      weekday: weekdays[i],
      isToday: date == widget.today,
      isPast: date.isBefore(widget.today),
      isDayOff: widget.dayOff[i],
      count: widget.counts[i],
      l10n: l10n,
      onTap: () => widget.onTapDay(i),
    );
  }
}

class _StripDay extends StatelessWidget {
  const _StripDay({
    required this.date,
    required this.weekday,
    required this.isToday,
    required this.isPast,
    required this.isDayOff,
    required this.count,
    required this.l10n,
    required this.onTap,
  });

  final DateTime date;
  final String weekday;
  final bool isToday;
  final bool isPast;
  final bool isDayOff;
  final int count;
  final AppLocalizations l10n;
  final VoidCallback onTap;

  // Every cell style is one of these — built once, not per cell per build.
  static final TextStyle _weekdayToday = VelvetText.railWeekday.copyWith(
    color: BrandColors.accentDeep,
  );
  static final TextStyle _weekdayDim = VelvetText.railWeekday.copyWith(
    color: BrandColors.weekendMuted,
  );
  static final TextStyle _weekdayPlain = VelvetText.railWeekday.copyWith(
    color: BrandColors.textSecondary,
  );
  static final TextStyle _numberToday = VelvetText.railDayNumber.copyWith(
    color: BrandColors.accentDeep,
    fontWeight: FontWeight.w800,
    decoration: TextDecoration.underline,
    decorationColor: BrandColors.accent,
    decorationThickness: 1.5,
  );
  static final TextStyle _numberDim = VelvetText.railDayNumber.copyWith(
    color: BrandColors.weekendMuted,
    fontWeight: FontWeight.w700,
    decoration: TextDecoration.none,
    decorationColor: BrandColors.accent,
    decorationThickness: 1.5,
  );
  static final TextStyle _numberPlain = VelvetText.railDayNumber.copyWith(
    color: BrandColors.text,
    fontWeight: FontWeight.w700,
    decoration: TextDecoration.none,
    decorationColor: BrandColors.accent,
    decorationThickness: 1.5,
  );
  static final TextStyle _countPast = VelvetText.weekCount.copyWith(
    color: BrandColors.weekendMuted,
    height: 1.1,
  );
  static final TextStyle _countUpcoming = VelvetText.weekCount.copyWith(
    color: BrandColors.accentDeep,
    height: 1.1,
  );

  String get _semantics {
    final List<String> parts = <String>[
      l10n.masterBookingsDaySemantics(weekday, date.day),
      if (isToday) l10n.masterWeekStripTodaySemantics,
      if (isDayOff)
        l10n.masterWeekStripDayOffSemantics
      else if (count == 0)
        l10n.masterWeekStripNoBookingsSemantics
      else
        l10n.masterBookingsCount(count),
    ];
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    // De-emphasised days use the rail's AA-safe `weekendMuted`, not the
    // preview's `muted` (2.69:1) — the cells stay tappable, so the WCAG
    // inactive-component exemption never applies (see `_DayChip`).
    final bool dim = !isToday && (isPast || isDayOff);
    final TextStyle weekdayStyle = isToday
        ? _weekdayToday
        : dim
        ? _weekdayDim
        : _weekdayPlain;
    final TextStyle numberStyle = isToday
        ? _numberToday
        : dim
        ? _numberDim
        : _numberPlain;
    final TextScaler ts = MediaQuery.textScalerOf(context);
    return Semantics(
      button: true,
      label: _semantics,
      excludeSemantics: true,
      child: GestureDetector(
        key: weekStripDayKey(date),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(weekday, maxLines: 1, softWrap: false, style: weekdayStyle),
            const SizedBox(height: 2),
            // Today mark = the shipped rail's: w800 + camel underline.
            Text(
              '${date.day}',
              maxLines: 1,
              softWrap: false,
              style: numberStyle,
            ),
            const SizedBox(height: 2),
            // Fixed-height slot: a count appearing never reflows the row.
            SizedBox(
              height: ts.scale(10) * 1.2,
              child: Center(child: _mark()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mark() {
    if (isDayOff) {
      // Hollow ring = no working hours (the grid's hatched column).
      return Container(
        key: weekStripDayOffKey(date),
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: BrandColors.faint, width: 1.2),
        ),
      );
    }
    if (count == 0) return const SizedBox.shrink();
    return Text(
      '$count',
      key: weekStripCountKey(date),
      maxLines: 1,
      softWrap: false,
      style: isPast ? _countPast : _countUpcoming,
    );
  }
}
