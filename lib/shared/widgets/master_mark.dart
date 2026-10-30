// The raised camel-gradient identity disc with initials.
//
// MOVED (REUSE-FIRST, phase 426) from
// `features/favorites/presentation/widgets/favorite_cards.dart`, where it was
// public but feature-local. The «Заблоковані клієнти» list
// (`features/moderation/`) draws the SAME mark (approved UgcSafety preview),
// and a `moderation/presentation` → `favorites/presentation` import would be
// a cross-feature presentation import, forbidden by the layering rule.
// `favorite_cards.dart` re-exports this file, so every existing importer
// resolves unchanged.
//
// Geometry is byte-identical to the original. The one addition, [imageUrl],
// is additive and null by default: every pre-existing caller renders exactly
// as before.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';

/// **One size for both identity marks** — the master's portrait disc and the
/// salon's storefront well are the same square (user decision 2026-08-24).
///
/// WHY 56 SPECIFICALLY. The mark is a FLOOR under a card's text column:
/// whichever is taller sets the card height. A single mark value S has to
/// thread a needle — below ~58, or a salon carrying a street stops being taller
/// than one without (both flatten to the same height); above ~52, or an
/// independent master falls to the same height as a full-address salon and then
/// below it. 56 is the largest integer inside that window, so it is the biggest
/// mark that still leaves all four row shapes a distinct height.
const double kFavoriteMarkSize = 56;

/// The identity mark for a person: a raised camel-gradient disc with initials.
class MasterMark extends StatelessWidget {
  const MasterMark({
    super.key,
    required this.initials,
    this.size = kFavoriteMarkSize,
    this.imageUrl,
    this.imageKey,
    this.monogramWhileLoading = false,
    this.decodeToCover = false,
  });

  final String initials;
  final double size;

  /// Phase 426 — the person's photo, drawn inside the disc through the shared
  /// [RemoteImage]. `null` (the default, every pre-existing caller) renders
  /// the initials disc exactly as before. A disallowed URL or a load error
  /// falls back to the initials.
  final String? imageUrl;

  /// Key forwarded to the photo's [RemoteImage]. `null` by default.
  final Key? imageKey;

  /// ADDITIVE: show the initials while [imageUrl] loads instead of the bare
  /// disc. `false` (the default) keeps every existing caller as it was.
  final bool monogramWhileLoading;

  /// ADDITIVE: decode with `RemoteImage.decodeToCover` so a non-square avatar
  /// is not decoded soft. `false` (the default) keeps every existing caller.
  final bool decodeToCover;

  /// The disc's own dark shadow — a deeper warm mocha than the card's, so it
  /// is visibly darker than the camel face and reads as genuine depth.
  static const Color _discShadow = Color(0xFF8C6A44);

  static const BoxDecoration _decoration = BoxDecoration(
    shape: BoxShape.circle,
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[
        BrandColors.accentLogo,
        BrandColors.accent,
        BrandColors.accentLatte,
      ],
      stops: <double>[0.0, 0.55, 1.0],
    ),
    boxShadow: <BoxShadow>[
      BoxShadow(color: _discShadow, offset: Offset(4, 4), blurRadius: 10),
      BoxShadow(
        color: BrandColors.shadowLightStrong,
        offset: Offset(-4, -4),
        blurRadius: 10,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final Widget monogram = Center(
      child: Text(
        // raw-ui-string-ok: the person's own initials, derived from their
        // name — data, not UI copy.
        initials,
        style: VelvetText.displayName().copyWith(
          // Runtime-computed from [size], not an inline literal: the mark's
          // glyph must stay proportional to the disc at any extent a caller
          // (or a golden) asks for. Allow-listed in
          // `scripts/.inline_fontsize_allow`.
          fontSize: size * 0.32,
          color: BrandColors.white,
        ),
      ),
    );
    final String? url = imageUrl;
    return Container(
      height: size,
      width: size,
      decoration: _decoration,
      child: url == null
          ? monogram
          : RemoteImage(
              key: imageKey,
              url: url,
              width: size,
              height: size,
              shape: RemoteImageShape.circle,
              excludeFromSemantics: true,
              fallback: monogram,
              decodeToCover: decodeToCover,
              loadingPlaceholder: monogramWhileLoading ? monogram : null,
            ),
    );
  }
}
