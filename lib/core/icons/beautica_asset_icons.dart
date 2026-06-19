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

  // ---------------------------------------------------------------------------
  // Navigation — home tab
  // ---------------------------------------------------------------------------

  /// Outline/line-style home glyph for the inactive nav state.
  ///
  /// Licence: Flaticon Free (attribution required before release — add credit
  /// to the app's "Licences / Ліцензії" screen as a release-gate item).
  /// Author / original URL: TBD (pending provenance resolution).
  /// SHA-256 of the downloaded file:
  ///   f95493a915cc05109684f24823567931c9a9116ae164bbe6a5777b08fe60148e
  /// (recorded verbatim in the SVG's top comment for git-history auditability).
  ///
  /// See `assets/icons/home_outline.svg` and `assets/icons/README.md`.
  static const String homeOutline = '$_base/home_outline.svg';

  /// Filled home glyph for the active/selected nav state.
  ///
  /// Hand-authored in-repo to match `homeOutline`'s 24×24 viewBox and
  /// visual proportions (same roofline, same door opening). See
  /// `assets/icons/home_filled.svg`.
  static const String homeFilled = '$_base/home_filled.svg';

  // ---------------------------------------------------------------------------
  // Add new icons below, grouped by feature / category.
  // Convention: feature_glyph, e.g. booking_calendar, review_star.
  // ---------------------------------------------------------------------------
}
