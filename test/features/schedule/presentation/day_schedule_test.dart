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

    test('a lunch gap between two intervals reads timeOff (pause)', () {
      final EffectiveDay day = _day(
        source: EffectiveSource.template,
        intervals: <WorkInterval>[
          _interval(9, 0, 13, 0),
          _interval(14, 0, 18, 0),
        ],
      );

      final List<SlotCell> cells = buildDayCells(day);

      // 13:00–14:00 lunch gap → timeOff (fully red) under the pause round-up
      // rule; the two work blocks → available.
      expect(
        _cellAt(cells, const TimeOfDay(hour: 13, minute: 30)).state,
        SlotState.timeOff,
        reason: 'the gap between two working intervals is a pause (timeOff)',
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

  // ───────────────────────────────────────────────────────────────────────────
  // The PAUSE ROUND-UP rule (the new behaviour to guard). An interior pause —
  // the gap between two consecutive working intervals — paints EVERY 30-min cell
  // it touches FULLY red, even on a single-minute (partial) overlap. So a 15-min
  // pause reddens ONE cell, a 45-min pause reddens TWO. The exact cell COUNT is
  // the contract these tests pin; counting `timeOff` cells (not eyeballing one
  // cell) is what catches a regression that over- or under-rounds.
  // ───────────────────────────────────────────────────────────────────────────
  group('buildDayCells — interior pause round-up (cell-count contract)', () {
    /// Times of every cell painted [SlotState.timeOff], in grid order. Asserting
    /// on this list pins both HOW MANY cells reddened and WHICH ones.
    List<TimeOfDay> _timeOffTimes(List<SlotCell> cells) => cells
        .where((SlotCell c) => c.state == SlotState.timeOff)
        .map((SlotCell c) => c.time)
        .toList();

    test('15-min pause [09:00–12:15, 12:30–18:00] → exactly ONE timeOff cell '
        '(12:00)', () {
      final EffectiveDay day = _day(
        source: EffectiveSource.template,
        intervals: <WorkInterval>[
          _interval(9, 0, 12, 15),
          _interval(12, 30, 18, 0),
        ],
      );

      final List<SlotCell> cells = buildDayCells(day);

      // The pause is 12:15–12:30 — it lives entirely inside the 12:00 cell
      // window [12:00, 12:30). Round-up: that ONE cell goes fully red, no more.
      expect(
        _timeOffTimes(cells),
        <TimeOfDay>[const TimeOfDay(hour: 12, minute: 0)],
        reason: 'a 15-min interior pause reddens exactly one 30-min cell',
      );
      // Flanking cells stay green; the 12:30 cell (work resumes) is green too.
      expect(
        _cellAt(cells, const TimeOfDay(hour: 11, minute: 30)).state,
        SlotState.available,
      );
      expect(
        _cellAt(cells, const TimeOfDay(hour: 12, minute: 30)).state,
        SlotState.available,
      );
    });

    test('45-min pause [09:00–12:00, 12:45–18:00] → exactly TWO timeOff cells '
        '(12:00 and 12:30)', () {
      final EffectiveDay day = _day(
        source: EffectiveSource.template,
        intervals: <WorkInterval>[
          _interval(9, 0, 12, 0),
          _interval(12, 45, 18, 0),
        ],
      );

      final List<SlotCell> cells = buildDayCells(day);

      // The pause is 12:00–12:45. It fully fills the 12:00 cell and partially
      // overlaps the 12:30 cell (12:30–12:45) → BOTH round up to red.
      expect(
        _timeOffTimes(cells),
        <TimeOfDay>[
          const TimeOfDay(hour: 12, minute: 0),
          const TimeOfDay(hour: 12, minute: 30),
        ],
        reason: 'a 45-min interior pause reddens exactly two consecutive cells',
      );
      // 13:00 (work resumed by then) is green again.
      expect(
        _cellAt(cells, const TimeOfDay(hour: 13, minute: 0)).state,
        SlotState.available,
      );
    });

    test('30-min pause [09:00–12:00, 12:30–18:00] → exactly ONE timeOff cell '
        '(12:00)', () {
      final EffectiveDay day = _day(
        source: EffectiveSource.template,
        intervals: <WorkInterval>[
          _interval(9, 0, 12, 0),
          _interval(12, 30, 18, 0),
        ],
      );

      final List<SlotCell> cells = buildDayCells(day);

      // The pause is exactly the 12:00 cell window [12:00, 12:30) → one red cell.
      expect(
        _timeOffTimes(cells),
        <TimeOfDay>[const TimeOfDay(hour: 12, minute: 0)],
        reason: 'a 30-min pause aligned to the grid reddens exactly one cell',
      );
    });

    test('pause straddling the :30 boundary [09:00–12:15, 12:45–18:00] → TWO '
        'timeOff cells (12:00 and 12:30)', () {
      final EffectiveDay day = _day(
        source: EffectiveSource.template,
        intervals: <WorkInterval>[
          _interval(9, 0, 12, 15),
          _interval(12, 45, 18, 0),
        ],
      );

      final List<SlotCell> cells = buildDayCells(day);

      // Pause 12:15–12:45 straddles the :30 boundary: it touches the 12:00 cell
      // (12:15–12:30) AND the 12:30 cell (12:30–12:45) → both round up to red.
      expect(
        _timeOffTimes(cells),
        <TimeOfDay>[
          const TimeOfDay(hour: 12, minute: 0),
          const TimeOfDay(hour: 12, minute: 30),
        ],
        reason: 'a pause spanning the :30 boundary reddens both touched cells',
      );
    });

    test('multiple pauses each round up independently (two distinct gaps)', () {
      // 11:00–11:15 (→ 11:00 cell) and 14:00–14:45 (→ 14:00 + 14:30 cells).
      final EffectiveDay day = _day(
        source: EffectiveSource.template,
        intervals: <WorkInterval>[
          _interval(9, 0, 11, 0),
          _interval(11, 15, 14, 0),
          _interval(14, 45, 18, 0),
        ],
      );

      final List<SlotCell> cells = buildDayCells(day);

      expect(
        _timeOffTimes(cells),
        <TimeOfDay>[
          const TimeOfDay(hour: 11, minute: 0),
          const TimeOfDay(hour: 14, minute: 0),
          const TimeOfDay(hour: 14, minute: 30),
        ],
        reason: 'each interior gap rounds up to its own touched cells',
      );
    });

    test('leading and trailing gaps stay unavailable — never timeOff', () {
      // A single interval 10:00–16:00: the 09:00/09:30 lead-in and the
      // 16:00..19:30 run-out are OUTSIDE the working span → grey, not red.
      final EffectiveDay day = _day(
        source: EffectiveSource.template,
        intervals: <WorkInterval>[_interval(10, 0, 16, 0)],
      );

      final List<SlotCell> cells = buildDayCells(day);

      // No interior gap exists, so nothing reddens.
      expect(
        _timeOffTimes(cells),
        isEmpty,
        reason: 'a single interval has no interior pause → no timeOff cells',
      );
      // Leading gap (before first start) → unavailable.
      expect(
        _cellAt(cells, const TimeOfDay(hour: 9, minute: 0)).state,
        SlotState.unavailable,
      );
      expect(
        _cellAt(cells, const TimeOfDay(hour: 9, minute: 30)).state,
        SlotState.unavailable,
      );
      // Trailing gap (after last end) → unavailable.
      expect(
        _cellAt(cells, const TimeOfDay(hour: 16, minute: 30)).state,
        SlotState.unavailable,
      );
      expect(
        _cellAt(cells, const TimeOfDay(hour: 19, minute: 0)).state,
        SlotState.unavailable,
      );
    });

    test(
      'noSchedule has no interior pause → zero timeOff cells (all grey)',
      () {
        final EffectiveDay day = _day(source: EffectiveSource.noSchedule);

        final List<SlotCell> cells = buildDayCells(day);

        expect(_timeOffTimes(cells), isEmpty);
        expect(
          cells.every((SlotCell c) => c.state == SlotState.unavailable),
          isTrue,
        );
      },
    );

    test('overrideDayOff reddens the WHOLE grid (not the pause path)', () {
      final EffectiveDay day = _day(source: EffectiveSource.overrideDayOff);

      final List<SlotCell> cells = buildDayCells(day);

      // Every cell is timeOff — regression guard that a day-off override is a
      // uniform fill, distinct from the interior-pause round-up.
      expect(_timeOffTimes(cells), hasLength(cells.length));
      expect(cells.every((SlotCell c) => c.state == SlotState.timeOff), isTrue);
    });
  });
}
