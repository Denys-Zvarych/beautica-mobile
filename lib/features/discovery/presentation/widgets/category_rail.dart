// Phase 13.x (Variant A — «Рейка + послуги») — horizontal category rail.
//
// Originally transcribed from the approved preview
// `docs/signup-designs/SearchCategoryDisplay/lib/widgets/category_widgets.dart`.
// Reworked so the rail shows EVERY approved category (no «Всі категорії» sheet)
// and each tile sizes to its own label — short («Брови») and long
// («Перманентний макіяж») names both render in full, never clipped. Resting
// tile = a raised soft pill with a glyph + label; selected = pressed-in inset
// well with a camel glyph. The rail stays a single lazy horizontal scroll.

import 'package:flutter/material.dart';

import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/theme/velvet_text.dart';
import '../../../../core/widgets/neumorphic.dart';

/// A category tile for the horizontal rail (Variant A). The tile sizes to its
/// label (intrinsic width, bounded [_kMinTileWidth].._kMaxTileWidth) so the
/// full category name shows on one or two lines without ellipsis clipping.
/// Resting = a raised soft pill with a glyph + label; selected = pressed-in
/// inset well with a camel glyph.
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

  /// Floor so a short label («Брови») still reads as a comfortable pill, not a
  /// cramped chip.
  static const double _kMinTileWidth = 72;

  /// Ceiling so a long label («Перманентний макіяж») wraps onto a 2nd line
  /// instead of stretching the rail with one very wide tile.
  static const double _kMaxTileWidth = 132;

  static final TextStyle _labelBase = VelvetText.body().copyWith(
    fontSize: 12,
    height: 1.15,
    fontWeight: FontWeight.w700,
  );

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
          Text(
            label,
            maxLines: 2,
            softWrap: true,
            textAlign: TextAlign.center,
            style: _labelBase.copyWith(
              color: selected
                  ? BrandColors.accentDeep
                  : BrandColors.textSecondary,
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: _kMinTileWidth,
            maxWidth: _kMaxTileWidth,
          ),
          child: IntrinsicWidth(
            child: selected
                ? NeumorphicInset(radius: VelvetRadii.card, child: inner)
                : NeumorphicCard(
                    padding: EdgeInsets.zero,
                    shadows: VelvetShadows.extrudedSmall,
                    child: inner,
                  ),
          ),
        ),
      ),
    );
  }
}
