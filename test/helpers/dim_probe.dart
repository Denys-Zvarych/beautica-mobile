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
//
// ── WHICH MODE ────────────────────────────────────────────────────────────
//
// * [expectDimRatio] — SIDE BY SIDE. Both states fit in one tree and each sits
//   in a test-owned [RepaintBoundary] with its own opaque ground. Use for a
//   widget you can instantiate twice (public widgets, purpose-built cells).
//
// * [expectRegionDimRatio] — TWO PUMPS. Use when the target is a private /
//   embedded widget (a chevron, a time well, a strip inside a screen) whose
//   dimmed and undimmed states can only be rendered one at a time, and you do
//   not want to add a `RepaintBoundary` seam to `lib/`. The target's paint
//   rect is cropped out of its NEAREST ANCESTOR [RenderRepaintBoundary]
//   (captured at the view's devicePixelRatio), once per pump, and compared
//   with the same deviation-ratio math. Requirements:
//     - the region needs a SOLID OPAQUE ground under the target, inside that
//       ancestor boundary. If the real screen paints a gradient or image
//       behind it, pump the owner widget over a `ColoredBox(ground)` inside a
//       `RepaintBoundary` instead of the real backdrop;
//     - the target's geometry must be identical in both pumps (else the test
//       fails: the comparison would be meaningless);
//     - an `AnimatedOpacity` / `FadeTransition` target must be pumped PAST its
//       tween (`pumpAndSettle` or a `pump(duration)`) inside `pumpFull` /
//       `pumpDimmed` before the capture, or the probe reads mid-tween.
//   Region mode rasterises the WHOLE ancestor boundary (then crops), so keep
//   that boundary small. It always captures at pixelRatio 1.0 regardless of the
//   view's devicePixelRatio (the crop rect is in logical px == capture px, so no
//   scaling is needed and a high-DPR view costs nothing extra); a self-test pins
//   that a 2.0 view still measures correctly.
//
// ── READING THE RATIO ─────────────────────────────────────────────────────
//
// The measured ratio is NOT a pure opacity when the target has soft shadows or
// anti-aliased edges: the dim also scales those, but they are part of the
// "deviation" only partly, so a 0.7 strip can read ~0.67. The honest control is
// to compare the REAL dimmed widget against the SAME full widget wrapped in a
// hand-made `Opacity(<value>)` and assert ratio 1.0 with a tight tolerance
// (e.g. 0.01) — then edges/shadows cancel. See the control cases in
// `test/features/booking/presentation/booking_detail_screen_test.dart`,
// `booking_detail_provider_view_test.dart` and
// `test/features/location/presentation/widgets/locality_tap_row_test.dart`.
//
// Both entry points take an optional `reason`, appended to the failure message:
// use it to say what ELSE could move the number (e.g. a restyled replica).

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
/// from the dim. [reason] (optional) is appended to a ratio-mismatch failure.
Future<void> expectDimRatio({
  required WidgetTester tester,
  required Finder dimmed,
  required Finder full,
  required Color ground,
  required double expected,
  double tolerance = kDimProbeTolerance,
  String? reason,
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

  _expectRatio(
    full: _deviationFromGround(fullBytes, ground),
    dim: _deviationFromGround(dimBytes, ground),
    expected: expected,
    tolerance: tolerance,
    reason: reason,
  );
}

/// Asserts the target's region composites to [expected] of its
/// deviation-from-[ground] between two pumps.
///
/// [pumpFull] renders the undimmed state, [pumpDimmed] the dimmed one; each
/// must leave the tree settled. [target] must resolve to exactly one widget
/// whose size and position are identical in both pumps. See the file header
/// for the ground and animation requirements.
///
/// [geometryTolerance] (logical px, default effectively zero) is an opt-in for
/// a host whose two states shift the target by a fixed sub-few-px offset that
/// is NOT the dim — e.g. a hairline border that exists only in the dimmed
/// state insets the content by 1dp. The target's SIZE is still compared with
/// the same tolerance; the caller must keep the shifted crop wholly over the
/// same solid-ground-composited area (inside the disc/card), and say why.
Future<void> expectRegionDimRatio({
  required WidgetTester tester,
  required Finder target,
  required Future<void> Function() pumpFull,
  required Future<void> Function() pumpDimmed,
  required Color ground,
  required double expected,
  double tolerance = kDimProbeTolerance,
  double geometryTolerance = _geometryEpsilon,
  String? reason,
}) async {
  await pumpFull();
  final _Region full = await _captureRegion(tester, target);
  await pumpDimmed();
  final _Region dim = await _captureRegion(tester, target);

  if ((full.rect.left - dim.rect.left).abs() > geometryTolerance ||
      (full.rect.top - dim.rect.top).abs() > geometryTolerance ||
      (full.rect.width - dim.rect.width).abs() > geometryTolerance ||
      (full.rect.height - dim.rect.height).abs() > geometryTolerance) {
    fail(
      'target geometry differs between the two pumps '
      '(full ${full.rect} vs dimmed ${dim.rect}) — the comparison is '
      'meaningless unless the dim is the ONLY change',
    );
  }

  _expectRatio(
    full: _deviationFromGround(full.bytes, ground),
    dim: _deviationFromGround(dim.bytes, ground),
    expected: expected,
    tolerance: tolerance,
    reason: reason,
  );
}

const double _geometryEpsilon = 0.01;

/// The ratio assertion shared by both modes.
void _expectRatio({
  required int full,
  required int dim,
  required double expected,
  required double tolerance,
  String? reason,
}) {
  final String extra = reason == null ? '' : ' — $reason';
  // Guard the guard: if the FULL subtree painted nothing distinguishable from
  // the ground, the ratio below would be 0/0 and this would be measuring the
  // capture rather than the dim.
  expect(
    full,
    greaterThan(0),
    reason:
        'the full-opacity control must paint something other than the ground '
        '— otherwise the ratio is meaningless$extra',
  );

  expect(
    dim.toDouble() / full.toDouble(),
    closeTo(expected, tolerance),
    reason:
        'Opacity(a) composites to a·|P - B| deviation, so the ratio IS the '
        'dim: 1.0 would mean the dim is gone entirely$extra',
  );
}

class _Region {
  const _Region(this.rect, this.bytes);

  /// The target's rect in its ancestor boundary's logical coordinates.
  final Rect rect;
  final ByteData? bytes;
}

/// Crops [target]'s paint rect out of its nearest ancestor
/// [RenderRepaintBoundary] through the real compositor.
Future<_Region> _captureRegion(WidgetTester tester, Finder target) async {
  final List<Element> found = target.evaluate().toList();
  if (found.length != 1) {
    fail('target must resolve to exactly one widget, found ${found.length}');
  }
  final RenderObject? ro = found.single.renderObject;
  if (ro is! RenderBox || !ro.hasSize) {
    fail('target must resolve to a laid-out RenderBox, got $ro');
  }

  RenderObject? ancestor = ro.parent;
  while (ancestor != null && ancestor is! RenderRepaintBoundary) {
    ancestor = ancestor.parent;
  }
  if (ancestor == null) {
    fail(
      'target has no ancestor RenderRepaintBoundary — wrap the owner widget '
      'in a RepaintBoundary over a solid ground',
    );
  }
  final RenderRepaintBoundary boundary = ancestor as RenderRepaintBoundary;

  final Rect rect = MatrixUtils.transformRect(
    ro.getTransformTo(boundary),
    Offset.zero & ro.size,
  );
  ByteData? cropped;
  await tester.runAsync(() async {
    cropped = await _captureCropped(boundary, rect);
  });

  if (cropped == null) {
    fail(
      'target region is empty or off-boundary (rect $rect) — nothing to probe',
    );
  }
  return _Region(rect, cropped);
}

/// Rasterizes [boundary] at pixelRatio 1.0 and returns ONLY the [rect] crop
/// (logical px == capture px). The full-boundary bytes are scoped to this
/// function, so they are collectable as soon as the crop is copied. Null when
/// the capture yields no bytes or the crop is empty.
Future<ByteData?> _captureCropped(
  RenderRepaintBoundary boundary,
  Rect rect,
) async {
  final ByteData? whole = await _captureBytes(boundary);
  if (whole == null) return null;
  final int imgW = boundary.size.width.ceil();
  final int imgH = boundary.size.height.ceil();
  final int left = rect.left.round().clamp(0, imgW);
  final int top = rect.top.round().clamp(0, imgH);
  final int right = rect.right.round().clamp(0, imgW);
  final int bottom = rect.bottom.round().clamp(0, imgH);
  final int w = right - left;
  final int h = bottom - top;
  if (w <= 0 || h <= 0) return null;

  final Uint8List src = whole.buffer.asUint8List(
    whole.offsetInBytes,
    whole.lengthInBytes,
  );
  final Uint8List out = Uint8List(w * h * 4);
  for (int y = 0; y < h; y++) {
    final int from = ((top + y) * imgW + left) * 4;
    out.setRange(y * w * 4, (y + 1) * w * 4, src, from);
  }
  return ByteData.sublistView(out);
}

/// Rasterizes [boundary] through the real compositor at pixelRatio 1.0; null
/// if it yields no bytes. The image is disposed even when capture throws.
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
