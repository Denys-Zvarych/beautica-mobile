// Regression test for the category-icon contract on the service-setup chips
// and group headers.
//
// HISTORY: this file used to lock a UNIFORM glyph — `serviceCategoryIcon`
// returned the same `Icons.spa_rounded` constant for every category slug, on
// purpose, so a chip/header never rendered a distinct pictogram per category
// (the fix for an earlier bug where `MAKEUP` alone diverged to
// `Icons.palette_rounded`).
//
// SUPERSEDED 2026-08-27 (user instruction: "continue adding SVGs to missed
// places"). `serviceCategoryIcon` is deleted. `CategoryChip` and
// `CategoryGroupHeader` now take an `iconAsset` (nullable SVG asset path)
// resolved by the caller via the shared
// `categoryIconOrNullFor(categoryKey:, categoryName:)` resolver
// (`lib/core/icons/category_icons.dart` — its own resolution-table contract
// is covered by `test/core/icons/category_icons_test.dart`). This file now
// guards the WIDGET side of that contract instead: that a resolved asset
// renders as a real per-category `AppIcon`, that different categories render
// DIFFERENT assets (the uniform-glyph behaviour is gone), and that a null
// asset (uncategorised) renders no icon while still reserving its slot so
// labels stay aligned.

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/icons/category_icons.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_setup_widgets.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [child] under the localisation + Material scaffolding both
/// [CategoryChip] and [CategoryGroupHeader] need (`CategoryGroupHeader` reads
/// `AppLocalizations.of(context)` for the "n з m" count text), inside a fixed
/// width so a `Row`-based header doesn't hit unbounded-width layout.
Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(width: 340, child: Align(child: child)),
      ),
    ),
  );
}

void main() {
  group(
    'categoryIconOrNullFor resolves distinct assets (no more uniform glyph)',
    () {
      test('MAKEUP and HAIRDRESSING resolve to DIFFERENT assets', () {
        final String? makeup = categoryIconOrNullFor(categoryKey: 'MAKEUP');
        final String? hair = categoryIconOrNullFor(categoryKey: 'HAIRDRESSING');
        expect(makeup, isNotNull);
        expect(hair, isNotNull);
        expect(
          makeup,
          isNot(equals(hair)),
          reason:
              'the uniform-icon contract (every slug -> Icons.spa_rounded) is '
              'SUPERSEDED 2026-08-27 — categories must render distinct glyphs',
        );
        expect(makeup, equals(BeauticaAssetIcons.categoryMakeup));
        expect(hair, equals(BeauticaAssetIcons.categoryHairdressing));
      });

      test(
        'an unrecognised slug still resolves (non-null) via the cosmetology fallback',
        () {
          expect(
            categoryIconOrNullFor(categoryKey: 'UNKNOWN_SLUG'),
            equals(BeauticaAssetIcons.categoryCosmetology),
          );
        },
      );

      test(
        'null/blank categoryKey and categoryName resolve to null (uncategorised)',
        () {
          expect(categoryIconOrNullFor(), isNull);
          expect(categoryIconOrNullFor(categoryKey: ''), isNull);
          expect(categoryIconOrNullFor(categoryKey: '   '), isNull);
          expect(
            categoryIconOrNullFor(categoryKey: '', categoryName: ''),
            isNull,
          );
        },
      );
    },
  );

  group('CategoryChip renders the resolved category icon', () {
    testWidgets(
      'a real asset renders as AppIcon at the resolver-measured size',
      (tester) async {
        await _pump(
          tester,
          CategoryChip(
            key: const ValueKey<String>('chip'),
            iconAsset: BeauticaAssetIcons.categoryMakeup,
            label: 'Макіяж',
            selected: false,
            includedCount: 0,
            onTap: () {},
          ),
        );

        final appIconFinder = find.byType(AppIcon);
        expect(appIconFinder, findsOneWidget);
        final AppIcon rendered = tester.widget<AppIcon>(appIconFinder);
        expect(rendered.asset, equals(BeauticaAssetIcons.categoryMakeup));

        // Widget-field assertions are vacuous on their own (a constrained
        // parent can clobber a child's requested size and the constructor
        // field would still read correctly) — assert the LAID-OUT size too.
        final Size laidOut = tester.getSize(appIconFinder);
        expect(laidOut, equals(const Size(20, 20)));
      },
    );

    testWidgets(
      'a null iconAsset renders NO AppIcon but reserves the 20x20 slot',
      (tester) async {
        await _pump(
          tester,
          CategoryChip(
            key: const ValueKey<String>('chip-null'),
            iconAsset: null,
            label: 'Без категорії',
            selected: false,
            includedCount: 0,
            onTap: () {},
          ),
        );

        expect(find.byType(AppIcon), findsNothing);
        // The reserved slot is the leading SizedBox inside the chip's Row —
        // locate it by its exact 20x20 footprint so a future unrelated
        // SizedBox in the tree can't false-match.
        final sizedBoxes = tester
            .widgetList<SizedBox>(find.byType(SizedBox))
            .where((box) => box.width == 20 && box.height == 20);
        expect(
          sizedBoxes,
          isNotEmpty,
          reason:
              'a null-icon chip must still hold a 20x20 slot so labels '
              'across chips stay left-aligned',
        );
      },
    );

    testWidgets(
      'selected vs unselected chips render the SAME asset with different tints',
      (tester) async {
        await _pump(
          tester,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CategoryChip(
                key: const ValueKey<String>('unselected'),
                iconAsset: BeauticaAssetIcons.categoryNailService,
                label: 'Манікюр',
                selected: false,
                includedCount: 0,
                onTap: () {},
              ),
              CategoryChip(
                key: const ValueKey<String>('selected'),
                iconAsset: BeauticaAssetIcons.categoryNailService,
                label: 'Манікюр',
                selected: true,
                includedCount: 0,
                onTap: () {},
              ),
            ],
          ),
        );

        final List<AppIcon> icons = tester
            .widgetList<AppIcon>(find.byType(AppIcon))
            .toList(growable: false);
        expect(icons, hasLength(2));
        expect(icons[0].asset, equals(BeauticaAssetIcons.categoryNailService));
        expect(icons[1].asset, equals(BeauticaAssetIcons.categoryNailService));
      },
    );
  });

  group('CategoryGroupHeader renders the resolved category icon', () {
    testWidgets(
      'a real asset renders as AppIcon at the resolver-measured size',
      (tester) async {
        await _pump(
          tester,
          const CategoryGroupHeader(
            iconAsset: BeauticaAssetIcons.categoryLashExtensions,
            label: 'Вії',
            includedCount: 1,
            total: 3,
          ),
        );

        final appIconFinder = find.byType(AppIcon);
        expect(appIconFinder, findsOneWidget);
        final AppIcon rendered = tester.widget<AppIcon>(appIconFinder);
        expect(
          rendered.asset,
          equals(BeauticaAssetIcons.categoryLashExtensions),
        );
        expect(tester.getSize(appIconFinder), equals(const Size(20, 20)));
      },
    );

    testWidgets(
      'a null iconAsset renders NO AppIcon but reserves the 20x20 slot',
      (tester) async {
        await _pump(
          tester,
          const CategoryGroupHeader(
            iconAsset: null,
            label: 'Без категорії',
            includedCount: 0,
            total: 2,
          ),
        );

        expect(find.byType(AppIcon), findsNothing);
        final sizedBoxes = tester
            .widgetList<SizedBox>(find.byType(SizedBox))
            .where((box) => box.width == 20 && box.height == 20);
        expect(sizedBoxes, isNotEmpty);
      },
    );
  });
}
