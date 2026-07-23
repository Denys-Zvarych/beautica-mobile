import 'package:flutter/material.dart';

import '../../core/icons/app_icon.dart';
import '../../core/icons/beautica_asset_icons.dart';
import '../../core/theme/brand_colors.dart';

/// A single rating star with a horizontal left→right fractional fill.
///
/// Two copies of [BeauticaAssetIcons.star] are stacked: a muted BASE empty star
/// and an accent FOREGROUND star clipped to the fill fraction with
/// `ClipRect` + `Align(widthFactor:)`. The accent star reveals from the left
/// edge, so a partial rating reads as a partially-filled single star.
///
/// ## Fill model (normalized — locked product choice)
///
/// ```text
/// fill = ((rating - 1) / 4).clamp(0.0, 1.0)
/// ```
///
/// So a rating of **1.0 is an empty star** and **5.0 is fully filled**
/// (e.g. 4.7 → 92.5% filled). A null or 0 rating renders an empty star.
///
/// This single-star fill model is the one canonical rating display across the
/// app, replacing every Material `Icons.star_*` glyph and the old 5-star row.
///
/// ## Label
///
/// When [showLabel] is true (the default) the numeric rating is shown beside the
/// star, formatted to one decimal (e.g. `4.7`). The label is DATA, not a
/// translatable string. A null rating hides the label.
class RatingStar extends StatelessWidget {
  const RatingStar({
    super.key,
    required this.rating,
    this.size = 24.0,
    this.showLabel = true,
    this.labelStyle,
    this.spacing = 2.0,
  });

  /// The rating value on the 1–5 scale; null = no rating yet (empty star).
  final double? rating;

  /// Star width and height in logical pixels (matches the Material icon it
  /// replaces at each site).
  final double size;

  /// Whether to render the numeric `n.n` label beside the star.
  final bool showLabel;

  /// Optional override for the numeric label text style.
  final TextStyle? labelStyle;

  /// Horizontal gap between the star and the numeric label.
  final double spacing;

  // Constant tints — hoisted to avoid per-build ColorFilter/withValues
  // allocation (perf backlog). The base (empty) star is a muted outline tone;
  // the foreground (filled) star is the camel accent.
  static const Color _baseColor = BrandColors.faint;
  static const Color _fillColor = BrandColors.accent;

  /// The left→right fill fraction for [rating], clamped to `[0, 1]`.
  ///
  /// Normalized so 1.0 → 0.0 (empty) and 5.0 → 1.0 (full).
  static double fillFor(double? rating) {
    if (rating == null) return 0;
    return ((rating - 1) / 4).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final double fill = fillFor(rating);

    final Widget star = SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // BASE — muted empty star.
          AppIcon(BeauticaAssetIcons.star, size: size, color: _baseColor),
          // FOREGROUND — accent fill revealed left→right to [fill].
          if (fill > 0)
            ClipRect(
              clipper: _LeftRevealClipper(fill),
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: fill,
                child: AppIcon(
                  BeauticaAssetIcons.star,
                  size: size,
                  color: _fillColor,
                ),
              ),
            ),
        ],
      ),
    );

    if (!showLabel || rating == null) {
      return star;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        star,
        SizedBox(width: spacing),
        Text(
          rating!.toStringAsFixed(1),
          style: labelStyle ?? DefaultTextStyle.of(context).style,
        ),
      ],
    );
  }
}

/// Clips the foreground star to its left [fraction] so the fill reveals from the
/// left edge. `Align(widthFactor:)` already shrinks the box; this clipper guards
/// against any sub-pixel overflow of the SVG silhouette past the reveal edge.
class _LeftRevealClipper extends CustomClipper<Rect> {
  const _LeftRevealClipper(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_LeftRevealClipper oldClipper) =>
      oldClipper.fraction != fraction;
}
