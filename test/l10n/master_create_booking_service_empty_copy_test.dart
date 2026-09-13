// 2026-09-13 audit (M3) — mechanical pin for the CROSS-KEY invariant
// `masterCreateBookingServiceEmptyBody` declares in prose.
//
// That key's ARB description says: "Names the services list screen by its
// `servicesTitle` label — keep the two in sync if either changes." Until this
// file, that sentence was the ENTIRE enforcement. Both keys moved on this
// branch («Мої послуги» → «Послуги») and a grep of `test/` +
// `integration_test/` for `masterCreateBookingServiceEmptyBody` returned
// nothing at all, so the next `servicesTitle` change would have drifted the
// booking wizard's empty-state copy silently — it would still read «Мої
// послуги» while the screen it points at is titled something else.
//
// ARB keys are NOT ledger-guarded (`project_mobile_cardinality_ledgers`,
// falsified 2026-09-05), so an unpinned key is an unguarded key. Mirrors the
// pumping recipe in `delete_service_blocked_copy_test.dart`: load
// AppLocalizations per locale and pin the resolved template against a
// hard-coded literal, never against the same getter under test.

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
  testWidgets('masterCreateBookingServiceEmptyBody is pinned in uk and en', (
    WidgetTester tester,
  ) async {
    final AppLocalizations uk = await _loadL10n(tester, const Locale('uk'));
    expect(
      uk.masterCreateBookingServiceEmptyBody,
      'Додайте послугу в розділі «Послуги», щоб створити запис.',
    );
    expect(
      uk.masterCreateBookingServiceEmptyTitle,
      'У вас ще немає жодної послуги',
    );

    final AppLocalizations en = await _loadL10n(tester, const Locale('en'));
    expect(
      en.masterCreateBookingServiceEmptyBody,
      'Add a service under "Services" to create a booking.',
    );
    expect(
      en.masterCreateBookingServiceEmptyTitle,
      "You don't have any services yet",
    );
  });

  testWidgets(
    'THE INVARIANT: masterCreateBookingServiceEmptyBody QUOTES servicesTitle '
    '— changing one without the other fails here, in both locales',
    (WidgetTester tester) async {
      // This is the assertion the prose-only rule was asking for. It cannot
      // pass vacuously: the substring is read from `servicesTitle` itself, so
      // renaming the services screen and forgetting the wizard copy goes RED
      // whatever either string becomes.
      final AppLocalizations uk = await _loadL10n(tester, const Locale('uk'));
      expect(
        uk.masterCreateBookingServiceEmptyBody,
        contains(uk.servicesTitle),
        reason:
            'The booking wizard empty state names the services screen. Its '
            'ARB description pins the two together; keep them in sync.',
      );

      final AppLocalizations en = await _loadL10n(tester, const Locale('en'));
      expect(
        en.masterCreateBookingServiceEmptyBody,
        contains(en.servicesTitle),
        reason:
            'The booking wizard empty state names the services screen. Its '
            'ARB description pins the two together; keep them in sync.',
      );
    },
  );
}
