// Phase 13.8 — BEAUTY PASSPORT screen (PassportScreen) widget tests.
//
// Drives the whole screen with mocked providers (real ScreenProtectionManager
// override so the native FLAG_SECURE plugin is never called — its enable/disable
// paths are kDebugMode-guarded, so a real manager is safe AND lets us assert the
// acquire/release reference-count contract directly).
//
// States covered:
//   • Chrome + profile + populated card render together; the untranslated
//     "BEAUTY PASSPORT" brand literal and the «Твій б'юті-паспорт у Beautica»
//     subtitle are present.
//   • POPULATED: the 3 columns render the procedure chips, district chips, the
//     UAH budget value, and the reviews footer (count + member-since).
//   • EMPTY (Passport.empty()): the encouraging empty variant renders with its
//     CTA — NOT the populated table (no brand title, no column chips).
//   • REMOVED elements: no «+ Додати ще» anywhere; no expand_more chevron in the
//     profile location line.
//   • FLAG_SECURE: acquire() fires on mount, release() on dispose (mirrors the
//     HomeHub screen-protection lifecycle).

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/passport/application/passport_notifier.dart';
import 'package:beautica_mobile/features/passport/domain/passport.dart';
import 'package:beautica_mobile/features/passport/presentation/passport_screen.dart';
import 'package:beautica_mobile/features/passport/presentation/widgets/passport_table.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Sample data
// ---------------------------------------------------------------------------

const _sampleProfile = ClientProfileSummary(
  firstName: 'Олена',
  lastName: 'Тест',
  city: 'Львів',
  phone: '+380 97 000 00 00',
  clientRating: null,
  memberSinceYear: 2024,
);

const _populatedPassport = Passport(
  favoriteProcedures: <String>['Манікюр', 'Брови', 'Педикюр'],
  favoriteDistricts: <String>['Центр', 'Сихів', 'Франківський'],
  budget: BudgetBand(avg: 600, min: 400, max: 800),
  bookingsConsidered: 7,
  reviewsLeft: 5,
  memberSinceYear: 2024,
);

// ---------------------------------------------------------------------------
// Provider overrides
// ---------------------------------------------------------------------------

List<Object> _overrides({
  required Passport passport,
  ClientProfileSummary profile = _sampleProfile,
  ScreenProtectionManager? protection,
}) {
  return [
    screenProtectionProvider.overrideWithValue(
      protection ?? ScreenProtectionManager(),
    ),
    clientProfileProvider.overrideWith((ref) async => profile),
    passportProvider.overrideWith((ref) async => passport),
  ];
}

Future<AppLocalizations> _uk() =>
    AppLocalizations.delegate.load(const Locale('uk'));

void main() {
  group('PassportScreen — chrome + profile + populated card', () {
    testWidgets('body renders WITHOUT the top bar (bar is shell-owned)', (
      tester,
    ) async {
      // 2026-06-24 wordmark-jump hoist: the top bar (wordmark · bell · burger)
      // is mounted by ClientShell above the branch body, NOT by PassportScreen.
      // Pumped in isolation the screen therefore has NO bar; its per-branch
      // config (passport_bell_button / btn-menu-passport) is pinned in
      // test/features/shell/client_shell_top_bar_test.dart. Here we assert the
      // bar is absent and the passport body still renders.
      await tester.pumpApp(
        const PassportScreen(),
        overrides: _overrides(passport: _populatedPassport),
      );
      await tester.pumpAndSettle();

      expect(find.text('beautica'), findsNothing);
      expect(find.byKey(const Key('passport_bell_button')), findsNothing);
      expect(find.byKey(const Key('btn-menu-passport')), findsNothing);
      // The body is present (profile name from the populated state).
      expect(find.text('Олена Тест'), findsOneWidget);
    });

    testWidgets('renders the profile name, city and phone', (tester) async {
      await tester.pumpApp(
        const PassportScreen(),
        overrides: _overrides(passport: _populatedPassport),
      );
      await tester.pumpAndSettle();

      expect(find.text('Олена Тест'), findsOneWidget);
      expect(find.text('Львів'), findsOneWidget);
      expect(find.text('+380 97 000 00 00'), findsOneWidget);
    });

    testWidgets(
      'renders the untranslated "BEAUTY PASSPORT" title and Ukrainian subtitle',
      (tester) async {
        await tester.pumpApp(
          const PassportScreen(),
          overrides: _overrides(passport: _populatedPassport),
        );
        await tester.pumpAndSettle();

        // Untranslated brand literal, asserted against the exported constant so
        // the test proves it is NOT routed through l10n.
        expect(kBeautyPassportTitle, 'BEAUTY PASSPORT');
        expect(find.text('BEAUTY PASSPORT'), findsOneWidget);
        expect(find.text(kBeautyPassportSubtitle), findsOneWidget);
      },
    );
  });

  group('PassportScreen — populated state', () {
    testWidgets('renders the PassportCard with all three derived columns', (
      tester,
    ) async {
      await tester.pumpApp(
        const PassportScreen(),
        overrides: _overrides(passport: _populatedPassport),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PassportCard), findsOneWidget);

      // Procedure chips.
      expect(find.text('Манікюр'), findsOneWidget);
      expect(find.text('Брови'), findsOneWidget);
      expect(find.text('Педикюр'), findsOneWidget);

      // District chips.
      expect(find.text('Центр'), findsOneWidget);
      expect(find.text('Сихів'), findsOneWidget);
      expect(find.text('Франківський'), findsOneWidget);
    });

    testWidgets('renders the UAH budget ceiling chip from the BudgetBand', (
      tester,
    ) async {
      await tester.pumpApp(
        const PassportScreen(),
        overrides: _overrides(passport: _populatedPassport),
      );
      await tester.pumpAndSettle();

      final AppLocalizations l10n = await _uk();
      // budget.max == 800 ⇒ passportBudgetCeiling(800) e.g. «до 800 ₴».
      expect(find.text(l10n.passportBudgetCeiling(800)), findsOneWidget);
    });

    testWidgets('renders the reviews footer (count + member-since)', (
      tester,
    ) async {
      await tester.pumpApp(
        const PassportScreen(),
        overrides: _overrides(passport: _populatedPassport),
      );
      await tester.pumpAndSettle();

      final AppLocalizations l10n = await _uk();
      expect(find.text(l10n.passportReviewsLeft(5)), findsOneWidget);
      expect(find.text(l10n.passportMemberSince('2024')), findsOneWidget);
    });
  });

  group('PassportScreen — empty state', () {
    testWidgets(
      'renders the encouraging empty variant, NOT the populated table',
      (tester) async {
        await tester.pumpApp(
          const PassportScreen(),
          overrides: _overrides(passport: Passport.empty()),
        );
        await tester.pumpAndSettle();

        final AppLocalizations l10n = await _uk();
        // Empty-state copy + CTA.
        expect(find.text(l10n.passportEmptyTitle), findsOneWidget);
        expect(find.text(l10n.passportEmptyBody), findsOneWidget);
        expect(
          find.byKey(const Key('passport_find_master_button')),
          findsOneWidget,
        );

        // The populated document card must NOT be present.
        expect(find.byType(PassportCard), findsNothing);
        expect(find.text('BEAUTY PASSPORT'), findsNothing);
      },
    );
  });

  group('PassportScreen — removed elements', () {
    testWidgets('shows NO «+ Додати ще» text in either state', (tester) async {
      await tester.pumpApp(
        const PassportScreen(),
        overrides: _overrides(passport: _populatedPassport),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Додати'), findsNothing);
    });

    testWidgets('profile location line has NO expand_more chevron', (
      tester,
    ) async {
      await tester.pumpApp(
        const PassportScreen(),
        overrides: _overrides(passport: _populatedPassport),
      );
      await tester.pumpAndSettle();

      // The Головна card has a chevron after the city; the passport design
      // dropped it — assert no Material chevron glyph anywhere on the screen.
      expect(find.byIcon(Icons.expand_more), findsNothing);
      expect(find.byIcon(Icons.expand_more_rounded), findsNothing);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });
  });

  group('PassportScreen — FLAG_SECURE lifecycle', () {
    testWidgets('acquires screen protection on mount, releases on dispose', (
      tester,
    ) async {
      // A real manager: its native enable/disable is kDebugMode-guarded (skipped
      // under flutter test), so only the reference-count bookkeeping runs.
      final ScreenProtectionManager protection = ScreenProtectionManager();
      expect(protection.acquirerCount, 0);

      await tester.pumpApp(
        const PassportScreen(),
        overrides: _overrides(
          passport: _populatedPassport,
          protection: protection,
        ),
      );
      await tester.pumpAndSettle();

      // Mounted ⇒ exactly one acquirer (the PassportScreen).
      expect(
        protection.acquirerCount,
        1,
        reason: 'PassportScreen must acquire() screen protection in initState',
      );

      // Replace the screen so PassportScreen is disposed.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(
        protection.acquirerCount,
        0,
        reason: 'PassportScreen must release() screen protection in dispose',
      );
    });
  });
}
