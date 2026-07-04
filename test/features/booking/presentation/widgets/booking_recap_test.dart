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
import 'package:flutter/rendering.dart';
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

        final double? compactSize = await totalPriceFontSize(compactText: true);
        final double? roomySize = await totalPriceFontSize(compactText: false);

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

  // mobile-qa regression — `_ServiceRow`'s service-name `Text` used to carry
  // `maxLines: 1` / `TextOverflow.ellipsis`, silently truncating long
  // service names on BOTH `BookingConfirmScreen` and `BookingSuccessScreen`
  // (this widget is shared by both — see the file header SCOPE NOTE). The
  // cap is now removed so a long name wraps onto additional lines instead.
  group('BookingRecap long service-name wrapping (mobile-qa regression)', () {
    // 89 Cyrillic characters — well past what fits on a single line at a
    // realistic phone width, forcing real wrapping (not just "doesn't
    // crash").
    const String longName =
        'Комплексний догляд за руками та нігтями з європейським '
        'манікюром і гель-лаковим покриттям';

    const longSelection = BookingSelection(
      name: longName,
      price: '500 грн',
      duration: '1 год 30 хв',
    );

    testWidgets(
      'a long service name wraps onto multiple lines instead of being '
      'ellipsis-truncated, with no overflow error',
      (tester) async {
        await tester.pumpApp(
          const Scaffold(
            body: BookingRecap(selections: <BookingSelection>[longSelection]),
          ),
          // Narrow, realistic phone width — forces the long name to
          // actually need more than one line. pumpApp's overflow guard fails
          // the test in tearDown on any RenderFlex overflow at this width,
          // so no separate overflow assertion is needed.
          width: 320,
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        final Text nameText = tester.widget<Text>(find.text(longName));
        expect(
          nameText.maxLines,
          isNull,
          reason:
              'a regression back to `maxLines: 1` would re-cap the service '
              'name to a single line and silently ellipsis-truncate long '
              "names — see this widget's SCOPE NOTE: it is shared by both "
              'BookingConfirmScreen and BookingSuccessScreen.',
        );
        expect(
          nameText.overflow,
          isNot(TextOverflow.ellipsis),
          reason:
              'the ellipsis overflow mode must not be reintroduced '
              'alongside maxLines',
        );

        final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
          find.text(longName),
        );
        expect(
          _lineCount(paragraph),
          greaterThan(1),
          reason:
              'proves the name actually WRAPPED (not merely "didn\'t '
              'throw") — an 89-char Cyrillic name cannot fit on one line at '
              '320dp without wrapping onto a second line.',
        );
      },
    );
  });
}

/// Number of lines the paragraph actually laid out — [RenderParagraph]
/// exposes no line count directly, so re-run the layout in a [TextPainter]
/// (mirrors the same technique already established in
/// `master_result_card_test.dart`'s long-name-wrapping tests).
int _lineCount(RenderParagraph p) {
  final TextPainter painter = TextPainter(
    text: p.text,
    textAlign: p.textAlign,
    textDirection: p.textDirection,
    textScaler: p.textScaler,
    maxLines: p.maxLines,
  )..layout(maxWidth: p.constraints.maxWidth);
  final int lines = painter.computeLineMetrics().length;
  painter.dispose();
  return lines;
}
