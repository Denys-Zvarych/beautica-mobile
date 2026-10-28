// Pins the MEANING of `blockedClientsIntro` in both locales.
//
// Backend phase 398 (user-blocks enforcement) cancels the blocked client's
// future bookings automatically. The phase 426 intro line still promised the
// opposite — «Наявні записи збережуться» / "Existing bookings stay" — which
// told the provider their calendar was untouched when it was not.
//
// Asserted against HARD-CODED fragments written into THIS file, never against
// `l10n.blockedClientsIntro` itself (a self-referential pin passes for every
// value — see `remove_admin_dialog_copy_test.dart`). Shape mirrors that file:
// load [AppLocalizations] per locale and inspect the resolved string. Plain
// `contains` matchers, not `find.text` finders, so `forbid_cyrillic_finder.sh`
// does not apply.

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
  testWidgets('uk blockedClientsIntro says future bookings were cancelled, '
      'never that existing bookings stay', (WidgetTester tester) async {
    final AppLocalizations uk = await _loadL10n(tester, const Locale('uk'));

    expect(uk.blockedClientsIntro, contains('скасовано'));
    expect(uk.blockedClientsIntro, contains('майбутні записи'));
    expect(uk.blockedClientsIntro, isNot(contains('збережуться')));
  });

  testWidgets('en blockedClientsIntro says future bookings were cancelled, '
      'never that existing bookings stay', (WidgetTester tester) async {
    final AppLocalizations en = await _loadL10n(tester, const Locale('en'));

    expect(en.blockedClientsIntro, contains('cancelled'));
    expect(en.blockedClientsIntro, contains('future bookings'));
    expect(en.blockedClientsIntro, isNot(contains('stay')));
  });
}
