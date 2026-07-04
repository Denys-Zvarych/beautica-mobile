// mobile-qa regression — `BookingRecap`'s `compactText` font-size reduction.
// `BookingSummaryCards` forwards its own `compactText` straight through to
// `BookingRecap` (see `booking_summary_cards.dart`'s file header) so the
// success screen's per-service row and "Разом" total row shrink a further
// notch alongside the details card's own label/value rows. Pins the ACTUAL
// rendered fontSize shrink for both rows — not merely that the flag reaches
// the constructor as an inert argument that never reaches any Text style.

import 'package:beautica_mobile/features/booking/presentation/widgets/booking_recap.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

// A single fixed-price/fixed-duration selection, chosen so the "Разом" total
// row's derived price/duration strings are IDENTICAL to this selection's own
// (500 грн summed over one service is still "500 грн"; 1 год 30 хв summed is
// still "1 год 30 хв") — see `_BookingTotals.from` in `booking_recap.dart`.
// That lets the total-row test below reconstruct the expected Semantics
// label deterministically without depending on the widget's own private
// parsing helpers.
const _kSelection = BookingSelection(
  name: 'Манікюр з покриттям',
  price: '500 грн',
  duration: '1 год 30 хв',
);

void main() {
  Future<void> pumpRecap(WidgetTester tester, {required bool compactText}) =>
      tester.pumpApp(
        Scaffold(
          body: BookingRecap(
            selections: const <BookingSelection>[_kSelection],
            compactText: compactText,
          ),
        ),
      );

  group('BookingRecap compactText', () {
    testWidgets(
      'compactText: true renders a smaller service-row name fontSize than '
      'compactText: false',
      (tester) async {
        await pumpRecap(tester, compactText: true);
        await tester.pumpAndSettle();
        final double? compactSize = tester
            .widget<Text>(find.text(_kSelection.name))
            .style
            ?.fontSize;

        await pumpRecap(tester, compactText: false);
        await tester.pumpAndSettle();
        final double? roomySize = tester
            .widget<Text>(find.text(_kSelection.name))
            .style
            ?.fontSize;

        expect(compactSize, 13.0);
        expect(roomySize, 14.5);
        expect(
          compactSize!,
          lessThan(roomySize!),
          reason:
              "compactText:true must shrink _ServiceRow's name text "
              '(14.5 -> 13) — if the flag were forwarded but never read '
              'by _ServiceRow, both renders would come out at 14.5 and '
              'this assertion would catch it.',
        );
      },
    );

    testWidgets(
      'compactText: true renders a smaller "Разом" total price fontSize '
      'than compactText: false',
      (tester) async {
        Future<double?> totalPriceFontSize({required bool compactText}) async {
          await pumpRecap(tester, compactText: compactText);
          await tester.pumpAndSettle();

          final l10n = AppLocalizations.of(
            tester.element(find.byType(BookingRecap)),
          );
          // Disambiguates from the per-service row's OWN '500 грн' price
          // text (a different Text instance, different fontSize) by scoping
          // the search to the "Разом" total row's own Semantics wrapper —
          // see `_TotalRow`'s `Semantics(label: semanticsLabel)` in
          // booking_recap.dart. A plain `find.text('500 грн')` would match
          // BOTH the service row's price and the total row's price and be
          // ambiguous (findsNWidgets(2)).
          final String totalSemanticsLabel = l10n.bookingTotalSemantics(
            _kSelection.duration,
            _kSelection.price,
          );
          final Finder totalSemantics = find.byWidgetPredicate(
            (Widget w) =>
                w is Semantics && w.properties.label == totalSemanticsLabel,
          );
          expect(
            totalSemantics,
            findsOneWidget,
            reason:
                'expected exactly one Semantics node carrying the "Разом" '
                'total row\'s label — if this fails, the fixture\'s '
                'derived total no longer matches _BookingTotals.from\'s '
                'own parse/sum, and the test needs updating alongside it.',
          );

          return tester
              .widget<Text>(
                find.descendant(
                  of: totalSemantics,
                  matching: find.text(_kSelection.price),
                ),
              )
              .style
              ?.fontSize;
        }

        final double? compactSize = await totalPriceFontSize(
          compactText: true,
        );
        final double? roomySize = await totalPriceFontSize(
          compactText: false,
        );

        expect(compactSize, 15.5);
        expect(roomySize, 17.0);
        expect(
          compactSize!,
          lessThan(roomySize!),
          reason:
              "compactText:true must shrink _TotalRow's price text "
              '(17 -> 15.5) — if the flag were forwarded but never read '
              'by _TotalRow, both renders would come out at 17.0 and '
              'this assertion would catch it.',
        );
      },
    );
  });
}
