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

## Notes

- `AppIcon` lives in `lib/core/icons/app_icon.dart`.
- Multicolour SVGs render but `AppIcon.color` has no effect on them.
- Flaticon free tier requires attribution — add the icon credit to the app's "Licences / Ліцензії" settings screen.
- Material `IconData` glyphs (font-based icons) are in `lib/core/theme/beautica_icons.dart`.
