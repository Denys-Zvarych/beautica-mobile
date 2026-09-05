// Unit tests for `shared/time/kyiv_day.dart` — the single canonical Kyiv
// calendar-day derivation ([kyivDayOf] / [kyivToday]).
//
// WHY THIS FILE EXISTS
// --------------------
// `toBeauticaTime` (tested in `time_zones_test.dart`) proves the WALL-CLOCK
// conversion is host-independent and DST-aware. This file proves the
// DERIVED-DAY layer built on top of it: that [kyivDayOf] resolves the
// correct calendar day (not merely the correct hour) for an instant observed
// from a device sitting in a completely unrelated zone, and that it does so
// correctly straddling a Europe/Kyiv DST transition — the exact place a
// fixed-offset or host-local shortcut drifts by a whole day.
//
// Every fixture below is anchored with `DateTime.utc(...)` or an explicit
// `tz.TZDateTime(...)` device zone — never a bare `DateTime(...)` — per
// `scripts/forbid_host_local_instant_anchor.sh`.
//
// Pure Dart — no Flutter, no widget tree, no network.

import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  // The harness has already initialised the tz database; calling again here
  // is an idempotent no-op and keeps the file self-contained when run in
  // isolation.
  initBeauticaTimeZones();

  group('kyivDayOf resolves the Kyiv calendar day for a device-agnostic '
      'instant', () {
    test('a UTC instant just before local Kyiv midnight resolves to the NEXT '
        'Kyiv day', () {
      // 2026-08-01T22:30Z + 3h (EEST, August is summer) = 2026-08-02
      // 01:30 Kyiv — the day has already rolled over in Kyiv even though
      // the UTC calendar date is still the 1st.
      final DateTime day = kyivDayOf(DateTime.utc(2026, 8, 1, 22, 30));

      expect(day, DateTime(2026, 8, 2));
      expect(day.hour, 0, reason: 'a date token sits at midnight');
    });
  });

  group('kyivDayOf disagrees with the DEVICE day when the device sits in a '
      'foreign zone', () {
    test('a Tokyo-device instant that is already "tomorrow" locally is still '
        '"today" (or earlier) in Kyiv', () {
      // 2026-08-02 05:00 in Asia/Tokyo (UTC+9, no DST) is 2026-08-01
      // 20:00Z, which is 2026-08-01 23:00 Kyiv (EEST, +3) — a full day
      // EARLIER than the device's own calendar day. A device-local
      // `DateTime.now()` stripped of its time-of-day would wrongly read
      // 2026-08-02; only routing through Kyiv gets 2026-08-01.
      final tz.TZDateTime tokyoInstant = tz.TZDateTime(
        tz.getLocation('Asia/Tokyo'),
        2026,
        8,
        2,
        5,
        0,
      );

      final DateTime day = kyivDayOf(tokyoInstant);

      expect(day, DateTime(2026, 8, 1));
      expect(
        day,
        isNot(DateTime(2026, 8, 2)),
        reason:
            'the device\'s OWN calendar day (Tokyo, Aug 2) must never leak '
            'through — only the Kyiv day is legal here',
      );
    });
  });

  group('kyivDayOf stays correct straddling a Europe/Kyiv DST transition '
      '(fall-back, 2026-10-25 01:00 UTC: EEST +3 → EET +2)', () {
    test('an instant BEFORE the switch uses the summer (+3) offset — a fixed '
        'winter (+2) offset would read one calendar day EARLIER', () {
      // 2026-10-24T21:01Z is before the 01:00Z switch, so Kyiv is still
      // EEST (+3): local = 2026-10-25 00:01 → day 25. Under a WRONG fixed
      // +2, local would read 2026-10-24 23:01 → day 24 — the case this
      // test pins.
      final DateTime day = kyivDayOf(DateTime.utc(2026, 10, 24, 21, 1));

      expect(day, DateTime(2026, 10, 25));
    });

    test('an instant AFTER the switch uses the winter (+2) offset — a fixed '
        'summer (+3) offset would read one calendar day LATER', () {
      // 2026-10-25T21:01Z is after the 01:00Z switch, so Kyiv is already
      // EET (+2): local = 2026-10-25 23:01 → day 25. Under a WRONG fixed
      // +3, local would read 2026-10-26 00:01 → day 26 — the case this
      // test pins.
      final DateTime day = kyivDayOf(DateTime.utc(2026, 10, 25, 21, 1));

      expect(day, DateTime(2026, 10, 25));
    });
  });

  group('kyivToday reads through the injected clock seam', () {
    test('delegates to kyivDayOf(clock())', () {
      final DateTime day = kyivToday(
        () => tz.TZDateTime(tz.getLocation('Asia/Tokyo'), 2026, 8, 2, 5, 0),
      );

      expect(day, DateTime(2026, 8, 1));
    });
  });

  // ── mobile-qa (2026-08-02 audit) — the date-token contract, empirically ───
  //
  // The file header's ILLEGAL list (`.toUtc()` / `.difference()` /
  // `.isBefore`/`.isAfter` against a booking instant) is a REVIEW-responsibility
  // invariant, not something `forbid_raw_clock_read.sh` (a declaration gate) or
  // the Dart type system can catch — a date token and a genuine instant are the
  // exact same runtime type. Nothing can PIN misuse at a call site that does
  // not exist yet. What this test CAN do is make the header's warning
  // concrete: demonstrate, with a real fixture, exactly how silently wrong the
  // banned operations are — so a future reviewer (or an agent) who is tempted
  // to reach for `.toUtc()` on a [kyivDayOf] result sees the failure mode
  // spelled out in a runnable example, not just prose.
  group('the date-token contract — why the ILLEGAL operations are illegal '
      '(documentation reinforcement, not a static gate)', () {
    test('.toUtc() on a date token does NOT round-trip to the instant it was '
        'derived from — it reinterprets the token\'s host-local midnight as '
        'if it were already UTC', () {
      // An instant deep in Kyiv's Aug 2nd (23:30 local, EEST +3 = 20:30Z).
      final DateTime instant = DateTime.utc(2026, 8, 2, 20, 30);
      final DateTime token = kyivDayOf(
        instant,
      ); // date token: Aug 2, host-local midnight.

      // The ORIGINAL instant is nowhere near host-local midnight on Aug 2.
      // This assertion IS the demonstration that `.toUtc()` on a date token is
      // garbage — `isNot(...)` asserts the round-trip FAILS. It is the one
      // place in the tree where performing the banned operation is the point,
      // and the only reason RULE 6 exists to flag it everywhere else.
      // date-token-ok: performing the banned operation IS this test's subject
      expect(instant, isNot(token.toUtc()));
      // `.toUtc()` on the token instead reports "midnight Aug 2 in the HOST's
      // own zone, expressed as UTC" — a value with no relationship to
      // [instant] at all beyond sharing a calendar day, which is exactly the
      // "compiles, runs, returns garbage" failure the file header warns about.
    });

    test('.difference() against a booking instant measures a bogus duration '
        'when one side is actually a date token', () {
      // A booking that starts at 23:30 Kyiv on Aug 1 (20:30Z).
      final DateTime bookingStartAt = DateTime.utc(2026, 8, 1, 20, 30);
      // "Today" resolves to the SAME Kyiv day the booking starts on.
      final DateTime today = kyivDayOf(bookingStartAt);
      expect(today, DateTime(2026, 8, 1));

      // A correct "is this booking today" check compares DAYS:
      expect(today, kyivDayOf(bookingStartAt));

      // But `.difference()` against the raw instant — the ILLEGAL operation —
      // reports a multi-hour gap for a booking that is unambiguously TODAY,
      // because [today] is host-local MIDNIGHT, not the booking's actual
      // wall-clock instant. A caller using this to gate e.g. "starts within
      // the next hour" would be wrong by however far local midnight sits from
      // the booking's real time.
      final Duration bogus = bookingStartAt.difference(today);
      expect(
        bogus,
        isNot(Duration.zero),
        reason:
            'a date token is never "the same instant" as the booking it was '
            'derived from, even when they share a calendar day — comparing '
            'their difference() measures host-local-midnight-to-instant, not '
            'anything meaningful',
      );
    });
  });

  // ── Phase 284 — kyivDaysBetween, the sanctioned token subtraction ─────────
  //
  // Subtracting two date tokens is LEGAL (both sides are the same kind of
  // value) but only through this function. The hand-written
  // `later.difference(earlier).inDays` shipped twice — most recently in
  // `shared/formatters/relative_date.dart` — and is wrong by exactly one day
  // whenever the HOST zone crosses a spring-forward between the two
  // host-local midnights.
  //
  // The transition cases carry the same `skip:` reasoning as
  // `relative_date_test.dart`'s: under a host with no transition in the
  // window (always `TZ=UTC`) they cannot discriminate, and a vacuous green is
  // worse than an honest skip. Reconcile PASSED + SKIPPED.
  group('kyivDaysBetween counts CALENDAR days between two date tokens', () {
    test('zero when both tokens name the same day', () {
      final DateTime day = kyivDayOf(DateTime.utc(2026, 6, 15, 9));

      expect(kyivDaysBetween(day, day), 0);
    });

    test('one for consecutive days, in the earlier → later direction', () {
      final DateTime jun14 = kyivDayOf(DateTime.utc(2026, 6, 14, 9));
      final DateTime jun15 = kyivDayOf(DateTime.utc(2026, 6, 15, 9));

      expect(kyivDaysBetween(jun14, jun15), 1);
    });

    test('NEGATIVE when [later] precedes [earlier] — a future-dated value is '
        'never clamped here; clamping is the caller\'s policy', () {
      final DateTime jun10 = kyivDayOf(DateTime.utc(2026, 6, 10, 9));
      final DateTime jun15 = kyivDayOf(DateTime.utc(2026, 6, 15, 9));

      expect(kyivDaysBetween(jun15, jun10), -5);
      expect(
        kyivDaysBetween(jun15, jun10),
        -kyivDaysBetween(jun10, jun15),
        reason: 'antisymmetric — swapping the operands negates the count',
      );
    });

    test('exactly 1 across the Europe/Kyiv SPRING FORWARD (2026-03-29), where '
        'the hand-written difference() measures 23 h and truncates to 0', () {
      final DateTime mar29 = kyivDayOf(DateTime.utc(2026, 3, 29, 12));
      final DateTime mar30 = kyivDayOf(DateTime.utc(2026, 3, 30, 12));

      expect(kyivDaysBetween(mar29, mar30), 1);
      // The mutation this pins, spelled out: the banned form on this very
      // fixture returns 0 on a Europe/Kyiv host.
      expect(
        mar30.difference(mar29).inDays,
        0,
        reason:
            'DEMONSTRATION, not an endorsement — this is the ILLEGAL '
            'hand-written form returning the wrong answer on the exact input '
            'kyivDaysBetween gets right. If this expectation ever fails, the '
            'host stopped observing a March transition and the case above '
            'should have skipped.',
      );
    }, skip: _skipUnlessHostShifts(2026, 3, 29, 2026, 3, 30));

    test('exactly 1 across the Europe/Kyiv FALL BACK (2026-10-25), the 25 h '
        'day the old arithmetic happened to survive', () {
      final DateTime oct25 = kyivDayOf(DateTime.utc(2026, 10, 25, 12));
      final DateTime oct26 = kyivDayOf(DateTime.utc(2026, 10, 26, 12));

      expect(kyivDaysBetween(oct25, oct26), 1);
    }, skip: _skipUnlessHostShifts(2026, 10, 25, 2026, 10, 26));

    test('an interval SPANNING a spring forward counts every calendar day — '
        'NEVER SKIPPED, so `TZ=UTC` still holds the contract', () {
      final DateTime mar24 = kyivDayOf(DateTime.utc(2026, 3, 24, 12));
      final DateTime mar31 = kyivDayOf(DateTime.utc(2026, 3, 31, 12));

      expect(kyivDaysBetween(mar24, mar31), 7);
    });

    test('a 180-day span crossing both yearly transitions is exact — the '
        'magnitude `bookings_day_rail.dart` documented as 4319:00:00', () {
      final DateTime jan20 = kyivDayOf(DateTime.utc(2026, 1, 20, 12));
      final DateTime jul19 = kyivDayOf(DateTime.utc(2026, 7, 19, 12));

      expect(kyivDaysBetween(jan20, jul19), 180);
    });
  });
}

/// `null` (run the test) when the HOST process zone's UTC offset differs
/// between host-local midnight on the two named days; a skip REASON otherwise.
/// See `test/shared/formatters/relative_date_test.dart` for the full rationale
/// — UTC has no DST, so a `TZ=UTC` run cannot discriminate this defect and
/// should say so rather than bank a vacuous pass.
String? _skipUnlessHostShifts(int y1, int m1, int d1, int y2, int m2, int d2) {
  if (DateTime(y1, m1, d1).timeZoneOffset !=
      DateTime(y2, m2, d2).timeZoneOffset) {
    return null;
  }
  return 'non-discriminating on this host: it holds one offset '
      '(${DateTime(y1, m1, d1).timeZoneName}) across $y1-$m1-$d1 → '
      '$y2-$m2-$d2. Run under TZ=Europe/Kyiv.';
}
