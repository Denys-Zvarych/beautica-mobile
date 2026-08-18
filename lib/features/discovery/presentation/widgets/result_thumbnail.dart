// Phase 13.4 — Result card photo thumbnail.
//
// A 72dp rounded tile. When the search payload carries an [avatarUrl] it renders
// the network image (cover-fit), falling back to the warm camel gradient stand-in
// (with a person/storefront glyph) on a null URL or a load error — exactly the
// gradient placeholder from the approved preview's `_Thumbnail`.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';

/// The 72dp photo thumbnail on a master/salon result card.
class ResultThumbnail extends StatelessWidget {
  const ResultThumbnail({
    super.key,
    required this.avatarUrl,
    required this.isSalon,
  });

  /// Avatar/logo URL, or null when the result has no photo.
  final String? avatarUrl;

  /// Whether this is a salon (storefront glyph) or a master (person glyph).
  final bool isSalon;

  static const double _size = 72;

  static const BorderRadius _radius = BorderRadius.all(
    Radius.circular(VelvetRadii.field),
  );

  // Warm camel gradient stand-in for a missing/failed photo.
  static const LinearGradient _placeholderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[BrandColors.accent, BrandColors.accentLatte],
  );

  // The gradient stand-in behind the shadowed frame. The extruded shadow now
  // lives on the always-present outer DecoratedBox (see [build]) so it wraps
  // BOTH the loaded photo and this fallback identically — as it did before,
  // when the loaded path carried the shadow on its own outer box and the
  // fallback carried its own copy.
  Widget _placeholder() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: _radius,
        gradient: _placeholderGradient,
      ),
      child: Icon(
        isSalon ? Icons.storefront_rounded : Icons.person_rounded,
        color: BrandColors.white.withValues(alpha: 0.9),
        size: 32,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The https-only + host-allowlist guard, decode-bounding and disk cache now
    // live in RemoteImage (core/media/beautica_image.dart). A null / empty /
    // non-https / non-allowed URL falls through to the gradient placeholder
    // WITHOUT a fetch. The 72dp rounded shape and the placeholder are
    // unchanged.
    return SizedBox(
      height: _size,
      width: _size,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          borderRadius: _radius,
          boxShadow: VelvetShadows.extrudedSmall,
        ),
        child: RemoteImage(
          url: avatarUrl,
          width: _size,
          height: _size,
          shape: RemoteImageShape.roundedRect,
          borderRadius: _radius,
          excludeFromSemantics: true,
          fallback: _placeholder(),
        ),
      ),
    );
  }
}
