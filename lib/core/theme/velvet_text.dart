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
    fontSize: 19,
    fontWeight: FontWeight.w700,
    letterSpacing: 22 * 0.16,
    // Wordmark needs >=4.5:1 contrast on BrandColors.base for WCAG AA — the
    // previous textSecondary (#6E5743) read at ~3.2:1 and was illegible on the
    // warm taupe splash background; textPrimary (#4A3322) is ~7:1 (WCAG AA+).
    color: BrandColors.text,
  );

  static final TextStyle _headingStyle = GoogleFonts.comfortaa(
    fontSize: 21,
    fontWeight: FontWeight.w700,
    height: 1.25,
    color: BrandColors.text,
  );

  static final TextStyle _subheadingStyle = GoogleFonts.comfortaa(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: BrandColors.text,
  );

  static final TextStyle _ctaStyle = GoogleFonts.comfortaa(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.3,
    color: BrandColors.white,
  );

  static final TextStyle _bodyStyle = GoogleFonts.nunito(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.5,
    color: BrandColors.textSecondary,
  );

  static final TextStyle _bodyStrongStyle = GoogleFonts.nunito(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    height: 1.5,
    color: BrandColors.text,
  );

  static final TextStyle _inputStyle = GoogleFonts.nunito(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: BrandColors.text,
  );

  static final TextStyle _labelStyle = GoogleFonts.nunito(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
    color: BrandColors.muted,
  );

  static final TextStyle _linkStyle = GoogleFonts.nunito(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: BrandColors.accentDeep,
  );

  // feedback base — color applied via a single copyWith per call site.
  static final TextStyle _feedbackBase = GoogleFonts.nunito(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1.4,
  );

  // ---------------------------------------------------------------------------
  // Public API — unchanged call-site signatures.
  // ---------------------------------------------------------------------------

  static TextStyle wordmark() => _wordmarkStyle;
  static TextStyle heading() => _headingStyle;
  static TextStyle subheading() => _subheadingStyle;

  /// THE single screen/page-title token for every top-level (bottom-nav
  /// tab-root) screen — Comfortaa 14 / w600 / [BrandColors.text], identical
  /// to [_subheadingStyle]. Any new top-level screen title MUST use this
  /// token rather than [heading], [subheading], or a per-screen one-off
  /// (e.g. the now-removed `masterBookingsTitle`, which forked its own
  /// 22 sp size and caused the tab-root title divergence this token fixes).
  static final TextStyle pageTitle = _subheadingStyle;

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
  static final TextStyle headingLg = _headingStyle.copyWith(fontSize: 23);

  /// Subheading with camel accent + italic — used by DoneScreen subtitle.
  static final TextStyle subheadingItalicAccent = _subheadingStyle.copyWith(
    color: BrandColors.accentDeep,
    fontStyle: FontStyle.italic,
  );

  /// Subheading at 15 sp — Comfortaa 15/600, espresso. Used by the master
  /// booking wizard's client-step sub-heading («Дані клієнта»). NOT the same
  /// as the pre-existing (mislabelled) [subheading15] below, which actually
  /// renders at 12 sp — kept distinct rather than reusing that mismatch.
  static final TextStyle subheadingWizard15 = _subheadingStyle.copyWith(
    fontSize: 15,
  );

  /// Body at 13 sp — used by DoneScreen description copy.
  static final TextStyle bodySmall = _bodyStyle.copyWith(fontSize: 11);

  /// Feedback label for summary chips — Nunito 13/700 in [BrandColors.textSecondary]
  /// at 12.5 sp. Used by DoneScreen _SummaryChip.
  static final TextStyle chipLabel = _feedbackBase.copyWith(
    color: BrandColors.textSecondary,
    fontSize: 11,
  );

  /// OTP digit style — Heading at 24 sp, camel accent color.
  /// Used by verification_screen._OtpCell (Batch-2 A3).
  static final TextStyle otpDigit = _headingStyle.copyWith(
    fontSize: 21,
    color: BrandColors.accent,
  );

  /// Cooldown resend link style — link weight with muted color.
  /// Used by verification_screen._ResendRowState cooldown branch (Batch-2 A3).
  static final TextStyle resendCooldown = _linkStyle.copyWith(
    color: BrandColors.faint,
  );

  /// Quiet camel-accent link — same 11 sp Nunito/700 weight as [link], but
  /// `BrandColors.accent` (camel) instead of `accentDeep` (mocha). Phase 221
  /// — used by the «більше»/«згорнути» note-expand toggle, which must read as
  /// a subordinate metadata affordance (camel) rather than a primary link
  /// (mocha is reserved for actionable CTAs/links elsewhere in this system).
  static final TextStyle linkAccent = _linkStyle.copyWith(
    color: BrandColors.accent,
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
  /// RegisterStep1Screen. Replaces `link().copyWith(fontSize: 11)` call sites
  /// that were allocating a new TextStyle on every parent rebuild (Batch-2 A5).
  static final TextStyle linkSmall = _linkStyle.copyWith(fontSize: 11);

  // ---------------------------------------------------------------------------
  // Phase 4.2 fix (PERF MEDIUM-1) — pre-cached feedback variants for the
  // master profile city label and role chip, replacing per-frame
  // `feedback(color).copyWith(fontSize: 11)` allocations.
  // ---------------------------------------------------------------------------

  /// Feedback label for the city / location text — Nunito 13/700, muted, 12 sp.
  static final TextStyle feedbackMutedSm = _feedbackBase.copyWith(
    color: BrandColors.muted,
    fontSize: 11,
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
    fontSize: 11,
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
    fontSize: 11,
  );

  /// ServiceTile price label — Nunito 13/700, accentDeep, 13 sp.
  static final TextStyle servicePriceLabel = _feedbackBase.copyWith(
    color: BrandColors.accentDeep,
    fontSize: 11,
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
    fontSize: 19,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: BrandColors.text,
  );

  static final TextStyle _sectionLabelStyle = GoogleFonts.comfortaa(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
    color: BrandColors.textSecondary,
  );

  static final TextStyle _statValueStyle = GoogleFonts.comfortaa(
    fontSize: 17,
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
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: BrandColors.text,
  );

  static final TextStyle _pillStyle = GoogleFonts.nunito(
    fontSize: 11,
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
    fontSize: 11,
    height: 1.1,
  );

  /// Pill content (duration / price chips) — Nunito 13/800, accentDeep with
  /// mild tracking so the short strings sit evenly inside the inset chip.
  static TextStyle pill() => _pillStyle;

  // ---------------------------------------------------------------------------
  // mobile-perf Finding C (Phase 14.16/14.17 salon booking time-picker audit)
  // — pre-composed statics replacing per-`build()` `.copyWith()` allocations
  // across salon_time_screen.dart, master_strip_shell.dart,
  // schedule_confirm_bar.dart, and master_schedule_page.dart. Each field is
  // computed exactly once at class-load time (zero per-frame cost).
  // ---------------------------------------------------------------------------

  /// `_StepIndicator`'s step-pill label ("Крок 3 з 4") on `SalonTimeScreen`'s
  /// top bar — feedback base, textSecondary, 12 sp, w800.
  static final TextStyle stepPillLabel = _feedbackBase.copyWith(
    color: BrandColors.textSecondary,
    fontSize: 11,
    fontWeight: FontWeight.w800,
  );

  /// `_MasterPager`'s "N / M" counter under the dots — same shape as
  /// [stepPillLabel]; named separately since the two call sites are
  /// independent and may diverge later.
  static final TextStyle schedulePagerCounter = _feedbackBase.copyWith(
    color: BrandColors.textSecondary,
    fontSize: 11,
    fontWeight: FontWeight.w800,
  );

  /// [MasterStripShell]'s small «Запис до майстра» prefix label — feedback
  /// base, textSecondary, 11 sp.
  static final TextStyle masterStripLabel = _feedbackBase.copyWith(
    color: BrandColors.textSecondary,
    fontSize: 11,
  );

  /// [MasterStripShell]'s master display name — subheading at 16 sp.
  static final TextStyle masterStripName = _subheadingStyle.copyWith(
    fontSize: 13,
  );

  /// `ScheduleConfirmBar`'s summed-duration caption beside the "Разом"
  /// label — feedback base, muted, 12 sp.
  static final TextStyle scheduleConfirmDurationLabel = _feedbackBase.copyWith(
    color: BrandColors.muted,
    fontSize: 11,
  );

  /// `ScheduleConfirmBar`'s total price figure — bodyStrong at 18 sp, w800,
  /// accentDeep.
  static final TextStyle scheduleConfirmPriceLabel = _bodyStrongStyle.copyWith(
    color: BrandColors.accentDeep,
    fontWeight: FontWeight.w800,
    fontSize: 15,
  );

  /// `_ProgressHint`'s "X з Y заплановано" label — feedback base,
  /// textSecondary, w800 (13 sp, unchanged from the base).
  static final TextStyle scheduleProgressHintLabel = _feedbackBase.copyWith(
    color: BrandColors.textSecondary,
    fontWeight: FontWeight.w800,
  );

  /// `MasterSchedulePage`'s "Вільний час" section heading — subheading at
  /// 16 sp.
  static final TextStyle scheduleTimeHeading = _subheadingStyle.copyWith(
    fontSize: 13,
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
    fontSize: 13,
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
    fontSize: 11,
    fontWeight: FontWeight.w800,
  );

  /// `_WindowLine`'s unchosen-slot prompt ("Оберіть час…") — feedback base,
  /// textSecondary, 13 sp.
  static final TextStyle windowLinePrompt = _feedbackBase.copyWith(
    color: BrandColors.textSecondary,
    fontSize: 11,
  );

  /// `_WindowLine`'s chosen-window value label — bodyStrong at 14 sp, w800,
  /// accentDeep.
  static final TextStyle windowLineAccent = _bodyStrongStyle.copyWith(
    color: BrandColors.accentDeep,
    fontWeight: FontWeight.w800,
    fontSize: 11,
  );

  // ---------------------------------------------------------------------------
  // Discovery (search) — result cards, category rail, filters, sort sheet.
  // Consolidated from inline `VelvetText.body()/bodyStrong().copyWith(fontSize:)`
  // call sites so every size lives here. Each is cached once at class-load.
  // ---------------------------------------------------------------------------

  /// Result-card locality / muted secondary line — body 12.5 sp, muted.
  static final TextStyle discLocality = _bodyStyle.copyWith(
    fontSize: 11,
    color: BrandColors.muted,
  );

  /// Shared muted caption — body 12 sp, muted. Used by the result-card
  /// address-detail line, the filter helper text, and the price end-label.
  static final TextStyle discCaptionMuted = _bodyStyle.copyWith(
    fontSize: 11,
    color: BrandColors.muted,
  );

  /// Result-card bold numeric rating value — bodyStrong 13 sp.
  static final TextStyle discRatingValue = _bodyStrongStyle.copyWith(
    fontSize: 11,
  );

  /// Accent price figure — bodyStrong 14 sp, accentDeep. Used by the result
  /// card «від N ₴» line and the filter price readout.
  static final TextStyle discPriceAccent = _bodyStrongStyle.copyWith(
    fontSize: 11,
    color: BrandColors.accentDeep,
  );

  /// Result-card service-names preview line — body 12.5 sp, secondary.
  static final TextStyle discServicesPreview = _bodyStyle.copyWith(
    fontSize: 11,
    color: BrandColors.textSecondary,
  );

  /// Category-rail label (resting) — body 12 sp, w700, secondary, height 1.15.
  static final TextStyle discCategoryLabelResting = _bodyStyle.copyWith(
    fontSize: 11,
    height: 1.15,
    fontWeight: FontWeight.w700,
    color: BrandColors.textSecondary,
  );

  /// Category-rail label (selected) — body 12 sp, w700, accentDeep, height 1.15.
  static final TextStyle discCategoryLabelSelected = _bodyStyle.copyWith(
    fontSize: 11,
    height: 1.15,
    fontWeight: FontWeight.w700,
    color: BrandColors.accentDeep,
  );

  /// Service-type tile caption (selected) — body 12 sp, w700, accentDeep.
  static final TextStyle discServiceTypeSelected = _bodyStyle.copyWith(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: BrandColors.accentDeep,
  );

  /// Service-type tile caption (unselected) — body 12 sp, w700, secondary.
  static final TextStyle discServiceTypeUnselected = _bodyStyle.copyWith(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: BrandColors.textSecondary,
  );

  /// Service-chip drawer label — body 13 sp, w700. Colour (white/text when
  /// selected) is applied at the call site via a single copyWith.
  static final TextStyle discChipLabel = _bodyStyle.copyWith(
    fontSize: 11,
    fontWeight: FontWeight.w700,
  );

  /// Sort-options sheet row label — body 15 sp, w700, primary text.
  static final TextStyle discSortOption = _bodyStyle.copyWith(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: BrandColors.text,
  );

  /// Filter «Очистити» clear-button label — body 13 sp, w600.
  static final TextStyle discClearButton = _bodyStyle.copyWith(
    fontSize: 11,
    fontWeight: FontWeight.w600,
  );

  /// Search-results header count — body 14 sp, w700, accent.
  static final TextStyle discResultCount = _bodyStyle.copyWith(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: BrandColors.accent,
  );

  /// The provider's free-text arrival note, third row of [ResultAddressBlock]
  /// (Phase 111 — «Улюблені»). One notch quieter than [discCaptionMuted] and,
  /// unlike every other row in that block, on a LOOSER line-height (1.3): the
  /// note is the only line there allowed to wrap, and the extra leading is the
  /// one typographic signal that it is a sentence someone wrote rather than
  /// another field off a form.
  static final TextStyle discAddressNote = _bodyStyle.copyWith(
    fontSize: 11,
    height: 1.3,
    fontWeight: FontWeight.w400,
    color: BrandColors.muted.withValues(alpha: 0.7),
  );

  // ---------------------------------------------------------------------------
  // Favourites («Улюблені», Phase 111) — the two card kinds, the inline
  // category filter and the removed-row dent.
  //
  // TRANSCRIBED BY ROLE, NOT BY NUMBER. The approved preview app sets its own
  // absolute sizes off a base scale ~1.25x this one (its `body()` is 15 sp
  // where `_bodyStyle` is 12, its `heading()` 24 where `_headingStyle` is 21).
  // Copying the preview's literals would have shipped a screen typographically
  // larger than every other screen in the app. Each token below therefore
  // derives from the SAME base style the preview reached for and keeps the
  // preview's DELTA — weight, line-height, colour, and the relative step up or
  // down from that base — on this app's absolute scale. Same rule the
  // discovery block above already follows.
  // ---------------------------------------------------------------------------

  /// Favourite-card rating value — [discRatingValue] tightened to `height: 1.1`
  /// so the star and the figure sit on one optical line inside the identity
  /// row. Colour is applied at the call site: the unrated pair dims as a UNIT.
  static final TextStyle favRatingValue = discRatingValue.copyWith(height: 1.1);

  /// «Where this master works» — the accentDeep salon line under a master's
  /// name. A step ABOVE the address rows beneath it in weight (w700) and size,
  /// because a salon is a navigable entity and an address is inert
  /// orientation; the hue break is the primary separator, this is the backup.
  static final TextStyle favAffiliation = _bodyStyle.copyWith(
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: BrandColors.accentDeep,
  );

  /// Inline category-filter pill + chip label — bodyStrong, w700, tight.
  /// Colour (accentDeep when selected, textSecondary at rest) is applied at
  /// the call site.
  static final TextStyle favFilterLabel = _bodyStrongStyle.copyWith(
    fontSize: 11,
    height: 1.1,
    fontWeight: FontWeight.w700,
  );

  /// The removed-row dent's headline — the name of who was just unliked.
  /// Secondary tone: the row is on its way out, so it must not compete with
  /// the live cards around it.
  static final TextStyle favDentName = _bodyStrongStyle.copyWith(
    fontSize: 11,
    height: 1.2,
    color: BrandColors.textSecondary,
  );

  /// «Прибрано з улюблених» under the dent name — muted caption.
  static final TextStyle favDentCaption = _bodyStyle.copyWith(
    fontSize: 10,
    height: 1.3,
    color: BrandColors.muted,
  );

  // ---------------------------------------------------------------------------
  // Generic size variants reused across features. Named by the base role +
  // size so callers stop re-deriving them inline.
  // ---------------------------------------------------------------------------

  /// Heading one step smaller than the base — Comfortaa 22 sp. Used by
  /// empty-state titles (services list) and section titles (schedule widgets).
  static final TextStyle headingSm = _headingStyle.copyWith(fontSize: 19);

  /// Subheading at 16 sp — Comfortaa 16/600. Used by the services accordion
  /// header and the service-setup row name (which overrides colour).
  static final TextStyle subheading16 = _subheadingStyle.copyWith(fontSize: 13);

  /// CTA label one step smaller — Comfortaa 14/700, white. Used by the
  /// change-photo label and the selected pricing segment.
  static final TextStyle ctaSm = _ctaStyle.copyWith(fontSize: 11);

  /// Inset accent pill at 12.5 sp — Nunito 13/800 accentDeep. Used by the
  /// service-card duration/price chips and the master-profile stat chip.
  static final TextStyle pillSm = _pillStyle.copyWith(fontSize: 11);

  /// Body at 12 sp — Nunito 12/600, secondary (base body colour retained).
  static final TextStyle body12 = _bodyStyle.copyWith(fontSize: 11);

  /// Body at 14 sp — Nunito 14/600, secondary (base body colour retained).
  static final TextStyle body14 = _bodyStyle.copyWith(fontSize: 11);

  /// Strong body at 13 sp — Nunito 13/700, primary text.
  static final TextStyle bodyStrong13 = _bodyStrongStyle.copyWith(fontSize: 11);

  /// Strong body at 14 sp — Nunito 14/700, primary text.
  static final TextStyle bodyStrong14 = _bodyStrongStyle.copyWith(fontSize: 11);

  /// Body at 13 sp — Nunito 13/600, secondary (base body colour retained).
  static final TextStyle body13 = _bodyStyle.copyWith(fontSize: 11);

  /// Strong body at 15 sp — Nunito 15/700, primary text.
  static final TextStyle bodyStrong15 = _bodyStrongStyle.copyWith(fontSize: 12);

  /// Strong body at 16 sp — Nunito 16/700, primary text.
  static final TextStyle bodyStrong16 = _bodyStrongStyle.copyWith(fontSize: 13);

  /// Heading at 20 sp — Comfortaa 20/700, espresso. Sheet / section titles.
  static final TextStyle heading20 = _headingStyle.copyWith(fontSize: 17);

  /// Label at 11 sp — Nunito 11/700, muted, letterSpacing 0.6.
  static final TextStyle label11 = _labelStyle.copyWith(fontSize: 11);

  /// Link at 13 sp — Nunito 13/700, accentDeep. Small inline action links.
  static final TextStyle link13 = _linkStyle.copyWith(fontSize: 11);

  /// Subheading at 15 sp — Comfortaa 15/600, espresso.
  static final TextStyle subheading15 = _subheadingStyle.copyWith(fontSize: 12);

  /// Strong body at 13.5 sp — Nunito 13.5/700, primary text.
  static final TextStyle bodyStrong135 = _bodyStrongStyle.copyWith(
    fontSize: 11,
  );

  /// Strong body at 14.5 sp — Nunito 14.5/700, primary text.
  static final TextStyle bodyStrong145 = _bodyStrongStyle.copyWith(
    fontSize: 11.5,
  );

  /// Phase 7.7 — the digit inside the «Мої записи» active-filter count badge.
  ///
  /// Cream (`BrandColors.white`, #F5EDE0) on the MOCHA badge fill — the design's
  /// `_AccentDot` is camel, but a dot carries no text and camel/cream is ~2:1,
  /// well under WCAG AA. `accentDeep` keeps the badge on-brand at ~7:1. `height:
  /// 1` so a single digit centres inside an 18dp pill instead of sitting low on
  /// the Nunito baseline.
  static final TextStyle filterBadge = _bodyStrongStyle.copyWith(
    fontSize: 9,
    height: 1,
    color: BrandColors.white,
  );

  // ---------------------------------------------------------------------------
  // Services — list cards, setup accordion, pricing segments, photo slot.
  // ---------------------------------------------------------------------------

  /// Service-card name — cardTitle 15 sp, height 1.15.
  static final TextStyle svcCardName = _cardTitleStyle.copyWith(
    fontSize: 12,
    height: 1.15,
  );

  /// Category count pill ("n з m") — pill 12 sp. Colour applied at call site.
  static final TextStyle svcCountPill = _pillStyle.copyWith(fontSize: 11);

  /// Category-group header line — body 12 sp, height 1.4, w800, accentDeep.
  static final TextStyle svcGroupHeader = _bodyStyle.copyWith(
    fontSize: 11,
    height: 1.4,
    fontWeight: FontWeight.w800,
    color: BrandColors.accentDeep,
  );

  /// Small caption note (excluded row / missing-service note) — body 12 sp,
  /// height 1.4.
  static final TextStyle svcCaptionNote = _bodyStyle.copyWith(
    fontSize: 11,
    height: 1.4,
  );

  /// Unselected pricing segment label — cta 14 sp, w600, secondary.
  static final TextStyle svcSegmentUnselected = _ctaStyle.copyWith(
    fontSize: 11,
    color: BrandColors.textSecondary,
    fontWeight: FontWeight.w600,
  );

  // ---------------------------------------------------------------------------
  // Shell — branch placeholders + client bottom-nav labels.
  // ---------------------------------------------------------------------------

  /// «Coming soon» placeholder chip label — feedback base, secondary, 12 sp.
  static final TextStyle shellComingSoonLabel = _feedbackBase.copyWith(
    color: BrandColors.textSecondary,
    fontSize: 11,
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
    fontSize: 21,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  /// Discrete-times window label — label 12 sp, w700, accentDeep.
  static final TextStyle schedWindowLabel = _labelStyle.copyWith(
    fontSize: 11,
    color: BrandColors.accentDeep,
    fontWeight: FontWeight.w700,
  );

  /// Discrete-times chip label — bodyStrong 13 sp, accentDeep, tabular figures.
  static final TextStyle schedTimeChip = _bodyStrongStyle.copyWith(
    fontSize: 11,
    color: BrandColors.accentDeep,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  /// Interval-editor time value — input 17 sp, w700, tabular figures. Colour
  /// (accent / text) applied at the call site.
  static final TextStyle schedIntervalTime = _inputStyle.copyWith(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  /// Row action link (regular) — link 14 sp, accentDeep.
  static final TextStyle schedActionLink = _linkStyle.copyWith(
    color: BrandColors.accentDeep,
    fontSize: 11,
  );

  /// Row action link (dense) — link 13 sp, accentDeep.
  static final TextStyle schedActionLinkDense = _linkStyle.copyWith(
    color: BrandColors.accentDeep,
    fontSize: 11,
  );

  /// Read-only time-grid axis label — label 12 sp, secondary.
  static final TextStyle schedTimeAxisLabel = _labelStyle.copyWith(
    fontSize: 11,
    color: BrandColors.textSecondary,
  );

  /// Weekly-template unset-window prompt — bodyStrong 13 sp, w600, placeholder.
  static final TextStyle schedWindowUnset = _bodyStrongStyle.copyWith(
    fontSize: 11,
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
      fontSize: 11,
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
    fontSize: 11,
    fontWeight: FontWeight.w800,
  );

  /// «covered services» label — feedback, accentDeep, 12 sp, w800.
  static final TextStyle bookCoveredLabel = _feedbackBase.copyWith(
    color: BrandColors.accentDeep,
    fontSize: 11,
    fontWeight: FontWeight.w800,
  );

  /// Feedback caption — placeholder, 12.5 sp.
  static final TextStyle bookFeedbackPlaceholder125 = _feedbackBase.copyWith(
    color: BrandColors.placeholder,
    fontSize: 11,
  );

  /// Feedback caption — placeholder, 11.5 sp.
  static final TextStyle bookFeedbackPlaceholder115 = _feedbackBase.copyWith(
    color: BrandColors.placeholder,
    fontSize: 11,
  );

  /// Feedback caption — secondary, 12.5 sp.
  static final TextStyle bookFeedbackSec125 = _feedbackBase.copyWith(
    color: BrandColors.textSecondary,
    fontSize: 11,
  );

  /// Feedback caption — secondary, 13 sp.
  static final TextStyle bookFeedbackSec13 = _feedbackBase.copyWith(
    color: BrandColors.textSecondary,
    fontSize: 11,
  );

  /// Feedback caption — secondary, 13 sp, w800.
  static final TextStyle bookFeedbackSec13w800 = _feedbackBase.copyWith(
    color: BrandColors.textSecondary,
    fontSize: 11,
    fontWeight: FontWeight.w800,
  );

  /// Feedback pill — 12.5 sp, w800. Colour (selected / secondary) at call site.
  static final TextStyle bookFeedback125w800 = _feedbackBase.copyWith(
    fontSize: 11,
    fontWeight: FontWeight.w800,
  );

  /// Feedback caption — muted, 11.5 sp.
  static final TextStyle bookFeedbackMuted115 = _feedbackBase.copyWith(
    color: BrandColors.muted,
    fontSize: 11,
  );

  /// Feedback caption — muted, 12.5 sp.
  static final TextStyle bookFeedbackMuted125 = _feedbackBase.copyWith(
    color: BrandColors.muted,
    fontSize: 11,
  );

  /// Feedback caption — muted, 14 sp (summary-bar total label).
  static final TextStyle bookSummaryMuted14 = _feedbackBase.copyWith(
    color: BrandColors.muted,
    fontSize: 11,
  );

  /// Accordion tag on selected row — feedback, white, 11 sp, w800.
  static final TextStyle bookFeedbackWhite11w800 = _feedbackBase.copyWith(
    color: BrandColors.white,
    fontSize: 11,
    fontWeight: FontWeight.w800,
  );

  /// Service-group name — bodyStrong 14.5 sp, accentDeep, w800.
  static final TextStyle bookGroupName = _bodyStrongStyle.copyWith(
    fontSize: 11.5,
    color: BrandColors.accentDeep,
    fontWeight: FontWeight.w800,
  );

  /// Accent numeric value — bodyStrong 14 sp, accentDeep, w800.
  static final TextStyle bookAccentValue14 = _bodyStrongStyle.copyWith(
    color: BrandColors.accentDeep,
    fontWeight: FontWeight.w800,
    fontSize: 11,
  );

  /// Total-price figure (medium) — bodyStrong 17 sp, accentDeep, w800.
  static final TextStyle bookPriceMd = _bodyStrongStyle.copyWith(
    color: BrandColors.accentDeep,
    fontWeight: FontWeight.w800,
    fontSize: 14,
  );

  /// Total-price figure (large) — bodyStrong 18 sp, accentDeep, w800.
  static final TextStyle bookPriceLg = _bodyStrongStyle.copyWith(
    color: BrandColors.accentDeep,
    fontWeight: FontWeight.w800,
    fontSize: 15,
  );

  /// Recap accent value (compact) — bodyStrong 13.5 sp, accentDeep, w800.
  static final TextStyle bookAccentBold135 = _bodyStrongStyle.copyWith(
    color: BrandColors.accentDeep,
    fontWeight: FontWeight.w800,
    fontSize: 11,
  );

  /// Recap accent value (regular) — bodyStrong 15 sp, accentDeep, w800.
  static final TextStyle bookAccentBold15 = _bodyStrongStyle.copyWith(
    color: BrandColors.accentDeep,
    fontWeight: FontWeight.w800,
    fontSize: 12,
  );

  /// Recap accent value (compact, large) — bodyStrong 15.5 sp, accentDeep, w800.
  static final TextStyle bookAccentBold155 = _bodyStrongStyle.copyWith(
    color: BrandColors.accentDeep,
    fontWeight: FontWeight.w800,
    fontSize: 12.5,
  );

  /// Recap service name (compact) — bodyStrong 14.5 sp, w800.
  static final TextStyle bookName145w800 = _bodyStrongStyle.copyWith(
    fontSize: 11.5,
    fontWeight: FontWeight.w800,
  );

  /// Recap service name (regular) — bodyStrong 16 sp, w800.
  static final TextStyle bookName16w800 = _bodyStrongStyle.copyWith(
    fontSize: 13,
    fontWeight: FontWeight.w800,
  );

  /// Summary-card value (compact) — bodyStrong 13.5 sp, height 1.3.
  static final TextStyle bookCardValue135 = _bodyStrongStyle.copyWith(
    fontSize: 11,
    height: 1.3,
  );

  /// Summary-card value (regular) — bodyStrong 15 sp, height 1.3.
  static final TextStyle bookCardValue15 = _bodyStrongStyle.copyWith(
    fontSize: 12,
    height: 1.3,
  );

  /// Slot chip label — bodyStrong 14 sp, w800. Colour applied at the call site.
  static final TextStyle bookSlotChip = _bodyStrongStyle.copyWith(
    fontWeight: FontWeight.w800,
    fontSize: 11,
  );

  /// Slot time-group sub-label — sectionLabel 12 sp.
  static final TextStyle bookSlotGroupLabel = _sectionLabelStyle.copyWith(
    fontSize: 11,
  );

  /// Success-screen subline — body 13 sp, height 1.35.
  static final TextStyle bookSuccessSubline = _bodyStyle.copyWith(
    height: 1.35,
    fontSize: 11,
  );

  /// Success-screen «add to calendar» CTA — bodyStrong 14.5 sp, accentDeep.
  static final TextStyle bookCalendarCta = _bodyStrongStyle.copyWith(
    fontSize: 11.5,
    color: BrandColors.accentDeep,
  );

  /// Comment field hint — body 14 sp, placeholder.
  static final TextStyle bookCommentHint = _bodyStyle.copyWith(
    fontSize: 11,
    color: BrandColors.placeholder,
  );

  /// `SalonAppointmentCard` status line — in-flight (muted). Pre-cached so the
  /// card never calls `feedback(color).copyWith()` per build (mobile-perf INFO,
  /// Phase 14.18 salon-submit audit).
  static final TextStyle salonApptStatusMuted = _feedbackBase.copyWith(
    color: BrandColors.muted,
  );

  /// `SalonAppointmentCard` status line — succeeded (success green).
  static final TextStyle salonApptStatusSuccess = _feedbackBase.copyWith(
    color: BrandColors.success,
  );

  /// `SalonAppointmentCard` status line — failed (error red).
  static final TextStyle salonApptStatusError = _feedbackBase.copyWith(
    color: BrandColors.error,
  );

  // ---------------------------------------------------------------------------
  // Phase 14.3 — My Bookings card date stub. A tight-leading numeral is a
  // recurring need (mirrors `schedWheelDigit` / `salonReviewAverage` /
  // `ratingBigNumber`, all of which set `height: 1.0` on a display numeral),
  // not a special case for this one screen.
  // ---------------------------------------------------------------------------

  /// Booking-card date-stub day number — heading 18 sp, `height: 1.0`. The
  /// biggest type on the card; against a body set at 10–11 sp that is a
  /// ~1.7x ratio, so dominance is the CONTRAST, not the absolute size. Stepped
  /// down one notch (was 21 sp) in the 2026-07-15 compact-card pass. Only the
  /// size + leading are overridden — a display numeral always needs a tight
  /// line-height.
  static final TextStyle bookingDayNumber = _headingStyle.copyWith(
    fontSize: 18,
    height: 1.0,
  );

  /// Booking-card date-stub time — statValue 14 sp, `height: 1.1` (was 17 sp;
  /// stepped down in the 2026-07-15 compact-card pass). Third stacked line
  /// under the day number and month/weekday caption (2026-08 move out of the
  /// body's top-right corner). Colour (mocha / muted, plus an optional
  /// no-show strikethrough) applied at the call site via a single
  /// `copyWith`.
  static final TextStyle bookingTime = _statValueStyle.copyWith(
    fontSize: 14,
    height: 1.1,
  );

  // ---------------------------------------------------------------------------
  // Phase 24.x compact-card pass (2026-07-15) — the «МОЇ ЗАПИСИ» list card
  // renders one notch smaller across the board. These step the card's shared
  // tokens (cardTitle / bodyStrong / statCaption / feedbackMutedSm / the recap's
  // bookAccentBold15) down by one size WITHOUT touching those shared tokens'
  // other call sites (services list, recap, salon reviews …). Colour stays
  // Warm Mocha; only size (and, where noted, leading) is reduced.
  // ---------------------------------------------------------------------------

  /// Booking-card master name — [cardTitle] stepped to Comfortaa 12/700,
  /// height 1.2. Colour applied at the call site.
  static final TextStyle bookingCardName = _cardTitleStyle.copyWith(
    fontSize: 12,
    height: 1.2,
  );

  /// Booking-card service-line name — [bodyStrong] stepped to Nunito 11/700,
  /// height 1.25. Colour applied at the call site.
  static final TextStyle bookingCardService = _bodyStrongStyle.copyWith(
    fontSize: 11,
    height: 1.25,
  );

  /// Booking-card locked-in price — Nunito 10/800, accentDeep. One step under
  /// the recap's [bookAccentBold15], so the card figure no longer shouts.
  static final TextStyle bookingCardPrice = _bodyStrongStyle.copyWith(
    fontSize: 10,
    fontWeight: FontWeight.w800,
    color: BrandColors.accentDeep,
  );

  /// Booking-card muted caption — the stub month line and the salon name.
  /// [statCaption] stepped to Nunito 10/700. The runtime colour (muted / faint /
  /// secondary) is applied at the call site via a single copyWith.
  static final TextStyle bookingCardCaption = _statCaptionStyle.copyWith(
    fontSize: 10,
  );

  /// Booking-card professional-title sub-line — Nunito 10/700, muted. One step
  /// under [feedbackMutedSm].
  static final TextStyle bookingCardSubtle = _feedbackBase.copyWith(
    color: BrandColors.muted,
    fontSize: 10,
  );

  // ---------------------------------------------------------------------------
  // Additional generic size variants (home / salon / passport / rating).
  // ---------------------------------------------------------------------------

  /// Body at 10.5 sp — Nunito 10.5/600, secondary.
  static final TextStyle body105 = _bodyStyle.copyWith(fontSize: 10.5);

  /// Body at 11 sp — Nunito 11/600, secondary.
  static final TextStyle body11 = _bodyStyle.copyWith(fontSize: 11);

  /// Body at 12.5 sp — Nunito 12.5/600, secondary.
  static final TextStyle body125 = _bodyStyle.copyWith(fontSize: 11);

  /// Body at 14 sp in primary text colour — Nunito 14/600, text.
  static final TextStyle body14Text = _bodyStyle.copyWith(
    fontSize: 11,
    color: BrandColors.text,
  );

  /// Strong body at 12 sp — Nunito 12/700, primary text.
  static final TextStyle bodyStrong12 = _bodyStrongStyle.copyWith(fontSize: 11);

  /// Subheading at 12 sp — Comfortaa 12/600. Colour/weight vary at call site.
  static final TextStyle subheading12 = _subheadingStyle.copyWith(fontSize: 11);

  /// Subheading at 14 sp — Comfortaa 14/600.
  static final TextStyle subheading14 = _subheadingStyle.copyWith(fontSize: 11);

  /// Heading at 18 sp — Comfortaa 18/700.
  static final TextStyle heading18 = _headingStyle.copyWith(fontSize: 15);

  /// Display name at 20 sp — Comfortaa 20/700.
  static final TextStyle displayName20 = _displayNameStyle.copyWith(
    fontSize: 17,
  );

  /// Display name at 21 sp — Comfortaa 21/700.
  static final TextStyle displayName21 = _displayNameStyle.copyWith(
    fontSize: 18,
  );

  /// CTA at 13.5 sp — Comfortaa 13.5/700, white. Colour varies at call site.
  static final TextStyle cta135 = _ctaStyle.copyWith(fontSize: 11);

  /// Feedback caption — muted, 13 sp.
  static final TextStyle feedbackMuted13 = _feedbackBase.copyWith(
    color: BrandColors.muted,
    fontSize: 11,
  );

  /// Feedback caption — muted, 12 sp, w600.
  static final TextStyle feedbackMuted12w600 = _feedbackBase.copyWith(
    color: BrandColors.muted,
    fontSize: 11,
    fontWeight: FontWeight.w600,
  );

  /// Feedback caption — error, 12 sp.
  static final TextStyle feedbackError12 = _feedbackBase.copyWith(
    color: BrandColors.error,
    fontSize: 11,
  );

  // ---------------------------------------------------------------------------
  // Home hub — profile card, quick links, passport preview, timeline, hub kit.
  // ---------------------------------------------------------------------------

  /// Section-header label (literal variant) — sectionLabel 13 sp, secondary,
  /// w700, letterSpacing 1.6.
  static final TextStyle homeSectionLiteral = _sectionLabelStyle.copyWith(
    letterSpacing: 1.6,
    fontSize: 11,
    color: BrandColors.textSecondary,
    fontWeight: FontWeight.w700,
  );

  /// «See all» link — link 13 sp, secondary.
  static final TextStyle homeSeeAllLink = _linkStyle.copyWith(
    fontSize: 11,
    color: BrandColors.textSecondary,
  );

  /// Countdown-chip label — feedback secondary, 12.5 sp, letterSpacing 0.2.
  static final TextStyle homeCountdownLabel = _feedbackBase.copyWith(
    color: BrandColors.textSecondary,
    fontSize: 11,
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
    fontSize: 11,
    fontWeight: FontWeight.w700,
  );

  /// Review-summary average figure — displayName 46 sp, height 1.0.
  static final TextStyle salonReviewAverage = _displayNameStyle.copyWith(
    fontSize: 43,
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
    fontSize: 173,
    height: 1,
    fontWeight: FontWeight.w700,
  );

  /// Passport section title — heading 18 sp, height 1.1, letterSpacing 1.6.
  static final TextStyle passportSectionTitle = _headingStyle.copyWith(
    fontSize: 15,
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
    fontSize: 11,
    height: 1.1,
    color: BrandColors.text,
  );

  /// Passport footer title — bodyStrong 13 sp, w800, letterSpacing 0.3,
  /// height 1.15, primary text.
  static final TextStyle passportFooterTitle = _bodyStrongStyle.copyWith(
    fontSize: 11,
    letterSpacing: 0.3,
    height: 1.15,
    fontWeight: FontWeight.w800,
    color: BrandColors.text,
  );

  /// Passport footer subtitle — body 11.5 sp, height 1.25.
  static final TextStyle passportFooterSubtitle = _bodyStyle.copyWith(
    fontSize: 11,
    height: 1.25,
  );

  // ---------------------------------------------------------------------------
  // Rating.
  // ---------------------------------------------------------------------------

  /// «My rating» big number — displayName 56 sp, w700, accentDeep, height 1.0.
  static final TextStyle ratingBigNumber = _displayNameStyle.copyWith(
    fontSize: 53,
    fontWeight: FontWeight.w700,
    color: BrandColors.accentDeep,
    height: 1.0,
  );

  /// «My rating» explanation copy — body 13 sp, secondary, height 1.4.
  static final TextStyle ratingExplanation = _bodyStyle.copyWith(
    fontSize: 11,
    color: BrandColors.textSecondary,
    height: 1.4,
  );

  // ---------------------------------------------------------------------------
  // Support — attachment tray + message-area live counters.
  // ---------------------------------------------------------------------------

  /// Message-area live counter (valid) — feedback muted, 12 sp, tabular figures.
  static final TextStyle supportCounterMuted = _feedbackBase.copyWith(
    color: BrandColors.muted,
    fontSize: 11,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  /// Message-area live counter (over budget) — feedback error, 12 sp, tabular.
  static final TextStyle supportCounterError = _feedbackBase.copyWith(
    color: BrandColors.error,
    fontSize: 11,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  // ---------------------------------------------------------------------------
  // Phase 14.6 — leave-review screen (master feedback card, star input,
  // comment counter). Runtime-varying colours (the counter's error/active/muted
  // states, the section tag's accent/muted states) are applied at the call site
  // via one copyWith on these cached bases — only the size/family/weight/height
  // live here so no inline `fontSize:` survives under lib/features.
  // ---------------------------------------------------------------------------

  /// Comment live-counter «$n / 500» — feedback base, Nunito 11/700, height 1.4.
  /// Colour (error at cap / secondary while typing / muted when empty) is
  /// applied at the call site.
  static final TextStyle feedbackCounter = _feedbackBase.copyWith(fontSize: 11);

  /// Section eyebrow required/optional tag («обовʼязково» / «за бажанням») —
  /// feedback base at 10 sp, Nunito 10/700, height 1.4. Colour (accentDeep when
  /// emphasized / muted otherwise) applied at the call site.
  static final TextStyle feedbackTag = _feedbackBase.copyWith(fontSize: 10);

  /// Master identity-card display name on the leave-review header — displayName
  /// stepped to Comfortaa 16/700, height 1.2, espresso.
  static final TextStyle feedbackName = _displayNameStyle.copyWith(
    fontSize: 16,
  );

  /// Star-input live descriptive word (rated) — displayName stepped to
  /// Comfortaa 18/700, height 1.2, accentDeep.
  static final TextStyle feedbackRatingWord = _displayNameStyle.copyWith(
    fontSize: 18,
    color: BrandColors.accentDeep,
  );

  /// Star-input unrated prompt — body stepped to Nunito 13/600, height 1.5,
  /// muted.
  static final TextStyle feedbackPrompt = _bodyStyle.copyWith(
    fontSize: 13,
    color: BrandColors.muted,
  );

  // ---------------------------------------------------------------------------
  // Phase 7.6 — the master's «Мої записи»: the day rail + the booking card.
  //
  // Transcribed from the approved preview at
  // `docs/signup-designs/SalonManagementDesign/lib/widgets/` (bookings_toolbar
  // `_DayChip`/`_AllChip`, booking_widgets `BookingCard`/`PriceTag`/
  // `BookingDateChip`). The preview spells each of these as an inline
  // `.copyWith(fontSize:)`; they are cached tokens here so the rail — which
  // rebuilds its visible cells on every scroll frame — never allocates a
  // TextStyle per frame, and so the sizes stay shared rather than
  // re-fragmenting the 116-token consolidation.
  //
  // Colour is deliberately NOT baked into the rail tokens: a day chip's
  // weekday/number colour is its SELECTION state, applied at the call site.
  // ---------------------------------------------------------------------------

  /// Day-rail weekday caption («Пн») — statCaption stepped to 11 sp.
  static final TextStyle railWeekday = _statCaptionStyle.copyWith(fontSize: 11);

  /// Day-rail day-of-month number — statValue stepped to 12.6 sp (18 sp × 0.7,
  /// 2026-07-19 pass). Still the rail's largest glyph relative to
  /// `railWeekday` (11 sp) and clears the project's 11 sp legibility floor,
  /// but only by 1.6 sp — re-check this pairing if the rail's cell size or
  /// weekday caption ever moves.
  static final TextStyle railDayNumber = _statValueStyle.copyWith(
    fontSize: 12.6,
  );

  // The `masterCard*` prefix is deliberate. The CLIENT booking card already
  // owns `bookingCard*` tokens (`bookingCardPrice`, `bookingCardService`, …)
  // at its own sizes; the two cards are different widgets with different grids
  // (see `master_booking_card.dart`'s header), so their type must not share a
  // namespace where a future edit could "consolidate" two unrelated sizes.
  //
  // LEGIBILITY FLOOR (2026-08-15, mobile-perf/mobile-security audit of the
  // font-size pass below): no LIVE `masterCard*` token goes below 9 sp.
  // [masterCardBadgeLabel] was stepped to 8.3 sp by the font-size pass and
  // bumped back to 9.0 sp for this reason — see that token's own doc. A
  // future density pass must not quietly cross this floor again; if a
  // `masterCard*` token needs to go below 9 sp, that is a deliberate
  // legibility trade-off to call out explicitly, not a mechanical ~8% step.
  //
  // UPDATE (2026-08-15): there IS now a `masterCardPricePill` — see that
  // token's own doc. Until the font-size pass below, there was deliberately
  // no `masterCardPrice`: the price pill rendered `pill()` verbatim, and a
  // `.copyWith(fontSize: 11)` on it would have been a no-op wearing a new
  // name. The pass needed the card's own price figure to shrink without
  // moving `pill()` itself (shared with wishlist/passport), which is what
  // finally justified a dedicated token.
  //
  // Compact-timeline pass (2026-07-20, see `master_booking_card.dart`'s class
  // doc): the card dropped its avatar row entirely and moved to a two-line
  // "time/service/price" + "client/status" grid, targeting ~52dp so it fits a
  // 45-60 minute timeline slot. [masterCardClientName]/[masterCardService]
  // keep their existing sizes (still exclusive to this card — no other call
  // site) but now also pin an explicit `height:` — the tight leading a
  // compact row needs, rather than inheriting their base styles' generous
  // 1.5/default line height. The old `masterCardDate` (icon + full date+time
  // caption, e.g. "12 лип, 14:30") is retired — a per-day timeline never
  // needs the date. [masterCardTime] and [masterCardBadgeLabel] are new for
  // the same pass.

  /// Client name on a master booking card (row 2) — subheading at 11.5 sp,
  /// height 1.2.
  ///
  /// FONT-SIZE PASS (2026-08-15) — was 12.5 sp. User request: "make all fonts
  /// of all existed elements in bookings cards a little bit lower" — a
  /// uniform ~1 sp step-down across every `masterCard*`/`masterFreeCard*`
  /// token, size-only (no colour/weight/reorder). See
  /// `master_booking_card.dart`'s class doc for the re-measured naturals this
  /// pass produced.
  static final TextStyle masterCardClientName = _subheadingStyle.copyWith(
    fontSize: 11.5,
    height: 1.2,
  );

  /// Service name on a master booking card (row 1) — bodyStrong at 10 sp,
  /// height 1.2 (down from the base style's 1.5 — see this section's header).
  ///
  /// FONT-SIZE PASS (2026-08-15) — was 11 sp; see [masterCardClientName]'s doc.
  static final TextStyle masterCardService = _bodyStrongStyle.copyWith(
    fontSize: 10,
    height: 1.2,
  );

  /// The COMPACT and MICRO bodies' start–end time range (e.g. "09:00–09:45").
  ///
  /// ONE TIME STYLE ACROSS ALL THREE DENSITIES (2026-07-24)
  /// -------------------------------------------------------------------
  /// Derived FROM [masterCardDateFull] — the >=1h card's own range recipe —
  /// rather than declared independently, so the three `MasterBookingCard`
  /// bodies can never drift apart typographically again. It previously ran
  /// `_bodyStrongStyle` at 11.5 sp in [BrandColors.text], which differed from
  /// the full card's range on all three visible axes at once (base recipe,
  /// size and colour): a lane of mixed-density cards read as two different
  /// time styles stacked on one timeline, which is the report this pass
  /// closes.
  ///
  /// THE ONE DELTA IS `height`, AND IT IS A LAYOUT KNOB, NOT A TYPE CHOICE.
  /// [masterCardDateFull] inherits `_feedbackBase`'s 1.4 leading, which the
  /// full card's 16dp-padded rows can afford. The MICRO body is a single
  /// text row inside a 12dp-padded box whose whole existence is fitting a
  /// sub-28-minute wall-clock band, and its rendered height IS the tallest
  /// child's line box — so 1.4 would inflate
  /// [MasterBookingCard.microLayoutNaturalHeight] from a measured 28dp to
  /// 30dp and leave a 15-minute booking (a 30dp band at `_kHourH` 120) with
  /// ZERO clearance over its own gridline. Stepping the leading to 1.2 —
  /// exactly what [masterCardService], the text beside it on that row,
  /// already uses — costs nothing visible (font, size, weight and colour are
  /// identical to the full card's range; a single line's glyphs are laid out
  /// the same either way, only the box around them changes) and keeps the
  /// micro row at 28dp with 2dp of clearance.
  ///
  /// Measured, not derived: 63.76dp × 13dp at textScaler 1.0 and
  /// 82.86dp × 17dp at 1.3 for the «09:00–09:20» fixture — NARROWER than the
  /// 66.65 / 86.58 the outgoing 11.5 sp recipe measured, so the compact
  /// identity row's `Expanded` client name GAINED ~3.7dp of budget in the
  /// change (see `master_booking_card.dart`'s row-1 comment).
  static final TextStyle masterCardTime = masterCardDateFull.copyWith(
    height: 1.2,
  );

  /// FROZEN COPY of [masterCardTime]'s pre-2026-08-15 recipe (Nunito 11 sp,
  /// [BrandColors.muted], height 1.2) — literal values, NOT derived from
  /// [masterCardDateFull], so it cannot move when that token does.
  ///
  /// [masterCardTime] itself shrank as part of the 2026-08-15 booking-card
  /// font-size pass (see [masterCardClientName]'s doc) because it derives
  /// from [masterCardDateFull], which the pass also stepped down (11 -> 10 sp)
  /// for the FULL card's own time caption and the free-card label. But
  /// [masterCardTime] is ALSO consumed by three screens that are NOT the
  /// booking card and were explicitly out of scope — `wishlist_row.dart`,
  /// `wishlist_compact_card.dart` and `passport_derived_block.dart` — and
  /// those three must render byte-identically to before. This token is what
  /// they now point at instead, so the booking card's own shrink cannot leak
  /// into them.
  ///
  /// Do NOT point a new booking-card call site at this — use
  /// [masterCardTime], which stays the single source recipe for the card's
  /// three densities (see that token's own "ONE TIME STYLE" doc).
  static final TextStyle masterCardTimeShared = _feedbackBase.copyWith(
    fontSize: 11,
    color: BrandColors.muted,
    height: 1.2,
  );

  /// [TimelineStatusBadge]'s label — feedback base at 9.0 sp, height 1.1 (down
  /// from the base's 1.4 — a compact pill has no room for generous leading).
  /// Colour (the resolved [BookingStatusVisual.accent]) is applied at the
  /// call site via a single `copyWith`, mirroring [feedback]'s own pattern.
  ///
  /// FONT-SIZE PASS (2026-08-15) — was 9 sp; see [masterCardClientName]'s doc.
  /// Stepped by 0.7 sp (~7.8%) rather than the usual 1 sp: at 9 sp this was
  /// already the smallest live token on the card, and a full 1 sp cut (11%)
  /// would have pushed it below what the "roughly 8%" step this pass targets
  /// allows for the rest of the scale.
  ///
  /// RESTORED to 9.0 sp the same day (mobile-perf/mobile-security audit):
  /// 8.3 sp fell below this section's 9 sp legibility floor (see the section
  /// header) — both auditors independently flagged it as the smallest live
  /// token on the card. This is a REVERSAL of the cut above, not a further
  /// step: the badge is back to its pre-pass size while every other
  /// `masterCard*` token keeps its ~1 sp reduction.
  ///
  /// GEOMETRY CHECK: growing this 0.7 sp back does NOT move
  /// [MasterBookingCard.fullLayoutNaturalHeight]. The FULL layout's row 3 is
  /// `max(price pill, badge)`, and the price pill
  /// ([VelvetText.masterCardPricePill] at [PriceTag.defaultVerticalPadding])
  /// measures 20dp there — comfortably taller than the badge at either 8.3 or
  /// 9.0 sp. Measured directly (`tester.getSize` on the real
  /// [TimelineStatusBadge], not token arithmetic): 15.0dp tall at 8.3 sp,
  /// 16.0dp at 9.0 sp, both textScaler 1.0 — still short of the pill's 20dp,
  /// so row 3, [fullLayoutNaturalHeight] (115) and the full/compact threshold
  /// are all unchanged by this restoration. Re-verify this margin if the
  /// price pill's own vertical padding or type size ever shrinks again.
  static final TextStyle masterCardBadgeLabel = _feedbackBase.copyWith(
    fontSize: 9.0,
    height: 1.1,
  );

  /// Client monogram initials on a master booking card's avatar — subheading
  /// stepped to 14 sp, accentDeep. Unused since the compact-timeline pass
  /// dropped the avatar row (see `master_booking_card.dart`'s
  /// `_ClientAvatar` doc) — kept for the same future-reuse reason.
  ///
  /// FONT-SIZE PASS (2026-08-15) — was 15 sp; see [masterCardClientName]'s
  /// doc. Stepped for token-family consistency even though this token has no
  /// live call site today.
  static final TextStyle masterCardInitials = _subheadingStyle.copyWith(
    fontSize: 14,
    color: BrandColors.accentDeep,
  );

  /// The master booking card's OWN price-pill figure — [PriceTag]'s `pill()`
  /// verbatim, stepped down 0.8 sp (11 -> 10.2 sp, ~7.3%) for the 2026-08-15
  /// font-size pass (see [masterCardClientName]'s doc).
  ///
  /// `pill()` ITSELF IS UNCHANGED, on purpose: `PriceTag` (`core/widgets/
  /// price_tag.dart`) is shared with `wishlist_row.dart`,
  /// `wishlist_compact_card.dart` and `passport_derived_block.dart`, none of
  /// which were in scope for this pass — see [masterCardTimeShared] for the
  /// same constraint on the time caption. `PriceTag` now takes an optional
  /// `style` override (defaulting to `null`, which keeps `pill()`); only
  /// `master_booking_card.dart`'s TWO `PriceTag` call sites (the compact and
  /// full bodies) pass this token — the MICRO body has no price row (see
  /// that widget's class doc), so it never renders a `PriceTag` at all.
  static final TextStyle masterCardPricePill = _pillStyle.copyWith(
    fontSize: 10.2,
  );

  // Adaptive-layout pass (2026-07-20, later the same day as the compact
  // pass above): `MasterBookingCard` now renders a FULLER layout (client
  // name → divider → service+date → price+status) whenever its box is tall
  // enough (>=112dp — a 60-minute-and-up booking's proportional floor; see
  // that widget's `_kFullLayoutMinHeight`). These three tokens are that
  // layout's exclusive sizes, transcribed verbatim from the approved
  // design's own inline styles (`booking_widgets.dart`'s `BookingCard`) —
  // still under the `masterCard*` namespace per this section's header (a
  // dedicated type, not to be consolidated with the compact tokens above or
  // the client-side `bookingCard*` family).

  /// Client name on the FULL layout's row 1 — subheading at 12.5 sp.
  /// Transcribed from the design's `VelvetText.subheading().copyWith(
  /// fontSize: 13.5)`.
  ///
  /// FONT-SIZE PASS (2026-08-15) — was 13.5 sp; see
  /// [masterCardClientName]'s doc. [masterFreeCardTime] derives from this
  /// token and shrinks with it (deliberate — see that token's doc).
  static final TextStyle masterCardClientNameFull = _subheadingStyle.copyWith(
    fontSize: 12.5,
  );

  /// Service name on the FULL layout's row (below the divider) — bodyStrong
  /// at 11.5 sp. Transcribed from the design's
  /// `VelvetText.bodyStrong().copyWith(fontSize: 12.5)`.
  ///
  /// FONT-SIZE PASS (2026-08-15) — was 12.5 sp; see
  /// [masterCardClientName]'s doc.
  static final TextStyle masterCardServiceFull = _bodyStrongStyle.copyWith(
    fontSize: 11.5,
  );

  /// The FULL layout's time caption — feedback base at 10 sp, muted.
  /// Transcribed from the design's
  /// `VelvetText.feedback(VelvetColors.muted).copyWith(fontSize: 11)`.
  ///
  /// Named `…DateFull` for the date+time string it originally carried
  /// ("12 лип, 14:30"); since 2026-07-21 it renders a bare start–end RANGE
  /// ("14:30–16:00") — the day-scoped timeline dropped the per-card date, see
  /// `master_booking_card.dart`'s "The time is a RANGE" header section. The
  /// token name is left alone deliberately: it is purely a size/colour recipe
  /// and renaming it would churn every reference for no behavioural gain.
  ///
  /// FONT-SIZE PASS (2026-08-15) — was 11 sp; see [masterCardClientName]'s
  /// doc. [masterCardTime] (the compact/micro range) and [masterFreeCardLabel]
  /// (the free card's «Вільно» caption) both derive from this token and
  /// shrink with it — deliberate, both are in scope. The three EXTERNAL
  /// consumers of [masterCardTime] (wishlist/passport) do NOT shrink — see
  /// [masterCardTimeShared].
  static final TextStyle masterCardDateFull = _feedbackBase.copyWith(
    fontSize: 10,
    color: BrandColors.muted,
  );

  // Phase 244 typography-scale fix (2026-08-13) — the EXPLICIT_TIMES free
  // slot card (`declared_time_cards.dart`'s `_FreeTimeCard`) sits in the
  // SAME `ListView.separated` as a booked [MasterBookingCard] rendered at
  // its FULL layout (see that file's `_kEntryMinHeight` doc — the free
  // card's floor is pinned to the booked card's FULL-layout box, so the two
  // are always siblings at the same height). The free card originally used
  // `VelvetText.statValue()` (Comfortaa 17/700) for its time and
  // `VelvetText.subheading()` (Comfortaa 14/600) for its «Вільно» caption —
  // both borrowed from the STAT-TILE family, a full size tier louder than
  // anything else in this list. These two tokens instead borrow the FULL
  // layout's own two tiers verbatim, so a free card reads as a quieter
  // sibling of a booked one rather than a headline shouting over it.

  /// The EXPLICIT_TIMES free-card's declared time — [masterCardClientNameFull]
  /// verbatim (Comfortaa 12.5/600 as of the 2026-08-15 font-size pass, was
  /// 13.5/600) recoloured to [BrandColors.accentDeep]. The mocha recolour is
  /// deliberate and unchanged from the original intent (the card's anchor
  /// reads as structure, not a headline) — only the SIZE tier moved, first
  /// from the stat-value family down to the full-layout client-name family
  /// (Phase 244), then down again with the rest of that family in the
  /// 2026-08-15 pass (see [masterCardClientName]'s doc) — it derives from
  /// [masterCardClientNameFull], so it tracks that token automatically.
  static final TextStyle masterFreeCardTime = masterCardClientNameFull.copyWith(
    color: BrandColors.accentDeep,
  );

  /// The EXPLICIT_TIMES free-card's «Вільно» caption — [masterCardDateFull]
  /// verbatim (Nunito 10/700, [BrandColors.muted] as of the 2026-08-15
  /// font-size pass, was 11/700), i.e. the FULL layout's own secondary-tier
  /// recipe, unmodified — it derives from [masterCardDateFull] and tracks it
  /// automatically.
  static final TextStyle masterFreeCardLabel = masterCardDateFull;

  // ---------------------------------------------------------------------------
  // Phase 7.10 — the master timeline's hour ruler (`TimelineHourRuler`).
  //
  // Transcribed from the approved preview's `_TimelineGrid` time-label column
  // (`docs/signup-designs/SalonManagementDesign/lib/widgets/
  // bookings_toolbar.dart:1396-1407`), which spells the label as an inline
  // `VelvetText.statCaption().copyWith(fontSize: 11, color: ..., fontWeight:
  // ...)`. Cached here as two tokens (ordinary / closing) instead, so the
  // ruler — which repaints one Text per rendered hour — never allocates a
  // TextStyle per frame and `forbid_inline_fontsize.sh` stays green.
  // ---------------------------------------------------------------------------

  /// Ordinary hour-mark label ("09:00") — statCaption at 11 sp, muted.
  static final TextStyle timelineHourLabel = _statCaptionStyle.copyWith(
    fontSize: 11,
    color: BrandColors.muted,
  );

  /// The CLOSING hour label (the extent's last mark) — statCaption at 11 sp,
  /// w700, accent — the same "this is where the grid ends" emphasis the
  /// design gives its last ruler tick.
  static final TextStyle timelineHourLabelAccent = _statCaptionStyle.copyWith(
    fontSize: 11,
    color: BrandColors.accent,
    fontWeight: FontWeight.w700,
  );

  // ---------------------------------------------------------------------------
  // Design-parity pass (finding #4/#5) — the master timeline's month
  // switcher (`_MonthSwitcher` in `bookings_discovery_view.dart`), above the
  // day rail.
  //
  // Transcribed from the approved preview's inline
  // `VelvetText.subheading().copyWith(fontSize: 14)` (the month/year label)
  // and `VelvetText.body().copyWith(fontSize: 12.5, fontWeight:
  // FontWeight.w700, color: VelvetColors.accentDeep)` (the «Сьогодні» pill
  // label) — `bookings_toolbar.dart`'s `_MonthSwitcher`. Cached here, at this
  // app's already-established compact scale (every other transcribed booking
  // token in this file lands 1-3 sp under its design source), so neither
  // allocates a TextStyle per rebuild.
  // ---------------------------------------------------------------------------

  /// Month switcher's "month + year" label (e.g. "Липень 2026") — subheading
  /// at 12 sp.
  static final TextStyle monthSwitcherLabel = _subheadingStyle.copyWith(
    fontSize: 12,
  );

  /// Month switcher's «Сьогодні» pill label — body at 11 sp, w700, accentDeep.
  static final TextStyle monthSwitcherTodayLabel = _bodyStyle.copyWith(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: BrandColors.accentDeep,
  );

  // ---------------------------------------------------------------------------
  // 2026-07-26 — day-off / pause booking-conflict dialog (`DayOffConflictDialog`
  // presentation/widgets). Transcribed verbatim from the approved preview's
  // `docs/signup-designs/DayOffConflictDialog/lib/theme/velvet_tokens.dart`
  // (`VelvetText.rowName` / `.rowService` / `.rowTime` / `.rowTimeEnd`) —
  // this preview's sizes/heights match the CURRENT shipped scale exactly (no
  // "known doc conflict" shrink adjustment needed, unlike the older MyBookings
  // port), so every value below is a literal copy.
  // ---------------------------------------------------------------------------

  /// A conflict row's client name — the heaviest text in the row (the person
  /// is what the master is weighing). bodyStrong at w800, height 1.25.
  static final TextStyle dayOffConflictRowName = _bodyStrongStyle.copyWith(
    fontWeight: FontWeight.w800,
    height: 1.25,
  );

  /// A conflict row's service name, beneath the client name — body at 11 sp,
  /// tight-leading (1.25) so the two row lines read as one block.
  static final TextStyle dayOffConflictRowService = _bodyStyle.copyWith(
    fontSize: 11,
    height: 1.25,
  );

  /// A conflict row's start time — statValue (Comfortaa) at 15 sp, `height:
  /// 1.0` so the bare numeral sits tight in the right-aligned time stub,
  /// mirroring [schedWheelDigit] / [bookingDayNumber]'s tight-numeral device.
  static final TextStyle dayOffConflictRowTime = _statValueStyle.copyWith(
    fontSize: 15,
    height: 1.0,
  );

  /// A conflict row's end time — the quiet half of the time stub. Feedback
  /// base at 10.5 sp, muted, `height: 1.0`, w600.
  static final TextStyle dayOffConflictRowTimeEnd = _feedbackBase.copyWith(
    color: BrandColors.muted,
    fontSize: 10.5,
    height: 1.0,
    fontWeight: FontWeight.w600,
  );

  // ---------------------------------------------------------------------------
  // VelvetSnack (`lib/shared/feedback/`) — the unified transient-feedback
  // surface. Transcribed verbatim from the approved preview app at
  // `docs/signup-designs/VelvetSnack/lib/theme/velvet_tokens.dart`
  // (`VelvetText.snackMessage` / `.snackAction`). Color references changed
  // from `VelvetColors.*` to `BrandColors.*`.
  // ---------------------------------------------------------------------------

  static final TextStyle _snackMessageStyle = GoogleFonts.nunito(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    height: 1.4,
    color: BrandColors.text,
  );

  static final TextStyle _snackActionBase = GoogleFonts.nunito(
    fontSize: 12,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.2,
  );

  /// The snack message — [bodyStrong] (12/700) tightened to `height: 1.4` so
  /// a two-line message stays a compact block rather than an airy paragraph.
  static TextStyle snackMessage() => _snackMessageStyle;

  /// The trailing action label ("Повторити" / "Скасувати") — one weight
  /// above the message so it out-ranks the text beside it without needing a
  /// box around it. Colour (the variant accent) is applied at the call site
  /// via [TextStyle.copyWith].
  static TextStyle snackAction(Color color) =>
      _snackActionBase.copyWith(color: color);
}
