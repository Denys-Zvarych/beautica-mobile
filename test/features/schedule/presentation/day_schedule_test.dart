// Phase 15.2 — Unit tests for the day-grid slot projection (`buildDayCells`).
//
// The grid is a PURE RENDER PROJECTION of a resolved [EffectiveDay] (Phase
// 15.1) plus the day's bookings. These tests pin the SlotState mapping the
// screen relies on (3-state legend, user decision 2026-10-30):
//   • overlaps a CONFIRMED / COMPLETED booking    → SlotState.booked
//   • inside a working interval                   → SlotState.available
//   • OVERRIDE_DAY_OFF / break / NO_SCHEDULE gap  → SlotState.unavailable
// and the 30-minute cell boundaries (half-open [start, end) interval edges).
//
// No widget tree — this is the pure-Dart projection used by both the legend and
// the screen's grid, so it is unit-tested in isolation.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
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

/// Times of every cell painted [state], in grid order. Asserting on this list
/// pins both HOW MANY cells took the state and WHICH ones.
List<TimeOfDay> _timesIn(List<SlotCell> cells, SlotState state) => cells
    .where((SlotCell c) => c.state == state)
    .map((SlotCell c) => c.time)
    .toList();

/// A booking on [_day]'s date (2026-06-08, Kyiv summer time UTC+3) from Kyiv
/// wall-clock [sh]:[sm] for [minutes].
Booking _booking({
  required int sh,
  required int sm,
  int minutes = 30,
  BookingStatus status = BookingStatus.confirmed,
  String id = 'b-1',
}) {
  final DateTime startAt = DateTime.utc(2026, 6, 8, sh - 3, sm);
  return Booking(
    id: id,
    masterId: 'master-1',
    masterFirstName: 'Оля',
    masterLastName: 'Коваль',
    masterType: 'INDEPENDENT_MASTER',
    serviceId: 'service-1',
    serviceName: 'Манікюр',
    durationMinutes: minutes,
    price: 500,
    startAt: startAt,
    endAt: startAt.add(Duration(minutes: minutes)),
    status: status,
    canReview: false,
  );
}

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

    test('OVERRIDE_DAY_OFF paints every cell as unavailable', () {
      final EffectiveDay day = _day(source: EffectiveSource.overrideDayOff);

      final List<SlotCell> cells = buildDayCells(day);

      expect(
        cells.every((SlotCell c) => c.state == SlotState.unavailable),
        isTrue,
        reason: 'a whole-day day-off override reads «Неробочий час» (grey)',
      );
    });

    test('NO_SCHEDULE gap maps every cell to unavailable (all grey)', () {
      final EffectiveDay day = _day(source: EffectiveSource.noSchedule);

      final List<SlotCell> cells = buildDayCells(day);

      expect(
        cells.every((SlotCell c) => c.state == SlotState.unavailable),
        isTrue,
        reason: 'a NO_SCHEDULE gap reads all-grey (never booked)',
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

    test('a lunch gap between two intervals reads unavailable (break)', () {
      final EffectiveDay day = _day(
        source: EffectiveSource.template,
        intervals: <WorkInterval>[
          _interval(9, 0, 13, 0),
          _interval(14, 0, 18, 0),
        ],
      );

      final List<SlotCell> cells = buildDayCells(day);

      // 13:00–14:00 lunch gap → unavailable (grey «Неробочий час»); the two
      // work blocks → available.
      expect(
        _cellAt(cells, const TimeOfDay(hour: 13, minute: 30)).state,
        SlotState.unavailable,
        reason: 'the gap between two working intervals is non-working time',
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
  // BREAKS (2026-10-30). The gap between two consecutive working intervals is
  // non-working time: a cell lying ENTIRELY in a break reads unavailable; a
  // cell that still overlaps work by at least a minute stays available (the
  // retired pink pause round-up no longer applies).
  // ───────────────────────────────────────────────────────────────────────────
  group('buildDayCells — breaks read unavailable', () {
    test('30-min break [09:00–12:00, 12:30–18:00] → exactly ONE unavailable '
        'cell (12:00)', () {
      final EffectiveDay day = _day(
        source: EffectiveSource.template,
        intervals: <WorkInterval>[
          _interval(9, 0, 12, 0),
          _interval(12, 30, 18, 0),
        ],
      );

      final List<SlotCell> cells = buildDayCells(day);

      expect(_timesIn(cells, SlotState.unavailable), <TimeOfDay>[
        const TimeOfDay(hour: 12, minute: 0),
      ]);
      expect(_timesIn(cells, SlotState.booked), isEmpty);
    });

    test('45-min break [09:00–12:00, 12:45–18:00] → 12:00 unavailable, the '
        'partly-working 12:30 cell stays available', () {
      final EffectiveDay day = _day(
        source: EffectiveSource.template,
        intervals: <WorkInterval>[
          _interval(9, 0, 12, 0),
          _interval(12, 45, 18, 0),
        ],
      );

      final List<SlotCell> cells = buildDayCells(day);

      expect(_timesIn(cells, SlotState.unavailable), <TimeOfDay>[
        const TimeOfDay(hour: 12, minute: 0),
      ]);
      expect(
        _cellAt(cells, const TimeOfDay(hour: 12, minute: 30)).state,
        SlotState.available,
      );
    });

    test('15-min break inside one cell [09:00–12:15, 12:30–18:00] → no '
        'unavailable cell (the 12:00 cell still overlaps work)', () {
      final EffectiveDay day = _day(
        source: EffectiveSource.template,
        intervals: <WorkInterval>[
          _interval(9, 0, 12, 15),
          _interval(12, 30, 18, 0),
        ],
      );

      final List<SlotCell> cells = buildDayCells(day);

      expect(_timesIn(cells, SlotState.unavailable), isEmpty);
      expect(
        cells.every((SlotCell c) => c.state == SlotState.available),
        isTrue,
      );
    });

    test(
      'single interval → no unavailable; leading + trailing tails are clamped',
      () {
        final EffectiveDay day = _day(
          source: EffectiveSource.template,
          intervals: <WorkInterval>[_interval(10, 0, 16, 0)],
        );

        final List<SlotCell> cells = buildDayCells(day);

        expect(_timesIn(cells, SlotState.unavailable), isEmpty);
        expect(cells.first.time, const TimeOfDay(hour: 10, minute: 0));
        expect(cells.last.time, const TimeOfDay(hour: 15, minute: 30));
        expect(
          _hasCellAt(cells, const TimeOfDay(hour: 9, minute: 30)),
          isFalse,
        );
        expect(
          _hasCellAt(cells, const TimeOfDay(hour: 16, minute: 30)),
          isFalse,
        );
      },
    );
  });

  // ───────────────────────────────────────────────────────────────────────────
  // BOOKINGS (2026-10-30). A cell overlapping a CONFIRMED / COMPLETED booking
  // is booked and wins over every availability state; other statuses ignored.
  // ───────────────────────────────────────────────────────────────────────────
  group('buildDayCells — booked cells', () {
    final EffectiveDay workingDay = _day(
      source: EffectiveSource.template,
      intervals: <WorkInterval>[_interval(9, 0, 13, 0)],
    );

    test(
      'a 10:00–10:30 CONFIRMED booking → exactly the 10:00 cell is booked',
      () {
        final List<SlotCell> cells = buildDayCells(
          workingDay,
          bookings: <Booking>[_booking(sh: 10, sm: 0)],
        );

        expect(_timesIn(cells, SlotState.booked), <TimeOfDay>[
          const TimeOfDay(hour: 10, minute: 0),
        ]);
        expect(
          _cellAt(cells, const TimeOfDay(hour: 9, minute: 30)).state,
          SlotState.available,
        );
        expect(
          _cellAt(cells, const TimeOfDay(hour: 10, minute: 30)).state,
          SlotState.available,
        );
      },
    );

    test('a COMPLETED booking also paints booked; a 45-min one rounds up to '
        'two cells', () {
      final List<SlotCell> cells = buildDayCells(
        workingDay,
        bookings: <Booking>[
          _booking(sh: 11, sm: 0, minutes: 45, status: BookingStatus.completed),
        ],
      );

      expect(_timesIn(cells, SlotState.booked), <TimeOfDay>[
        const TimeOfDay(hour: 11, minute: 0),
        const TimeOfDay(hour: 11, minute: 30),
      ]);
    });

    for (final BookingStatus ignored in <BookingStatus>[
      BookingStatus.cancelled,
      BookingStatus.declined,
      BookingStatus.notCompleted,
    ]) {
      test(
        'a ${ignored.name} 10:00–10:30 booking leaves the cells available',
        () {
          final List<SlotCell> cells = buildDayCells(
            workingDay,
            bookings: <Booking>[_booking(sh: 10, sm: 0, status: ignored)],
          );

          expect(_timesIn(cells, SlotState.booked), isEmpty);
          expect(
            _cellAt(cells, const TimeOfDay(hour: 10, minute: 0)).state,
            SlotState.available,
          );
        },
      );
    }

    test('a booking inside a break paints booked over unavailable', () {
      final EffectiveDay day = _day(
        source: EffectiveSource.template,
        intervals: <WorkInterval>[
          _interval(9, 0, 12, 0),
          _interval(13, 0, 18, 0),
        ],
      );

      final List<SlotCell> cells = buildDayCells(
        day,
        bookings: <Booking>[_booking(sh: 12, sm: 0)],
      );

      expect(
        _cellAt(cells, const TimeOfDay(hour: 12, minute: 0)).state,
        SlotState.booked,
      );
      expect(
        _cellAt(cells, const TimeOfDay(hour: 12, minute: 30)).state,
        SlotState.unavailable,
      );
    });

    test('memo: the same day re-projected with/without bookings never serves '
        'a stale grid', () {
      final List<SlotCell> plain = buildDayCells(workingDay);
      final List<SlotCell> booked = buildDayCells(
        workingDay,
        bookings: <Booking>[_booking(sh: 10, sm: 0)],
      );
      final List<SlotCell> plainAgain = buildDayCells(workingDay);

      expect(_timesIn(plain, SlotState.booked), isEmpty);
      expect(_timesIn(booked, SlotState.booked), hasLength(1));
      expect(_timesIn(plainAgain, SlotState.booked), isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // REGRESSION (clamped-grid contract). The grid used to render trailing grey
  // "outside working hours" cells past the master's last interval end (e.g.
  // 18:00–19:30 cards on a day ending at 18:00). The fix made `_gridBounds`
  // minute-based and clamps the grid end EXACTLY to lastEnd. These cases pin
  // that no card renders at or after the working end, while interior breaks
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

    test('interior break survives while the trailing tail is clamped '
        '([09:00–12:00, 12:30–18:00])', () {
      // The 12:00 break cell ([12:00, 12:30) — work resumes at 12:30) must
      // still be emitted (unavailable), proving the clamp suppresses ONLY the
      // non-working tail, not interior breaks inside [firstStart, lastEnd).
      final EffectiveDay day = _day(
        source: EffectiveSource.template,
        intervals: <WorkInterval>[
          _interval(9, 0, 12, 0),
          _interval(12, 30, 18, 0),
        ],
      );

      final List<SlotCell> cells = buildDayCells(day);

      // Interior break preserved.
      expect(
        _cellAt(cells, const TimeOfDay(hour: 12, minute: 0)).state,
        SlotState.unavailable,
        reason: 'the interior break cell survives the clamp',
      );
      expect(
        _timesIn(cells, SlotState.unavailable),
        <TimeOfDay>[const TimeOfDay(hour: 12, minute: 0)],
        reason: 'exactly one interior break cell — no spurious grey cells',
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
