// Warm Mocha auth background — Phase 2.x visual redesign (CustomPainter).
//
// Draws the espresso base fill (#0D0906) and two off-screen-anchored radial
// gradient washes that match the HTML design's .phone::before / .phone::after
// pseudo-elements. Blob centres are placed partially off-screen so only the
// faint outer tail bleeds into the corners — no visible opaque "circle".
//
// CustomPainter design decisions:
//   - canvas.drawRect fills the espresso base, replacing DecoratedBox.
//   - Two more canvas.drawRect calls paint RadialGradient shaders whose centres
//     are outside the canvas bounds, mirroring the CSS top:-70 right:-80 /
//     bottom:130 left:-70 offsets from the HTML design.
//   - Paint objects are created inline per paint() call — avoids the Impeller
//     race that occurs when static Paint objects have their shader field mutated.
//   - shouldRepaint always returns false — background is fully static.

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
/// Blob geometry matches the HTML design's `.phone::before` / `.phone::after`
/// pseudo-elements exactly: blob centres are placed partially off-screen so
/// only the faint outer tail of each radial gradient bleeds into the corners.
/// This avoids the visible "circle" artefact that occurs when the opaque core
/// of a large, on-screen-anchored gradient is rendered at full opacity.
///
/// All [Paint] objects are created fresh per [paint] call to avoid the Impeller
/// race that occurs when static [Paint] objects have their [shader] field
/// mutated across frames.
class _AuthBackgroundPainter extends CustomPainter {
  const _AuthBackgroundPainter();

  // HTML: --phone-bg: #0d0906
  static const Color _kEspresso = Color(0xFF0D0906);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Espresso base fill.
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = _kEspresso);

    // 2. Blob 1 — top-right warm wash. Center pushed OUTSIDE the corner so the
    // visible canvas only samples the monotonic tail (HTML clips the core via
    // overflow:hidden + border-radius). No on-screen local max → no disc.
    final blob1Center = Offset(w + 30, -30);
    const blob1Radius = 420.0;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader =
            const RadialGradient(
              colors: [Color(0x61583A1A), Color(0x00583A1A)],
              stops: [0.0, 0.70],
            ).createShader(
              Rect.fromCircle(center: blob1Center, radius: blob1Radius),
            ),
    );

    // 3. Blob 2 — bottom-left warm wash. Center pushed off the left edge for the
    // same tail-only visibility.
    final blob2Center = Offset(-30, h - 240);
    const blob2Radius = 160.0;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader =
            const RadialGradient(
              colors: [Color(0x47442A10), Color(0x00442A10)],
              stops: [0.0, 0.70],
            ).createShader(
              Rect.fromCircle(center: blob2Center, radius: blob2Radius),
            ),
    );
  }

  @override
  bool shouldRepaint(_AuthBackgroundPainter old) => false;
}
