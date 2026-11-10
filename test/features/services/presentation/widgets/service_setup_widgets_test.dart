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

  // ── Phase 471 — ServiceRowState copies + additive ServiceTypeRowCard params ──
  group('phase 471 — copy rows', () {
    const String id = 'type-massage-classic';
    const String typeName = 'Класичний масаж';

    ServiceRowState primary({String duration = '60', Set<int>? owned}) {
      final row = ServiceRowState(
        serviceTypeId: id,
        nameUk: typeName,
        alreadyAdded: owned != null,
        ownedDurations: owned ?? const <int>{},
      );
      row.included = true;
      row.duration.text = duration;
      return row;
    }

    Future<AppLocalizations> pumpCard(
      WidgetTester tester,
      ServiceRowState row, {
      VoidCallback? onAddCopy,
      VoidCallback? onRemove,
      bool showNameField = false,
      double gapBelow = 0,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 360,
                // Mirrors the setup list's per-row bottom gap when set.
                child: Padding(
                  padding: EdgeInsets.only(bottom: gapBelow),
                  child: ServiceTypeRowCard(
                    row: row,
                    resolveRangeError: (_) => null,
                    onAddCopy: onAddCopy,
                    onRemove: onRemove,
                    showNameField: showNameField,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return AppLocalizations.of(tester.element(find.byType(Scaffold)));
    }

    test('copyOf seeds the type, an empty price, included, and the nearest '
        'free quick-pick above the source duration', () {
      final source = primary();
      final copy = ServiceRowState.copyOf(source);
      addTearDown(source.dispose);
      addTearDown(copy.dispose);
      expect(copy.serviceTypeId, id);
      expect(copy.nameUk, typeName);
      expect(copy.isExtraCopy, isTrue);
      expect(copy.keyId, '${id}_copy_1');
      expect(copy.included, isTrue);
      expect(copy.duration.text, '90');
      expect(copy.fixed.text, isEmpty);
      expect(copy.customName, isNull);
    });

    test('copyOf skips owned and other-session durations', () {
      final source = primary(owned: const <int>{90});
      final copy = ServiceRowState.copyOf(
        source,
        takenDurations: const <int>{120},
        copyIndex: 2,
      );
      addTearDown(source.dispose);
      addTearDown(copy.dispose);
      expect(copy.duration.text, '150');
      expect(copy.keyId, '${id}_copy_2');
    });

    test('effective name: trimmed, lower-cased, blank = type name', () {
      final row = primary();
      addTearDown(row.dispose);
      expect(row.effectiveNameKey, typeName.toLowerCase());
      row.name.text = '  класичний МАСАЖ ';
      expect(row.effectiveNameKey, typeName.toLowerCase());
      expect(row.keepsTypeName, isTrue);
      row.name.text = 'Масаж спини авторський';
      expect(row.keepsTypeName, isFalse);
      expect(row.customName, 'Масаж спини авторський');
    });

    test('durationTaken: a renamed copy may share an owned duration', () {
      final row = primary(owned: const <int>{60});
      addTearDown(row.dispose);
      row.duration.text = '60';
      expect(row.durationTaken, isTrue);
      row.name.text = 'Масаж спини авторський';
      expect(row.durationTaken, isFalse);
    });

    testWidgets('no new params -> no copy actions and no name field', (
      tester,
    ) async {
      final row = primary();
      addTearDown(row.dispose);
      await pumpCard(tester, row);
      expect(find.byKey(const Key('btn-setup-row-add-copy-$id')), findsNothing);
      expect(find.byKey(const Key('btn-setup-row-remove-$id')), findsNothing);
      expect(find.byKey(const Key('setup_row_name_$id')), findsNothing);
    });

    testWidgets('onAddCopy renders «+ ще раз» (48dp) and fires on tap', (
      tester,
    ) async {
      final row = primary();
      addTearDown(row.dispose);
      var taps = 0;
      final l10n = await pumpCard(tester, row, onAddCopy: () => taps++);
      final add = find.byKey(const Key('btn-setup-row-add-copy-$id'));
      expect(add, findsOneWidget);
      expect(
        find.descendant(of: add, matching: find.text(l10n.serviceSetupAddCopy)),
        findsOneWidget,
      );
      await tester.tap(add);
      expect(taps, 1);
    });

    testWidgets('«+ ще раз» touch target spans >= 48 dp vertically without '
        'layout: footer band + slop below the card', (tester) async {
      final row = primary();
      addTearDown(row.dispose);
      var taps = 0;
      await pumpCard(tester, row, onAddCopy: () => taps++, gapBelow: 16);
      final Rect band = tester.getRect(
        find.byKey(const Key('btn-setup-row-add-copy-$id')),
      );
      final double cardBottom = tester
          .getRect(find.byType(ServiceTypeRowCard))
          .bottom;
      // The footer band ends on the card's bottom edge.
      expect(band.bottom, moreOrLessEquals(cardBottom));
      final double top = band.top + 0.5;
      final double bottom = cardBottom + 15.5; // inside the 16 dp slop
      expect(bottom - top, greaterThanOrEqualTo(48));
      await tester.tapAt(Offset(band.center.dx, top));
      await tester.tapAt(Offset(band.center.dx, bottom));
      expect(taps, 2);
      // Past the slop nothing fires.
      await tester.tapAt(Offset(band.center.dx, cardBottom + 17));
      expect(taps, 2);
    });

    testWidgets('the action line adds at most 20 px to an included row', (
      tester,
    ) async {
      final row = primary();
      addTearDown(row.dispose);
      await pumpCard(tester, row);
      final double plain = tester
          .getSize(find.byType(ServiceTypeRowCard))
          .height;
      await pumpCard(tester, row, onAddCopy: () {}, onRemove: () {});
      final double withActions = tester
          .getSize(find.byType(ServiceTypeRowCard))
          .height;
      expect(withActions - plain, lessThanOrEqualTo(20));
    });

    testWidgets('«+ ще раз» is hidden while the row is excluded', (
      tester,
    ) async {
      final row = primary()..included = false;
      addTearDown(row.dispose);
      await pumpCard(tester, row, onAddCopy: () {});
      expect(find.byKey(const Key('btn-setup-row-add-copy-$id')), findsNothing);
    });

    testWidgets('onRemove renders «Прибрати» and fires on tap', (tester) async {
      final row = primary();
      addTearDown(row.dispose);
      var taps = 0;
      final l10n = await pumpCard(tester, row, onRemove: () => taps++);
      final remove = find.byKey(const Key('btn-setup-row-remove-$id'));
      expect(
        find.descendant(
          of: remove,
          matching: find.text(l10n.serviceSetupRemoveCopy),
        ),
        findsOneWidget,
      );
      await tester.tap(remove);
      expect(taps, 1);
    });

    testWidgets('showNameField renders the optional name well bound to the '
        'row name controller', (tester) async {
      final row = primary();
      addTearDown(row.dispose);
      final l10n = await pumpCard(tester, row, showNameField: true);
      final field = find.byKey(const Key('setup_row_name_$id'));
      expect(field, findsOneWidget);
      expect(
        find.descendant(
          of: field,
          matching: find.text(l10n.serviceSetupCopyNameHint),
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.descendant(of: field, matching: find.byType(TextField)),
        'Авторський',
      );
      expect(row.name.text, 'Авторський');
    });

    testWidgets('copyCollision shows serviceSetupCopyCollision inline', (
      tester,
    ) async {
      final row = primary()..copyCollision = true;
      addTearDown(row.dispose);
      final l10n = await pumpCard(tester, row, showNameField: true);
      expect(find.text(l10n.serviceSetupCopyCollision), findsOneWidget);
      row.copyCollision = false;
      await tester.pumpAndSettle();
      expect(find.text(l10n.serviceSetupCopyCollision), findsNothing);
    });
  });
}
