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
  // ---------------------------------------------------------------------------
  // Cached base styles — GoogleFonts is called once per style at class-load
  // time. Each public factory method returns the cached instance (or a single
  // cheap copyWith for parameterised variants) so that calling VelvetText.*()
  // inside build() does NOT allocate a fresh TextStyle per frame.
  // ---------------------------------------------------------------------------

  static final TextStyle _wordmarkStyle = GoogleFonts.comfortaa(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: 22 * 0.16,
    color: BrandColors.textSecondary,
  );

  static final TextStyle _headingStyle = GoogleFonts.comfortaa(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.25,
    color: BrandColors.text,
  );

  static final TextStyle _subheadingStyle = GoogleFonts.comfortaa(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: BrandColors.text,
  );

  static final TextStyle _ctaStyle = GoogleFonts.comfortaa(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.3,
    color: BrandColors.white,
  );

  static final TextStyle _bodyStyle = GoogleFonts.nunito(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.5,
    color: BrandColors.textSecondary,
  );

  static final TextStyle _bodyStrongStyle = GoogleFonts.nunito(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.5,
    color: BrandColors.text,
  );

  static final TextStyle _inputStyle = GoogleFonts.nunito(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: BrandColors.text,
  );

  static final TextStyle _labelStyle = GoogleFonts.nunito(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
    color: BrandColors.muted,
  );

  static final TextStyle _linkStyle = GoogleFonts.nunito(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: BrandColors.accentDeep,
  );

  // feedback base — color applied via a single copyWith per call site.
  static final TextStyle _feedbackBase = GoogleFonts.nunito(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    height: 1.4,
  );

  // ---------------------------------------------------------------------------
  // Public API — unchanged call-site signatures.
  // ---------------------------------------------------------------------------

  static TextStyle wordmark() => _wordmarkStyle;
  static TextStyle heading() => _headingStyle;
  static TextStyle subheading() => _subheadingStyle;
  static TextStyle cta() => _ctaStyle;
  static TextStyle body() => _bodyStyle;
  static TextStyle bodyStrong() => _bodyStrongStyle;
  static TextStyle input() => _inputStyle;
  static TextStyle label() => _labelStyle;
  static TextStyle link() => _linkStyle;

  /// Returns a cached Nunito 13/700 base with [color] applied via [copyWith].
  /// One small [copyWith] allocation per call — far cheaper than a full
  /// [GoogleFonts.nunito] construction on every keystroke.
  static TextStyle feedback(Color color) =>
      _feedbackBase.copyWith(color: color);
}
