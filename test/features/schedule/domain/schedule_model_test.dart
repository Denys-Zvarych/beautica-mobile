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

    // REWRITTEN (availability data-loss bugfix). This test previously asserted
    // the DEFECT: `toIntervals` used to `continue` past any break touching a
    // window edge without advancing the cursor, so a 17:00–18:00 break was
    // silently discarded and the day persisted as a full 09:00–18:00 window.
    // The break is now CLAMPED to the remaining window and the cursor always
    // advances, so an end-flush break carves real time off the tail edge —
    // it simply leaves no trailing block, which is not the same as being
    // ignored. Asserting `18` here again would re-lock the bug.
    test('a break flush against the window END carves the tail off: '
        '17:00–18:00 leaves [09:00–17:00], NOT the full window', () {
      final day = DayHours(
        window: _wi(9, 0, 18, 0),
        breaks: <BreakRange>[_br(17, 0, 18, 0)],
      );

      final intervals = day.toIntervals();

      expect(
        intervals,
        hasLength(1),
        reason: 'an end-flush break emits no trailing block, only the head',
      );
      _expectInterval(intervals.single, 9, 0, 17, 0);
      // Pin the availability loss explicitly: the persisted day must be one
      // hour SHORTER than the window the master typed.
      expect(
        summariseIntervals(intervals),
        '09:00–17:00',
        reason:
            'persisting 09:00–18:00 here would advertise availability the '
            'master explicitly blocked out',
      );
    });

    // REWRITTEN + SPLIT. The former single test conflated two behaviours under
    // one "skipped gracefully" name and asserted the bug for the second of
    // them. They are now separate tests because only ONE of the two changed:
    //   • a genuinely inverted break is still dropped (unchanged, below);
    //   • a break flush against the window START now TAKES EFFECT (it used to
    //     be discarded, collapsing the result back to the bare window).
    test('a genuinely inverted break (end <= start) is dropped and leaves the '
        'rest of the day untouched', () {
      // Inverted ranges are nonsense the editor can transiently produce while
      // a picker is mid-edit; `toIntervals` drops them rather than emitting a
      // negative-length block. With no other break the full window survives.
      final day = DayHours(
        window: _wi(9, 0, 18, 0),
        breaks: <BreakRange>[_br(15, 0, 14, 0)],
      );

      final intervals = day.toIntervals();

      expect(intervals, hasLength(1));
      _expectInterval(intervals.single, 9, 0, 18, 0);
    });

    test('a break flush against the window START now takes effect: '
        '09:00–10:00 leaves [10:00–18:00], and a sibling inverted break does '
        'not resurrect the lost hour', () {
      // The exact reported bug: window 09:00–18:00 + a «Перерва» 09:00–10:00
      // (flush against the START). The old guard skipped any break whose start
      // was at/behind the cursor WITHOUT advancing it, so the save persisted a
      // full 09:00–18:00 day — the break vanished after validation had already
      // passed and Save was enabled. The break is now clamped and the cursor
      // advances to its end, so the day starts at 10:00.
      final day = DayHours(
        window: _wi(9, 0, 18, 0),
        breaks: <BreakRange>[
          _br(15, 0, 14, 0), // inverted — dropped
          _br(9, 0, 10, 0), // flush against the window start — takes effect
        ],
      );

      final intervals = day.toIntervals();

      expect(intervals, hasLength(1));
      _expectInterval(intervals.single, 10, 0, 18, 0);
      expect(
        intervals.single.startMinutes,
        greaterThan(day.window.startMinutes),
        reason:
            'the persisted day must start AFTER the window start — a 09:00 '
            'start is the discarded-break regression',
      );
    });
  });

  // ── REGRESSION (availability data-loss, CRITICAL) ──────────────────────────
  //
  // `toIntervals()` used to `continue` past any break touching a window edge
  // without advancing its cursor. Consequences, in ascending severity:
  //   • start-flush break  → the blocked hour was silently restored,
  //   • end-flush break    → same at the tail,
  //   • whole-window break → an EMPTY result hit the old `if (result.isEmpty)`
  //     fallback, which re-emitted the bare window: the persisted schedule
  //     advertised FULL availability, the exact inverse of the intent, and an
  //     overbooking exposure.
  // All three are now correct: clamp + always advance, no bare-window fallback,
  // and a whole-window break set is rejected by `validateDayHours` before it
  // can reach `toIntervals` at all.
  group('DayHours.toIntervals — edge-flush breaks (regression table)', () {
    // Window is 09:00–18:00 for every row; only the break set varies.
    final List<({String name, List<BreakRange> breaks, List<List<int>> want})>
    cases = <({String name, List<BreakRange> breaks, List<List<int>> want})>[
      (
        name: 'start-flush 09:00–10:00 → [10:00–18:00]',
        breaks: <BreakRange>[_br(9, 0, 10, 0)],
        want: <List<int>>[
          <int>[10, 0, 18, 0],
        ],
      ),
      (
        name: 'end-flush 17:00–18:00 → [09:00–17:00]',
        breaks: <BreakRange>[_br(17, 0, 18, 0)],
        want: <List<int>>[
          <int>[9, 0, 17, 0],
        ],
      ),
      (
        name: 'both edges flush → [10:00–17:00]',
        breaks: <BreakRange>[_br(9, 0, 10, 0), _br(17, 0, 18, 0)],
        want: <List<int>>[
          <int>[10, 0, 17, 0],
        ],
      ),
      (
        // CONTROL: the interior case never regressed — it pins that the fix
        // did not change the ordinary split-day behaviour.
        name: 'interior 13:00–14:00 → [09:00–13:00, 14:00–18:00] (control)',
        breaks: <BreakRange>[_br(13, 0, 14, 0)],
        want: <List<int>>[
          <int>[9, 0, 13, 0],
          <int>[14, 0, 18, 0],
        ],
      ),
    ];

    for (final c in cases) {
      test(c.name, () {
        final day = DayHours(window: _wi(9, 0, 18, 0), breaks: c.breaks);

        final intervals = day.toIntervals();

        expect(
          intervals,
          hasLength(c.want.length),
          reason: 'expected ${c.want.length} working block(s) for ${c.name}',
        );
        for (int i = 0; i < c.want.length; i++) {
          _expectInterval(
            intervals[i],
            c.want[i][0],
            c.want[i][1],
            c.want[i][2],
            c.want[i][3],
          );
        }
        // Cross-check: no emitted block may overlap ANY break — the property
        // the discarded-break bug violated.
        for (final WorkInterval w in intervals) {
          for (final BreakRange b in c.breaks) {
            expect(
              w.startMinutes >= b.endMinutes || w.endMinutes <= b.startMinutes,
              isTrue,
              reason:
                  'working block ${formatTime(w.start)}–${formatTime(w.end)} '
                  'overlaps break ${formatTime(b.start)}–${formatTime(b.end)}',
            );
          }
        }
      });
    }

    test('a whole-window break emits NO working block — it must never collapse '
        'back to the bare window (overbooking hazard)', () {
      // `validateDayHours` rejects this shape up-front (see the
      // breakCoversWholeWindow group below), so the editor can never reach
      // here. This pins the defence-in-depth behaviour of the collapsed
      // fallback's REMOVAL: if a caller ignores validation, the result is
      // empty (indistinguishable from a day off) — never FULL availability,
      // which is the exact inverse of what the master asked for.
      final day = DayHours(
        window: _wi(9, 0, 18, 0),
        breaks: <BreakRange>[_br(9, 0, 18, 0)],
      );

      expect(day.toIntervals(), isEmpty);
    });

    // The two remaining `continue` arms are unreachable through the editor
    // (`validateDayHours` rejects overlaps and out-of-window breaks first), but
    // they are exactly the arms the bug lived in — an early `continue` that
    // fails to advance the cursor. Pin that they degrade SAFELY: every emitted
    // block is forward-going, in-window, and non-overlapping.
    test('degrades safely on break sets validation would have rejected '
        '(overlapping + wholly out-of-window)', () {
      final day = DayHours(
        window: _wi(9, 0, 18, 0),
        breaks: <BreakRange>[
          _br(10, 0, 13, 0),
          _br(11, 0, 12, 0), // swallowed: entirely behind the cursor
          _br(19, 0, 20, 0), // wholly past the window end
          _br(8, 0, 9, 30), // starts before the window: clamped to 09:00
        ],
      );

      final intervals = day.toIntervals();

      for (final WorkInterval w in intervals) {
        expect(
          w.endMinutes,
          greaterThan(w.startMinutes),
          reason: 'no emitted block may be zero-length or inverted',
        );
        expect(w.startMinutes, greaterThanOrEqualTo(day.window.startMinutes));
        expect(w.endMinutes, lessThanOrEqualTo(day.window.endMinutes));
      }
      for (int i = 1; i < intervals.length; i++) {
        expect(
          intervals[i].startMinutes,
          greaterThanOrEqualTo(intervals[i - 1].endMinutes),
          reason: 'blocks must be emitted in forward, non-overlapping order',
        );
      }
      // Concretely: 08:00–09:30 clamps to the window start, 10:00–13:00 carves
      // the middle, the 11:00–12:00 overlap is already consumed, and the
      // 19:00–20:00 break is out of range → [09:30–10:00, 13:00–18:00].
      expect(summariseIntervals(intervals), '09:30–10:00  ·  13:00–18:00');
    });
  });

  // ── REGRESSION — validateDayHours rejects zero-working-time break sets ──────
  //
  // The gate that makes `toIntervals`'s "at least one block survives" premise
  // safe. It is a COVERAGE WALK over the whole break set, not a single-break
  // special case: any union that leaves no gap inside the window is rejected.
  group('validateDayHours — breakCoversWholeWindow', () {
    test('a single break spanning the entire window → breakCoversWholeWindow '
        'ringing that break row', () {
      final day = DayHours(
        window: _wi(9, 0, 18, 0),
        breaks: <BreakRange>[_br(9, 0, 18, 0)],
      );

      final err = validateDayHours(day);

      expect(err, isNotNull);
      expect(err!.kind, DayHoursErrorKind.breakCoversWholeWindow);
      expect(err.message, 'Перерва не може займати весь робочий день');
      expect(err.breakIndex, 0, reason: 'the offending break row must ring');
      expect(err.windowInvalid, isFalse);
      expect(dayHoursValid(day), isFalse);
    });

    test('TWO contiguous breaks whose union covers the window (09:00–13:00 + '
        '13:00–18:00) are ALSO rejected — the walk is over the whole set, not '
        'one break', () {
      final day = DayHours(
        window: _wi(9, 0, 18, 0),
        breaks: <BreakRange>[_br(9, 0, 13, 0), _br(13, 0, 18, 0)],
      );

      final err = validateDayHours(day);

      expect(err, isNotNull);
      expect(err!.kind, DayHoursErrorKind.breakCoversWholeWindow);
      expect(
        err.breakIndex,
        1,
        reason:
            'the LAST break in start order is the one that closes the window '
            '— that row is the one the editor rings',
      );
      // And the day it would have produced carries zero bookable time, which
      // is why the gate exists.
      expect(day.toIntervals(), isEmpty);
    });

    test('THREE contiguous breaks covering the window are rejected too (the '
        'walk does not stop after two)', () {
      final day = DayHours(
        window: _wi(9, 0, 18, 0),
        breaks: <BreakRange>[
          _br(9, 0, 12, 0),
          _br(12, 0, 15, 0),
          _br(15, 0, 18, 0),
        ],
      );

      expect(
        validateDayHours(day)!.kind,
        DayHoursErrorKind.breakCoversWholeWindow,
      );
    });

    test(
      'the same breaks with ANY gap left validate CLEAN — the gate is scoped '
      'to zero-working-time, not to edge-flush breaks in general',
      () {
        // Identical shape to the rejected pair above, except the second break
        // starts 15 minutes later, leaving a 13:00–13:15 working sliver.
        final day = DayHours(
          window: _wi(9, 0, 18, 0),
          breaks: <BreakRange>[_br(9, 0, 13, 0), _br(13, 15, 18, 0)],
        );

        expect(
          validateDayHours(day),
          isNull,
          reason: 'a surviving working sliver must keep the day saveable',
        );
        final intervals = day.toIntervals();
        expect(intervals, hasLength(1));
        _expectInterval(intervals.single, 13, 0, 13, 15);
      },
    );

    test('both edge-flush breaks with a working middle validate CLEAN', () {
      // The reported bug's shape (a 09:00–10:00 flush break) must remain a
      // perfectly legal day — the new gate must not over-reject it.
      final day = DayHours(
        window: _wi(9, 0, 18, 0),
        breaks: <BreakRange>[_br(9, 0, 10, 0), _br(17, 0, 18, 0)],
      );

      expect(validateDayHours(day), isNull);
      expect(dayHoursValid(day), isTrue);
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

  // ═══════════════════════════════════════════════════════════════════════════
  // 2026-07-27 — STORED WORKING WINDOW (`windowStart`/`windowEnd`).
  //
  // THE USER-REPORTED BUG. A master with hours 09:00–18:00 adds a «Перерва»
  // 09:00–10:00 (flush against the window START). Only working INTERVALS were
  // persisted and breaks were reconstructed from the GAPS BETWEEN them, so an
  // edge-flush break left no gap to see: `[10:00–18:00]` read back as "window
  // 10:00–18:00, no breaks". The break was not lost from AVAILABILITY (an
  // earlier fix on this branch already stopped it being discarded — that was
  // the overbooking exposure), but it VANISHED FROM THE SCREEN: the master
  // reopened the editor and their break was gone, silently normalised into a
  // shortened working day.
  //
  // The backend now stores the outer window alongside the intervals, so
  // `DayHours.fromIntervals` gets a second regime:
  //
  //     window present  →  breaks = window MINUS intervals   (lossless)
  //     window absent   →  legacy gap reconstruction         (unchanged)
  //
  // EVERY pre-existing test in this file exercises the LEGACY regime (none of
  // them pass a window), so the window-present regime had ZERO coverage before
  // this group. The `window == null` rows below are therefore not decoration:
  // they are what protects every already-shipped legacy template row from being
  // re-interpreted by the new code path.
  // ═══════════════════════════════════════════════════════════════════════════

  /// Asserts [got] matches [want] break-for-break, in order.
  void expectBreaks(List<BreakRange> got, List<BreakRange> want) {
    expect(
      got,
      hasLength(want.length),
      reason:
          'expected ${want.length} break(s), got '
          '${got.map((b) => '${formatTime(b.start)}–${formatTime(b.end)}').join(', ')}',
    );
    for (int i = 0; i < want.length; i++) {
      expect(
        got[i].start,
        want[i].start,
        reason: 'break $i start (${formatTime(want[i].start)} expected)',
      );
      expect(
        got[i].end,
        want[i].end,
        reason: 'break $i end (${formatTime(want[i].end)} expected)',
      );
    }
  }

  group('DayHours.fromIntervals — WINDOW PRESENT (breaks = window MINUS '
      'intervals)', () {
    // Every row shares the SAME stored window 09:00–18:00; only the saved
    // interval list varies. `wantWithWindow` is what the master must SEE on
    // reload; `wantLegacy` is what the SAME intervals produce with no stored
    // window — the byte-identical pre-window behaviour, pinned side by side so
    // the two regimes can never silently converge.
    final List<
      ({
        String name,
        List<WorkInterval> intervals,
        List<BreakRange> wantWithWindow,
        WorkInterval legacyWindow,
        List<BreakRange> wantLegacy,
      })
    >
    cases =
        <
          ({
            String name,
            List<WorkInterval> intervals,
            List<BreakRange> wantWithWindow,
            WorkInterval legacyWindow,
            List<BreakRange> wantLegacy,
          })
        >[
          (
            // ── THE USER'S EXACT BUG ────────────────────────────────────────
            name:
                'start-flush: [10:00–18:00] + window 09:00–18:00 → break '
                '09:00–10:00',
            intervals: <WorkInterval>[_wi(10, 0, 18, 0)],
            wantWithWindow: <BreakRange>[_br(9, 0, 10, 0)],
            legacyWindow: _wi(10, 0, 18, 0),
            wantLegacy: <BreakRange>[],
          ),
          (
            name:
                'end-flush: [09:00–17:00] + window 09:00–18:00 → break '
                '17:00–18:00',
            intervals: <WorkInterval>[_wi(9, 0, 17, 0)],
            wantWithWindow: <BreakRange>[_br(17, 0, 18, 0)],
            legacyWindow: _wi(9, 0, 17, 0),
            wantLegacy: <BreakRange>[],
          ),
          (
            name:
                'both edges flush: [10:00–17:00] + window 09:00–18:00 → breaks '
                '09:00–10:00 + 17:00–18:00',
            intervals: <WorkInterval>[_wi(10, 0, 17, 0)],
            wantWithWindow: <BreakRange>[_br(9, 0, 10, 0), _br(17, 0, 18, 0)],
            legacyWindow: _wi(10, 0, 17, 0),
            wantLegacy: <BreakRange>[],
          ),
          (
            name:
                'both edges flush + an interior break: '
                '[10:00–13:00, 14:00–17:00] + window 09:00–18:00 → three breaks',
            intervals: <WorkInterval>[_wi(10, 0, 13, 0), _wi(14, 0, 17, 0)],
            wantWithWindow: <BreakRange>[
              _br(9, 0, 10, 0),
              _br(13, 0, 14, 0),
              _br(17, 0, 18, 0),
            ],
            legacyWindow: _wi(10, 0, 17, 0),
            // Legacy sees only the ONE gap between the two intervals.
            wantLegacy: <BreakRange>[_br(13, 0, 14, 0)],
          ),
          (
            // CONTROL — the interior-only case never regressed. Both regimes
            // must agree here, which is precisely why the bug went unnoticed.
            name:
                'interior only (control): [09:00–13:00, 14:00–18:00] + window '
                '09:00–18:00 → break 13:00–14:00, identical to legacy',
            intervals: <WorkInterval>[_wi(9, 0, 13, 0), _wi(14, 0, 18, 0)],
            wantWithWindow: <BreakRange>[_br(13, 0, 14, 0)],
            legacyWindow: _wi(9, 0, 18, 0),
            wantLegacy: <BreakRange>[_br(13, 0, 14, 0)],
          ),
        ];

    for (final c in cases) {
      test('WINDOW PRESENT — ${c.name}', () {
        final DayHours day = DayHours.fromIntervals(
          c.intervals,
          window: _wi(9, 0, 18, 0),
        );

        // The stored window is honoured verbatim — never re-derived from the
        // intervals.
        _expectInterval(day.window, 9, 0, 18, 0);
        expectBreaks(day.breaks, c.wantWithWindow);

        // Property: the reconstructed view must collapse back to EXACTLY the
        // intervals it came from. This is the whole point of the feature — the
        // display gains a break without the availability changing by a minute.
        expect(
          summariseIntervals(day.toIntervals()),
          summariseIntervals(c.intervals),
          reason:
              'window+breaks must collapse back to the saved intervals — a '
              'difference here is an availability change smuggled in by a '
              'display-only field',
        );
      });

      test('WINDOW NULL (legacy, byte-identical) — ${c.name}', () {
        // The SAME intervals with no stored window must behave exactly as they
        // did before this change: window = [firstStart, lastEnd], breaks = the
        // gaps between consecutive intervals, edge-flush breaks unrecoverable.
        final DayHours legacy = DayHours.fromIntervals(c.intervals);

        _expectInterval(
          legacy.window,
          c.legacyWindow.start.hour,
          c.legacyWindow.start.minute,
          c.legacyWindow.end.hour,
          c.legacyWindow.end.minute,
        );
        expectBreaks(legacy.breaks, c.wantLegacy);

        // And an explicit `window: null` is the same call as omitting it — the
        // named parameter must not change the default path.
        final DayHours explicitNull = DayHours.fromIntervals(
          c.intervals,
          window: null,
        );
        expect(explicitNull.window.startMinutes, legacy.window.startMinutes);
        expect(explicitNull.window.endMinutes, legacy.window.endMinutes);
        expectBreaks(explicitNull.breaks, legacy.breaks);
      });
    }

    test('the start-flush bug: WITHOUT a window the break disappears, WITH one '
        'it survives — the two regimes differ on exactly this input', () {
      // Stated as one assertion pair so the regression is unmistakable: this
      // is the before/after of the reported defect on the reported input.
      final List<WorkInterval> saved = <WorkInterval>[_wi(10, 0, 18, 0)];

      final DayHours legacy = DayHours.fromIntervals(saved);
      expect(
        legacy.breaks,
        isEmpty,
        reason: 'legacy gap reconstruction cannot see an edge-flush break',
      );
      expect(
        formatTime(legacy.window.start),
        '10:00',
        reason: 'legacy collapses the break into a shortened working window',
      );

      final DayHours withWindow = DayHours.fromIntervals(
        saved,
        window: _wi(9, 0, 18, 0),
      );
      expect(
        formatTime(withWindow.window.start),
        '09:00',
        reason:
            'THE BUG: a 10:00 window start here means the stored window was '
            'ignored and the break was re-normalised away',
      );
      expect(withWindow.breaks, hasLength(1));
      expect(formatTime(withWindow.breaks.single.start), '09:00');
      expect(formatTime(withWindow.breaks.single.end), '10:00');
    });
  });

  // ── The property the whole feature exists to provide ────────────────────────
  group('DayHours — full round-trip fromIntervals(toIntervals(day), '
      'window: day.window)', () {
    final List<({String name, List<BreakRange> breaks})> shapes =
        <({String name, List<BreakRange> breaks})>[
          (name: 'no breaks', breaks: <BreakRange>[]),
          (name: 'start-flush break', breaks: <BreakRange>[_br(9, 0, 10, 0)]),
          (name: 'end-flush break', breaks: <BreakRange>[_br(17, 0, 18, 0)]),
          (
            name: 'both edges flush',
            breaks: <BreakRange>[_br(9, 0, 10, 0), _br(17, 0, 18, 0)],
          ),
          (name: 'interior break', breaks: <BreakRange>[_br(13, 0, 14, 0)]),
          (
            name: 'both edges + interior',
            breaks: <BreakRange>[
              _br(9, 0, 10, 0),
              _br(13, 0, 14, 0),
              _br(17, 0, 18, 0),
            ],
          ),
          (
            name: 'two interior breaks',
            breaks: <BreakRange>[_br(11, 0, 11, 30), _br(14, 0, 15, 0)],
          ),
        ];

    for (final s in shapes) {
      test('${s.name} — window + breaks survive a save→load cycle exactly', () {
        final DayHours original = DayHours(
          window: _wi(9, 0, 18, 0),
          breaks: s.breaks,
        );
        // Sanity: the shape the editor would let the master save.
        expect(
          validateDayHours(original),
          isNull,
          reason: 'fixture must be a legal day',
        );

        // SAVE — the wire carries the collapsed intervals PLUS the window.
        final List<WorkInterval> wireIntervals = original.toIntervals();
        final WorkInterval wireWindow = original.window.clone();

        // LOAD — reconstruct from exactly what the wire carried.
        final DayHours reloaded = DayHours.fromIntervals(
          wireIntervals,
          window: wireWindow,
        );

        _expectInterval(reloaded.window, 9, 0, 18, 0);
        expectBreaks(reloaded.breaks, s.breaks);

        // And a SECOND save must be a byte-identical no-op — the property the
        // weekly editor's dirty-diff depends on (an idempotent reload must
        // never look like an edit).
        expect(
          summariseIntervals(reloaded.toIntervals()),
          summariseIntervals(wireIntervals),
        );
      });
    }
  });

  group('DayHours.fromIntervals — window regime degenerate inputs', () {
    test('empty intervals → defaultDay REGARDLESS of a supplied window (never '
        'a whole-window break)', () {
      // The backend never stores a window for a day with no intervals; if one
      // ever arrived, honouring it would manufacture a 09:00–18:00 break that
      // validateDayHours immediately rejects — an unsaveable day.
      final DayHours day = DayHours.fromIntervals(
        const <WorkInterval>[],
        window: _wi(9, 0, 18, 0),
      );

      expect(day.breaks, isEmpty);
      _expectInterval(day.window, 9, 0, 18, 0); // the default day, not a break
      expect(validateDayHours(day), isNull);
    });

    test('a degenerate stored window (end <= start) falls back to the LEGACY '
        'regime rather than inverting the day', () {
      final DayHours day = DayHours.fromIntervals(<WorkInterval>[
        _wi(10, 0, 18, 0),
      ], window: _wi(18, 0, 9, 0));

      _expectInterval(
        day.window,
        10,
        0,
        18,
        0,
      ); // derived, not the bad stored pair
      expect(day.breaks, isEmpty);
    });

    test('a zero-length stored window (end == start) also falls back to '
        'LEGACY', () {
      final DayHours day = DayHours.fromIntervals(<WorkInterval>[
        _wi(10, 0, 18, 0),
      ], window: _wi(9, 0, 9, 0));

      _expectInterval(day.window, 10, 0, 18, 0);
      expect(day.breaks, isEmpty);
    });

    test('an interval poking OUTSIDE the stored window is clamped — no '
        'inverted or negative-length break is produced', () {
      // A malformed row (window narrower than its own intervals) must degrade
      // to a sane view, never to a break with end < start.
      final DayHours day = DayHours.fromIntervals(<WorkInterval>[
        _wi(8, 0, 12, 0), // starts an hour before the window
        _wi(14, 0, 19, 0), // ends an hour after the window
      ], window: _wi(9, 0, 18, 0));

      _expectInterval(day.window, 9, 0, 18, 0);
      for (final BreakRange b in day.breaks) {
        expect(
          b.endMinutes,
          greaterThan(b.startMinutes),
          reason: 'no reconstructed break may be zero-length or inverted',
        );
        expect(b.startMinutes, greaterThanOrEqualTo(day.window.startMinutes));
        expect(b.endMinutes, lessThanOrEqualTo(day.window.endMinutes));
      }
      // Concretely: 08:00–12:00 clamps to 09:00–12:00, leaving 12:00–14:00 as
      // the only in-window uncovered stretch; 14:00–19:00 clamps to the end.
      expectBreaks(day.breaks, <BreakRange>[_br(12, 0, 14, 0)]);
    });

    test('unsorted intervals are ordered before the window walk', () {
      final DayHours day = DayHours.fromIntervals(<WorkInterval>[
        _wi(14, 0, 17, 0),
        _wi(10, 0, 13, 0),
      ], window: _wi(9, 0, 18, 0));

      expectBreaks(day.breaks, <BreakRange>[
        _br(9, 0, 10, 0),
        _br(13, 0, 14, 0),
        _br(17, 0, 18, 0),
      ]);
    });

    test('intervals exactly filling the window → no breaks at all', () {
      final DayHours day = DayHours.fromIntervals(<WorkInterval>[
        _wi(9, 0, 18, 0),
      ], window: _wi(9, 0, 18, 0));

      expect(day.breaks, isEmpty);
    });
  });

  // ── The window is INTERVAL-shape metadata only ──────────────────────────────
  group('TemplateDay.window — cleared on the flip to EXPLICIT_TIMES', () {
    TemplateDay intervalDay() => TemplateDay(
      dayOfWeek: 1,
      label: 'Понеділок',
      intervals: <WorkInterval>[_wi(10, 0, 18, 0)],
      window: _wi(9, 0, 18, 0),
    );

    test('setMode(explicitTimes) drops the window along with the intervals', () {
      final TemplateDay day = intervalDay();
      expect(day.window, isNotNull, reason: 'precondition');

      day.setMode(WeekdayMode.explicitTimes);

      expect(day.intervals, isEmpty);
      expect(
        day.window,
        isNull,
        reason:
            'a window describes an INTERVAL day\'s від–до; the backend rejects '
            'it on an EXPLICIT_TIMES day, so the flip must clear it',
      );
    });

    test('flipping BACK to interval does not resurrect the dropped window', () {
      final TemplateDay day = intervalDay();

      day.setMode(WeekdayMode.explicitTimes);
      day.setMode(WeekdayMode.interval);

      expect(
        day.window,
        isNull,
        reason:
            'the window is gone for good once cleared — the editor re-seeds it '
            'from the redrawn intervals, never from stale state',
      );
    });

    test('a no-op setMode (already in that mode) leaves the window intact', () {
      final TemplateDay day = intervalDay();

      day.setMode(WeekdayMode.interval);

      expect(day.window, isNotNull);
      expect(day.window!.startMinutes, 9 * 60);
    });

    test('TemplateDay defaults window to null (a legacy / unset row)', () {
      final TemplateDay day = TemplateDay(
        dayOfWeek: 1,
        label: 'Понеділок',
        intervals: <WorkInterval>[_wi(9, 0, 18, 0)],
      );
      expect(day.window, isNull);
    });
  });

  group('ScheduleOverride.window — only the CUSTOM_HOURS INTERVAL shape has '
      'one', () {
    test('custom INTERVAL override carries the given window', () {
      final ScheduleOverride o = ScheduleOverride.custom(
        start: DateTime(2026, 7, 27),
        end: DateTime(2026, 7, 27),
        intervals: <WorkInterval>[_wi(10, 0, 18, 0)],
        window: _wi(9, 0, 18, 0),
      );

      expect(o.window, isNotNull);
      expect(o.window!.startMinutes, 9 * 60);
      expect(o.window!.endMinutes, 18 * 60);
    });

    test('custom INTERVAL override without a window is null (legacy row)', () {
      final ScheduleOverride o = ScheduleOverride.custom(
        start: DateTime(2026, 7, 27),
        end: DateTime(2026, 7, 27),
        intervals: <WorkInterval>[_wi(10, 0, 18, 0)],
      );
      expect(o.window, isNull);
    });

    test('a day-off override has no window', () {
      final ScheduleOverride o = ScheduleOverride.dayOff(
        start: DateTime(2026, 7, 27),
        end: DateTime(2026, 7, 27),
      );
      expect(o.window, isNull);
    });

    test('an EXPLICIT_TIMES override has no window', () {
      final ScheduleOverride o = ScheduleOverride.explicitTimes(
        start: DateTime(2026, 7, 27),
        end: DateTime(2026, 7, 27),
        times: <TimeOfDay>[_t(9, 0), _t(11, 0)],
      );
      expect(o.window, isNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // mobile-qa (2026-07-29) — Phase 23.2 audit regression: `formatDay` had ZERO
  // test coverage anywhere in the suite (not here, not in any widget/golden
  // test — the screens that call it locate elements by `Key`, never by the
  // rendered date string), despite being an actively-used public function
  // (`master_schedule_screen.dart`, `apply_schedule_sheet.dart` — 3 call
  // sites) whose implementation this phase rewired from a local
  // `_monthsGenitive[d.month - 1]` table lookup onto
  // `monthGenitive(d.month)` in the canonical `shared/formatters/
  // uk_calendar.dart` module. The phase doc's Step 5 claimed this file
  // "Pins `monthShort` and `formatDay`" and must stay green unchanged — that
  // claim was false (grep confirms neither was ever referenced here before
  // this group), so a wrong-month regression in the rewiring would have
  // shipped invisibly. This group closes that gap; it is a genuine addition,
  // not the "unchanged" verification the phase doc described.
  // ───────────────────────────────────────────────────────────────────────────
  group('formatDay — long human date via the canonical uk_calendar module', () {
    test('29 травня (the phase-doc pinned example)', () {
      expect(formatDay(DateTime(2026, 5, 29)), '29 травня');
    });

    test('January 1 — lower month boundary, single-digit day, no zero-pad', () {
      expect(formatDay(DateTime(2026, 1, 1)), '1 січня');
    });

    test('December 31 — upper month boundary', () {
      expect(formatDay(DateTime(2026, 12, 31)), '31 грудня');
    });

    test('every month resolves its own distinct genitive name, in order', () {
      final List<String> resolved = List<String>.generate(
        12,
        (int i) => formatDay(DateTime(2026, i + 1, 15)),
      );
      expect(resolved, <String>[
        '15 січня',
        '15 лютого',
        '15 березня',
        '15 квітня',
        '15 травня',
        '15 червня',
        '15 липня',
        '15 серпня',
        '15 вересня',
        '15 жовтня',
        '15 листопада',
        '15 грудня',
      ]);
    });
  });
}
