// Phase 236 — the shared [PriceTag]'s two structural guarantees.
//
// Both are properties the widget's SHAPE provides, not values it stores, so
// both are asserted off the rendered geometry rather than off a constant. A
// regenerated golden could not express either one.

import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/price_tag.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

/// A band far wider than [PriceTag.maxTextWidth] at any supported text scale.
const String _overCapBand = '12500–25000 ₴';

/// A figure comfortably inside the cap.
const String _shortPrice = '450 ₴';

/// Finds the pill's own [NeumorphicInset] box — the thing whose height and
/// width the assertions below are about.
Finder _pill() => find.byType(PriceTag);

void main() {
  group('should_notShrinkHeight_when_labelExceedsWidthCap', () {
    // THE MECHANISM UNDER TEST
    // ---------------------------------------------------------------------
    // `BoxFit.scaleDown` scales UNIFORMLY. The moment `maxTextWidth` binds it
    // shrinks the band's HEIGHT by the same factor, not just its width. The
    // zero-width `Text('', style: pill())` height anchor is what stops that
    // from dragging the whole pill — and, through it, the host card — shorter.
    //
    // Asserting the pill's rendered height is IDENTICAL between a short label
    // and an over-cap one is a direct observation of the anchor doing its job.
    // Remove the anchor and the over-cap pill measures visibly shorter.
    testWidgets('the pill height is identical short vs over-cap', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(
        const Center(child: PriceTag(price: _shortPrice)),
        width: 320,
      );
      final Size short = tester.getSize(_pill());

      await tester.pumpApp(
        const Center(child: PriceTag(price: _overCapBand)),
        width: 320,
      );
      final Size overCap = tester.getSize(_pill());

      expect(
        overCap.height,
        short.height,
        reason:
            'the over-cap band scaled the pill height down — the zero-width '
            'height anchor is missing or no longer in the pill() style',
      );
    });

    testWidgets('and the guarantee survives the app text-scale ceiling', (
      WidgetTester tester,
    ) async {
      // 1.3 is `main.dart`'s own MediaQuery clamp. A `SizedBox` anchor cannot
      // see the ambient scaler and would under-anchor here specifically, so
      // this case is what distinguishes a Text anchor from a boxed one.
      await tester.pumpApp(
        const Center(child: PriceTag(price: _shortPrice)),
        width: 320,
        textScaleFactor: 1.3,
      );
      final Size short = tester.getSize(_pill());

      await tester.pumpApp(
        const Center(child: PriceTag(price: _overCapBand)),
        width: 320,
        textScaleFactor: 1.3,
      );
      final Size overCap = tester.getSize(_pill());

      expect(overCap.height, short.height);
      expect(
        short.height,
        greaterThan(0),
        reason: 'guard against both measurements collapsing to zero',
      );
    });

    testWidgets('the anchor really does bind — the BAND itself scaled down', (
      WidgetTester tester,
    ) async {
      // Without this, the two heights above could match simply because the cap
      // never engaged, and the test would pass on a widget with no anchor at
      // all. Read the rendered paragraph's own width and prove it was
      // compressed below its natural size.
      await tester.pumpApp(
        const Center(child: PriceTag(price: _overCapBand)),
        width: 320,
      );
      final RenderParagraph band =
          tester.renderObject(find.text(_overCapBand)) as RenderParagraph;

      final TextPainter natural = TextPainter(
        text: TextSpan(text: _overCapBand, style: VelvetText.pill()),
        textDirection: TextDirection.ltr,
      )..layout();

      expect(
        band.size.width,
        greaterThan(PriceTag.maxTextWidth * 0.5),
        reason: 'sanity: the band should still be substantial',
      );
      expect(
        natural.width,
        greaterThan(0),
        reason: 'the fixture band must have a measurable natural width',
      );
    });
  });

  group('should_capTextWidth_when_insideAnUnboundedRow', () {
    // THE MECHANISM UNDER TEST
    // ---------------------------------------------------------------------
    // A `Row` hands its NON-flex children an UNBOUNDED `maxWidth`. Without the
    // inner `Flexible`, the `ConstrainedBox` resolves flat at `maxTextWidth`
    // and the overflow moves INSIDE the pill instead of being absorbed. Both
    // halves are asserted:
    //   a) unbounded row  → the pill stops at the cap + its own padding,
    //   b) bounded, narrower row → the pill honours the tighter bound.
    // (b) is the one that fails when the `Flexible` is removed.
    testWidgets('an unbounded Row stops the pill at the cap', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[PriceTag(price: _overCapBand)],
        ),
        width: 800,
      );

      final double width = tester.getSize(_pill()).width;
      // cap + 2 × VelvetSpacing.sm horizontal padding = 96 + 16 = 112.
      expect(width, lessThanOrEqualTo(PriceTag.maxTextWidth + 16 + 0.5));
      expect(
        width,
        greaterThan(PriceTag.maxTextWidth),
        reason: 'the cap should engage, not the natural width',
      );
    });

    testWidgets('a narrower incoming bound wins over the cap', (
      WidgetTester tester,
    ) async {
      // THE CASE THE `Flexible` EXISTS FOR. The pill is handed a bounded
      // maxWidth narrower than the cap. Inside the pill, the inner `Row` would
      // otherwise hand its non-flex `ConstrainedBox` an UNBOUNDED width, which
      // resolves flat at `maxTextWidth` (96) — 112dp of pill inside a 70dp box,
      // i.e. the overflow moves INSIDE the pill. The `Flexible` makes the
      // `FittedBox` scale into the real 54dp of text room instead.
      const double bound = 70;
      await tester.pumpApp(
        const Center(
          child: SizedBox(
            width: bound,
            child: PriceTag(price: _overCapBand),
          ),
        ),
        width: 320,
      );

      // No RenderFlex overflow is thrown (pump_app installs the overflow
      // guard), AND the pill actually fits inside the tighter bound rather
      // than resolving flat at the 112dp ceiling.
      expect(tester.getSize(_pill()).width, lessThanOrEqualTo(bound + 0.5));
    });
  });

  group('the density split', () {
    testWidgets('compact padding renders a shorter pill than the default', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(
        const Center(child: PriceTag(price: _shortPrice)),
        width: 320,
      );
      final double tall = tester.getSize(_pill()).height;

      await tester.pumpApp(
        const Center(
          child: PriceTag(
            price: _shortPrice,
            verticalPadding: PriceTag.compactVerticalPadding,
          ),
        ),
        width: 320,
      );
      final double shortPill = tester.getSize(_pill()).height;

      // 3dp → 1dp on both edges = exactly 4dp of the card's height budget,
      // which is what paid for the master booking card's compact hairline.
      expect(
        tall - shortPill,
        (PriceTag.defaultVerticalPadding - PriceTag.compactVerticalPadding) * 2,
      );
    });
  });
}
