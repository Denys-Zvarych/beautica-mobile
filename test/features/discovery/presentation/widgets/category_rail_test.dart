// Phase 13.x (Variant A «Рейка + послуги») — widget tests for [CategoryRailTile]
// in isolation.
//
// The redesign makes every tile a UNIFORM fixed size — identical width AND
// height regardless of label length — so the rail reads as a clean row of
// identical cards. A constant 2-line label area is reserved and the glyph +
// label are vertically centered, so a 1-line label («Брови») yields a card
// exactly as tall as a 2-line one («Перманентний макіяж»), which still wraps
// onto its second line without ellipsis clipping. These tests pin that
// tile-level contract directly (the screen-level «all categories render» count
// is pinned in search_filters_screen_test.dart):
//   • a long label renders in FULL (Text.data == the full label, no truncation);
//   • the label Text never opts into TextOverflow.ellipsis (softWrap, maxLines:2);
//   • every tile is the SAME fixed width and height (short vs long label) via a
//     tight SizedBox — no IntrinsicWidth, no per-label sizing.
//
// All finders are type/widget-based; the label string is fixture data asserted
// only as rendered content.

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/category_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/overflow_guard.dart';

/// The longest realistic category name in the live taxonomy — two words that
/// must wrap onto a second line rather than clip. Used to prove the no-ellipsis
/// full-label contract.
const String _longLabel = 'Перманентний макіяж';

/// A const-constructible no-op tap handler so the tiles above can be `const`.
void _noop() {}

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

/// Hosts [child] under a forced [textScale], so the uniform fixed-height tile is
/// exercised at large-text settings (where a 2-line label is closest to
/// clipping). Mirrors how accessibility text-scaling reaches the tile in-app.
Widget _hostScaled(Widget child, double textScale) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(body: Center(child: child)),
  ),
);

/// Finds the tile's caption [Text] (the one carrying the category label),
/// excluding any incidental text. The tile renders exactly one Text — its label.
Text _labelText(WidgetTester tester, String label) {
  return tester.widget<Text>(find.text(label));
}

void main() {
  setUp(installOverflowGuard);

  testWidgets('renders a long label IN FULL — no ellipsis, no truncation', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CategoryRailTile(
          icon: Icons.gesture_outlined,
          label: _longLabel,
          selected: false,
          onTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The full label is present as rendered content — not clipped to «Перман…».
    expect(find.text(_longLabel), findsOneWidget);

    final Text label = _labelText(tester, _longLabel);
    // Ground-truth no-clip contract: the caption never opts into the ellipsis
    // overflow, wraps softly, and is allowed two lines for a long name.
    expect(
      label.overflow,
      isNot(TextOverflow.ellipsis),
      reason: 'the caption must never clip the category name to «…»',
    );
    expect(label.softWrap, isTrue, reason: 'a long label wraps, not clips');
    expect(label.maxLines, 2, reason: 'a long label gets a second line');
    // The Text data is the untruncated label verbatim.
    expect(label.data, _longLabel);
  });

  testWidgets(
    'long label actually lays out on two lines (render-layer, no overflow)',
    (tester) async {
      await tester.pumpWidget(
        _host(
          CategoryRailTile(
            icon: Icons.gesture_outlined,
            label: _longLabel,
            selected: false,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ground truth from the render tree: the bounded-width tile forces the
      // long two-word label onto a second line WITHOUT firing the maxLines clip
      // — i.e. it fits in 2 lines and is not truncated.
      final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
        find.text(_longLabel),
      );
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason: 'the long label must fit within 2 lines, not overflow/clip',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'the tile must lay out cleanly with no RenderFlex overflow',
      );
    },
  );

  // The tile is a FIXED-height box ([kTileHeight]); its real failure mode under
  // accessibility text-scaling is the 2-line label exceeding the reserved area
  // and clipping (didExceedMaxLines) or overflowing the box. Pin BOTH the 1.0×
  // baseline and the 1.3× large-text cell — the latter is the meaningful guard:
  // a non-uniform / under-reserved tile would clip the long label there.
  for (final double scale in const <double>[1.0, 1.3]) {
    testWidgets('long label still fits two lines without clip OR overflow at '
        '${scale}x text scale', (tester) async {
      await tester.pumpWidget(
        _hostScaled(
          CategoryRailTile(
            icon: Icons.gesture_outlined,
            label: _longLabel,
            selected: false,
            onTap: () {},
          ),
          scale,
        ),
      );
      await tester.pumpAndSettle();

      // The tile keeps its uniform fixed geometry regardless of text scale —
      // the box never grows to absorb a larger label.
      final Size size = tester.getSize(find.byType(CategoryRailTile));
      expect(size.width, CategoryRailTile.kTileWidth);
      expect(size.height, CategoryRailTile.kTileHeight);

      // Render-layer ground truth: the long label fits within 2 lines (not
      // truncated) AND lays out without firing a RenderFlex overflow.
      final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
        find.text(_longLabel),
      );
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason: 'at ${scale}x the long label must still fit 2 lines, not clip',
      );
      expect(paragraph.size.height, lessThanOrEqualTo(size.height));
      // No RenderFlex overflow (the suite-wide guard also fails on one, but
      // assert explicitly here so the scale cell pins it directly).
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a short label renders in full as well (single line)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CategoryRailTile(
          icon: Icons.remove_red_eye_outlined,
          label: 'Брови',
          selected: false,
          onTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Брови'), findsOneWidget);
    expect(_labelText(tester, 'Брови').data, 'Брови');
    expect(tester.takeException(), isNull);
  });

  testWidgets('every tile is the SAME fixed width and height regardless of '
      'label length', (tester) async {
    // Pump a short-label tile and a long-label tile side by side: a uniform
    // rail means both occupy an identical fixed box (no per-label sizing).
    await tester.pumpWidget(
      _host(
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CategoryRailTile(
              key: Key('tile_short'),
              icon: Icons.remove_red_eye_outlined,
              label: 'Брови',
              selected: false,
              onTap: _noop,
            ),
            CategoryRailTile(
              key: Key('tile_long'),
              icon: Icons.gesture_outlined,
              label: _longLabel,
              selected: true,
              onTap: _noop,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Size shortSize = tester.getSize(find.byKey(const Key('tile_short')));
    final Size longSize = tester.getSize(find.byKey(const Key('tile_long')));

    // Identical fixed geometry — the core uniform-card contract.
    expect(shortSize.width, CategoryRailTile.kTileWidth);
    expect(shortSize.height, CategoryRailTile.kTileHeight);
    expect(longSize.width, CategoryRailTile.kTileWidth);
    expect(longSize.height, CategoryRailTile.kTileHeight);
    // A 1-line label card is exactly as wide AND as tall as a 2-line one.
    expect(shortSize, longSize);
  });

  testWidgets('tapping the tile fires its onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        CategoryRailTile(
          icon: Icons.remove_red_eye_outlined,
          label: 'Брови',
          selected: false,
          onTap: () => taps++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(CategoryRailTile));
    await tester.pump();

    expect(taps, 1);
  });

  // ── SVG glyph migration (mobile-qa gap-closure) ───────────────────────────
  //
  // Before this group, NO test in the suite constructed [CategoryRailTile]
  // with [CategoryRailTile.iconAsset] at all — the entire additive migration
  // (production always sets it via `categoryIconFor` in
  // `search_filters_screen.dart:951`) was unguarded. These pin the additive
  // contract in both directions and the actual laid-out glyph size.
  group('CategoryRailTile — iconAsset (SVG) migration', () {
    testWidgets(
      'renders the SVG glyph (AppIcon/SvgPicture) when iconAsset is set, '
      'NOT the Material Icon',
      (tester) async {
        await tester.pumpWidget(
          _host(
            const CategoryRailTile(
              icon: Icons.remove_red_eye_outlined,
              iconAsset: BeauticaAssetIcons.categoryBrows,
              label: 'Брови',
              selected: false,
              onTap: _noop,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(AppIcon), findsOneWidget);
        expect(find.byType(SvgPicture), findsOneWidget);
        expect(
          find.byType(Icon),
          findsNothing,
          reason: 'the Material glyph must not co-render once iconAsset wins',
        );
      },
    );

    testWidgets(
      'renders the Material Icon glyph when iconAsset is null (additive '
      'default — the pre-migration contract every OTHER caller relies on)',
      (tester) async {
        await tester.pumpWidget(
          _host(
            const CategoryRailTile(
              icon: Icons.remove_red_eye_outlined,
              label: 'Брови',
              selected: false,
              onTap: _noop,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(Icon), findsOneWidget);
        expect(find.byType(AppIcon), findsNothing);
        expect(find.byType(SvgPicture), findsNothing);
      },
    );

    testWidgets(
      'the SVG glyph is actually LAID OUT at kGlyphAssetSize (36dp) — not '
      'merely configured with size: 36',
      (tester) async {
        // A `find.widget<AppIcon>(...).size == 36` assertion reads the
        // CONSTRUCTOR FIELD only — it is satisfied even if a tight-constrained
        // ancestor silently clobbers the rendered size (exactly the trap that
        // hid a 64dp-vs-36dp bug in beauty_timeline_section.dart's medallion
        // for a full chain this session — see
        // test/golden/beauty_timeline_rail_golden_test.dart's header). Measure
        // the actual RenderBox instead.
        await tester.pumpWidget(
          _host(
            const CategoryRailTile(
              icon: Icons.remove_red_eye_outlined,
              iconAsset: BeauticaAssetIcons.categoryBrows,
              label: 'Брови',
              selected: false,
              onTap: _noop,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final Size renderedSize = tester.getSize(find.byType(SvgPicture));
        expect(
          renderedSize,
          const Size(
            CategoryRailTile.kGlyphAssetSize,
            CategoryRailTile.kGlyphAssetSize,
          ),
          reason:
              'the SVG glyph must actually PAINT at 36×36 — a mismatch here '
              'means some ancestor is clobbering the requested size even '
              'though the AppIcon constructor field still reads 36',
        );
      },
    );

    testWidgets(
      'the Material glyph stays at kGlyphSize (24dp) when iconAsset is null '
      '— unaffected by the migration',
      (tester) async {
        await tester.pumpWidget(
          _host(
            const CategoryRailTile(
              icon: Icons.remove_red_eye_outlined,
              label: 'Брови',
              selected: false,
              onTap: _noop,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final Icon icon = tester.widget<Icon>(find.byType(Icon));
        expect(icon.size, CategoryRailTile.kGlyphSize);
      },
    );
  });
}
