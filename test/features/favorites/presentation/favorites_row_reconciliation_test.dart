// Phase 111 (mobile-qa) — the LIST RECONCILIATION pins.
//
// WHY THIS FILE EXISTS
// --------------------
// mobile-perf's finding on this chain, verbatim: "Delete the per-item key, the
// `findChildIndexCallback`, `_quantize`, or the `_refreshing` guard and all 16
// stay green. 'favourites 16' is not evidence of closure — my probes were."
// The `_refreshing` guard is pinned in `favorites_notifier_test.dart`; the other
// three are pinned here, and each test below names the exact deletion it goes
// red on.
//
// THE ASSERTIONS ARE BEHAVIOURAL, NOT STRUCTURAL. mobile-perf measured the
// defect as `MORPH_OCCURRED` via a `RenderAnimatedSize` probe; that is a
// diagnostic, not a durable assertion — it names an internal render object that
// a refactor may legitimately replace. What the CLIENT experiences is that
// every surviving row is already at its settled height on the very next frame,
// so that is what is asserted. It stays true under any implementation that
// actually fixes the bug, and false under any that does not.
//
// The row key's exact STRING is deliberately not asserted. mobile-dev is
// changing it to a composite `'${item.kind.name}-${item.id}'` in a concurrent
// pass, and a test pinned to a literal would be a merge conflict rather than a
// guarantee. What matters — the key exists, is a ValueKey, identifies the ITEM
// rather than the slot, and is unique per row — is asserted directly.

import 'package:beautica_mobile/features/favorites/application/favorites_notifier.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_item.dart';
import 'package:beautica_mobile/features/favorites/presentation/widgets/favorite_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'favorites_test_fixtures.dart';

/// Eight rows of ALTERNATING height — mobile-perf's own recipe.
///
/// The odd rows carry a two-line arrival note and are ~30dp taller than the
/// even ones. Uniform-height rows are what make this defect invisible: if every
/// row is the same height, handing slot 3 the next row's content produces no
/// size change and nothing animates. The alternation is the measuring
/// instrument, not decoration.
List<FavoriteItem> _alternatingRows(int count) => <FavoriteItem>[
  for (int i = 0; i < count; i++)
    favMaster(
      'm$i',
      name: 'Master $i',
      locationNote: i.isOdd
          ? 'A deliberately long arrival note that wraps onto a second '
                'rendered line so this row is measurably taller than its '
                'neighbours.'
          : null,
    ),
];

/// The reconciliation key of the row rendering master [id].
///
/// Read from the TREE, never hard-coded: the closest `KeyedSubtree` ancestor of
/// a card is the row wrapper `_rowsSliver` builds. Pinning the literal string
/// would make this a merge conflict with mobile-dev's concurrent change to a
/// composite `'${item.kind.name}-${item.id}'` form rather than a guarantee —
/// and the string is not what the sliver reconciles on. Identity and uniqueness
/// are.
String _rowKeyFor(WidgetTester tester, String id) {
  final Finder card = find.byKey(Key('favorites-master-$id'));
  expect(card, findsOneWidget, reason: 'no card rendered for $id');
  final Iterable<KeyedSubtree> ancestors = tester.widgetList<KeyedSubtree>(
    find.ancestor(of: card, matching: find.byType(KeyedSubtree)),
  );
  final KeyedSubtree? row = ancestors
      .where((KeyedSubtree w) => w.key is ValueKey<String>)
      .firstOrNull;
  expect(
    row,
    isNotNull,
    reason:
        'row $id has NO keyed wrapper at all — SliverChildBuilderDelegate '
        'reconciles by index without one, which is exactly the perf HIGH '
        'defect this file pins',
  );
  return (row!.key! as ValueKey<String>).value;
}

/// The rendered height of the SLOT holding master [id] — the `AnimatedSize`,
/// never the card inside it.
///
/// THIS DISTINCTION IS THE TEST. A first cut of this file measured the CARD
/// (`favorites-master-<id>`) and stayed GREEN with the per-item key deleted,
/// because the card is the `AnimatedSize`'s CHILD: a child always lays out at
/// its own intrinsic height, so it can never be caught mid-morph. It is the
/// wrapper that animates from the height the slot used to have to the height it
/// now needs, and therefore the wrapper that has to be measured. Caught by
/// mutation, not by review.
double? _slotHeight(WidgetTester tester, String id) {
  final Finder card = find.byKey(Key('favorites-master-$id'));
  if (card.evaluate().isEmpty) return null;
  final Finder slot = find
      .ancestor(of: card, matching: find.byType(AnimatedSize))
      .first;
  if (slot.evaluate().isEmpty) return null;
  return tester.getSize(slot).height;
}

Map<String, double> _rowHeights(WidgetTester tester, List<String> ids) {
  return <String, double>{
    for (final String id in ids)
      if (_slotHeight(tester, id) case final double h) id: h,
  };
}

void main() {
  group('FavoritesScreen rows — per-item key (perf HIGH pin)', () {
    testWidgets('every row carries a UNIQUE ValueKey derived from its ITEM', (
      WidgetTester tester,
    ) async {
      // RED WHEN the `KeyedSubtree(key: ValueKey<String>(...))` wrapper in
      // `favorites_screen.dart:437` is dropped: `SliverChildBuilderDelegate`
      // reconciles by INDEX unless the built child has a key.
      final FavoritesHarness h = FavoritesHarness()
        ..repo.masters = _alternatingRows(4);
      await h.pump(tester);
      await tester.pumpAndSettle();

      // The key STRING is read off the tree rather than hard-coded: the
      // closest `KeyedSubtree` ancestor of a card IS the row wrapper, whatever
      // its prefix happens to be this week.
      final List<String> rowKeys = <String>[
        for (int i = 0; i < 4; i++) _rowKeyFor(tester, 'm$i'),
      ];

      for (int i = 0; i < 4; i++) {
        expect(
          rowKeys[i],
          contains('m$i'),
          reason:
              'row $i is keyed on something other than its own item id — '
              'an index-derived key reconciles by SLOT, which is the defect',
        );
      }
      // No two rows collide, which is what makes reconciliation follow the
      // item instead of the slot.
      expect(rowKeys.toSet(), hasLength(4));
    });

    testWidgets('removing a row leaves every SURVIVOR at its settled height '
        'on the very next frame', (WidgetTester tester) async {
      // THE PIN. RED WHEN the `KeyedSubtree`/`ValueKey` at
      // `favorites_screen.dart:437` is removed.
      //
      // Unkeyed, `SliverChildBuilderDelegate` reconciles by index: after
      // removing row 0, slot 0 keeps the ELEMENT (and the `RenderAnimatedSize`
      // sitting at the old row's height) and is handed row 1's content — so it
      // animates from the height it had to the height it now needs, over the
      // 280 ms collapse, and every visible row below the removal does it at
      // once. mobile-perf measured slot 0 reading 40.07 against a 60.0 target.
      //
      // The assertion is the client-visible consequence: the height a survivor
      // shows on the FIRST frame after the removal must already equal the
      // height it settles at, and equal the height it had before.
      final FavoritesHarness h = FavoritesHarness()
        ..repo.masters = _alternatingRows(8);
      await h.pump(tester);
      await tester.pumpAndSettle();

      final List<String> survivors = <String>[
        for (int i = 1; i < 8; i++) 'm$i',
      ];
      final Map<String, double> before = _rowHeights(tester, survivors);
      // The fixture must actually alternate, or this test measures nothing.
      expect(
        before.values.toSet().length,
        greaterThan(1),
        reason:
            'the fixture rows are all the same height — a slot/content '
            'mismatch would produce no size change and this assertion would '
            'be vacuous',
      );

      final List<FavoriteItem> items = h
          .container(tester)
          .read(favoritesProvider)
          .value!;
      await h
          .container(tester)
          .read(favoritesProvider.notifier)
          .unfavorite(items.first);
      await tester.pump();

      final Map<String, double> immediate = _rowHeights(tester, survivors);
      await tester.pumpAndSettle();
      final Map<String, double> settled = _rowHeights(tester, survivors);

      // Only rows that were ALREADY laid out before the removal can be
      // compared: this is a lazy sliver, so a row that scrolled INTO the
      // viewport when the list shortened has no "before" height and its
      // absence is not a defect.
      final List<String> comparable = before.keys
          .where(immediate.containsKey)
          .toList(growable: false);
      expect(
        comparable.length,
        greaterThanOrEqualTo(2),
        reason:
            'fewer than two survivors were laid out both before and after '
            'the removal — this assertion would be near-vacuous',
      );
      expect(
        comparable.map((String id) => before[id]).toSet().length,
        greaterThan(1),
        reason:
            'every comparable survivor has the same height, so a '
            'slot/content mismatch would be invisible here',
      );

      for (final String id in comparable) {
        expect(
          immediate[id],
          settled[id],
          reason:
              'row $id was mid-morph one frame after the removal — the '
              'per-item ValueKey is missing, so the sliver reconciled by '
              'index and handed this slot another row\'s content',
        );
        expect(
          immediate[id],
          before[id],
          reason: 'row $id changed height because of a removal ABOVE it',
        );
      }
    });

    testWidgets('a surviving row keeps its ELEMENT across a removal', (
      WidgetTester tester,
    ) async {
      // The other half of the same contract, and the half a height assertion
      // cannot see: reconciliation must FOLLOW the item, so the row that moved
      // from index 2 to index 1 keeps the State it already had rather than
      // being torn down and rebuilt.
      //
      // `UnlikeHeart` is the probe because it is the only PUBLIC StatefulWidget
      // inside a row; its State identity is destroyed by a rebuild and
      // preserved by a move.
      final FavoritesHarness h = FavoritesHarness()
        ..repo.masters = _alternatingRows(6);
      await h.pump(tester);
      await tester.pumpAndSettle();

      State<StatefulWidget> heartState(String id) => tester.state(
        find.descendant(
          of: find.byKey(Key('favorites-master-$id')),
          matching: find.byType(UnlikeHeart),
        ),
      );

      final State<StatefulWidget> beforeState = heartState('m3');

      final List<FavoriteItem> items = h
          .container(tester)
          .read(favoritesProvider)
          .value!;
      await h
          .container(tester)
          .read(favoritesProvider.notifier)
          .unfavorite(items.first);
      await tester.pumpAndSettle();

      expect(
        identical(heartState('m3'), beforeState),
        isTrue,
        reason:
            'row m3 was rebuilt rather than moved — the keyed child was '
            'not located at its new index',
      );
    });
  });

  group('FavoritesScreen rows — reveal-interval quantization (perf MEDIUM)', () {
    testWidgets('draining a 40-row list one row at a time stays inside the '
        'StaggeredReveal cache budget', (WidgetTester tester) async {
      // RED WHEN `_quantize` (`favorites_screen.dart:306`) is removed, or when
      // either of its two call sites at :434/:441 stops using it.
      //
      // `_stepFor` derives each row's reveal `start` from the list LENGTH, so
      // an UNQUANTIZED interval mints a fresh `(start, end)` cache key on every
      // single removal. `StaggeredReveal._revealCache` is `putIfAbsent`-only,
      // each entry holds a status listener on the controller, and this screen
      // is a `StatefulShellRoute.indexedStack` branch that is never disposed
      // for the whole session — so it is an unbounded listener leak.
      // mobile-perf measured 486 cached `CurvedAnimation`s for 40 live rows.
      //
      // The debug assert at `staggered_reveal.dart:187` trips at 96 entries.
      // This test is the caller that reaches it: it drains the list through the
      // NOTIFIER (not the 5 s undo window), so 40 successive list lengths are
      // rendered in one test.
      final FavoritesHarness h = FavoritesHarness()
        ..repo.masters = <FavoriteItem>[
          for (int i = 0; i < 40; i++) favMaster('m$i', name: 'Master $i'),
        ];
      await h.pump(tester);
      await tester.pumpAndSettle();

      final Favorites notifier = h
          .container(tester)
          .read(favoritesProvider.notifier);

      for (int i = 0; i < 40; i++) {
        final List<FavoriteItem> items = h
            .container(tester)
            .read(favoritesProvider)
            .value!;
        expect(items, hasLength(40 - i));
        await notifier.unfavorite(items.first);
        // One frame per removal, so every distinct list length is actually
        // BUILT — batching the removals would collapse 40 interval sets into
        // one and the leak would never be exercised.
        await tester.pump();
      }

      await tester.pumpAndSettle();
      expect(h.container(tester).read(favoritesProvider).value, isEmpty);
      // Reaching here without an AssertionError from
      // `staggered_reveal.dart:187` IS the assertion.
    });
  });
}
