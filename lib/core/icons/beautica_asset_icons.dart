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
  // Navigation — search tab (center elevated disc)
  // ---------------------------------------------------------------------------

  /// Outline magnifier glyph.
  ///
  /// Source: https://www.flaticon.com/free-icon-font/search_3917132
  /// Author: Flaticon UICONS (free icon font).
  /// Licence: Flaticon Free (attribution required before release — add credit
  /// to the app's "Licences / Ліцензії" screen as a release-gate item).
  /// RELEASE-GATE: re-download under 1-month Premium before any store build,
  /// keep certificate. SHA-256 of the downloaded file:
  ///   6224533932f02f36c6a203e312826c2ff19f81961bf04beea7c40fb74ff4f824
  ///
  /// Decision: the center search disc uses [searchFilled] (heavier glyph reads
  /// better on the gradient disc surface). [searchOutline] is kept for registry
  /// completeness and future use (e.g. a search field leading icon).
  static const String searchOutline = '$_base/search_outline.svg';

  /// Solid magnifier glyph — used on the elevated center search disc.
  ///
  /// Derived in-repo from [searchOutline]; same 24×24 viewBox + proportions.
  /// See `assets/icons/search_filled.svg`.
  static const String searchFilled = '$_base/search_filled.svg';

  // ---------------------------------------------------------------------------
  // Navigation — favorites tab (index 1)
  // ---------------------------------------------------------------------------

  /// Outline heart glyph for the inactive favorites tab state.
  ///
  /// Source: https://www.flaticon.com/free-icon-font/heart_3916579
  /// Author: Flaticon UICONS (free icon font).
  /// Licence: Flaticon Free (attribution required; same release-gate as above).
  /// SHA-256: f3ebdd1b2d600d442dc69295a3e44253577013a088ba75ee5f58212282e82574
  static const String heartOutline = '$_base/heart_outline.svg';

  /// Filled heart glyph for the active favorites tab state.
  ///
  /// Derived in-repo from [heartOutline]; outer silhouette filled solid,
  /// no inner detail. Same 24×24 viewBox. See `assets/icons/heart_filled.svg`.
  static const String heartFilled = '$_base/heart_filled.svg';

  // ---------------------------------------------------------------------------
  // Navigation — bookings / записи tab (index 3)
  // ---------------------------------------------------------------------------

  /// Outline notepad glyph for the inactive bookings tab state.
  ///
  /// Source: https://www.flaticon.com/free-icon-font/memo-pad_9585401
  /// Author: Flaticon UICONS (free icon font).
  /// Licence: Flaticon Free (attribution required; same release-gate as above).
  /// SHA-256: 2ef24c44194cb521d3f2c99f2de2d4a19226e2edc4f70bbcc79044f19079872c
  static const String noteOutline = '$_base/note_outline.svg';

  /// Filled notepad glyph for the active bookings tab state.
  ///
  /// Derived in-repo from [noteOutline]; outer rounded-rectangle filled solid
  /// with inner text-line strips punched via fill-rule evenodd. Same 24×24
  /// viewBox. See `assets/icons/note_filled.svg`.
  static const String noteFilled = '$_base/note_filled.svg';

  // ---------------------------------------------------------------------------
  // Navigation — BEAUTY PASSPORT tab (index 4) + passport stat pill
  // ---------------------------------------------------------------------------

  /// Outline badge/id-card glyph for the inactive passport tab state.
  ///
  /// Source: https://www.flaticon.com/free-icon-font/id-badge_3914510
  /// Author: Flaticon UICONS (free icon font).
  /// Licence: Flaticon Free (attribution required; same release-gate as above).
  /// SHA-256: 0e1bd5ed12c3169dc05bc5a6dbfcd6299db0b74a49950358a4def679b59fb165
  static const String passportOutline = '$_base/passport_outline.svg';

  /// Filled badge/id-card glyph for the active passport tab state and the
  /// BEAUTY PASSPORT stat pill in the home hub.
  ///
  /// Derived in-repo from [passportOutline]; outer badge body filled solid with
  /// photo-box and text-line cutouts punched via fill-rule evenodd. Same 24×24
  /// viewBox. See `assets/icons/passport_filled.svg`.
  static const String passportFilled = '$_base/passport_filled.svg';

  // ---------------------------------------------------------------------------
  // Top-bar — notification bell
  // ---------------------------------------------------------------------------

  /// Plain bell glyph with **no baked-in notification dot** — used for the
  /// notification bell in the home hub top bar.
  ///
  /// Hand-authored in-repo; same 24×24 viewBox and filled-style weight as
  /// [notificationOutline] / [notificationFilled] but without the corner dot.
  /// The home-hub top bar draws its own app-controlled overlay dot (visible
  /// only when there are unread notifications), so the asset must stay dotless
  /// to avoid a permanent second dot. See `assets/icons/notification_plain.svg`.
  static const String notificationPlain = '$_base/notification_plain.svg';

  /// Unread-state bell — the **same bell silhouette** as [notificationPlain]
  /// plus a baked-in warm red-orange notification dot at the top-right corner.
  ///
  /// Hand-authored in-repo (no Flaticon release-gate). Unlike [notificationPlain]
  /// this is a **two-tone** asset (brown bell `#6E5743` + vermilion dot `#E2552F`
  /// with a base-colour ring), so it MUST be rendered with `AppIcon(...,
  /// multicolor: true)` — the default `srcIn` flatten would repaint the red dot
  /// to the bell colour and defeat the purpose. The home-hub bell swaps between
  /// this and [notificationPlain] on `hasUnread`, replacing the old code-drawn
  /// overlay dot. See `assets/icons/notification_unread.svg`.
  static const String notificationUnread = '$_base/notification_unread.svg';

  /// Outline bell-with-dot glyph (the Flaticon source has a notification dot
  /// **baked into the artwork**).
  ///
  /// Source: https://www.flaticon.com/free-icon-font/bell-notification-social-media_16309977
  /// Author: Flaticon UICONS (free icon font).
  /// Licence: Flaticon Free (attribution required; same release-gate as above).
  /// SHA-256: 99d1688d3ba2123ef9320e51b2e67cd44c18cd82aa0962cc6f86a935aa8ffdab
  ///
  /// Decision: the Flaticon source glyph is already a solid/filled-style shape
  /// (filled bell body + filled notification dot) so [notificationOutline] and
  /// [notificationFilled] are visually identical. **Do not** use either for the
  /// top-bar bell — their baked-in dot collides with the app-controlled overlay
  /// dot (the double-dot bug). Use [notificationPlain] there instead. Both
  /// constants are kept for registry symmetry / future use where a fixed dot is
  /// actually desired.
  static const String notificationOutline = '$_base/notification_outline.svg';

  /// Filled bell glyph — visually identical to [notificationOutline] because
  /// the Flaticon source is already a solid-style glyph (including the baked-in
  /// dot). Kept for registry symmetry. See `assets/icons/notification_filled.svg`.
  static const String notificationFilled = '$_base/notification_filled.svg';

  // ---------------------------------------------------------------------------
  // Location — pin / marker
  // ---------------------------------------------------------------------------

  /// Filled location-pin glyph — the single canonical location marker across the
  /// app (profile/passport locality lines, settings location rows, the locality
  /// picker field, the register location-step hero, and the master identity
  /// card address line). Replaces every `Icons.location_on_*` / `Icons.place_*`
  /// Material glyph.
  ///
  /// Source: https://www.flaticon.com/free-icon-font/marker_3916880
  /// Author: Flaticon UICONS (free icon font).
  /// Licence: Flaticon Free (attribution required; same release-gate as above —
  /// re-download under 1-month Premium before any store build, keep certificate).
  /// SHA-256: 71111aa34ced576c936597993e431167ac111ce897203f52b9e05303b74a211c
  ///
  /// Monochrome — render via `AppIcon(BeauticaAssetIcons.locationMarker,
  /// color: …, size: …)` so the `srcIn` tint matches the Material icon it
  /// replaced at each site. See `assets/icons/location_marker.svg`.
  static const String locationMarker = '$_base/location_marker.svg';

  // ---------------------------------------------------------------------------
  // Rating — star (single canonical rating glyph)
  // ---------------------------------------------------------------------------

  /// Single solid-silhouette star glyph — the one canonical rating star across
  /// the app (master rating badges, passport rating pill, master-profile rating
  /// stat, the "Мій рейтинг" client screen). Replaces every `Icons.star_*`
  /// Material glyph used for ratings.
  ///
  /// Rendered exclusively via [RatingStar] (`lib/shared/widgets/rating_star.dart`),
  /// which stacks two tinted copies — a muted BASE empty star plus an accent
  /// FOREGROUND star clipped to a left→right fractional fill — to show a single
  /// star whose fill encodes the normalized rating (1.0 = empty, 5.0 = full).
  ///
  /// Source: https://www.flaticon.com/free-icon-font/star_3916582
  /// Author: Flaticon UICONS (free icon font).
  /// Licence: Flaticon Free (attribution required; same release-gate as above —
  /// re-download under 1-month Premium before any store build, keep certificate).
  /// SHA-256: 5a27637436e57a5483fb36d85a456bbf9e733e76e230ab99ccf6adf87a408bf6
  ///
  /// Monochrome solid silhouette — render TINTED (pass a [AppIcon.color]); never
  /// `multicolor: true`. See `assets/icons/star.svg` and `assets/icons/README.md`.
  static const String star = '$_base/star.svg';

  // ---------------------------------------------------------------------------
  // Add new icons below, grouped by feature / category.
  // Convention: feature_glyph, e.g. booking_calendar, review_star.
  // ---------------------------------------------------------------------------
}
