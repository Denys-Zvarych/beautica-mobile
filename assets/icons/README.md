# Beautica SVG Icon Library

Drop monochrome SVG icons here. The pipeline tints them to the VelvetTouch palette at runtime — no separate themed copies needed.

## How to add an icon

1. **Download a monochrome SVG** — single colour, line/outline style. Recommended sources:
   - Heroicons (MIT) — https://heroicons.com
   - Lucide (ISC) — https://lucide.dev
   - Flaticon free tier (requires attribution in the app's "Licences" section)

2. **Clean and verify the SVG** — the file must contain a single foreground path with `stroke="currentColor"` or `fill="currentColor"` (or a fixed single colour). Remove embedded raster images, `<style>` blocks with multi-colour rules, or gradient fills. Multicolour SVGs render fine but cannot be theme-tinted.

   Before committing, open the raw file and confirm it contains **no** `<script>`, `<use xlink:href="…">`, or `<image href="data:…">` elements. Record the download URL and SHA-256 of the original file in a comment at the top of the SVG so provenance is auditable in git history:

   ```xml
   <!-- source: https://heroicons.com/outline/star  sha256: abc123… -->
   ```

3. **Drop into this folder** — e.g. `assets/icons/my_new_icon.svg`.

4. **Register a constant** in `lib/core/icons/beautica_asset_icons.dart`:

   ```dart
   static const String myNewIcon = '$_base/my_new_icon.svg';
   ```

5. **Use it** anywhere in the widget tree:

   ```dart
   // Inherits IconTheme color (default)
   AppIcon(BeauticaAssetIcons.myNewIcon)

   // Explicit tint — monochrome icons only
   AppIcon(BeauticaAssetIcons.myNewIcon, color: BrandColors.accent, size: 20)

   // With accessibility label
   AppIcon(BeauticaAssetIcons.myNewIcon, semanticLabel: l10n.starLabel)
   ```

## Flaticon source manifest (release-gate provenance)

Every Flaticon FREE icon's source URL is recorded here at download time (and as a
comment at the top of the SVG). Before any store build, re-download each under a
1-month Flaticon Premium and keep the licence certificate.

| Asset | Source URL | SHA-256 |
|---|---|---|
| `location_marker.svg` | https://www.flaticon.com/free-icon-font/marker_3916880 | `71111aa34ced576c936597993e431167ac111ce897203f52b9e05303b74a211c` |
| `star.svg` | https://www.flaticon.com/free-icon-font/star_3916582 | `5a27637436e57a5483fb36d85a456bbf9e733e76e230ab99ccf6adf87a408bf6` |
| `filter.svg` | https://www.flaticon.com/free-icon-font/filter_3914366 | `099791fb4a43ba6d05cdca105e2b9b1bc77898ada7ccc83bf04a3ca5e87ad5fa` |
| `category_hairdressing.svg` | https://www.flaticon.com/free-icon-font/barber-shop_3914559 | `701812988c4468f74e9260a2a548f1e0929cc45e27a60af2cf7207dd5f46aaac` |
| `category_nail_service.svg` | https://www.flaticon.com/free-icon-font/finger-nail_17699788 | `48290d0b4129dd8ca58a516aca2c2b720da765ae9234edb5cb31e234d4db50fa` |
| `category_lash_extensions.svg` | https://www.flaticon.com/free-icon-font/eye-lashes_18407551 | `bd8143eb0acf305bce291089d287a516e1c8466e583d1701e875af70578cdca0` |
| `category_makeup.svg` | https://www.flaticon.com/free-icon-font/blush_19002308 | `71b72b48fda6a145e23ffb9973723b9211c74f8da9cc8f1eb004bb6356d1115d` |
| `category_podology.svg` | https://www.flaticon.com/free-icon-font/footprint_17003879 | `52fc1a77492f6056826f1e5621af02bb58d5ae953eb2278f880b9c6f946a7d90` |
| `category_barbering.svg` | https://www.flaticon.com/free-icon-font/barber-pole_14700816 | `2dd8aaa56e4f63dd953fbd15fcec6aaa375356279627f92454c56d8a9fa5eb09` |
| `category_beard_care.svg` | https://www.flaticon.com/free-icon-font/beard_18556793 | `30babccdcccdf6519ddbd781e8baf3f89da7da988189a0e93ab1b8ea45f2f045` |

## Traced category icons (NOT Flaticon — no release-gate obligation)

13 of the 20 category icons (`category_brows.svg`, `category_hair_coloring.svg`,
`category_hair_treatment.svg`, `category_hair_extensions.svg`,
`category_trichology.svg`, `category_lash_lamination.svg`,
`category_cosmetology.svg`, `category_injection_cosmetology.svg`,
`category_hardware_cosmetology.svg`, `category_aesthetic_cosmetology.svg`,
`category_laser_cosmetology.svg`, `category_hair_removal.svg`,
`category_permanent_makeup.svg`) are traced in-repo from the user's own source
PNGs via `scripts/icons/trace_icon.py` (marching squares + Ramer-Douglas-Peucker
+ quadratic smoothing) — see `docs/mobile-phases/category-icons-resume.md` for
the method. They carry no Flaticon licence and are exempt from the
Premium-re-download release gate above.

## Notes

- `AppIcon` lives in `lib/core/icons/app_icon.dart`.
- Multicolour SVGs render but `AppIcon.color` has no effect on them.
- Flaticon free tier requires attribution — add the icon credit to the app's "Licences / Ліцензії" settings screen.
- Material `IconData` glyphs (font-based icons) are in `lib/core/theme/beautica_icons.dart`.
