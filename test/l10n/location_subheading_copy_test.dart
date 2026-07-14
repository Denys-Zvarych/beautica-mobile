// Regression — pins the EXACT `locationSubheading` copy in both locales.
//
// The value of `locationSubheading` was deliberately revised (uk + en) and the
// user cared about the precise wording. The screen render test in
// `test/features/home/presentation/client_location_edit_screen_test.dart`
// asserts the subheading through the l10n getter (value-agnostic by design — it
// guards that the CLIENT screen WIRES the key, not a specific wording). That
// test would happily pass on an accidental revert or a re-worded string.
//
// This file closes that gap: it loads `AppLocalizations` for each supported
// locale and asserts `locationSubheading` resolves to the exact approved text,
// so any silent revision to the ARB values fails CI. If the copy is
// intentionally changed again, THIS test is the single place to update.
//
// Pattern mirrors `plurals_test.dart` / `on_generate_title_test.dart`: pump a
// bare `MaterialApp` forced to the target locale, grab the generated
// `AppLocalizations` instance via a `Builder`, then assert the string.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The approved copy — the single source of truth these assertions pin against.
const String _ukLocationSubheading =
    'Оберіть свою локацію, щоб ми могли показувати Вам майстрів у цьому місті';
const String _enLocationSubheading =
    'Choose your location so we can show you masters in this city';

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
    'uk locale resolves locationSubheading to the exact approved copy',
    (WidgetTester tester) async {
      final AppLocalizations l10n = await _loadL10n(
        tester,
        const Locale('uk', 'UA'),
      );

      expect(
        l10n.locationSubheading,
        _ukLocationSubheading,
        reason:
            'the Ukrainian location subheading copy is deliberate — a silent '
            'revert or re-word must fail this test',
      );
    },
  );

  testWidgets(
    'en locale resolves locationSubheading to the exact approved copy',
    (WidgetTester tester) async {
      final AppLocalizations l10n = await _loadL10n(tester, const Locale('en'));

      expect(
        l10n.locationSubheading,
        _enLocationSubheading,
        reason:
            'the English location subheading copy must stay in parity-lock with '
            'the deliberate wording — a silent revert or re-word must fail here',
      );
    },
  );
}
