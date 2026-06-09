// Phase 15.5 — Unit tests for [ScheduleDateMath], the Dart mirror of the backend
// `com.beautica.master.service.ScheduleDateMath`.
//
// Strategy: each rule is exercised with an injected fixed `today` (date-only),
// exactly mirroring the backend `ScheduleDateMathTest` expectation table so the
// client never sends a range the backend would reject. The Dart surface is
// narrower than the backend (no `expandInclusive`/`assertWithinBounds` — the
// client only NEEDS the preset ranges, the far-future cap, and the two boolean
// guards `exceedsCap`/`exceedsSpan` + the `clampToCap` defence), so these tests
// cover that narrower surface against the same calendar arithmetic the backend
// table pins.

import 'package:beautica_mobile/features/schedule/domain/schedule_date_math.dart';
import 'package:flutter_test/flutter_test.dart';

ScheduleDateMath _at(int y, int m, int d) =>
    ScheduleDateMath(today: DateTime(y, m, d));

void main() {
  group('ScheduleDateMath.today / isPast / isSelectable', () {
    test('strips the time component to a local-midnight date-only today', () {
      final math = ScheduleDateMath(today: DateTime(2024, 5, 22, 22, 30));
      expect(math.today, DateTime(2024, 5, 22));
    });

    test('classifies yesterday as past, today and tomorrow as not past', () {
      final math = _at(2024, 5, 22);
      expect(math.isPast(DateTime(2024, 5, 21)), isTrue);
      expect(math.isPast(DateTime(2024, 5, 22)), isFalse);
      expect(math.isPast(DateTime(2024, 5, 23)), isFalse);
    });

    test('treats today and future as selectable, past as frozen', () {
      final math = _at(2024, 5, 22);
      expect(math.isSelectable(DateTime(2024, 5, 21)), isFalse);
      expect(math.isSelectable(DateTime(2024, 5, 22)), isTrue);
      expect(math.isSelectable(DateTime(2024, 5, 23)), isTrue);
    });
  });

  group('ScheduleDateMath.wholeCurrentMonth', () {
    test('clamps start to today when today is after the first of month', () {
      final range = _at(2024, 5, 21).wholeCurrentMonth();
      expect(
        range,
        ScheduleRangeDates(DateTime(2024, 5, 21), DateTime(2024, 5, 31)),
      );
    });

    test('starts at the first of month when today is the first', () {
      final range = _at(2024, 5, 1).wholeCurrentMonth();
      expect(
        range,
        ScheduleRangeDates(DateTime(2024, 5, 1), DateTime(2024, 5, 31)),
      );
    });

    test('uses the leap-aware last day (Feb 2024 → 29)', () {
      final range = _at(2024, 2, 10).wholeCurrentMonth();
      expect(range.end, DateTime(2024, 2, 29));
    });

    test('uses the non-leap last day (Feb 2023 → 28)', () {
      final range = _at(2023, 2, 10).wholeCurrentMonth();
      expect(range.end, DateTime(2023, 2, 28));
    });
  });

  group('ScheduleDateMath.nextNMonths (end-of-month clamp)', () {
    test('Jan 31 + 1mo clamps to Feb 29 in a leap year', () {
      final range = _at(2024, 1, 31).nextNMonths(1);
      expect(range.start, DateTime(2024, 1, 31));
      expect(range.end, DateTime(2024, 2, 29));
    });

    test('Jan 31 + 1mo clamps to Feb 28 in a non-leap year', () {
      final range = _at(2023, 1, 31).nextNMonths(1);
      expect(range.end, DateTime(2023, 2, 28));
    });

    test('Nov 30 + 3mo clamps into the next (non-leap) February → Feb 28', () {
      final range = _at(2024, 11, 30).nextNMonths(3);
      expect(range.start, DateTime(2024, 11, 30));
      expect(range.end, DateTime(2025, 2, 28));
    });

    test('a plain 3-month preset rolls the day forward unchanged', () {
      final range = _at(2024, 5, 22).nextNMonths(3);
      expect(
        range,
        ScheduleRangeDates(DateTime(2024, 5, 22), DateTime(2024, 8, 22)),
      );
    });
  });

  group('ScheduleDateMath.wholeYear', () {
    test('runs from today through Dec 31 of THIS year (never +1 year)', () {
      final range = _at(2024, 2, 29).wholeYear();
      expect(
        range,
        ScheduleRangeDates(DateTime(2024, 2, 29), DateTime(2024, 12, 31)),
      );
    });
  });

  group('ScheduleDateMath.addMonths / addYears (leap clamping)', () {
    test('addMonths clamps an end-of-month origin onto a shorter target', () {
      expect(
        _at(2024, 5, 22).addMonths(DateTime(2024, 1, 31), 1),
        DateTime(2024, 2, 29),
      );
      expect(
        _at(2023, 5, 22).addMonths(DateTime(2023, 1, 31), 1),
        DateTime(2023, 2, 28),
      );
    });

    test('addMonths borrows a whole year for a negative offset', () {
      expect(
        _at(2024, 5, 22).addMonths(DateTime(2024, 1, 15), -1),
        DateTime(2023, 12, 15),
      );
    });

    test('addYears clamps a Feb-29 origin to Feb-28 in a non-leap target', () {
      expect(
        _at(2024, 2, 29).addYears(DateTime(2024, 2, 29), 1),
        DateTime(2025, 2, 28),
      );
    });

    test('addYears keeps Feb-29 when the target year is also leap', () {
      expect(
        _at(2024, 2, 29).addYears(DateTime(2024, 2, 29), 4),
        DateTime(2028, 2, 29),
      );
    });
  });

  group('ScheduleDateMath.cap (today + 2 years)', () {
    test('clamps a leap-day origin to Feb 28 of the non-leap target year', () {
      // today 2024-02-29 → cap 2026-02-28 (mirrors backend cap() table).
      expect(_at(2024, 2, 29).cap(), DateTime(2026, 2, 28));
    });

    test('is exactly today + 2 years for an ordinary date', () {
      expect(_at(2024, 5, 22).cap(), DateTime(2026, 5, 22));
    });
  });

  group('ScheduleDateMath.exceedsCap / clampToCap', () {
    test(
      'a date one day beyond the cap exceeds it; the cap itself does not',
      () {
        final math = _at(2024, 5, 22); // cap = 2026-05-22
        expect(math.exceedsCap(DateTime(2026, 5, 22)), isFalse);
        expect(math.exceedsCap(DateTime(2026, 5, 23)), isTrue);
      },
    );

    test('clampToCap pins a too-far end to the cap and leaves an in-bounds '
        'end untouched', () {
      final math = _at(2024, 5, 22); // cap = 2026-05-22
      expect(math.clampToCap(DateTime(2030, 1, 1)), DateTime(2026, 5, 22));
      expect(math.clampToCap(DateTime(2025, 1, 1)), DateTime(2025, 1, 1));
    });
  });

  group('ScheduleDateMath.exceedsSpan (366-day span guard)', () {
    test('an exactly-365-day span (366 inclusive dates) is accepted', () {
      final from = DateTime(2024, 1, 1);
      final to = from.add(const Duration(days: 365)); // 366 inclusive dates
      final math = _at(2024, 1, 1);
      expect(math.exceedsSpan(from, to), isFalse);
      expect(ScheduleRangeDates(from, to).inclusiveDays, 366);
    });

    test('a 366-day span (367 inclusive dates) is rejected', () {
      final from = DateTime(2024, 1, 1);
      final to = from.add(const Duration(days: 366));
      expect(_at(2024, 1, 1).exceedsSpan(from, to), isTrue);
    });
  });

  group('ScheduleRangeDates value semantics', () {
    test('inclusiveDays is 1 for a single-day range', () {
      final r = ScheduleRangeDates(
        DateTime(2024, 5, 22),
        DateTime(2024, 5, 22),
      );
      expect(r.inclusiveDays, 1);
    });

    test('equality ignores the time-of-day, comparing date-only', () {
      final a = ScheduleRangeDates(
        DateTime(2024, 5, 1, 9),
        DateTime(2024, 5, 31, 17),
      );
      final b = ScheduleRangeDates(DateTime(2024, 5, 1), DateTime(2024, 5, 31));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
