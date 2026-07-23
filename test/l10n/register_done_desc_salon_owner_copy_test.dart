// Regression — pins the EXACT `registerDoneDescSalonOwner` copy in both locales.
//
// The SALON_OWNER done-screen description was deliberately authored (uk + en)
// and the user cared about the precise wording. The screen render test in
// `test/features/auth/presentation/done_screen_test.dart` (Test E) asserts the
// description through the l10n getter (value-agnostic by design — it guards that
// the salonOwner branch WIRES the new key and diverges from the client copy, not
// a specific wording). That test would happily pass on an accidental re-word.
//
// This file closes that gap: it loads `AppLocalizations` for each supported
// locale and asserts `registerDoneDescSalonOwner` resolves to the exact approved
// text, so any silent revision to the ARB values fails CI. If the copy is
// intentionally changed again, THIS test is the single place to update.
//
// Pattern mirrors `location_subheading_copy_test.dart`: pump a bare
// `MaterialApp` forced to the target locale, grab the generated
// `AppLocalizations` instance via a `Builder`, then assert the string.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The approved copy — the single source of truth these assertions pin against.
const String _ukSalonOwnerDesc =
    'Тепер Ви можете оформити свій профіль, додати майстрів та послуги салону. '
    'Активно розвивати свій бізнес, а ми створимо для цього усі необхідні умови.';
const String _enSalonOwnerDesc =
    'Now you can set up your profile, add masters and salon services. '
    "Actively grow your business — we'll create all the conditions you need for it.";

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
    'uk locale resolves registerDoneDescSalonOwner to the exact approved copy',
    (WidgetTester tester) async {
      final AppLocalizations l10n = await _loadL10n(
        tester,
        const Locale('uk', 'UA'),
      );

      expect(
        l10n.registerDoneDescSalonOwner,
        _ukSalonOwnerDesc,
        reason:
            'the Ukrainian salon-owner done-screen description is deliberate — '
            'a silent revert or re-word must fail this test',
      );
    },
  );

  testWidgets(
    'en locale resolves registerDoneDescSalonOwner to the exact approved copy',
    (WidgetTester tester) async {
      final AppLocalizations l10n = await _loadL10n(tester, const Locale('en'));

      expect(
        l10n.registerDoneDescSalonOwner,
        _enSalonOwnerDesc,
        reason:
            'the English salon-owner done-screen description must stay in '
            'parity-lock with the deliberate wording — a silent revert or '
            're-word must fail here',
      );
    },
  );
}
