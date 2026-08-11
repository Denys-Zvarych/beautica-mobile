// Phase 236 — [HubOutlineButton].
//
// The one property that matters is the one the approved design argues for: it
// must read as an OVERFLOW control, not as a second primary action beside the
// camel-filled «Записатись». That is a fill-and-stroke difference, so it is
// asserted off the rendered decoration rather than off a screenshot.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/hub_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

BoxDecoration _decorationOf(WidgetTester tester, Type buttonType) {
  final Container box = tester.widget<Container>(
    find
        .descendant(
          of: find.byType(buttonType),
          matching: find.byType(Container),
        )
        .first,
  );
  return box.decoration! as BoxDecoration;
}

void main() {
  group('should_renderOutlineNotFilled_when_hubOutlineButton', () {
    testWidgets('it draws a stroke and a near-transparent face', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(
        Center(
          child: SizedBox(
            width: 200,
            child: HubOutlineButton(label: 'Показати всі (5)', onTap: () {}),
          ),
        ),
        width: 320,
      );

      final BoxDecoration d = _decorationOf(tester, HubOutlineButton);

      expect(d.border, isNotNull, reason: 'an outline button must be stroked');
      final BorderSide side = (d.border! as Border).top;
      expect(side.color.r, closeTo(BrandColors.accentDeep.r, 0.001));
      expect(side.color.g, closeTo(BrandColors.accentDeep.g, 0.001));
      expect(side.color.b, closeTo(BrandColors.accentDeep.b, 0.001));
      expect(
        side.color.a,
        lessThan(1.0),
        reason: 'the stroke is alpha-attenuated, not solid mocha',
      );

      // The face is a cream wash, NOT the camel fill the filled button uses.
      expect(d.color, isNotNull);
      expect(
        d.color!.a,
        lessThan(1.0),
        reason: 'a fully opaque face would read as a filled button',
      );
      expect(
        d.color!.r == BrandColors.accent.r &&
            d.color!.g == BrandColors.accent.g &&
            d.color!.b == BrandColors.accent.b,
        isFalse,
        reason: 'the outline variant must not wear the camel CTA fill',
      );
    });

    testWidgets('the FILLED sibling is the opposite — solid camel, no stroke', (
      WidgetTester tester,
    ) async {
      // The distinction is only meaningful as a CONTRAST, so the filled button
      // is measured in the same run rather than assumed.
      await tester.pumpApp(
        Center(
          child: SizedBox(
            width: 200,
            child: HubFilledButton(label: 'Записатись', onTap: () {}),
          ),
        ),
        width: 320,
      );

      final BoxDecoration d = _decorationOf(tester, HubFilledButton);
      expect(d.border, isNull);
      // The filled button wears the locked camel→mocha CTA gradient, not a
      // flat fill — see `hub_widgets.dart`'s `_decoration` for why a flat
      // `BrandColors.accent` fill read as disabled.
      expect(d.color, isNull);
      final Gradient? gradient = d.gradient;
      expect(gradient, isA<LinearGradient>());
      final LinearGradient linear = gradient! as LinearGradient;
      expect(linear.colors, <Color>[
        BrandColors.accentLatte,
        BrandColors.accentDeep,
      ]);
    });

    testWidgets('both share one footprint — same height and radius', (
      WidgetTester tester,
    ) async {
      // A one-pixel difference between the two reads as a mistake, not as
      // hierarchy: they stack directly on top of each other in the section.
      await tester.pumpApp(
        Center(
          child: SizedBox(
            width: 200,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                HubFilledButton(label: 'Записатись', onTap: () {}),
                HubOutlineButton(label: 'Показати всі (5)', onTap: () {}),
              ],
            ),
          ),
        ),
        width: 320,
      );

      // mobile-security (HIGH, tap-target fix): both buttons now carry the
      // IDENTICAL invisible `Padding` that grows their interactive area to
      // the shared 48dp accessibility floor (`_kMinTapExtent`/`_kTapPad` in
      // `hub_widgets.dart`), so the OUTER rects — not just the painted
      // pills — share a height again, restoring the original invariant this
      // test existed to pin: a one-pixel difference between the two reads
      // as a mistake, not as hierarchy.
      expect(
        tester.getSize(find.byType(HubOutlineButton)).height,
        tester.getSize(find.byType(HubFilledButton)).height,
      );
      // The PAINTED pill each one draws must also still match.
      expect(
        tester
            .getSize(
              find
                  .descendant(
                    of: find.byType(HubOutlineButton),
                    matching: find.byType(Container),
                  )
                  .first,
            )
            .height,
        tester
            .getSize(
              find
                  .descendant(
                    of: find.byType(HubFilledButton),
                    matching: find.byType(Container),
                  )
                  .first,
            )
            .height,
      );
      expect(
        (_decorationOf(tester, HubOutlineButton).borderRadius! as BorderRadius)
            .topLeft,
        (_decorationOf(tester, HubFilledButton).borderRadius! as BorderRadius)
            .topLeft,
      );
    });
  });

  group('should_insetLabelFromEdges_when_hubFilledButton', () {
    // mobile-qa (2026-08-10): pins the SECOND half of the original bug report
    // — «Обрати майстра» "spanned the whole button" — which nothing in this
    // suite asserted directly before now. `hub_filled_button_contrast_test
    // .dart` measures the gradient colour under the label's rendered rect but
    // never checks that the rect is INSET from the button's own edges; the
    // wishlist overflow suite only pins an exact total button WIDTH for one
    // WishlistRow fixture, which is a width check, not a margin check, and
    // says nothing about `WishlistCompactCard` (the passport surface the
    // report was actually about) since that consumer passes no width bound at
    // all. `HubFilledButton`'s padding is shared by every consumer, so one
    // direct assertion here — inside `IntrinsicWidth` so `FittedBox` is not
    // scaling anything down — covers all of them without duplicating a
    // per-consumer copy.
    //
    // MUTATION PROOF: with `hub_widgets.dart`'s `padding: const EdgeInsets
    // .symmetric(horizontal: VelvetSpacing.md)` reverted to `EdgeInsets.zero`,
    // both margins below measure ~0 and this test fails; restoring the
    // padding makes it pass again.
    for (final String label in <String>[
      'Записатись', // i18n-const-ok: mirrors wishlistBookCta verbatim.
      'Обрати майстра', // i18n-const-ok: mirrors wishlistChooseMasterCta.
    ]) {
      testWidgets(
        'label «$label» keeps VelvetSpacing.md of breathing room on both '
        'sides, not edge-to-edge',
        (tester) async {
          await tester.pumpApp(
            Center(
              child: IntrinsicWidth(
                child: HubFilledButton(label: label, onTap: () {}),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final Rect buttonRect = tester.getRect(find.byType(HubFilledButton));
          final Rect labelRect = tester.getRect(find.text(label));

          final double leftMargin = labelRect.left - buttonRect.left;
          final double rightMargin = buttonRect.right - labelRect.right;

          expect(
            leftMargin,
            moreOrLessEquals(VelvetSpacing.md, epsilon: 0.5),
            reason:
                'left margin was $leftMargin — the label must sit '
                'VelvetSpacing.md (${VelvetSpacing.md}dp) in from the '
                "button's edge, not flush against it",
          );
          expect(
            rightMargin,
            moreOrLessEquals(VelvetSpacing.md, epsilon: 0.5),
            reason:
                'right margin was $rightMargin — the label must sit '
                'VelvetSpacing.md (${VelvetSpacing.md}dp) in from the '
                "button's edge, not flush against it",
          );
        },
      );
    }
  });

  testWidgets('danger swaps the foreground to error red', (
    WidgetTester tester,
  ) async {
    await tester.pumpApp(
      Center(
        child: SizedBox(
          width: 200,
          child: HubOutlineButton(
            label: 'Скасувати',
            onTap: () {},
            danger: true,
          ),
        ),
      ),
      width: 320,
    );

    final BorderSide side =
        (_decorationOf(tester, HubOutlineButton).border! as Border).top;
    expect(side.color.r, closeTo(BrandColors.error.r, 0.001));
    expect(side.color.g, closeTo(BrandColors.error.g, 0.001));
    expect(side.color.b, closeTo(BrandColors.error.b, 0.001));

    // Located by TYPE inside the button, not by its Cyrillic copy: a
    // `find.text('Скасувати')` would become a findsNothing failure the day EN
    // ships, and the property under test is the label's COLOUR, not its words.
    final Text label = tester.widget<Text>(
      find
          .descendant(
            of: find.byType(HubOutlineButton),
            matching: find.byType(Text),
          )
          .first,
    );
    expect(label.style!.color, BrandColors.error);
  });

  testWidgets('it fires onTap and announces itself as a button', (
    WidgetTester tester,
  ) async {
    int taps = 0;
    await tester.pumpApp(
      Center(
        child: SizedBox(
          width: 200,
          child: HubOutlineButton(
            label: 'Показати всі (5)',
            onTap: () => taps++,
          ),
        ),
      ),
      width: 320,
    );

    await tester.tap(find.byKey(const Key('hub_outline_button')));
    await tester.pump();
    expect(taps, 1);

    expect(
      tester
          .getSemantics(find.byType(HubOutlineButton).first)
          .label
          .contains('Показати всі (5)'),
      isTrue,
    );
  });
}
