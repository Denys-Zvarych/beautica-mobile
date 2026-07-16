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

/// The master identity header on the leave-review screen. Avatar + name, with
/// the completed booking's service + date as a quiet, check-marked context line
/// so the client is sure *which* visit they are rating.
class MasterFeedbackCard extends StatelessWidget {
  const MasterFeedbackCard({
    super.key,
    required this.name,
    required this.roleLabel,
    required this.visitContext,
  });

  final String name;

  /// Role / subtitle line, e.g. «Незалежний майстер» or the salon name.
  final String roleLabel;

  /// The completed visit's context line, e.g. «Жіноча стрижка · 14 липня».
  final String visitContext;

  // Camel wash surface — matches the booking flow's master strip.
  static const Color _cardColor = Color(0xFFEDE4D5);

  // Hoisted display styles.
  static final TextStyle _nameStyle = VelvetText.displayName().copyWith(
    fontSize: 16,
  );
  static final TextStyle _contextStyle = VelvetText.bodyStrong().copyWith(
    fontSize: 11,
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$name, $visitContext',
      excludeSemantics: true,
      child: NeumorphicCard(
        color: _cardColor,
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
          ],
        ),
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

  static final TextStyle _tagAccent = VelvetText.feedback(
    BrandColors.accentDeep,
  ).copyWith(fontSize: 10);
  static final TextStyle _tagMuted = VelvetText.feedback(
    BrandColors.muted,
  ).copyWith(fontSize: 10);

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
