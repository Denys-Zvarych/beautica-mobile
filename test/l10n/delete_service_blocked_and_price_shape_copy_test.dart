// Phase 319, D2/D4 — pins `deleteServiceBlockedBodyNoCount` and
// `servicePriceShapeMismatchBody` in both `app_uk.arb` and `app_en.arb`.
//
// ARB keys are NOT ledger-guarded (`project_mobile_cardinality_ledgers`,
// falsified 2026-09-05) — an unpinned key is an unguarded key. Mirrors the
// pumping recipe `remove_master_dialog_copy_test.dart` uses (load
// AppLocalizations per locale, pin the resolved template against a
// hard-coded literal — never the same getter under test, which can never
// fail no matter what the ARB says).
//
// `servicePriceShapeMismatchBody` also pins that currency is always ₴, never
// «грн» (project_currency_symbol_hryvnia), and that the RANGE/FIXED ICU
// `select` branches actually differ.

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

  testWidgets(
    'servicePriceShapeMismatchBody RANGE (isRange=true) is pinned in uk and '
    'en, names both bounds, and uses ₴ never «грн»',
    (WidgetTester tester) async {
      final AppLocalizations uk = await _loadL10n(tester, const Locale('uk'));
      final String ukRange = uk.servicePriceShapeMismatchBody(
        'true',
        '400',
        '900',
      );
      expect(
        ukRange,
        'У салоні ця послуга вже коштує від 400 до 900 ₴. Виберіть такий '
        'самий формат ціни.',
      );
      expect(ukRange, isNot(contains('грн')));

      final AppLocalizations en = await _loadL10n(tester, const Locale('en'));
      final String enRange = en.servicePriceShapeMismatchBody(
        'true',
        '400',
        '900',
      );
      expect(
        enRange,
        'In this salon, this service already costs from 400 to 900 ₴. '
        'Choose the same price format.',
      );
    },
  );

  testWidgets(
    'servicePriceShapeMismatchBody FIXED (isRange=false, the "other" ICU '
    'select branch) names a single amount and DIFFERS from the RANGE branch',
    (WidgetTester tester) async {
      final AppLocalizations uk = await _loadL10n(tester, const Locale('uk'));
      final String ukFixed = uk.servicePriceShapeMismatchBody(
        'false',
        '400',
        '400',
      );
      expect(
        ukFixed,
        'У салоні ця послуга вже коштує 400 ₴. Виберіть такий самий формат '
        'ціни.',
      );
      expect(ukFixed, isNot(contains('900')));
      expect(
        ukFixed,
        isNot(uk.servicePriceShapeMismatchBody('true', '400', '900')),
        reason:
            'the FIXED and RANGE ICU select branches must render '
            'differently, or the isRange argument bought nothing',
      );

      final AppLocalizations en = await _loadL10n(tester, const Locale('en'));
      final String enFixed = en.servicePriceShapeMismatchBody(
        'false',
        '400',
        '400',
      );
      expect(
        enFixed,
        'In this salon, this service already costs 400 ₴. Choose the same '
        'price format.',
      );
    },
  );
}
