// Phase 110 THIN-unification QA gap-closure (mobile-qa INFO → test).
//
// WHY THIS FILE EXISTS
// ---------------------
// `AppIcon` (`lib/core/icons/app_icon.dart`) tints every category glyph with
// a single `ColorFilter.mode(color, BlendMode.srcIn)`. That only renders
// correctly -- solid, correctly scaled, uniformly tinted -- when every
// `category_*.svg` obeys the SAME structural contract that
// `beautica_asset_icons.dart`'s own doc comment already promises in prose
// ("All 20 are monochrome ... `viewBox="0 0 24 24"`, one
// `<path fill-rule="evenodd">`, no fill/stroke colour attributes") but that,
// before this file, NOTHING enforced:
//
//   1. `viewBox="0 0 24 24"` -- any other viewBox scales the glyph wrong
//      relative to the fixed `kGlyphAssetSize`/`kGlyphSize` constants every
//      call site assumes.
//   2. Exactly one `<path>` -- a second path is either dead weight or an
//      accidental multi-shape SVG that `multicolor: false` would flatten
//      into a single silhouette in an unintended way.
//   3. No `fill="..."` / `stroke="..."` colour attribute on the root `<svg>`
//      or the `<path>` -- `fill-rule="evenodd"` is fine (a rasterisation
//      rule, not a colour). A stray `fill="none"` (outline-only) or a
//      `stroke`-only path changes which pixels are opaque, which changes
//      what `srcIn` paints solid vs. hollow -- a real, visible regression
//      class that `ColorFilter.mode(..., BlendMode.srcIn)` does NOT protect
//      against on its own.
//
// The two `test/golden/` goldens that touch category icons
// (`category_rail_svg_glyphs_360_*`) photograph exactly ONE of the 20
// assets (`categoryBarbering`). A future asset drop that violates this
// contract on any of the other 19 would render wrong on-device while every
// existing test -- goldens included -- stayed green. This file closes that
// gap cheaply: it is a text-content check over 20 small XML files, no
// widget tree, no golden capture.
//
// Scope: every `assets/icons/category_*.svg` on disk (Group A, eroded
// Flaticon derivatives, AND Group B, in-repo traced) -- both groups make the
// same contract promise, so both are checked the same way. `category_brows`
// (the one asset left at a heavier stroke pending a separate user decision,
// see CLAUDE.md "Do NOT" list for this phase) still owes the SAME structural
// contract -- only its stroke *weight* is exempted, not this shape.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final Directory iconsDir = Directory('assets/icons');
  final List<File> categorySvgs =
      iconsDir
          .listSync()
          .whereType<File>()
          .where(
            (File f) =>
                f.uri.pathSegments.last.startsWith('category_') &&
                f.uri.pathSegments.last.endsWith('.svg'),
          )
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));

  test('exactly 20 category_*.svg assets are present on disk', () {
    expect(
      categorySvgs.length,
      20,
      reason:
          'the registry (`beautica_asset_icons.dart`) documents 20 '
          'category assets; a file added or removed under assets/icons/ '
          'without updating this count means the registry and the '
          'bundle have drifted',
    );
  });

  group('category_*.svg -- AppIcon structural contract', () {
    for (final File file in categorySvgs) {
      final String name = file.uri.pathSegments.last;
      final String content = file.readAsStringSync();

      test('$name has viewBox="0 0 24 24"', () {
        expect(
          content,
          contains('viewBox="0 0 24 24"'),
          reason:
              'AppIcon renders every category glyph at the same fixed '
              'logical size; a different viewBox scales this one glyph '
              'wrong relative to the other 19',
        );
      });

      test('$name has exactly one <path>', () {
        final int pathCount = '<path'.allMatches(content).length;
        expect(
          pathCount,
          1,
          reason:
              'the registry documents every category asset as a single '
              '<path fill-rule="evenodd">; a second path is either dead '
              'weight or an unintended multi-shape SVG',
        );
      });

      test('$name has no fill/stroke colour attribute (only fill-rule '
          'is allowed)', () {
        // `.contains('fill="')` does NOT false-positive on
        // `fill-rule="evenodd"` -- that substring is `fill-rule="`, not
        // `fill="`, so no negative-lookahead is needed here.
        expect(
          content.contains('fill="'),
          isFalse,
          reason:
              'AppIcon tints via ColorFilter.mode(color, BlendMode.srcIn); '
              'a baked-in fill="none" makes the shape interior transparent '
              '(alpha=0), so srcIn paints it hollow instead of solid',
        );
        expect(
          content.contains('stroke="'),
          isFalse,
          reason:
              'a stroke-only path (no fill) leaves the shape interior '
              'transparent under srcIn tinting, same failure mode as '
              'fill="none"',
        );
      });
    }
  });
}
