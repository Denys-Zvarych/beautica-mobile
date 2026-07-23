// Phase 13.x (Variant A — «Рейка + послуги») — horizontal category rail.
//
// Originally transcribed from the approved preview
// `docs/signup-designs/SearchCategoryDisplay/lib/widgets/category_widgets.dart`.
// Reworked so the rail shows EVERY approved category (no «Всі категорії» sheet)
// in a clean row of UNIFORM cards — every tile is exactly the same fixed width
// AND height, regardless of label length. Short («Брови») and long
// («Перманентний макіяж») names both render in full, never clipped: a constant
// 2-line label area is reserved so a 1-line label card is exactly as tall as a
// 2-line one, with the glyph + label vertically centered in the box. Resting
// tile = a raised soft pill with a glyph + label; selected = pressed-in inset
// well with a camel glyph. The rail stays a single lazy horizontal scroll.

import 'package:flutter/material.dart';

import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/theme/velvet_text.dart';
import '../../../../core/widgets/neumorphic.dart';

/// A category tile for the horizontal rail (Variant A). Every tile is a fixed
/// [kTileWidth] × [kTileHeight] box so the rail reads as a clean row of
/// identical cards. A constant 2-line label area ([_kLabelMinHeight]) is
/// reserved and the glyph + label are vertically centered, so a 1-line label
/// («Брови») renders exactly as tall as a 2-line one («Перманентний макіяж»),
/// which wraps onto its second line without ellipsis clipping. Resting = a
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

  /// Uniform tile width — chosen so the longest approved label
  /// («Перманентний макіяж») still wraps cleanly onto two lines within the
  /// inner content width (width − 2×[_kTileHPadding] ≈ 100 dp) without a
  /// mid-word break, while short labels sit comfortably centered.
  static const double kTileWidth = 112;

  /// Uniform tile height — reserves the 24 dp glyph + gap + a 2-line label area
  /// with symmetric vertical breathing, centered. Constant across every tile so
  /// 1-line and 2-line labels yield identical-height cards.
  static const double kTileHeight = 80;

  /// Horizontal breathing inside the card; keeps the inner content width at
  /// ~100 dp (the proven width at which the longest label wraps to two lines).
  static const double _kTileHPadding = 6;

  /// Reserved vertical space for the label — two lines at the label style
  /// (2 × 12 × 1.15 ≈ 27.6 dp). A `minHeight` (not a fixed height) so the box
  /// grows instead of clipping at large text-scale settings.
  static const double _kLabelMinHeight = 28;

  static final TextStyle _labelResting = VelvetText.discCategoryLabelResting;

  static final TextStyle _labelSelected = VelvetText.discCategoryLabelSelected;

  @override
  Widget build(BuildContext context) {
    final Color glyph = selected
        ? BrandColors.accent
        : BrandColors.textSecondary;
    final Widget inner = Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kTileHPadding),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, color: glyph, size: 24),
          const SizedBox(height: VelvetSpacing.xs + 2),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _kLabelMinHeight),
            child: Align(
              alignment: Alignment.topCenter,
              child: Text(
                label,
                maxLines: 2,
                softWrap: true,
                textAlign: TextAlign.center,
                style: selected ? _labelSelected : _labelResting,
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
          width: kTileWidth,
          height: kTileHeight,
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
