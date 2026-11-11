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
import 'package:beautica_mobile/features/services/domain/master_service.dart';
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
      VoidCallback? onChanged,
      ValueChanged<bool>? onFieldEdited,
      bool showNameField = false,
      double gapBelow = 0,
      bool offerCustomName = false,
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
                    onChanged: onChanged,
                    onFieldEdited: onFieldEdited,
                    showNameField: showNameField,
                    offerCustomName: offerCustomName,
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

    test('D4: copyOf seeds the type, included, an EMPTY duration and an '
        'empty price — no nearest-free duration seed', () {
      final source = primary();
      final copy = ServiceRowState.copyOf(source);
      addTearDown(source.dispose);
      addTearDown(copy.dispose);
      expect(copy.serviceTypeId, id);
      expect(copy.nameUk, typeName);
      expect(copy.isExtraCopy, isTrue);
      expect(copy.keyId, '${id}_copy_1');
      expect(copy.included, isTrue);
      expect(copy.duration.text, isEmpty);
      expect(copy.durationMinutes, isNull);
      expect(copy.fixed.text, isEmpty);
      expect(copy.customName, isNull);
    });

    test('D4: a copy of an owned type starts empty too', () {
      final source = primary(owned: const <int>{90});
      final copy = ServiceRowState.copyOf(source, copyIndex: 2);
      addTearDown(source.dispose);
      addTearDown(copy.dispose);
      expect(copy.duration.text, isEmpty);
      expect(copy.durationTaken, isFalse);
      expect(copy.keyId, '${id}_copy_2');
    });

    test('D4: text canonically equal to the type name is no custom name', () {
      final row = primary();
      addTearDown(row.dispose);
      row.name.text = typeName;
      expect(row.customName, isNull);
      expect(row.keepsTypeName, isTrue);
      // Space runs / full-width spaces fold away (serviceNameCanonical).
      row.name.text = ' Класичний\u3000 масаж ';
      expect(row.customName, isNull);
      // A case-only change IS a custom name (the stored name differs), but it
      // still compares as the type name in the duplicate rule.
      // i18n-finder-ok: user-typed service name fixture, not UI copy
      row.name.text = 'класичний масаж';
      // i18n-finder-ok: user-typed service name fixture, not UI copy
      expect(row.customName, 'класичний масаж');
      expect(row.keepsTypeName, isTrue);
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

    test('B6 (472): durationTaken compares each owned copy\'s canonical name '
        '— a renamed existing copy does not block a type-name row', () {
      MasterService svc(String name, int minutes) => MasterService(
        id: 'svc-$minutes',
        serviceDefId: 'def-$minutes',
        name: name,
        serviceTypeId: id,
        durationMinutes: minutes,
        priceMin: 500,
        priceDisplay: '500 ₴',
      );
      final row = ServiceRowState(
        serviceTypeId: id,
        nameUk: typeName,
        alreadyAdded: true,
        ownedDurations: const <int>{60, 90},
        ownedServices: <MasterService>[
          // i18n-finder-ok: fixture service name, not UI copy
          svc('Масаж спини авторський', 60),
          svc('', 90), // blank = the type name
        ],
      );
      addTearDown(row.dispose);
      row.included = true;
      row.duration.text = '60';
      expect(row.durationTaken, isFalse, reason: 'the 60-min copy is renamed');
      row.name.text = '  масаж   СПИНИ авторський ';
      expect(row.durationTaken, isTrue, reason: 'same canonical name at 60');
      row.name.text = '';
      row.duration.text = '90';
      expect(row.durationTaken, isTrue, reason: 'blank owned name = type name');
      final copy = ServiceRowState.copyOf(row);
      addTearDown(copy.dispose);
      expect(copy.ownedCopyKeys, row.ownedCopyKeys);
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

    testWidgets('onAddCopy renders «+ додати ще» (48dp) and fires on tap', (
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

    testWidgets('«+ додати ще» touch target spans >= 48 dp vertically without '
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

    testWidgets('«+ додати ще» is hidden while the row is excluded', (
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
      // D4: compact — no visible label; it stays the semantics label.
      expect(
        find.descendant(
          of: field,
          matching: find.text(l10n.serviceSetupCopyNameHint),
        ),
        findsNothing,
      );
      final semantics = tester.ensureSemantics();
      expect(
        tester
            .getSemantics(
              find.descendant(of: field, matching: find.byType(EditableText)),
            )
            .getSemanticsData()
            .label,
        contains(l10n.serviceSetupCopyNameHint),
      );
      semantics.dispose();
      // D4.3: the field takes the title's place — no second title line.
      expect(
        find.text(typeName).evaluate().length,
        find
            .descendant(of: field, matching: find.text(typeName))
            .evaluate()
            .length,
        reason: 'every title-text match is the field (its hint), not a title',
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

    test('durationMinutes / customName are cached from the controller TEXT '
        'and follow every text change', () {
      final row = ServiceRowState(
        serviceTypeId: id,
        nameUk: typeName,
        name: '  Авторський ',
      );
      addTearDown(row.dispose);
      expect(row.durationMinutes, isNull);
      expect(row.customName, 'Авторський');
      row.duration.text = ' 75 ';
      expect(row.durationMinutes, 75);
      row.duration.selection = const TextSelection.collapsed(offset: 0);
      expect(row.durationMinutes, 75);
      row.duration.text = 'x';
      expect(row.durationMinutes, isNull);
      row.name.text = '   ';
      expect(row.customName, isNull);
      expect(row.effectiveNameKey, typeName.toLowerCase());
    });

    testWidgets('onFieldEdited reports every real duration / name edit once '
        '(with the taken flip) and replaces onChanged for field edits; caret '
        'moves report nothing', (tester) async {
      final row = primary(duration: '45', owned: <int>{60});
      addTearDown(row.dispose);
      var changed = 0;
      final flips = <bool>[];
      await pumpCard(
        tester,
        row,
        showNameField: true,
        onChanged: () => changed++,
        onFieldEdited: flips.add,
      );

      row.duration.selection = const TextSelection.collapsed(offset: 0);
      row.name.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      expect(flips, isEmpty);

      row.duration.text = '60'; // owned → taken flips on
      row.name.text = 'Авторський'; // renamed → taken flips off
      row.name.text = 'Авторський 2'; // no flip
      await tester.pump();
      expect(flips, <bool>[true, true, false]);
      expect(changed, 0, reason: 'field edits go through onFieldEdited only');
    });

    const MasterService ownedSvc = MasterService(
      id: 'svc-owned',
      serviceDefId: 'def-owned',
      // i18n-finder-ok: fixture service name, not UI copy
      name: 'Масаж спини',
      serviceTypeId: id,
      durationMinutes: 60,
      priceMin: 500,
      priceDisplay: '500 ₴',
    );

    ServiceRowState ownedRow() => ServiceRowState(
      serviceTypeId: id,
      nameUk: typeName,
      alreadyAdded: true,
      ownedDurations: const <int>{60},
      ownedServices: const <MasterService>[ownedSvc],
    )..included = true;

    const Key pencilKey = Key('btn-setup-row-name-$id');
    const Key wellKey = Key('setup_row_name_$id');

    testWidgets('D3: an owned card shows its name with a pencil and only the '
        '«Вже додано» label — no list of existing services', (tester) async {
      final row = ownedRow();
      addTearDown(row.dispose);
      final l10n = await pumpCard(tester, row, offerCustomName: true);
      expect(find.byKey(pencilKey), findsOneWidget);
      expect(find.text(typeName), findsOneWidget);
      expect(find.text(l10n.serviceSetupRowAlreadyAdded), findsOneWidget);
      expect(find.text(ownedSvc.name), findsNothing);
      expect(find.byKey(const Key('setup_row_owned_svc-owned')), findsNothing);
      expect(find.byKey(wellKey), findsNothing);
    });

    testWidgets('D3: a switched-on not-owned card and a «+ додати ще» copy '
        'card each show their own pencil; an excluded card shows none', (
      tester,
    ) async {
      final row = primary();
      addTearDown(row.dispose);
      await pumpCard(tester, row, offerCustomName: true);
      expect(find.byKey(pencilKey), findsOneWidget);

      final copy = ServiceRowState.copyOf(row);
      addTearDown(copy.dispose);
      await pumpCard(tester, copy, offerCustomName: true);
      expect(
        find.byKey(const Key('btn-setup-row-name-${id}_copy_1')),
        findsOneWidget,
      );

      row.included = false;
      await pumpCard(tester, row, offerCustomName: true);
      expect(find.byKey(pencilKey), findsNothing);
    });

    testWidgets('D3: the pencil turns into the name well; the typed name is '
        'this card\'s custom name', (tester) async {
      final row = ownedRow();
      addTearDown(row.dispose);
      await pumpCard(tester, row, offerCustomName: true);
      await tester.tap(find.byKey(pencilKey));
      await tester.pumpAndSettle();
      expect(find.byKey(wellKey), findsOneWidget);
      expect(find.byKey(pencilKey), findsNothing, reason: 'well replaces it');
      expect(row.nameFieldOpen, isTrue);
      expect(row.nameFocus.hasFocus, isTrue);
      // D4: pre-filled with the type name as editable TEXT, caret at the end;
      // unchanged it is no custom name.
      expect(row.name.text, typeName);
      expect(
        row.name.selection,
        const TextSelection.collapsed(offset: typeName.length),
      );
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(wellKey),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        typeName,
      );
      expect(row.customName, isNull);
      expect(row.keepsTypeName, isTrue);
      await tester.enterText(
        find.descendant(
          of: find.byKey(wellKey),
          matching: find.byType(TextField),
        ),
        // i18n-finder-ok: user-typed service name fixture, not UI copy
        ' Масаж шиї ',
      );
      await tester.pump();
      // i18n-finder-ok: user-typed service name fixture, not UI copy
      expect(row.customName, 'Масаж шиї');
    });

    testWidgets('D4.3: the pencil swaps the title for the field in place — '
        'card size unchanged, title replaced not duplicated; focus loss '
        'returns title + pencil with the edited name', (tester) async {
      final row = ownedRow();
      addTearDown(row.dispose);
      await pumpCard(tester, row, offerCustomName: true);
      final Finder card = find.byType(ServiceTypeRowCard);
      final Size before = tester.getSize(card);
      final Rect title = tester.getRect(find.text(typeName));
      await tester.tap(find.byKey(pencilKey));
      await tester.pumpAndSettle();
      final Finder field = find.byKey(wellKey);
      expect(field, findsOneWidget);
      expect(tester.getSize(card), before, reason: 'card never resizes');
      final Rect fieldRect = tester.getRect(field);
      expect(fieldRect.top, moreOrLessEquals(title.top, epsilon: 0.5));
      expect(fieldRect.height, moreOrLessEquals(title.height, epsilon: 0.5));
      // The only title-text matches are inside the field (text + hint).
      expect(
        find.text(typeName).evaluate().length,
        find
            .descendant(of: field, matching: find.text(typeName))
            .evaluate()
            .length,
      );
      expect(find.byKey(pencilKey), findsNothing);
      await tester.enterText(
        find.descendant(of: field, matching: find.byType(TextField)),
        // i18n-finder-ok: user-typed service name fixture, not UI copy
        'Масаж шиї',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byKey(wellKey), findsNothing);
      expect(find.byKey(pencilKey), findsOneWidget);
      // i18n-finder-ok: user-typed service name fixture, not UI copy
      expect(find.text('Масаж шиї'), findsOneWidget);
      expect(tester.getSize(card), before);
      // i18n-finder-ok: user-typed service name fixture, not UI copy
      expect(row.customName, 'Масаж шиї');
    });

    test('D4: a pencil on a card that already has a custom name '
        'pre-fills that name', () {
      // i18n-finder-ok: user-typed service name fixture, not UI copy
      final row = ownedRow()..name.text = 'Масаж шиї';
      addTearDown(row.dispose);
      row.openNameField();
      // i18n-finder-ok: user-typed service name fixture, not UI copy
      expect(row.name.text, 'Масаж шиї');
    });

    testWidgets('D4: a pre-filled, unchanged name at an owned type-name '
        'duration is taken exactly like no name', (tester) async {
      const MasterService typeNamed = MasterService(
        id: 'svc-type',
        serviceDefId: 'def-type',
        name: '',
        serviceTypeId: id,
        durationMinutes: 60,
        priceMin: 500,
        priceDisplay: '500 ₴',
      );
      final row = ServiceRowState(
        serviceTypeId: id,
        nameUk: typeName,
        alreadyAdded: true,
        ownedDurations: const <int>{60},
        ownedServices: const <MasterService>[typeNamed],
      )..included = true;
      addTearDown(row.dispose);
      row.duration.text = '60';
      expect(row.durationTaken, isTrue);
      await pumpCard(tester, row, offerCustomName: true);
      await tester.tap(find.byKey(pencilKey));
      await tester.pumpAndSettle();
      expect(row.name.text, typeName);
      expect(row.customName, isNull);
      expect(row.durationTaken, isTrue, reason: 'unchanged = the type name');
      row.duration.text = '90';
      expect(row.durationTaken, isFalse, reason: 'not a type-name clash');
    });

    testWidgets('472 audit: the pencil touch target is >= 48x48 dp without '
        'growing the name line', (tester) async {
      for (final double dySign in <double>[-1, 1]) {
        final row = ownedRow();
        addTearDown(row.dispose);
        final l10n = await pumpCard(tester, row, offerCustomName: true);
        final Rect box = tester.getRect(find.byKey(pencilKey));
        final Rect name = tester.getRect(find.text(typeName));
        expect(box.width, greaterThanOrEqualTo(48));
        expect(
          box.height,
          lessThan(48),
          reason: 'the laid-out box keeps the text line height',
        );
        expect(box.height, lessThanOrEqualTo(name.height + 4));
        final Rect semantics = tester.getSemantics(find.byKey(pencilKey)).rect;
        expect(semantics.width, greaterThanOrEqualTo(48));
        expect(semantics.height, greaterThanOrEqualTo(48));
        expect(
          tester.getSemantics(find.byKey(pencilKey)).label,
          l10n.serviceSetupNameAction,
        );
        // A corner of the 48x48 target, outside the laid-out box.
        final Offset corner = Offset(
          dySign < 0 ? box.left + 1 : box.right - 1,
          box.center.dy + dySign * 23,
        );
        expect(box.contains(corner), isFalse);
        await tester.tapAt(corner);
        await tester.pumpAndSettle();
        expect(
          find.byKey(wellKey),
          findsOneWidget,
          reason: 'a tap ${dySign < 0 ? 'above' : 'below'} the glyph opens it',
        );
      }
    });

    testWidgets('472 audit: a tap past the 48 dp target does not open the '
        'name well', (tester) async {
      final row = ownedRow();
      addTearDown(row.dispose);
      await pumpCard(tester, row, offerCustomName: true);
      final Rect box = tester.getRect(find.byKey(pencilKey));
      await tester.tapAt(Offset(box.center.dx, box.center.dy + 26));
      await tester.pumpAndSettle();
      expect(find.byKey(wellKey), findsNothing);
    });

    testWidgets('472 audit: the name well drops the Hangul fillers the backend '
        'rejects', (tester) async {
      final row = ownedRow();
      addTearDown(row.dispose);
      await pumpCard(tester, row, offerCustomName: true);
      await tester.tap(find.byKey(pencilKey));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(wellKey),
          matching: find.byType(TextField),
        ),
        'АᅟБᅠВㅤГﾠД',
      );
      await tester.pump();
      expect(row.name.text, 'АБВГД');
    });

    testWidgets('D4 (QA): a type name with a character outside the allow-list '
        'is pre-filled filtered; left untouched it sends no name', (
      tester,
    ) async {
      // i18n-finder-ok: catalogue type-name fixture, not UI copy
      const String hashName = 'Масаж #1 спини';
      final row = ServiceRowState(serviceTypeId: id, nameUk: hashName)
        ..included = true;
      addTearDown(row.dispose);
      await pumpCard(tester, row, offerCustomName: true);
      await tester.tap(find.byKey(pencilKey));
      await tester.pumpAndSettle();

      // i18n-finder-ok: catalogue type-name fixture, not UI copy
      const String filtered = 'Масаж 1 спини';
      expect(row.name.text, filtered, reason: '«#» is not in the allow-list');
      expect(
        row.name.selection,
        const TextSelection.collapsed(offset: filtered.length),
      );
      expect(row.customName, isNull, reason: 'untouched pre-fill = no name');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(row.customName, isNull);
      expect(find.byKey(wellKey), findsNothing);
    });

    testWidgets('D4.3 (QA): a plain blur (focus moves to the duration well) '
        'closes the in-place field back to title + pencil', (tester) async {
      final row = ownedRow();
      addTearDown(row.dispose);
      await pumpCard(tester, row, offerCustomName: true);
      await tester.tap(find.byKey(pencilKey));
      await tester.pumpAndSettle();
      expect(row.nameFocus.hasFocus, isTrue);

      row.durationFocus.requestFocus();
      await tester.pumpAndSettle();

      expect(row.nameFieldOpen, isFalse);
      expect(find.byKey(wellKey), findsNothing);
      expect(find.byKey(pencilKey), findsOneWidget);
    });

    testWidgets('D4.3 (QA): a server name error keeps the in-place field open '
        'through a blur', (tester) async {
      final row = ownedRow();
      addTearDown(row.dispose);
      await pumpCard(tester, row, offerCustomName: true);
      await tester.tap(find.byKey(pencilKey));
      await tester.pumpAndSettle();
      // i18n-finder-ok: server error fixture, not UI copy
      row.serverNameError = 'Недопустимі символи';
      await tester.pump();

      row.durationFocus.requestFocus();
      await tester.pumpAndSettle();

      expect(find.byKey(wellKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(wellKey),
          // i18n-finder-ok: server error fixture, not UI copy
          matching: find.text('Недопустимі символи'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('D4.3 (QA): a closed card attaches no blur listener to the '
        'name focus node; opening the field does', (tester) async {
      final row = ownedRow();
      addTearDown(row.dispose);
      await pumpCard(tester, row, offerCustomName: true);
      // ignore: invalid_use_of_protected_member — test-only listener probe
      expect(row.nameFocus.hasListeners, isFalse);

      await tester.tap(find.byKey(pencilKey));
      await tester.pumpAndSettle();
      // ignore: invalid_use_of_protected_member — test-only listener probe
      expect(row.nameFocus.hasListeners, isTrue);
    });
  });
}
