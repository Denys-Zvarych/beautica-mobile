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

  // 15-min step alignment (the new behaviour to guard). The editor snaps new
  // picks to 15-min steps, but a legacy / loaded schedule may carry a misaligned
  // edge — validateDayHours must flag it as `notAligned` so the master re-aligns
  // before re-saving. Every accepted edge minute is one of {:00, :15, :30, :45}.
  group('validateDayHours — 15-minute step alignment (notAligned)', () {
    test('window start minute :03 → notAligned, windowInvalid', () {
      final day = DayHours(window: _wi(9, 3, 18, 0), breaks: <BreakRange>[]);

      final err = validateDayHours(day);

      expect(err, isNotNull);
      expect(err!.kind, DayHoursErrorKind.notAligned);
      expect(err.message, 'Час має бути кратним 15 хвилинам');
      expect(err.windowInvalid, isTrue);
      expect(err.breakIndex, isNull);
    });

    test('window end minute :07 → notAligned, windowInvalid', () {
      final day = DayHours(window: _wi(9, 0, 18, 7), breaks: <BreakRange>[]);

      final err = validateDayHours(day);

      expect(err!.kind, DayHoursErrorKind.notAligned);
      expect(err.windowInvalid, isTrue);
    });

    test('break start minute :07 → notAligned ringing that break row', () {
      // The window is aligned, so the misalignment must surface on the break.
      final day = DayHours(
        window: _wi(9, 0, 18, 0),
        breaks: <BreakRange>[_br(13, 7, 14, 0)],
      );

      final err = validateDayHours(day);

      expect(err!.kind, DayHoursErrorKind.notAligned);
      expect(err.message, 'Час має бути кратним 15 хвилинам');
      expect(err.breakIndex, 0);
      expect(err.windowInvalid, isFalse);
    });

    test('break end minute :03 → notAligned ringing that break row', () {
      final day = DayHours(
        window: _wi(9, 0, 18, 0),
        breaks: <BreakRange>[_br(13, 0, 14, 3)],
      );

      final err = validateDayHours(day);

      expect(err!.kind, DayHoursErrorKind.notAligned);
      expect(err.breakIndex, 0);
    });

    test('window misalignment is reported before any break problem', () {
      // A :05 window start AND a self-inverted break: the window guard runs
      // first, so the typed kind is notAligned (window), not breakEndBeforeStart.
      final day = DayHours(
        window: _wi(9, 5, 18, 0),
        breaks: <BreakRange>[_br(14, 0, 13, 0)],
      );

      final err = validateDayHours(day);

      expect(err!.kind, DayHoursErrorKind.notAligned);
      expect(err.windowInvalid, isTrue);
    });

    test('all four 15-min steps (:00/:15/:30/:45) are accepted → null', () {
      // Window edges on :00 and :45; break edges on :15 and :30 — every edge is
      // a multiple of 15, so the day validates clean.
      final day = DayHours(
        window: _wi(9, 0, 17, 45),
        breaks: <BreakRange>[_br(13, 15, 13, 30)],
      );

      expect(validateDayHours(day), isNull);
      expect(dayHoursValid(day), isTrue);
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

  // REGRESSION (single-span day summary): the day-panel "Робочий день: …" line
  // now uses summariseSpan, which collapses any interior pause into ONE overall
  // span (firstStart–lastEnd). This pins that behaviour so the day-summary can
  // never silently revert to the multi-segment summariseIntervals output. The
  // multi-interval case below FAILS against the old summariseIntervals call
  // (which produced "09:00–13:00  ·  14:00–18:00") and PASSES now.
  group('summariseSpan — single-span day summary', () {
    test('empty list → "Вихідний"', () {
      expect(summariseSpan(const <WorkInterval>[]), 'Вихідний');
    });

    test('single interval → that interval as the span', () {
      expect(summariseSpan(<WorkInterval>[_wi(9, 0, 18, 0)]), '09:00–18:00');
    });

    test('day WITH a pause → ONE collapsed span (firstStart–lastEnd)', () {
      // A lunch-break day: 09:00–13:00 then 14:00–18:00.
      final span = summariseSpan(<WorkInterval>[
        _wi(9, 0, 13, 0),
        _wi(14, 0, 18, 0),
      ]);

      expect(span, '09:00–18:00');
    });

    test('multi-interval span does NOT contain the "·" segment separator', () {
      // Proves the bug fix: summariseIntervals would emit the "  ·  " join here;
      // summariseSpan must not — it shows the overall span only.
      final span = summariseSpan(<WorkInterval>[
        _wi(9, 0, 13, 0),
        _wi(14, 0, 18, 0),
      ]);

      expect(span.contains('·'), isFalse);
      // And it must differ from the segment-listing helper for the same input.
      expect(
        span,
        isNot(
          equals(
            summariseIntervals(<WorkInterval>[
              _wi(9, 0, 13, 0),
              _wi(14, 0, 18, 0),
            ]),
          ),
        ),
      );
    });

    test(
      'unsorted intervals → min start to max end (scan, not first/last)',
      () {
        final span = summariseSpan(<WorkInterval>[
          _wi(14, 0, 18, 0),
          _wi(9, 0, 13, 0),
        ]);

        expect(span, '09:00–18:00');
      },
    );
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

  // ── 2026-07-26 booking-conflict design: OverrideConflictCheck / ────────────
  //    OverrideConflict — the day-off-conflict dialog's sole data input.
  //
  // Zero coverage existed for this model before this audit (mobile-qa,
  // 2026-07-26) — the widget-level dialog tests
  // (`day_off_conflict_dialog_test.dart`) exercise it indirectly, but the
  // getters themselves (the exact boundary conditions the dialog's copy
  // selection branches on) had no direct test.
  group('OverrideConflictCheck', () {
    OverrideConflict conflict({String id = 'b1', DateTime? date}) =>
        OverrideConflict(
          bookingId: id,
          appointmentId: null,
          date: date ?? DateTime(2026, 7, 27),
          startsAt: DateTime.utc(2026, 7, 27, 10),
          endsAt: DateTime.utc(2026, 7, 27, 11),
          clientDisplayName: 'Клієнт',
          serviceName: 'Послуга',
        );

    test('isEmpty / isNotEmpty mirror conflicts.isEmpty', () {
      const empty = OverrideConflictCheck(
        conflicts: <OverrideConflict>[],
        totalCount: 0,
        truncated: false,
        scanTruncated: false,
      );
      expect(empty.isEmpty, isTrue);
      expect(empty.isNotEmpty, isFalse);

      final nonEmpty = OverrideConflictCheck(
        conflicts: <OverrideConflict>[conflict()],
        totalCount: 1,
        truncated: false,
        scanTruncated: false,
      );
      expect(nonEmpty.isEmpty, isFalse);
      expect(nonEmpty.isNotEmpty, isTrue);
    });

    test('isCountExact is false ONLY when scanTruncated — independent of '
        'truncated', () {
      OverrideConflictCheck check({
        required bool truncated,
        required bool scanTruncated,
      }) => OverrideConflictCheck(
        conflicts: <OverrideConflict>[conflict()],
        totalCount: 10,
        truncated: truncated,
        scanTruncated: scanTruncated,
      );

      expect(
        check(truncated: false, scanTruncated: false).isCountExact,
        isTrue,
      );
      // Result list trimmed, but the SCAN was not — totalCount is still an
      // exact figure, just not equal to conflicts.length.
      expect(
        check(truncated: true, scanTruncated: false).isCountExact,
        isTrue,
        reason:
            'truncated (a capped RESULT LIST) alone must not make the count '
            'inexact — only scanTruncated (a capped CANDIDATE SCAN) does',
      );
      expect(
        check(truncated: false, scanTruncated: true).isCountExact,
        isFalse,
      );
      expect(check(truncated: true, scanTruncated: true).isCountExact, isFalse);
    });

    test('spansMultipleDates is false for <2 conflicts or a single shared '
        'date, true once a second date appears', () {
      final d1 = DateTime(2026, 7, 27);
      final d2 = DateTime(2026, 7, 28);

      expect(
        const OverrideConflictCheck(
          conflicts: <OverrideConflict>[],
          totalCount: 0,
          truncated: false,
          scanTruncated: false,
        ).spansMultipleDates,
        isFalse,
        reason: '0 conflicts',
      );

      expect(
        OverrideConflictCheck(
          conflicts: <OverrideConflict>[conflict(date: d1)],
          totalCount: 1,
          truncated: false,
          scanTruncated: false,
        ).spansMultipleDates,
        isFalse,
        reason: '1 conflict — below the <2 guard',
      );

      expect(
        OverrideConflictCheck(
          conflicts: <OverrideConflict>[
            conflict(id: 'b1', date: d1),
            conflict(id: 'b2', date: d1),
          ],
          totalCount: 2,
          truncated: false,
          scanTruncated: false,
        ).spansMultipleDates,
        isFalse,
        reason: '2 conflicts sharing the SAME date',
      );

      expect(
        OverrideConflictCheck(
          conflicts: <OverrideConflict>[
            conflict(id: 'b1', date: d1),
            conflict(id: 'b2', date: d2),
          ],
          totalCount: 2,
          truncated: false,
          scanTruncated: false,
        ).spansMultipleDates,
        isTrue,
        reason: '2 conflicts on DIFFERENT dates',
      );
    });
  });

  group('ScheduleOverride.narrowedHoursLabel', () {
    test('null for a day-off (no window to summarise)', () {
      final o = ScheduleOverride.dayOff(
        start: DateTime(2026, 7, 27),
        end: DateTime(2026, 7, 27),
      );
      expect(o.narrowedHoursLabel, isNull);
    });

    test('earliest interval start – latest interval end for INTERVAL mode', () {
      final o = ScheduleOverride.custom(
        start: DateTime(2026, 7, 27),
        end: DateTime(2026, 7, 27),
        intervals: <WorkInterval>[_wi(14, 0, 18, 0), _wi(9, 0, 12, 0)],
      );
      expect(o.narrowedHoursLabel, '09:00–18:00');
    });

    test('earliest – latest discrete start time for EXPLICIT_TIMES mode', () {
      final o = ScheduleOverride.explicitTimes(
        start: DateTime(2026, 7, 27),
        end: DateTime(2026, 7, 27),
        times: <TimeOfDay>[_t(15, 0), _t(9, 0), _t(11, 0)],
      );
      expect(o.narrowedHoursLabel, '09:00–15:00');
    });
  });
}
