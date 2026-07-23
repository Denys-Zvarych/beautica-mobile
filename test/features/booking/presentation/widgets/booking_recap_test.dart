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
import 'package:beautica_mobile/shared/formatters/booking_price_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

// A single fixed-price/fixed-duration selection, chosen so the "Разом" total
// row's derived price/duration strings are IDENTICAL to this selection's own
// (500 ₴ summed over one service is still "500 ₴"; 1 год 30 хв summed is
// still "1 год 30 хв") — see `_BookingTotals.from` in `booking_recap.dart`.
// That lets the total-row test below reconstruct the expected Semantics
// label deterministically without depending on the widget's own private
// parsing helpers.
const _kSelection = BookingSelection(
  name: 'Манікюр з покриттям',
  price: '500 ₴',
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
          // Disambiguates from the per-service row's OWN '500 ₴' price
          // text (a different Text instance, different fontSize) by scoping
          // the search to the "Разом" total row's own Semantics wrapper —
          // see `_TotalRow`'s `Semantics(label: semanticsLabel)` in
          // booking_recap.dart. A plain `find.text('500 ₴')` would match
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
      price: '500 ₴',
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
        price: '400 ₴',
        duration: '1 год',
        durationMinutes: 60,
        priceMin: 400,
      ),
      BookingSelection(
        name: 'Корекція брів',
        price: '300 ₴',
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

      // The SUMMED total still renders (400 + 300 = 700 ₴, 60 + 45 = 105
      // min = "1 год 45 хв").
      // i18n-finder-ok: price/duration are fixture-derived data strings, not translated UI copy.
      expect(find.text('700 ₴'), findsOneWidget);
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
          priceDisplay: '400 ₴',
          durationMinutes: 60,
          priceType: ServicePriceType.fixed,
          priceMin: 400,
        );

        final BookingSelection selection =
            BookingSelection.fromSalonCatalogService(service);

        expect(selection.name, 'Манікюр класичний');
        expect(selection.price, '400 ₴');
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
        priceDisplay: '600 - 900 ₴',
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
        // fallback would parse "999 ₴" -> 999 and "3 год" -> 180 minutes.
        // If `_BookingTotals.from` ever regressed to always re-parsing the
        // display string instead of preferring the typed fields, the total
        // below would read "999 ₴" / "3 год" instead of the typed "400
        // ₴" / "1 год".
        const selection = BookingSelection(
          name: 'Манікюр класичний',
          price: '999 ₴',
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
          '400 ₴',
        );
        final Finder totalSemantics = find.byWidgetPredicate(
          (Widget w) => w is Semantics && w.properties.label == expectedLabel,
        );
        expect(
          totalSemantics,
          findsOneWidget,
          reason:
              'the total must reflect the TYPED fields (400 ₴ / 1 год), '
              'never the stale display strings (999 ₴ / 3 год) a regex '
              're-parse would have produced',
        );
        // And the WRONG (regex-derived) total must never appear either.
        expect(
          find.byWidgetPredicate(
            (Widget w) =>
                w is Semantics &&
                w.properties.label ==
                    l10n.bookingTotalSemantics('3 год', '999 ₴'),
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
          price: '400 ₴',
          duration: '1 год',
        );
        const selectionB = BookingSelection(
          name: 'Корекція брів',
          price: '300 ₴',
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
          '700 ₴',
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
          price: '400 ₴',
          duration: '1 год',
          durationMinutes: 60,
          priceMin: 400,
        );
        const untypedSelection = BookingSelection(
          name: 'Корекція брів',
          price: '300 ₴',
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
          '700 ₴',
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

  // ===========================================================================
  // Security MEDIUM — `_BookingTotals.from` used to coerce the WIRE doubles
  // `BookingSelection.priceMin`/`priceMax` to `int` via `.round()` and
  // hand-build its own `'$minSum–$maxSum ₴'` label, bypassing the shared
  // `isRenderablePrice` guard that `formatBookingTotals` /
  // `formatBookingPrice` / `ServicePriceDisplay.format` all pass through.
  // That coercion failed TWO ways, and the wire path is unclamped end-to-end
  // (`master_service_mapper.dart` / `salon_mapper.dart` pass the decoded
  // doubles straight through, and `jsonDecode('1e400')` yields
  // `double.infinity` WITHOUT throwing):
  //
  //   1. `double.infinity.round()` / `double.nan.round()` THROW
  //      (`UnsupportedError: Infinity or NaN toInt`) — inside `build()`, so
  //      the booking-confirm / success / salon-confirm screen became an error
  //      widget.
  //   2. `(1e30).round()` does NOT throw — it saturates to int64 max
  //      (9223372036854775807). ONE such service rendered
  //      «9223372036854775807 ₴»; TWO wrapped `minSum +=` around to a
  //      NEGATIVE total («-2 ₴») on the very screen where the client is
  //      agreeing to a price.
  //
  // Both roads are pinned below. The control case at the end is what makes
  // these honest: a blanket "always render —" mutation would satisfy the
  // first four tests and fail the fifth.
  // ===========================================================================

  group('BookingRecap totals — unrenderable wire prices', () {
    /// The «Разом» row's Semantics label for a total that could not be stated.
    Finder unrenderableTotal(WidgetTester tester, String durationLabel) {
      final l10n = AppLocalizations.of(
        tester.element(find.byType(BookingRecap)),
      );
      final String expected = l10n.bookingTotalSemantics(
        durationLabel,
        priceUnavailableLabel,
      );
      return find.byWidgetPredicate(
        (Widget w) => w is Semantics && w.properties.label == expected,
      );
    }

    /// Every rendered `Text` string in the tree — used to assert that no
    /// garbage figure leaked into ANY of them, not merely into the one node
    /// a scoped finder happened to look at.
    List<String> renderedTexts(WidgetTester tester) => tester
        .widgetList<Text>(find.byType(Text))
        .map((Text t) => t.data ?? '')
        .toList();

    Future<void> pumpTotals(
      WidgetTester tester,
      List<BookingSelection> selections,
    ) async {
      await tester.pumpApp(
        Scaffold(body: BookingRecap(selections: selections)),
      );
      await tester.pumpAndSettle();
    }

    for (final (String name, double bad) in <(String, double)>[
      ('double.infinity', double.infinity),
      ('double.nan', double.nan),
    ]) {
      testWidgets(
        'a $name priceMin off the wire renders the neutral unavailable label '
        'instead of throwing out of build()',
        (tester) async {
          await pumpTotals(tester, <BookingSelection>[
            BookingSelection(
              name: 'Манікюр класичний',
              price: '400 ₴',
              duration: '1 год',
              durationMinutes: 60,
              priceMin: bad,
            ),
          ]);

          expect(
            tester.takeException(),
            isNull,
            reason:
                '$name must never reach `.toInt()`/`.round()` — that throws '
                'UnsupportedError inside build() and turns the booking '
                'confirm/success screen into an error widget',
          );
          expect(
            unrenderableTotal(tester, '1 год'),
            findsOneWidget,
            reason:
                'an unstatable total must fall back to the shared '
                'priceUnavailableLabel, exactly as formatBookingPrice does '
                'for an unrenderable floor',
          );
          expect(
            renderedTexts(tester).where((String s) => s.contains('Infinity')),
            isEmpty,
            reason: '«Infinity ₴» must never be stringified onto a screen',
          );
          expect(
            renderedTexts(tester).where((String s) => s.contains('NaN')),
            isEmpty,
            reason: '«NaN ₴» must never be stringified onto a screen',
          );
        },
      );
    }

    testWidgets(
      'TWO 1e30-priced services do not int64-saturate-then-overflow into a '
      'NEGATIVE total — the road that never threw and so shipped a wrong '
      'money figure silently',
      (tester) async {
        await pumpTotals(tester, const <BookingSelection>[
          BookingSelection(
            name: 'Манікюр класичний',
            price: '400 ₴',
            duration: '1 год',
            durationMinutes: 60,
            priceMin: 1e30,
          ),
          BookingSelection(
            name: 'Корекція брів',
            price: '300 ₴',
            duration: '45 хв',
            durationMinutes: 45,
            priceMin: 1e30,
          ),
        ]);

        expect(tester.takeException(), isNull);

        final List<String> texts = renderedTexts(tester);
        expect(
          texts.where((String s) => RegExp(r'-\s*\d').hasMatch(s)),
          isEmpty,
          reason:
              'a negative money figure («-2 ₴», the int64 wrap of two '
              'saturated terms) must never render on the screen where the '
              'client is agreeing to a price',
        );
        expect(
          texts.where((String s) => s.contains('9223372036854775807')),
          isEmpty,
          reason: 'the int64 saturation value itself must never render either',
        );
        expect(unrenderableTotal(tester, '1 год 45 хв'), findsOneWidget);
      },
    );

    testWidgets(
      'a per-service figure is gated BEFORE it is summed — two out-of-range '
      'terms that cancel each other to a plausible 0 still refuse to state a '
      'total',
      (tester) async {
        // `+` is not protective: 1e30 + -1e30 == 0.0, which passes
        // isRenderablePrice at the SUM level and would render a confident,
        // entirely fictional «0 ₴». Only an upstream per-term gate catches it.
        await pumpTotals(tester, const <BookingSelection>[
          BookingSelection(
            name: 'Манікюр класичний',
            price: '400 ₴',
            duration: '1 год',
            durationMinutes: 60,
            priceMin: 1e30,
          ),
          BookingSelection(
            name: 'Корекція брів',
            price: '300 ₴',
            duration: '45 хв',
            durationMinutes: 45,
            priceMin: -1e30,
          ),
        ]);

        expect(tester.takeException(), isNull);
        expect(
          unrenderableTotal(tester, '1 год 45 хв'),
          findsOneWidget,
          reason:
              'gating only the SUM would render «0 ₴» here — the guard must '
              'sit on each term before it enters the accumulator',
        );
      },
    );

    testWidgets(
      'CONTROL — well-formed wire doubles still render the ordinary summed '
      'band, so the guard above cannot be satisfied by suppressing every '
      'total',
      (tester) async {
        await pumpTotals(tester, const <BookingSelection>[
          BookingSelection(
            name: 'Манікюр класичний',
            price: '400 ₴',
            duration: '1 год',
            durationMinutes: 60,
            priceMin: 400,
            priceMax: 600,
          ),
          BookingSelection(
            name: 'Корекція брів',
            price: '300 ₴',
            duration: '45 хв',
            durationMinutes: 45,
            priceMin: 300,
          ),
        ]);

        final l10n = AppLocalizations.of(
          tester.element(find.byType(BookingRecap)),
        );
        expect(
          find.byWidgetPredicate(
            (Widget w) =>
                w is Semantics &&
                w.properties.label ==
                    l10n.bookingTotalSemantics('1 год 45 хв', '700–900 ₴'),
          ),
          findsOneWidget,
          reason:
              '400+300 = 700 floor, 600+300 = 900 ceiling — the en-dash band '
              'the shared formatBookingTotals conventions produce',
        );
        expect(unrenderableTotal(tester, '1 год 45 хв'), findsNothing);
      },
    );
  });

  // ── showPrice gates the SEMANTICS tree, not just the visual one ──────────
  //
  // Security MEDIUM: `_ServiceRow` used to build its `Semantics(label: ...)`
  // unconditionally while `showPrice` gated only the visual `Text`, so a
  // cancelled / declined / not-completed booking still ANNOUNCED its price to
  // TalkBack/VoiceOver and exposed it in the semantics tree — a readable
  // surface under this project's threat model. The accessibility tree must
  // state exactly what the visual tree states.
  group('BookingRecap.single — showPrice gates the semantics label too', () {
    Future<AppLocalizations> pumpSingle(
      WidgetTester tester, {
      required bool showPrice,
    }) async {
      await tester.pumpApp(
        Scaffold(
          body: BookingRecap.single(
            selection: const BookingSelection(
              name: 'Манікюр з покриттям',
              price: '300–500 ₴',
              duration: '1 год 30 хв',
            ),
            showPrice: showPrice,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Locate the context by TYPE, not by the service name: the name is
      // fixture data this helper supplies, and keying the lookup off it would
      // couple the test to a literal that has nothing to do with what the
      // assertions below actually prove.
      return AppLocalizations.of(tester.element(find.byType(BookingRecap)));
    }

    testWidgets('showPrice: false announces the price-less variant and the '
        'band appears nowhere in the semantics tree', (tester) async {
      final AppLocalizations l10n = await pumpSingle(tester, showPrice: false);

      // The visual gate still holds.
      expect(find.text('300–500 ₴'), findsNothing);

      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w is Semantics &&
              w.properties.label ==
                  l10n.bookingServiceTileSemanticsNoPrice(
                    'Манікюр з покриттям',
                    '1 год 30 хв',
                  ),
        ),
        findsOneWidget,
      );

      // The real assertion: no semantics node anywhere carries the band. A
      // label-equality check alone would pass even if a second node leaked it.
      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w is Semantics && (w.properties.label ?? '').contains('₴'),
        ),
        findsNothing,
        reason: 'a suppressed price must not reach the accessibility tree',
      );
    });

    testWidgets('showPrice: true (the booking-flow default) still announces '
        'the full name + duration + price label', (tester) async {
      final AppLocalizations l10n = await pumpSingle(tester, showPrice: true);

      expect(find.text('300–500 ₴'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w is Semantics &&
              w.properties.label ==
                  l10n.bookingServiceTileSemantics(
                    'Манікюр з покриттям',
                    '1 год 30 хв',
                    '300–500 ₴',
                  ),
        ),
        findsOneWidget,
      );
    });
  });

  // ── the SAME gate, one constructor over: LIST mode ──────────────────────
  //
  // Security MEDIUM (re-audit). `showPrice` is fully plumbed into this branch
  // — `booking_summary_cards.dart` forwards it to the plain `BookingRecap(…)`
  // exactly as it does to `.single(…)` — and both files' doc comments assert
  // it gates "the «Разом» total (list mode)". It did not: `_TotalRow` was
  // built unconditionally, semantics label and all, and the per-service rows
  // were never handed the flag so they defaulted to `true`. A documented-but-
  // absent gate is worse than no gate: the salon N-master flow already feeds
  // real multi-item lists, so one future multi-service detail surface would
  // have reintroduced the leak without touching this widget at all.
  //
  // Mirrors the single-mode assertions above deliberately — the two modes must
  // be provably equivalent on this flag, not merely similar in intent.
  group('BookingRecap (list mode) — showPrice gates rows AND the total', () {
    const List<BookingSelection> twoServices = <BookingSelection>[
      BookingSelection(
        name: 'Манікюр класичний',
        price: '400 ₴',
        duration: '1 год',
        durationMinutes: 60,
        priceMin: 400,
      ),
      BookingSelection(
        name: 'Корекція брів',
        price: '300 ₴',
        duration: '45 хв',
        durationMinutes: 45,
        priceMin: 300,
      ),
    ];

    Future<AppLocalizations> pumpList(
      WidgetTester tester, {
      required bool showPrice,
    }) async {
      await tester.pumpApp(
        Scaffold(
          body: BookingRecap(selections: twoServices, showPrice: showPrice),
        ),
      );
      await tester.pumpAndSettle();
      return AppLocalizations.of(tester.element(find.byType(BookingRecap)));
    }

    testWidgets('showPrice: false suppresses every per-service price, the '
        '«Разом» band, and the whole band from the semantics tree', (
      tester,
    ) async {
      final AppLocalizations l10n = await pumpList(tester, showPrice: false);

      // Visual gate — the two row prices AND the summed total (700 ₴).
      // i18n-finder-ok: price strings are fixture-derived data, not translated UI copy.
      expect(find.text('400 ₴'), findsNothing);
      // i18n-finder-ok: price strings are fixture-derived data, not translated UI copy.
      expect(find.text('300 ₴'), findsNothing);
      // i18n-finder-ok: price strings are fixture-derived data, not translated UI copy.
      expect(find.text('700 ₴'), findsNothing);

      // The total row itself still renders — only its money is dropped — and
      // announces the price-less variant.
      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w is Semantics &&
              w.properties.label ==
                  l10n.bookingTotalSemanticsNoPrice('1 год 45 хв'),
        ),
        findsOneWidget,
        reason:
            'the «Разом» row must announce the price-less variant, not fall '
            'silent and not keep the priced one',
      );

      // The real assertion, identical to single mode: NOTHING in the
      // accessibility tree carries the currency. Catches the per-service rows
      // and the total in one sweep, and would still fire if a third node
      // started leaking a band.
      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w is Semantics && (w.properties.label ?? '').contains('₴'),
        ),
        findsNothing,
        reason: 'a suppressed price must not reach the accessibility tree',
      );
    });

    testWidgets('showPrice: true (the booking-flow default) still renders both '
        'row prices and the summed «Разом» band', (tester) async {
      final AppLocalizations l10n = await pumpList(tester, showPrice: true);

      // i18n-finder-ok: price strings are fixture-derived data, not translated UI copy.
      expect(find.text('400 ₴'), findsOneWidget);
      // i18n-finder-ok: price strings are fixture-derived data, not translated UI copy.
      expect(find.text('300 ₴'), findsOneWidget);
      // i18n-finder-ok: price strings are fixture-derived data, not translated UI copy.
      expect(find.text('700 ₴'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w is Semantics &&
              w.properties.label ==
                  l10n.bookingTotalSemantics('1 год 45 хв', '700 ₴'),
        ),
        findsOneWidget,
      );
    });
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
