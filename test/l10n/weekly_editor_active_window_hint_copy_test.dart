// Regression — pins the EXACT `weeklyEditorActiveWindowHint` copy in both locales.
//
// `weeklyEditorActiveWindowHint` is the helper line rendered under the
// active-window card on the weekly-template editor
// (`weekly_template_editor_screen.dart:1189`, Phase 15.5). Its wording was
// deliberately reworded (uk + en) — the key was unchanged, so no test that
// keys off the identifier would notice a silent revert to the old sentence.
//
// No existing widget/integration test asserts this hint renders at all (not
// even value-agnostically), so nothing currently guards the string. This file
// closes that gap: it loads `AppLocalizations` for each supported locale and
// asserts `weeklyEditorActiveWindowHint` resolves to the exact approved text,
// so any silent revision to the ARB values fails CI. If the copy is
// intentionally changed, THIS test is the single place to update.
//
// Pattern mirrors `service_setup_duration_max_copy_test.dart`.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The approved copy — the single source of truth these assertions pin against.
const String _ukHint =
    'Ваш графік автоматично діятиме на період, який Ви оберете. '
    'За потреби - Ви зможете вносити зміни.';
const String _enHint =
    'Your schedule will apply automatically for the period you choose. '
    'You can make changes whenever you need to.';

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
    'uk locale resolves weeklyEditorActiveWindowHint to the exact approved copy',
    (WidgetTester tester) async {
      final AppLocalizations l10n = await _loadL10n(
        tester,
        const Locale('uk', 'UA'),
      );

      expect(
        l10n.weeklyEditorActiveWindowHint,
        _ukHint,
        reason:
            'the Ukrainian active-window hint is deliberate — a silent revert '
            'or re-word must fail this test',
      );
    },
  );

  testWidgets(
    'en locale resolves weeklyEditorActiveWindowHint to the exact approved copy',
    (WidgetTester tester) async {
      final AppLocalizations l10n = await _loadL10n(tester, const Locale('en'));

      expect(
        l10n.weeklyEditorActiveWindowHint,
        _enHint,
        reason:
            'the English active-window hint must stay in parity-lock with the '
            'deliberate wording — a silent revert or re-word must fail here',
      );
    },
  );
}
