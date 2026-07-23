// Phase 13.8 — BEAUTY PASSPORT card (PassportCard) widget tests.
//
// Exercises the document card in ISOLATION (no screen, no providers): the
// branded header, the three derived columns, the budget chip, and the reviews
// footer. The card itself takes already-localised String values, so these tests
// pass literal Ukrainian/English values in and assert they render.
//
// What is asserted:
//   • The locked, UNTRANSLATED brand title "BEAUTY PASSPORT" renders as a raw
//     literal (kBeautyPassportTitle) — never via an l10n lookup — and the locked
//     Ukrainian subtitle «Твій б'юті-паспорт у Beautica» renders.
//   • The three column eyebrow labels render (uppercased) from l10n.
//   • Each procedure / district chip and the budget value chip render.
//   • The reviews footer shows the localised count + member-since lines.
//   • REMOVED affordance: NO «+ Додати ще» text anywhere (read-only by design).

import 'package:beautica_mobile/features/passport/presentation/widgets/passport_table.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
  locale: const Locale('uk'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(child: SizedBox(width: 360, child: child)),
  ),
);

const PassportCard _populatedCard = PassportCard(
  procedures: <String>['Манікюр', 'Брови', 'Педикюр'],
  districts: <String>['Центр', 'Сихів', 'Франківський'],
  budgetValue: 'до 800 ₴',
  reviewsLeft: 5,
  memberSince: '2024',
);

void main() {
  group('PassportCard — branded header', () {
    testWidgets(
      'renders the untranslated "BEAUTY PASSPORT" literal (not an l10n lookup)',
      (tester) async {
        await tester.pumpWidget(_wrap(_populatedCard));
        await tester.pumpAndSettle();

        // The exported brand constant IS the literal — proving the title is not
        // routed through AppLocalizations.
        expect(kBeautyPassportTitle, 'BEAUTY PASSPORT');
        expect(find.text(kBeautyPassportTitle), findsOneWidget);
        expect(find.text('BEAUTY PASSPORT'), findsOneWidget);
      },
    );

    testWidgets('renders the locked Ukrainian brand subtitle', (tester) async {
      await tester.pumpWidget(_wrap(_populatedCard));
      await tester.pumpAndSettle();

      expect(find.text(kBeautyPassportSubtitle), findsOneWidget);
      // The exact locked literal (curly apostrophe), not paraphrased.
      expect(kBeautyPassportSubtitle, 'Твій б’юті-паспорт у Beautica');
    });
  });

  group('PassportCard — three derived columns', () {
    testWidgets('renders the three column eyebrow labels (uppercased)', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(_populatedCard));
      await tester.pumpAndSettle();

      final AppLocalizations l10n = await AppLocalizations.delegate.load(
        const Locale('uk'),
      );
      expect(
        find.text(l10n.passportColumnProcedures.toUpperCase()),
        findsOneWidget,
      );
      expect(
        find.text(l10n.passportColumnDistricts.toUpperCase()),
        findsOneWidget,
      );
      expect(
        find.text(l10n.passportColumnBudget.toUpperCase()),
        findsOneWidget,
      );
    });

    testWidgets('renders every procedure chip', (tester) async {
      await tester.pumpWidget(_wrap(_populatedCard));
      await tester.pumpAndSettle();

      expect(find.text('Манікюр'), findsOneWidget);
      expect(find.text('Брови'), findsOneWidget);
      expect(find.text('Педикюр'), findsOneWidget);
    });

    testWidgets('renders every district chip', (tester) async {
      await tester.pumpWidget(_wrap(_populatedCard));
      await tester.pumpAndSettle();

      expect(find.text('Центр'), findsOneWidget);
      expect(find.text('Сихів'), findsOneWidget);
      expect(find.text('Франківський'), findsOneWidget);
    });

    testWidgets('renders the budget value chip', (tester) async {
      await tester.pumpWidget(_wrap(_populatedCard));
      await tester.pumpAndSettle();

      expect(find.text('до 800 ₴'), findsOneWidget);
    });
  });

  group('PassportCard — reviews footer', () {
    testWidgets('renders the localised reviews-left + member-since lines', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(_populatedCard));
      await tester.pumpAndSettle();

      final AppLocalizations l10n = await AppLocalizations.delegate.load(
        const Locale('uk'),
      );
      expect(find.text(l10n.passportReviewsLeft(5)), findsOneWidget);
      expect(find.text(l10n.passportMemberSince('2024')), findsOneWidget);
    });
  });

  group('PassportCard — read-only (no add affordance)', () {
    testWidgets('shows NO «+ Додати ще» text anywhere (read-only by design)', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(_populatedCard));
      await tester.pumpAndSettle();

      expect(find.textContaining('Додати'), findsNothing);
    });
  });
}
