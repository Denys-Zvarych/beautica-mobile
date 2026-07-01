// Tests for DurationMinutes — the Ukrainian short duration label builder.
//
// Behaviour (from the source):
//   minutes < 60          → "<minutes> хв"
//   whole hours (m == 0)  → "<h> год"
//   hours + minutes       → "<h> год <m> хв"
// No pluralisation of "хв"/"год" — the labels are invariant. There is no
// special handling for 0 or for very large inputs; they follow the same rules.

import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DurationMinutes.format', () {
    test('sub-hour durations render only minutes', () {
      expect(DurationMinutes.format(45), '45 хв');
    });

    test('zero minutes renders "0 хв"', () {
      expect(DurationMinutes.format(0), '0 хв');
    });

    test('one minute renders "1 хв" (no singular form)', () {
      expect(DurationMinutes.format(1), '1 хв');
    });

    test('59 minutes stays under the hour boundary', () {
      expect(DurationMinutes.format(59), '59 хв');
    });

    test('exactly one hour renders "1 год" with no minutes part', () {
      expect(DurationMinutes.format(60), '1 год');
    });

    test('one minute past the hour shows both parts', () {
      expect(DurationMinutes.format(61), '1 год 1 хв');
    });

    test('ninety minutes renders "1 год 30 хв"', () {
      expect(DurationMinutes.format(90), '1 год 30 хв');
    });

    test('whole multiples of an hour omit the minutes part', () {
      expect(DurationMinutes.format(120), '2 год');
      expect(DurationMinutes.format(180), '3 год');
    });

    test('hours plus a remainder show both parts', () {
      expect(DurationMinutes.format(125), '2 год 5 хв');
    });

    test('a full day stays expressed in hours', () {
      expect(DurationMinutes.format(1440), '24 год');
    });

    test('the 59→60 boundary switches from minutes to hours', () {
      expect(DurationMinutes.format(59), '59 хв');
      expect(DurationMinutes.format(60), '1 год');
    });
  });
}
