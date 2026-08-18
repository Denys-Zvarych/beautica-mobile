// Phase 14.6 — the leave-review screen's master identity card + the section
// eyebrow helper.
//
// Ported from the approved preview
// `docs/signup-designs/MasterFeedbackScreen/lib/widgets/master_feedback_card.dart`,
// mapped onto the project's tokens and reusing the shared booking-flow
// [MasterAvatarBadge] (the RRect Impeller-GLES-safe glyph) rather than the
// preview's duplicated avatar. The card surface is the same camel wash
// (`#EDE4D5`) the booking flow's master strips use, so this header reads as the
// same object the client already saw when they booked.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';

import 'master_avatar_badge.dart';
import 'master_strip.dart';

/// The master identity header on the leave-review screen. Avatar + name + the
/// master's ★ rating, with the completed booking's service + date as a quiet,
/// check-marked context line so the client is sure *which* visit they are
/// rating.
///
/// ## Why this is not `MasterStrip.fromBooking`
///
/// It is deliberately NOT the shared strip. The strip has three content slots
/// (name, one sub-line, one trailing) and this card needs four things: name,
/// role, the ★ readout AND the check-marked visit line. The visit line is the
/// card's whole reason to exist — it is the only thing on the screen that says
/// WHICH visit the client is about to rate, and a client with two bookings
/// from the same master has nothing else to tell them apart. Swapping in the
/// strip would trade that disambiguator for the rating; instead the card takes
/// the rating too, rendering it through the strip's own
/// [MasterRatingReadout], so the two cards cannot drift apart visually.
class MasterFeedbackCard extends StatelessWidget {
  const MasterFeedbackCard({
    super.key,
    required this.name,
    required this.roleLabel,
    required this.visitContext,
    this.avgRating,
    this.reviewCount = 0,
    this.onTap,
    this.semanticsLabel,
  });

  final String name;

  /// Role / subtitle line, e.g. «Незалежний майстер» or the salon name.
  final String roleLabel;

  /// The completed visit's context line, e.g. «Жіноча стрижка · 14 липня».
  final String visitContext;

  /// The master's average rating, or `null` when they have no reviews yet —
  /// rendered as [MasterStrip.noRatingLabel], never as `0.0`.
  final double? avgRating;

  /// How many reviews [avgRating] is computed from; `0` suppresses the `(n)`
  /// suffix.
  final int reviewCount;

  /// Opens the master's public reviews list; `null` leaves the card inert.
  ///
  /// Tappable here per the policy on [MasterStrip.onTap] — «Залишити відгук»
  /// is a review-shaped screen, and reading what other clients wrote is a
  /// natural detour from writing your own.
  final VoidCallback? onTap;

  /// Pre-composed, already-localized accessibility label for the whole card —
  /// mirrors the sibling `ClientFeedbackCard`'s own parameter, and keeps this
  /// widget l10n-free. Needed because [semanticsLabel] is the ONLY thing a
  /// screen reader gets here (the subtree is excluded), so the ★ readout is
  /// invisible unless the caller folds it into this string. Falls back to the
  /// pre-rating name + visit composition.
  final String? semanticsLabel;

  // Camel wash surface — matches the booking flow's master strip.
  static const Color _cardColor = Color(0xFFEDE4D5);

  /// The card radius, shared by the ink `Material` and the `InkWell` that
  /// clips the press wash to it. Compile-time `const` and hoisted (mobile-perf
  /// LOW) so a press — which rebuilds this card — stops allocating two fresh
  /// `BorderRadius` objects per build. Mirrors the sibling
  /// `MasterStripShell._radius`.
  static const BorderRadius _radius = BorderRadius.all(
    Radius.circular(VelvetRadii.card),
  );

  /// Press wash — the same camel tint `MasterStripShell` uses, so the two
  /// identity cards respond to touch identically.
  static final Color _splash = BrandColors.accent.withValues(alpha: 0.14);
  static final Color _highlight = BrandColors.accent.withValues(alpha: 0.07);

  // Hoisted display styles.
  static final TextStyle _nameStyle = VelvetText.feedbackName;
  static final TextStyle _contextStyle = VelvetText.bodyStrong13;

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(
      padding: const EdgeInsets.all(VelvetSpacing.md),
      child: Row(
        children: <Widget>[
          const MasterAvatarBadge(),
          const SizedBox(width: VelvetSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _nameStyle,
                ),
                const SizedBox(height: 2),
                Text(
                  roleLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VelvetText.feedbackMutedSm,
                ),
                const SizedBox(height: VelvetSpacing.xs),
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: BrandColors.success,
                    ),
                    const SizedBox(width: VelvetSpacing.xs),
                    Flexible(
                      child: Text(
                        visitContext,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _contextStyle,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: VelvetSpacing.sm),
          MasterRatingReadout(avgRating: avgRating, reviewCount: reviewCount),
        ],
      ),
    );

    final VoidCallback? tap = onTap;
    if (tap != null) {
      // Same construction as `MasterStripShell`: the InkWell needs a Material
      // ABOVE the card's opaque camel fill or the wash paints underneath it
      // and is never seen. `NeumorphicCard`'s own padding is moved inside so
      // the whole card surface — not just its content box — takes the tap.
      content = Material(
        type: MaterialType.transparency,
        borderRadius: _radius,
        child: InkWell(
          onTap: tap,
          borderRadius: _radius,
          splashColor: _splash,
          highlightColor: _highlight,
          child: content,
        ),
      );
    }

    return Semantics(
      label: semanticsLabel ?? '$name, $visitContext',
      button: tap != null,
      // The subtree is excluded, so the InkWell's own tap action never reaches
      // the accessibility tree — this node has to carry it, or the card
      // announces as a button that cannot be activated.
      onTap: tap,
      excludeSemantics: true,
      child: NeumorphicCard(
        color: _cardColor,
        padding: EdgeInsets.zero,
        child: content,
      ),
    );
  }
}

/// A small uppercase section eyebrow — «ВАША ОЦІНКА», «ВАШ ВІДГУК» — with a
/// trailing required/optional [tag]. Both [text] and [tag] arrive already
/// localized from the screen.
class ReviewSectionLabel extends StatelessWidget {
  const ReviewSectionLabel({
    super.key,
    required this.text,
    required this.tag,
    this.emphasized = false,
  });

  final String text;
  final String tag;

  /// When true (the required rating section) the tag is tinted camel
  /// [BrandColors.accentDeep]; otherwise muted (the optional comment section).
  final bool emphasized;

  static final TextStyle _tagAccent = VelvetText.feedbackTag.copyWith(
    color: BrandColors.accentDeep,
  );
  static final TextStyle _tagMuted = VelvetText.feedbackTag.copyWith(
    color: BrandColors.muted,
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(text, style: VelvetText.label()),
        const SizedBox(width: VelvetSpacing.xs),
        Text(tag, style: emphasized ? _tagAccent : _tagMuted),
      ],
    );
  }
}
