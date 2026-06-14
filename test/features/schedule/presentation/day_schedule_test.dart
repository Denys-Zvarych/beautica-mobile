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

/// The resolved cell at [time] within [cells], or `null` when no cell with that
/// start was emitted. On a working day the grid is CLAMPED to the working span
/// (start floored to the enclosing 30-min cell, end == last interval end), so
/// any cell at or after the last interval end — or before the clamped start —
/// is simply absent. Use [_hasCellAt] to assert presence/absence directly.
SlotCell? _cellAtOrNull(List<SlotCell> cells, TimeOfDay time) {
  for (final SlotCell c in cells) {
    if (c.time.hour == time.hour && c.time.minute == time.minute) return c;
  }
  return null;
}

/// The resolved cell at [time]; fails the test if no such cell was emitted.
SlotCell _cellAt(List<SlotCell> cells, TimeOfDay time) {
  final SlotCell? cell = _cellAtOrNull(cells, time);
  expect(
    cell,
    isNotNull,
    reason:
        'expected a cell at ${time.hour}:${time.minute} but it was clamped '
        'away or never generated',
  );
  return cell!;
}

/// Whether a cell with start [time] was emitted into [cells].
bool _hasCellAt(List<SlotCell> cells, TimeOfDay time) =>
    _cellAtOrNull(cells, time) != null;

/// Times of every cell painted [SlotState.timeOff], in grid order. Asserting on
/// this list pins both HOW MANY cells reddened and WHICH ones.
List<TimeOfDay> timeOffTimes(List<SlotCell> cells) => cells
    .where((SlotCell c) => c.state == SlotState.timeOff)
    .map((SlotCell c) => c.time)
    .toList();

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
      'interval coverage maps to available; the trailing tail is clamped away',
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
        // The grid now clamps to lastEnd (13:00): cells at/after the working
        // end are no longer generated — assert their ABSENCE, not a state.
        expect(
          _hasCellAt(cells, const TimeOfDay(hour: 14, minute: 0)),
          isFalse,
          reason: '14:00 is past lastEnd (13:00) — clamped away, no card',
        );
        expect(
          _hasCellAt(cells, const TimeOfDay(hour: 18, minute: 30)),
          isFalse,
          reason: '18:30 is far past the working span — clamped away',
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
      // The grid clamps its START to the first interval start (12:00 here), so
      // the 09:30 lead-in cell is never generated.
      expect(
        _hasCellAt(cells, const TimeOfDay(hour: 9, minute: 30)),
        isFalse,
        reason: 'grid starts at the first interval (12:00) — no 09:30 cell',
      );
      // The grid also clamps its END to lastEnd (16:00) — the first cell is
      // 12:00 and there is no trailing tail past 16:00.
      expect(cells.first.time, const TimeOfDay(hour: 12, minute: 0));
      expect(
        _hasCellAt(cells, const TimeOfDay(hour: 16, minute: 0)),
        isFalse,
        reason: '16:00 == lastEnd is the exclusive grid end — clamped away',
      );
    });
  });

  group('buildDayCells — 30-min boundary alignment (half-open intervals)', () {
    test('09:00–13:00 → last emitted cell is 12:30; no 13:00 cell', () {
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
      // The grid end == lastEnd (13:00) and the loop is half-open, so the last
      // emitted cell is 12:30 and the 13:00 cell is never generated.
      expect(
        cells.last.time,
        const TimeOfDay(hour: 12, minute: 30),
        reason: 'the clamped grid stops at lastEnd — 12:30 is the final cell',
      );
      expect(
        _hasCellAt(cells, const TimeOfDay(hour: 13, minute: 0)),
        isFalse,
        reason: '13:00 == lastEnd is the exclusive end — clamped, no card',
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

    test('uniform/no-schedule day uses the 09:00–19:00 reference window', () {
      // The clamp applies ONLY to working days. A no-schedule (empty-intervals)
      // day still falls back to the fixed reference window [09:00, 19:00).
      final EffectiveDay day = _day(source: EffectiveSource.noSchedule);

      final List<SlotCell> cells = buildDayCells(day);

      // Half-open [540, 1140) in 30-min steps: 09:00..18:30 → 20 cells, the
      // first at 09:00 and the last at 18:30 (19:00 is the exclusive end).
      expect(cells.length, 20);
      expect(cells.first.time, const TimeOfDay(hour: 9, minute: 0));
      expect(cells.last.time, const TimeOfDay(hour: 18, minute: 30));
      expect(
        _hasCellAt(cells, const TimeOfDay(hour: 19, minute: 0)),
        isFalse,
        reason: '19:00 is the exclusive reference-window end — no cell',
      );
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
        timeOffTimes(cells),
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
        timeOffTimes(cells),
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
        timeOffTimes(cells),
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
        timeOffTimes(cells),
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
        timeOffTimes(cells),
        <TimeOfDay>[
          const TimeOfDay(hour: 11, minute: 0),
          const TimeOfDay(hour: 14, minute: 0),
          const TimeOfDay(hour: 14, minute: 30),
        ],
        reason: 'each interior gap rounds up to its own touched cells',
      );
    });

    test(
      'no interior pause → no timeOff; leading + trailing tails are clamped',
      () {
        // A single interval 10:00–16:00: the grid clamps to [10:00, 16:00). The
        // 09:00/09:30 lead-in and the 16:00.. run-out are no longer generated.
        final EffectiveDay day = _day(
          source: EffectiveSource.template,
          intervals: <WorkInterval>[_interval(10, 0, 16, 0)],
        );

        final List<SlotCell> cells = buildDayCells(day);

        // No interior gap exists, so nothing reddens.
        expect(
          timeOffTimes(cells),
          isEmpty,
          reason: 'a single interval has no interior pause → no timeOff cells',
        );
        // The clamped grid starts at 10:00 and ends at 16:00 (exclusive).
        expect(cells.first.time, const TimeOfDay(hour: 10, minute: 0));
        expect(cells.last.time, const TimeOfDay(hour: 15, minute: 30));
        // Leading gap clamped away (grid starts at the first interval).
        expect(
          _hasCellAt(cells, const TimeOfDay(hour: 9, minute: 0)),
          isFalse,
          reason: 'grid starts at 10:00 — the 09:00 lead-in is clamped',
        );
        expect(
          _hasCellAt(cells, const TimeOfDay(hour: 9, minute: 30)),
          isFalse,
        );
        // Trailing tail clamped away (grid ends exactly at lastEnd).
        expect(
          _hasCellAt(cells, const TimeOfDay(hour: 16, minute: 30)),
          isFalse,
          reason: 'grid ends at 16:00 — the trailing run-out is clamped',
        );
        expect(
          _hasCellAt(cells, const TimeOfDay(hour: 19, minute: 0)),
          isFalse,
        );
      },
    );

    test(
      'noSchedule has no interior pause → zero timeOff cells (all grey)',
      () {
        final EffectiveDay day = _day(source: EffectiveSource.noSchedule);

        final List<SlotCell> cells = buildDayCells(day);

        expect(timeOffTimes(cells), isEmpty);
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
      expect(timeOffTimes(cells), hasLength(cells.length));
      expect(cells.every((SlotCell c) => c.state == SlotState.timeOff), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // REGRESSION (clamped-grid contract). The grid used to render trailing grey
  // "outside working hours" cells past the master's last interval end (e.g.
  // 18:00–19:30 cards on a day ending at 18:00). The fix made `_gridBounds`
  // minute-based and clamps the grid end EXACTLY to lastEnd. These cases pin
  // that no card renders at or after the working end, while interior pauses
  // (inside the working span) still survive.
  // ───────────────────────────────────────────────────────────────────────────
  group('buildDayCells — trailing-tail clamp regression', () {
    test(
      'a day ending at 18:00 emits ZERO cells at/after 18:00; last cell is 17:30',
      () {
        // 09:00–18:00 working day. Before the fix this rendered 18:00, 18:30,
        // and 19:00/19:30 grey "off" cards. The grid end now == lastEnd (18:00).
        final EffectiveDay day = _day(
          source: EffectiveSource.template,
          intervals: <WorkInterval>[_interval(9, 0, 18, 0)],
        );

        final List<SlotCell> cells = buildDayCells(day);

        // No card at or after the last interval end.
        expect(
          cells.where((SlotCell c) => c.time.hour >= 18),
          isEmpty,
          reason: 'the non-working tail past 18:00 is clamped — no cards',
        );
        // The 17:30 cell ([17:30, 18:00)) is the last emitted, and it is green.
        expect(cells.last.time, const TimeOfDay(hour: 17, minute: 30));
        expect(cells.last.state, SlotState.available);
        // Explicit absence of the cells that used to leak.
        expect(
          _hasCellAt(cells, const TimeOfDay(hour: 18, minute: 0)),
          isFalse,
        );
        expect(
          _hasCellAt(cells, const TimeOfDay(hour: 18, minute: 30)),
          isFalse,
        );
      },
    );

    test('interior pause survives while the trailing tail is clamped '
        '([09:00–12:00, 12:30–18:00])', () {
      // The 12:00 pause cell ([12:00, 12:30) — work resumes at 12:30) must
      // still paint timeOff, proving the clamp suppresses ONLY the non-working
      // tail, not interior pauses inside [firstStart, lastEnd).
      final EffectiveDay day = _day(
        source: EffectiveSource.template,
        intervals: <WorkInterval>[
          _interval(9, 0, 12, 0),
          _interval(12, 30, 18, 0),
        ],
      );

      final List<SlotCell> cells = buildDayCells(day);

      // Interior pause preserved.
      expect(
        _cellAt(cells, const TimeOfDay(hour: 12, minute: 0)).state,
        SlotState.timeOff,
        reason: 'the interior pause cell survives the clamp',
      );
      expect(
        timeOffTimes(cells),
        <TimeOfDay>[const TimeOfDay(hour: 12, minute: 0)],
        reason: 'exactly one interior pause cell — no spurious timeOff cells',
      );
      // Trailing tail past 18:00 clamped away.
      expect(
        cells.where((SlotCell c) => c.time.hour >= 18),
        isEmpty,
        reason: 'zero cards at/after lastEnd (18:00)',
      );
      expect(cells.last.time, const TimeOfDay(hour: 17, minute: 30));
      expect(cells.last.state, SlotState.available);
    });
  });
}
