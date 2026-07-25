// Track 7.x Wave B — the leave-client-feedback screen's client identity card.
//
// Ported from the approved preview
// `docs/signup-designs/LeaveClientFeedback/lib/widgets/client_feedback_card.dart`,
// mapped onto the project's tokens and reusing the shared booking-flow
// [MasterAvatarBadge] (the RRect Impeller-GLES-safe glyph, same camel→mocha
// gradient the preview's own `ClientAvatarBadge` used) rather than
// duplicating a second avatar widget, and the shipped [ReviewSectionLabel]
// (`master_feedback_card.dart`) rather than the preview's own `SectionLabel`
// — the two are the exact same eyebrow, already ported once.
//
// The card surface is the same camel wash (`#EDE4D5`) the booking flow's
// counterparty strips use, so this header reads as the same booking object
// the provider already served, mirroring `MasterFeedbackCard` exactly.
//
// NOTE (locked product decision, 2026-07-25): the approved preview's
// `ConfidentialityNote` widget («Видно лише спеціалістам») was REMOVED from
// the design by the user — it is deliberately NOT ported here. The inline
// «Клієнт цього коментаря не побачить» reminder near the comment field is a
// SEPARATE, still-live piece of the design and lives on the screen's comment
// card, not on this file.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';

import 'master_avatar_badge.dart';

/// The client identity header on the leave-client-feedback screen. Avatar +
/// name, with the completed booking's service + date as a quiet,
/// check-marked context line so the provider is sure *which* client and
/// *which* visit they are rating.
class ClientFeedbackCard extends StatelessWidget {
  const ClientFeedbackCard({
    super.key,
    required this.name,
    required this.roleLabel,
    required this.visitContext,
    required this.semanticsLabel,
  });

  final String name;

  /// Generic sub-label, e.g. «Клієнт».
  final String roleLabel;

  /// The completed visit's context line, e.g. «Манікюр · 14 липня».
  final String visitContext;

  /// Pre-composed accessibility label for the whole card, already localized
  /// by the caller (mirrors [visitContext] etc. — this widget stays
  /// l10n-free, like `MasterFeedbackCard`).
  final String semanticsLabel;

  // Camel wash surface — matches the booking flow's counterparty strips.
  static const Color _cardColor = Color(0xFFEDE4D5);

  // Hoisted display styles.
  static final TextStyle _nameStyle = VelvetText.feedbackName;
  static final TextStyle _contextStyle = VelvetText.bodyStrong13;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
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
