// Phase 15.1 — Unit tests for the canonical schedule domain model.
//
// Covers the lossless window+breaks ⇄ intervals round-trip (the heart of the
// editor port), validateDayHours (exact ported Ukrainian messages),
// summariseIntervals, and ISO-weekday preservation on TemplateDay.
//
// Pure Dart: no ProviderScope, no widget tree, no network.

import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TimeOfDay _t(int h, [int m = 0]) => TimeOfDay(hour: h, minute: m);

WorkInterval _wi(int sh, int sm, int eh, int em) =>
    WorkInterval(start: _t(sh, sm), end: _t(eh, em));

BreakRange _br(int sh, int sm, int eh, int em) =>
    BreakRange(start: _t(sh, sm), end: _t(eh, em));

/// Asserts an interval matches the given HH:MM bounds.
void _expectInterval(WorkInterval w, int sh, int sm, int eh, int em) {
  expect(w.start.hour, sh);
  expect(w.start.minute, sm);
  expect(w.end.hour, eh);
  expect(w.end.minute, em);
}

void main() {
  group('DayHours.toIntervals / fromIntervals — lossless round-trip', () {
    test('zero breaks → one solid block 09:00–18:00', () {
      final day = DayHours(window: _wi(9, 0, 18, 0), breaks: <BreakRange>[]);

      final intervals = day.toIntervals();

      expect(intervals, hasLength(1));
      _expectInterval(intervals.single, 9, 0, 18, 0);

      // fromIntervals reconstructs the same window with no breaks.
      final back = DayHours.fromIntervals(intervals);
      _expectInterval(back.window, 9, 0, 18, 0);
      expect(back.breaks, isEmpty);
    });

    test('one lunch break — preview example 09:00–13:00 · 14:00–18:00 '
        '⇄ window 09:00–18:00 + break 13:00–14:00', () {
      final day = DayHours(
        window: _wi(9, 0, 18, 0),
        breaks: <BreakRange>[_br(13, 0, 14, 0)],
      );

      // window+breaks → intervals
      final intervals = day.toIntervals();
      expect(intervals, hasLength(2));
      _expectInterval(intervals[0], 9, 0, 13, 0);
      _expectInterval(intervals[1], 14, 0, 18, 0);
      expect(summariseIntervals(intervals), '09:00–13:00  ·  14:00–18:00');

      // intervals → window+breaks (the exact inverse)
      final back = DayHours.fromIntervals(intervals);
      _expectInterval(back.window, 9, 0, 18, 0);
      expect(back.breaks, hasLength(1));
      expect(back.breaks.single.start, _t(13, 0));
      expect(back.breaks.single.end, _t(14, 0));

      // and back to intervals again — still lossless
      final intervals2 = back.toIntervals();
      expect(intervals2, hasLength(2));
      _expectInterval(intervals2[0], 9, 0, 13, 0);
      _expectInterval(intervals2[1], 14, 0, 18, 0);
    });

    test('two breaks → three blocks, round-trips losslessly', () {
      final day = DayHours(
        window: _wi(9, 0, 19, 0),
        breaks: <BreakRange>[_br(11, 0, 11, 30), _br(14, 0, 15, 0)],
      );

      final intervals = day.toIntervals();
      expect(intervals, hasLength(3));
      _expectInterval(intervals[0], 9, 0, 11, 0);
      _expectInterval(intervals[1], 11, 30, 14, 0);
      _expectInterval(intervals[2], 15, 0, 19, 0);

      final back = DayHours.fromIntervals(intervals);
      _expectInterval(back.window, 9, 0, 19, 0);
      expect(back.breaks, hasLength(2));
      expect(back.breaks[0].start, _t(11, 0));
      expect(back.breaks[0].end, _t(11, 30));
      expect(back.breaks[1].start, _t(14, 0));
      expect(back.breaks[1].end, _t(15, 0));
    });

    test('break touching the window edge (end == window end) is ignored', () {
      // A break that ends exactly at the window end leaves no trailing block —
      // toIntervals must NOT emit it (guard: b.endMinutes >= window.endMinutes).
      final day = DayHours(
        window: _wi(9, 0, 18, 0),
        breaks: <BreakRange>[_br(17, 0, 18, 0)],
      );

      final intervals = day.toIntervals();

      expect(intervals, hasLength(1), reason: 'edge-touching break dropped');
      _expectInterval(intervals.single, 9, 0, 18, 0);
    });

    test('inverted / out-of-window break is skipped gracefully', () {
      // Inverted (end <= start) AND a break starting at the window start — both
      // are skipped; toIntervals degrades to the bare window rather than
      // emptying the day.
      final day = DayHours(
        window: _wi(9, 0, 18, 0),
        breaks: <BreakRange>[
          _br(15, 0, 14, 0), // inverted
          _br(9, 0, 10, 0), // starts at window start (b.start <= cursor)
        ],
      );

      final intervals = day.toIntervals();

      // The 09:00 break is dropped (starts at cursor); inverted is dropped;
      // result collapses to the bare window.
      expect(intervals, hasLength(1));
      _expectInterval(intervals.single, 9, 0, 18, 0);
    });
  });

  group('validateDayHours — exact ported Ukrainian messages', () {
    test('valid day → null', () {
      final day = DayHours(
        window: _wi(9, 0, 18, 0),
        breaks: <BreakRange>[_br(13, 0, 14, 0)],
      );
      expect(validateDayHours(day), isNull);
      expect(dayHoursValid(day), isTrue);
    });

    test('window end <= start → window message, windowInvalid', () {
      final day = DayHours(window: _wi(18, 0, 9, 0), breaks: <BreakRange>[]);

      final err = validateDayHours(day);

      expect(err, isNotNull);
      expect(
        err!.message,
        'Час завершення робочого дня має бути пізніше початку',
      );
      expect(err.windowInvalid, isTrue);
      expect(err.breakIndex, isNull);
    });

    test('break end <= start → break message with the right index', () {
      final day = DayHours(
        window: _wi(9, 0, 18, 0),
        breaks: <BreakRange>[_br(14, 0, 13, 0)],
      );

      final err = validateDayHours(day);

      expect(err!.message, 'Час завершення перерви має бути пізніше початку');
      expect(err.breakIndex, 0);
      expect(err.windowInvalid, isFalse);
    });

    test('break outside the window → out-of-bounds message', () {
      final day = DayHours(
        window: _wi(9, 0, 18, 0),
        breaks: <BreakRange>[_br(19, 0, 20, 0)],
      );

      final err = validateDayHours(day);

      expect(err!.message, 'Перерва має бути в межах робочих годин');
      expect(err.breakIndex, 0);
    });

    test('overlapping breaks → overlap message ringing the later row', () {
      // Breaks given out of order; the later (overlapping) one rings — the
      // function pairs each break with its ORIGINAL index before sorting.
      final day = DayHours(
        window: _wi(9, 0, 18, 0),
        breaks: <BreakRange>[
          _br(12, 0, 13, 30), // index 0
          _br(13, 0, 14, 0), // index 1 — starts before index 0 ends
        ],
      );

      final err = validateDayHours(day);

      expect(err!.message, 'Перерви не можуть перетинатися');
      expect(err.breakIndex, 1);
    });
  });

  group('summariseIntervals', () {
    test('empty list → "Вихідний"', () {
      expect(summariseIntervals(const <WorkInterval>[]), 'Вихідний');
    });

    test('unsorted intervals are sorted and joined with "  ·  "', () {
      final summary = summariseIntervals(<WorkInterval>[
        _wi(14, 0, 18, 0),
        _wi(9, 0, 13, 0),
      ]);

      expect(summary, '09:00–13:00  ·  14:00–18:00');
    });

    test('single interval → no separator', () {
      expect(
        summariseIntervals(<WorkInterval>[_wi(9, 0, 18, 0)]),
        '09:00–18:00',
      );
    });
  });

  group('TemplateDay — ISO weekday preserved', () {
    test('dayOfWeek 1..7 retained, isDayOff / hasError reflect intervals', () {
      for (var dow = 1; dow <= 7; dow++) {
        final day = TemplateDay(
          dayOfWeek: dow,
          label: 'd$dow',
          intervals: dow == 7
              ? <WorkInterval>[]
              : <WorkInterval>[_wi(9, 0, 18, 0)],
        );
        expect(day.dayOfWeek, dow);
      }

      final off = TemplateDay(
        dayOfWeek: 7,
        label: 'Неділя',
        intervals: <WorkInterval>[],
      );
      expect(off.isDayOff, isTrue);
      expect(off.hasError, isFalse);

      final broken = TemplateDay(
        dayOfWeek: 1,
        label: 'Понеділок',
        intervals: <WorkInterval>[_wi(18, 0, 9, 0)], // inverted
      );
      expect(broken.isDayOff, isFalse);
      expect(broken.hasError, isTrue);
    });
  });
}
