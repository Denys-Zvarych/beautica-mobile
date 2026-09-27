// RASTER CENSUS — read the pixels a user's eye would receive, not the fields a
// widget was configured with.
//
// ## Where this came from, and why it is here rather than copied
//
// `salon_bookings_board_pixel_census_test.dart` authored this mechanism
// (private `_Raster` / `_rasterize`) for a specific defect: the board's column
// wash shipped INVISIBLE once and OVER-BRIGHT once, and the suite that was
// supposed to guard it could not, because the wash that shipped was a
// `CustomPainter` drawing straight to the canvas — nothing a widget-walking
// census or a keyed finder can see. Rasterising through
// `RenderRepaintBoundary.toImage()` puts everything that PAINTS in scope by
// construction: `ColoredBox`, `CustomPainter`, `BoxDecoration`, a gradient.
//
// The audit that followed (LOW-8, 2026-09-20) found the same blind spot in
// several other tests, which assert `border.top.width`, `icon.size`,
// `divider.color`. Those read CONFIGURATION. They go green on a widget that
// carries the right field and paints nothing, or that is overpainted by a
// sibling, or whose ancestor is `Opacity(0)`. So the mechanism was PROMOTED
// here instead of being copied a second time — the original file now imports
// it and its private copies are gone, which is what keeps the two from
// drifting.
//
// ## What a field read is still right for
//
// This is not a rule that every `widget<X>(…).someField` is wrong. A field
// read is the honest check when the question genuinely is about
// configuration — "is `onPressed` null", "is this `BoxShape.circle` rather
// than a rect", "does this decoration carry NO `boxShadow`" (a
// shape/shadow COMBINATION whose raster failure mode has its own dedicated
// Impeller guard). It is wrong when the question is "does the user SEE this",
// which is every colour, every hairline, every glyph tint.
//
// ## Using it
//
// Wrap the subject in a `RepaintBoundary` with a known key, INSIDE which the
// production ground colour is reproduced — `BookingsTimelineGrid` and
// `MasterBookingCard` paint no background of their own, so without an explicit
// `ColoredBox` every pixel they do not cover comes back TRANSPARENT and the
// measurement reads alpha instead of the composite.
//
//     await tester.pumpApp(
//       RepaintBoundary(
//         key: kCensusBoundary,
//         child: const ColoredBox(color: BrandColors.base, child: subject),
//       ),
//       width: 840,
//     );
//     final Raster raster = await rasterize(tester);
//     final (int r, int g, int b) = raster.at(rect.left + 2, rect.center.dy);
//
// `pumpApp(width:)` pins `devicePixelRatio` to 1 and `toImage`'s default
// `pixelRatio` is 1, so one image pixel IS one logical pixel and no scaling is
// folded in.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The default boundary key [rasterize] looks for.
const Key kCensusBoundary = Key('pixel-census-boundary');

/// A captured frame plus the global-coordinate origin it was captured at, so a
/// rect measured with `tester.getRect` can be read straight out of it.
class Raster {
  const Raster(this.px, this.width, this.height, this.origin);

  final Uint8List px;
  final int width;
  final int height;
  final Offset origin;

  bool contains(int x, int y) => x >= 0 && y >= 0 && x < width && y < height;

  /// The opaque RGB triple at GLOBAL logical position ([gx], [gy]).
  (int, int, int) at(double gx, double gy) {
    final int x = (gx - origin.dx).round();
    final int y = (gy - origin.dy).round();
    expect(
      contains(x, y),
      isTrue,
      reason: 'sample ($gx, $gy) fell outside the captured frame',
    );
    final int i = (y * width + x) * 4;
    return (px[i], px[i + 1], px[i + 2]);
  }

  /// Every distinct RGB triple inside [rect] (global coordinates), as a set —
  /// for "this region contains SOME pixel of colour X" questions where the
  /// exact sample point is an antialiasing lottery.
  Set<(int, int, int)> colorsIn(Rect rect) {
    final Set<(int, int, int)> out = <(int, int, int)>{};
    for (double y = rect.top; y < rect.bottom; y += 1) {
      for (double x = rect.left; x < rect.right; x += 1) {
        final int ix = (x - origin.dx).round();
        final int iy = (y - origin.dy).round();
        if (!contains(ix, iy)) continue;
        final int i = (iy * width + ix) * 4;
        out.add((px[i], px[i + 1], px[i + 2]));
      }
    }
    return out;
  }

  /// The RGB triple that occurs MOST inside [rect] — the region's dominant
  /// colour, which is what "what colour is this hairline" actually asks.
  (int, int, int) dominantIn(Rect rect) {
    final Map<(int, int, int), int> counts = <(int, int, int), int>{};
    for (double y = rect.top; y < rect.bottom; y += 1) {
      for (double x = rect.left; x < rect.right; x += 1) {
        final int ix = (x - origin.dx).round();
        final int iy = (y - origin.dy).round();
        if (!contains(ix, iy)) continue;
        final int i = (iy * width + ix) * 4;
        final (int, int, int) c = (px[i], px[i + 1], px[i + 2]);
        counts[c] = (counts[c] ?? 0) + 1;
      }
    }
    expect(
      counts,
      isNotEmpty,
      reason: 'the sampled rect $rect captured no pixels at all',
    );
    return counts.entries
        .reduce(
          (
            MapEntry<(int, int, int), int> a,
            MapEntry<(int, int, int), int> b,
          ) => a.value >= b.value ? a : b,
        )
        .key;
  }
}

/// Rasterises the [RepaintBoundary] keyed [boundary] (default
/// [kCensusBoundary]) and returns its pixels.
Future<Raster> rasterize(
  WidgetTester tester, {
  Key boundary = kCensusBoundary,
}) async {
  final RenderRepaintBoundary renderBoundary = tester
      .renderObject<RenderRepaintBoundary>(find.byKey(boundary));

  late final ByteData? raw;
  late final int w;
  late final int h;
  await tester.runAsync(() async {
    final ui.Image image = await renderBoundary.toImage();
    w = image.width;
    h = image.height;
    raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
  });

  final ByteData? bytes = raw;
  expect(bytes, isNotNull, reason: 'the boundary must rasterize');
  return Raster(
    bytes!.buffer.asUint8List(),
    w,
    h,
    tester.getTopLeft(find.byKey(boundary)),
  );
}

/// The 0–255 channel value of a `double` colour component (`Color.r`/`.g`/`.b`
/// are 0..1 in Flutter's wide-gamut `Color`).
int channel8(double component) => (component * 255).round();

/// [over] composited onto [under] by straight source-over alpha — the colour a
/// translucent fill ACTUALLY produces on the app's ground, which is what a
/// raster sample can be compared against.
(int, int, int) compositeOver(Color over, Color under) {
  final double a = over.a;
  int mix(double o, double u) => ((o * a + u * (1 - a)) * 255).round();
  return (mix(over.r, under.r), mix(over.g, under.g), mix(over.b, under.b));
}
