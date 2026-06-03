// Phase 6.1 — Unit tests for [WorkingHoursMapper].
//
// The gap-fill / drop-invalid contract is the whole reason this mapper exists,
// yet until now it was only exercised transitively (via the repository's
// replaceAll response remap and via master_repository_test). These tests pin the
// mapper directly so a regression surfaces here, at the translation boundary,
// not three layers up.
//
// Covers:
//   toDomainWeek
//     - null input            → 7 inactive default windows, ordered Mon..Sun.
//     - sparse input          → present days carried, missing days gap-filled.
//     - out-of-range dayOfWeek (0, 8, negative) → row dropped.
//     - null dayOfWeek        → row dropped.
//     - null startTime/endTime/isActive on a valid row → safe defaults applied.
//     - duplicate day         → last one wins.
//     - output is always 7 entries ordered 1..7.
//   toRequestList
//     - 1:1 field mapping, order preserved.
//     - round-trips through toDomainWeek for a full week.
//
// Pure Dart: generated built_value DTOs in, domain models out. No network.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/features/calendar/data/working_hours_mapper.dart';
import 'package:beautica_mobile/features/calendar/domain/working_hours.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a generated [WorkingHoursResponse]. Pass `null` explicitly to exercise
/// the mapper's null-field handling.
WorkingHoursResponse _resp({
  int? day,
  String? start = '09:00:00',
  String? end = '18:00:00',
  bool? active = true,
}) =>
    (WorkingHoursResponseBuilder()
          ..dayOfWeek = day
          ..startTime = start
          ..endTime = end
          ..isActive = active)
        .build();

/// Builds a domain [WorkingHours] for the round-trip test.
WorkingHours _wh(int day, {bool active = true}) => WorkingHours(
  dayOfWeek: day,
  startTime: '09:00:00',
  endTime: '18:00:00',
  isActive: active,
);

void main() {
  group('toDomainWeek — gap-fill', () {
    test('null input → 7 inactive default windows ordered Mon..Sun', () {
      final week = WorkingHoursMapper.toDomainWeek(null);

      expect(week, hasLength(7));
      expect(week.map((w) => w.dayOfWeek), [1, 2, 3, 4, 5, 6, 7]);
      expect(week.every((w) => !w.isActive), isTrue);
      expect(week.every((w) => w.startTime == '09:00:00'), isTrue);
      expect(week.every((w) => w.endTime == '18:00:00'), isTrue);
    });

    test('empty input → 7 inactive default windows', () {
      final week = WorkingHoursMapper.toDomainWeek(const []);

      expect(week, hasLength(7));
      expect(week.every((w) => !w.isActive), isTrue);
    });

    test('sparse input — present days carried, missing days gap-filled', () {
      final week = WorkingHoursMapper.toDomainWeek([
        _resp(day: 1, start: '08:00:00', end: '16:00:00'),
        _resp(day: 3, start: '10:00:00', end: '19:00:00'),
        _resp(day: 5),
      ]);

      expect(week, hasLength(7));
      expect(week.map((w) => w.dayOfWeek), [1, 2, 3, 4, 5, 6, 7]);

      // Present days carry their server values and stay active.
      expect(week[0].isActive, isTrue);
      expect(week[0].startTime, '08:00:00');
      expect(week[0].endTime, '16:00:00');
      expect(week[2].isActive, isTrue);
      expect(week[2].startTime, '10:00:00');
      expect(week[4].isActive, isTrue);

      // Missing days (2, 4, 6, 7) are inactive defaults.
      expect(week[1].isActive, isFalse);
      expect(week[3].isActive, isFalse);
      expect(week[5].isActive, isFalse);
      expect(week[6].isActive, isFalse);
    });

    test('output is always exactly 7 entries ordered 1..7', () {
      final week = WorkingHoursMapper.toDomainWeek([_resp(day: 4)]);

      expect(week, hasLength(7));
      expect(week.map((w) => w.dayOfWeek), [1, 2, 3, 4, 5, 6, 7]);
    });
  });

  group('toDomainWeek — drop invalid rows', () {
    test('dayOfWeek 0 (below ISO range) is dropped', () {
      final week = WorkingHoursMapper.toDomainWeek([
        _resp(day: 0, active: true),
      ]);

      // The bogus row did not displace any real day; all 7 stay inactive.
      expect(week, hasLength(7));
      expect(week.every((w) => !w.isActive), isTrue);
    });

    test('dayOfWeek 8 (above ISO range) is dropped', () {
      final week = WorkingHoursMapper.toDomainWeek([
        _resp(day: 8, active: true),
      ]);

      expect(week, hasLength(7));
      expect(week.every((w) => !w.isActive), isTrue);
    });

    test('negative dayOfWeek is dropped', () {
      final week = WorkingHoursMapper.toDomainWeek([
        _resp(day: -1, active: true),
      ]);

      expect(week, hasLength(7));
      expect(week.every((w) => !w.isActive), isTrue);
    });

    test('null dayOfWeek is dropped (cannot be slotted into the week)', () {
      final week = WorkingHoursMapper.toDomainWeek([
        _resp(day: null, active: true),
      ]);

      expect(week, hasLength(7));
      expect(week.every((w) => !w.isActive), isTrue);
    });

    test('a valid row survives alongside dropped invalid rows', () {
      final week = WorkingHoursMapper.toDomainWeek([
        _resp(day: 0),
        _resp(day: 2, start: '11:00:00'),
        _resp(day: 99),
      ]);

      expect(week, hasLength(7));
      // Only Tuesday (day 2) became active.
      expect(week.where((w) => w.isActive), hasLength(1));
      expect(week[1].dayOfWeek, 2);
      expect(week[1].startTime, '11:00:00');
    });
  });

  group('toDomainWeek — null fields on a valid row default safely', () {
    test('null startTime / endTime fall back to the default window', () {
      final week = WorkingHoursMapper.toDomainWeek([
        _resp(day: 1, start: null, end: null),
      ]);

      expect(week[0].startTime, '09:00:00');
      expect(week[0].endTime, '18:00:00');
    });

    test('null isActive defaults to false (closed)', () {
      final week = WorkingHoursMapper.toDomainWeek([
        _resp(day: 1, active: null),
      ]);

      expect(week[0].isActive, isFalse);
    });
  });

  group('toDomainWeek — duplicate day', () {
    test('last entry wins when the backend sends a day twice', () {
      final week = WorkingHoursMapper.toDomainWeek([
        _resp(day: 2, start: '08:00:00'),
        _resp(day: 2, start: '12:00:00'),
      ]);

      expect(week[1].dayOfWeek, 2);
      expect(week[1].startTime, '12:00:00');
    });
  });

  group('toRequestList', () {
    test('maps each domain entry 1:1, preserving order and fields', () {
      final requests = WorkingHoursMapper.toRequestList([
        _wh(1, active: true),
        _wh(2, active: false),
      ]);

      expect(requests, hasLength(2));
      expect(requests[0].dayOfWeek, 1);
      expect(requests[0].startTime, '09:00:00');
      expect(requests[0].endTime, '18:00:00');
      expect(requests[0].isActive, isTrue);
      expect(requests[1].dayOfWeek, 2);
      expect(requests[1].isActive, isFalse);
    });

    test('round-trips a full week through toDomainWeek unchanged', () {
      final original = [
        for (var day = 1; day <= 7; day++) _wh(day, active: day <= 5),
      ];

      // Domain → request DTOs → (server echoes them as responses) → domain.
      final requests = WorkingHoursMapper.toRequestList(original);
      final echoed = requests.map(
        (r) => _resp(
          day: r.dayOfWeek,
          start: r.startTime,
          end: r.endTime,
          active: r.isActive,
        ),
      );
      final result = WorkingHoursMapper.toDomainWeek(echoed);

      expect(result, hasLength(7));
      expect(result.map((w) => w.dayOfWeek), original.map((w) => w.dayOfWeek));
      expect(result.map((w) => w.isActive), original.map((w) => w.isActive));
      expect(result.map((w) => w.startTime), original.map((w) => w.startTime));
      expect(result.map((w) => w.endTime), original.map((w) => w.endTime));
    });
  });
}
