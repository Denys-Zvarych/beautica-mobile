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
// Android/Impeller fix: BoxShape.circle was removed from both blob decorations.
// When Flutter clips a Container to BoxShape.circle, Impeller rasterizes the
// clip as its own offscreen compositing layer. That compositing boundary makes
// the gradient's soft centre look like a hard-edged filled disc — the intended
// radial soft-falloff is still present, but the clip's compositing layer makes
// it visually opaque. Without the clip, the RadialGradient itself fades from a
// warm colour at stop 0.0 to fully transparent at stop 0.7 (~105 px from centre
// in a 300×300 container), producing a naturally soft circular glow with no
// compositing penalty.
//
// Android/Impeller compensation: Impeller renders warm RGBA colours more
// saturated than Chrome's browser rendering. The HTML source values (0.38 and
// 0.28) look correct in Chrome but oversaturate on device. Blob centre
// opacities are further reduced to ~0.08 and ~0.05 (from the previous ~0.18
// and ~0.10) based on emulator screenshots.
//
// No blur is used. The soft falloff comes entirely from the 2-stop radial
// gradient (opaque centre → fully transparent at 70% radius), exactly as the
// HTML does — no CSS filter, no Flutter ImageFilter.

import 'package:flutter/material.dart';

import '../../../core/theme/brand_colors.dart';

/// Full-screen Warm Mocha background — espresso solid fill with two ambient
/// radial-gradient blobs in mocha tones.
///
/// Blob 1 (top-right): 300 × 300 logical pixels, rgba(88,56,26,~0.08) core.
///   HTML value 0.38; reduced via two rounds of Android/Impeller compensation.
///   [BoxShape.circle] removed — the RadialGradient soft falloff (stop 0→0.7)
///   is the glow; no circle clip means no Impeller compositing layer, no hard edge.
/// Blob 2 (bottom-left): 220 × 220 logical pixels, rgba(68,42,16,~0.05) core.
///   HTML value 0.28; reduced via two rounds of Android/Impeller compensation.
///   Same BoxShape.circle removal as blob 1.
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
  ///
  /// No BoxShape.circle: removing the circle clip avoids an Impeller compositing
  /// layer that makes the gradient look like a hard-edged disc. The RadialGradient
  /// itself fades to transparent at stop 0.7 (105 px from centre in a 300×300
  /// container), producing a naturally soft circular glow without any explicit clip.
  /// HTML rgba(88,56,26,0.38); reduced to ~0.08 for Android display compensation.
  static const BoxDecoration _blob1 = BoxDecoration(
    gradient: RadialGradient(
      colors: [
        Color(0x14583A1A), // rgba(88,56,26,~0.08)
        Color(0x00583A1A), // transparent
      ],
      stops: [0.0, 0.7],
    ),
  );

  /// Bottom-left ambient blob — darker mocha undertone.
  ///
  /// Same Impeller fix as _blob1: no BoxShape.circle clip. The RadialGradient
  /// fades to transparent at stop 0.7, which is the soft-glow effect.
  /// HTML rgba(68,42,16,0.28); reduced to ~0.05 for Android display compensation.
  static const BoxDecoration _blob2 = BoxDecoration(
    gradient: RadialGradient(
      colors: [
        Color(0x0D442A10), // rgba(68,42,16,~0.05)
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
