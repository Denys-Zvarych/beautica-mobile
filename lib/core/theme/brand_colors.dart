import 'package:flutter/material.dart';

/// Beautica brand palette — VelvetTouch design system (2026-05-23).
///
/// Transcribed verbatim from the approved preview app in
/// `docs/signup-designs/VelvetTouchDesign/lib/theme/velvet_tokens.dart`.
/// Only the outer class name was kept as [BrandColors] for source
/// compatibility with existing call sites; every constant name and hex
/// value is a 1:1 copy of [VelvetColors] from the design source.
///
/// Light-mode neumorphic ("soft UI") palette: a single warm-taupe base
/// tone with depth communicated exclusively through paired light/dark
/// shadows. Color is reserved for the camel/mocha accent family and for
/// semantic feedback (always paired with icon + text).
abstract final class BrandColors {
  /// Page + surface base — all neumorphic surfaces share this exact warm
  /// taupe tone. Never pure white so both highlight and shadow read clearly.
  static const Color base = Color(0xFFE6DDD0);

  /// Primary camel accent — CTA gradient base, focus rings, active states.
  static const Color accent = Color(0xFFB89A7A);

  /// Deeper mocha — dark end of the CTA gradient and pressed accents.
  static const Color accentDeep = Color(0xFF6A4A28);

  /// Latte mid-tone — light end of the CTA gradient.
  static const Color accentLatte = Color(0xFF8A6840);

  /// Slightly lifted camel — logo mark only.
  static const Color accentLogo = Color(0xFFC4A988);

  /// Primary text — warm espresso brown, ~7:1 on [base], WCAG AA+.
  static const Color text = Color(0xFF4A3322);

  /// Secondary / body-supporting text (warm coffee brown).
  static const Color textSecondary = Color(0xFF6E5743);

  /// Muted labels (field labels). Use at >= 12 px bold.
  static const Color muted = Color(0xFF9A8367);

  /// Input placeholder text.
  static const Color placeholder = Color(0xFFAD9A82);

  /// Faint hairlines / disabled glyphs.
  static const Color faint = Color(0xFFBCAB95);

  /// Cream — text/glyphs that sit on the camel/mocha CTA fill.
  static const Color white = Color(0xFFF5EDE0);

  // ---------------------------------------------------------------------------
  // Neumorphic shadow tones (on the warm-taupe base)
  // ---------------------------------------------------------------------------

  /// Warm highlight — top-left lift. Creamy near-white, stays warm family.
  static const Color shadowLightStrong = Color(0xFFFFFBF4);

  /// Warm taupe-brown card shadow — bottom-right recess.
  static const Color shadowDarkCard = Color(0xFFC4B49E);

  /// Warm taupe-brown button shadow — slightly deeper than the card.
  static const Color shadowDarkButton = Color(0xFFC0AF98);

  // ---------------------------------------------------------------------------
  // Semantic feedback (both >=4.5:1 on [base]; always paired with icon+text)
  // ---------------------------------------------------------------------------

  /// Error state — validation failures, cancellation.
  static const Color error = Color(0xFFB0452F);

  /// Success state — positive confirmation.
  static const Color success = Color(0xFF5C7A4A);

  /// Material 3 seed — used for [ColorScheme.fromSeed].
  static const Color seed = accentDeep;
}
