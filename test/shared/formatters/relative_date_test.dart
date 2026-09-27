// mobile-qa (2026-08-02, backlog :226 audit) — the missing pinning test for
// `shared/formatters/relative_date.dart`.
//
// WHY THIS FILE EXISTS
// ---------------------
// `formatRelativeDate` had ZERO test coverage before this file, despite being
// migrated from `.toLocal()` (the device's own zone) to `toBeauticaTime`
// (Kyiv-anchored) as part of the Kyiv-day-authority track (backlog :226) —
// see that file's own header. Every review-tab screen renders through this
// formatter, so an un-pinned regression back to `.toLocal()` would silently
// reintroduce a device-zone-dependent "Сьогодні"/"Вчора"/"N днів тому" label
// with no test anywhere failing.
//
// Every fixture is anchored with `DateTime.utc(...)` — never a bare
// `DateTime(...)` — per `scripts/forbid_host_local_instant_anchor.sh`.
//
// THE ONE DELIBERATE EXCEPTION (Phase 284): the three host-zone helpers at
// the bottom of this file — `_skipUnlessHostShifts`,
// `_hostMidnightOffsetShifts` and `_hostZoneLabel` — DO build bare host-local
// `DateTime(y, m, d)` values, because interrogating the HOST zone is
// precisely their job: they ask whether this machine's UTC offset moves
// between two host-local midnights, which decides whether the two
// DST-straddle cases below can discriminate at all, and name the zone in the
// skip/failure message when it does not. They read `.timeZoneOffset` and
// `.timeZoneName` only, never `.difference`, so they never perform the
// operation under test. No fixture instant is derived from them.

import 'package:beautica_mobile/l10n/app_localizations_uk.dart';
import 'package:beautica_mobile/shared/formatters/relative_date.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  initBeauticaTimeZones();

  final AppLocalizationsUk l10n = AppLocalizationsUk();

  group('formatRelativeDate — bucket boundaries', () {
    test('same instant → "Сьогодні"', () {
      final DateTime now = DateTime.utc(2026, 6, 15, 12);
      expect(formatRelativeDate(l10n, now, now: now), l10n.relativeDateToday);
    });

    test('exactly 1 Kyiv calendar day earlier → "Вчора"', () {
      final DateTime now = DateTime.utc(2026, 6, 15, 12);
      final DateTime yesterday = DateTime.utc(2026, 6, 14, 12);
      expect(
        formatRelativeDate(l10n, yesterday, now: now),
        l10n.relativeDateYesterday,
      );
    });

    test('5 days earlier → "N днів тому"', () {
      final DateTime now = DateTime.utc(2026, 6, 15, 12);
      final DateTime then = DateTime.utc(2026, 6, 10, 12);
      expect(
        formatRelativeDate(l10n, then, now: now),
        l10n.relativeDateDaysAgo(5),
      );
    });

    test('2 weeks earlier → "N тижнів тому"', () {
      final DateTime now = DateTime.utc(2026, 6, 15, 12);
      final DateTime then = DateTime.utc(2026, 6, 1, 12);
      expect(
        formatRelativeDate(l10n, then, now: now),
        l10n.relativeDateWeeksAgo(2),
      );
    });

    test('2 months earlier → "N місяців тому"', () {
      final DateTime now = DateTime.utc(2026, 6, 15, 12);
      final DateTime then = DateTime.utc(2026, 4, 15, 12);
      final int days = now.difference(then).inDays;
      expect(
        formatRelativeDate(l10n, then, now: now),
        l10n.relativeDateMonthsAgo(days ~/ 30),
      );
    });

    test('2 years earlier → "N років тому"', () {
      final DateTime now = DateTime.utc(2026, 6, 15, 12);
      final DateTime then = DateTime.utc(2024, 6, 15, 12);
      final int days = now.difference(then).inDays;
      expect(
        formatRelativeDate(l10n, then, now: now),
        l10n.relativeDateYearsAgo(days ~/ 365),
      );
    });

    test('a FUTURE dateTime (negative days) clamps to "Сьогодні", never a '
        'negative bucket', () {
      final DateTime now = DateTime.utc(2026, 6, 15, 12);
      final DateTime future = DateTime.utc(2026, 6, 20, 12);
      expect(
        formatRelativeDate(l10n, future, now: now),
        l10n.relativeDateToday,
      );
    });
  });

  // ── Kyiv-anchored bucketing — the regression this file exists to close ────
  group('formatRelativeDate is Kyiv-anchored, not UTC/device-day (backlog '
      ':226)', () {
    test('a review straddling the Kyiv midnight boundary (but on the SAME '
        'UTC calendar day) buckets as "Вчора", not "Сьогодні"', () {
      // `then`  = 2026-08-01T20:00Z → Kyiv (EEST, +3) = 2026-08-01 23:00 →
      //           Kyiv day = Aug 1.
      // `now`   = 2026-08-01T22:30Z → Kyiv (EEST, +3) = 2026-08-02 01:30 →
      //           Kyiv day = Aug 2 (already rolled over).
      // Both instants fall on the SAME UTC calendar day (Aug 1) — a formatter
      // that read `.toLocal()` on a UTC-TZ host (CI's default, and the exact
      // pre-fix behaviour) would compute todayUTC == thenUTC == Aug 1 and
      // wrongly report "Сьогодні". The correct Kyiv-anchored reading is ONE
      // full Kyiv calendar day apart.
      final DateTime then = DateTime.utc(2026, 8, 1, 20, 0);
      final DateTime now = DateTime.utc(2026, 8, 1, 22, 30);

      final String result = formatRelativeDate(l10n, then, now: now);

      expect(
        result,
        l10n.relativeDateYesterday,
        reason:
            'then and now are on different KYIV calendar days (Aug 1 vs '
            'Aug 2) even though both share the same UTC calendar date — a '
            'device/UTC-day bucketing would wrongly collapse them to "today"',
      );
      expect(
        result,
        isNot(l10n.relativeDateToday),
        reason:
            'the exact wrong answer a reintroduced `.toLocal()` (device/UTC '
            'day) regression would produce on a UTC-TZ host',
      );
    });

    test('the mirrored case just BEFORE the Kyiv boundary — same Kyiv day → '
        '"Сьогодні", proving the boundary itself (not merely "yesterday '
        'ever fires") is what the previous case pins', () {
      // Both now Kyiv day = Aug 2 this time: `then` nudged 3h later so it
      // also crosses into Aug 2 Kyiv.
      final DateTime then = DateTime.utc(2026, 8, 1, 22, 0); // Kyiv 01:00 Aug2
      final DateTime now = DateTime.utc(2026, 8, 1, 22, 30); // Kyiv 01:30 Aug2

      expect(formatRelativeDate(l10n, then, now: now), l10n.relativeDateToday);
    });
  });

  // ── Phase 284 — DST-safe day arithmetic ──────────────────────────────────
  //
  // THE USUAL `TZ=UTC` RULE IS INVERTED FOR THIS DEFECT. UTC observes no DST,
  // so the bug these cases pin is INVISIBLE under `TZ=UTC` — the standard
  // "pin TZ=UTC to surface timezone bugs" guidance would miss it entirely.
  // The dev VM's own `Europe/Kyiv` is, for once, the DISCRIMINATING
  // environment. The two straddle cases below therefore carry an explicit
  // `skip:` keyed on whether the HOST zone actually shifts its offset across
  // the fixture window (see [_hostMidnightOffsetShifts]), rather than
  // pretending to test something they cannot: a green run under `TZ=UTC`
  // would otherwise be indistinguishable from a passing gate, which is the
  // exact failure mode `scripts/verify_guards.sh` exists to refuse.
  // Reconcile PASSED + SKIPPED, never passed alone.
  group('formatRelativeDate counts KYIV CALENDAR days, not elapsed host '
      'wall-clock hours (Phase 284)', () {
    // Europe/Kyiv 2026: spring forward on Sun 29 Mar (03:00 EET → 04:00
    // EEST), fall back on Sun 25 Oct (04:00 EEST → 03:00 EET). Host-local
    // MIDNIGHT offsets, which is what the buggy subtraction used:
    //   Mar 29 → +02:00   Mar 30 → +03:00   (23 h "day", truncates to 0)
    //   Oct 25 → +03:00   Oct 26 → +02:00   (25 h "day", truncates to 1)
    test(
      'should_sayYesterday_when_theIntervalSpansTheKyivSpringForward',
      () {
        // `then` = 2026-03-29T12:00Z → Kyiv 15:00 → Kyiv day Mar 29.
        // `now`  = 2026-03-30T12:00Z → Kyiv 15:00 → Kyiv day Mar 30.
        // Pre-fix the two host-local midnights sat 23 h apart, `.inDays`
        // truncated to 0, and this rendered «Сьогодні» — the live defect.
        final DateTime then = DateTime.utc(2026, 3, 29, 12);
        final DateTime now = DateTime.utc(2026, 3, 30, 12);

        expect(
          formatRelativeDate(l10n, then, now: now),
          l10n.relativeDateYesterday,
          reason:
              'one Kyiv calendar day apart — the host zone crossing a DST '
              'transition between the two midnights must not shorten the count',
        );
      },
      skip: _skipUnlessHostShifts(2026, 3, 29, 2026, 3, 30),
    );

    test(
      'should_sayYesterday_when_theIntervalSpansTheKyivFallBack',
      () {
        // The mirror image: a 25 h "day". `.inDays` truncates 25 h to 1, so
        // this case passed BEFORE the fix too — it is here to catch a fix that
        // OVER-corrects (e.g. rounding, or adding a blanket +1).
        final DateTime then = DateTime.utc(2026, 10, 25, 12);
        final DateTime now = DateTime.utc(2026, 10, 26, 12);

        expect(
          formatRelativeDate(l10n, then, now: now),
          l10n.relativeDateYesterday,
          reason:
              'fall-back is benign for the OLD arithmetic; a fix that rounds '
              'instead of re-anchoring would break exactly here',
        );
      },
      skip: _skipUnlessHostShifts(2026, 10, 25, 2026, 10, 26),
    );

    test('should_countExactDays_when_theIntervalSpansASpringForward', () {
      // Kyiv day Mar 26 → Kyiv day Mar 31 = 5 days, straddling the 29th.
      // Pre-fix: 4 d 23 h → «4 дні тому».
      final DateTime then = DateTime.utc(2026, 3, 26, 12);
      final DateTime now = DateTime.utc(2026, 3, 31, 12);

      expect(
        formatRelativeDate(l10n, then, now: now),
        l10n.relativeDateDaysAgo(5),
      );
    });

    test('should_bucketAsOneWeek_when_theSeventhDaySpansASpringForward', () {
      // The day-7 bucket edge — where the off-by-one is loudest, because it
      // does not merely change a number, it changes which l10n key fires.
      // Kyiv day Mar 24 → Kyiv day Mar 31 = 7 days. Pre-fix: 6 → «6 днів
      // тому» instead of «1 тиждень тому».
      final DateTime then = DateTime.utc(2026, 3, 24, 12);
      final DateTime now = DateTime.utc(2026, 3, 31, 12);

      expect(
        formatRelativeDate(l10n, then, now: now),
        l10n.relativeDateWeeksAgo(1),
      );
      expect(
        formatRelativeDate(l10n, then, now: now),
        isNot(l10n.relativeDateDaysAgo(6)),
        reason: 'the exact wrong bucket the truncating subtraction produced',
      );
    });

    test('should_returnTheSameDelta_when_theHostZoneDiffers', () {
      // NEVER SKIPPED, deliberately — this is the case that still
      // discriminates under `TZ=UTC` and `TZ=America/New_York`, where the two
      // straddle cases above cannot. The host zone is not an input to a Kyiv
      // calendar-day count, so every row below must hold on every host.
      final List<(DateTime, DateTime, String)> cases =
          <(DateTime, DateTime, String)>[
            // across the Kyiv spring forward
            (
              DateTime.utc(2026, 3, 29, 12),
              DateTime.utc(2026, 3, 30, 12),
              l10n.relativeDateYesterday,
            ),
            // across the Kyiv fall back
            (
              DateTime.utc(2026, 10, 25, 12),
              DateTime.utc(2026, 10, 26, 12),
              l10n.relativeDateYesterday,
            ),
            // across the US spring forward (2026-03-08) — a transition
            // Europe/Kyiv does NOT observe, so an America/New_York host is
            // the only one whose arithmetic this row could ever have bent
            (
              DateTime.utc(2026, 3, 7, 12),
              DateTime.utc(2026, 3, 9, 12),
              l10n.relativeDateDaysAgo(2),
            ),
            // a plain interval with no transition anywhere near it
            (
              DateTime.utc(2026, 6, 10, 12),
              DateTime.utc(2026, 6, 15, 12),
              l10n.relativeDateDaysAgo(5),
            ),
          ];

      for (final (DateTime then, DateTime now, String expected) in cases) {
        expect(
          formatRelativeDate(l10n, then, now: now),
          expected,
          reason:
              '$then → $now must read identically on every host zone; this '
              'run resolves them under ${_hostZoneLabel(2026, 6, 15)}',
        );
      }
    });

    test('should_preserveKyivMidnightStraddle_when_theFixIsApplied', () {
      // Belt-and-braces over the pre-existing backlog :226 cases above: the
      // Phase 284 fix must not walk Kyiv anchoring back toward `.toLocal()`
      // while making the day count DST-safe. Both instants share a UTC
      // calendar day; only Kyiv separates them.
      expect(
        formatRelativeDate(
          l10n,
          DateTime.utc(2026, 8, 1, 20),
          now: DateTime.utc(2026, 8, 1, 22, 30),
        ),
        l10n.relativeDateYesterday,
      );
      expect(
        formatRelativeDate(
          l10n,
          DateTime.utc(2026, 8, 1, 22),
          now: DateTime.utc(2026, 8, 1, 22, 30),
        ),
        l10n.relativeDateToday,
      );
    });
  });
}

/// `null` (run the test) when the HOST process zone's UTC offset differs
/// between host-local midnight on the two named days; a skip REASON otherwise.
///
/// The pre-Phase-284 formatter built both of its operands as host-local
/// midnights, so the defect could only ever manifest on a host whose offset
/// actually moves between them. On a host where it does not (`TZ=UTC` always;
/// `TZ=America/New_York` for the Kyiv transition dates, whose own transitions
/// fall on 8 March and 1 November), the test would pass no matter what the
/// formatter did — a green that proves nothing. Skipping says so out loud
/// rather than banking a vacuous pass.
String? _skipUnlessHostShifts(int y1, int m1, int d1, int y2, int m2, int d2) {
  final DateTime aDay = DateTime(y1, m1, d1);
  final DateTime bDay = DateTime(y2, m2, d2);
  if (_hostMidnightOffsetShifts(aDay, bDay)) return null;
  return 'non-discriminating on this host: it holds one offset '
      '(${aDay.timeZoneName}) across $y1-$m1-$d1 → $y2-$m2-$d2, so the DST '
      'truncation this case pins cannot occur here. Run under '
      'TZ=Europe/Kyiv.';
}

/// The host zone's name at host-local midnight on the given day — for failure
/// messages only. Same deliberate host-local exception as
/// [_hostMidnightOffsetShifts]: naming the HOST zone is the whole point, and
/// it reads `.timeZoneName` only, never `.difference`.
String _hostZoneLabel(int y, int m, int d) => DateTime(y, m, d).timeZoneName;

/// Whether the host zone reports a different UTC offset at these two
/// host-local midnights. Reads `.timeZoneOffset` only — never `.difference`,
/// which is the very operation under test.
bool _hostMidnightOffsetShifts(DateTime aDay, DateTime bDay) =>
    aDay.timeZoneOffset != bDay.timeZoneOffset;
