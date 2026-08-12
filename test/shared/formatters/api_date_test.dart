// Phase 7.1 — `yyyy-MM-dd` wire-date helpers.
//
// These are the primitives the whole booking-filter date path rests on, and
// the bug they exist to prevent (a one-day slip near midnight for any device
// east of UTC) is silent: the request succeeds, the data looks plausible, and
// the user's filter is simply off by a day.

import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/shared/formatters/api_date.dart';

void main() {
  group('toApiDate', () {
    test('formats a plain date', () {
      expect(toApiDate(DateTime(2026, 7, 18)), '2026-07-18');
    });

    test('zero-pads single-digit months and days', () {
      expect(toApiDate(DateTime(2026, 1, 5)), '2026-01-05');
      expect(toApiDate(DateTime(2026, 12, 9)), '2026-12-09');
    });

    test('ignores any time component — the calendar day is what travels', () {
      expect(toApiDate(DateTime(2026, 7, 18, 13, 45, 30, 500)), '2026-07-18');
    });

    test('one second before local midnight still reads as THAT day', () {
      expect(toApiDate(DateTime(2026, 7, 18, 23, 59, 59)), '2026-07-18');
    });

    test('local midnight exactly reads as that day, not the previous one', () {
      expect(toApiDate(DateTime(2026, 7, 19)), '2026-07-19');
    });

    test('a late-evening local time is NOT shifted to the next/previous UTC '
        'day — the day-slip regression guard', () {
      // On any UTC+n device, `.toUtc()` on 23:30 local rolls the date forward;
      // on UTC-n it rolls back. Reading local fields directly cannot.
      final DateTime lateLocal = DateTime(2026, 7, 18, 23, 30);
      expect(toApiDate(lateLocal), '2026-07-18');

      final DateTime earlyLocal = DateTime(2026, 7, 19, 0, 30);
      expect(toApiDate(earlyLocal), '2026-07-19');
    });

    test('handles a leap day', () {
      expect(toApiDate(DateTime(2028, 2, 29)), '2028-02-29');
    });
  });

  group('dateOnly', () {
    test('truncates the time component to local midnight', () {
      expect(
        dateOnly(DateTime(2026, 7, 18, 16, 42, 9, 3)),
        DateTime(2026, 7, 18),
      );
    });

    test('is idempotent', () {
      final DateTime once = dateOnly(DateTime(2026, 7, 18, 9, 1));
      expect(dateOnly(once), once);
    });

    test('collapses two same-day instants to an EQUAL value — the family-key '
        'normalisation this exists for', () {
      expect(
        dateOnly(DateTime(2026, 7, 18, 0, 0, 1)),
        dateOnly(DateTime(2026, 7, 18, 23, 59, 59)),
      );
    });

    test('produces a local (non-UTC) DateTime', () {
      expect(dateOnly(DateTime(2026, 7, 18, 10)).isUtc, isFalse);
    });
  });

  group('parseApiDate', () {
    test('parses a bare backend day into a local date-only DateTime', () {
      final DateTime d = parseApiDate('2026-07-18');

      expect(d, DateTime(2026, 7, 18));
      expect(d.isUtc, isFalse);
      expect(d.hour, 0);
    });

    test('round-trips with toApiDate', () {
      for (final String s in <String>[
        '2026-01-01',
        '2026-07-18',
        '2028-02-29',
        '2026-12-31',
      ]) {
        expect(toApiDate(parseApiDate(s)), s);
      }
    });

    test('parses zero-padded components', () {
      expect(parseApiDate('2026-01-05'), DateTime(2026, 1, 5));
    });

    test('throws FormatException on a malformed value', () {
      expect(() => parseApiDate('not-a-date'), throwsFormatException);
      expect(() => parseApiDate('2026-07'), throwsFormatException);
      expect(() => parseApiDate(''), throwsFormatException);
      expect(() => parseApiDate('2026-07-18T10:00:00Z'), throwsFormatException);
    });

    // Phase 244 — hardening added for the `/schedule?date=` deep-link route,
    // which hands an attacker-controlled string straight to this function
    // (`MainActivity` is `exported="true"`). See this function's own doc for
    // the two failure modes a bare `DateTime(y, m, d)` construction has that
    // are NOT `FormatException` by default: `ArgumentError` on a
    // representable-range-exceeding year, and a SILENTLY ABSURD (but
    // non-throwing) `DateTime` for a year so large `int.tryParse` still
    // accepts it. Both must surface as `FormatException`, never anything
    // else, and never as a quietly-wrong date.
    group('bound hardening (mobile-security)', () {
      test(
        'a year within int range but outside DateTime\'s representable range '
        'throws FormatException, not ArgumentError',
        () {
          expect(
            () => parseApiDate('300000-01-01'),
            throwsFormatException,
            reason:
                'DateTime(300000, 1, 1) throws ArgumentError directly — the '
                'bound check must reject this BEFORE construction',
          );
        },
      );

      test('an absurdly large year that DateTime would silently accept without '
          'throwing ANYTHING still throws FormatException', () {
        expect(
          () => parseApiDate('9999999999999-01-01'),
          throwsFormatException,
        );
      });

      test('a day that does not exist rolls the month forward silently in '
          'DateTime — parseApiDate must reject the rollover instead', () {
        // April has 30 days; DateTime(2026, 4, 31) normalises to May 1.
        expect(() => parseApiDate('2026-04-31'), throwsFormatException);
      });

      test(
        'February 30th (never valid) is rejected via the same rollover check',
        () {
          expect(() => parseApiDate('2026-02-30'), throwsFormatException);
        },
      );

      test('February 30th on a leap year is STILL rejected — the rollover '
          'check is date-invalid, not leap-year-unaware', () {
        expect(() => parseApiDate('2028-02-30'), throwsFormatException);
      });

      test('the minimum accepted year (0001-01-01) parses cleanly', () {
        final DateTime d = parseApiDate('0001-01-01');
        expect(d, DateTime(1, 1, 1));
      });

      test('the maximum accepted year (9999-12-31) parses cleanly', () {
        final DateTime d = parseApiDate('9999-12-31');
        expect(d, DateTime(9999, 12, 31));
      });

      test('year 0000 is rejected (below the 1..9999 bound)', () {
        expect(() => parseApiDate('0000-01-01'), throwsFormatException);
      });

      test('year 10000 is rejected (above the 1..9999 bound)', () {
        expect(() => parseApiDate('10000-01-01'), throwsFormatException);
      });
    });
  });
}
