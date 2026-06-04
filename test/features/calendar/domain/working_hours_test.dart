// Phase 6.1 — Unit tests for the [WorkingHours] domain model.
//
// Covers the derived time-of-day getters and the wire round-trip the Phase 6.2
// editor depends on:
//   - start / end parse "HH:mm:ss" and "HH:mm" wire strings into [TimeOfDay],
//     dropping any seconds component.
//   - fromTimeOfDay serialises a [TimeOfDay] back into the backend "HH:mm:00"
//     contract, zero-padding hour and minute.
//   - fromTimeOfDay → start / end is a lossless round-trip at minute
//     granularity.
//   - freezed value semantics (== / copyWith) behave as expected so the editor
//     can compare and mutate windows.
//
// Pure Dart (only the material [TimeOfDay] type is touched); no widget tree.

import 'package:beautica_mobile/features/calendar/domain/working_hours.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';

WorkingHours _wh({
  int day = 1,
  String start = '09:00:00',
  String end = '18:00:00',
  bool active = true,
}) => WorkingHours(
  dayOfWeek: day,
  startTime: start,
  endTime: end,
  isActive: active,
);

void main() {
  group('WorkingHours.start / .end parsing', () {
    test('parses an "HH:mm:ss" wire string, dropping seconds', () {
      final wh = _wh(start: '08:30:00', end: '17:45:00');

      expect(wh.start, const TimeOfDay(hour: 8, minute: 30));
      expect(wh.end, const TimeOfDay(hour: 17, minute: 45));
    });

    test('parses an "HH:mm" wire string with no seconds component', () {
      final wh = _wh(start: '09:15', end: '18:05');

      expect(wh.start, const TimeOfDay(hour: 9, minute: 15));
      expect(wh.end, const TimeOfDay(hour: 18, minute: 5));
    });

    test('parses midnight and end-of-day boundary values', () {
      final wh = _wh(start: '00:00:00', end: '23:59:00');

      expect(wh.start, const TimeOfDay(hour: 0, minute: 0));
      expect(wh.end, const TimeOfDay(hour: 23, minute: 59));
    });

    test('drops a non-zero seconds component (minute granularity only)', () {
      final wh = _wh(start: '10:20:59');

      expect(wh.start, const TimeOfDay(hour: 10, minute: 20));
    });
  });

  group('WorkingHours.fromTimeOfDay', () {
    test('serialises to "HH:mm:00", zero-padding hour and minute', () {
      expect(
        WorkingHours.fromTimeOfDay(const TimeOfDay(hour: 9, minute: 5)),
        '09:05:00',
      );
    });

    test('serialises a two-digit hour and minute without extra padding', () {
      expect(
        WorkingHours.fromTimeOfDay(const TimeOfDay(hour: 18, minute: 30)),
        '18:30:00',
      );
    });

    test('serialises midnight as "00:00:00"', () {
      expect(
        WorkingHours.fromTimeOfDay(const TimeOfDay(hour: 0, minute: 0)),
        '00:00:00',
      );
    });
  });

  group('fromTimeOfDay → start / end round-trip', () {
    test('round-trips an arbitrary time losslessly at minute granularity', () {
      const picked = TimeOfDay(hour: 7, minute: 5);

      final wh = _wh(start: WorkingHours.fromTimeOfDay(picked));

      expect(wh.startTime, '07:05:00');
      expect(wh.start, picked);
    });

    test('round-trips both ends of a window the editor would build', () {
      const open = TimeOfDay(hour: 10, minute: 0);
      const close = TimeOfDay(hour: 19, minute: 30);

      final wh = _wh(
        start: WorkingHours.fromTimeOfDay(open),
        end: WorkingHours.fromTimeOfDay(close),
      );

      expect(wh.start, open);
      expect(wh.end, close);
    });
  });

  group('freezed value semantics', () {
    test('isActive defaults to true when omitted', () {
      const wh = WorkingHours(
        dayOfWeek: 1,
        startTime: '09:00:00',
        endTime: '18:00:00',
      );

      expect(wh.isActive, isTrue);
    });

    test('two windows with identical fields are equal', () {
      expect(_wh(), _wh());
    });

    test('copyWith toggling isActive preserves the rest of the window', () {
      final closed = _wh().copyWith(isActive: false);

      expect(closed.isActive, isFalse);
      expect(closed.dayOfWeek, 1);
      expect(closed.startTime, '09:00:00');
      expect(closed.endTime, '18:00:00');
      expect(closed, isNot(_wh()));
    });
  });
}
