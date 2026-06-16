// Phase 6.2 — Unit tests for [WorkingHoursMapper].
//
// The mapper is the single translation boundary between the generated
// weekly-schedule DTOs (`WeeklyScheduleResponse` / `WeeklyScheduleRequest`) and
// the single-window domain [WorkingHours] model. Two behaviours carry real risk
// and are pinned directly here so a regression surfaces at the translation
// boundary, not three layers up:
//
//   weeklyScheduleToDomainWeek (READ — multi-interval week → dense single-window)
//     - null schedule         → 7 inactive default windows, ordered Mon..Sun.
//     - sparse schedule       → present days carried, omitted days gap-filled.
//     - multi-interval day    → FIRST interval wins (single-window editor).
//     - empty-intervals day   → treated as "off" (inactive default).
//     - out-of-range / null dayOfWeek row → dropped (cannot be slotted).
//     - duplicate day         → last one wins.
//     - isActive reflects whether the day carried any interval.
//     - output is always exactly 7 entries ordered 1..7.
//
//   toWeeklyScheduleRequest (WRITE — domain week → schedule body)
//     - active days → one WeeklyScheduleDayRequest with one interval each.
//     - inactive days omitted entirely.
//     - validFrom passed through verbatim (stamped as a Date).
//     - validTo left open-ended (null).
//     - endTime <= startTime throws ValidationFailure (cross-midnight forbidden).
//
// Pure Dart: generated built_value DTOs in, domain models out. No network.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/calendar/data/working_hours_mapper.dart';
import 'package:beautica_mobile/features/calendar/domain/working_hours.dart';
import 'package:built_collection/built_collection.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a generated [WorkIntervalDto] for the given wire times.
WorkIntervalDto _interval(String start, String end) => WorkIntervalDto(
  (b) => b
    ..startTime = start
    ..endTime = end,
);

/// Builds a [WeeklyScheduleDayResponse] for an ISO [day].
///
/// Pass `intervals: null` for a null-intervals row, or an empty list for a
/// day-off row; otherwise the supplied intervals are carried verbatim.
WeeklyScheduleDayResponse _day(
  int? day, {
  List<WorkIntervalDto>? intervals = const [],
}) => WeeklyScheduleDayResponse((b) {
  b.dayOfWeek = day;
  if (intervals != null) {
    b.intervals = ListBuilder<WorkIntervalDto>(intervals);
  }
});

/// Builds a [WeeklyScheduleResponse] from a list of day rows.
WeeklyScheduleResponse _schedule(
  List<WeeklyScheduleDayResponse> days, {
  String id = 'sched-1',
}) => WeeklyScheduleResponse(
  (b) => b
    ..id = id
    ..validFrom = Date(2026, 1, 1)
    ..days = ListBuilder<WeeklyScheduleDayResponse>(days),
);

/// Builds a domain [WorkingHours] for the given ISO [day].
WorkingHours _wh(
  int day, {
  bool active = true,
  String start = '09:00:00',
  String end = '18:00:00',
}) => WorkingHours(
  dayOfWeek: day,
  startTime: start,
  endTime: end,
  isActive: active,
);

void main() {
  group('weeklyScheduleToDomainWeek — gap-fill', () {
    test('null schedule → 7 inactive default windows ordered Mon..Sun', () {
      final week = WorkingHoursMapper.weeklyScheduleToDomainWeek(null);

      expect(week, hasLength(7));
      expect(week.map((w) => w.dayOfWeek), [1, 2, 3, 4, 5, 6, 7]);
      expect(week.every((w) => !w.isActive), isTrue);
      expect(week.every((w) => w.startTime == '09:00:00'), isTrue);
      expect(week.every((w) => w.endTime == '18:00:00'), isTrue);
    });

    test('schedule with null days → 7 inactive default windows', () {
      final schedule = WeeklyScheduleResponse(
        (b) => b
          ..id = 'sched-1'
          ..validFrom = Date(2026, 1, 1),
      );

      final week = WorkingHoursMapper.weeklyScheduleToDomainWeek(schedule);

      expect(week, hasLength(7));
      expect(week.every((w) => !w.isActive), isTrue);
    });

    test('sparse schedule — present days carried, omitted days gap-filled', () {
      final week = WorkingHoursMapper.weeklyScheduleToDomainWeek(
        _schedule([
          _day(1, intervals: [_interval('08:00:00', '16:00:00')]),
          _day(3, intervals: [_interval('10:00:00', '19:00:00')]),
          _day(5, intervals: [_interval('09:00:00', '18:00:00')]),
        ]),
      );

      expect(week, hasLength(7));
      expect(week.map((w) => w.dayOfWeek), [1, 2, 3, 4, 5, 6, 7]);

      // Present days carry their server values and become active.
      expect(week[0].isActive, isTrue);
      expect(week[0].startTime, '08:00:00');
      expect(week[0].endTime, '16:00:00');
      expect(week[2].isActive, isTrue);
      expect(week[2].startTime, '10:00:00');
      expect(week[2].endTime, '19:00:00');
      expect(week[4].isActive, isTrue);

      // Omitted days (2, 4, 6, 7) are inactive defaults.
      expect(week[1].isActive, isFalse);
      expect(week[3].isActive, isFalse);
      expect(week[5].isActive, isFalse);
      expect(week[6].isActive, isFalse);
    });

    test('output is always exactly 7 entries ordered 1..7', () {
      final week = WorkingHoursMapper.weeklyScheduleToDomainWeek(
        _schedule([
          _day(4, intervals: [_interval('09:00:00', '18:00:00')]),
        ]),
      );

      expect(week, hasLength(7));
      expect(week.map((w) => w.dayOfWeek), [1, 2, 3, 4, 5, 6, 7]);
    });
  });

  group('weeklyScheduleToDomainWeek — first-interval-wins', () {
    test('a multi-interval (break-split) day flattens to its first interval', () {
      // A lunch break splits Monday into two intervals; the single-window editor
      // keeps only the first.
      final week = WorkingHoursMapper.weeklyScheduleToDomainWeek(
        _schedule([
          _day(
            1,
            intervals: [
              _interval('09:00:00', '13:00:00'),
              _interval('14:00:00', '18:00:00'),
            ],
          ),
        ]),
      );

      expect(week[0].isActive, isTrue);
      expect(week[0].startTime, '09:00:00');
      expect(
        week[0].endTime,
        '13:00:00',
        reason: 'first interval wins; the post-break interval is dropped',
      );
    });
  });

  group('weeklyScheduleToDomainWeek — isActive reflects intervals', () {
    test('a day with intervals is active', () {
      final week = WorkingHoursMapper.weeklyScheduleToDomainWeek(
        _schedule([
          _day(2, intervals: [_interval('11:00:00', '20:00:00')]),
        ]),
      );

      expect(week[1].isActive, isTrue);
    });

    test('a day with an empty interval list is treated as off (inactive)', () {
      final week = WorkingHoursMapper.weeklyScheduleToDomainWeek(
        _schedule([_day(2, intervals: const [])]),
      );

      expect(week[1].isActive, isFalse);
      // Falls back to the seeded default window.
      expect(week[1].startTime, '09:00:00');
      expect(week[1].endTime, '18:00:00');
    });

    test('a day with null intervals is treated as off (inactive)', () {
      final week = WorkingHoursMapper.weeklyScheduleToDomainWeek(
        _schedule([_day(2, intervals: null)]),
      );

      expect(week[1].isActive, isFalse);
    });
  });

  group('weeklyScheduleToDomainWeek — drop invalid day rows', () {
    test('dayOfWeek 0 (below ISO range) is dropped', () {
      final week = WorkingHoursMapper.weeklyScheduleToDomainWeek(
        _schedule([
          _day(0, intervals: [_interval('09:00:00', '18:00:00')]),
        ]),
      );

      // The bogus row did not displace any real day; all 7 stay inactive.
      expect(week, hasLength(7));
      expect(week.every((w) => !w.isActive), isTrue);
    });

    test('dayOfWeek 8 (above ISO range) is dropped', () {
      final week = WorkingHoursMapper.weeklyScheduleToDomainWeek(
        _schedule([
          _day(8, intervals: [_interval('09:00:00', '18:00:00')]),
        ]),
      );

      expect(week, hasLength(7));
      expect(week.every((w) => !w.isActive), isTrue);
    });

    test('negative dayOfWeek is dropped', () {
      final week = WorkingHoursMapper.weeklyScheduleToDomainWeek(
        _schedule([
          _day(-1, intervals: [_interval('09:00:00', '18:00:00')]),
        ]),
      );

      expect(week, hasLength(7));
      expect(week.every((w) => !w.isActive), isTrue);
    });

    test('null dayOfWeek is dropped (cannot be slotted into the week)', () {
      final week = WorkingHoursMapper.weeklyScheduleToDomainWeek(
        _schedule([
          _day(null, intervals: [_interval('09:00:00', '18:00:00')]),
        ]),
      );

      expect(week, hasLength(7));
      expect(week.every((w) => !w.isActive), isTrue);
    });

    test('a valid row survives alongside dropped invalid rows', () {
      final week = WorkingHoursMapper.weeklyScheduleToDomainWeek(
        _schedule([
          _day(0, intervals: [_interval('09:00:00', '18:00:00')]),
          _day(2, intervals: [_interval('11:00:00', '18:00:00')]),
          _day(99, intervals: [_interval('09:00:00', '18:00:00')]),
        ]),
      );

      expect(week, hasLength(7));
      // Only Tuesday (day 2) became active.
      expect(week.where((w) => w.isActive), hasLength(1));
      expect(week[1].dayOfWeek, 2);
      expect(week[1].startTime, '11:00:00');
    });
  });

  group('weeklyScheduleToDomainWeek — duplicate day', () {
    test('last entry wins when the backend sends a day twice', () {
      final week = WorkingHoursMapper.weeklyScheduleToDomainWeek(
        _schedule([
          _day(2, intervals: [_interval('08:00:00', '18:00:00')]),
          _day(2, intervals: [_interval('12:00:00', '18:00:00')]),
        ]),
      );

      expect(week[1].dayOfWeek, 2);
      expect(week[1].startTime, '12:00:00');
    });
  });

  group('toWeeklyScheduleRequest', () {
    test('active days → one day request with one interval each; inactive '
        'days omitted', () {
      final request = WorkingHoursMapper.toWeeklyScheduleRequest([
        _wh(1, active: true, start: '08:00:00', end: '17:00:00'),
        _wh(2, active: false),
        _wh(3, active: true, start: '10:00:00', end: '19:00:00'),
      ], validFrom: DateTime(2026, 6, 10));

      final days = request.days!;
      expect(
        days,
        hasLength(2),
        reason: 'only the two active days are emitted; the inactive day off',
      );
      expect(days.map((d) => d.dayOfWeek), [1, 3]);

      // Each active day carries exactly one interval with the domain times.
      final mon = days[0];
      expect(mon.intervals, hasLength(1));
      expect(mon.intervals!.first.startTime, '08:00:00');
      expect(mon.intervals!.first.endTime, '17:00:00');

      final wed = days[1];
      expect(wed.intervals, hasLength(1));
      expect(wed.intervals!.first.startTime, '10:00:00');
      expect(wed.intervals!.first.endTime, '19:00:00');
    });

    test('validFrom is passed through verbatim and validTo is open-ended', () {
      final request = WorkingHoursMapper.toWeeklyScheduleRequest([
        _wh(1),
      ], validFrom: DateTime(2025, 3, 14));

      expect(request.validFrom, Date(2025, 3, 14));
      expect(
        request.validTo,
        isNull,
        reason: 'the schedule is always created / updated open-ended',
      );
    });

    test(
      'an all-inactive week emits an empty days list (still a valid body)',
      () {
        final request = WorkingHoursMapper.toWeeklyScheduleRequest([
          for (var d = 1; d <= 7; d++) _wh(d, active: false),
        ], validFrom: DateTime(2026, 6, 10));

        expect(request.days, isEmpty);
        expect(request.validFrom, Date(2026, 6, 10));
      },
    );

    test('endTime == startTime throws ValidationFailure', () {
      expect(
        () => WorkingHoursMapper.toWeeklyScheduleRequest([
          _wh(1, active: true, start: '12:00:00', end: '12:00:00'),
        ], validFrom: DateTime(2026, 6, 10)),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('endTime before startTime throws ValidationFailure', () {
      expect(
        () => WorkingHoursMapper.toWeeklyScheduleRequest([
          _wh(1, active: true, start: '18:00:00', end: '09:00:00'),
        ], validFrom: DateTime(2026, 6, 10)),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('an inactive day with an invalid window does NOT throw (it is '
        'omitted before validation)', () {
      // Only active days are validated; a closed day keeps its stale window.
      final request = WorkingHoursMapper.toWeeklyScheduleRequest([
        _wh(1, active: false, start: '18:00:00', end: '09:00:00'),
      ], validFrom: DateTime(2026, 6, 10));

      expect(request.days, isEmpty);
    });
  });

  group('round-trip — write then read', () {
    test('a domain week survives request → echoed response → domain week', () {
      final original = [
        for (var day = 1; day <= 7; day++)
          _wh(day, active: day <= 5, start: '08:00:00', end: '17:00:00'),
      ];

      // Domain → request body.
      final request = WorkingHoursMapper.toWeeklyScheduleRequest(
        original,
        validFrom: DateTime(2026, 6, 10),
      );

      // Server echoes the persisted days back as a response schedule.
      final echoed = WeeklyScheduleResponse(
        (b) => b
          ..id = 'sched-1'
          ..validFrom = request.validFrom
          ..days = ListBuilder<WeeklyScheduleDayResponse>([
            for (final d in request.days!)
              WeeklyScheduleDayResponse(
                (db) => db
                  ..dayOfWeek = d.dayOfWeek
                  ..intervals = ListBuilder<WorkIntervalDto>(d.intervals!),
              ),
          ]),
      );

      // Response → domain week.
      final result = WorkingHoursMapper.weeklyScheduleToDomainWeek(echoed);

      expect(result, hasLength(7));
      expect(result.map((w) => w.dayOfWeek), [1, 2, 3, 4, 5, 6, 7]);
      // Active flags survive (Mon–Fri active, Sat/Sun off).
      expect(result.map((w) => w.isActive), [
        true,
        true,
        true,
        true,
        true,
        false,
        false,
      ]);
      // The active days keep their window.
      expect(result.first.startTime, '08:00:00');
      expect(result.first.endTime, '17:00:00');
    });
  });
}
