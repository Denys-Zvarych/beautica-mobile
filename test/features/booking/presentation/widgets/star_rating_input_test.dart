// mobile-qa (fix/review-stars-fill-and-salon-card-price) — regression suite for
// [StarRatingInput], the leave-review 5-star input.
//
// Bug: a "filled" star rendered as an outline RING. `assets/icons/star.svg` was
// the Flaticon OUTLINE glyph (outer contour + an inner cut-out subpath), so
// tinting it `BrandColors.accent` only coloured a 1-2dp stroke; the star's
// middle stayed the ground colour. Every existing check read the `AppIcon.color`
// FIELD (accent vs faint), which was correct all along — they stayed green on
// the broken asset.
//
// So these tests read PIXELS: the colour at each star's centre. On the solid
// glyph a filled star's centre IS `accent` and an empty one's IS `faint`; on
// the outline glyph both centres are the ground colour. Plus a static pin on
// the asset itself (exactly one subpath) so the cut-out cannot come back.

import 'dart:io';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/star_rating_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/asset_star_finder.dart';
import '../../../../helpers/pixel_census.dart';
import '../../../../helpers/pump_app.dart';

const (int, int, int) _kFilled = (0xB8, 0x9A, 0x7A); // BrandColors.accent
const (int, int, int) _kEmpty = (0xBC, 0xAB, 0x95); // BrandColors.faint

Finder _star(int n) => find.byKey(ValueKey<String>('review-star-$n'));

/// Hosts the input with the rating owned by a parent, as the screen does.
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int _rating = 0;

  @override
  Widget build(BuildContext context) => StarRatingInput(
    rating: _rating,
    onChanged: (int v) => setState(() => _rating = v),
    labels: const <String>['l1', 'l2', 'l3', 'l4', 'l5'],
    prompt: 'prompt',
    semanticsLabel: 'rating',
  );
}

Future<void> _pump(WidgetTester tester) => tester.pumpApp(
  const RepaintBoundary(
    key: kCensusBoundary,
    child: ColoredBox(
      color: BrandColors.base,
      child: Center(child: _Host()),
    ),
  ),
  width: 400,
  height: 400,
);

/// The rendered centre colour of stars 1..5, in order.
Future<List<(int, int, int)>> _starCentres(WidgetTester tester) =>
    assetStarCentreColors(
      tester,
      find.descendant(
        of: find.byType(StarRatingInput),
        matching: findAssetStar(),
      ),
    );

void main() {
  testWidgets('tapping the 4th star paints stars 1-4 solid accent and star 5 '
      'faint', (WidgetTester tester) async {
    await _pump(tester);

    await tester.tap(_star(4));
    await tester.pumpAndSettle();

    expect(await _starCentres(tester), <(int, int, int)>[
      _kFilled,
      _kFilled,
      _kFilled,
      _kFilled,
      _kEmpty,
    ]);
  });

  testWidgets('tapping the 2nd star after the 4th leaves only stars 1-2 '
      'painted', (WidgetTester tester) async {
    await _pump(tester);
    await tester.tap(_star(4));
    await tester.pumpAndSettle();

    await tester.tap(_star(2));
    await tester.pumpAndSettle();

    expect(await _starCentres(tester), <(int, int, int)>[
      _kFilled,
      _kFilled,
      _kEmpty,
      _kEmpty,
      _kEmpty,
    ]);
  });

  test('assets/icons/star.svg is ONE solid subpath (no inner cut-out)', () {
    final String svg = File('assets/icons/star.svg').readAsStringSync();
    final List<RegExpMatch> paths = RegExp(
      r'<path\b[^>]*\sd="([^"]*)"',
    ).allMatches(svg).toList();

    expect(paths, hasLength(1), reason: 'exactly one <path> element');
    // Every subpath starts with a moveto (M/m); the outline glyph had two.
    expect(
      RegExp('[Mm]').allMatches(paths.single.group(1)!).length,
      1,
      reason: 'a second moveto is the inner cut-out that renders a ring',
    );
  });
}
