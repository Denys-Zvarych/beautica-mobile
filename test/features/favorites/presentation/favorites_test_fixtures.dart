// Phase 111 (mobile-qa) — shared harness + fixtures for the «Улюблені» widget
// tests.
//
// NOT a `_test.dart` file: it registers no tests and is imported by
// `favorites_screen_test.dart`, `favorites_row_reconciliation_test.dart` and
// `favorite_cards_test.dart`.
//
// Extracted because a `testWidgets` body over ~30 lines hides its own assertion
// intent, and because the three files must drive the screen through EXACTLY the
// same boot — a second, subtly different pump would let a fix pass in one file
// and rot in another.

import 'dart:async';

import 'package:beautica_mobile/features/favorites/application/favorites_notifier.dart';
import 'package:beautica_mobile/features/favorites/data/favorite_repository_provider.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_item.dart';
import 'package:beautica_mobile/features/favorites/presentation/favorites_screen.dart';
import 'package:beautica_mobile/features/favorites/presentation/widgets/favorite_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_favorite_repository.dart';
import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Item fixtures
// ---------------------------------------------------------------------------
//
// Names are LATIN on purpose. These are wire values, so they are identical in
// every locale — and keeping them out of the Cyrillic range means no assertion
// in this suite needs the `// i18n-finder-ok:` escape hatch that
// `scripts/forbid_cyrillic_finder.sh` requires. The one place a Cyrillic
// payload matters (the bidi-override note) is pinned in the MAPPER test, where
// no finder is involved at all.

FavoriteItem favMaster(
  String id, {
  String name = 'Marta Honchar',
  double? rating,
  String? salonName,
  String? categoryId,
  String? categoryLabel,
  String? cityLabel,
  String? districtLabel,
  String? street,
  String? buildingNo,
  String? locationNote,
}) => FavoriteItem(
  id: id,
  kind: FavoriteKind.master,
  name: name,
  initials: 'MH',
  rating: rating,
  salonName: salonName,
  categoryId: categoryId,
  categoryLabel: categoryLabel,
  cityLabel: cityLabel,
  districtLabel: districtLabel,
  street: street,
  buildingNo: buildingNo,
  locationNote: locationNote,
);

FavoriteItem favSalon(
  String id, {
  String name = 'Crystal Room',
  double? rating,
  String? categoryId,
  String? categoryLabel,
  String? cityLabel,
  String? districtLabel,
  String? street,
  String? buildingNo,
  String? locationNote,
}) => FavoriteItem(
  id: id,
  kind: FavoriteKind.salon,
  name: name,
  initials: 'CR',
  rating: rating,
  categoryId: categoryId,
  categoryLabel: categoryLabel,
  cityLabel: cityLabel,
  districtLabel: districtLabel,
  street: street,
  buildingNo: buildingNo,
  locationNote: locationNote,
);

// ---------------------------------------------------------------------------
// Preset category filter
// ---------------------------------------------------------------------------

class _PresetCategoryFilter extends FavoritesCategoryFilter {
  _PresetCategoryFilter(this._initial);

  final String? _initial;

  @override
  String? build() => _initial;
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// Boots [FavoritesScreen] inside a router context with a controllable fake
/// repository.
class FavoritesHarness {
  final FakeFavoriteRepository repo = FakeFavoriteRepository();

  late final GoRouter router;

  Completer<void>? _mastersGate;

  /// Blocks `getFavoriteMasters` so the LOADING state is observable.
  void blockMasters() {
    final Completer<void> gate = Completer<void>();
    _mastersGate = gate;
    repo.mastersDelay = gate.future;
  }

  void releaseMasters() {
    repo.mastersDelay = null;
    _mastersGate?.complete();
    _mastersGate = null;
  }

  /// Pumps the screen at `/` with two keyed probe leaves standing in for the
  /// public profiles a card tap pushes.
  Future<void> pump(WidgetTester tester, {String? selectedCategory}) async {
    router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext _, GoRouterState _) =>
              const Scaffold(body: SafeArea(child: FavoritesScreen())),
        ),
        GoRoute(
          path: '/masters/:masterId',
          builder: (BuildContext _, GoRouterState _) => const Scaffold(
            key: Key('probe-master-profile'),
            body: SizedBox.shrink(),
          ),
        ),
        GoRoute(
          path: '/salons/:salonId',
          builder: (BuildContext _, GoRouterState _) => const Scaffold(
            key: Key('probe-salon-profile'),
            body: SizedBox.shrink(),
          ),
        ),
      ],
    );

    await tester.pumpRoutedApp(
      router,
      overrides: <Object>[
        favoriteRepositoryProvider.overrideWithValue(repo),
        if (selectedCategory != null)
          favoritesCategoryFilterProvider.overrideWith(
            () => _PresetCategoryFilter(selectedCategory),
          ),
      ],
    );
  }

  /// The live [ProviderContainer] behind the pumped tree.
  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(FavoritesScreen)));

  /// Taps the unlike heart on ONE card, scoped by that card's own key.
  ///
  /// `UnlikeHeart` carries no `Key` of its own (pre-existing, flagged by
  /// mobile-dev). Scoping by the card key is precise — one heart per card — and
  /// keeps working unchanged the day a key is added. Its `AnimatedScale` is a
  /// DESCENDANT of the `GestureDetector`, not the widget root, so the hit test
  /// reaches the handler and `warnIfMissed` never has to be silenced.
  Future<void> tapHeart(WidgetTester tester, String cardKey) async {
    final Finder heart = find.descendant(
      of: find.byKey(Key(cardKey)),
      matching: find.byType(UnlikeHeart),
    );
    expect(heart, findsOneWidget, reason: 'no unlike heart inside $cardKey');
    await tester.tap(heart);
  }

  /// Advances past the 5 s undo window AND the 280 ms dent collapse.
  Future<void> settleUndoWindow(WidgetTester tester) async {
    // fixed-wait-ok: the undo window is a DECLARED 5 s `Timer` plus a 280 ms
    // collapse (`favorites_screen.dart:75,78`) — the duration is read off the
    // screen's own constants, not guessed. It cannot be a pump-until: several
    // tests here assert that NOTHING happens when the window elapses (a
    // cancelled timer must not fire a DELETE), so there is no widget to wait
    // for, and a pump-until would return instantly WITHOUT advancing the clock
    // — turning the assertion vacuous while leaving it green.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  }
}
