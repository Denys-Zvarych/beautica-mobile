// Phase 319, D2 — pins `deleteServiceBlockedBodyNoCount` in both
// `app_uk.arb` and `app_en.arb`.
//
// ARB keys are NOT ledger-guarded (`project_mobile_cardinality_ledgers`,
// falsified 2026-09-05) — an unpinned key is an unguarded key. Mirrors the
// pumping recipe `remove_master_dialog_copy_test.dart` uses (load
// AppLocalizations per locale, pin the resolved template against a
// hard-coded literal — never the same getter under test, which can never
// fail no matter what the ARB says).

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AppLocalizations> _loadL10n(WidgetTester tester, Locale locale) async {
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

void main() {
  testWidgets('deleteServiceBlockedBodyNoCount is pinned in uk and en', (
    WidgetTester tester,
  ) async {
    final AppLocalizations uk = await _loadL10n(tester, const Locale('uk'));
    expect(
      uk.deleteServiceBlockedBodyNoCount,
      'Ця послуга має майбутні бронювання. Спочатку скасуйте їх.',
    );

    final AppLocalizations en = await _loadL10n(tester, const Locale('en'));
    expect(
      en.deleteServiceBlockedBodyNoCount,
      'This service has future bookings. Cancel them first.',
    );
  });

  testWidgets(
    'deleteServiceBlockedBodyNoCount never states a count — it must differ '
    'from deleteServiceBlockedBody rendered with any count',
    (WidgetTester tester) async {
      final AppLocalizations uk = await _loadL10n(tester, const Locale('uk'));
      final String noCount = uk.deleteServiceBlockedBodyNoCount;
      expect(noCount, isNot(uk.deleteServiceBlockedBody(0)));
      expect(noCount, isNot(uk.deleteServiceBlockedBody(1)));
      expect(noCount, isNot(uk.deleteServiceBlockedBody(3)));
    },
  );
}
