// mobile-qa gap-closure (feat/salon-master-schedule-read-only) — unit tests
// for `weeklyScheduleSummary` (lib/shared/formatters/weekly_schedule_summary
// .dart), new on this branch (~102 lines). Before this file, the only
// coverage was INDIRECT, through `salon_staff_profile_screen_test.dart`'s
// D3 «Графік роботи» row — and only for the contiguous-weekday + INTERVAL
// path (that file self-documents the deferral three times). Untested until
// now:
//   - a non-contiguous weekday pattern (comma-join, not a dash range)
//   - `_activeTemplate`'s multi-window selection AND its no-match fallback
//     (`schedules.first`)
//   - the EXPLICIT_TIMES hours branch (`_hoursLabel`'s fallback path, when
//     every working day carries discrete `times` and no `intervals` at all)
//
// Pure Dart formatter — no widget pump needed.

import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/shared/formatters/weekly_schedule_summary.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';

const String _notSet = 'Графік не вказано';

/// An INTERVAL working day — `mode` defaults to [WeekdayMode.interval], so a
/// non-empty [intervals] list is what makes [TemplateDay.isDayOff] `false`.
TemplateDay _intervalDay(
  int dayOfWeek, {
  required int startH,
  required int startM,
  required int endH,
  required int endM,
}) => TemplateDay(
  dayOfWeek: dayOfWeek,
  label: 'day-$dayOfWeek',
  intervals: <WorkInterval>[
    WorkInterval(
      start: TimeOfDay(hour: startH, minute: startM),
      end: TimeOfDay(hour: endH, minute: endM),
    ),
  ],
);

/// A day off — empty intervals, default INTERVAL mode.
TemplateDay _dayOff(int dayOfWeek) =>
    TemplateDay(dayOfWeek: dayOfWeek, label: 'day-$dayOfWeek', intervals: []);

/// An EXPLICIT_TIMES working day — empty `intervals` (authoritative for
/// [WeekdayMode.explicitTimes] is [TemplateDay.times]), so [TemplateDay
/// .isDayOff] reads `times.isEmpty` instead.
TemplateDay _explicitTimesDay(int dayOfWeek, List<TimeOfDay> times) =>
    TemplateDay(
      dayOfWeek: dayOfWeek,
      label: 'day-$dayOfWeek',
      intervals: const <WorkInterval>[],
      mode: WeekdayMode.explicitTimes,
      times: times,
    );

/// A dense 7-day week (`weeklyScheduleSummary` assumes [WeeklySchedule.days]
/// is always the gap-filled full ISO week, per that class's own doc
/// comment), with [working] entries overlaid at their `dayOfWeek` and every
/// other day defaulted to off.
List<TemplateDay> _week(List<TemplateDay> working) {
  final Map<int, TemplateDay> byDay = <int, TemplateDay>{
    for (final TemplateDay d in working) d.dayOfWeek: d,
  };
  return <TemplateDay>[for (int d = 1; d <= 7; d++) byDay[d] ?? _dayOff(d)];
}

void main() {
  group('non-contiguous weekday comma-join', () {
    test('Mon + Wed + Fri working, Tue/Thu/Sat/Sun off → comma-joined label, '
        'not a dash range', () {
      final WeeklySchedule schedule = WeeklySchedule(
        validFrom: DateTime(2026, 1, 1),
        validTo: null,
        days: _week(<TemplateDay>[
          _intervalDay(1, startH: 9, startM: 0, endH: 18, endM: 0),
          _intervalDay(3, startH: 9, startM: 0, endH: 18, endM: 0),
          _intervalDay(5, startH: 9, startM: 0, endH: 18, endM: 0),
        ]),
      );

      final String result = weeklyScheduleSummary(
        <WeeklySchedule>[schedule],
        DateTime(2026, 3, 10),
        _notSet,
      );

      expect(
        result,
        'Пн, Ср, Пт · 09:00–18:00',
        reason:
            'a contiguous-range formatter (Пн–Пт) would silently pass a '
            'pattern with gaps as if it had none',
      );
    });

    test('two separated pairs (Mon+Tue, Thu+Fri) still comma-join every '
        'weekday individually, not "Пн–Вт, Чт–Пт"', () {
      final WeeklySchedule schedule = WeeklySchedule(
        validFrom: DateTime(2026, 1, 1),
        validTo: null,
        days: _week(<TemplateDay>[
          _intervalDay(1, startH: 10, startM: 0, endH: 16, endM: 0),
          _intervalDay(2, startH: 10, startM: 0, endH: 16, endM: 0),
          _intervalDay(4, startH: 10, startM: 0, endH: 16, endM: 0),
          _intervalDay(5, startH: 10, startM: 0, endH: 16, endM: 0),
        ]),
      );

      final String result = weeklyScheduleSummary(
        <WeeklySchedule>[schedule],
        DateTime(2026, 3, 10),
        _notSet,
      );

      expect(result, 'Пн, Вт, Чт, Пт · 10:00–16:00');
    });
  });

  group('_activeTemplate — multi-window selection', () {
    test('today falls inside the SECOND of two windows → that window\'s hours '
        'are used, not the first\'s', () {
      final WeeklySchedule windowA = WeeklySchedule(
        validFrom: DateTime(2026, 1, 1),
        validTo: DateTime(2026, 1, 31),
        days: _week(<TemplateDay>[
          _intervalDay(1, startH: 8, startM: 0, endH: 12, endM: 0),
        ]),
      );
      final WeeklySchedule windowB = WeeklySchedule(
        validFrom: DateTime(2026, 2, 1),
        validTo: null,
        days: _week(<TemplateDay>[
          _intervalDay(1, startH: 10, startM: 0, endH: 19, endM: 0),
        ]),
      );

      final String result = weeklyScheduleSummary(
        <WeeklySchedule>[windowA, windowB],
        DateTime(2026, 2, 15),
        _notSet,
      );

      expect(
        result,
        'Пн · 10:00–19:00',
        reason:
            'must resolve windowB (covers 2026-02-15), never windowA '
            '(closed 2026-01-31) or a naive "first in list" pick',
      );
    });

    test('today falls in the GAP between two windows → falls back to '
        'schedules.first, not notSetLabel', () {
      final WeeklySchedule windowA = WeeklySchedule(
        validFrom: DateTime(2026, 3, 1),
        validTo: DateTime(2026, 3, 31),
        days: _week(<TemplateDay>[
          _intervalDay(2, startH: 9, startM: 0, endH: 13, endM: 0),
        ]),
      );
      final WeeklySchedule windowB = WeeklySchedule(
        validFrom: DateTime(2026, 5, 1),
        validTo: DateTime(2026, 5, 31),
        days: _week(<TemplateDay>[
          _intervalDay(4, startH: 14, startM: 0, endH: 20, endM: 0),
        ]),
      );

      // 2026-04-15 is covered by NEITHER window — the gap month.
      final String result = weeklyScheduleSummary(
        <WeeklySchedule>[windowA, windowB],
        DateTime(2026, 4, 15),
        _notSet,
      );

      expect(
        result,
        'Вт · 09:00–13:00',
        reason:
            'the documented defensive fallback is schedules.first '
            '(windowA here), never notSetLabel and never windowB',
      );
    });

    test('the same gap, with the window LIST ORDER reversed, falls back to '
        'the NEW schedules.first — proving the fallback reads list order, '
        'not date proximity', () {
      final WeeklySchedule windowA = WeeklySchedule(
        validFrom: DateTime(2026, 3, 1),
        validTo: DateTime(2026, 3, 31),
        days: _week(<TemplateDay>[
          _intervalDay(2, startH: 9, startM: 0, endH: 13, endM: 0),
        ]),
      );
      final WeeklySchedule windowB = WeeklySchedule(
        validFrom: DateTime(2026, 5, 1),
        validTo: DateTime(2026, 5, 31),
        days: _week(<TemplateDay>[
          _intervalDay(4, startH: 14, startM: 0, endH: 20, endM: 0),
        ]),
      );

      final String result = weeklyScheduleSummary(
        <WeeklySchedule>[windowB, windowA],
        DateTime(2026, 4, 15),
        _notSet,
      );

      expect(result, 'Чт · 14:00–20:00');
    });
  });

  group('_hoursLabel — EXPLICIT_TIMES branch', () {
    test('a pure EXPLICIT_TIMES template (no intervals anywhere) summarises '
        'hours from the min/max discrete start time, not intervals text', () {
      final WeeklySchedule schedule = WeeklySchedule(
        validFrom: DateTime(2026, 1, 1),
        validTo: null,
        days: _week(<TemplateDay>[
          _explicitTimesDay(1, <TimeOfDay>[
            const TimeOfDay(hour: 9, minute: 0),
            const TimeOfDay(hour: 11, minute: 30),
            const TimeOfDay(hour: 14, minute: 0),
          ]),
        ]),
      );

      final String result = weeklyScheduleSummary(
        <WeeklySchedule>[schedule],
        DateTime(2026, 3, 10),
        _notSet,
      );

      expect(result, 'Пн · 09:00–14:00');
    });

    test('EXPLICIT_TIMES span aggregates across MULTIPLE working days — the '
        'earliest start and latest start across the whole week, not just '
        'one day\'s', () {
      final WeeklySchedule schedule = WeeklySchedule(
        validFrom: DateTime(2026, 1, 1),
        validTo: null,
        days: _week(<TemplateDay>[
          _explicitTimesDay(1, <TimeOfDay>[
            const TimeOfDay(hour: 10, minute: 0),
          ]),
          _explicitTimesDay(3, <TimeOfDay>[
            const TimeOfDay(hour: 8, minute: 15),
            const TimeOfDay(hour: 20, minute: 45),
          ]),
        ]),
      );

      final String result = weeklyScheduleSummary(
        <WeeklySchedule>[schedule],
        DateTime(2026, 3, 10),
        _notSet,
      );

      expect(
        result,
        'Пн, Ср · 08:15–20:45',
        reason:
            'the 08:15 and 20:45 extremes both come from Wednesday; '
            'Monday\'s single 10:00 must not narrow the span',
      );
    });

    test('a working day carrying at least one INTERVAL takes priority over '
        'EXPLICIT_TIMES days present elsewhere in the SAME template — the '
        'times-only fallback never fires while any interval exists', () {
      final WeeklySchedule schedule = WeeklySchedule(
        validFrom: DateTime(2026, 1, 1),
        validTo: null,
        days: _week(<TemplateDay>[
          _intervalDay(1, startH: 9, startM: 0, endH: 18, endM: 0),
          _explicitTimesDay(3, <TimeOfDay>[
            const TimeOfDay(hour: 22, minute: 0),
          ]),
        ]),
      );

      final String result = weeklyScheduleSummary(
        <WeeklySchedule>[schedule],
        DateTime(2026, 3, 10),
        _notSet,
      );

      expect(
        result,
        'Пн, Ср · 09:00–18:00',
        reason:
            '_hoursLabel collects intervals across every working day '
            'first and only falls back to times when that combined list '
            'is empty; Wednesday\'s 22:00 explicit time must not leak in',
      );
    });
  });
}
