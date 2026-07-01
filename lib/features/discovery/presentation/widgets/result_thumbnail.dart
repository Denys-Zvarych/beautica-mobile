// Phase 13.4 — Result card photo thumbnail.
//
// A 72dp rounded tile. When the search payload carries an [avatarUrl] it renders
// the network image (cover-fit), falling back to the warm camel gradient stand-in
// (with a person/storefront glyph) on a null URL or a load error — exactly the
// gradient placeholder from the approved preview's `_Thumbnail`.

import 'package:flutter/material.dart';

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

  Widget _placeholder() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: _radius,
        gradient: _placeholderGradient,
        boxShadow: VelvetShadows.extrudedSmall,
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
    final String? url = avatarUrl;
    // Image.network uses its own HttpClient (not the pinned Dio), so guard the
    // scheme here: only https is allowed. A null/empty/non-https URL falls
    // through to the gradient placeholder — this stops a malicious/compromised
    // `http://` avatar leaking the client IP if ATS/NSC is ever relaxed.
    final bool isHttps =
        url != null && url.isNotEmpty && Uri.tryParse(url)?.scheme == 'https';
    if (!isHttps) {
      return SizedBox(height: _size, width: _size, child: _placeholder());
    }
    // Cap decode resolution to the tile's physical pixel width so a full-res
    // avatar isn't decoded into a 72dp box. Height follows the aspect ratio
    // under BoxFit.cover.
    final int cacheWidth = (_size * MediaQuery.devicePixelRatioOf(context))
        .round();
    return SizedBox(
      height: _size,
      width: _size,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          borderRadius: _radius,
          boxShadow: VelvetShadows.extrudedSmall,
        ),
        child: ClipRRect(
          borderRadius: _radius,
          child: Image.network(
            url,
            fit: BoxFit.cover,
            cacheWidth: cacheWidth,
            errorBuilder: (_, _, _) => _placeholder(),
          ),
        ),
      ),
    );
  }
}
