// Warm Mocha auth background — Phase 2.x visual redesign (CustomPainter rewrite).
//
// Replaces the previous Positioned-Container + RadialGradient approach with a
// CustomPainter that draws directly onto the canvas. Two corner-anchored
// RadialGradient washes are painted with canvas.drawRect(), which covers the
// full screen area. The gradient fades naturally from each corner with no
// visible circular boundary.
//
// Why canvas.drawRect() instead of canvas.drawCircle():
//   canvas.drawCircle(center, radius, paint) only touches pixels within the
//   circle of that radius. The human eye sees the sharp boundary between the
//   painted circle and the untouched base as a visible circle edge, even when
//   the gradient alpha reaches zero well before the edge.
//   canvas.drawRect(fullRect, paintWithGradientShader) paints the entire canvas
//   area. The RadialGradient shader still has a circular falloff, but the alpha
//   blends smoothly into the espresso base everywhere — no circle edge, just a
//   warm colour wash emanating from the corner.
//
// CustomPainter design decisions:
//   - canvas.drawRect fills the espresso base, replacing DecoratedBox.
//   - Two more canvas.drawRect calls paint corner-anchored RadialGradient shaders
//     (top-right and bottom-left) using the same fullRect, so both shaders receive
//     accurate corner-anchor mapping from Alignment → screen coordinates.
//   - No canvas.drawCircle — eliminates the visible circular boundary artifact.
//   - shouldRepaint always returns false — background is fully static.
//   - No RepaintBoundary — Flutter's render tree manages layer caching.

import 'package:flutter/material.dart';

/// Full-screen Warm Mocha background painted directly on the canvas.
///
/// Uses a [CustomPainter] to:
///   1. Fill the espresso base colour (#0D0906) with [canvas.drawRect].
///   2. Overlay two corner-anchored [RadialGradient] washes using two more
///      [canvas.drawRect] calls. Each wash is anchored to its screen corner via
///      [Alignment] so the glow fades smoothly across the full canvas with no
///      visible circular boundary.
///
/// This widget is always [const] — it carries no state and never repaints.
class AuthGradientBackground extends StatelessWidget {
  const AuthGradientBackground({super.key});

  @override
  Widget build(BuildContext context) => const CustomPaint(
    painter: _AuthBackgroundPainter(),
    child: SizedBox.expand(),
  );
}

/// Static [CustomPainter] that draws the espresso base fill and two warm mocha
/// corner gradient washes directly onto the canvas.
///
/// All drawing uses [canvas.drawRect] — no [canvas.drawCircle] calls. This
/// eliminates the visible circular boundary that appears when [drawCircle]
/// clips the gradient at the circle's radius edge.
///
/// Each [RadialGradient] is anchored to its screen corner via [Alignment] and
/// created from [fullRect] so the [Alignment.topRight] / [Alignment.bottomLeft]
/// anchor resolves correctly to the actual corner pixel. The gradient fades
/// from the warm mocha colour at the corner to fully transparent before
/// reaching the opposite corner, leaving no visible boundary on screen.
///
/// Performance notes:
///   - [_kGrad1] / [_kGrad2] are `static const` — allocated once at class
///     initialisation, never re-created (including on orientation-change
///     re-rasterisation).
///   - [_sBasePaint] / [_sPaint1] / [_sPaint2] are `static final` — the
///     [Paint] objects themselves are reused; only their `.shader` is updated
///     on each [paint] call via [RadialGradient.createShader], which must
///     accept the size-dependent [Rect] computed at paint time.
///   - Mutation of the static [Paint] objects is safe: [paint] executes on
///     the UI thread sequentially, and [shouldRepaint] always returns `false`
///     so no interleaved calls can occur.
class _AuthBackgroundPainter extends CustomPainter {
  const _AuthBackgroundPainter();

  /// Espresso base — #0D0906 (same as BrandColors.espresso). Inlined as a
  /// hex constant to avoid importing brand_colors.dart into a painter.
  static const Color _kEspresso = Color(0xFF0D0906);

  // ── Pre-computed gradient constants — no allocation per paint() call.
  //
  // Hex alpha derivation:
  //   blob 1: 0.38 × 255 ≈ 97 = 0x61   → Color(0x61583A1A)
  //   blob 2: 0.28 × 255 ≈ 71 = 0x47   → Color(0x47442A10)
  //
  // radius explanation (Flutter RadialGradient docs):
  //   radius: 1.0 = a circle whose radius equals the shorter side of the
  //   bounding rect. For a 390pt phone:
  //     _kGrad1 radius 1.3 → 507pt from corner. At the opposite corner
  //     (390pt), 77% of the gradient is consumed → visible warm glow. At the
  //     far diagonal (913pt), gradient is fully transparent → no visible edge.
  //     _kGrad2 radius 1.1 → 429pt from corner → subtler secondary accent.
  //
  // The transparent stop preserves the RGB channels (colour-aware transparent)
  // to prevent hue-shift artefacts in Impeller's blend mode.

  /// Top-right warm wash — anchored to the top-right corner. Drawn with
  /// drawRect so the gradient fades into the espresso base with no visible
  /// circular boundary.
  static const _kGrad1 = RadialGradient(
    center: Alignment.topRight,
    radius: 1.3,
    colors: [Color(0x61583A1A), Color(0x00583A1A)],
  );

  /// Bottom-left warm wash — anchored to the bottom-left corner. Slightly
  /// tighter radius for a subtler secondary accent.
  static const _kGrad2 = RadialGradient(
    center: Alignment.bottomLeft,
    radius: 1.1,
    colors: [Color(0x47442A10), Color(0x00442A10)],
  );

  // ── Reusable Paint objects — allocated once, shader updated per paint().
  static final _sBasePaint = Paint()..color = _kEspresso;
  static final _sPaint1 = Paint();
  static final _sPaint2 = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);

    // ── 1. Espresso base fill — covers the entire paint area.
    canvas.drawRect(fullRect, _sBasePaint);

    // ── 2. Top-right warm wash — gradient fades from corner across the screen.
    _sPaint1.shader = _kGrad1.createShader(fullRect);
    canvas.drawRect(fullRect, _sPaint1);

    // ── 3. Bottom-left warm wash — secondary accent gradient.
    _sPaint2.shader = _kGrad2.createShader(fullRect);
    canvas.drawRect(fullRect, _sPaint2);
  }

  /// Background is fully static — never repaint.
  @override
  bool shouldRepaint(_AuthBackgroundPainter old) => false;
}
