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
// HTML reference: docs/signup-designs/login-page.html
//   .phone::before — 300×300, top:-70, right:-80, blob-1 rgba(88,56,26,0.38)→transparent at 70%
//   .phone::after  — 220×220, bottom:130, left:-70, blob-2 rgba(68,42,16,0.28)→transparent at 70%
//
// Android/Impeller compensation: Impeller renders warm RGBA colors more
// saturated than Chrome's browser rendering. The HTML source values (0.38 and
// 0.28) look correct in Chrome but oversaturate on device. Blob centre
// opacities are reduced (~0.18 and ~0.10) to compensate.
//
// No blur is used. The soft falloff comes entirely from the 2-stop radial
// gradient (opaque centre → fully transparent at 70% radius), exactly as the
// HTML does — no CSS filter, no Flutter ImageFilter.

import 'package:flutter/material.dart';

import '../../../core/theme/brand_colors.dart';

/// Full-screen Warm Mocha background — espresso solid fill with two ambient
/// radial-gradient blobs in mocha tones.
///
/// Blob 1 (top-right): 300 × 300 logical pixels, rgba(88,56,26,~0.18) core
///   (HTML value 0.38 reduced for Android/Impeller saturation compensation).
/// Blob 2 (bottom-left): 220 × 220 logical pixels, rgba(68,42,16,~0.10) core
///   (HTML value 0.28 reduced for Android/Impeller saturation compensation).
///
/// Sizes and offsets are transcribed directly from the HTML reference.
/// No blur filter is applied — the gradient handles the soft falloff.
class AuthGradientBackground extends StatelessWidget {
  const AuthGradientBackground({super.key});

  // ── Static decoration objects — allocated once, never recreated on build().

  static const BoxDecoration _solidFill = BoxDecoration(
    color: BrandColors.espresso,
  );

  /// Top-right ambient blob — mocha warm glow.
  /// HTML: rgba(88,56,26,0.38). Android-compensated to ~0.18 opacity.
  static const BoxDecoration _blob1 = BoxDecoration(
    shape: BoxShape.circle,
    gradient: RadialGradient(
      colors: [
        Color(
          0x2F583A1A,
        ), // rgba(88,56,26,~0.18) — reduced from 0.38 for Impeller
        Color(0x00583A1A), // transparent
      ],
      stops: [0.0, 0.7],
    ),
  );

  /// Bottom-left ambient blob — darker mocha undertone.
  /// HTML: rgba(68,42,16,0.28). Android-compensated to ~0.10 opacity.
  static const BoxDecoration _blob2 = BoxDecoration(
    shape: BoxShape.circle,
    gradient: RadialGradient(
      colors: [
        Color(
          0x1A442A10,
        ), // rgba(68,42,16,~0.10) — reduced from 0.28 for Impeller
        Color(0x00442A10), // transparent
      ],
      stops: [0.0, 0.7],
    ),
  );

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      // ── Solid espresso base — fills the entire screen.
      const DecoratedBox(decoration: _solidFill, child: SizedBox.expand()),

      // ── Blob 1: top-right, 300×300, offset top:-70 right:-80.
      Positioned(
        top: -70,
        right: -80,
        child: Container(width: 300, height: 300, decoration: _blob1),
      ),

      // ── Blob 2: bottom-left, 220×220, offset bottom:130 left:-70.
      Positioned(
        bottom: 130,
        left: -70,
        child: Container(width: 220, height: 220, decoration: _blob2),
      ),
    ],
  );
}
