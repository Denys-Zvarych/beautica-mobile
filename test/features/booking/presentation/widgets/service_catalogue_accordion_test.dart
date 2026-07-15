// Widget + unit tests for the shared catalogue accordion
// (`lib/features/booking/presentation/widgets/service_catalogue_accordion.dart`),
// extracted from `ServiceSelectorSheet` and `SalonServiceSelectionScreen`'s
// former hand-copied implementations. Pins:
//   1. `CatalogueSelectionController` — toggle / isSelected / selectedCountAmong
//      / replaceAll, as a pure unit test (no widget tree).
//   2. `CatalogueCategorySection` row rendering (name / duration / price).
//   3. Tapping a row calls `onToggleService` with the row's id and the depth
//      check control flips to its "selected" face.
//   4. Tapping the header calls `onToggleExpand`; rows only build while
//      `expanded` is true (mirrors both screens' controlled-expansion
//      pattern — the section never toggles its own `expanded` flag).
//   5. `showCountBadges` gates BOTH the row-count badge and the "N selected"
//      badge — even when a selection exists (mobile-qa audit: the original
//      pass only ever tested the false path with zero selected, which can't
//      distinguish "badge hidden" from "badge never had anything to show").
//   6. Multi-category independence: two `CatalogueCategorySection`s sharing
//      ONE `CatalogueSelectionController` — toggling a row in one category
//      must never select/badge a sibling category (mobile-qa audit: the
//      original pass only ever mounted a single category, so this section's
//      own `_computeSelectedInGroup` scoping contract, documented on
//      `_CatalogueCategorySectionState`, went completely unexercised).

import 'package:beautica_mobile/features/booking/presentation/widgets/service_catalogue_accordion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const CatalogueRow _rowA = CatalogueRow(
  id: 'row-a',
  name: 'Класичний манікюр',
  categoryLabel: 'MANICURE',
  durationLabel: '1 год',
  priceLabel: '300 ₴',
);

const CatalogueRow _rowB = CatalogueRow(
  id: 'row-b',
  name: 'Педикюр',
  categoryLabel: 'PEDICURE',
  durationLabel: '2 год',
  priceLabel: '800 ₴',
);

const CatalogueCategoryGroup _group = CatalogueCategoryGroup(
  key: 'MANICURE',
  label: 'Манікюр',
  rows: <CatalogueRow>[_rowA, _rowB],
);

const CatalogueRow _rowC = CatalogueRow(
  id: 'row-c',
  name: 'Стрижка',
  categoryLabel: 'HAIRCUT',
  durationLabel: '30 хв',
  priceLabel: '200 ₴',
);

const CatalogueRow _rowD = CatalogueRow(
  id: 'row-d',
  name: 'Укладка',
  categoryLabel: 'HAIRCUT',
  durationLabel: '20 хв',
  priceLabel: '150 ₴',
);

// Two rows (not one) so this group's own row-COUNT badge reads "2" rather
// than "1" — disambiguates it from the "1 selected" badge the independence
// test below must prove never leaks in from a sibling category.
const CatalogueCategoryGroup _groupB = CatalogueCategoryGroup(
  key: 'HAIRCUT',
  label: 'Стрижка',
  rows: <CatalogueRow>[_rowC, _rowD],
);

String _semantics({
  required String label,
  required int count,
  required int selectedCount,
  required bool expanded,
}) => 'sem:$label:$count:$selectedCount:$expanded';

Key _tileKeyForId(String id) => Key('tile_$id');

/// Owns the `expanded` flag + selection controller the same way the two
/// production screens do: `CatalogueCategorySection` never mutates its own
/// `expanded` prop, so a harness (mirroring
/// `_SalonServiceSelectionScreenState` / `_ServiceSelectorSheetState`) is
/// needed to exercise the expand/collapse round trip.
class _Harness extends StatefulWidget {
  const _Harness({
    required this.onToggleExpand,
    this.showCountBadges = true,
    this.initiallyExpanded = false,
  });

  final VoidCallback onToggleExpand;
  final bool showCountBadges;
  final bool initiallyExpanded;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late bool _expanded = widget.initiallyExpanded;
  final CatalogueSelectionController _controller =
      CatalogueSelectionController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CatalogueCategorySection(
        category: _group,
        expanded: _expanded,
        selectedIdsListenable: _controller,
        onToggleExpand: () {
          widget.onToggleExpand();
          setState(() => _expanded = !_expanded);
        },
        onToggleService: _controller.toggleService,
        headerSemanticsLabel: _semantics,
        tileKeyForId: _tileKeyForId,
        headerVerticalPadding: 12,
        headerKey: const Key('header'),
        showCountBadges: widget.showCountBadges,
      ),
    );
  }
}

/// Two sibling `CatalogueCategorySection`s sharing ONE
/// `CatalogueSelectionController`, both permanently expanded — mirrors how
/// `ServiceSelectorSheet`/`SalonServiceSelectionScreen` lay out a real
/// multi-category catalogue. Exercises the section's own
/// `_computeSelectedInGroup`/`_handleSelectionChanged` scoping contract
/// (documented on `_CatalogueCategorySectionState`): a toggle inside one
/// category's rows must never bleed into a sibling section's selected-count
/// badge or row check-state, since both sections listen to the SAME
/// controller and must each filter to their own `category.rows` only.
class _MultiGroupHarness extends StatefulWidget {
  const _MultiGroupHarness();

  @override
  State<_MultiGroupHarness> createState() => _MultiGroupHarnessState();
}

class _MultiGroupHarnessState extends State<_MultiGroupHarness> {
  final CatalogueSelectionController _controller =
      CatalogueSelectionController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: <Widget>[
          CatalogueCategorySection(
            key: const Key('section-a'),
            category: _group,
            expanded: true,
            selectedIdsListenable: _controller,
            onToggleExpand: () {},
            onToggleService: _controller.toggleService,
            headerSemanticsLabel: _semantics,
            tileKeyForId: _tileKeyForId,
            headerVerticalPadding: 12,
            headerKey: const Key('header-a'),
          ),
          CatalogueCategorySection(
            key: const Key('section-b'),
            category: _groupB,
            expanded: true,
            selectedIdsListenable: _controller,
            onToggleExpand: () {},
            onToggleService: _controller.toggleService,
            headerSemanticsLabel: _semantics,
            tileKeyForId: _tileKeyForId,
            headerVerticalPadding: 12,
            headerKey: const Key('header-b'),
          ),
        ],
      ),
    );
  }
}

void main() {
  group('CatalogueSelectionController', () {
    test('toggleService adds then removes an id', () {
      final controller = CatalogueSelectionController();
      addTearDown(controller.dispose);

      expect(controller.isSelected('svc-1'), isFalse);

      controller.toggleService('svc-1');
      expect(controller.isSelected('svc-1'), isTrue);
      expect(controller.value, <String>{'svc-1'});

      controller.toggleService('svc-1');
      expect(controller.isSelected('svc-1'), isFalse);
      expect(controller.value, isEmpty);
    });

    test('selectedCountAmong counts only the given ids', () {
      final controller = CatalogueSelectionController();
      addTearDown(controller.dispose);

      controller.toggleService('a');
      controller.toggleService('b');
      controller.toggleService('c');

      expect(controller.selectedCountAmong(<String>['a', 'b']), 2);
      expect(controller.selectedCountAmong(<String>['a', 'z']), 1);
      expect(controller.selectedCountAmong(<String>['x', 'y']), 0);
    });

    test('replaceAll swaps the whole selection set atomically', () {
      final controller = CatalogueSelectionController();
      addTearDown(controller.dispose);

      controller.toggleService('stale');
      controller.replaceAll(<String>{'fresh'});

      expect(controller.value, <String>{'fresh'});
      expect(controller.isSelected('stale'), isFalse);
    });
  });

  group('row rendering', () {
    testWidgets('shows each row\'s name, duration and price while expanded', (
      tester,
    ) async {
      await tester.pumpApp(
        _Harness(onToggleExpand: () {}, initiallyExpanded: true),
      );

      // `_rowA`/`_rowB`'s `name`/`durationLabel`/`priceLabel` are
      // hand-written fixture data above, not `AppLocalizations` copy —
      // `CatalogueRow.durationLabel`/`priceLabel` are documented
      // "pre-formatted ... always render as-is" and
      // `CatalogueCategorySection` echoes all three fields verbatim (no
      // internal formatting/locale lookup), so these literals are exactly
      // what the widget renders regardless of device locale.
      // i18n-finder-ok: see the fixture-data note above (`_rowA.name`).
      expect(find.text('Класичний манікюр'), findsOneWidget);
      // i18n-finder-ok: see the fixture-data note above (`_rowA.durationLabel`).
      expect(find.text('1 год'), findsOneWidget);
      // i18n-finder-ok: see the fixture-data note above (`_rowA.priceLabel`).
      expect(find.text('300 ₴'), findsOneWidget);

      // i18n-finder-ok: see the fixture-data note above (`_rowB.name`).
      expect(find.text('Педикюр'), findsOneWidget);
      // i18n-finder-ok: see the fixture-data note above (`_rowB.durationLabel`).
      expect(find.text('2 год'), findsOneWidget);
      // i18n-finder-ok: see the fixture-data note above (`_rowB.priceLabel`).
      expect(find.text('800 ₴'), findsOneWidget);
    });

    testWidgets('rows are absent while collapsed', (tester) async {
      await tester.pumpApp(_Harness(onToggleExpand: () {}));

      expect(find.byKey(const Key('tile_row-a')), findsNothing);
      expect(find.byKey(const Key('tile_row-b')), findsNothing);
    });
  });

  group('toggle', () {
    testWidgets(
      'tapping a row calls onToggleService with its id and flips the check '
      'control to the selected face',
      (tester) async {
        await tester.pumpApp(
          _Harness(onToggleExpand: () {}, initiallyExpanded: true),
        );

        expect(
          find.descendant(
            of: find.byKey(const Key('tile_row-a')),
            matching: find.byKey(const ValueKey<bool>(true)),
          ),
          findsNothing,
        );

        await tester.tap(find.byKey(const Key('tile_row-a')));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(const Key('tile_row-a')),
            matching: find.byKey(const ValueKey<bool>(true)),
          ),
          findsOneWidget,
        );
        // The untouched sibling row stays deselected.
        expect(
          find.descendant(
            of: find.byKey(const Key('tile_row-b')),
            matching: find.byKey(const ValueKey<bool>(true)),
          ),
          findsNothing,
        );
      },
    );
  });

  group('expand / collapse', () {
    testWidgets(
      'tapping the header calls onToggleExpand; rows only build while '
      'expanded is true',
      (tester) async {
        int calls = 0;
        await tester.pumpApp(_Harness(onToggleExpand: () => calls++));

        expect(find.byKey(const Key('tile_row-a')), findsNothing);

        await tester.tap(find.byKey(const Key('header')));
        await tester.pumpAndSettle();

        expect(calls, 1);
        expect(find.byKey(const Key('tile_row-a')), findsOneWidget);
        expect(find.byKey(const Key('tile_row-b')), findsOneWidget);

        await tester.tap(find.byKey(const Key('header')));
        await tester.pumpAndSettle();

        expect(calls, 2);
        expect(find.byKey(const Key('tile_row-a')), findsNothing);
      },
    );
  });

  group('showCountBadges', () {
    testWidgets('renders the row-count badge when true', (tester) async {
      await tester.pumpApp(
        _Harness(onToggleExpand: () {}, showCountBadges: true),
      );

      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('renders no count badge when false', (tester) async {
      await tester.pumpApp(
        _Harness(onToggleExpand: () {}, showCountBadges: false),
      );

      expect(find.text('2'), findsNothing);
    });

    testWidgets(
      'renders the "N selected" badge alongside the count badge when true '
      'and a row is selected',
      (tester) async {
        await tester.pumpApp(
          _Harness(
            onToggleExpand: () {},
            initiallyExpanded: true,
            showCountBadges: true,
          ),
        );

        await tester.tap(find.byKey(const Key('tile_row-a')));
        await tester.pumpAndSettle();

        // "1" — the selected-count badge; "2" — the total-count badge.
        expect(find.text('1'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
      },
    );

    testWidgets(
      'hides the "N selected" badge (as well as the count badge) when '
      'false, even with a row selected',
      (tester) async {
        await tester.pumpApp(
          _Harness(
            onToggleExpand: () {},
            initiallyExpanded: true,
            showCountBadges: false,
          ),
        );

        await tester.tap(find.byKey(const Key('tile_row-a')));
        await tester.pumpAndSettle();

        expect(find.text('1'), findsNothing);
        expect(find.text('2'), findsNothing);
      },
    );
  });

  group('multi-category independence', () {
    testWidgets('toggling a service in one category does not select or badge a '
        'sibling category listening to the same controller', (tester) async {
      await tester.pumpApp(const _MultiGroupHarness());

      await tester.tap(find.byKey(const Key('tile_row-a')));
      await tester.pumpAndSettle();

      // The toggled row itself flips selected...
      expect(
        find.descendant(
          of: find.byKey(const Key('tile_row-a')),
          matching: find.byKey(const ValueKey<bool>(true)),
        ),
        findsOneWidget,
      );
      // ...its own section's untouched sibling row stays deselected...
      expect(
        find.descendant(
          of: find.byKey(const Key('tile_row-b')),
          matching: find.byKey(const ValueKey<bool>(true)),
        ),
        findsNothing,
      );
      // ...and the UNRELATED category's row is completely untouched — a
      // regression that shares selection state across sections instead of
      // scoping to `category.rows` would flip this too.
      expect(
        find.descendant(
          of: find.byKey(const Key('tile_row-c')),
          matching: find.byKey(const ValueKey<bool>(true)),
        ),
        findsNothing,
      );
      // The sibling section's own header never renders a "selected" badge
      // for a selection that happened in a DIFFERENT category — this is
      // the assertion that would catch `_computeSelectedInGroup` leaking
      // the whole controller's selection instead of filtering to its own
      // group's row ids.
      expect(
        find.descendant(
          of: find.byKey(const Key('header-b')),
          matching: find.text('1'),
        ),
        findsNothing,
      );
    });
  });
}
