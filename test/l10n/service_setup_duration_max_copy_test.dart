// Regression — pins the EXACT `serviceSetupDurationMax` copy in both locales.
//
// `serviceSetupDurationMax` is the message shown on a service-setup row when a
// duration exceeds the backend maximum (480 min / 8 h) — surfaced either by the
// client-side `> 480` guard OR mapped back from a backend
// `items[i].durationMinutes` per-field 400. The widget regression
// (`service_setup_screen_test.dart`, group "per-field 400 maps to the offending
// submitted row") asserts the row renders `l10n.serviceSetupDurationMax`
// (value-agnostic by design — it guards the WIRING, not the wording), so an
// accidental re-word would pass there.
//
// This file closes that gap: it loads `AppLocalizations` for each supported
// locale and asserts `serviceSetupDurationMax` resolves to the exact approved
// text, so any silent revision to the ARB values fails CI. If the copy is
// intentionally changed, THIS test is the single place to update.
//
// Pattern mirrors `master_add_services_copy_test.dart`.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The approved copy — the single source of truth these assertions pin against.
const String _ukDurationMax = 'Тривалість не може перевищувати 480 хв (8 год)';
const String _enDurationMax = 'Duration must be at most 480 minutes (8 hours)';

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
    'uk locale resolves serviceSetupDurationMax to the exact approved copy',
    (WidgetTester tester) async {
      final AppLocalizations l10n = await _loadL10n(
        tester,
        const Locale('uk', 'UA'),
      );

      expect(
        l10n.serviceSetupDurationMax,
        _ukDurationMax,
        reason:
            'the Ukrainian service-setup duration-max message is deliberate — '
            'a silent revert or re-word must fail this test',
      );
    },
  );

  testWidgets(
    'en locale resolves serviceSetupDurationMax to the exact approved copy',
    (WidgetTester tester) async {
      final AppLocalizations l10n = await _loadL10n(tester, const Locale('en'));

      expect(
        l10n.serviceSetupDurationMax,
        _enDurationMax,
        reason:
            'the English service-setup duration-max message must stay in '
            'parity-lock with the deliberate wording — a silent revert or '
            're-word must fail here',
      );
    },
  );
}
