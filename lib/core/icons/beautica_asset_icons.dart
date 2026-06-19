/// Asset-path registry for Beautica's SVG icon library.
///
/// Use this class whenever you need an SVG icon from `assets/icons/`. Every
/// path is a compile-time constant, so a typo or a missing file is caught
/// at build time rather than at runtime.
///
/// **Relationship to [BeauticaIcons]**
/// - [BeauticaIcons] (`lib/core/theme/beautica_icons.dart`) holds `IconData`
///   constants for Material font glyphs — zero-weight, always tintable.
/// - [BeauticaAssetIcons] (this file) holds asset paths for SVG files loaded
///   from the bundle via [AppIcon]. Use SVG assets when the desired glyph is
///   not in the Material icon set or when a custom Beautica-branded shape is
///   required.
///
/// **How to add an icon**
///   1. Drop the monochrome `.svg` file into `assets/icons/`.
///   2. Add a `static const String` below.
///   3. Use `AppIcon(BeauticaAssetIcons.yourIcon)` in your widget.
///
/// See also `assets/icons/README.md` for the full contributor guide.
abstract final class BeauticaAssetIcons {
  /// Base asset directory — keep in sync with `pubspec.yaml` flutter.assets.
  static const String _base = 'assets/icons';

  /// Sample 24 × 24 five-pointed star (outline stroke, single path).
  ///
  /// Included as the pipeline's smoke-test asset: if this renders, the
  /// `flutter_svg` + asset-bundle wiring is correct. Safe to remove once a
  /// real product icon replaces it.
  static const String sampleStar = '$_base/sample_star.svg';

  // ---------------------------------------------------------------------------
  // Add new icons below, grouped by feature / category.
  // Convention: feature_glyph, e.g. nav_home, booking_calendar, review_star.
  // ---------------------------------------------------------------------------
}
