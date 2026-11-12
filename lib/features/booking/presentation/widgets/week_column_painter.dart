// Phase 483 — WeekColumnPainter: one week-grid day column's background.
// Port of the MasterWeekBookings preview `_ColumnPainter`
// (`docs/signup-designs/MasterWeekBookings/lib/widgets/week_time_grid.dart`).
//
// Non-working time — before the first start, after the last end, every
// break between intervals, a whole day off and a whole EXPLICIT_TIMES day —
// paints as a RECESSED band: the card's own recess tone (`shadowDarkCard`)
// at 0.55, a 45° camel hatch (`accent` at 0.38) and an inset edge (dark line
// on the top inner edge, highlight on the bottom). Palette tones only.

import 'dart:math' as math;
import 'dart:typed_data' show Float32List;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart'
    show WorkInterval;
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';

import 'bookings_timeline_grid.dart' show BookingsTimelineGrid;
import 'timeline_hour_ruler.dart';

/// A minute range `[start, end)` since the column day's Kyiv midnight.
typedef MinuteRange = ({int start, int end});

/// The [schedule]'s intervals, start-sorted (the editors keep them sorted;
/// this does not trust it).
List<MinuteRange> _sortedIntervals(EffectiveDay schedule) => <MinuteRange>[
  for (final WorkInterval w in schedule.intervals)
    (start: w.startMinutes, end: w.endMinutes),
]..sort((MinuteRange a, MinuteRange b) => a.start.compareTo(b.start));

/// Whether [schedule] has no working time at all — a day off.
bool isWeekDayOff(EffectiveDay schedule) =>
    schedule.intervals.isEmpty && schedule.times.isEmpty;

/// The breaks of an INTERVAL day — the gaps between consecutive intervals.
/// Empty for a day off and for an EXPLICIT_TIMES day.
List<MinuteRange> weekBreaks(EffectiveDay schedule) {
  if (schedule.isExplicitTimes) return const <MinuteRange>[];
  final List<MinuteRange> sorted = _sortedIntervals(schedule);
  final List<MinuteRange> out = <MinuteRange>[];
  int cursor = sorted.isEmpty ? 0 : sorted.first.end;
  for (int i = 1; i < sorted.length; i++) {
    if (sorted[i].start > cursor) {
      out.add((start: cursor, end: sorted[i].start));
    }
    cursor = math.max(cursor, sorted[i].end);
  }
  return out;
}

/// The non-working bands of one column inside the window
/// `[windowStart, windowEnd)` (minutes): the window minus the working
/// intervals. A day off and an EXPLICIT_TIMES day are ONE band over the whole
/// window (an explicit day's free times sit on top of it). `null` schedule
/// (not loaded) = no bands — the grid claims nothing it does not know.
List<MinuteRange> weekOffBands(
  EffectiveDay? schedule,
  int windowStart,
  int windowEnd,
) {
  if (schedule == null) return const <MinuteRange>[];
  if (schedule.isExplicitTimes || isWeekDayOff(schedule)) {
    return <MinuteRange>[(start: windowStart, end: windowEnd)];
  }
  final List<MinuteRange> out = <MinuteRange>[];
  int cursor = windowStart;
  for (final MinuteRange w in _sortedIntervals(schedule)) {
    if (w.start > cursor) {
      out.add((start: cursor, end: math.min(w.start, windowEnd)));
    }
    cursor = math.max(cursor, w.end);
    if (cursor >= windowEnd) break;
  }
  if (cursor < windowEnd) out.add((start: cursor, end: windowEnd));
  return out;
}

/// Column background: optional today wash, hour + half-hour hairlines,
/// recessed hatched non-working bands, and the column divider.
class WeekColumnPainter extends CustomPainter {
  WeekColumnPainter({
    required this.day,
    required this.schedule,
    required this.firstHour,
    required this.lastHour,
    required this.hourHeight,
    required this.isToday,
    this.topPad = TimelineHourRuler.labelCenteringNudge,
  });

  /// The column's Kyiv date token.
  final DateTime day;

  /// The resolved schedule; `null` = not loaded (no bands, no wash).
  final EffectiveDay? schedule;
  final int firstHour;
  final int lastHour;
  final double hourHeight;
  final bool isToday;

  /// The band's offset below the ruler's origin.
  final double topPad;

  static final Paint _offHours = Paint()
    ..color = BrandColors.shadowDarkCard.withValues(alpha: 0.55);
  static final Paint _hatch = Paint()
    ..color = BrandColors.accent.withValues(alpha: 0.38)
    ..strokeWidth = 1.2;
  static final Paint _insetDark = Paint()
    ..color = BrandColors.shadowDarkButton
    ..strokeWidth = 2;
  static final Paint _insetLight = Paint()
    ..color = BrandColors.shadowLightStrong.withValues(alpha: 0.9)
    ..strokeWidth = 1.5;
  static final Paint _hour = Paint()
    ..color = BrandColors.faint
    ..strokeWidth = 1;
  static final Paint _half = Paint()
    ..color = BookingsTimelineGrid.halfHourLineColor
    ..strokeWidth = 1;
  static final Paint _divider = Paint()
    ..color = BrandColors.accent.withValues(alpha: 0.18)
    ..strokeWidth = 1;
  static final Paint _todayWash = Paint()
    ..color = BrandColors.shadowLightStrong.withValues(alpha: 0.35);

  /// Hatch spacing along x.
  static const double hatchStep = 9;

  double _y(int minute) => topPad + (minute - firstHour * 60) / 60 * hourHeight;

  /// The recessed band rectangles for a column of [size] — exposed so tests
  /// pin the geometry without reading pixels.
  List<Rect> offBandRects(Size size) => <Rect>[
    for (final MinuteRange b in weekOffBands(
      schedule,
      firstHour * 60,
      lastHour * 60,
    ))
      Rect.fromLTRB(0, _y(b.start), size.width, _y(b.end)),
  ];

  /// The 45° hatch of band [r] as `(x0, y0, x1, y1)` segment quadruples for
  /// ONE `drawRawPoints(PointMode.lines, …)` call — clipped to [r]
  /// ANALYTICALLY, so the band needs no `save()` / `clipRect()` layer and no
  /// full-length line is rasterised outside it. Every line satisfies
  /// `x − y = k · hatchStep` in COLUMN coordinates, so stacked bands line up;
  /// a line's visible part is `y ∈ [max(top, left − c), min(bottom, right − c)]`.
  @visibleForTesting
  static Float32List hatchSegments(Rect r) {
    final double kFrom = ((r.left - r.bottom) / hatchStep).floorToDouble();
    final double kTo = ((r.right - r.top) / hatchStep).ceilToDouble();
    final List<double> points = <double>[];
    for (double k = kFrom; k <= kTo; k++) {
      final double c = k * hatchStep;
      final double y0 = math.max(r.top, r.left - c);
      final double y1 = math.min(r.bottom, r.right - c);
      if (y1 <= y0) continue;
      points
        ..add(c + y0)
        ..add(y0)
        ..add(c + y1)
        ..add(y1);
    }
    return Float32List.fromList(points);
  }

  void _offBand(Canvas canvas, Rect r) {
    if (r.height <= 0 || r.width <= 0) return;
    canvas
      ..drawRect(r, _offHours)
      ..drawRawPoints(PointMode.lines, hatchSegments(r), _hatch)
      ..drawLine(
        r.topLeft.translate(0, 1),
        r.topRight.translate(0, 1),
        _insetDark,
      )
      ..drawLine(
        r.bottomLeft.translate(0, -0.75),
        r.bottomRight.translate(0, -0.75),
        _insetLight,
      );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double top = _y(firstHour * 60);
    final double bottom = _y(lastHour * 60);
    final EffectiveDay? s = schedule;

    if (isToday && s != null && !s.isExplicitTimes && !isWeekDayOff(s)) {
      canvas.drawRect(Rect.fromLTRB(0, top, size.width, bottom), _todayWash);
    }

    for (int h = firstHour; h <= lastHour; h++) {
      final double y = _y(h * 60);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), _hour);
      if (h < lastHour) {
        final double yh = y + hourHeight / 2;
        canvas.drawLine(Offset(0, yh), Offset(size.width, yh), _half);
      }
    }

    for (final Rect r in offBandRects(size)) {
      _offBand(canvas, r);
    }

    canvas.drawLine(Offset(0, top), Offset(0, bottom), _divider);
  }

  /// Day / window / today only. The schedule is compared by IDENTITY — a
  /// resolve that hands a new [EffectiveDay] repaints, an unrelated rebuild
  /// (a now-tick) does not.
  @override
  bool shouldRepaint(WeekColumnPainter old) =>
      old.day != day ||
      !identical(old.schedule, schedule) ||
      old.firstHour != firstHour ||
      old.lastHour != lastHour ||
      old.hourHeight != hourHeight ||
      old.topPad != topPad ||
      old.isToday != isToday;
}
