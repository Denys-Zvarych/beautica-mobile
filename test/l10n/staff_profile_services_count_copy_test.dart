// Phase 318, D3 — copy pin for `app_uk.arb#staffProfileServicesCount`, the
// trailing value of the «Послуги» SettingsRow on SalonStaffProfileScreen.
//
// ARB keys are NOT ledger-guarded (`project_mobile_cardinality_ledgers`,
// falsified 2026-09-05) — an unpinned key is an unguarded key. Mirrors the
// pumping recipe `plurals_test.dart` uses for `calendarBookingsForDay`.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Ukrainian staffProfileServicesCount picks the right form', (
    WidgetTester tester,
  ) async {
    late AppLocalizations l10n;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('uk', 'UA'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (ctx) {
            l10n = AppLocalizations.of(ctx);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    // `many` — 0 mod 10 == 0 → "послуг".
    expect(l10n.staffProfileServicesCount(0), '0 послуг');
    // `one` — 1 mod 10 == 1 and 1 mod 100 != 11 → "послуга".
    expect(l10n.staffProfileServicesCount(1), '1 послуга');
    // `few` — 2..4 mod 10 (not 12..14) → "послуги".
    expect(l10n.staffProfileServicesCount(3), '3 послуги');
    // `many` — 5..20 mod 100 → "послуг".
    expect(l10n.staffProfileServicesCount(5), '5 послуг');
    // `one` again — 21 mod 10 == 1, 21 mod 100 != 11 → "послуга".
    expect(l10n.staffProfileServicesCount(21), '21 послуга');

    // 2026-09-13 audit (M14) — the two EXCEPTION cases the comments above
    // name but never exercised. Both are `many`, and both are the forms a
    // regression would break FIRST: a naive `n % 10` rule (the shape the
    // comments describe) returns `one` for 11 and `few` for 12..14.
    //
    // `many` — 11 mod 10 == 1 BUT 11 mod 100 == 11 → "послуг", not "послуга".
    expect(l10n.staffProfileServicesCount(11), '11 послуг');
    // `many` — 12..14 mod 100 → "послуг", not the `few` "послуги" that
    // 2..4 mod 10 would otherwise select.
    expect(l10n.staffProfileServicesCount(12), '12 послуг');
    expect(l10n.staffProfileServicesCount(13), '13 послуг');
    expect(l10n.staffProfileServicesCount(14), '14 послуг');
    // The boundary immediately after the exception window is `few` again.
    expect(l10n.staffProfileServicesCount(22), '22 послуги');
  });

  // 2026-09-13 audit (M15) — `staffProfileServicesEmpty` is the SIBLING value
  // on the same `ManagementActionCard` (an empty catalogue renders it instead
  // of `staffProfileServicesCount(0)`), it is new on this branch, and ARB keys
  // are NOT ledger-guarded — so without this it was an unguarded key. Pinned
  // against hard-coded literals, never against the getter under test.
  testWidgets('staffProfileServicesEmpty is pinned in uk and en', (
    WidgetTester tester,
  ) async {
    late AppLocalizations uk;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('uk', 'UA'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (ctx) {
            uk = AppLocalizations.of(ctx);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(uk.staffProfileServicesEmpty, 'Ще немає');
    // The empty copy must never read as a COUNT — that is the whole reason
    // D3 gave it its own key instead of rendering the plural with 0.
    expect(
      uk.staffProfileServicesEmpty,
      isNot(uk.staffProfileServicesCount(0)),
    );

    late AppLocalizations en;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (ctx) {
            en = AppLocalizations.of(ctx);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(en.staffProfileServicesEmpty, 'None yet');
    expect(
      en.staffProfileServicesEmpty,
      isNot(en.staffProfileServicesCount(0)),
    );
  });

  testWidgets('English staffProfileServicesCount picks =1/other', (
    WidgetTester tester,
  ) async {
    late AppLocalizations l10n;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (ctx) {
            l10n = AppLocalizations.of(ctx);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(l10n.staffProfileServicesCount(0), '0 services');
    expect(l10n.staffProfileServicesCount(1), '1 service');
    expect(l10n.staffProfileServicesCount(3), '3 services');
  });

  // ── AUDIT cycle-3 (C3) — the four VelvetBottomNavBar tile labels ─────────
  //
  // `masterNavTabServices` / `…Bookings` / `…Schedule` / `…Profile` are the
  // only copy on the master surface's bottom bar. They had ZERO references in
  // `test/` or `integration_test/`: an auditor swapped `_servicesLabel` and
  // `_profileLabel` in `lib/shared/widgets/velvet_bottom_nav_bar.dart` and,
  // apart from 15 goldens, the entire suite stayed green — `test/shared/` and
  // `test/features/master/` included.
  //
  // Goldens being the ONLY guard is not a guard at all here: a routine
  // `--update-goldens` after any design change silently absorbs a wrong or
  // drifted nav label, and a regenerated golden is self-referential
  // (`feedback_golden_not_acceptance`). ARB keys are not ledger-guarded
  // either (`project_mobile_cardinality_ledgers`, falsified 2026-09-05), so
  // an unpinned key is simply an unguarded one.
  //
  // Pinned against hard-coded literals in BOTH locales — never against
  // another getter, which a swap would satisfy just as well.
  group('masterNavTab* tile labels are pinned', () {
    Future<AppLocalizations> localizationsFor(
      WidgetTester tester,
      Locale locale,
    ) async {
      late AppLocalizations l10n;
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (ctx) {
              l10n = AppLocalizations.of(ctx);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return l10n;
    }

    testWidgets('Ukrainian — the four tiles read left-to-right as designed', (
      WidgetTester tester,
    ) async {
      final uk = await localizationsFor(tester, const Locale('uk', 'UA'));

      // Tile order is the bar's own 0..3; the literals are the approved copy.
      expect(uk.masterNavTabServices, 'Послуги');
      expect(uk.masterNavTabBookings, 'Записи');
      expect(uk.masterNavTabSchedule, 'Графік');
      expect(uk.masterNavTabProfile, 'Профіль');
    });

    testWidgets('English — the four tiles carry their EN copy', (
      WidgetTester tester,
    ) async {
      final en = await localizationsFor(tester, const Locale('en'));

      expect(en.masterNavTabServices, 'Services');
      expect(en.masterNavTabBookings, 'Bookings');
      expect(en.masterNavTabSchedule, 'Schedule');
      expect(en.masterNavTabProfile, 'Profile');
    });

    // Anti-vacuity for the two rows above: four literal equalities would all
    // still hold if two of the ARB VALUES were identical to each other, which
    // is its own shipping bug (two tiles that read the same). Pinned
    // separately so the failure message names the collision rather than an
    // arbitrary one of the four literals.
    testWidgets('the four tile labels are pairwise distinct in both locales', (
      WidgetTester tester,
    ) async {
      for (final Locale locale in const <Locale>[
        Locale('uk', 'UA'),
        Locale('en'),
      ]) {
        final l10n = await localizationsFor(tester, locale);
        final labels = <String>[
          l10n.masterNavTabServices,
          l10n.masterNavTabBookings,
          l10n.masterNavTabSchedule,
          l10n.masterNavTabProfile,
        ];
        expect(
          labels.toSet(),
          hasLength(4),
          reason:
              'two bottom-nav tiles would render the same label in '
              '$locale: $labels',
        );
      }
    });
  });
}
