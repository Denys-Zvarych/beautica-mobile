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

  // ---------------------------------------------------------------------------
  // Discovery (search) — result cards, category rail, filters, sort sheet.
  // Consolidated from inline `VelvetText.body()/bodyStrong().copyWith(fontSize:)`
  // call sites so every size lives here. Each is cached once at class-load.
  // ---------------------------------------------------------------------------

  /// Result-card locality / muted secondary line — body 12.5 sp, muted.
  static final TextStyle discLocality = _bodyStyle.copyWith(
    fontSize: 12.5,
    color: BrandColors.muted,
  );

  /// Shared muted caption — body 12 sp, muted. Used by the result-card
  /// address-detail line, the filter helper text, and the price end-label.
  static final TextStyle discCaptionMuted = _bodyStyle.copyWith(
    fontSize: 12,
    color: BrandColors.muted,
  );

  /// Result-card bold numeric rating value — bodyStrong 13 sp.
  static final TextStyle discRatingValue = _bodyStrongStyle.copyWith(
    fontSize: 13,
  );

  /// Accent price figure — bodyStrong 14 sp, accentDeep. Used by the result
  /// card «від N грн» line and the filter price readout.
  static final TextStyle discPriceAccent = _bodyStrongStyle.copyWith(
    fontSize: 14,
    color: BrandColors.accentDeep,
  );

  /// Result-card service-names preview line — body 12.5 sp, secondary.
  static final TextStyle discServicesPreview = _bodyStyle.copyWith(
    fontSize: 12.5,
    color: BrandColors.textSecondary,
  );

  /// Category-rail label (resting) — body 12 sp, w700, secondary, height 1.15.
  static final TextStyle discCategoryLabelResting = _bodyStyle.copyWith(
    fontSize: 12,
    height: 1.15,
    fontWeight: FontWeight.w700,
    color: BrandColors.textSecondary,
  );

  /// Category-rail label (selected) — body 12 sp, w700, accentDeep, height 1.15.
  static final TextStyle discCategoryLabelSelected = _bodyStyle.copyWith(
    fontSize: 12,
    height: 1.15,
    fontWeight: FontWeight.w700,
    color: BrandColors.accentDeep,
  );

  /// Service-type tile caption (selected) — body 12 sp, w700, accentDeep.
  static final TextStyle discServiceTypeSelected = _bodyStyle.copyWith(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: BrandColors.accentDeep,
  );

  /// Service-type tile caption (unselected) — body 12 sp, w700, secondary.
  static final TextStyle discServiceTypeUnselected = _bodyStyle.copyWith(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: BrandColors.textSecondary,
  );

  /// Service-chip drawer label — body 13 sp, w700. Colour (white/text when
  /// selected) is applied at the call site via a single copyWith.
  static final TextStyle discChipLabel = _bodyStyle.copyWith(
    fontSize: 13,
    fontWeight: FontWeight.w700,
  );

  /// Sort-options sheet row label — body 15 sp, w700, primary text.
  static final TextStyle discSortOption = _bodyStyle.copyWith(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: BrandColors.text,
  );

  /// Filter «Очистити» clear-button label — body 13 sp, w600.
  static final TextStyle discClearButton = _bodyStyle.copyWith(
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );

  /// Search-results header count — body 14 sp, w700, accent.
  static final TextStyle discResultCount = _bodyStyle.copyWith(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: BrandColors.accent,
  );

  // ---------------------------------------------------------------------------
  // Generic size variants reused across features. Named by the base role +
  // size so callers stop re-deriving them inline.
  // ---------------------------------------------------------------------------

  /// Heading one step smaller than the base — Comfortaa 22 sp. Used by
  /// empty-state titles (services list) and section titles (schedule widgets).
  static final TextStyle headingSm = _headingStyle.copyWith(fontSize: 22);

  /// Subheading at 16 sp — Comfortaa 16/600. Used by the services accordion
  /// header and the service-setup row name (which overrides colour).
  static final TextStyle subheading16 = _subheadingStyle.copyWith(fontSize: 16);

  /// CTA label one step smaller — Comfortaa 14/700, white. Used by the
  /// change-photo label and the selected pricing segment.
  static final TextStyle ctaSm = _ctaStyle.copyWith(fontSize: 14);

  /// Inset accent pill at 12.5 sp — Nunito 13/800 accentDeep. Used by the
  /// service-card duration/price chips and the master-profile stat chip.
  static final TextStyle pillSm = _pillStyle.copyWith(fontSize: 12.5);

  /// Body at 12 sp — Nunito 12/600, secondary (base body colour retained).
  static final TextStyle body12 = _bodyStyle.copyWith(fontSize: 12);

  /// Body at 14 sp — Nunito 14/600, secondary (base body colour retained).
  static final TextStyle body14 = _bodyStyle.copyWith(fontSize: 14);

  /// Strong body at 13 sp — Nunito 13/700, primary text.
  static final TextStyle bodyStrong13 = _bodyStrongStyle.copyWith(fontSize: 13);

  /// Strong body at 14 sp — Nunito 14/700, primary text.
  static final TextStyle bodyStrong14 = _bodyStrongStyle.copyWith(fontSize: 14);

  /// Body at 13 sp — Nunito 13/600, secondary (base body colour retained).
  static final TextStyle body13 = _bodyStyle.copyWith(fontSize: 13);

  /// Strong body at 15 sp — Nunito 15/700, primary text.
  static final TextStyle bodyStrong15 = _bodyStrongStyle.copyWith(fontSize: 15);

  /// Strong body at 16 sp — Nunito 16/700, primary text.
  static final TextStyle bodyStrong16 = _bodyStrongStyle.copyWith(fontSize: 16);

  /// Heading at 20 sp — Comfortaa 20/700, espresso. Sheet / section titles.
  static final TextStyle heading20 = _headingStyle.copyWith(fontSize: 20);

  /// Label at 11 sp — Nunito 11/700, muted, letterSpacing 0.6.
  static final TextStyle label11 = _labelStyle.copyWith(fontSize: 11);

  /// Link at 13 sp — Nunito 13/700, accentDeep. Small inline action links.
  static final TextStyle link13 = _linkStyle.copyWith(fontSize: 13);

  /// Subheading at 15 sp — Comfortaa 15/600, espresso.
  static final TextStyle subheading15 = _subheadingStyle.copyWith(fontSize: 15);

  /// Strong body at 13.5 sp — Nunito 13.5/700, primary text.
  static final TextStyle bodyStrong135 = _bodyStrongStyle.copyWith(
    fontSize: 13.5,
  );

  /// Strong body at 14.5 sp — Nunito 14.5/700, primary text.
  static final TextStyle bodyStrong145 = _bodyStrongStyle.copyWith(
    fontSize: 14.5,
  );

  // ---------------------------------------------------------------------------
  // Services — list cards, setup accordion, pricing segments, photo slot.
  // ---------------------------------------------------------------------------

  /// Service-card name — cardTitle 15 sp, height 1.15.
  static final TextStyle svcCardName = _cardTitleStyle.copyWith(
    fontSize: 15,
    height: 1.15,
  );

  /// Category count pill ("n з m") — pill 12 sp. Colour applied at call site.
  static final TextStyle svcCountPill = _pillStyle.copyWith(fontSize: 12);

  /// Category-group header line — body 12 sp, height 1.4, w800, accentDeep.
  static final TextStyle svcGroupHeader = _bodyStyle.copyWith(
    fontSize: 12,
    height: 1.4,
    fontWeight: FontWeight.w800,
    color: BrandColors.accentDeep,
  );

  /// Small caption note (excluded row / missing-service note) — body 12 sp,
  /// height 1.4.
  static final TextStyle svcCaptionNote = _bodyStyle.copyWith(
    fontSize: 12,
    height: 1.4,
  );

  /// Unselected pricing segment label — cta 14 sp, w600, secondary.
  static final TextStyle svcSegmentUnselected = _ctaStyle.copyWith(
    fontSize: 14,
    color: BrandColors.textSecondary,
    fontWeight: FontWeight.w600,
  );

  // ---------------------------------------------------------------------------
  // Shell — branch placeholders + client bottom-nav labels.
  // ---------------------------------------------------------------------------

  /// «Coming soon» placeholder chip label — feedback base, secondary, 12 sp.
  static final TextStyle shellComingSoonLabel = _feedbackBase.copyWith(
    color: BrandColors.textSecondary,
    fontSize: 12,
  );

  /// Client bottom-nav label (active) — feedback base, accentDeep, 9 sp,
  /// height 1.1, letterSpacing 0.1.
  static final TextStyle shellNavLabelActive = _feedbackBase.copyWith(
    color: BrandColors.accentDeep,
    fontSize: 9,
    height: 1.1,
    letterSpacing: 0.1,
  );

  /// Client bottom-nav label (inactive) — feedback base, muted, 9 sp,
  /// height 1.1, letterSpacing 0.1.
  static final TextStyle shellNavLabelInactive = _feedbackBase.copyWith(
    color: BrandColors.muted,
    fontSize: 9,
    height: 1.1,
    letterSpacing: 0.1,
  );

  // ---------------------------------------------------------------------------
  // Schedule — time pickers, interval/discrete editors, week grid, template.
  // Colours that vary at runtime (selected / active / tint) are applied at the
  // call site via a single copyWith on these cached bases.
  // ---------------------------------------------------------------------------

  /// Time-picker wheel digit — heading 24 sp with tabular figures.
  static final TextStyle schedWheelDigit = _headingStyle.copyWith(
    fontSize: 24,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  /// Discrete-times window label — label 12 sp, w700, accentDeep.
  static final TextStyle schedWindowLabel = _labelStyle.copyWith(
    fontSize: 12,
    color: BrandColors.accentDeep,
    fontWeight: FontWeight.w700,
  );

  /// Discrete-times chip label — bodyStrong 13 sp, accentDeep, tabular figures.
  static final TextStyle schedTimeChip = _bodyStrongStyle.copyWith(
    fontSize: 13,
    color: BrandColors.accentDeep,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  /// Interval-editor time value — input 17 sp, w700, tabular figures. Colour
  /// (accent / text) applied at the call site.
  static final TextStyle schedIntervalTime = _inputStyle.copyWith(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  /// Row action link (regular) — link 14 sp, accentDeep.
  static final TextStyle schedActionLink = _linkStyle.copyWith(
    color: BrandColors.accentDeep,
    fontSize: 14,
  );

  /// Row action link (dense) — link 13 sp, accentDeep.
  static final TextStyle schedActionLinkDense = _linkStyle.copyWith(
    color: BrandColors.accentDeep,
    fontSize: 13,
  );

  /// Read-only time-grid axis label — label 12 sp, secondary.
  static final TextStyle schedTimeAxisLabel = _labelStyle.copyWith(
    fontSize: 12,
    color: BrandColors.textSecondary,
  );

  /// Weekly-template unset-window prompt — bodyStrong 13 sp, w600, placeholder.
  static final TextStyle schedWindowUnset = _bodyStrongStyle.copyWith(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: BrandColors.placeholder,
  );

  // ---------------------------------------------------------------------------
  // Auth register step 3 + registration progress indicator.
  //
  // NOTE: the field-tip and progress-number styles are intentionally RAW
  // (no explicit font family — they inherit the ambient DefaultTextStyle), so
  // they are plain `const TextStyle`s rather than GoogleFonts-derived tokens.
  // ---------------------------------------------------------------------------

  /// Field tip caption (register step 3) — accent, 10 sp, w700, height 1.
  static const TextStyle authFieldTip = TextStyle(
    color: BrandColors.accent,
    fontSize: 10,
    fontWeight: FontWeight.w700,
    height: 1,
  );

  /// Optional-tag label (register step 3 oblast) — muted camel, 11 sp, w600.
  static const TextStyle authOptionalTag = TextStyle(
    color: Color(0x8CB89A7A),
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
  );

  /// Progress-dot number (active) — 10 sp, w700, dark, height 1.
  static const TextStyle authProgressNumActive = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    color: Color(0xFF3A2810),
    height: 1,
  );

  /// Progress-dot number (inactive) — 10 sp, w700, faint white, height 1.
  static const TextStyle authProgressNumInactive = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    color: Color(0x47FFFFFF),
    height: 1,
  );

  /// Progress step label — Comfortaa italic 14/600, accent, height 1,
  /// letterSpacing 0.14.
  static final TextStyle authProgressLabel = GoogleFonts.comfortaa(
    textStyle: const TextStyle(
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w600,
      fontSize: 14,
      color: BrandColors.accent,
      height: 1,
      letterSpacing: 0.14,
    ),
  );

  // ---------------------------------------------------------------------------
  // Booking — salon service/master selection, summary bar/cards, recap, slot
  // picker, month calendar, success. Runtime-varying colours (selected /
  // numberColor / per-slot) are applied at the call site via one copyWith.
  // ---------------------------------------------------------------------------

  /// Chip caption — feedback, secondary, 12 sp, w800.
  static final TextStyle bookChipSecW800 = _feedbackBase.copyWith(
    color: BrandColors.textSecondary,
    fontSize: 12,
    fontWeight: FontWeight.w800,
  );

  /// «covered services» label — feedback, accentDeep, 12 sp, w800.
  static final TextStyle bookCoveredLabel = _feedbackBase.copyWith(
    color: BrandColors.accentDeep,
    fontSize: 12,
    fontWeight: FontWeight.w800,
  );

  /// Feedback caption — placeholder, 12.5 sp.
  static final TextStyle bookFeedbackPlaceholder125 = _feedbackBase.copyWith(
    color: BrandColors.placeholder,
    fontSize: 12.5,
  );

  /// Feedback caption — placeholder, 11.5 sp.
  static final TextStyle bookFeedbackPlaceholder115 = _feedbackBase.copyWith(
    color: BrandColors.placeholder,
    fontSize: 11.5,
  );

  /// Feedback caption — secondary, 12.5 sp.
  static final TextStyle bookFeedbackSec125 = _feedbackBase.copyWith(
    color: BrandColors.textSecondary,
    fontSize: 12.5,
  );

  /// Feedback caption — secondary, 13 sp.
  static final TextStyle bookFeedbackSec13 = _feedbackBase.copyWith(
    color: BrandColors.textSecondary,
    fontSize: 13,
  );

  /// Feedback caption — secondary, 13 sp, w800.
  static final TextStyle bookFeedbackSec13w800 = _feedbackBase.copyWith(
    color: BrandColors.textSecondary,
    fontSize: 13,
    fontWeight: FontWeight.w800,
  );

  /// Feedback pill — 12.5 sp, w800. Colour (selected / secondary) at call site.
  static final TextStyle bookFeedback125w800 = _feedbackBase.copyWith(
    fontSize: 12.5,
    fontWeight: FontWeight.w800,
  );

  /// Feedback caption — muted, 11.5 sp.
  static final TextStyle bookFeedbackMuted115 = _feedbackBase.copyWith(
    color: BrandColors.muted,
    fontSize: 11.5,
  );

  /// Feedback caption — muted, 12.5 sp.
  static final TextStyle bookFeedbackMuted125 = _feedbackBase.copyWith(
    color: BrandColors.muted,
    fontSize: 12.5,
  );

  /// Feedback caption — muted, 14 sp (summary-bar total label).
  static final TextStyle bookSummaryMuted14 = _feedbackBase.copyWith(
    color: BrandColors.muted,
    fontSize: 14,
  );

  /// Accordion tag on selected row — feedback, white, 11 sp, w800.
  static final TextStyle bookFeedbackWhite11w800 = _feedbackBase.copyWith(
    color: BrandColors.white,
    fontSize: 11,
    fontWeight: FontWeight.w800,
  );

  /// Service-group name — bodyStrong 14.5 sp, accentDeep, w800.
  static final TextStyle bookGroupName = _bodyStrongStyle.copyWith(
    fontSize: 14.5,
    color: BrandColors.accentDeep,
    fontWeight: FontWeight.w800,
  );

  /// Accent numeric value — bodyStrong 14 sp, accentDeep, w800.
  static final TextStyle bookAccentValue14 = _bodyStrongStyle.copyWith(
    color: BrandColors.accentDeep,
    fontWeight: FontWeight.w800,
    fontSize: 14,
  );

  /// Total-price figure (medium) — bodyStrong 17 sp, accentDeep, w800.
  static final TextStyle bookPriceMd = _bodyStrongStyle.copyWith(
    color: BrandColors.accentDeep,
    fontWeight: FontWeight.w800,
    fontSize: 17,
  );

  /// Total-price figure (large) — bodyStrong 18 sp, accentDeep, w800.
  static final TextStyle bookPriceLg = _bodyStrongStyle.copyWith(
    color: BrandColors.accentDeep,
    fontWeight: FontWeight.w800,
    fontSize: 18,
  );

  /// Recap accent value (compact) — bodyStrong 13.5 sp, accentDeep, w800.
  static final TextStyle bookAccentBold135 = _bodyStrongStyle.copyWith(
    color: BrandColors.accentDeep,
    fontWeight: FontWeight.w800,
    fontSize: 13.5,
  );

  /// Recap accent value (regular) — bodyStrong 15 sp, accentDeep, w800.
  static final TextStyle bookAccentBold15 = _bodyStrongStyle.copyWith(
    color: BrandColors.accentDeep,
    fontWeight: FontWeight.w800,
    fontSize: 15,
  );

  /// Recap accent value (compact, large) — bodyStrong 15.5 sp, accentDeep, w800.
  static final TextStyle bookAccentBold155 = _bodyStrongStyle.copyWith(
    color: BrandColors.accentDeep,
    fontWeight: FontWeight.w800,
    fontSize: 15.5,
  );

  /// Recap service name (compact) — bodyStrong 14.5 sp, w800.
  static final TextStyle bookName145w800 = _bodyStrongStyle.copyWith(
    fontSize: 14.5,
    fontWeight: FontWeight.w800,
  );

  /// Recap service name (regular) — bodyStrong 16 sp, w800.
  static final TextStyle bookName16w800 = _bodyStrongStyle.copyWith(
    fontSize: 16,
    fontWeight: FontWeight.w800,
  );

  /// Summary-card value (compact) — bodyStrong 13.5 sp, height 1.3.
  static final TextStyle bookCardValue135 = _bodyStrongStyle.copyWith(
    fontSize: 13.5,
    height: 1.3,
  );

  /// Summary-card value (regular) — bodyStrong 15 sp, height 1.3.
  static final TextStyle bookCardValue15 = _bodyStrongStyle.copyWith(
    fontSize: 15,
    height: 1.3,
  );

  /// Slot chip label — bodyStrong 14 sp, w800. Colour applied at the call site.
  static final TextStyle bookSlotChip = _bodyStrongStyle.copyWith(
    fontWeight: FontWeight.w800,
    fontSize: 14,
  );

  /// Slot time-group sub-label — sectionLabel 12 sp.
  static final TextStyle bookSlotGroupLabel = _sectionLabelStyle.copyWith(
    fontSize: 12,
  );

  /// Success-screen subline — body 13 sp, height 1.35.
  static final TextStyle bookSuccessSubline = _bodyStyle.copyWith(
    height: 1.35,
    fontSize: 13,
  );

  /// Success-screen «add to calendar» CTA — bodyStrong 14.5 sp, accentDeep.
  static final TextStyle bookCalendarCta = _bodyStrongStyle.copyWith(
    fontSize: 14.5,
    color: BrandColors.accentDeep,
  );

  /// Comment field hint — body 14 sp, placeholder.
  static final TextStyle bookCommentHint = _bodyStyle.copyWith(
    fontSize: 14,
    color: BrandColors.placeholder,
  );

  // ---------------------------------------------------------------------------
  // Additional generic size variants (home / salon / passport / rating).
  // ---------------------------------------------------------------------------

  /// Body at 10.5 sp — Nunito 10.5/600, secondary.
  static final TextStyle body105 = _bodyStyle.copyWith(fontSize: 10.5);

  /// Body at 11 sp — Nunito 11/600, secondary.
  static final TextStyle body11 = _bodyStyle.copyWith(fontSize: 11);

  /// Body at 12.5 sp — Nunito 12.5/600, secondary.
  static final TextStyle body125 = _bodyStyle.copyWith(fontSize: 12.5);

  /// Body at 14 sp in primary text colour — Nunito 14/600, text.
  static final TextStyle body14Text = _bodyStyle.copyWith(
    fontSize: 14,
    color: BrandColors.text,
  );

  /// Strong body at 12 sp — Nunito 12/700, primary text.
  static final TextStyle bodyStrong12 = _bodyStrongStyle.copyWith(fontSize: 12);

  /// Subheading at 12 sp — Comfortaa 12/600. Colour/weight vary at call site.
  static final TextStyle subheading12 = _subheadingStyle.copyWith(fontSize: 12);

  /// Subheading at 14 sp — Comfortaa 14/600.
  static final TextStyle subheading14 = _subheadingStyle.copyWith(fontSize: 14);

  /// Heading at 18 sp — Comfortaa 18/700.
  static final TextStyle heading18 = _headingStyle.copyWith(fontSize: 18);

  /// Display name at 20 sp — Comfortaa 20/700.
  static final TextStyle displayName20 = _displayNameStyle.copyWith(
    fontSize: 20,
  );

  /// Display name at 21 sp — Comfortaa 21/700.
  static final TextStyle displayName21 = _displayNameStyle.copyWith(
    fontSize: 21,
  );

  /// CTA at 13.5 sp — Comfortaa 13.5/700, white. Colour varies at call site.
  static final TextStyle cta135 = _ctaStyle.copyWith(fontSize: 13.5);

  /// Feedback caption — muted, 13 sp.
  static final TextStyle feedbackMuted13 = _feedbackBase.copyWith(
    color: BrandColors.muted,
    fontSize: 13,
  );

  /// Feedback caption — muted, 12 sp, w600.
  static final TextStyle feedbackMuted12w600 = _feedbackBase.copyWith(
    color: BrandColors.muted,
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );

  /// Feedback caption — error, 12 sp.
  static final TextStyle feedbackError12 = _feedbackBase.copyWith(
    color: BrandColors.error,
    fontSize: 12,
  );

  // ---------------------------------------------------------------------------
  // Home hub — profile card, quick links, passport preview, timeline, hub kit.
  // ---------------------------------------------------------------------------

  /// Section-header label (literal variant) — sectionLabel 13 sp, secondary,
  /// w700, letterSpacing 1.6.
  static final TextStyle homeSectionLiteral = _sectionLabelStyle.copyWith(
    letterSpacing: 1.6,
    fontSize: 13,
    color: BrandColors.textSecondary,
    fontWeight: FontWeight.w700,
  );

  /// «See all» link — link 13 sp, secondary.
  static final TextStyle homeSeeAllLink = _linkStyle.copyWith(
    fontSize: 13,
    color: BrandColors.textSecondary,
  );

  /// Countdown-chip label — feedback secondary, 12.5 sp, letterSpacing 0.2.
  static final TextStyle homeCountdownLabel = _feedbackBase.copyWith(
    color: BrandColors.textSecondary,
    fontSize: 12.5,
    letterSpacing: 0.2,
  );

  /// Quick-link tile label — body 10.5 sp, height 1.15, secondary.
  static final TextStyle homeQuickLinkLabel = _bodyStyle.copyWith(
    fontSize: 10.5,
    height: 1.15,
    color: BrandColors.textSecondary,
  );

  /// Passport-preview title — bodyStrong 11 sp, w800, letterSpacing 0.3,
  /// height 1.15.
  static final TextStyle homePassportPreviewTitle = _bodyStrongStyle.copyWith(
    fontSize: 11,
    letterSpacing: 0.3,
    height: 1.15,
    fontWeight: FontWeight.w800,
  );

  /// Passport-preview subtitle — body 10 sp, height 1.25.
  static final TextStyle homePassportPreviewSubtitle = _bodyStyle.copyWith(
    fontSize: 10,
    height: 1.25,
  );

  /// Passport-preview stat label — bodyStrong 10 sp, w800, letterSpacing 0.3,
  /// height 1.15.
  static final TextStyle homePassportStatLabel = _bodyStrongStyle.copyWith(
    fontSize: 10,
    letterSpacing: 0.3,
    height: 1.15,
    fontWeight: FontWeight.w800,
  );

  /// Passport-preview stat value (rated) — body 11 sp, height 1.25, accentDeep,
  /// w700.
  static final TextStyle homePassportStatValueRated = _bodyStyle.copyWith(
    fontSize: 11,
    height: 1.25,
    color: BrandColors.accentDeep,
    fontWeight: FontWeight.w700,
  );

  /// Passport-preview stat value (empty) — body 11 sp, height 1.25, secondary.
  static final TextStyle homePassportStatValueEmpty = _bodyStyle.copyWith(
    fontSize: 11,
    height: 1.25,
    color: BrandColors.textSecondary,
  );

  /// Favourite-master rating caption — statCaption 10.5 sp.
  static final TextStyle favMasterRating = _statCaptionStyle.copyWith(
    fontSize: 10.5,
  );

  // ---------------------------------------------------------------------------
  // Salon — public profile, reviews, master card, cover, services accordion.
  // ---------------------------------------------------------------------------

  /// Review sort-pill label — feedback muted, 12.5 sp, w700.
  static final TextStyle salonSortLabel = _feedbackBase.copyWith(
    color: BrandColors.muted,
    fontSize: 12.5,
    fontWeight: FontWeight.w700,
  );

  /// Review-summary average figure — displayName 46 sp, height 1.0.
  static final TextStyle salonReviewAverage = _displayNameStyle.copyWith(
    fontSize: 46,
    height: 1.0,
  );

  /// Cover edit-pill label — feedback white, 11 sp, w700.
  static final TextStyle salonCoverEditPill = _feedbackBase.copyWith(
    color: BrandColors.white,
    fontSize: 11,
    fontWeight: FontWeight.w700,
  );

  // ---------------------------------------------------------------------------
  // Passport table.
  // ---------------------------------------------------------------------------

  /// Embossed «B» watermark — heading 176 sp, height 1, w700.
  static final TextStyle passportWatermark = _headingStyle.copyWith(
    fontSize: 176,
    height: 1,
    fontWeight: FontWeight.w700,
  );

  /// Passport section title — heading 18 sp, height 1.1, letterSpacing 1.6.
  static final TextStyle passportSectionTitle = _headingStyle.copyWith(
    fontSize: 18,
    height: 1.1,
    letterSpacing: 1.6,
  );

  /// Passport field label — label 8.5 sp, letterSpacing 0.5, height 1.2.
  static final TextStyle passportTableLabel = _labelStyle.copyWith(
    fontSize: 8.5,
    letterSpacing: 0.5,
    height: 1.2,
  );

  /// Passport field text — bodyStrong 11.5 sp, height 1.1, primary text.
  static final TextStyle passportTableText = _bodyStrongStyle.copyWith(
    fontSize: 11.5,
    height: 1.1,
    color: BrandColors.text,
  );

  /// Passport footer title — bodyStrong 13 sp, w800, letterSpacing 0.3,
  /// height 1.15, primary text.
  static final TextStyle passportFooterTitle = _bodyStrongStyle.copyWith(
    fontSize: 13,
    letterSpacing: 0.3,
    height: 1.15,
    fontWeight: FontWeight.w800,
    color: BrandColors.text,
  );

  /// Passport footer subtitle — body 11.5 sp, height 1.25.
  static final TextStyle passportFooterSubtitle = _bodyStyle.copyWith(
    fontSize: 11.5,
    height: 1.25,
  );

  // ---------------------------------------------------------------------------
  // Rating.
  // ---------------------------------------------------------------------------

  /// «My rating» big number — displayName 56 sp, w700, accentDeep, height 1.0.
  static final TextStyle ratingBigNumber = _displayNameStyle.copyWith(
    fontSize: 56,
    fontWeight: FontWeight.w700,
    color: BrandColors.accentDeep,
    height: 1.0,
  );

  /// «My rating» explanation copy — body 13 sp, secondary, height 1.4.
  static final TextStyle ratingExplanation = _bodyStyle.copyWith(
    fontSize: 13,
    color: BrandColors.textSecondary,
    height: 1.4,
  );

  // ---------------------------------------------------------------------------
  // Support — attachment tray + message-area live counters.
  // ---------------------------------------------------------------------------

  /// Message-area live counter (valid) — feedback muted, 12 sp, tabular figures.
  static final TextStyle supportCounterMuted = _feedbackBase.copyWith(
    color: BrandColors.muted,
    fontSize: 12,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  /// Message-area live counter (over budget) — feedback error, 12 sp, tabular.
  static final TextStyle supportCounterError = _feedbackBase.copyWith(
    color: BrandColors.error,
    fontSize: 12,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );
}
