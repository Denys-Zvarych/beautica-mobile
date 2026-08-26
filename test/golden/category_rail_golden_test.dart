// Phase 13.4 — Full-label category-rail golden (FIRST rail golden).
//
// The canonical uniform-card / wrap / no-truncation pixel case for
// [CategoryRailTile]: a row holding a deliberately long label
// («Перманентний макіяж», which MUST wrap onto a 2nd line, never ellipsis-clip)
// beside a short one («Брови»), one tile selected (pressed-in inset well) and
// one resting (raised pill). A regression that re-introduces single-line
// truncation, drops the wrap, swaps the selected/resting treatment, OR breaks
// the uniform fixed sizing (the two tiles must be identical width AND height)
// reads as a pixel diff here.
//
// Every tile is a fixed [CategoryRailTile.kTileWidth] ×
// [CategoryRailTile.kTileHeight] box, so the two tiles are identical in size —
// we host them in a left-aligned Row on the brand base, matching the rail on
// screen.
//
// Captured at {360} dp × {1.0, 1.3} scale — the 1.3 cell is the meaningful one:
// it proves the long label still wraps (never clips) under large-text settings.
//
// File names: category_rail_full_labels_360_1x.png
//             category_rail_full_labels_360_1_3x.png
//
// ── SVG GLYPH COVERAGE — GAP-CLOSURE (mobile-qa, 2026-08-26) ────────────────
//
// mobile-build-verifier raised a MEDIUM: every scenario above constructs its
// tiles with `icon:` only — [CategoryRailTile.iconAsset] is never passed, so
// these two baselines moved purely from the 80→92dp height bump and carry
// ZERO visual coverage of the SVG glyph path production ALWAYS renders
// (`search_filters_screen.dart:951` never leaves `iconAsset` null —
// `categoryIconFor` never returns null). A regression in [AppIcon],
// `categoryIconFor`, or the [CategoryRailTile.kGlyphAssetSize] constant would
// not move either baseline above.
//
// The `category rail SVG glyph` group below closes that gap: two tiles built
// WITH `iconAsset` set (mirroring the beauty-timeline-rail precedent at
// `beauty_timeline_rail_golden_test.dart`), captured at the same {360dp} ×
// {1.0, 1.3} matrix.
//
// GOLDENS ARE NOT ACCEPTANCE BY THEMSELVES — see
// `beauty_timeline_rail_golden_test.dart`'s header for the full argument. The
// non-golden `measured ground truth` group below is what this golden's
// confidence actually rests on: it proves the SVG is genuinely painted (not a
// blank decode placeholder — [find.byType(SvgPicture)] resolves and is NOT
// `findsNothing`) and genuinely LAID OUT at 36×36 via `tester.getSize`, not
// merely constructed with `size: 36` (the vacuous constructor-field trap —
// see `category_rail_test.dart`'s matching group).
//
// MUTATION PROOF the golden itself sees the SVG layer (not just the measured
// group): swapping tile `rail_tile_svg_a`'s resolved asset from
// `category_trichology.svg` to `category_hairdressing.svg` (same size, same
// selected/camel-tint state — ONLY the SVG's own pixel content differs) and
// regenerating (`flutter test --update-goldens --plain-name "category rail
// SVG glyphs" test/golden/category_rail_golden_test.dart`) changes the
// baseline hash:
//   category_rail_svg_glyphs_360_1x    original sha256 17017cf520026b1cf0a726767c5c714d897c48e533158767585ba5f808f2aa8e
//   category_rail_svg_glyphs_360_1x    mutated  sha256 845162238088f86e61026d15f2435c027ee7b5d184a5687495150f39f5941577
//   category_rail_svg_glyphs_360_1_3x  original sha256 67fffaaa3bd476f194954eef3a74f3036f47fd36a8f2e9ea1cc50caf89d2c15b
//   category_rail_svg_glyphs_360_1_3x  mutated  sha256 b2e14bbe2aadbbc86843cbceb33a949cd38d6f3aedebd013b0081667496f187d
// Mutation reverted; regenerating again from the reverted source reproduces
// the ORIGINAL hashes byte-for-byte (verified via `cmp`) — the committed
// PNGs are the original, un-mutated baseline.

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/category_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/golden_pump.dart';

/// A long label that must wrap to two lines, and a short one that stays a pill.
Widget _rail() => Row(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: <Widget>[
    CategoryRailTile(
      key: const Key('rail_tile_short'),
      icon: Icons.face_retouching_natural,
      label: 'Брови',
      selected: true,
      onTap: () {},
    ),
    const SizedBox(width: 12),
    CategoryRailTile(
      key: const Key('rail_tile_long'),
      icon: Icons.brush_outlined,
      label: 'Перманентний макіяж',
      selected: false,
      onTap: () {},
    ),
  ],
);

/// Hosts [child] on the brand base with the rail's vertical breathing room.
Widget _host(double width, Widget child) => ColoredBox(
  color: BrandColors.base,
  child: SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Align(alignment: Alignment.centerLeft, child: child),
    ),
  ),
);

/// Two tiles built WITH [CategoryRailTile.iconAsset] set — the path
/// production ALWAYS takes (`search_filters_screen.dart:951`). Selected tile
/// uses `category_trichology.svg` (the camel-tinted inset state), resting
/// tile uses `category_barbering.svg` (the raised-pill state) — the SAME two
/// slugs spot-checked in
/// `search_filters_screen_category_icons_test.dart` for correct resolution,
/// so this golden and that widget test corroborate the same production
/// wiring from two independent angles.
Widget _railWithSvgGlyphs() => Row(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: <Widget>[
    CategoryRailTile(
      key: const Key('rail_tile_svg_a'),
      icon: Icons.face_retouching_natural,
      iconAsset: BeauticaAssetIcons.categoryTrichology,
      label: 'Трихологія',
      selected: true,
      onTap: () {},
    ),
    const SizedBox(width: 12),
    CategoryRailTile(
      key: const Key('rail_tile_svg_b'),
      icon: Icons.content_cut_outlined,
      iconAsset: BeauticaAssetIcons.categoryBarbering,
      label: 'Барберинг',
      selected: false,
      onTap: () {},
    ),
  ],
);

void main() {
  const double width = 360;

  for (final double scale in kGoldenTextScales) {
    goldenTest(
      'category rail full labels ${width.toInt()}dp x$scale',
      fileName: 'category_rail_full_labels_${widthScaleSuffix(width, scale)}',
      constraints: BoxConstraints.tight(const Size(width, 160)),
      textScaleFactor: scale,
      pumpWidget: goldenPumpWidget(width: width),
      builder: () => _host(width, _rail()),
    );
  }

  // ── Measured ground truth (not golden) ────────────────────────────────────
  //
  // What this golden's confidence actually rests on — see the file header.
  group('CategoryRailTile SVG glyph — measured ground truth (not golden)', () {
    testWidgets(
      'the SVG glyph genuinely paints (SvgPicture resolves, not a blank '
      'decode placeholder) and the Material Icon does NOT co-render',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: _host(width, _railWithSvgGlyphs()))),
        );
        await tester.pumpAndSettle();

        expect(find.byType(AppIcon), findsNWidgets(2));
        expect(find.byType(SvgPicture), findsNWidgets(2));
        expect(find.byType(Icon), findsNothing);
      },
    );

    testWidgets(
      'the SVG glyph is actually LAID OUT at kGlyphAssetSize (36dp), not '
      'merely configured — the layout-clobber trap a size-field read would miss',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: _host(width, _railWithSvgGlyphs()))),
        );
        await tester.pumpAndSettle();

        for (final Element el in find.byType(SvgPicture).evaluate()) {
          final Size size = tester.getSize(find.byWidget(el.widget));
          expect(
            size,
            const Size(
              CategoryRailTile.kGlyphAssetSize,
              CategoryRailTile.kGlyphAssetSize,
            ),
          );
        }
      },
    );
  });

  // ── Golden — the SVG glyph path production always takes ──────────────────
  group('category rail SVG glyph golden', () {
    for (final double scale in kGoldenTextScales) {
      goldenTest(
        'category rail SVG glyphs ${width.toInt()}dp x$scale',
        fileName: 'category_rail_svg_glyphs_${widthScaleSuffix(width, scale)}',
        constraints: BoxConstraints.tight(const Size(width, 160)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(width: width),
        builder: () => _host(width, _railWithSvgGlyphs()),
      );
    }
  });
}
