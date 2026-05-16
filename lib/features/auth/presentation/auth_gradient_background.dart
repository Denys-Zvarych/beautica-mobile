// Warm Mocha auth background — Phase 2.x visual redesign.
//
// Replaces the old navy LinearGradient with an espresso (#0D0906) solid fill
// plus two ambient radial-gradient blob overlays (top-right and bottom-left)
// in warm mocha tones — mirroring the HTML mockups' ::before/::after blobs.
//
// Used as the bottom layer of the Stack in [LoginScreen] and [RegisterScreen].
// Declared public so it is accessible across the auth presentation layer.
//
// IMPORTANT: This widget uses a [Stack] + [Positioned] approach rather than
// CSS pseudo-elements. The background is rendered once and never rebuilt
// because all its children are `const`.

import 'package:flutter/material.dart';

import '../../../core/theme/brand_colors.dart';

/// Full-screen Warm Mocha background — espresso solid fill with two ambient
/// radial-gradient blobs in mocha tones.
///
/// Blob 1 (top-right): 300 × 300 logical pixels, rgba(88,56,26,0.38).
/// Blob 2 (bottom-left): 220 × 220 logical pixels, rgba(68,42,16,0.28).
///
/// These dimensions and positions faithfully match the HTML mockup's
/// `::before` / `::after` pseudo-elements. The blobs are purely decorative
/// and marked `excludeFromSemantics` implicitly by being `Container` paint.
class AuthGradientBackground extends StatelessWidget {
  const AuthGradientBackground({super.key});

  // ── Static decoration objects — allocated once, never recreated on build().

  static const BoxDecoration _solidFill = BoxDecoration(
    color: BrandColors.espresso,
  );

  /// Top-right ambient blob — mocha warm glow.
  static const BoxDecoration _blob1 = BoxDecoration(
    shape: BoxShape.circle,
    gradient: RadialGradient(
      colors: [
        Color(0x61583A1A), // rgba(88,56,26,0.38)
        Color(0x00583A1A),
      ],
      stops: [0.0, 1.0],
    ),
  );

  /// Bottom-left ambient blob — darker mocha undertone.
  static const BoxDecoration _blob2 = BoxDecoration(
    shape: BoxShape.circle,
    gradient: RadialGradient(
      colors: [
        Color(0x47442A10), // rgba(68,42,16,0.28)
        Color(0x00442A10),
      ],
      stops: [0.0, 1.0],
    ),
  );

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      // ── Solid espresso base — fills the entire screen.
      const DecoratedBox(decoration: _solidFill, child: SizedBox.expand()),

      // ── Blob 1: top-right, 300 × 300.
      Positioned(
        top: -70,
        right: -80,
        child: Container(width: 300, height: 300, decoration: _blob1),
      ),

      // ── Blob 2: bottom-left, 220 × 220.
      // Positioned relative to bottom — LayoutBuilder lets us compute the
      // bottom offset only if we know the height, but since this widget
      // always fills the screen behind a SafeArea'd child, we use a
      // fractional approach: we pin to bottom with an upward offset so it
      // appears approximately 130 px from the bottom of the phone shell.
      Positioned(
        bottom: 130,
        left: -70,
        child: Container(width: 220, height: 220, decoration: _blob2),
      ),
    ],
  );
}
