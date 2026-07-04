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

  /// Role chip label at 11 sp — used by RoleChip to fit 'Незалежний майстер'
  /// without truncation on typical phone widths.
  static final TextStyle feedbackAccentXs = _feedbackBase.copyWith(
    color: BrandColors.accentDeep,
    fontSize: 11,
  );

  /// Address / location text at 11 sp — used by master profile identity card
  /// to fit longer address strings without truncation.
  static final TextStyle feedbackMutedXs = _feedbackBase.copyWith(
    color: BrandColors.muted,
    fontSize: 11,
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

  // ---------------------------------------------------------------------------
  // Phase 5.2 — Service list screen styles.
  //
  // Transcribed from the approved preview app at
  // `docs/signup-designs/ServiceListScreen/lib/theme/velvet_tokens.dart`
  // (VelvetText.cardTitle / VelvetText.pill additive section). Color references
  // changed from VelvetColors.* to BrandColors.*. Cached as static finals so
  // build() never allocates a new TextStyle per frame.
  // ---------------------------------------------------------------------------

  static final TextStyle _cardTitleStyle = GoogleFonts.comfortaa(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: BrandColors.text,
  );

  static final TextStyle _pillStyle = GoogleFonts.nunito(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.2,
    color: BrandColors.accentDeep,
  );

  /// Service name on a card — Comfortaa 17/700, espresso. A touch heavier than
  /// [subheading] so the service title is the clear anchor of each row.
  static TextStyle cardTitle() => _cardTitleStyle;

  // ---------------------------------------------------------------------------
  // Schedule month-navigator title — a slightly smaller subheading used by the
  // two-row month/year stack in master_schedule_screen. Same Comfortaa family,
  // weight, and color as [subheading] (so it still reads as the header) but at
  // 14 sp instead of 17 sp, giving a tasteful one-step reduction that keeps the
  // fixed two-row stack compact. Cached once at class-load time.
  // ---------------------------------------------------------------------------

  /// Month-navigator header title — Comfortaa 14/600, espresso (a touch smaller
  /// than [subheading]). Used for both the month and year rows.
  static final TextStyle monthNavTitle = _subheadingStyle.copyWith(
    fontSize: 14,
    height: 1.1,
  );

  /// Pill content (duration / price chips) — Nunito 13/800, accentDeep with
  /// mild tracking so the short strings sit evenly inside the inset chip.
  static TextStyle pill() => _pillStyle;

  // ---------------------------------------------------------------------------
  // mobile-perf Finding C (Phase 14.16/14.17 salon booking time-picker audit)
  // — pre-composed statics replacing per-`build()` `.copyWith()` allocations
  // across salon_time_screen.dart, salon_master_strip.dart,
  // schedule_confirm_bar.dart, and master_schedule_page.dart. Each field is
  // computed exactly once at class-load time (zero per-frame cost).
  // ---------------------------------------------------------------------------

  /// `_StepIndicator`'s step-pill label ("Крок 3 з 4") on `SalonTimeScreen`'s
  /// top bar — feedback base, textSecondary, 12 sp, w800.
  static final TextStyle stepPillLabel = _feedbackBase.copyWith(
    color: BrandColors.textSecondary,
    fontSize: 12,
    fontWeight: FontWeight.w800,
  );

  /// `_MasterPager`'s "N / M" counter under the dots — same shape as
  /// [stepPillLabel]; named separately since the two call sites are
  /// independent and may diverge later.
  static final TextStyle schedulePagerCounter = _feedbackBase.copyWith(
    color: BrandColors.textSecondary,
    fontSize: 12,
    fontWeight: FontWeight.w800,
  );

  /// `SalonMasterStrip`'s small "Ви записуєтесь до" prefix label — feedback
  /// base, textSecondary, 11 sp.
  static final TextStyle masterStripLabel = _feedbackBase.copyWith(
    color: BrandColors.textSecondary,
    fontSize: 11,
  );

  /// `SalonMasterStrip`'s master display name — subheading at 16 sp.
  static final TextStyle masterStripName = _subheadingStyle.copyWith(
    fontSize: 16,
  );

  /// `SalonMasterStrip`'s assigned-services line — feedback base,
  /// accentDeep, 12 sp, w800.
  static final TextStyle masterStripServiceLabel = _feedbackBase.copyWith(
    color: BrandColors.accentDeep,
    fontSize: 12,
    fontWeight: FontWeight.w800,
  );

  /// `SalonMasterStrip`'s summed-duration pill label — bodyStrong at 12 sp,
  /// w800, accentDeep.
  static final TextStyle masterStripDurationLabel = _bodyStrongStyle.copyWith(
    fontSize: 12,
    fontWeight: FontWeight.w800,
    color: BrandColors.accentDeep,
  );

  /// `ScheduleConfirmBar`'s summed-duration caption beside the "Разом"
  /// label — feedback base, muted, 12 sp.
  static final TextStyle scheduleConfirmDurationLabel = _feedbackBase.copyWith(
    color: BrandColors.muted,
    fontSize: 12,
  );

  /// `ScheduleConfirmBar`'s total price figure — bodyStrong at 18 sp, w800,
  /// accentDeep.
  static final TextStyle scheduleConfirmPriceLabel = _bodyStrongStyle.copyWith(
    color: BrandColors.accentDeep,
    fontWeight: FontWeight.w800,
    fontSize: 18,
  );

  /// `_ProgressHint`'s "X з Y заплановано" label — feedback base,
  /// textSecondary, w800 (13 sp, unchanged from the base).
  static final TextStyle scheduleProgressHintLabel = _feedbackBase.copyWith(
    color: BrandColors.textSecondary,
    fontWeight: FontWeight.w800,
  );

  /// `MasterSchedulePage`'s date-phase intro copy — body at 14 sp.
  static final TextStyle scheduleDateIntro = _bodyStyle.copyWith(fontSize: 14);

  /// `MasterSchedulePage`'s "Вільний час" section heading — subheading at
  /// 16 sp.
  static final TextStyle scheduleTimeHeading = _subheadingStyle.copyWith(
    fontSize: 16,
  );

  /// `MasterSchedulePage`'s day-unavailable error copy — feedback base,
  /// muted (13 sp, unchanged from the base) — pre-cached so the per-build
  /// `VelvetText.feedback(...)` call is avoided entirely.
  static final TextStyle dayUnavailableLabel = _feedbackBase.copyWith(
    color: BrandColors.muted,
  );

  /// `_DayHeaderChip`'s formatted-day title ("Пн, 5 липня") — subheading at
  /// 16 sp, accentDeep.
  static final TextStyle dayHeaderTitle = _subheadingStyle.copyWith(
    fontSize: 16,
    color: BrandColors.accentDeep,
  );

  /// `_DayHeaderChip`'s "masterName · role" subtitle — feedback base,
  /// textSecondary, 11 sp.
  static final TextStyle dayHeaderSubtitle = _feedbackBase.copyWith(
    color: BrandColors.textSecondary,
    fontSize: 11,
  );

  /// `_DayHeaderChip`'s «Змінити» change-date CTA label — feedback base,
  /// accentDeep, 13 sp, w800.
  static final TextStyle changeDateCta = _feedbackBase.copyWith(
    color: BrandColors.accentDeep,
    fontSize: 13,
    fontWeight: FontWeight.w800,
  );

  /// `_WindowLine`'s unchosen-slot prompt ("Оберіть час…") — feedback base,
  /// textSecondary, 13 sp.
  static final TextStyle windowLinePrompt = _feedbackBase.copyWith(
    color: BrandColors.textSecondary,
    fontSize: 13,
  );

  /// `_WindowLine`'s chosen-window value label — bodyStrong at 14 sp, w800,
  /// accentDeep.
  static final TextStyle windowLineAccent = _bodyStrongStyle.copyWith(
    color: BrandColors.accentDeep,
    fontWeight: FontWeight.w800,
    fontSize: 14,
  );
}
