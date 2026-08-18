// Phase 224 audit fix (mobile-perf MEDIUM) — the measurement/render agreement
// test for [MasterAddressBlock].
//
// WHAT DEFECT THIS FILE EXISTS TO CATCH
// -------------------------------------
// `MasterAddressBlock` promises, in its own class doc, that it only collapses
// the address onto one line when "the string fits whole and nothing is
// clipped". It keeps that promise by laying out a `TextPainter` and reading
// `didExceedMaxLines`. That promise is only as good as the painter's INPUT: a
// `Text` whose `style.inherit` is true renders
// `DefaultTextStyle.of(context).style.merge(style)`, NOT the raw style, and
// the ambient default here is Material 3 `bodyMedium`, which carries
// `letterSpacing: 0.25`. Measuring with the raw `VelvetText.feedbackMutedXs`
// (which sets no `letterSpacing`, so the merge keeps 0.25) undercounted the
// string by `0.25 × glyphCount` — enough to classify a real address as
// "fits", collapse it, and then ellipsize it for real, silently dropping the
// building number.
//
// WHY THIS TEST IS NOT SELF-REFERENTIAL
// -------------------------------------
// A test that re-runs the widget's own `TextPainter` with the widget's own
// style and asserts they agree proves nothing — it is the implementation
// checked against itself. So:
//   - the `TextPainter`s below are used ONLY to CHOOSE the fixture width and
//     to establish the CONTROL (that the raw style and the effective style
//     genuinely disagree at that width, i.e. the pre-fix code WOULD have
//     collapsed here — asserted, not assumed);
//   - every pass/fail assertion reads the REAL `RenderParagraph` out of the
//     laid-out tree and asks it whether it actually overflowed. That is
//     ground truth produced by the same engine that paints pixels, not a
//     re-derivation of the decision under test.
//
// The ambient style is read out of the live tree rather than hard-coded, so
// the test tracks whatever Material actually installs instead of pinning a
// framework constant that could drift.

import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/master_address_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The three content-scoped keys the block can render.
const Key _combinedKey = Key('fixture-address-combined-text');
const Key _localityKey = Key('fixture-locality-text');
const Key _streetKey = Key('fixture-address-text');

const String _city = 'Київ';
const String _street = 'вул. Хрещатик';
const String _building = '22';
const String _combined = 'Київ, вул. Хрещатик, 22';

/// Pumps the block inside a real `MaterialApp` + `Scaffold` — the `Material`
/// is what installs `theme.textTheme.bodyMedium` as the ambient
/// `DefaultTextStyle`, which is exactly the input the block must account for.
/// The block is given EXACTLY [width] logical pixels, the same way the
/// identity card's `Expanded` column constrains it in production.
Future<void> _pumpAt(WidgetTester tester, double width) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: const MasterAddressBlock(
              keyPrefix: 'fixture',
              icon: SizedBox(
                width: MasterAddressBlock.iconSize,
                height: MasterAddressBlock.iconSize,
              ),
              localityLine: _city,
              streetLine: '$_street, $_building',
              combinedLine: _combined,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The ambient `DefaultTextStyle` the block sees, read from the LIVE tree.
TextStyle _ambientStyle(WidgetTester tester) =>
    DefaultTextStyle.of(tester.element(find.byType(MasterAddressBlock))).style;

/// Unconstrained rendered width of [_combined] at [style].
double _measure(TextStyle style) {
  final TextPainter painter = TextPainter(
    text: TextSpan(text: _combined, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  );
  try {
    painter.layout();
    return painter.width;
  } finally {
    painter.dispose();
  }
}

/// GROUND TRUTH — whether the paragraph behind [key] actually overflowed its
/// line budget in the laid-out tree. Not a re-measurement: this is the render
/// object the engine painted.
bool _overflowed(WidgetTester tester, Key key) =>
    tester.renderObject<RenderParagraph>(find.byKey(key)).didExceedMaxLines;

void main() {
  group('MasterAddressBlock — the collapsed path never over-promises', () {
    testWidgets(
      'refuses to collapse at a width where the RAW style would have said '
      '"fits" but the EFFECTIVE (ambient-merged) style does not',
      (WidgetTester tester) async {
        // Prime the tree once at a generous width just to read the ambient
        // style the block will actually resolve against.
        await _pumpAt(tester, 1000);
        final TextStyle ambient = _ambientStyle(tester);
        final TextStyle effective = ambient.merge(VelvetText.feedbackMutedXs);

        // CONTROL 1 — the two styles must genuinely differ, otherwise this
        // whole test is vacuous and would silently stop guarding anything.
        expect(
          effective.letterSpacing,
          isNot(VelvetText.feedbackMutedXs.letterSpacing),
          reason:
              'the ambient DefaultTextStyle no longer contributes a '
              'letterSpacing — this test can no longer distinguish the raw '
              'style from the effective one and must be re-based on whatever '
              'property now differs',
        );

        final double rawWidth = _measure(VelvetText.feedbackMutedXs);
        final double effectiveWidth = _measure(effective);

        // CONTROL 2 — the effective render is genuinely WIDER, so a band of
        // widths exists where the raw measurement lies.
        expect(
          effectiveWidth,
          greaterThan(rawWidth + 1),
          reason: 'no disagreement band exists to test at',
        );

        // Pick a width squarely inside that band: the text column gets just
        // over the raw width, still well under the effective width. The pin
        // and its gap are outside the text column, so add them back — from the
        // block's OWN constants, never mirrored literals. A mirrored gap would
        // not fail this test if the widget changed it; it would silently move
        // the fixture width off the disagreement band and keep passing while
        // proving nothing.
        final double blockWidth =
            rawWidth +
            MasterAddressBlock.iconSize +
            MasterAddressBlock.iconGap +
            0.5;
        await _pumpAt(tester, blockWidth);

        // THE ASSERTION — the block must have kept the split. Before the fix
        // it collapsed here (control 1 + 2 prove the raw measurement said
        // "fits") and clipped the building number off the end.
        expect(
          find.byKey(_combinedKey),
          findsNothing,
          reason:
              'collapsed at a width where the real render cannot fit the '
              'whole string — the measurement used a different style than '
              'the render',
        );
        expect(find.byKey(_localityKey), findsOneWidget);
        expect(find.byKey(_streetKey), findsOneWidget);

        // And the fallback itself must not be clipping the locality row.
        expect(_overflowed(tester, _localityKey), isFalse);
      },
    );

    testWidgets(
      'across a sweep of widths, WHENEVER the block collapses, the real '
      'paragraph is not ellipsized — the class-doc contract, checked against '
      'the render tree rather than against the measurement',
      (WidgetTester tester) async {
        await _pumpAt(tester, 1000);
        final TextStyle effective = _ambientStyle(
          tester,
        ).merge(VelvetText.feedbackMutedXs);
        final double effectiveWidth = _measure(effective);

        // Sweep the whole decision boundary — from far too narrow to
        // comfortably wide — in 2 px steps, so the exact crossover width is
        // covered without the test having to know where it is.
        bool sawCollapse = false;
        bool sawSplit = false;
        for (
          double width = effectiveWidth - 40;
          width <= effectiveWidth + 40;
          width += 2
        ) {
          await _pumpAt(tester, width);
          final bool collapsed = find.byKey(_combinedKey).evaluate().isNotEmpty;
          if (collapsed) {
            sawCollapse = true;
            expect(
              _overflowed(tester, _combinedKey),
              isFalse,
              reason:
                  'collapsed at ${width.toStringAsFixed(1)}px but the '
                  'rendered paragraph overflowed its single line — the '
                  'address was silently truncated',
            );
            // Exclusive paths: the split rows must be gone.
            expect(find.byKey(_localityKey), findsNothing);
          } else {
            sawSplit = true;
            expect(find.byKey(_localityKey), findsOneWidget);
            expect(find.byKey(_streetKey), findsOneWidget);
          }
        }

        // The sweep must have straddled the boundary, otherwise it proved
        // nothing about the decision.
        expect(sawCollapse, isTrue, reason: 'sweep never reached a collapse');
        expect(sawSplit, isTrue, reason: 'sweep never reached a split');
      },
    );

    testWidgets(
      'renders the EFFECTIVE style on the Text, so the style that was '
      'measured is the style that paints',
      (WidgetTester tester) async {
        await _pumpAt(tester, 1000);
        final TextStyle effective = _ambientStyle(
          tester,
        ).merge(VelvetText.feedbackMutedXs);

        final Text combined = tester.widget<Text>(find.byKey(_combinedKey));
        expect(combined.style, effective);
        // The VelvetText identity must survive the merge — the ambient style
        // contributes only what feedbackMutedXs leaves unset.
        expect(combined.style?.fontSize, VelvetText.feedbackMutedXs.fontSize);
        expect(
          combined.style?.fontWeight,
          VelvetText.feedbackMutedXs.fontWeight,
        );
        expect(combined.style?.color, VelvetText.feedbackMutedXs.color);
      },
    );

    testWidgets('a degenerate (zero-width) column keeps the split rather than '
        'collapsing into a clipped line', (WidgetTester tester) async {
      await _pumpAt(tester, 0);
      expect(find.byKey(_combinedKey), findsNothing);
      expect(find.byKey(_localityKey), findsOneWidget);
    });
  });
}
