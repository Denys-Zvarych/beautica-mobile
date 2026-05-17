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

    // 2. Blob 1 — top-right corner wash.
    // HTML: 300px blob, top:-70 right:-80, radial-gradient(circle,
    // rgba(88,56,26,0.38) 0%, transparent 70%). Centre placed off-screen
    // so only the faint tail is visible. Radius = 300/2 = 150pt.
    final blob1Center = Offset(w + 80, -70);
    const blob1Radius = 150.0;
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

    // 3. Blob 2 — bottom-left corner wash.
    // HTML: 220px blob, bottom:130 left:-70, radial-gradient(circle,
    // rgba(68,42,16,0.28) 0%, transparent 70%). Radius = 220/2 = 110pt.
    final blob2Center = Offset(-70, h - 130);
    const blob2Radius = 110.0;
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
