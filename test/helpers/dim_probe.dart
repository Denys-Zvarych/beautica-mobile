// Shared PIXEL probe for LAYER opacity (`Opacity` / `AnimatedOpacity` /
// `FadeTransition`) — the one thing the golden tier cannot see.
//
// ── WHY THIS EXISTS ───────────────────────────────────────────────────────
//
// `test/flutter_test_config.dart` runs alchemist in CI-golden mode only
// (`obscureText: true`). That capture path re-paints into the render object's
// already-populated `debugLayer` through `BlockedTextPaintingContext`, and a
// composited opacity layer does NOT survive it: measured 2026-08-31, a
// baseline generated at `Opacity(0.30)` compares GREEN against `1.0`. Goldens
// gate geometry, layout, copy and per-element colour — NOT layer opacity.
// Layer opacity is gated HERE, through the real compositor
// (`RenderRepaintBoundary.toImage()`), where it survives.
//
// ── THE MEASUREMENT ───────────────────────────────────────────────────────
//
// `Opacity(a)` over an opaque ground `B` composites every pixel to
// `P' = a·P + (1 - a)·B`, so each pixel's DEVIATION from the ground scales
// exactly by `a`:  |P' - B| = a·|P - B|.
//
// Two subtrees are pumped with IDENTICAL configuration except the dim, each in
// its own [RepaintBoundary] with an OPAQUE ground INSIDE the boundary
// (`toImage()` rasterizes only the boundary's own subtree; a ground painted by
// an ancestor is absent and every uncovered pixel comes back transparent —
// which a dimmed subtree produces too, so the probe would read alpha rather
// than the composite a user sees). Summing per-channel deviation from the
// ground across each captured image gives a ratio that must equal the dim:
//
//     Σ|P_dim - B| / Σ|P_full - B|  ==  expected
//
// A real number read out of real pixels, not a widget field.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Default composite tolerance — the capture is 8-bit per channel and the
/// subtrees carry anti-aliased glyph/text edges, so the summed ratio lands a
/// hair off the exact algebraic value. Tight enough that 1.0 (no dim) and
/// 0.05 (the mutants) are both far outside.
const double kDimProbeTolerance = 0.02;

/// Asserts that the [RepaintBoundary] found by [dimmed] composites to
/// [expected] of the deviation-from-[ground] of the one found by [full].
///
/// Both finders must resolve to a [RenderRepaintBoundary] that has an opaque
/// [ground] inside it, and the two subtrees must paint the same content apart
/// from the dim.
Future<void> expectDimRatio({
  required WidgetTester tester,
  required Finder dimmed,
  required Finder full,
  required Color ground,
  required double expected,
  double tolerance = kDimProbeTolerance,
}) async {
  final RenderRepaintBoundary fullBoundary = tester
      .renderObject<RenderRepaintBoundary>(full);
  final RenderRepaintBoundary dimBoundary = tester
      .renderObject<RenderRepaintBoundary>(dimmed);

  // ONE real-async hop captures both boundaries.
  ByteData? fullBytes;
  ByteData? dimBytes;
  await tester.runAsync(() async {
    fullBytes = await _captureBytes(fullBoundary);
    dimBytes = await _captureBytes(dimBoundary);
  });

  final int full0 = _deviationFromGround(fullBytes, ground);
  final int dim0 = _deviationFromGround(dimBytes, ground);

  // Guard the guard: if the FULL subtree painted nothing distinguishable from
  // the ground, the ratio below would be 0/0 and this would be measuring the
  // capture rather than the dim.
  expect(
    full0,
    greaterThan(0),
    reason:
        'the full-opacity control must paint something other than the ground '
        '— otherwise the ratio is meaningless',
  );

  expect(
    dim0.toDouble() / full0.toDouble(),
    closeTo(expected, tolerance),
    reason:
        'Opacity(a) composites to a·|P - B| deviation, so the ratio IS the '
        'dim: 1.0 would mean the dim is gone entirely',
  );
}

/// Rasterizes [boundary] through the real compositor; null if it yields no
/// bytes. The image is disposed even when capture throws.
Future<ByteData?> _captureBytes(RenderRepaintBoundary boundary) async {
  final ui.Image image = await boundary.toImage();
  try {
    return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  } finally {
    image.dispose();
  }
}

/// Sums every pixel's per-channel distance from [ground] across the captured
/// [bytes].
///
/// Alpha is ignored: the boundary is captured over an opaque ground, so every
/// pixel comes back fully opaque and only the colour carries information.
int _deviationFromGround(ByteData? bytes, Color ground) {
  expect(bytes, isNotNull, reason: 'the boundary must rasterize');

  final Uint8List px = bytes!.buffer.asUint8List(
    bytes.offsetInBytes,
    bytes.lengthInBytes,
  );
  final int groundR = (ground.r * 255).round();
  final int groundG = (ground.g * 255).round();
  final int groundB = (ground.b * 255).round();

  int sum = 0;
  for (int i = 0; i + 3 < px.length; i += 4) {
    sum += (px[i] - groundR).abs();
    sum += (px[i + 1] - groundG).abs();
    sum += (px[i + 2] - groundB).abs();
  }
  return sum;
}
