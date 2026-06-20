import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// A reusable tinted SVG icon widget backed by [SvgPicture.asset].
///
/// Use [AppIcon] with paths from [BeauticaAssetIcons] to keep all icon
/// references type-safe and consistently themed.
///
/// ```dart
/// // Inherits the surrounding IconTheme colour (behaves like Material Icon):
/// AppIcon(BeauticaAssetIcons.homeOutline)
///
/// // Explicit VelvetTouch tint — works only on monochrome SVGs:
/// AppIcon(BeauticaAssetIcons.homeFilled, color: BrandColors.accent, size: 20)
///
/// // Accessible variant:
/// AppIcon(BeauticaAssetIcons.homeOutline, semanticLabel: l10n.homeLabel)
/// ```
///
/// ## Colour behaviour
///
/// When [color] is non-null, a `ColorFilter.mode(color, BlendMode.srcIn)` is
/// applied, replacing every non-transparent pixel with the given colour. This
/// works correctly for **monochrome** SVGs (single-colour fill or stroke). For
/// multicolour SVGs the filter flattens all colours — omit [color] and let the
/// SVG's own palette show through.
///
/// When [color] is null, [AppIcon] falls back to `IconTheme.of(context).color`
/// so it behaves like a standard [Icon] and inherits any ambient tint (e.g.
/// from an [IconTheme] wrapper or a [ListTile] leading icon slot).
///
/// ## Size
///
/// [size] controls both width and height. The rendered box is exactly
/// `size × size` logical pixels, matching the contract of Material's [Icon].
///
/// ## Accessibility
///
/// Pass [semanticLabel] to announce the icon's purpose to screen readers.
/// When null the icon is treated as decorative (excluded from semantics).
class AppIcon extends StatelessWidget {
  /// Creates a tinted SVG icon.
  ///
  /// [asset] is an asset path constant from [BeauticaAssetIcons] (or any
  /// other `assets/icons/` path registered in `pubspec.yaml`).
  const AppIcon(
    this.asset, {
    super.key,
    this.size = 24.0,
    this.color,
    this.semanticLabel,
    this.multicolor = false,
  });

  /// Asset path, e.g. `BeauticaAssetIcons.homeOutline`.
  final String asset;

  /// Rendered width and height in logical pixels. Defaults to 24.
  final double size;

  /// Tint colour applied via `ColorFilter.mode(color, BlendMode.srcIn)`.
  ///
  /// When null, the colour is inherited from `IconTheme.of(context).color`,
  /// matching the behaviour of a Material [Icon].
  final Color? color;

  /// Screen-reader label. When null the icon is marked decorative.
  final String? semanticLabel;

  /// When `true`, the SVG renders with its own baked-in palette and **no**
  /// `srcIn` tint is applied — even if [color] is non-null. Use this for
  /// genuinely multi-colour SVGs (e.g. a bell whose notification dot must stay
  /// red while the bell stays brown). Defaults to `false` (monochrome flatten).
  final bool multicolor;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? IconTheme.of(context).color;
    final colorFilter = (multicolor || effectiveColor == null)
        ? null
        : ColorFilter.mode(effectiveColor, BlendMode.srcIn);

    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: colorFilter,
      semanticsLabel: semanticLabel,
    );
  }
}
