// Phase 111 (mobile-qa) — unit tests for [FavoriteItem]'s value equality.
//
// WHY THIS FILE EXISTS
// ---------------------
// No test anywhere in the suite constructed two `FavoriteItem`s and compared
// them directly. `favorite_item.dart`'s own `==` override comments explain,
// at length, why `listEquals(other.categories, categories)` is used instead
// of a bare `other.categories == categories` (a bare `List.==` is identity,
// which would silently break `_FavoritesScreenState._viewModelFor`'s
// memoisation the moment two distinct-but-equal lists were compared) — but
// the contract itself was unpinned.
//
// Mutation-confirmed (mobile-qa, 2026-08-25): replacing `listEquals(...)`
// with a bare `other.categories == categories` left the ENTIRE suite green
// (`test/features/favorites/` and
// `integration_test/client_favorites_flow_test.dart`). This is not a hole in
// coverage so much as a hole in the REACHABILITY of the bug in production:
// `FavoritesNotifier` always assigns a fresh `List` via
// `<FavoriteItem>[...current]` (see that file's header) and Riverpod's own
// state diff never gets far enough to hit `FavoriteItem.==` — a `List` has no
// `==` override of its own, so nothing on the current call path exercises the
// element-wise comparison this class promises. Pinned here directly against
// the class's own contract so a future caller that DOES rely on `==`
// (a `Set<FavoriteItem>`, a `distinct()` stream transformer, a future memo
// keyed on value rather than identity) does not inherit a silently-broken
// promise.

import 'package:beautica_mobile/features/favorites/domain/favorite_item.dart';
import 'package:flutter_test/flutter_test.dart';

FavoriteItem _item({
  String id = 'm1',
  List<FavoriteCategory> categories = const <FavoriteCategory>[],
}) => FavoriteItem(
  id: id,
  kind: FavoriteKind.master,
  name: 'Marta Honchar',
  initials: 'MH',
  categories: categories,
);

void main() {
  group('FavoriteItem.== — categories (deep equality, not identity)', () {
    test('two items built from DISTINCT-but-equal-by-VALUE category lists '
        'compare equal', () {
      final FavoriteItem a = _item(
        categories: const <FavoriteCategory>[
          FavoriteCategory(id: 'c1', label: 'Nails'),
        ],
      );
      final FavoriteItem b = _item(
        // A separately-constructed list — not the same List instance as
        // `a`'s, but element-wise identical. A bare `List.==` (identity)
        // would say these differ; `listEquals` must say they match.
        categories: <FavoriteCategory>[
          const FavoriteCategory(id: 'c1', label: 'Nails'),
        ],
      );

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('a genuinely different category list makes two items unequal', () {
      final FavoriteItem a = _item(
        categories: const <FavoriteCategory>[
          FavoriteCategory(id: 'c1', label: 'Nails'),
        ],
      );
      final FavoriteItem b = _item(
        categories: const <FavoriteCategory>[
          FavoriteCategory(id: 'c2', label: 'Brows'),
        ],
      );

      expect(a, isNot(equals(b)));
    });

    test('category ORDER is part of equality — [c1, c2] is not [c2, c1]', () {
      final FavoriteItem a = _item(
        categories: const <FavoriteCategory>[
          FavoriteCategory(id: 'c1', label: 'Nails'),
          FavoriteCategory(id: 'c2', label: 'Brows'),
        ],
      );
      final FavoriteItem b = _item(
        categories: const <FavoriteCategory>[
          FavoriteCategory(id: 'c2', label: 'Brows'),
          FavoriteCategory(id: 'c1', label: 'Nails'),
        ],
      );

      expect(a, isNot(equals(b)));
    });

    test('two items with no categories at all compare equal', () {
      expect(_item(), equals(_item()));
    });
  });
}
