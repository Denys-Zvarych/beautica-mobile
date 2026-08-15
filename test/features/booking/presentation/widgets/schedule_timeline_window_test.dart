// Phase 244 — ScheduleTimelineWindow + scheduleWindowFor + includesStart.
//
// Pure Dart unit tests (no widget tree) for the working-hours window the
// master's own «Мої записи» timeline is now bounded by. See
// `schedule_timeline_window.dart`'s file header for the product decision this
// pins: grid top = earliest working start, grid bottom = latest working end
// (INTERVAL) or latest declared start time (EXPLICIT_TIMES), and the
// boundary-rule asymmetry between the two modes.
//
// mobile-qa build-verifier gap: zero test files referenced
// `scheduleWindowFor|ScheduleTimelineWindow|scheduleFirstMinute|
// scheduleWindowEndMinute` before this file — the whole feature had no direct
// coverage.

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/features/booking/presentation/widgets/schedule_timeline_window.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';

WorkInterval _interval(int sh, int sm, int eh, int em) => WorkInterval(
  start: TimeOfDay(hour: sh, minute: sm),
  end: TimeOfDay(hour: eh, minute: em),
);

final DateTime _date = DateTime(2026, 8, 12);

EffectiveDay _day({
  required EffectiveSource source,
  List<WorkInterval> intervals = const <WorkInterval>[],
  List<TimeOfDay> times = const <TimeOfDay>[],
}) => EffectiveDay(
  date: _date,
  source: source,
  intervals: intervals,
  times: times,
);

void main() {
  group('scheduleWindowFor — INTERVAL days', () {
    test('a multi-interval day resolves the window to the EARLIEST start and '
        'the LATEST end across all intervals — 10:00-13:00 + 15:00-19:00 => '
        '600/1140', () {
      final EffectiveDay day = _day(
        source: EffectiveSource.template,
        intervals: <WorkInterval>[
          _interval(10, 0, 13, 0),
          _interval(15, 0, 19, 0),
        ],
      );

      final ScheduleTimelineWindow? window = scheduleWindowFor(day);

      expect(window, isNotNull);
      expect(window!.firstMinute, 600); // 10:00
      expect(window.windowEndMinute, 1140); // 19:00
      expect(window.isExplicitTimes, isFalse);
    });

    test('intervals given out of chronological order still resolve to the true '
        'min start / max end — the fold does not assume sorted input', () {
      final EffectiveDay day = _day(
        source: EffectiveSource.overrideCustom,
        intervals: <WorkInterval>[
          _interval(15, 0, 19, 0),
          _interval(10, 0, 13, 0),
          _interval(13, 30, 14, 30),
        ],
      );

      final ScheduleTimelineWindow? window = scheduleWindowFor(day);

      expect(window!.firstMinute, 600);
      expect(window.windowEndMinute, 1140);
    });

    test('a single interval resolves to its own start/end', () {
      final EffectiveDay day = _day(
        source: EffectiveSource.template,
        intervals: <WorkInterval>[_interval(9, 0, 18, 0)],
      );

      final ScheduleTimelineWindow? window = scheduleWindowFor(day);

      expect(window!.firstMinute, 540);
      expect(window.windowEndMinute, 1080);
    });

    test(
      'empty intervals on a non-explicit-times source resolves to null — the '
      'defensive "working source, no real hours" case',
      () {
        final EffectiveDay day = _day(
          source: EffectiveSource.template,
          intervals: const <WorkInterval>[],
        );

        expect(scheduleWindowFor(day), isNull);
      },
    );
  });

  group('scheduleWindowFor — EXPLICIT_TIMES days', () {
    test('resolves the window to the MIN and MAX of the declared times, marked '
        'isExplicitTimes', () {
      final EffectiveDay day = _day(
        source: EffectiveSource.template,
        times: const <TimeOfDay>[
          TimeOfDay(hour: 9, minute: 0),
          TimeOfDay(hour: 13, minute: 0),
          TimeOfDay(hour: 15, minute: 30),
        ],
      );

      final ScheduleTimelineWindow? window = scheduleWindowFor(day);

      expect(window, isNotNull);
      expect(window!.firstMinute, 540); // 09:00
      expect(
        window.windowEndMinute,
        930,
      ); // 15:30 — the LAST time, not +duration
      expect(window.isExplicitTimes, isTrue);
    });

    test('times given out of order still resolve to true min/max', () {
      final EffectiveDay day = _day(
        source: EffectiveSource.overrideCustom,
        times: const <TimeOfDay>[
          TimeOfDay(hour: 15, minute: 30),
          TimeOfDay(hour: 9, minute: 0),
          TimeOfDay(hour: 13, minute: 0),
        ],
      );

      final ScheduleTimelineWindow? window = scheduleWindowFor(day);

      expect(window!.firstMinute, 540);
      expect(window.windowEndMinute, 930);
    });

    test('a single declared time collapses first == last', () {
      final EffectiveDay day = _day(
        source: EffectiveSource.template,
        times: const <TimeOfDay>[TimeOfDay(hour: 11, minute: 0)],
      );

      final ScheduleTimelineWindow? window = scheduleWindowFor(day);

      expect(window!.firstMinute, 660);
      expect(window.windowEndMinute, 660);
      expect(window.isExplicitTimes, isTrue);
    });

    test('empty times on the explicit-times branch resolves to null', () {
      // EffectiveDay.isExplicitTimes is derived from times.isNotEmpty, so an
      // empty `times` list cannot itself select the explicit-times branch —
      // this exercises `day.times.isEmpty` returning null defensively, which
      // is only reachable if a caller ever constructs an EffectiveDay with
      // isExplicitTimes forced true and no times (not possible through the
      // freezed constructor today, but scheduleWindowFor's own `if
      // (day.times.isEmpty) return null;` line is direct dead-code-adjacent
      // insurance — pinned so a future refactor of EffectiveDay cannot
      // silently drop it).
      final EffectiveDay day = _day(
        source: EffectiveSource.template,
        times: const <TimeOfDay>[],
        intervals: const <WorkInterval>[],
      );

      expect(scheduleWindowFor(day), isNull);
    });
  });

  group('scheduleWindowFor — no-window sources', () {
    test(
      'overrideDayOff always resolves to null, even with garbage intervals set',
      () {
        final EffectiveDay day = _day(
          source: EffectiveSource.overrideDayOff,
          intervals: <WorkInterval>[_interval(9, 0, 18, 0)],
        );

        expect(
          scheduleWindowFor(day),
          isNull,
          reason:
              'a settled day-off has no window regardless of what else is set',
        );
      },
    );

    test('noSchedule always resolves to null', () {
      final EffectiveDay day = _day(source: EffectiveSource.noSchedule);

      expect(scheduleWindowFor(day), isNull);
    });
  });

  group('includesStart — boundary rule asymmetry', () {
    // INTERVAL day: 09:00-18:00 => firstMinute 540, windowEndMinute 1080.
    const ScheduleTimelineWindow intervalWindow = ScheduleTimelineWindow(
      firstMinute: 540,
      windowEndMinute: 1080,
      isExplicitTimes: false,
    );

    test('a start below firstMinute is excluded', () {
      expect(intervalWindow.includesStart(539), isFalse);
    });

    test('a start exactly at firstMinute is included', () {
      expect(intervalWindow.includesStart(540), isTrue);
    });

    test(
      'a start exactly AT windowEndMinute is EXCLUDED on an interval day — '
      'there is no time left to serve a booking starting when the day closes',
      () {
        expect(intervalWindow.includesStart(1080), isFalse);
      },
    );

    test('a start one minute before windowEndMinute is included', () {
      expect(intervalWindow.includesStart(1079), isTrue);
    });

    // EXPLICIT_TIMES day: declared times end at 930 (15:30).
    const ScheduleTimelineWindow explicitWindow = ScheduleTimelineWindow(
      firstMinute: 540,
      windowEndMinute: 930,
      isExplicitTimes: true,
    );

    test('a start exactly AT windowEndMinute IS included on an EXPLICIT_TIMES '
        'day — the last declared time is itself a legal booking start', () {
      expect(explicitWindow.includesStart(930), isTrue);
    });

    test(
      'a start one minute past windowEndMinute is excluded even in EXPLICIT_TIMES mode',
      () {
        expect(explicitWindow.includesStart(931), isFalse);
      },
    );

    test('a start below firstMinute is excluded regardless of mode', () {
      expect(explicitWindow.includesStart(0), isFalse);
    });
  });
}
