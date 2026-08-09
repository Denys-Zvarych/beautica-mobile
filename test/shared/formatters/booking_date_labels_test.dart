// Phase 23.3 — the pinning test for `shared/formatters/booking_date_labels.dart`.
//
// This file did not exist before Phase 23.3; the phase's own doc
// (`docs/mobile-phases/phase-216-23.3-booking-labels-migration.md`) describes
// it as pre-existing ("must stay green unchanged"), but no such file was
// actually present in the repo at the time this phase landed — coverage of
// the seven formatters lived only indirectly, through the widget/screen tests
// that render their output (`master_booking_card_test.dart`,
// `month_calendar_test.dart`, `slot_time_tz_regression_test.dart`, etc.). This
// file is the direct, isolated pin the doc calls for, created rather than
// modified (the doc's own "Files to create / modify" section covers both).
//
// Every case below is a REAL calendar fixture — the day/weekday/month facts
// are independently true of the Gregorian calendar, not re-derived from the
// module under test — so a table mix-up (e.g. genitive substituted for
// abbreviated, or a wrong weekday-numbering offset) fails a literal string
// comparison, not a tautology.
//
// TIMEZONE: every fixture instant is constructed as canonical UTC
// (`DateTime.utc(...)`), exactly the shape the generated built_value client
// hands these formatters in production, and every expected wall-clock value
// below is the KNOWN Europe/Kyiv rendering of that instant (EET = UTC+2 in
// January, EEST = UTC+3 in June/July) — never `.toLocal()`. The Phase 23.3
// cross-midnight case additionally proves the Kyiv CALENDAR DAY, not just the
// clock time, is read from the converted instant.

import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/formatters/uk_calendar.dart'
    show weekdayAbbrev;
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Idempotent — the global test config also does this; kept here so the
  // file is self-contained when run in isolation (same convention as
  // `slot_time_tz_regression_test.dart`).
  initBeauticaTimeZones();

  group('formatBookingDayHeader', () {
    test('Monday 15 January (EET, UTC+2) → "пн, 15 січ"', () {
      // 12:00Z == 14:00 Kyiv (EET, +2h) — same calendar day either way, so
      // this case isolates the vocabulary/format shape from any DST math.
      final DateTime instant = DateTime.utc(2024, 1, 15, 12);
      expect(formatBookingDayHeader(instant), 'пн, 15 січ');
    });
  });

  group('formatBookingWindow', () {
    test(
      'Monday 15 January, 14:00–18:30 Kyiv → "пн, 15 січ · 14:00–18:30"',
      () {
        final DateTime start = DateTime.utc(2024, 1, 15, 12);
        final DateTime end = DateTime.utc(2024, 1, 15, 16, 30);
        expect(formatBookingWindow(start, end), 'пн, 15 січ · 14:00–18:30');
      },
    );
  });

  group('formatSlotTime', () {
    test('06:00Z is 09:00 Kyiv (EEST, +3h in July)', () {
      final DateTime instant = DateTime.utc(2024, 7, 17, 6);
      expect(formatSlotTime(instant), '09:00');
    });

    test('07:15Z is 09:15 Kyiv (EET, +2h in January)', () {
      final DateTime instant = DateTime.utc(2024, 1, 15, 7, 15);
      expect(formatSlotTime(instant), '09:15');
    });
  });

  group('formatFullDate', () {
    test('Monday 15 January (EET, UTC+2) → "понеділок, 15 січня"', () {
      final DateTime instant = DateTime.utc(2024, 1, 15, 12);
      expect(formatFullDate(instant), 'понеділок, 15 січня');
    });
  });

  group('formatTimeRange', () {
    test('90-minute service starting 14:00 Kyiv → "14:00–15:30"', () {
      final DateTime start = DateTime.utc(2024, 1, 15, 12); // 14:00 Kyiv
      expect(formatTimeRange(start, 90), '14:00–15:30');
    });
  });

  group('formatSlotTimeRange', () {
    test('two real instants, 14:00–16:45 Kyiv → "14:00–16:45"', () {
      final DateTime start = DateTime.utc(2024, 1, 15, 12); // 14:00 Kyiv
      final DateTime end = DateTime.utc(2024, 1, 15, 14, 45); // 16:45 Kyiv
      expect(formatSlotTimeRange(start, end), '14:00–16:45');
    });
  });

  group('formatStubDayLine', () {
    test('Wednesday 19 June (EEST, UTC+3) → "червня, ср"', () {
      // 10:00Z == 13:00 Kyiv — same calendar day, isolates format shape.
      final DateTime instant = DateTime.utc(2024, 6, 19, 10);
      expect(formatStubDayLine(instant), 'червня, ср');
    });
  });

  group('formatStubDayNumber', () {
    test('Wednesday 19 June (EEST, UTC+3) → "19"', () {
      // Same fixture as the formatStubDayLine test above — on the booking
      // card the two lines stack together and must describe the same
      // calendar date, so they share the same instant here too.
      final DateTime instant = DateTime.utc(2024, 6, 19, 10);
      expect(formatStubDayNumber(instant), '19');
    });
  });

  // ===========================================================================
  // mobile-qa — 2026-08 regression: `_DateStub`'s day number line read
  // `start.day.toString()` off the raw UTC instant while its two sibling
  // lines (`formatStubDayLine`, the slot time) already converted to the
  // Europe/Kyiv wall-clock via `toBeauticaTime` first. Every fixture ABOVE in
  // this file sits mid-UTC-day (comments say so explicitly — "isolates
  // format shape from any DST math" / "same calendar day either way"), so
  // the day number and the Kyiv conversion always agreed by accident: none
  // of them would have failed pre-fix. These two sit in the UTC 21:00–23:59
  // divergence window instead (winter UTC+2 / summer UTC+3), where Kyiv is
  // already the next calendar day.
  //
  // Winter AND summer are both required, not just one: this proves
  // `toBeauticaTime`'s DST-awareness itself, since it reads the real IANA
  // Europe/Kyiv database — a test pinning only one offset could pass by
  // accident against an implementation that hardcoded +2 or +3.
  //
  // Worked proof the pre-fix bug was not cosmetic: 2026-06-18 22:30Z is
  // 2026-06-19 01:30 Kyiv, a Friday — but 18 June 2026 (the pre-fix, raw-UTC
  // day number) is a Thursday. No 18 June 2026 is ever a Friday; pre-fix the
  // card paired a real weekday caption with a day number that date can never
  // have.
  // ===========================================================================
  group('formatStubDayNumber — UTC 21:00–23:59 divergence window', () {
    test('summer/EEST: 2026-06-18T22:30Z is 2026-06-19 01:30 Kyiv (Friday) → '
        '"19", agreeing with formatStubDayLine\'s "червня, пт"', () {
      final DateTime instant = DateTime.utc(2026, 6, 18, 22, 30);
      expect(formatStubDayNumber(instant), '19');
      expect(formatStubDayLine(instant), 'червня, пт');
    });

    test('winter/EET: 2026-01-18T22:30Z is 2026-01-19 00:30 Kyiv (Monday) → '
        '"19", agreeing with formatStubDayLine\'s "січня, пн"', () {
      final DateTime instant = DateTime.utc(2026, 1, 18, 22, 30);
      expect(formatStubDayNumber(instant), '19');
      expect(formatStubDayLine(instant), 'січня, пн');
    });
  });

  // ===========================================================================
  // Phase 23.3 — cross-midnight regression (mandated by the phase doc).
  //
  // A careless table-index refactor (e.g. reading `local.weekday` before the
  // `toBeauticaTime` conversion, or reintroducing device `.toLocal()`) is
  // exactly the class of bug this pins: the fixture below is a UTC instant
  // that is a DIFFERENT calendar day — and a different weekday — in Kyiv than
  // in raw UTC.
  //
  // 2026-07-14T22:30:00Z is 2026-07-15T01:30 in Kyiv (EEST, UTC+3): the raw
  // UTC date is the 14th (a Tuesday), the Kyiv date is the 15th (a
  // Wednesday). Both `formatBookingDayHeader` and `formatFullDate` must read
  // the 15th/Wednesday, never the 14th/Tuesday.
  // ===========================================================================
  group('cross-midnight — Kyiv calendar day differs from raw UTC', () {
    final DateTime crossing = DateTime.utc(2026, 7, 14, 22, 30);

    test('sanity: the raw UTC date (14th) is a different weekday than the '
        'Kyiv date (15th)', () {
      expect(
        DateTime.utc(2026, 7, 14).weekday,
        isNot(DateTime(2026, 7, 15).weekday),
      );
    });

    test(
      'formatBookingDayHeader reads the Kyiv day/weekday/month → "ср, 15 лип"',
      () {
        expect(formatBookingDayHeader(crossing), 'ср, 15 лип');
      },
    );

    test(
      'formatFullDate reads the Kyiv day/weekday/month → "середа, 15 липня"',
      () {
        expect(formatFullDate(crossing), 'середа, 15 липня');
      },
    );

    // The stub formatters (Phase 14.3) were not covered by this group before
    // mobile-qa's 2026-08 audit — see the dedicated divergence-window group
    // above for why that mattered in practice.
    test(
      'formatStubDayNumber reads the Kyiv day, not the raw UTC day → "15"',
      () {
        expect(formatStubDayNumber(crossing), '15');
      },
    );

    test(
      'formatStubDayLine reads the Kyiv day/weekday/month → "липня, ср"',
      () {
        expect(formatStubDayLine(crossing), 'липня, ср');
      },
    );

    test('formatStubDayNumber and formatStubDayLine agree on the same calendar '
        'date — the invariant the 2026-08 bug violated', () {
      // Parse the day number out of formatStubDayNumber's own output and
      // independently derive its weekday via plain Gregorian arithmetic
      // (`DateTime(year, month, day).weekday`, Dart core — NOT
      // `toBeauticaTime`, so this does not just re-run the same conversion
      // the fix performs), then confirm that weekday is the one
      // formatStubDayLine actually printed. Pre-fix, formatStubDayNumber
      // returned the raw UTC day (14, a Tuesday) while formatStubDayLine
      // still correctly read "липня, ср" (Wednesday) — the two lines
      // named two different dates, which is exactly what this pins.
      final int day = int.parse(formatStubDayNumber(crossing));
      final int trueWeekday = DateTime(2026, 7, day).weekday;
      final String expectedAbbrev = weekdayAbbrev(trueWeekday);

      expect(
        formatStubDayLine(crossing),
        endsWith(', $expectedAbbrev'),
        reason:
            'day number $day and formatStubDayLine "${formatStubDayLine(crossing)}" '
            'must name the same weekday',
      );
    });
  });
}
