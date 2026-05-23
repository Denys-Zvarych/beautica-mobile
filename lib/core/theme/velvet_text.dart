import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';

/// VelvetTouch typography helpers.
///
/// Comfortaa is used for display / heading / CTA copy; Nunito for body,
/// inputs, labels, and links. Both fonts are served via `google_fonts` —
/// no additional dependency is required.
///
/// Transcribed verbatim from the approved Flutter preview app at
/// `docs/signup-designs/VelvetTouchDesign/lib/theme/velvet_tokens.dart`
/// (`VelvetText` class). Only the color references were changed from
/// `VelvetColors.` to `BrandColors.` for source-compatibility with the
/// project's existing call sites.
abstract final class VelvetText {
  static TextStyle wordmark() => GoogleFonts.comfortaa(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: 22 * 0.16,
    color: BrandColors.textSecondary,
  );

  static TextStyle heading() => GoogleFonts.comfortaa(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.25,
    color: BrandColors.text,
  );

  static TextStyle subheading() => GoogleFonts.comfortaa(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: BrandColors.text,
  );

  static TextStyle cta() => GoogleFonts.comfortaa(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.3,
    color: BrandColors.white,
  );

  static TextStyle body() => GoogleFonts.nunito(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.5,
    color: BrandColors.textSecondary,
  );

  static TextStyle bodyStrong() => GoogleFonts.nunito(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.5,
    color: BrandColors.text,
  );

  static TextStyle input() => GoogleFonts.nunito(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: BrandColors.text,
  );

  static TextStyle label() => GoogleFonts.nunito(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
    color: BrandColors.muted,
  );

  static TextStyle link() => GoogleFonts.nunito(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: BrandColors.accentDeep,
  );

  static TextStyle feedback(Color color) => GoogleFonts.nunito(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    height: 1.4,
    color: color,
  );
}
