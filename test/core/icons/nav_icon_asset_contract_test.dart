// Regression guard for the 2026-08-29 stroked-hairline nav icon defect.
//
// WHY THIS FILE EXISTS
// ---------------------
// `assets/icons/team_outline.svg` was, until this fix, the ONLY asset in
// `assets/icons/` built by STROKING a filled contour instead of filling it
// (`fill="none"` + `stroke="#000000" stroke-width="0.56"`). Every other icon
// in the bottom-nav sets -- `home_*`, `heart_*`, `note_*`, `passport_*`, and
// `team_*`'s own filled partner -- is a solid-fill path with no stroke. At
// the real 22dp nav size the stroked glyph rendered as a hairline roughly 3x
// lighter than its neighbours in the same bar; the user reported it as "not
// in our style".
//
// `test/golden/salon_bottom_nav_golden_test.dart` was regenerated FROM the
// fixed assets as part of this same change, so it is self-referential for
// this defect class: a future regression that reintroduces a stroked
// derivative and re-runs `--update-goldens` would happily re-bless the
// hairline. (Project rule: a regenerated golden is not acceptance for a
// visual bug.) This file is the independent, non-regenerable check -- it
// reads the SVG source text directly, the same way
// `test/core/icons/category_icon_asset_contract_test.dart` already does for
// the category set. It is intentionally a separate file, not a fork of that
// one: the category set and the nav set are registered, sourced, and scoped
// independently in `beautica_asset_icons.dart`, and merging them would mean
// one glob pattern trying to serve two different naming conventions.
//
// SCOPE: every asset backing an `svgIcon`/`svgActiveIcon` slot across the
// app's bottom-nav bars -- `SalonBottomNav.ownerAdminItems` (home, team) and
// `ClientBottomNav` (home, heart, note, passport) -- both outline and
// filled variants. `team_*` is the pair the defect actually hit; the other
// four are covered too because they make the identical solid-fill promise
// and a future asset drop on any of them would be just as invisible to the
// existing goldens (each golden photographs only the tab column it targets).
//
// COMMENT-STRIPPING GOTCHA (do not "simplify" this away): every asset in
// this set carries a provenance doc-comment as its first XML comment, and
// `team_outline.svg`'s own comment narrates the discarded defect in prose --
// it literally contains the substring `fill="none"` inside the sentence
// describing what was replaced. A raw `content.contains('fill="none"')`
// over the whole file text false-positives RED on the CURRENT, CORRECT file
// for that reason alone. This file strips XML comments before scanning so
// the contract is checked against actual markup, not provenance prose.
// Verified: without stripping, `team_outline.svg` fails the fill/stroke
// check today even though the glyph itself is solid-fill; category assets
// don't hit this because none of their comments happen to quote `fill="`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Strips `<!-- ... -->` XML comments so provenance prose (which may
/// legitimately narrate a past `fill="none"`/`stroke="..."` defect) can't
/// masquerade as, or mask, real markup attributes.
String _stripXmlComments(String svg) {
  return svg.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
}

void main() {
  const List<String> navIconBaseNames = <String>[
    'home_outline',
    'home_filled',
    'heart_outline',
    'heart_filled',
    'note_outline',
    'note_filled',
    'passport_outline',
    'passport_filled',
    'team_outline',
    'team_filled',
  ];

  final Directory iconsDir = Directory('assets/icons');

  test('every nav icon asset named above exists on disk', () {
    for (final String name in navIconBaseNames) {
      final File file = File('${iconsDir.path}/$name.svg');
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'nav bar registers $name.svg via BeauticaAssetIcons; the file '
            'is missing from assets/icons/',
      );
    }
  });

  group(
    'nav svgIcon/svgActiveIcon assets -- solid-fill structural contract',
    () {
      for (final String name in navIconBaseNames) {
        final File file = File('${iconsDir.path}/$name.svg');
        if (!file.existsSync()) {
          continue; // reported by the existence test above
        }
        final String rawContent = file.readAsStringSync();
        final String markup = _stripXmlComments(rawContent);

        test('$name.svg has viewBox="0 0 24 24"', () {
          expect(
            markup,
            contains('viewBox="0 0 24 24"'),
            reason:
                'nav bar renders every svgIcon/svgActiveIcon glyph at the '
                'same fixed logical size; a different viewBox scales this '
                'one glyph wrong relative to its neighbours in the bar',
          );
        });

        test('$name.svg has no fill="none" (outline-via-stroke) in its '
            'markup', () {
          expect(
            markup.contains('fill="none"'),
            isFalse,
            reason:
                'fill="none" makes the shape interior transparent so the '
                'icon renders as an outline instead of a solid glyph -- this '
                'is exactly the 2026-08-29 team_outline.svg defect class; '
                'checked against markup with XML comments stripped, so a '
                'provenance comment narrating a past defect cannot trip this',
          );
        });

        test('$name.svg has no stroke attribute in its markup', () {
          expect(
            markup.contains('stroke='),
            isFalse,
            reason:
                'every nav icon in this set is a solid-fill path with no '
                'stroke; a stroked derivative renders roughly 3x lighter '
                'than its solid-fill neighbours at real nav size (the '
                '2026-08-29 defect) -- checked against markup with XML '
                'comments stripped',
          );
        });
      }
    },
  );
}
