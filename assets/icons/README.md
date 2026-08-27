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
1-month Flaticon Premium and keep the licence certificate. **The release-gate
obligation applies regardless of whether the committed file is the verbatim
download or a modified derivative (see the 7 `category_*` rows below) — it is
tied to the original Flaticon asset, not to the exact bytes in this folder.**

| Asset | Source URL | SHA-256 |
|---|---|---|
| `location_marker.svg` | https://www.flaticon.com/free-icon-font/marker_3916880 | `71111aa34ced576c936597993e431167ac111ce897203f52b9e05303b74a211c` |
| `star.svg` | https://www.flaticon.com/free-icon-font/star_3916582 | `5a27637436e57a5483fb36d85a456bbf9e733e76e230ab99ccf6adf87a408bf6` |
| `filter.svg` | https://www.flaticon.com/free-icon-font/filter_3914366 | `099791fb4a43ba6d05cdca105e2b9b1bc77898ada7ccc83bf04a3ca5e87ad5fa` |

### `category_*.svg` (7) — MODIFIED FROM ORIGINAL, 2026-08-26

Originally genuine verbatim Flaticon UICONS downloads at stroke weight **1.78**
(of 24 units). The other 13 category icons are traced in-repo at **0.56**, a
3.2× visual mismatch the user could see; two uniform variants were generated
(bold-the-13 capped at 1.03–1.31 before drawings fused; thin-the-7 closed the
gap cleanly) and the user picked **THIN**. Each row below is now an **in-repo
derivative work**: rasterised at 512, morphologically eroded to stroke ~0.56,
re-traced via `scripts/icons/trace_icon.py`. **A fresh download from the Source
URL will no longer hash-match the SHA-256 below** — that hash is of the eroded
source SVG the committed asset derives from, not of a pristine Flaticon
download. The original download's SHA-256, for historical record, is in this
file's git history (pre-2026-08-26) and in
`docs/mobile-phases/category-icons-provenance.md`.

**Two SHA-256 columns, two different jobs — do not conflate them:**
- **SHA-256 (eroded source, current)** — the *provenance chain* hash. It
  identifies the intermediate the trace tool consumed, one step back from
  the committed file. It will NOT match a fresh download, and it will NOT
  match `sha256sum` on the file sitting in this repo.
- **SHA-256 (committed file)** — the *tamper-evidence* hash. It IS
  `sha256sum` of the exact bytes committed at `assets/icons/category_*.svg`
  today. Use this column, not the one above, to detect whether the on-disk
  asset has been altered since this table was written.

| Asset | Source URL | SHA-256 (eroded source, current) | SHA-256 (committed file) | Modification |
|---|---|---|---|---|
| `category_hairdressing.svg` | https://www.flaticon.com/free-icon-font/barber-shop_3914559 | `027279c404a295099c7b639790b68f2f84eb7524daa9b2a693818bc0555c2826` | `043b6c184e493fa08bc46a87b7d3b12f81358f42cf1f0a33a558bddbf85481e8` | eroded 1.78→0.56 |
| `category_nail_service.svg` | https://www.flaticon.com/free-icon-font/finger-nail_17699788 | `df95f685587f0e3da007e49a23147b8850c5728b07fe5602043e7e65b332a311` | `50c25c5adace277a4b9389adfa91cab32663091f2c0980566e04edf7f2e879ae` | eroded 1.78→0.56 |
| `category_lash_extensions.svg` | https://www.flaticon.com/free-icon-font/eye-lashes_18407551 | `edfd2757dcb05b52a48da0b3106ab17c80b6d9503b259831235e5c342fb14f88` | `d603110f434f64811c0714fdaabbfef782ccca58537a5d941ebd06257b52ebdf` | eroded 1.78→0.56 |
| `category_makeup.svg` | https://www.flaticon.com/free-icon-font/blush_19002308 | `14b63f764fbcb6ac56a29ed38ddae98d19f8904cb6d4d758af7fc9465cf44094` | `5f4ede77b0a4e3b0a51868232a943b44c7822c650066e74ac1d2f4003f17077c` | eroded 1.78→0.56 |
| `category_podology.svg` | https://www.flaticon.com/free-icon-font/footprint_17003879 | `11529263bd0c83e311f1885ddf549af612c40e3361a26bd520505ccc4446d657` | `704b3431678716e5a27f9ceb2e8e0a7f1446ceaa03f346132f61ba0eac004034` | eroded 1.78→0.56; smallest toe-dot loop merged into its neighbour (7→6 closed subpaths) |
| `category_barbering.svg` | https://www.flaticon.com/free-icon-font/barber-pole_14700816 | `17336fa200b7b43cb80ce9dbbd1a1e863be20588da1696235ce7fdacfb5b0dd1` | `6a85f2b3946c783fa7ce627a9612358fde2bd1bf462f80276c928fe22e32dd58` | eroded 1.78→0.56 |
| `category_beard_care.svg` | https://www.flaticon.com/free-icon-font/beard_18556793 | `1df0ed76e9d1e9b620154b0e793f6821bbd79f8299c0507c2b8b309705e610c4` | `7e817e7d680a5301dfe1c0ba7549f39051ef269e29e0df6e11e578b14c17c068` | eroded 1.78→0.56 |

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
