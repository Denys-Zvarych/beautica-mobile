// Finders/counters for the approved rating-star asset glyph
// (`BeauticaAssetIcons.star` rendered through `AppIcon`) — the replacement for
// `find.byIcon(Icons.star_rounded)` since the Material star sweep (backlog
// HIGH, 2026-08-28; landed 2026-11-14).

import 'dart:typed_data';
import 'dart:ui' as ui;

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
    RenderObject? node = box.parent;
    while (node != null && node is! RenderRepaintBoundary) {
      node = node.parent;
    }
    expect(node, isNotNull, reason: 'a star must sit under a repaint boundary');
    final RenderRepaintBoundary boundary = node as RenderRepaintBoundary;
    final Raster raster = rasters[boundary] ??= await _rasterizeBoundary(
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

Future<Raster> _rasterizeBoundary(
  WidgetTester tester,
  RenderRepaintBoundary boundary,
) async {
  Uint8List? px;
  int w = 0;
  int h = 0;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage();
    w = image.width;
    h = image.height;
    final ByteData? raw = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    px = raw?.buffer.asUint8List();
    image.dispose();
  });
  final Uint8List? bytes = px;
  expect(bytes, isNotNull, reason: 'the boundary must rasterize');
  return Raster(
    bytes ?? Uint8List(0),
    w,
    h,
    boundary.localToGlobal(Offset.zero),
  );
}
