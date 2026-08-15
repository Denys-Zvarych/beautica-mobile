// mobile-qa — 2026-08-15 booking-card font-size pass, regression coverage.
//
// [PriceTag] grew an optional `style` field so `master_booking_card.dart`
// could shrink its OWN price figure (`VelvetText.masterCardPricePill`,
// 10.2 sp) without moving the shared `VelvetText.pill()` (11 sp) that
// `wishlist_row.dart`, `wishlist_compact_card.dart` and
// `passport_derived_block.dart` also render through this exact widget — see
// `price_tag.dart`'s `style` field doc and `velvet_text.dart`'s
// `masterCardPricePill` doc.
//
// NOTHING pinned the new knob before this file: `price_tag_test.dart` never
// constructs a `PriceTag` with `style:` at all, and no test anywhere asserts
// the DEFAULT (`style: null`) path resolves to `pill()`'s literal numbers
// rather than to some other cached style that happens to look similar.
//
// Every assertion below is a REAL RENDER measurement — `tester.getSize` on
// the mounted `PriceTag` and the framework's own resolved `RenderParagraph`
// style — never arithmetic recomputed from the `VelvetText` tokens. A
// self-referential assertion (comparing the render to the very token it is
// supposed to prove renders) cannot catch a token/call-site mismatch; these
// compare the render to independently-known LITERAL numbers instead.

import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/price_tag.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

const String _price = '450 ₴';

void main() {
  group('PriceTag.style — the default (null) path renders pill() verbatim', () {
    testWidgets('no style, default padding — the pill measures 21dp '
        '(VelvetText.pill()\'s 15dp natural line + 3dp padding × 2), the '
        'PRE-2026-08-15-pass figure every non-booking-card consumer must still '
        'render', (WidgetTester tester) async {
      await tester.pumpApp(
        const Center(child: PriceTag(price: _price)),
        width: 320,
      );

      final double height = tester.getSize(find.byType(PriceTag)).height;
      expect(
        height,
        21,
        reason:
            'PriceTag() with no style measured ${height}dp — it must stay '
            'at the pre-pass 21dp (pill()\'s 15dp line + defaultVerticalPadding '
            '3dp × 2). wishlist_row.dart and passport_derived_block.dart both '
            'render a bare PriceTag(price: …) and must be byte-identical to '
            'before the 2026-08-15 booking-card font-size pass.',
      );

      final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
        find.text(_price),
      );
      expect(
        paragraph.text.style?.fontSize,
        11,
        reason:
            'the visible price text must paint at pill()\'s literal 11sp, '
            'not masterCardPricePill\'s 10.2sp — a regression here would '
            'shrink every wish-list/passport price pill along with the '
            'booking card\'s, which this pass explicitly did not intend.',
      );
    });

    testWidgets(
      'no style, COMPACT padding — the pill measures 17dp, the exact figure '
      'wishlist_compact_card.dart renders (verticalPadding: '
      'compactVerticalPadding, no style override)',
      (WidgetTester tester) async {
        await tester.pumpApp(
          const Center(
            child: PriceTag(
              price: _price,
              verticalPadding: PriceTag.compactVerticalPadding,
            ),
          ),
          width: 320,
        );

        final double height = tester.getSize(find.byType(PriceTag)).height;
        expect(
          height,
          17,
          reason:
              'PriceTag(verticalPadding: compactVerticalPadding) with no '
              'style measured ${height}dp — pill()\'s 15dp line + 1dp × 2. '
              'wishlist_compact_card.dart depends on exactly this figure.',
        );
      },
    );
  });

  group('PriceTag.style — an explicit override moves BOTH the height anchor '
      'and the visible text', () {
    testWidgets(
      'style: masterCardPricePill shrinks the default-padding pill to 20dp '
      'and the painted text to 10.2sp — the booking card\'s own figure',
      (WidgetTester tester) async {
        await tester.pumpApp(
          Center(
            child: PriceTag(
              price: _price,
              style: VelvetText.masterCardPricePill,
            ),
          ),
          width: 320,
        );

        final double height = tester.getSize(find.byType(PriceTag)).height;
        expect(
          height,
          20,
          reason:
              'PriceTag(style: masterCardPricePill) at the default 3dp '
              'padding measured ${height}dp — it must be 14dp line + 3×2, '
              'matching master_booking_card.dart\'s FULL-layout pill.',
        );

        final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
          find.text(_price),
        );
        expect(paragraph.text.style?.fontSize, 10.2);
      },
    );

    testWidgets(
      'style: masterCardPricePill at COMPACT padding measures 16dp — the '
      'booking card\'s own COMPACT-layout figure',
      (WidgetTester tester) async {
        await tester.pumpApp(
          Center(
            child: PriceTag(
              price: _price,
              style: VelvetText.masterCardPricePill,
              verticalPadding: PriceTag.compactVerticalPadding,
            ),
          ),
          width: 320,
        );

        final double height = tester.getSize(find.byType(PriceTag)).height;
        expect(height, 16);
      },
    );

    testWidgets(
      'MUTATION CHECK — the anchor and the visible text must move TOGETHER: '
      'an override that reached only the visible Text (not the zero-width '
      'height anchor) would still shrink the painted glyphs\' fontSize while '
      'the box stayed 21dp',
      (WidgetTester tester) async {
        await tester.pumpApp(
          Center(
            child: PriceTag(
              price: _price,
              style: VelvetText.masterCardPricePill,
            ),
          ),
          width: 320,
        );

        final double height = tester.getSize(find.byType(PriceTag)).height;
        final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
          find.text(_price),
        );

        // Both signals of "the override took" must agree — a real defect (the
        // style reaching only one of the two Text widgets PriceTag builds)
        // would fail exactly one of these two expectations, not both.
        expect(
          paragraph.text.style?.fontSize,
          lessThan(11),
          reason: 'the visible text did not pick up the override at all',
        );
        expect(
          height,
          lessThan(21),
          reason:
              'the visible text shrank but the height anchor did not follow '
              'it — the box would still measure the OLD 21dp default while '
              'painting smaller glyphs inside it, a visible mismatch',
        );
      },
    );
  });
}
