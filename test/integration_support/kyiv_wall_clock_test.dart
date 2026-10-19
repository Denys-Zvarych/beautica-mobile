// Pure-Dart proof of `kyivWallClockUtc` (integration_test/support/), the
// DST-aware replacement for hand-offset `DateTime.utc(day, 6)` booking
// fixtures. Europe/Kyiv leaves summer time at 04:00 local on Sunday
// 2026-10-25 (UTC+3 -> UTC+2), so the same 09:00 Kyiv wall clock maps to two
// different UTC hours on either side of it.

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/kyiv_wall_clock.dart';

void main() {
  group('kyivWallClockUtc', () {
    test('09:00 Kyiv on 2026-10-24 (summer, UTC+3) is 06:00Z', () {
      final DateTime got = kyivWallClockUtc(DateTime(2026, 10, 24), 9);

      expect(got, DateTime.utc(2026, 10, 24, 6));
      expect(got.isUtc, isTrue);
    });

    test('09:00 Kyiv on 2026-10-26 (winter, UTC+2) is 07:00Z', () {
      final DateTime got = kyivWallClockUtc(DateTime(2026, 10, 26), 9);

      expect(got, DateTime.utc(2026, 10, 26, 7));
      expect(got.isUtc, isTrue);
    });

    test('09:00 Kyiv on the fall-back day itself (2026-10-25) is 07:00Z', () {
      // The switch happens at 04:00 local, so 09:00 is already UTC+2.
      expect(
        kyivWallClockUtc(DateTime(2026, 10, 25), 9),
        DateTime.utc(2026, 10, 25, 7),
      );
    });

    test('spring-forward (2027-03-28): 09:00 Kyiv is 07:00Z the day before, '
        '06:00Z on the day', () {
      // Europe/Kyiv enters summer time at 03:00 local on Sunday 2027-03-28
      // (UTC+2 -> UTC+3) — the direction the rolling fixture day crosses next.
      expect(
        kyivWallClockUtc(DateTime(2027, 3, 27), 9),
        DateTime.utc(2027, 3, 27, 7),
      );
      expect(
        kyivWallClockUtc(DateTime(2027, 3, 28), 9),
        DateTime.utc(2027, 3, 28, 6),
      );
    });

    test('minute is carried through, defaulting to 0', () {
      expect(
        kyivWallClockUtc(DateTime(2026, 6, 15), 12, 30),
        DateTime.utc(2026, 6, 15, 9, 30),
      );
      expect(
        kyivWallClockUtc(DateTime(2026, 6, 15), 12),
        DateTime.utc(2026, 6, 15, 9),
      );
    });

    test('reads only the date of [day] — the time-of-day is ignored', () {
      expect(
        kyivWallClockUtc(DateTime.utc(2026, 10, 26, 23, 59), 9),
        DateTime.utc(2026, 10, 26, 7),
      );
    });

    test('returns a plain DateTime, not a TZDateTime subtype', () {
      final DateTime got = kyivWallClockUtc(DateTime(2026, 10, 26), 9);

      expect(got.runtimeType, DateTime);
      expect(got.toIso8601String(), '2026-10-26T07:00:00.000Z');
    });
  });

  group('kyivFixtureDayOf', () {
    test('is the KYIV date of the instant, not its UTC date', () {
      // 22:30Z on 2026-08-01 is 01:30 Kyiv on 2026-08-02 (UTC+3).
      expect(
        kyivFixtureDayOf(DateTime.utc(2026, 8, 1, 22, 30)),
        DateTime(2026, 8, 2),
      );
      // 21:30Z on 2026-10-26 is 23:30 Kyiv the same day (UTC+2).
      expect(
        kyivFixtureDayOf(DateTime.utc(2026, 10, 26, 21, 30)),
        DateTime(2026, 10, 26),
      );
    });
  });
}
