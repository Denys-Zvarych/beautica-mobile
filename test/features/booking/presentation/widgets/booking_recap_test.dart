// mobile-qa regression — `BookingRecap`'s `compactText` font-size reduction.
// `BookingSummaryCards` forwards its own `compactText` straight through to
// `BookingRecap` (see `booking_summary_cards.dart`'s file header) so the
// success screen's per-service row and "Разом" total row shrink a further
// notch alongside the details card's own label/value rows. Pins the ACTUAL
// rendered fontSize shrink for both rows — not merely that the flag reaches
// the constructor as an inert argument that never reaches any Text style.

import 'package:beautica_mobile/features/booking/presentation/widgets/booking_recap.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
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

        expect(compactSize, 11.0);
        expect(roomySize, 11.5);
        expect(
          compactSize!,
          lessThan(roomySize!),
          reason:
              "compactText:true must shrink _ServiceRow's name text "
              '(11.5 -> 11) — if the flag were forwarded but never read '
              'by _ServiceRow, both renders would come out at 11.5 and '
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

        expect(compactSize, 12.5);
        expect(roomySize, 14.0);
        expect(
          compactSize!,
          lessThan(roomySize!),
          reason:
              "compactText:true must shrink _TotalRow's price text "
              '(14 -> 12.5) — if the flag were forwarded but never read '
              'by _TotalRow, both renders would come out at 14.0 and '
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

  // ===========================================================================
  // mobile-qa gap (salon confirm/success rework, KNOWN COVERAGE GAPS): neither
  // `BookingRecap.totalOnly` nor `BookingSelection.fromSalonCatalogService` had
  // ANY direct unit/widget pinning — both shipped in this session and are only
  // exercised indirectly through the salon confirm/success screens.
  // ===========================================================================

  group('BookingRecap.totalOnly', () {
    const twoServices = <BookingSelection>[
      BookingSelection(
        name: 'Манікюр класичний',
        price: '400 грн',
        duration: '1 год',
        durationMinutes: 60,
        priceMin: 400,
      ),
      BookingSelection(
        name: 'Корекція брів',
        price: '300 грн',
        duration: '45 хв',
        durationMinutes: 45,
        priceMin: 300,
      ),
    ];

    testWidgets('totalOnly: true renders ONLY the bold "Разом" total row — no '
        '"Послуги" header, no per-service rows, no hairline dividers', (
      tester,
    ) async {
      await tester.pumpApp(
        const Scaffold(
          body: BookingRecap(selections: twoServices, totalOnly: true),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(BookingRecap)),
      );

      expect(
        find.text(l10n.bookingServicesRecapLabel),
        findsNothing,
        reason:
            'totalOnly must suppress the "Послуги" header entirely — the '
            'salon confirm/success grand-total card wants ONLY the bold '
            'total line, not a second services list',
      );
      // i18n-finder-ok: service names are fixture data (twoServices), not translated UI copy.
      expect(find.text('Манікюр класичний'), findsNothing);
      // i18n-finder-ok: service names are fixture data (twoServices), not translated UI copy.
      expect(find.text('Корекція брів'), findsNothing);
      expect(find.byType(Divider), findsNothing);

      // The SUMMED total still renders (400 + 300 = 700 грн, 60 + 45 = 105
      // min = "1 год 45 хв").
      // i18n-finder-ok: price/duration are fixture-derived data strings, not translated UI copy.
      expect(find.text('700 грн'), findsOneWidget);
      // i18n-finder-ok: price/duration are fixture-derived data strings, not translated UI copy.
      expect(find.text('1 год 45 хв'), findsOneWidget);
    });

    testWidgets(
      'totalOnly: false (the default) still renders the full "Послуги" list '
      'alongside the total — the flag genuinely branches rendering, it is '
      'not always-total',
      (tester) async {
        await tester.pumpApp(
          const Scaffold(body: BookingRecap(selections: twoServices)),
        );
        await tester.pumpAndSettle();

        final l10n = AppLocalizations.of(
          tester.element(find.byType(BookingRecap)),
        );
        expect(find.text(l10n.bookingServicesRecapLabel), findsOneWidget);
        // i18n-finder-ok: service names are fixture data (twoServices), not translated UI copy.
        expect(find.text('Манікюр класичний'), findsOneWidget);
        // i18n-finder-ok: service names are fixture data (twoServices), not translated UI copy.
        expect(find.text('Корекція брів'), findsOneWidget);
      },
    );
  });

  group('BookingSelection.fromSalonCatalogService', () {
    test(
      'maps every field 1:1 from a FIXED-price SalonCatalogService, carrying '
      'the TYPED durationMinutes/priceMin through (priceMax stays null)',
      () {
        const service = SalonCatalogService(
          id: 'svc-1',
          name: 'Манікюр класичний',
          durationLabel: '1 год',
          priceDisplay: '400 грн',
          durationMinutes: 60,
          priceType: ServicePriceType.fixed,
          priceMin: 400,
        );

        final BookingSelection selection =
            BookingSelection.fromSalonCatalogService(service);

        expect(selection.name, 'Манікюр класичний');
        expect(selection.price, '400 грн');
        expect(selection.duration, '1 год');
        expect(
          selection.durationMinutes,
          60,
          reason:
              'the typed field must be carried straight through, not '
              're-derived by parsing `durationLabel`',
        );
        expect(selection.priceMin, 400);
        expect(selection.priceMax, isNull);
      },
    );

    test('carries a RANGE service\'s priceMax through too (priceMin = floor, '
        'priceMax = ceiling)', () {
      const service = SalonCatalogService(
        id: 'svc-2',
        name: 'Нарощення вій',
        durationLabel: '2 год',
        priceDisplay: '600 - 900 грн',
        durationMinutes: 120,
        priceType: ServicePriceType.range,
        priceMin: 600,
        priceMax: 900,
      );

      final BookingSelection selection =
          BookingSelection.fromSalonCatalogService(service);

      expect(selection.name, 'Нарощення вій');
      expect(selection.durationMinutes, 120);
      expect(selection.priceMin, 600);
      expect(selection.priceMax, 900);
    });
  });

  // ===========================================================================
  // mobile-perf MEDIUM regression (Phase 14.18 salon-confirm audit): assert
  // the SUMMED total is actually derived from the TYPED durationMinutes/
  // priceMin/priceMax fields, not a regex re-parse of the display strings —
  // AND that the regex-parse fallback still works for a selection built
  // without the typed fields (e.g. an older fixture).
  // ===========================================================================

  group('BookingRecap typed-totals path', () {
    testWidgets(
      'when typed durationMinutes/priceMin are present, the "Разом" total '
      'sums the TYPED fields — proven with a selection whose display '
      'strings would parse to a DIFFERENT (wrong) number via the regex '
      'fallback',
      (tester) async {
        // The display strings are deliberately WRONG/stale: the regex
        // fallback would parse "999 грн" -> 999 and "3 год" -> 180 minutes.
        // If `_BookingTotals.from` ever regressed to always re-parsing the
        // display string instead of preferring the typed fields, the total
        // below would read "999 грн" / "3 год" instead of the typed "400
        // грн" / "1 год".
        const selection = BookingSelection(
          name: 'Манікюр класичний',
          price: '999 грн',
          duration: '3 год',
          durationMinutes: 60,
          priceMin: 400,
        );

        await tester.pumpApp(
          const Scaffold(
            body: BookingRecap(selections: <BookingSelection>[selection]),
          ),
        );
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(BookingRecap)),
        );

        final String expectedLabel = l10n.bookingTotalSemantics(
          '1 год',
          '400 грн',
        );
        final Finder totalSemantics = find.byWidgetPredicate(
          (Widget w) => w is Semantics && w.properties.label == expectedLabel,
        );
        expect(
          totalSemantics,
          findsOneWidget,
          reason:
              'the total must reflect the TYPED fields (400 грн / 1 год), '
              'never the stale display strings (999 грн / 3 год) a regex '
              're-parse would have produced',
        );
        // And the WRONG (regex-derived) total must never appear either.
        expect(
          find.byWidgetPredicate(
            (Widget w) =>
                w is Semantics &&
                w.properties.label ==
                    l10n.bookingTotalSemantics('3 год', '999 грн'),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'when typed fields are ABSENT (null) on every selection, the total '
      'still sums correctly via the regex-parse fallback on the display '
      'strings — the pre-existing behaviour for a selection/fixture that '
      'carries no typed data',
      (tester) async {
        const selectionA = BookingSelection(
          name: 'Манікюр класичний',
          price: '400 грн',
          duration: '1 год',
        );
        const selectionB = BookingSelection(
          name: 'Корекція брів',
          price: '300 грн',
          duration: '45 хв',
        );

        await tester.pumpApp(
          const Scaffold(
            body: BookingRecap(
              selections: <BookingSelection>[selectionA, selectionB],
            ),
          ),
        );
        await tester.pumpAndSettle();

        final l10n = AppLocalizations.of(
          tester.element(find.byType(BookingRecap)),
        );
        final String expectedLabel = l10n.bookingTotalSemantics(
          '1 год 45 хв',
          '700 грн',
        );
        expect(
          find.byWidgetPredicate(
            (Widget w) => w is Semantics && w.properties.label == expectedLabel,
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a MIXED list (one selection WITH typed fields, one WITHOUT) sums '
      'both correctly — the typed-vs-fallback branch is chosen '
      'independently per selection, not for the whole list at once',
      (tester) async {
        const typedSelection = BookingSelection(
          name: 'Манікюр класичний',
          price: '400 грн',
          duration: '1 год',
          durationMinutes: 60,
          priceMin: 400,
        );
        const untypedSelection = BookingSelection(
          name: 'Корекція брів',
          price: '300 грн',
          duration: '45 хв',
        );

        await tester.pumpApp(
          const Scaffold(
            body: BookingRecap(
              selections: <BookingSelection>[typedSelection, untypedSelection],
            ),
          ),
        );
        await tester.pumpAndSettle();

        final l10n = AppLocalizations.of(
          tester.element(find.byType(BookingRecap)),
        );
        final String expectedLabel = l10n.bookingTotalSemantics(
          '1 год 45 хв',
          '700 грн',
        );
        expect(
          find.byWidgetPredicate(
            (Widget w) => w is Semantics && w.properties.label == expectedLabel,
          ),
          findsOneWidget,
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
