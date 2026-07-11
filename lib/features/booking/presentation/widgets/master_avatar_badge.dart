// Shared 48×48 master avatar badge.
//
// Extracted from the inline circular-gradient + `person_rounded` glyph that
// both `widgets/master_strip.dart` (independent flow) and
// `widgets/salon_master_strip.dart` (salon flow) hand-rolled. Edit the badge
// once, both strips change.
//
// IMPELLER-GLES WORKAROUND (ported verbatim from `SalonMasterStrip`): the
// circle is drawn as an RRect (`borderRadius` = half the 48 dp side), NOT
// `shape: BoxShape.circle`. Under Impeller's OpenGLES backend a blurred
// `BoxShadow` on a `BoxShape.circle` rasterizes as a hard white square (the
// shadow's bounding box); the RRect blur path is correct. Using the shared
// badge routes the independent strip's avatar through the same correct path
// too (it previously used `BoxShape.circle` — a latent instance of the same
// bug). See `test/features/booking/impeller_circle_shadow_guard_test.dart`.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';

/// A small raised circular avatar glyph — a two-stop diagonal [gradient] wash
/// behind a white `person_rounded` icon, lifted by the small extruded shadow.
class MasterAvatarBadge extends StatelessWidget {
  const MasterAvatarBadge({super.key, this.gradient, this.bordered = false});

  /// Two-stop diagonal gradient; defaults to the independent-master flow's
  /// camel→mocha wash.
  final List<Color>? gradient;

  /// Adds the salon flow's 2 dp translucent-white ring. The independent flow
  /// leaves it off.
  final bool bordered;

  static const List<Color> _defaultGradient = <Color>[
    Color(0xFFD8BE9C),
    Color(0xFF6A4A28),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      width: 48,
      decoration: BoxDecoration(
        // RRect (radius = half the 48 dp side) reads as a circle but avoids
        // Impeller-GLES's broken circle box-shadow blur path (a blurred
        // BoxShadow on BoxShape.circle rasterizes as a hard white square under
        // the opengles backend).
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient ?? _defaultGradient,
        ),
        boxShadow: VelvetShadows.extrudedSmall,
        border: bordered
            ? Border.all(
                color: BrandColors.white.withValues(alpha: 0.35),
                width: 2,
              )
            : null,
      ),
      child: Center(
        child: Icon(
          Icons.person_rounded,
          color: BrandColors.white.withValues(alpha: 0.82),
          size: 24,
        ),
      ),
    );
  }
}
