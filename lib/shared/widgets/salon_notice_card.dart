// A centred "nothing to do here" notice on the shared [NeumorphicInset] —
// a tinted glyph disc, a heading and a body line.
//
// PROMOTED (REUSE-FIRST, Phase 21.6 audit follow-up) out of
// `move_admin_salon_screen.dart`, where it was the file-private
// `_MoveTargetsEmptyState`. [StaffSettingsScreen]'s "this staff member is
// not an administrator" guard needs EXACTLY this shape, and being private was
// the signal a promotion was due — not a licence to copy it.
//
// MOVED (Phase 311, REUSE-FIRST) from `features/salon/presentation/widgets/`
// to here: the three schedule editors (`WeeklyTemplateEditorScreen`,
// `DayHoursSheet`, `ApplyScheduleSheet`) need this exact "you cannot act
// here" shape too, and `features/schedule/presentation/` importing
// `features/salon/presentation/widgets/` would be a cross-feature
// presentation→presentation import — forbidden by the architecture's
// layering rule (cross-feature imports go through `domain/` or `shared/`
// only). The widget has no salon-specific dependency (only `core/theme` +
// `core/widgets`), so it belongs here, not in a feature folder. Name kept as
// `SalonNoticeCard` — renaming would touch call sites for no behavioural
// gain; a future pass may rename it if a clearer generic name earns its
// churn.
//
// The geometry is byte-identical to the private original (glyph disc 56 dp,
// `accent @ 16%` fill, 26 dp icon, `VelvetSpacing.xl` padding, `md`/`sm`
// gaps, `subheadingWizard15` title over `feedbackMutedSm` body, both
// centred), so every existing caller renders exactly as before the move.
// Everything that varied between call sites — the glyph, the two copy lines
// and the widget key — is a parameter; nothing else was made configurable,
// so there is no way for a caller to drift the shape.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';

/// A non-actionable notice card: glyph, [title], [body].
class SalonNoticeCard extends StatelessWidget {
  const SalonNoticeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  /// The glyph inside the tinted disc.
  final IconData icon;

  /// Heading line — what the situation is.
  final String title;

  /// Supporting line — why, in the viewer's terms.
  final String body;

  static const double _glyphExtent = 56;

  // Hoisted — `withValues` allocates a Color, so never call it in build().
  static final BoxDecoration _glyphDecoration = BoxDecoration(
    shape: BoxShape.circle,
    color: BrandColors.accent.withValues(alpha: 0.16),
  );

  @override
  Widget build(BuildContext context) {
    return NeumorphicInset(
      radius: VelvetRadii.card,
      child: Padding(
        padding: const EdgeInsets.all(VelvetSpacing.xl),
        child: Column(
          children: <Widget>[
            Container(
              height: _glyphExtent,
              width: _glyphExtent,
              decoration: _glyphDecoration,
              child: Icon(icon, size: 26, color: BrandColors.accentDeep),
            ),
            const SizedBox(height: VelvetSpacing.md),
            Text(
              title,
              style: VelvetText.subheadingWizard15,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: VelvetSpacing.sm),
            Text(
              body,
              style: VelvetText.feedbackMutedSm,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
