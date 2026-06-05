// Phase 15.2 — Unit tests for the day-grid slot projection (`buildDayCells`).
//
// The grid is a PURE RENDER PROJECTION of a resolved [EffectiveDay] (Phase
// 15.1). These tests pin the SlotState mapping the screen relies on:
//   • inside a working interval                 → SlotState.available
//   • OVERRIDE_DAY_OFF (whole-day time-off)      → SlotState.timeOff
//   • outside every interval / NO_SCHEDULE gap   → SlotState.unavailable
// and the 30-minute cell boundaries (half-open [start, end) interval edges).
//
// No widget tree — this is the pure-Dart projection used by both the legend and
// the screen's grid, so it is unit-tested in isolation.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/widgets/day_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/widgets/slot_colors.dart';

/// The resolved cell at [time] within [cells] (the grid spans 09:00–19:00 on
/// 30-min boundaries by default).
SlotCell _cellAt(List<SlotCell> cells, TimeOfDay time) => cells.firstWhere(
  (SlotCell c) => c.time.hour == time.hour && c.time.minute == time.minute,
);

WorkInterval _interval(int sh, int sm, int eh, int em) => WorkInterval(
  start: TimeOfDay(hour: sh, minute: sm),
  end: TimeOfDay(hour: eh, minute: em),
);

EffectiveDay _day({
  required EffectiveSource source,
  List<WorkInterval> intervals = const <WorkInterval>[],
}) => EffectiveDay(
  date: DateTime(2026, 6, 8),
  source: source,
  intervals: intervals,
);

void main() {
  group('buildDayCells — SlotState projection from EffectiveDay', () {
    test(
      'interval coverage maps to available; outside maps to unavailable',
      () {
        final EffectiveDay day = _day(
          source: EffectiveSource.template,
          intervals: <WorkInterval>[_interval(9, 0, 13, 0)],
        );

        final List<SlotCell> cells = buildDayCells(day);

        // Inside the interval → available.
        expect(
          _cellAt(cells, const TimeOfDay(hour: 9, minute: 0)).state,
          SlotState.available,
        );
        expect(
          _cellAt(cells, const TimeOfDay(hour: 11, minute: 30)).state,
          SlotState.available,
        );
        // Outside the interval → unavailable.
        expect(
          _cellAt(cells, const TimeOfDay(hour: 14, minute: 0)).state,
          SlotState.unavailable,
        );
        expect(
          _cellAt(cells, const TimeOfDay(hour: 18, minute: 30)).state,
          SlotState.unavailable,
        );
      },
    );

    test('OVERRIDE_DAY_OFF paints every cell as timeOff', () {
      final EffectiveDay day = _day(source: EffectiveSource.overrideDayOff);

      final List<SlotCell> cells = buildDayCells(day);

      expect(
        cells.every((SlotCell c) => c.state == SlotState.timeOff),
        isTrue,
        reason: 'a whole-day time-off override tints the entire grid pink',
      );
    });

    test('NO_SCHEDULE gap maps every cell to unavailable (all grey)', () {
      final EffectiveDay day = _day(source: EffectiveSource.noSchedule);

      final List<SlotCell> cells = buildDayCells(day);

      expect(
        cells.every((SlotCell c) => c.state == SlotState.unavailable),
        isTrue,
        reason: 'a NO_SCHEDULE gap reads all-grey (never time-off)',
      );
    });

    test('OVERRIDE_CUSTOM intervals project the same as a templated day', () {
      final EffectiveDay day = _day(
        source: EffectiveSource.overrideCustom,
        intervals: <WorkInterval>[_interval(12, 0, 16, 0)],
      );

      final List<SlotCell> cells = buildDayCells(day);

      expect(
        _cellAt(cells, const TimeOfDay(hour: 12, minute: 0)).state,
        SlotState.available,
      );
      expect(
        _cellAt(cells, const TimeOfDay(hour: 9, minute: 30)).state,
        SlotState.unavailable,
      );
    });
  });

  group('buildDayCells — 30-min boundary alignment (half-open intervals)', () {
    test('09:00–13:00 → last green cell is 12:30; 13:00 is unavailable', () {
      final EffectiveDay day = _day(
        source: EffectiveSource.template,
        intervals: <WorkInterval>[_interval(9, 0, 13, 0)],
      );

      final List<SlotCell> cells = buildDayCells(day);

      // 12:30 is the last cell still inside [09:00, 13:00).
      expect(
        _cellAt(cells, const TimeOfDay(hour: 12, minute: 30)).state,
        SlotState.available,
        reason: '12:30 is inside the half-open interval — last green cell',
      );
      // 13:00 == the exclusive end → unavailable.
      expect(
        _cellAt(cells, const TimeOfDay(hour: 13, minute: 0)).state,
        SlotState.unavailable,
        reason: 'the interval end (13:00) is exclusive — not a working cell',
      );
    });

    test(
      'interval start edge is inclusive (09:00 available, 08:30 absent)',
      () {
        final EffectiveDay day = _day(
          source: EffectiveSource.template,
          intervals: <WorkInterval>[_interval(9, 0, 13, 0)],
        );

        final List<SlotCell> cells = buildDayCells(day);

        // The grid starts at 09:00 by default, so 08:30 is not even generated.
        expect(
          cells.any((SlotCell c) => c.time.hour == 8),
          isFalse,
          reason: 'grid spans 09:00–19:00 — no pre-09:00 cells',
        );
        expect(
          _cellAt(cells, const TimeOfDay(hour: 9, minute: 0)).state,
          SlotState.available,
          reason: 'the interval start (09:00) is inclusive',
        );
      },
    );

    test('grid covers 09:00 through 19:00 inclusive on 30-min steps', () {
      final EffectiveDay day = _day(source: EffectiveSource.noSchedule);

      final List<SlotCell> cells = buildDayCells(day);

      // 09:00..19:00 inclusive on the hour + half-hour → 21 boundaries × ... :
      // hours 9..19 (11 hours) × 2 = 22 cells.
      expect(cells.length, 22);
      expect(cells.first.time, const TimeOfDay(hour: 9, minute: 0));
      expect(cells.last.time, const TimeOfDay(hour: 19, minute: 30));
    });

    test('a lunch gap between two intervals reads unavailable', () {
      final EffectiveDay day = _day(
        source: EffectiveSource.template,
        intervals: <WorkInterval>[
          _interval(9, 0, 13, 0),
          _interval(14, 0, 18, 0),
        ],
      );

      final List<SlotCell> cells = buildDayCells(day);

      // 13:00–14:00 lunch gap → unavailable; the two work blocks → available.
      expect(
        _cellAt(cells, const TimeOfDay(hour: 13, minute: 30)).state,
        SlotState.unavailable,
        reason: 'the gap between two working intervals is the lunch break',
      );
      expect(
        _cellAt(cells, const TimeOfDay(hour: 14, minute: 0)).state,
        SlotState.available,
      );
      expect(
        _cellAt(cells, const TimeOfDay(hour: 9, minute: 0)).state,
        SlotState.available,
      );
    });
  });
}
