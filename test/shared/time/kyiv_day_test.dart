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
}
