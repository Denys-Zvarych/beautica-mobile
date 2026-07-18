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
  });
}
