// Shared master avatar badge — 48×48 by default, [MasterAvatarBadge.size]
// elsewhere.
//
// The single home of the booking flow's avatar glyph (a circular gradient +
// `person_rounded`), rendered through [MasterStripShell] by every booking
// screen in both flows. Edit the badge once, every card changes.
//
// IMPELLER-GLES WORKAROUND (ported verbatim from the deleted salon strip): the
// circle is drawn as an RRect (`borderRadius` = half the 48 dp side), NOT
// `shape: BoxShape.circle`. Under Impeller's OpenGLES backend a blurred
// `BoxShadow` on a `BoxShape.circle` rasterizes as a hard white square (the
// shadow's bounding box); the RRect blur path is correct. Using the shared
// badge routes the independent strip's avatar through the same correct path
// too (it previously used `BoxShape.circle` — a latent instance of the same
// bug). See `test/features/booking/impeller_circle_shadow_guard_test.dart`.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';

/// A small raised circular avatar glyph — a two-stop diagonal [gradient] wash
/// behind a white `person_rounded` icon, lifted by the small extruded shadow.
class MasterAvatarBadge extends StatelessWidget {
  const MasterAvatarBadge({
    super.key,
    this.gradient,
    this.bordered = false,
    this.size = 48,
    this.imageUrl,
  }) : assert(size > 0, 'size must be positive');

  /// Two-stop diagonal gradient; defaults to the independent-master flow's
  /// camel→mocha wash.
  final List<Color>? gradient;

  /// Adds the salon flow's 2 dp translucent-white ring. The independent flow
  /// leaves it off. The ring, the corner radius and the glyph all track
  /// [size], so a smaller badge stays proportionate rather than carrying a
  /// full-size ring on a half-size circle.
  final bool bordered;

  /// Phase 21.12 — the badge's side length. `48` (the default) is what every
  /// pre-existing call site renders, unchanged: [MasterStripShell] and its
  /// nine hosting screens pass nothing.
  ///
  /// The salon board's roster chip ([MasterColumnStrip]) passes `28` — a
  /// 148dp-wide column cannot hold a 48dp glyph beside a name, a role line and
  /// a rating. ADDITIVE and derived rather than a second set of literals: the
  /// radius stays exactly half the side (the Impeller RRect workaround above
  /// depends on that identity), and the ring width and glyph size scale with
  /// it, so there is still ONE avatar glyph in the booking flow rather than a
  /// forked "small" copy.
  final double size;

  /// Phase 9.7 — the master's photo. `null` (the default, every pre-existing
  /// caller) renders exactly the gradient + glyph above. When set, the photo is
  /// drawn through the shared [RemoteImage] inside the same circle, inset by the
  /// ring width; a disallowed URL or a load error falls back to the glyph.
  final String? imageUrl;

  static const List<Color> _defaultGradient = <Color>[
    Color(0xFFD8BE9C),
    Color(0xFF6A4A28),
  ];

  @override
  Widget build(BuildContext context) {
    final Widget glyph = Center(
      child: Icon(
        Icons.person_rounded,
        color: BrandColors.white.withValues(alpha: 0.82),
        size: size / 2,
      ),
    );
    final double ring = bordered ? size / 24 : 0;
    final double photo = size - 2 * ring;
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        // RRect (radius = half the side) reads as a circle but avoids
        // Impeller-GLES's broken circle box-shadow blur path (a blurred
        // BoxShadow on BoxShape.circle rasterizes as a hard white square under
        // the opengles backend).
        borderRadius: BorderRadius.circular(size / 2),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient ?? _defaultGradient,
        ),
        boxShadow: VelvetShadows.extrudedSmall,
        border: bordered
            ? Border.all(
                color: BrandColors.white.withValues(alpha: 0.35),
                width: size / 24,
              )
            : null,
      ),
      child: imageUrl == null
          ? glyph
          : RemoteImage(
              url: imageUrl,
              width: photo,
              height: photo,
              shape: RemoteImageShape.circle,
              excludeFromSemantics: true,
              fallback: glyph,
            ),
    );
  }
}
