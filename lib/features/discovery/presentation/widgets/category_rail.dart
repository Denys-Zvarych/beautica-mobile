// Phase 13.x (Variant A — «Рейка + послуги») — horizontal category rail.
//
// Transcribed verbatim from the approved preview
// `docs/signup-designs/SearchCategoryDisplay/lib/widgets/category_widgets.dart`
// (`CategoryRailTile`, `CategoryRailMoreTile`), swapping the preview's local
// `VelvetColors.*` for the in-app `BrandColors.*` and the standalone tokens for
// `VelvetSpacing` / `VelvetRadii` / `VelvetShadows`. Pixel values (96 dp tile
// width, 64 dp label width, paddings, glyph sizes) are reproduced exactly.
//
// A fixed-height horizontal rail of the six popular categories ending in a
// «Всі категорії» tile. Resting tile = a raised soft pill with a glyph + label;
// selected = pressed-in inset well with a camel glyph. Sized so ~3.5 fit across
// a phone, so the rail's partially-clipped last tile signals "scroll for more"
// without ever growing the layout vertically.

import 'package:flutter/material.dart';

import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/theme/velvet_text.dart';
import '../../../../core/widgets/neumorphic.dart';

/// A compact category tile for the horizontal rail (Variant A). Resting = a
/// raised soft pill with a glyph + label; selected = pressed-in inset well with
/// a camel glyph.
class CategoryRailTile extends StatelessWidget {
  const CategoryRailTile({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color glyph = selected
        ? BrandColors.accent
        : BrandColors.textSecondary;
    final Widget inner = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.md,
        vertical: VelvetSpacing.sm + 2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: glyph, size: 24),
          const SizedBox(height: VelvetSpacing.xs + 2),
          SizedBox(
            width: 64,
            child: Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: VelvetText.body().copyWith(
                fontSize: 12,
                height: 1.15,
                fontWeight: FontWeight.w700,
                color: selected
                    ? BrandColors.accentDeep
                    : BrandColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 96,
          child: selected
              ? NeumorphicInset(radius: VelvetRadii.card, child: inner)
              : NeumorphicCard(
                  padding: EdgeInsets.zero,
                  shadows: VelvetShadows.extrudedSmall,
                  child: inner,
                ),
        ),
      ),
    );
  }
}

/// The trailing «Всі категорії» tile on the rail — a raised pill (apps icon)
/// that opens the full category sheet. Visually distinct so it reads as an
/// action, not another category.
class CategoryRailMoreTile extends StatelessWidget {
  const CategoryRailMoreTile({
    super.key,
    required this.onTap,
    required this.label,
    required this.semanticLabel,
  });

  final VoidCallback onTap;

  /// Two-line caption («Всі\nкатегорії»).
  final String label;

  /// Flattened single-line accessibility label.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 96,
          child: NeumorphicCard(
            padding: EdgeInsets.zero,
            shadows: VelvetShadows.extrudedSmall,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: VelvetSpacing.md,
                vertical: VelvetSpacing.sm + 2,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.apps_rounded,
                    color: BrandColors.accentDeep,
                    size: 24,
                  ),
                  const SizedBox(height: VelvetSpacing.xs + 2),
                  SizedBox(
                    width: 64,
                    child: Text(
                      label,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: VelvetText.body().copyWith(
                        fontSize: 12,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        color: BrandColors.accentDeep,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
