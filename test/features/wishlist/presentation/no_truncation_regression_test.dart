// REGRESSION GUARD — NO TRUNCATION anywhere on the BEAUTY PASSPORT surfaces.
//
// THE BUG (fixed by phases 238 + 239)
// -----------------------------------
// «Шевченківський» rendered as «Шев…» in the retired passport document card's
// cramped three-column layout. The whole redesign exists to fix that class of
// defect, and the locked rule that came out of it is absolute:
//
//   A SERVICE NAME, A MASTER NAME, A DISTRICT NAME OR A CITY NAME CARRIES NO
//   `maxLines` AND NO `TextOverflow`. It WRAPS. If it does not fit, the fix is
//   layout — never an ellipsis.
//
// WHAT THIS TEST PINS, AND WHY IT IS THREE ASSERTIONS AND NOT ONE
// ---------------------------------------------------------------
// Each fixture is checked three ways, because each catches a different way the
// rule can be broken and none of the three subsumes the others:
//
//   1. STRUCTURAL — the [Text] carries `maxLines == null` and its `overflow` is
//      not `ellipsis`. This is the direct statement of the rule and it fails on
//      the exact edit a future author is most likely to make.
//   2. RENDERED — the laid-out `RenderParagraph` reports
//      `didExceedMaxLines == false`. Ground truth rather than intent: a
//      `maxLines` inherited from an ancestor `DefaultTextStyle`, or applied by
//      a wrapper widget, never touches the [Text]'s own fields and would sail
//      straight past assertion 1.
//   3. FITS ITS BOX — the paragraph's laid-out width does not exceed the
//      constraint it was given. This is the UNBREAKABLE-WORD case: a single
//      word wider than its column does not ellipsise (there is no ellipsis to
//      apply), it PAINTS OUTSIDE ITS BOX, silently, with no RenderFlex overflow
//      stripe to report it. `installOverflowGuard` cannot see this one — it
//      watches `RenderFlex`, and a `RenderParagraph` is not a flex.
//
// WIDTHS
// ------
// 360 dp and 320 dp, the two the approved preview was measured at. Both matter:
// at 360 the compact card's text column is 126 dp and at 320 it is 106 dp,
// which is where «Ламінування» (~79 dp, the longest unbreakable word in the
// fixtures) gets close enough to the edge to be worth pinning.
//
// The widgets are pumped through their REAL hosts, not in isolation at the
// surface width: `WishlistSection` lays its two cards out inside its own
// `IntrinsicHeight` row, so the cards receive the same ~150 / ~130 dp they get
// on the page. Pumping a card directly at 360 dp would hand it 2.4x the width
// it actually has and the test would pass against a layout that truncates in
// production.
//
// MUTATION-VERIFIED
// -----------------
// Adding `maxLines: 1, overflow: TextOverflow.ellipsis` to the compact card's
// service name turns this file RED — see the phase report for the recorded
// failure output. A test that cannot go red is not a guard.

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/price_tag.dart';
import 'package:beautica_mobile/features/passport/presentation/widgets/passport_derived_block.dart';
import 'package:beautica_mobile/features/wishlist/application/wishlist_notifier.dart';
import 'package:beautica_mobile/features/wishlist/domain/wishlist_service.dart';
import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_row.dart';
import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_wishlist_repository.dart';
import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Worst-case fixtures — the longest real Ukrainian strings on these surfaces,
// taken verbatim from the approved preview's own fixture set
// (`docs/signup-designs/BeautyPassport/lib/screens/passport_data.dart`).
// ---------------------------------------------------------------------------

/// The longest service name. ~204 dp in `svcCardName` against a 126 dp compact
/// column — it MUST wrap to two lines and MUST NOT ellipsise.
const String kLongService = 'Ламінування та фарбування брів';

/// The longest master name. ~112 dp in `bookingCardSubtle`.
const String kLongMaster = 'Анастасія Мельниченко';

/// THE original bug. Clipped to «Шев…» in the retired card.
const String kLongDistrict = 'Шевченківський';

const String kSecondDistrict = 'Голосіївський';
const String kThirdDistrict = 'Печерський';
const String kCity = 'Бровари';

/// The two widths the preview was measured at.
const List<double> kWidths = <double>[360, 320];

WishlistService _entry({
  required String id,
  String service = kLongService,
  String master = kLongMaster,
  int minutes = 150,
  String priceDisplay = '1 200 ₴',
  bool isRange = false,
  double? priceMin,
  double? priceMax,
}) => WishlistService(
  masterServiceId: id,
  masterId: 'm-$id',
  serviceName: service,
  masterName: master,
  durationMinutes: minutes,
  priceDisplay: priceDisplay,
  isRangePrice: isRange,
  priceMin: priceMin,
  priceMax: priceMax,
);

/// The worst-case pair the passport page's two-card line actually renders:
/// the longest service name AND the longest master name, plus the widest price
/// form (a RANGE band) on the second card.
final List<WishlistService> _worstCase = <WishlistService>[
  _entry(id: 'w1'),
  _entry(
    id: 'w2',
    minutes: 120,
    isRange: true,
    priceMin: 700,
    priceMax: 1100,
    priceDisplay: 'від 700 до 1 100 ₴',
  ),
];

// ---------------------------------------------------------------------------
// The assertion
// ---------------------------------------------------------------------------

/// Fails unless [text] is rendered WHOLE — not ellipsised, not line-clipped and
/// not painted outside its own box. See the file header for why all three.
void expectRendersWhole(WidgetTester tester, String text, {String? at}) {
  final String where = at == null ? '' : ' ($at)';
  // i18n-finder-ok: these are FIXTURE DATA — a service, master and district
  // name that arrive from the wire identically in every locale — not UI copy
  // pulled from the ARB. Locating them by key is impossible: the point of the
  // test is that THIS STRING renders whole.
  final Finder finder = find.text(text);
  expect(
    finder,
    findsOneWidget,
    reason: 'the fixture «$text» should be on screen$where',
  );

  // 1. STRUCTURAL.
  final Text widget = tester.widget<Text>(finder);
  expect(
    widget.maxLines,
    isNull,
    reason:
        'NO TRUNCATION: «$text»$where must carry no maxLines — it wraps. '
        'If it does not fit, fix the layout, never add an ellipsis.',
  );
  expect(
    widget.overflow,
    isNot(TextOverflow.ellipsis),
    reason:
        'NO TRUNCATION: «$text»$where must carry no TextOverflow.ellipsis. '
        'This is the original «Шев…» bug.',
  );

  // 2. RENDERED — ground truth, independent of the widget's own fields.
  final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: finder, matching: find.byType(RichText)),
  );
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason:
        'NO TRUNCATION: the laid-out paragraph for «$text»$where dropped at '
        'least one line. Something upstream is imposing a maxLines.',
  );

  // 3. FITS ITS BOX — the unbreakable-word case, which never ellipsises and
  //    never trips the RenderFlex overflow guard; it just paints outside.
  final BoxConstraints constraints = paragraph.constraints;
  if (constraints.hasBoundedWidth) {
    expect(
      paragraph.size.width,
      lessThanOrEqualTo(constraints.maxWidth + 0.5),
      reason:
          'NO TRUNCATION: «$text»$where laid out '
          '${paragraph.size.width.toStringAsFixed(1)} dp wide inside a '
          '${constraints.maxWidth.toStringAsFixed(1)} dp box — it is painting '
          'outside its bounds. A word wider than its column cannot ellipsise, '
          'so this failure is invisible on screen and only measurable here.',
    );
  }
}

/// Pumps [child] under the page's own horizontal padding at [width], so the
/// widget receives the constraint it gets in production rather than the raw
/// surface width.
Future<void> _pumpAtPageWidth(
  WidgetTester tester,
  Widget child, {
  required double width,
  List<Object> overrides = const <Object>[],
}) {
  return tester.pumpApp(
    Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
          child: child,
        ),
      ),
    ),
    width: width,
    overrides: overrides,
  );
}

void main() {
  for (final double width in kWidths) {
    group('NO TRUNCATION at ${width.toInt()} dp', () {
      testWidgets(
        'should_wrapServiceAndMasterName_when_compactCardsAtWorstCase',
        (WidgetTester tester) async {
          await _pumpAtPageWidth(
            tester,
            WishlistSection(
              onBook: (_) {},
              onFindMaster: () {},
              onShowAll: () {},
            ),
            width: width,
            overrides: <Object>[
              wishlistRepositoryProvider.overrideWithValue(
                FakeWishlistRepository(services: _worstCase),
              ),
            ],
          );
          await tester.pumpAndSettle();

          // Both cards carry the same names, so each string appears twice —
          // check the FIRST card's copies via a scoped finder.
          for (final String fixture in <String>[kLongService, kLongMaster]) {
            // i18n-finder-ok: fixture DATA, not UI copy — see
            // expectRendersWhole's own annotation.
            final Finder all = find.text(fixture);
            expect(
              all,
              findsNWidgets(2),
              reason: 'both compact cards render «$fixture»',
            );
            for (int i = 0; i < 2; i++) {
              final Text widget = tester.widget<Text>(all.at(i));
              expect(
                widget.maxLines,
                isNull,
                reason: 'NO TRUNCATION: «$fixture» on compact card $i',
              );
              expect(
                widget.overflow,
                isNot(TextOverflow.ellipsis),
                reason: 'NO TRUNCATION: «$fixture» on compact card $i',
              );
              final RenderParagraph paragraph = tester
                  .renderObject<RenderParagraph>(
                    find.descendant(
                      of: all.at(i),
                      matching: find.byType(RichText),
                    ),
                  );
              expect(
                paragraph.didExceedMaxLines,
                isFalse,
                reason: 'NO TRUNCATION: «$fixture» on compact card $i',
              );
              final BoxConstraints c = paragraph.constraints;
              if (c.hasBoundedWidth) {
                expect(
                  paragraph.size.width,
                  lessThanOrEqualTo(c.maxWidth + 0.5),
                  reason:
                      'NO TRUNCATION: «$fixture» paints outside its box on '
                      'compact card $i — laid out '
                      '${paragraph.size.width.toStringAsFixed(1)} dp inside '
                      '${c.maxWidth.toStringAsFixed(1)} dp',
                );
              }
            }
          }
        },
      );

      testWidgets('should_wrapServiceAndMasterName_when_fullWidthRow', (
        WidgetTester tester,
      ) async {
        await _pumpAtPageWidth(
          tester,
          WishlistRow(
            item: _entry(id: 'w1'),
            onBook: () {},
            onUnfavourite: () {},
          ),
          width: width,
        );
        await tester.pumpAndSettle();

        expectRendersWhole(tester, kLongService, at: 'WishlistRow');
        expectRendersWhole(tester, kLongMaster, at: 'WishlistRow');
      });

      testWidgets('should_wrapNotTruncate_when_districtIsShevchenkivskyi', (
        WidgetTester tester,
      ) async {
        await _pumpAtPageWidth(
          tester,
          const PassportDerivedBlock(
            districts: <String>[kLongDistrict, kSecondDistrict, kThirdDistrict],
            cities: <String>['Київ', kCity],
            averageSpend: '750 ₴',
          ),
          width: width,
        );
        await tester.pumpAndSettle();

        // THE original bug, at both widths.
        expectRendersWhole(tester, kLongDistrict, at: 'derived block');
        expectRendersWhole(tester, kSecondDistrict, at: 'derived block');
        expectRendersWhole(tester, kThirdDistrict, at: 'derived block');
        expectRendersWhole(tester, kCity, at: 'derived block');
      });
    });
  }

  group('NO TRUNCATION — the rule holds structurally, not by budget', () {
    testWidgets(
      'should_carryNoMaxLinesAnywhere_except_thePriceTagsOwnFittedBox',
      (WidgetTester tester) async {
        // A sweep rather than a per-fixture check: it catches a `maxLines`
        // added to a NAME slot this file does not name a fixture for.
        //
        // Three families are legitimately exempt and are subtracted explicitly
        // rather than tolerated by a loose matcher:
        //   * PriceTag's inner Text — `maxLines: 1` under a `FittedBox`, which
        //     SCALES the band down rather than clipping it. Documented in
        //     `price_tag.dart`.
        //   * HubFilledButton / HubOutlineButton labels — same FittedBox
        //     treatment, and a CTA label is fixed app copy, not user content.
        await _pumpAtPageWidth(
          tester,
          WishlistRow(
            item: _entry(
              id: 'w1',
              isRange: true,
              priceMin: 700,
              priceMax: 1100,
            ),
            onBook: () {},
            onUnfavourite: () {},
          ),
          width: 320,
        );
        await tester.pumpAndSettle();

        final Finder priceTexts = find.descendant(
          of: find.byType(PriceTag),
          matching: find.byType(Text),
        );
        final Finder buttonTexts = find.descendant(
          of: find.byType(FittedBox),
          matching: find.byType(Text),
        );
        final Set<Element> exempt = <Element>{
          ...priceTexts.evaluate(),
          ...buttonTexts.evaluate(),
        };

        for (final Element element in find.byType(Text).evaluate()) {
          if (exempt.contains(element)) continue;
          final Text widget = element.widget as Text;
          expect(
            widget.maxLines,
            isNull,
            reason:
                'NO TRUNCATION: «${widget.data}» carries maxLines='
                '${widget.maxLines}. Content text on the wish-list surfaces '
                'wraps; only PriceTag and CTA labels may cap lines, and both '
                'do it under a FittedBox that SCALES rather than clips.',
          );
          expect(
            widget.overflow,
            isNot(TextOverflow.ellipsis),
            reason:
                'NO TRUNCATION: «${widget.data}» carries '
                'TextOverflow.ellipsis. This is the original «Шев…» bug.',
          );
        }
      },
    );
  });

  group('RANGE prices render the app band, not the backend long form', () {
    testWidgets('should_renderEnDashBand_when_priceTypeIsRange', (
      WidgetTester tester,
    ) async {
      // The USER DECISION behind `WishlistService.priceLabel`: the backend
      // sends «від 700 до 1 100 ₴», which measures ~138 dp against the compact
      // card's 126 dp. The client re-formats RANGE through the SHARED
      // `formatBookingPrice`, so the pill shows the app's own en-dash band.
      await _pumpAtPageWidth(
        tester,
        WishlistRow(
          item: _entry(
            id: 'w2',
            isRange: true,
            priceMin: 700,
            priceMax: 1100,
            priceDisplay: 'від 700 до 1 100 ₴',
          ),
          onBook: () {},
          onUnfavourite: () {},
        ),
        width: 320,
      );
      await tester.pumpAndSettle();

      // i18n-finder-ok: money strings — data, identical in every locale.
      expect(find.text('700–1100 ₴'), findsOneWidget);
      // i18n-finder-ok: the backend long form must NOT reach the pill.
      expect(find.text('від 700 до 1 100 ₴'), findsNothing);
    });

    testWidgets('should_passPriceDisplayThrough_when_priceTypeIsFixed', (
      WidgetTester tester,
    ) async {
      await _pumpAtPageWidth(
        tester,
        WishlistRow(
          item: _entry(id: 'w1', priceDisplay: '1 200 ₴'),
          onBook: () {},
          onUnfavourite: () {},
        ),
        width: 320,
      );
      await tester.pumpAndSettle();

      // i18n-finder-ok: money string — data, identical in every locale.
      expect(find.text('1 200 ₴'), findsOneWidget);
    });
  });
}
