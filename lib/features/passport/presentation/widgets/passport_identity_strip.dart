// Phase 238 — the BEAUTY PASSPORT identity strip.
//
// Transcribed from the approved preview
// `docs/signup-designs/BeautyPassport/lib/widgets/passport_widgets.dart`
// (`PassportIdentityStrip`). Preview tokens resolved to the shipped scale;
// the derived lines routed through the ARB; the two brand literals kept
// verbatim as named constants.
//
// Replaces the retired full-page "document" card (`passport_table.dart`,
// deleted in this phase) — the ruled «Улюблені процедури» / «Улюблені райони» /
// «Бюджет» fields, the tally-dot rank affordance and the embossed «B»
// watermark are gone, not merely unrouted.
//
//   ┌──────────────────────────────────────────────────────────────┐
//   │ (♛)  BEAUTY PASSPORT                │  12 відгуків залишено  │
//   │      Твій б'юті-паспорт у Beautica  │  Користувач з 2026     │
//   └──────────────────────────────────────────────────────────────┘
//
// ## The signature is the counter-rule
//
// A full-height hairline splitting brand (left) from standing (right) is what
// makes a 2x2 type block read as a document's ISSUING PANEL instead of two
// loose paragraphs. The right column is right-ALIGNED for the same reason: a
// counter column reads against a rule, not away from it.
//
// This is the page's only HEAVY neumorphic surface (raised `extrudedCard` +
// blush wash). Everything below it uses the flat, airy Головна card language,
// so the page has one focal surface and a calm tail.
//
// ## How the seal earns its width back
//
// The seal leads the WHOLE card, not the left column, so both text columns
// still start from one baseline. Its 32 dp + gap is paid for by three cuts,
// none of which touches a § 9 token: card padding tightened to `AppSpacing.sm`,
// the counter-rule gutters tightened to `xxs + 1 + xxs`, and the flex split
// moved to 56/44 so the TITLE gets the slack rather than the counter column.
//
// Measured against that, at 360 dp the left column is ~134 dp and the locked
// literal needs ~129, so it renders at FULL SIZE; at 320 dp it is ~111 and the
// literal scales to ~87%.
//
// ## WHY NOTHING HERE CAN WRAP OR CLIP
//
// The two FIRST rows — the brand literal and the standing line — are each
// wrapped in a `FittedBox(BoxFit.scaleDown)`. That pins them to exactly ONE
// line at every viewport: they shrink uniformly rather than wrapping,
// ellipsising or clipping. The two SECOND rows (subtitle, member-since) are
// plain unbounded [Text] — free to wrap, never clipped.
//
// NO `maxLines` AND NO `TextOverflow` APPEARS ANYWHERE IN THIS FILE.
//
// Read-only by design: both right-hand values are derived, and there is no edit
// affordance anywhere on this widget.

import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/theme/velvet_text.dart';
import '../../../../l10n/app_localizations.dart';

/// The locked, untranslated product title.
// ignore: constant_identifier_names — brand literal, kept verbatim.
const String kBeautyPassportTitle = 'BEAUTY PASSPORT';

/// The locked, untranslated product subtitle. Ukrainian, but a brand line
/// rather than UI copy — it ships identically in every locale by product
/// decision, exactly like the title above it.
const String kBeautyPassportSubtitle = 'Твій б’юті-паспорт у Beautica';

/// The passport identity strip: a leading crown seal, then two columns, two
/// rows.
class PassportIdentityStrip extends StatelessWidget {
  const PassportIdentityStrip({
    super.key,
    required this.reviewsWritten,
    required this.memberSinceYear,
  });

  /// How many reviews the client has WRITTEN. Derived, read-only.
  final int reviewsWritten;

  /// The year the client joined, from the wire. NEVER defaulted to the current
  /// year — `Passport.memberSinceYear` is a required non-null int precisely so
  /// no call site can fabricate one, and the fabrication that used to live on
  /// this page was deleted in Phase 235.
  final int memberSinceYear;

  /// Flex split. 56/44 rather than 50/50 so the locked literal gets the slack —
  /// «BEAUTY PASSPORT» needs ~129 dp and «12 відгуків залишено» ~114 dp, so the
  /// title is the tighter fit and the extra width goes to it.
  static const int _kBrandFlex = 56;
  static const int _kStandingFlex = 44;

  /// The counter-rule.
  static const double _kHairline = 1;
  static const double _kHairlineAlpha = 0.5;

  /// The blush wash, transcribed from the approved preview's
  /// `VelvetGradients.identityBlush`
  /// (`docs/signup-designs/BeautyPassport/lib/theme/velvet_tokens.dart:679`).
  ///
  /// A VERTICAL, TWO-STOP ramp: `base` lifted toward the creamy highlight at
  /// the top, warmed toward camel at the bottom. Both blend factors are named
  /// so the ramp cannot drift between call sites — they are the preview's
  /// `_blushLift` / `_blushWarm`.
  ///
  /// All three properties are load-bearing and were each wrong before:
  ///   * VERTICAL, not diagonal — a document panel is lit from above, and a
  ///     top-left→bottom-right axis lights it from the corner instead.
  ///   * TWO stops, not three — a flat `base` stop inserted mid-ramp flattens
  ///     the gradient into two short washes with a dead band between them.
  ///   * `shadowLightStrong` (#FFFBF4), not `white` (#F5EDE0) — the cream
  ///     `white` is a TEXT colour on accent; the neumorphic light token is what
  ///     every other raised surface highlights with, and it is the brighter of
  ///     the two, which is what makes the strip read as raised at all.
  static final LinearGradient _blush = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      Color.lerp(BrandColors.base, BrandColors.shadowLightStrong, _kBlushLift)!,
      Color.lerp(BrandColors.base, BrandColors.accent, _kBlushWarm)!,
    ],
  );

  /// How far `base` is lifted toward the creamy highlight at the top.
  static const double _kBlushLift = 0.45;

  /// How far `base` is warmed toward camel at the bottom.
  static const double _kBlushWarm = 0.10;

  static final BoxDecoration _decoration = BoxDecoration(
    gradient: _blush,
    borderRadius: BorderRadius.circular(VelvetRadii.card),
    boxShadow: VelvetShadows.extrudedCard,
  );

  static final Color _ruleColor = BrandColors.faint.withValues(
    alpha: _kHairlineAlpha,
  );

  /// Colour lifted to `text` because this is the strip's PRIMARY line, not a
  /// section eyebrow. Hoisted: `copyWith` per build is pure waste here.
  static final TextStyle _titleStyle = VelvetText.homeSectionLiteral.copyWith(
    color: BrandColors.text,
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Container(
      key: const Key('passport_identity_strip'),
      decoration: _decoration,
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Center(child: _PassportSeal()),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              flex: _kBrandFlex,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // Locked brand literal — never translated, pinned to one line.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(kBeautyPassportTitle, style: _titleStyle),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  // Unbounded — free to wrap, never clipped.
                  Text(
                    kBeautyPassportSubtitle,
                    style: VelvetText.homePassportPreviewSubtitle,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xxs),
            // The counter-rule: a full-height hairline, the strip's signature.
            Container(width: _kHairline, color: _ruleColor),
            const SizedBox(width: AppSpacing.xxs),
            Expanded(
              flex: _kStandingFlex,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      l10n.passportReviewsLeft(reviewsWritten),
                      textAlign: TextAlign.right,
                      style: VelvetText.homePassportPreviewTitle,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    l10n.passportMemberSince(memberSinceYear.toString()),
                    textAlign: TextAlign.right,
                    style: VelvetText.homePassportPreviewSubtitle,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The crown seal leading the identity strip — the same premium glyph the
/// retired document card used (`Icons.workspace_premium_rounded`), set in a
/// 32 dp CIRCULAR neumorphic well.
///
/// Circular, not the old rounded square, for two reasons: a disc reads as a
/// stamp pressed into the page (right for a passport, and it echoes the profile
/// avatar directly above), and a disc gives the § 9 `extrudedSmall` shadow pair
/// an even falloff at a size where a 12 dp-radius square starts to look like a
/// button. The well is filled with plain `base` while the card around it carries
/// the blush wash, so it reads as APPLIED to the card rather than cut from it.
class _PassportSeal extends StatelessWidget {
  const _PassportSeal();

  static const double _kSeal = 32;
  static const double _kGlyph = 18;

  static const BoxDecoration _decoration = BoxDecoration(
    color: BrandColors.base,
    shape: BoxShape.circle,
    boxShadow: VelvetShadows.extrudedSmall,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _kSeal,
      width: _kSeal,
      alignment: Alignment.center,
      decoration: _decoration,
      child: const Icon(
        Icons.workspace_premium_rounded,
        size: _kGlyph,
        color: BrandColors.accentDeep,
      ),
    );
  }
}
