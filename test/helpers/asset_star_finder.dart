// Finders/counters for the approved rating-star asset glyph
// (`BeauticaAssetIcons.star` rendered through `AppIcon`) — the replacement for
// `find.byIcon(Icons.star_rounded)` since the Material star sweep (backlog
// HIGH, 2026-08-28; landed 2026-11-14).

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pixel_census.dart';

/// Every asset star; [color] narrows to one tint, e.g. the filled
/// (`BrandColors.accent`) vs empty (`BrandColors.faint`) slot of the
/// star-rating input.
Finder findAssetStar({Color? color}) => find.byWidgetPredicate(
  (Widget w) =>
      w is AppIcon &&
      w.asset == BeauticaAssetIcons.star &&
      (color == null || w.color == color),
  description:
      'AppIcon(BeauticaAssetIcons.star${color == null ? '' : ', $color'})',
);

/// How many of the asset stars matched by [stars] are PAINTED in
/// [BrandColors.accentDeep] — the filled colour of `ReviewStarRow`.
///
/// Read from rendered pixels, never from widget fields: `ReviewStarRow` tints
/// the whole row once through a `ShaderMask` (mobile-perf, 2026-11-14), so the
/// glyphs themselves carry no colour. Each star is classified by its darkest
/// pixel (the stroke core): nearer `accentDeep` = filled, nearer `faint` =
/// empty. Rasterises the nearest enclosing [RenderRepaintBoundary] (the
/// route's own boundary is enough), so the host needs no extra wrapper.
Future<int> countFilledAssetStars(WidgetTester tester, Finder stars) async {
  final Map<RenderRepaintBoundary, Raster> rasters =
      <RenderRepaintBoundary, Raster>{};
  int dist((int, int, int) a, Color c) =>
      (a.$1 - channel8(c.r)).abs() +
      (a.$2 - channel8(c.g)).abs() +
      (a.$3 - channel8(c.b)).abs();

  int filled = 0;
  for (final Element star in stars.evaluate()) {
    final RenderBox box = star.renderObject as RenderBox;
    final RenderRepaintBoundary boundary = enclosingRepaintBoundary(box);
    final Raster raster = rasters[boundary] ??= await rasterizeBoundary(
      tester,
      boundary,
    );

    final Rect rect = box.localToGlobal(Offset.zero) & box.size;
    final (int, int, int) core = raster
        .colorsIn(rect)
        .reduce(
          ((int, int, int) a, (int, int, int) b) =>
              a.$1 + a.$2 + a.$3 <= b.$1 + b.$2 + b.$3 ? a : b,
        );
    if (dist(core, BrandColors.accentDeep) < dist(core, BrandColors.faint)) {
      filled++;
    }
  }
  return filled;
}

/// The dominant RENDERED colour of the 4x4dp square at the centre of each
/// asset star matched by [stars], in finder order.
///
/// Read from pixels, never from `AppIcon.color`: the field stays correct even
/// when the glyph itself is wrong (the outline `star.svg` painted only a ring,
/// so a "filled" star's centre was the ground colour while its `color` field
/// said accent — fix/review-stars-fill-and-salon-card-price). On the solid
/// glyph a tinted star's centre IS its tint. Rasterises the nearest enclosing
/// [RenderRepaintBoundary], so the host needs no extra wrapper.
Future<List<(int, int, int)>> assetStarCentreColors(
  WidgetTester tester,
  Finder stars,
) async {
  final Map<RenderRepaintBoundary, Raster> rasters =
      <RenderRepaintBoundary, Raster>{};
  final List<(int, int, int)> centres = <(int, int, int)>[];
  for (final Element star in stars.evaluate()) {
    final RenderBox box = star.renderObject as RenderBox;
    final RenderRepaintBoundary boundary = enclosingRepaintBoundary(box);
    final Raster raster = rasters[boundary] ??= await rasterizeBoundary(
      tester,
      boundary,
    );
    centres.add(
      raster.dominantIn(
        Rect.fromCenter(
          center: box.localToGlobal(box.size.center(Offset.zero)),
          width: 4,
          height: 4,
        ),
      ),
    );
  }
  return centres;
}
