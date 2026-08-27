// Phase 111 (mobile-qa) — focused unit tests for [FavoriteChoice.from].
//
// WHY THIS FILE EXISTS
// ---------------------
// `mobile-perf` flagged (INFO) that no dedicated test isolates the
// multi-category UNION — coverage lived only inside
// `favorites_screen_test.dart`'s wider "SEVERAL categories" assertions,
// where a second category always happened to coincide with some OTHER item's
// first (and only) category. That coincidence hides two real regressions:
//
//   1. `FavoriteChoice.from` reading only `item.categories.first` instead of
//      iterating the whole list — a provider's SECOND category still built a
//      chip in the wide test, contributed by a different item's first
//      category, not because the union actually walked past index 0.
//      Mutation-confirmed (mobile-qa, 2026-08-25): breaking `from` to read
//      only the first category left `favorites_screen_test.dart` AND
//      `integration_test/client_favorites_flow_test.dart`'s Test 8b fully
//      GREEN.
//   2. First-seen ORDER — sorting alphabetically instead of preserving
//      traversal order also stayed fully GREEN under the same probe: no test
//      anywhere asserted the chip LIST, only chip PRESENCE/absence and
//      filtering behaviour, which are order-blind.
//
// This file isolates the union from the widget tree entirely (pure Dart
// against `List<FavoriteItem>` → `List<FavoriteChoice>`), so both defects are
// pinned directly against the method that owns them rather than incidentally
// through the screen.
//
// Reuses `favMaster`/`favSalon` from `favorites_test_fixtures.dart`
// (REUSE-FIRST) rather than hand-building `FavoriteItem`s here.

import 'package:beautica_mobile/features/favorites/domain/favorite_item.dart';
import 'package:beautica_mobile/features/favorites/presentation/widgets/favorites_filter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'favorites_test_fixtures.dart';

void main() {
  group('FavoriteChoice.from — the union', () {
    test('a SINGLE item offering several categories contributes EVERY one of '
        'them, not just the first', () {
      // No other item exists to "accidentally" contribute the second
      // category as its own first — this is the case the wide screen test
      // cannot isolate.
      final List<FavoriteChoice> choices = FavoriteChoice.from(<FavoriteItem>[
        favMaster(
          'm1',
          categories: const <FavoriteCategory>[
            FavoriteCategory(id: 'c1', label: 'Nails'),
            FavoriteCategory(id: 'c2', label: 'Brows'),
          ],
        ),
      ]);

      expect(choices, const <FavoriteChoice>[
        FavoriteChoice(id: 'c1', label: 'Nails'),
        FavoriteChoice(id: 'c2', label: 'Brows'),
      ]);
    });

    test('an item with an empty categories list contributes nothing', () {
      expect(FavoriteChoice.from(<FavoriteItem>[favMaster('m1')]), isEmpty);
    });

    test('items with no categories at all yield an empty choice list', () {
      expect(FavoriteChoice.from(const <FavoriteItem>[]), isEmpty);
    });
  });

  group('FavoriteChoice.from — dedupe across items', () {
    test('the same category id repeated across items produces ONE chip, '
        'keeping the FIRST-seen label', () {
      final List<FavoriteChoice> choices = FavoriteChoice.from(<FavoriteItem>[
        favMaster('m1', categoryId: 'c1', categoryLabel: 'Nails'),
        favMaster('m2', categoryId: 'c1', categoryLabel: 'Manicure (dup)'),
      ]);

      expect(choices, const <FavoriteChoice>[
        FavoriteChoice(id: 'c1', label: 'Nails'),
      ]);
    });
  });

  group('FavoriteChoice.from — first-seen order (not alphabetical)', () {
    test('the chip order mirrors traversal order — item 0 then item 1 — even '
        'when that disagrees with alphabetical id order', () {
      // Alphabetically 'c1' < 'c3' < 'c9', but traversal meets them
      // c9, c1, c3. A `..sort()` on the id would reorder this and this
      // assertion would catch it; presence/absence checks would not.
      final List<FavoriteChoice> choices = FavoriteChoice.from(<FavoriteItem>[
        favMaster(
          'm1',
          categories: const <FavoriteCategory>[
            FavoriteCategory(id: 'c9', label: 'Lashes'),
            FavoriteCategory(id: 'c1', label: 'Nails'),
          ],
        ),
        favMaster('m2', categoryId: 'c3', categoryLabel: 'Brows'),
      ]);

      expect(choices.map((FavoriteChoice c) => c.id).toList(), <String>[
        'c9',
        'c1',
        'c3',
      ]);
    });

    test('a category re-seen on a LATER item does not move its position — '
        'first occurrence wins the slot', () {
      final List<FavoriteChoice> choices = FavoriteChoice.from(<FavoriteItem>[
        favMaster('m1', categoryId: 'c1', categoryLabel: 'Nails'),
        favMaster('m2', categoryId: 'c2', categoryLabel: 'Brows'),
        // Re-mentions c1 — must stay at index 0, not jump to index 2.
        favMaster('m3', categoryId: 'c1', categoryLabel: 'Nails'),
      ]);

      expect(choices.map((FavoriteChoice c) => c.id).toList(), <String>[
        'c1',
        'c2',
      ]);
    });
  });

  group('FavoriteChoice.from — cap on distinct categories (mobile-security '
      'finding 1)', () {
    test('never returns more than 50 distinct choices, even when the '
        'response claims more', () {
      // One item per distinct code — a hostile/buggy server response is not
      // required to concentrate every code on a single item's `categories`
      // list to defeat an unbounded union.
      final List<FavoriteItem> items = <FavoriteItem>[
        for (int i = 0; i < 80; i++)
          favMaster('m$i', categoryId: 'c$i', categoryLabel: 'Category $i'),
      ];

      final List<FavoriteChoice> choices = FavoriteChoice.from(items);

      expect(
        choices.length,
        lessThanOrEqualTo(50),
        reason:
            'FavoriteChoice.from must cap the rendered chip set — an '
            'unbounded union feeds an unconditional Wrap under an '
            'AnimatedSize (mobile-security finding 1, MEDIUM).',
      );
    });

    test('the cap does not disturb the currently-selected chip when it is '
        'within the first 50', () {
      final List<FavoriteItem> items = <FavoriteItem>[
        for (int i = 0; i < 60; i++)
          favMaster('m$i', categoryId: 'c$i', categoryLabel: 'Category $i'),
      ];

      final List<FavoriteChoice> choices = FavoriteChoice.from(items);

      expect(
        choices.any((FavoriteChoice c) => c.id == 'c0'),
        isTrue,
        reason: 'the first-seen categories must survive the cap',
      );
    });
  });
}
