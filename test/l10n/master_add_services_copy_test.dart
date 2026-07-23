// Regression — pins the EXACT `masterAddServices` copy in both locales.
//
// `masterAddServices` is the label of the master-home zero-services empty-state
// CTA (Key('btn-master-add-services') in master_profile_screen.dart). The
// widget test `master_profile_screen_test.dart` (group 13, test C) asserts the
// CTA renders its l10n value (value-agnostic by design — it guards the WIRING,
// not the wording), so an accidental re-word would pass there.
//
// This file closes that gap: it loads `AppLocalizations` for each supported
// locale and asserts `masterAddServices` resolves to the exact approved text,
// so any silent revision to the ARB values fails CI. If the copy is
// intentionally changed, THIS test is the single place to update.
//
// Pattern mirrors `register_done_desc_salon_owner_copy_test.dart`.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The approved copy — the single source of truth these assertions pin against.
const String _ukAddServices = 'Додати послуги';
const String _enAddServices = 'Add services';

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
  testWidgets(
    'uk locale resolves masterAddServices to the exact approved copy',
    (WidgetTester tester) async {
      final AppLocalizations l10n = await _loadL10n(
        tester,
        const Locale('uk', 'UA'),
      );

      expect(
        l10n.masterAddServices,
        _ukAddServices,
        reason:
            'the Ukrainian master-home add-services CTA label is deliberate — '
            'a silent revert or re-word must fail this test',
      );
    },
  );

  testWidgets(
    'en locale resolves masterAddServices to the exact approved copy',
    (WidgetTester tester) async {
      final AppLocalizations l10n = await _loadL10n(tester, const Locale('en'));

      expect(
        l10n.masterAddServices,
        _enAddServices,
        reason:
            'the English master-home add-services CTA label must stay in '
            'parity-lock with the deliberate wording — a silent revert or '
            're-word must fail here',
      );
    },
  );
}
