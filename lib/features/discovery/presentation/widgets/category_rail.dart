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

import '../../../../core/icons/app_icon.dart';
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
    this.iconAsset,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Optional SVG asset path (e.g. from `categoryIconFor` in
  /// `core/icons/category_icons.dart`), rendered via [AppIcon] at
  /// [kGlyphAssetSize] instead of the Material [icon]. Additive — defaults to
  /// `null` so every existing caller keeps rendering the Material [icon] at
  /// [kGlyphSize] exactly as before.
  ///
  /// The asset glyph paints larger than the Material fallback because most of
  /// the 20 registered category SVGs are traced from detailed line artwork
  /// (up to 26 closed loops) that reads as a smudge below ~32 dp — confirmed
  /// by rendering the four densest (`category_cosmetology`,
  /// `category_hair_treatment`, `category_laser_cosmetology`,
  /// `category_aesthetic_cosmetology`) at 24–48 dp. 36 dp is the smallest size
  /// at which all of them read as distinct silhouettes.
  final String? iconAsset;

  /// Material [icon] glyph size — used only when [iconAsset] is null.
  static const double kGlyphSize = 24;

  /// [iconAsset] SVG glyph size — see [iconAsset]'s doc for why this is
  /// larger than [kGlyphSize].
  static const double kGlyphAssetSize = 36;

  /// Uniform tile width — chosen so the longest approved label
  /// («Перманентний макіяж») still wraps cleanly onto two lines within the
  /// inner content width (width − 2×[_kTileHPadding] ≈ 100 dp) without a
  /// mid-word break, while short labels sit comfortably centered.
  static const double kTileWidth = 112;

  /// Uniform tile height — reserves the glyph ([kGlyphAssetSize], the larger
  /// of the two glyph sizes so an [iconAsset] tile never clips) + gap + a
  /// 2-line label area with symmetric vertical breathing, centered. Constant
  /// across every tile so 1-line and 2-line labels yield identical-height
  /// cards. Grew 80→92 (+12, exactly [kGlyphAssetSize] − [kGlyphSize]) when
  /// [iconAsset] was added, to keep the same vertical breathing margin.
  static const double kTileHeight = 92;

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
    final Color glyphColor = selected
        ? BrandColors.accent
        : BrandColors.textSecondary;
    final Widget glyph = iconAsset != null
        ? AppIcon(iconAsset!, color: glyphColor, size: kGlyphAssetSize)
        : Icon(icon, color: glyphColor, size: kGlyphSize);
    final Widget inner = Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kTileHPadding),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          glyph,
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
