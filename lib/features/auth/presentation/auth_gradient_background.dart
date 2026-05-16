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
//
// Defect 3 fix: the two blobs were rendering with a hard circular edge and
// visible colour banding (only a 2-stop gradient). They are now built from
// 4-stop radial gradients AND run through a single hoisted
// [ImageFilter.blur] (sigma 60, decal tile mode) so the glow is genuinely
// soft. The solid espresso base stays OUTSIDE the blur so the screen edges
// remain a clean opaque colour.

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../core/theme/brand_colors.dart';

/// Full-screen Warm Mocha background — espresso solid fill with two ambient
/// radial-gradient blobs in mocha tones, softened by a single blur layer.
///
/// Blob 1 (top-right): ~360 × 360 logical pixels, mocha warm glow.
/// Blob 2 (bottom-left): ~280 × 280 logical pixels, darker mocha undertone.
///
/// The blobs are enlarged relative to the HTML mockup's 300/220 px to
/// compensate for the `decal` blur shrinking the visible radius. They are
/// purely decorative.
class AuthGradientBackground extends StatelessWidget {
  const AuthGradientBackground({super.key});

  // ── Static decoration objects — allocated once, never recreated on build().

  static const BoxDecoration _solidFill = BoxDecoration(
    color: BrandColors.espresso,
  );

  /// Hoisted blur filter — allocated once. Allocating [ImageFilter.blur]
  /// inside build() every frame would be a perf regression (see perf
  /// convention). `decal` keeps the blur from sampling the transparent
  /// pixels outside the blob box, avoiding a hard square halo.
  static final ImageFilter _kBlobBlur = ImageFilter.blur(
    sigmaX: 60,
    sigmaY: 60,
    tileMode: TileMode.decal,
  );

  /// Top-right ambient blob — mocha warm glow. 4 stops for a smooth,
  /// band-free falloff into full transparency.
  static const BoxDecoration _blob1 = BoxDecoration(
    shape: BoxShape.circle,
    gradient: RadialGradient(
      colors: [
        Color(0x61583A1A), // rgba(88,56,26,0.38)
        Color(0x33583A1A),
        Color(0x0F583A1A),
        Color(0x00583A1A),
      ],
      stops: [0.0, 0.35, 0.55, 0.72],
    ),
  );

  /// Bottom-left ambient blob — darker mocha undertone. 4 stops.
  static const BoxDecoration _blob2 = BoxDecoration(
    shape: BoxShape.circle,
    gradient: RadialGradient(
      colors: [
        Color(0x47442A10), // rgba(68,42,16,0.28)
        Color(0x26442A10),
        Color(0x0B442A10),
        Color(0x00442A10),
      ],
      stops: [0.0, 0.35, 0.55, 0.72],
    ),
  );

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      // ── Solid espresso base — fills the entire screen. OUTSIDE the blur
      //    so the screen edges stay a clean, opaque espresso colour.
      const DecoratedBox(decoration: _solidFill, child: SizedBox.expand()),

      // ── Blurred blob layer — only the two ambient glows are blurred.
      Positioned.fill(
        child: ImageFiltered(
          imageFilter: _kBlobBlur,
          child: Stack(
            children: [
              // Blob 1: top-right, ~360 × 360.
              Positioned(
                top: -100,
                right: -110,
                child: Container(width: 360, height: 360, decoration: _blob1),
              ),

              // Blob 2: bottom-left, ~280 × 280. Pinned to the bottom with an
              // upward offset so it appears as a soft glow near the lower-left
              // of the phone shell — matching login-page.html `.phone::after`.
              Positioned(
                bottom: 120,
                left: -100,
                child: Container(width: 280, height: 280, decoration: _blob2),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}
