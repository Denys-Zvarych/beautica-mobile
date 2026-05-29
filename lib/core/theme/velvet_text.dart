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
    // Wordmark needs >=4.5:1 contrast on BrandColors.base for WCAG AA — the
    // previous textSecondary (#6E5743) read at ~3.2:1 and was illegible on the
    // warm taupe splash background; textPrimary (#4A3322) is ~7:1 (WCAG AA+).
    color: BrandColors.text,
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

  // ---------------------------------------------------------------------------
  // Pre-composed cached variants (Batch-2 A2).
  //
  // These replace per-build `SomeStyle().copyWith(...)` call sites that were
  // allocating a new TextStyle object on every frame / keystroke.  Each field
  // is computed exactly once at class-load time.
  // ---------------------------------------------------------------------------

  /// Heading at 26 sp — used by DoneScreen greeting headline.
  static final TextStyle headingLg = _headingStyle.copyWith(fontSize: 26);

  /// Subheading with camel accent + italic — used by DoneScreen subtitle.
  static final TextStyle subheadingItalicAccent = _subheadingStyle.copyWith(
    color: BrandColors.accentDeep,
    fontStyle: FontStyle.italic,
  );

  /// Body at 13 sp — used by DoneScreen description copy.
  static final TextStyle bodySmall = _bodyStyle.copyWith(fontSize: 13);

  /// Feedback label for summary chips — Nunito 13/700 in [BrandColors.textSecondary]
  /// at 12.5 sp. Used by DoneScreen _SummaryChip.
  static final TextStyle chipLabel = _feedbackBase.copyWith(
    color: BrandColors.textSecondary,
    fontSize: 12.5,
  );

  /// OTP digit style — Heading at 24 sp, camel accent color.
  /// Used by verification_screen._OtpCell (Batch-2 A3).
  static final TextStyle otpDigit = _headingStyle.copyWith(
    fontSize: 24,
    color: BrandColors.accent,
  );

  /// Cooldown resend link style — link weight with muted color.
  /// Used by verification_screen._ResendRowState cooldown branch (Batch-2 A3).
  static final TextStyle resendCooldown = _linkStyle.copyWith(
    color: BrandColors.faint,
  );

  // ---------------------------------------------------------------------------
  // Pre-composed variants for PasswordChecklist _RuleRow (Batch-2 A5).
  //
  // Replaces the per-keystroke `VelvetText.feedback(color).copyWith(...)` call
  // that was allocating 2 TextStyle objects per rule per keystroke (6 per
  // keystroke with 3 rules).  Each field is computed exactly once at class-load
  // time.
  // ---------------------------------------------------------------------------

  /// Feedback label for a met password rule — Nunito 13/w700, success green.
  static final TextStyle feedbackMet = _feedbackBase.copyWith(
    color: BrandColors.success,
    fontWeight: FontWeight.w700,
  );

  /// Feedback label for an unmet password rule — Nunito 13/w600, muted color.
  static final TextStyle feedbackUnmet = _feedbackBase.copyWith(
    color: BrandColors.muted,
    fontWeight: FontWeight.w600,
  );

  /// Small link style at 13 sp — used by the terms/privacy inline spans on
  /// RegisterStep1Screen. Replaces `link().copyWith(fontSize: 13)` call sites
  /// that were allocating a new TextStyle on every parent rebuild (Batch-2 A5).
  static final TextStyle linkSmall = _linkStyle.copyWith(fontSize: 13);

  // ---------------------------------------------------------------------------
  // Phase 4.2 fix (PERF MEDIUM-1) — pre-cached feedback variants for the
  // master profile city label and role chip, replacing per-frame
  // `feedback(color).copyWith(fontSize: 12)` allocations.
  // ---------------------------------------------------------------------------

  /// Feedback label for the city / location text — Nunito 13/700, muted, 12 sp.
  static final TextStyle feedbackMutedSm = _feedbackBase.copyWith(
    color: BrandColors.muted,
    fontSize: 12,
  );

  /// Location note sub-row — Nunito 13/700, muted, 11 sp.
  /// Used for the optional [Master.locationNote] indented row on the identity
  /// card. Pre-cached here so the profile screen never calls `.copyWith()` per
  /// build frame (PERF MEDIUM pattern).
  static final TextStyle feedbackMutedNote = _feedbackBase.copyWith(
    color: BrandColors.muted,
    fontSize: 11,
  );

  /// Feedback label for the role chip / accent small text — Nunito 13/700,
  /// accentDeep, 12 sp.
  static final TextStyle feedbackAccentSm = _feedbackBase.copyWith(
    color: BrandColors.accentDeep,
    fontSize: 12,
  );

  // ---------------------------------------------------------------------------
  // Phase 4.x consolidated MEDIUM fixes — pre-composed statics replacing
  // `feedback(color).copyWith(fontSize: N)` double-allocation call sites.
  // Each field is computed once at class-load time (zero per-frame cost).
  // ---------------------------------------------------------------------------

  /// Nav-tab label — Nunito 13/700, dynamic color applied via a single copyWith.
  /// Base for `_VelvetNavTile`: callers do `navTabLabel.copyWith(color: color)`.
  static final TextStyle navTabLabel = _feedbackBase.copyWith(
    color: BrandColors.muted,
    fontSize: 10,
  );

  /// ContactTile platform label (e.g. "Instagram") — Nunito 13/700,
  /// textSecondary, 11 sp.
  static final TextStyle contactPlatformLabel = _feedbackBase.copyWith(
    color: BrandColors.textSecondary,
    fontSize: 11,
  );

  /// ServiceTile duration label — Nunito 13/700, muted, 12 sp.
  static final TextStyle serviceDurationLabel = _feedbackBase.copyWith(
    color: BrandColors.muted,
    fontSize: 12,
  );

  /// ServiceTile price label — Nunito 13/700, accentDeep, 13 sp.
  static final TextStyle servicePriceLabel = _feedbackBase.copyWith(
    color: BrandColors.accentDeep,
    fontSize: 13,
  );

  // ---------------------------------------------------------------------------
  // Phase 4.2 — Master Profile styles.
  //
  // Transcribed verbatim from the approved preview app at
  // `docs/signup-designs/MasterProfileScreen/lib/theme/velvet_tokens.dart`
  // (VelvetText.displayName / sectionLabel / statValue / statCaption).
  // Color references changed from VelvetColors.* to BrandColors.*.
  // ---------------------------------------------------------------------------

  static final TextStyle _displayNameStyle = GoogleFonts.comfortaa(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: BrandColors.text,
  );

  static final TextStyle _sectionLabelStyle = GoogleFonts.comfortaa(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
    color: BrandColors.textSecondary,
  );

  static final TextStyle _statValueStyle = GoogleFonts.comfortaa(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: BrandColors.text,
  );

  static final TextStyle _statCaptionStyle = GoogleFonts.nunito(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.3,
    color: BrandColors.textSecondary,
  );

  /// Display name on the master profile — Comfortaa 22/700, espresso.
  static TextStyle displayName() => _displayNameStyle;

  /// Section label ("Про себе", "Послуги") — Comfortaa 13/600, secondary.
  static TextStyle sectionLabel() => _sectionLabelStyle;

  /// Big numeric value in a stat tile — Comfortaa 20/700, espresso.
  static TextStyle statValue() => _statValueStyle;

  /// Small caption under a stat tile — Nunito 11/700, secondary.
  static TextStyle statCaption() => _statCaptionStyle;
}
