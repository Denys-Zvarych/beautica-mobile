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
}
