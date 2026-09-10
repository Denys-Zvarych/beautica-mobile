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
}
