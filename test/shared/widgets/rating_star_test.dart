// Dedicated widget tests for the RatingStar single-star fractional-fill widget
// (lib/shared/widgets/rating_star.dart).
//
// my_rating_screen_test.dart pins RatingStar.fillFor (the pure mapping) and the
// screen-level wiring. THIS file guards the RENDERED structure of the widget
// itself — the thing fillFor alone cannot prove:
//
//   1. Fill rendering — the foreground Align's widthFactor equals fillFor(r) at
//      every key rating, AND the fill>0 fast path: exactly ONE AppIcon(star)
//      layer when fill==0 (base only), TWO layers when fill>0 (base + reveal).
//   2. Horizontal direction — the foreground Align reveals from Alignment
//      .centerLeft (left→right). A regression to right/centre/vertical fails.
//   3. Label — toStringAsFixed(1) shown only when showLabel && rating != null.
//   4. Size — the size param flows to both AppIcon layers.
//   5. Tints — base uses the muted BrandColors.faint, foreground the accent;
//      base.color != foreground.color.
//
// Red-against-regression: the production fill is ((rating-1)/4).clamp(0,1).
// If it regressed to the naive rating/5, then at r=1.0 the widthFactor
// assertion expects 0.0 (the fast path → ONE layer) but rating/5 would give
// 0.2 (TWO layers) — fails; at r=3.0 we expect 0.5 but rating/5 gives 0.6 —
// fails. So these tests pin the approved NORMALIZED mapping, not just "some
// monotonic fill".

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/shared/widgets/rating_star.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

void main() {
  // Finds every AppIcon rendering the canonical star SVG (base + foreground).
  final Finder starIcons = find.byWidgetPredicate(
    (w) => w is AppIcon && w.asset == BeauticaAssetIcons.star,
  );

  // The foreground reveal Align — the only Align whose direct child is an
  // AppIcon(star). This is the production reveal hook (widthFactor + alignment).
  final Finder foregroundAlign = find.byWidgetPredicate(
    (w) =>
        w is Align &&
        w.child is AppIcon &&
        (w.child! as AppIcon).asset == BeauticaAssetIcons.star,
  );

  // ── 1. Fill rendering at key ratings ──────────────────────────────────────
  //
  // For each rating: the number of star layers (1 when empty / fast-path
  // skipped, 2 when filled) AND — when filled — the foreground Align's
  // widthFactor must equal fillFor(rating) exactly.

  group('RatingStar — foreground fill matches fillFor at key ratings', () {
    // fill == 0 ⇒ the `if (fill > 0)` fast path skips the foreground subtree:
    // exactly ONE AppIcon(star) and NO foreground Align.
    for (final double? r in <double?>[1.0, null]) {
      testWidgets('rating $r → empty (base only, no foreground layer)', (
        tester,
      ) async {
        await tester.pumpApp(RatingStar(rating: r, showLabel: false));
        await tester.pump();

        expect(
          RatingStar.fillFor(r),
          equals(0.0),
          reason: 'precondition: rating $r maps to fill 0.0',
        );
        expect(
          starIcons,
          findsOneWidget,
          reason:
              'fill==0 must render ONLY the base star (foreground fast-path '
              'skipped) — finding two layers means the if (fill>0) guard broke',
        );
        expect(
          foregroundAlign,
          findsNothing,
          reason: 'no foreground reveal Align when fill==0',
        );
      });
    }

    // fill > 0 ⇒ base + foreground layers; the foreground Align.widthFactor
    // must equal fillFor(r) to the bit. Includes the canonical 4.7 (0.925) and
    // the midpoint 3.0 (0.5) — the two values that distinguish the approved
    // (rating-1)/4 mapping from the naive rating/5.
    for (final MapEntry<double, double> e in <double, double>{
      2.0: 0.25,
      3.0: 0.5,
      4.0: 0.75,
      5.0: 1.0,
      4.7: 0.925,
    }.entries) {
      testWidgets(
        'rating ${e.key} → fill ${e.value} (base + foreground reveal)',
        (tester) async {
          await tester.pumpApp(RatingStar(rating: e.key, showLabel: false));
          await tester.pump();

          expect(
            starIcons,
            findsNWidgets(2),
            reason:
                'fill>0 must render TWO star layers (muted base + accent fill)',
          );
          expect(
            foregroundAlign,
            findsOneWidget,
            reason: 'exactly one foreground reveal Align when fill>0',
          );

          final Align align = tester.widget<Align>(foregroundAlign);
          expect(
            align.widthFactor,
            closeTo(e.value, 1e-9),
            reason:
                'foreground reveal width must equal fillFor(${e.key}); pins '
                'the normalized (rating-1)/4 mapping (rating/5 would give a '
                'different fraction here and fail)',
          );
          expect(
            align.widthFactor,
            closeTo(RatingStar.fillFor(e.key), 1e-9),
            reason: 'widthFactor must stay bound to fillFor()',
          );
        },
      );
    }
  });

  // ── 2. Horizontal direction (left→right reveal) ───────────────────────────

  group('RatingStar — reveal direction', () {
    testWidgets('foreground Align reveals from centerLeft (left→right)', (
      tester,
    ) async {
      await tester.pumpApp(const RatingStar(rating: 4.7, showLabel: false));
      await tester.pump();

      final Align align = tester.widget<Align>(foregroundAlign);
      expect(
        align.alignment,
        equals(Alignment.centerLeft),
        reason:
            'partial fill must reveal from the LEFT edge; a regression to '
            'centerRight / center / a vertical alignment must fail here',
      );
    });
  });

  // ── 3. Label ──────────────────────────────────────────────────────────────

  group('RatingStar — numeric label', () {
    testWidgets('showLabel:true → renders toStringAsFixed(1)', (tester) async {
      await tester.pumpApp(const RatingStar(rating: 4.7));
      await tester.pump();

      expect(
        find.text('4.7'),
        findsOneWidget,
        reason: 'label must show the rating formatted to one decimal',
      );
    });

    testWidgets('rating 5.0 with label → "5.0" (one-decimal formatting)', (
      tester,
    ) async {
      await tester.pumpApp(const RatingStar(rating: 5.0));
      await tester.pump();

      expect(find.text('5.0'), findsOneWidget);
    });

    testWidgets('showLabel:false → no label text', (tester) async {
      await tester.pumpApp(const RatingStar(rating: 4.7, showLabel: false));
      await tester.pump();

      expect(
        find.text('4.7'),
        findsNothing,
        reason: 'no numeric label when showLabel is false',
      );
      // The star itself is still rendered (base + foreground).
      expect(starIcons, findsNWidgets(2));
    });

    testWidgets('null rating + showLabel:true → label hidden, no Row', (
      tester,
    ) async {
      // Production: `if (!showLabel || rating == null) return star;` — a null
      // rating returns the bare star with NO label and NO surrounding Row.
      await tester.pumpApp(const RatingStar(rating: null));
      await tester.pump();

      expect(
        find.byType(Text),
        findsNothing,
        reason: 'null rating must hide the label even when showLabel is true',
      );
      expect(
        find.byType(Row),
        findsNothing,
        reason: 'null rating returns the bare star, not the label Row',
      );
      // Empty star: base only, no foreground.
      expect(starIcons, findsOneWidget);
      expect(foregroundAlign, findsNothing);
    });
  });

  // ── 4. Size ───────────────────────────────────────────────────────────────

  group('RatingStar — size param', () {
    testWidgets('size flows to both base and foreground star layers', (
      tester,
    ) async {
      const double size = 40.0;
      await tester.pumpApp(
        const RatingStar(rating: 4.7, size: size, showLabel: false),
      );
      await tester.pump();

      final Iterable<AppIcon> icons = tester
          .widgetList<AppIcon>(starIcons)
          .cast<AppIcon>();
      expect(icons.length, 2, reason: 'base + foreground at fill>0');
      for (final AppIcon icon in icons) {
        expect(
          icon.size,
          equals(size),
          reason: 'every star layer must honor the size param ($size)',
        );
      }
    });

    testWidgets('default size is 24 when size omitted', (tester) async {
      await tester.pumpApp(const RatingStar(rating: 4.7, showLabel: false));
      await tester.pump();

      for (final AppIcon icon in tester.widgetList<AppIcon>(starIcons)) {
        expect(icon.size, equals(24.0));
      }
    });
  });

  // ── 5. Tints (base muted, foreground accent) ──────────────────────────────

  group('RatingStar — layer tints', () {
    testWidgets('base uses faint, foreground uses accent (base != fill)', (
      tester,
    ) async {
      await tester.pumpApp(const RatingStar(rating: 4.7, showLabel: false));
      await tester.pump();

      // Base star = the AppIcon(star) NOT inside the foreground Align.
      final Align fgAlign = tester.widget<Align>(foregroundAlign);
      final AppIcon foreground = fgAlign.child! as AppIcon;

      final List<AppIcon> all = tester
          .widgetList<AppIcon>(starIcons)
          .toList(growable: false);
      expect(all.length, 2);
      final AppIcon base = all.firstWhere((w) => !identical(w, foreground));

      expect(
        base.color,
        equals(BrandColors.faint),
        reason: 'base (empty) star must use the muted faint tint',
      );
      expect(
        foreground.color,
        equals(BrandColors.accent),
        reason: 'foreground (filled) star must use the camel accent tint',
      );
      expect(
        base.color,
        isNot(equals(foreground.color)),
        reason:
            'base and fill must be visually distinct — a regression that '
            'tints both the same colour erases the partial-fill read',
      );
    });
  });
}
