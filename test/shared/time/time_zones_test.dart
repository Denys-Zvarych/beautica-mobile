// Unit tests for the Beautica market timezone anchor (`shared/time/time_zones.dart`).
//
// WHY THIS FILE EXISTS
// --------------------
// The Kyiv-pin fix (device `.toLocal()` → `toBeauticaTime`) rests entirely on
// two properties that the slot/formatter regression test does NOT lock:
//
//   1. HOST-INDEPENDENCE — the conversion target is pinned to Europe/Kyiv in
//      code, so a UTC CI runner and a Kyiv dev box produce identical wall-clocks.
//      Every expectation below is a KNOWN Kyiv wall-clock literal, derived from
//      the UTC instant + the calendar, NEVER from `.toLocal()`. There is no `TZ`
//      guard, so none of these can pass vacuously on a particular runner — the
//      suite is run under both `TZ=UTC` and `TZ=Europe/Kyiv` and must be green
//      under each.
//
//   2. DST-AWARENESS — Kyiv is UTC+2 in winter (EET) and UTC+3 in summer (EEST).
//      The slot regression only exercises a JULY instant (UTC+3), so a naive
//      FIXED `+3` offset would pass it. The winter cases and the two EU DST
//      transition boundaries below get exactly ONE side wrong under a fixed
//      offset, so they are what actually proves the fix is DST-correct.
//
// The process-global harness (`test/flutter_test_config.dart`) already calls
// `initBeauticaTimeZones()`, so the tz database is loaded before this main runs;
// the idempotency group calls it again to prove extra calls are safe no-ops.
//
// Pure Dart — no Flutter, no widget tree, no network.

import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The harness has already initialised the tz database; calling again here is
  // an idempotent no-op and keeps the file self-contained when run in isolation.
  initBeauticaTimeZones();

  group('initBeauticaTimeZones is idempotent + resolves the Kyiv location', () {
    test('the anchor constant is the IANA Europe/Kyiv name', () {
      expect(kBeauticaTimeZoneName, 'Europe/Kyiv');
    });

    test('repeated calls are safe no-ops and leave the zone resolved', () {
      // Calling several more times must neither throw nor change the resolved
      // location — the whole point of the idempotent guard so app main, the test
      // harness and the integration boot path can all call it unconditionally.
      initBeauticaTimeZones();
      initBeauticaTimeZones();
      initBeauticaTimeZones();

      expect(beauticaZone.name, 'Europe/Kyiv');
    });

    test('beauticaZone exposes the resolved Europe/Kyiv location', () {
      expect(beauticaZone.name, kBeauticaTimeZoneName);
    });
  });

  group('toBeauticaTime converts a UTC instant to the Kyiv wall-clock', () {
    test('display-only: the source UTC instant is never mutated', () {
      final DateTime instant = DateTime.utc(2026, 7, 15, 10);
      toBeauticaTime(instant);

      expect(instant, DateTime.utc(2026, 7, 15, 10));
      expect(instant.isUtc, isTrue);
    });

    test('the same instant renders the same Kyiv wall-clock on any runner', () {
      // Host-independence, stated as a fact: this expectation is a literal Kyiv
      // wall-clock, so it holds identically under TZ=UTC and TZ=Europe/Kyiv.
      final DateTime summerUtc = DateTime.utc(2026, 7, 15, 10);
      final converted = toBeauticaTime(summerUtc);

      expect(converted.year, 2026);
      expect(converted.month, 7);
      expect(converted.day, 15);
      expect(converted.hour, 13); // 10:00Z + 3h (EEST)
      expect(converted.minute, 0);
    });
  });

  group('DST-awareness: Kyiv is UTC+2 in winter, UTC+3 in summer', () {
    test(
      'WINTER instant (January) converts at UTC+2 — a fixed +3 would fail',
      () {
        // 2026-01-15T10:00Z → 12:00 Kyiv (EET, +2). A naive fixed +3 offset would
        // wrongly render 13:00 here; this is the case the July-only regression
        // cannot catch.
        final converted = toBeauticaTime(DateTime.utc(2026, 1, 15, 10));

        expect(converted.hour, 12);
        expect(converted.timeZoneOffset, const Duration(hours: 2));
      },
    );

    test('SUMMER instant (July) converts at UTC+3', () {
      // 2026-07-15T10:00Z → 13:00 Kyiv (EEST, +3).
      final converted = toBeauticaTime(DateTime.utc(2026, 7, 15, 10));

      expect(converted.hour, 13);
      expect(converted.timeZoneOffset, const Duration(hours: 3));
    });

    test('offsets differ between winter and summer for the same wall-hour', () {
      // Strictly encodes that the offset is NOT constant across the year — the
      // single strongest guard against a fixed-offset regression.
      final winter = toBeauticaTime(DateTime.utc(2026, 1, 15, 10));
      final summer = toBeauticaTime(DateTime.utc(2026, 7, 15, 10));

      expect(
        winter.timeZoneOffset,
        isNot(summer.timeZoneOffset),
        reason: 'a DST-aware zone must apply +2 in winter and +3 in summer',
      );
    });
  });

  group('beauticaZone guards against being read before init', () {
    test('reading before initBeauticaTimeZones throws a StateError', () {
      // The process-global harness initialises tz once for the whole run, so
      // this defensive branch is unreachable without a deliberate reset. Undo
      // the reset before the test ends (addTearDown) so every other test in the
      // shared process still sees an initialised database — the reset MUST be
      // temporary or it breaks unrelated tests.
      addTearDown(initBeauticaTimeZones);

      resetBeauticaTimeZonesForTest();

      expect(() => beauticaZone, throwsStateError);
      expect(
        () => toBeauticaTime(DateTime.utc(2026, 7, 15, 10)),
        throwsStateError,
      );

      // Restore immediately (belt-and-braces alongside the tearDown) so any
      // conversion later in this main body also succeeds.
      initBeauticaTimeZones();
      expect(beauticaZone.name, kBeauticaTimeZoneName);
    });
  });

  group('DST boundary transitions (EU rule: switch at 01:00 UTC)', () {
    // EU DST begins the last Sunday of March 2026 (the 29th) and ends the last
    // Sunday of October 2026 (the 25th), both at 01:00 UTC. These are the
    // instants where a fixed offset is provably wrong on exactly one side.

    test('spring-forward: 00:59Z is +2, 01:00Z jumps to +3 (03:00→04:00)', () {
      final justBefore = toBeauticaTime(DateTime.utc(2026, 3, 29, 0, 59));
      final justAfter = toBeauticaTime(DateTime.utc(2026, 3, 29, 1));

      // Before the switch: still EET (+2) → 02:59 local.
      expect(justBefore.timeZoneOffset, const Duration(hours: 2));
      expect(justBefore.hour, 2);
      expect(justBefore.minute, 59);

      // After the switch: EEST (+3); Kyiv clocks jump 03:00 → 04:00.
      expect(justAfter.timeZoneOffset, const Duration(hours: 3));
      expect(justAfter.hour, 4);
      expect(justAfter.minute, 0);
    });

    test('fall-back: 00:59Z is +3, 01:00Z drops to +2 (04:00→03:00)', () {
      final justBefore = toBeauticaTime(DateTime.utc(2026, 10, 25, 0, 59));
      final justAfter = toBeauticaTime(DateTime.utc(2026, 10, 25, 1));

      // Before the switch: still EEST (+3) → 03:59 local.
      expect(justBefore.timeZoneOffset, const Duration(hours: 3));
      expect(justBefore.hour, 3);
      expect(justBefore.minute, 59);

      // After the switch: EET (+2); Kyiv clocks drop 04:00 → 03:00.
      expect(justAfter.timeZoneOffset, const Duration(hours: 2));
      expect(justAfter.hour, 3);
      expect(justAfter.minute, 0);
    });
  });
}
