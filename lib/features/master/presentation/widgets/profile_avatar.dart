// Phase 4.2 — ProfileAvatar and RoleChip for master-profile screens.
//
// Ported verbatim from the approved preview app at
// `docs/signup-designs/MasterProfileScreen/lib/widgets/profile_widgets.dart`.
//
// Changes from the preview:
//   • VelvetColors.* → BrandColors.*
//   • VelvetSpacing.* unchanged (same constants in velvet_geometry.dart)
//   • VelvetSizes.avatar not in production VelvetSizes — using the preview
//     value 104 directly via the named constant [ProfileAvatar.kDiameter].

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';

/// The avatar well — a recessed circular well that "sinks" into the surface,
/// holding a camel [Icons.person_outline] placeholder. The concave look reads
/// as an empty photo slot waiting to be filled (Phase 4.4).
///
/// The production [NeumorphicInset] does not support a `circle` parameter, so
/// this widget paints the inset inner-shadow effect directly via a circular
/// [CustomPaint] layer, then clips child content with [ClipOval].
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, this.diameter = kDiameter});

  /// Default avatar diameter — matches the preview spec (96–112 px band).
  static const double kDiameter = 104;

  final double diameter;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Фото профілю',
      image: true,
      child: SizedBox(
        key: const Key('master-profile-avatar'),
        height: diameter,
        width: diameter,
        child: CustomPaint(
          painter: const _CircleInsetPainter(),
          child: ClipOval(
            child: ColoredBox(
              color: BrandColors.base,
              child: Center(
                child: Icon(
                  Icons.person_outline,
                  color: BrandColors.accent,
                  size: diameter * 0.42,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the neumorphic inset inner-shadow effect on a circular shape.
///
/// Mirrors the logic of [_InsetShadowPainter] in `neumorphic.dart` but
/// clips to [Rect.fromLTWH] as a full circle (no rounded rect needed).
class _CircleInsetPainter extends CustomPainter {
  const _CircleInsetPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final double r = size.width / 2;
    final Offset center = Offset(r, r);

    final Paint dark = Paint()
      ..color = BrandColors.shadowDarkButton
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final Paint light = Paint()
      ..color = BrandColors.shadowLightStrong
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final Paint fill = Paint()..color = BrandColors.base;

    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: r)),
    );

    // Dark inner shadow from top-left.
    canvas.drawCircle(center.translate(-5, -5), r, dark);
    // Light inner shadow from bottom-right.
    canvas.drawCircle(center.translate(5, 5), r, light);
    // Re-fill the centre with base tone — only rim glows remain.
    canvas.drawCircle(center, r - 4, fill);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_CircleInsetPainter oldDelegate) => false;
}

/// A small recessed pill for the role label ("Незалежний майстер").
///
/// Inset treatment signals non-tappable badge rather than an action.
class RoleChip extends StatelessWidget {
  const RoleChip({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return NeumorphicInset(
      radius: 999,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VelvetSpacing.md,
          vertical: VelvetSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 14, color: BrandColors.accentDeep),
              const SizedBox(width: VelvetSpacing.xs - 2),
            ],
            Text(
              label,
              // Fix 3 (PERF MEDIUM-1): use pre-cached static instead of
              // calling feedback().copyWith() per build frame.
              style: VelvetText.feedbackAccentSm,
            ),
          ],
        ),
      ),
    );
  }
}

/// A single raised stat tile — icon → value → caption centred in a column.
///
/// Used in the 4-up stats row (bookings/rating/services/reviews).
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.value,
    required this.caption,
    this.iconColor = BrandColors.accent,
    this.valueKey,
  });

  final IconData icon;
  final String value;
  final String caption;
  final Color iconColor;

  /// Optional [Key] placed on the value [Text] — used by widget tests.
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$value $caption',
      child: NeumorphicCard(
        padding: const EdgeInsets.symmetric(
          vertical: VelvetSpacing.xs,
          horizontal: VelvetSpacing.xs,
        ),
        radius: VelvetRadii.field + 2,
        shadows: VelvetShadows.extrudedSmall,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(height: VelvetSpacing.xs),
              Text(value, key: valueKey, style: VelvetText.statValue()),
              const SizedBox(height: 1),
              Text(
                caption,
                style: VelvetText.statCaption(),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
