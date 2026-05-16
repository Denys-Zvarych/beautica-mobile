// Warm Mocha auth background — Phase 2.x visual redesign (CustomPainter rewrite).
//
// Replaces the previous Positioned-Container + RadialGradient approach with a
// CustomPainter that draws directly onto the canvas via canvas.drawCircle() +
// RadialGradient.createShader(). This bypasses all Impeller compositing layers
// that caused hard-edged circle artifacts on Android.
//
// Root cause of the old approach:
//   Positioned Container widgets with RadialGradient BoxDecoration trigger
//   Impeller compositing boundaries even without BoxShape.circle. When a
//   Container is partially off-screen (clipped by the Stack viewport), Impeller
//   may rasterize the visible edge as a hard boundary. canvas.drawCircle() is a
//   native canvas operation; Impeller handles it without a compositing layer.
//
// CustomPainter design decisions:
//   - canvas.drawRect fills the espresso base, replacing DecoratedBox.
//   - canvas.drawCircle() draws the blob shape; the RadialGradient shader
//     is created from Rect.fromCircle centered on the blob — the gradient
//     fades from the warm colour at opacity [opacity] to alpha=0 at the radius.
//   - Blob positions mirror the HTML ::before/::after CSS pseudo-elements,
//     translated from CSS top/right/bottom/left into screen-space Offsets.
//   - shouldRepaint always returns false — background is fully static.
//   - No RepaintBoundary — Flutter's render tree manages layer caching.
//
// HTML reference (docs/signup-designs/login-page.html):
//   .phone::before — 300×300, top:-70, right:-80, blob-1 rgba(88,56,26,0.38)→transparent at 70%
//   .phone::after  — 220×220, bottom:130, left:-70, blob-2 rgba(68,42,16,0.28)→transparent at 70%

import 'package:flutter/material.dart';

/// Full-screen Warm Mocha background painted directly on the canvas.
///
/// Uses a [CustomPainter] to:
///   1. Fill the espresso base colour (#0D0906).
///   2. Draw two ambient radial-gradient blobs (top-right and bottom-left)
///      via [canvas.drawCircle] + [RadialGradient.createShader], avoiding
///      all Impeller compositing artifacts from the previous Positioned-Container
///      approach.
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
/// ambient glow blobs directly onto the canvas.
///
/// All drawing is done with [canvas.drawRect] and [canvas.drawCircle] —
/// no Flutter widget compositing layers involved, which eliminates the
/// hard-edged circle artifact produced by Impeller when rendering
/// [RadialGradient] inside a [Container].
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
  // stops [0.0, 0.7]: matches CSS `transparent 70%` — gradient reaches fully
  // transparent at 70% of radius (same as the HTML radial-gradient stop).
  // Without stops, the gradient fades linearly across the full radius,
  // creating a visible circular edge at the blob's boundary.
  // The transparent stop preserves the RGB channels (colour-aware transparent)
  // to prevent hue-shift artefacts in Impeller's blend mode.

  /// Top-right blob gradient — rgba(88,56,26) at 38% centre → transparent at 70% radius.
  static const _kGrad1 = RadialGradient(
    colors: [Color(0x61583A1A), Color(0x00583A1A)],
    stops: [0.0, 0.7],
  );

  /// Bottom-left blob gradient — rgba(68,42,16) at 28% centre → transparent at 70% radius.
  static const _kGrad2 = RadialGradient(
    colors: [Color(0x47442A10), Color(0x00442A10)],
    stops: [0.0, 0.7],
  );

  // ── Reusable Paint objects — allocated once, shader updated per paint().
  static final _sBasePaint = Paint()..color = _kEspresso;
  static final _sPaint1 = Paint();
  static final _sPaint2 = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    // ── 1. Espresso base fill — covers the entire paint area.
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), _sBasePaint);

    // ── 2. Blob 1 — top-right ambient glow.
    //
    // HTML .phone::before: width 300, height 300, top -70, right -80.
    //   center_x = size.width + 80 - 150 = size.width - 70
    //   center_y = -70 + 150 = 80
    final blob1Center = Offset(size.width - 70, 80);
    _sPaint1.shader = _kGrad1.createShader(
      Rect.fromCircle(center: blob1Center, radius: 150),
    );
    canvas.drawCircle(blob1Center, 150, _sPaint1);

    // ── 3. Blob 2 — bottom-left ambient glow.
    //
    // HTML .phone::after: width 220, height 220, bottom 130, left -70.
    //   center_x = -70 + 110 = 40
    //   center_y = size.height - 130 - 110 = size.height - 240
    final blob2Center = Offset(40, size.height - 240);
    _sPaint2.shader = _kGrad2.createShader(
      Rect.fromCircle(center: blob2Center, radius: 110),
    );
    canvas.drawCircle(blob2Center, 110, _sPaint2);
  }

  /// Background is fully static — never repaint.
  @override
  bool shouldRepaint(_AuthBackgroundPainter old) => false;
}
