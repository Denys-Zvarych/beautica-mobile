// Phase 13.x / perf LOW-2 — Retained-page rendering across a re-key.
//
// WHY THIS FILE EXISTS
// --------------------
// Re-keying a search points `searchResultsProvider` at a family member with no
// cached value, so `.when(loading:)` fires. Returning a SKELETON there unmounts
// the whole rendered list: 20 neumorphic cards are thrown away and re-inflated,
// and — the bug users actually felt — the scroll offset snaps back to 0, so
// re-keying while halfway down the results teleports you to the top.
//
// THE RE-KEY TRIGGER
// ------------------
// Changing the SORT ordering, which is the only re-key path the results screen
// still owns: the live search field was removed from this screen, so free-text
// entry (and therefore a query re-key) happens on the FILTERS screen only, and
// arriving here is always a fresh mount rather than an in-place re-key. The
// retention mechanism itself is `_applyFilters`, shared by every trigger, so
// driving it through sort exercises exactly the code the query path used to.
//
// The fix is structural, not cosmetic: BOTH the `loading:` and the `data:`
// branch return the SAME widget type (`_ResultsView`), whose Stack child 0 is
// ALWAYS `_ResultsList`. `Widget.canUpdate` compares runtimeType and key, so an
// identical shape lets Flutter UPDATE the existing element instead of replacing
// it — which is what preserves the `ScrollPosition` and the inflated cards.
//
// That makes this a TYPE-IDENTITY contract, and a type mismatch is silent: the
// screen still renders, still shows the right data, and only the scroll offset
// quietly resets. So the assertions below are about ELEMENT IDENTITY and
// ScrollPosition IDENTITY, not about what is on screen. `the retained page
// renders the same ListView ELEMENT` is the one that fails if anyone swaps the
// loading branch back to a differently-shaped subtree.
//
// TEST SHAPE
// ----------
// The re-keyed fetch is held PENDING on a Completer, which is precisely the
// window the retained page exists to cover. `pumpAndSettle` cannot be used
// while it is pending — the retained branch renders an indeterminate
// `LinearProgressIndicator`, which never settles — so these use explicit
// `pump()`s.

import 'dart:async';

import 'package:beautica_mobile/features/discovery/data/search_repository.dart';
import 'package:beautica_mobile/features/discovery/data/search_repository_provider.dart';
import 'package:beautica_mobile/features/discovery/domain/master_search_item.dart';
import 'package:beautica_mobile/features/discovery/domain/salon_search_item.dart';
import 'package:beautica_mobile/features/discovery/domain/search_filters.dart';
import 'package:beautica_mobile/features/discovery/presentation/search_results_screen.dart';
import 'package:beautica_mobile/features/discovery/presentation/state/search_filters_controller.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/master_result_card.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/results_states.dart';
import 'package:beautica_mobile/features/favorites/application/favorite_toggle_notifier.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/overflow_guard.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

const Key _sortButton = Key('results_sort_button');
const Key _resultsList = Key('results_list');

/// The ordering picked to force a re-key (the seed is [SearchSort.ratingDesc],
/// and `_setSort` no-ops on an unchanged selection).
const SearchSort _newSort = SearchSort.priceAsc;

/// How far down the list the user is when the search is re-keyed.
const double _scrollOffset = 680;

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

MasterSearchItem _master(String id) => MasterSearchItem(
  masterId: id,
  firstName: 'Марія',
  lastName: 'Іванюк',
  avatarUrl: null,
  avgRating: 4.8,
  reviewCount: 12,
  cityLabel: 'Львів',
  districtLabel: 'Центр',
  minEffectivePrice: 600,
  priceMax: null,
  street: null,
  buildingNo: null,
  locationNote: null,
  serviceNames: const <String>[],
  servicesLine: null,
);

/// A repository whose FIRST page-0 fetch resolves immediately and whose SECOND
/// (the re-keyed one) stays pending until [releaseSecond] is called.
class _GatedSearchRepository implements SearchRepository {
  final Completer<void> _second = Completer<void>();
  int masterCalls = 0;

  void releaseSecond() {
    if (!_second.isCompleted) _second.complete();
  }

  @override
  Future<SearchPage<MasterSearchItem>> searchMasters({
    required SearchFilters filters,
    required int page,
    int size = kSearchPageSize,
    CancelToken? cancelToken,
  }) async {
    masterCalls++;
    if (masterCalls > 1) await _second.future;
    return SearchPage<MasterSearchItem>(
      items: <MasterSearchItem>[for (int i = 0; i < 20; i++) _master('m$i')],
      page: 0,
      totalPages: 1,
      totalElements: 20,
    );
  }

  @override
  Future<SearchPage<SalonSearchItem>> searchSalons({
    required SearchFilters filters,
    required int page,
    int size = kSearchPageSize,
    CancelToken? cancelToken,
  }) async {
    if (masterCalls > 1) await _second.future;
    return const SearchPage<SalonSearchItem>(
      items: <SalonSearchItem>[],
      page: 0,
      totalPages: 1,
      totalElements: 0,
    );
  }
}

class _SeededFiltersController extends SearchFiltersController {
  _SeededFiltersController(this._seed);

  final SearchFilters _seed;

  @override
  SearchFilters build() => _seed;
}

class _NoopFavoriteToggle extends FavoriteToggleNotifier {
  @override
  Map<FavoriteTarget, FavoriteEntry> build() =>
      const <FavoriteTarget, FavoriteEntry>{};
}

const List<LocalizationsDelegate<Object>> _delegates =
    <LocalizationsDelegate<Object>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ];

void main() {
  setUp(installOverflowGuard);

  Future<_GatedSearchRepository> pumpScreen(WidgetTester tester) async {
    final repo = _GatedSearchRepository();
    const SearchFilters seed = SearchFilters(query: 'манікюр');
    await tester.pumpWidget(
      ProviderScope(
        retry: beauticaProviderRetry,
        overrides: <Object>[
          searchRepositoryProvider.overrideWithValue(repo),
          searchFiltersControllerProvider.overrideWith(
            () => _SeededFiltersController(seed),
          ),
          favoriteToggleProvider.overrideWith(_NoopFavoriteToggle.new),
        ].cast(),
        child: const MaterialApp(
          localizationsDelegates: _delegates,
          supportedLocales: <Locale>[Locale('uk'), Locale('en')],
          locale: Locale('uk'),
          home: SearchResultsScreen(initialFilters: seed),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  ScrollableState listScrollable(WidgetTester tester) =>
      tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(_resultsList),
          matching: find.byType(Scrollable),
        ),
      );

  /// Scrolls the results list to [_scrollOffset] and returns the live position.
  Future<ScrollPosition> scrollDown(WidgetTester tester) async {
    listScrollable(tester).position.jumpTo(_scrollOffset);
    await tester.pump();
    return listScrollable(tester).position;
  }

  /// Picks a NEW sort ordering, WITHOUT settling afterwards — the re-keyed
  /// fetch is deliberately left pending, which is the window the retained page
  /// exists to cover.
  ///
  /// `pumpAndSettle` cannot follow the pick: the retained branch renders an
  /// indeterminate `LinearProgressIndicator` that never settles. The sheet's
  /// exit transition (after which `showModalBottomSheet`'s future resolves and
  /// `_setSort` re-keys) is therefore stepped across with bounded pumps.
  Future<void> reSort(WidgetTester tester) async {
    await tester.tap(find.byKey(_sortButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('sort_option_${_newSort.name}')));
    for (int i = 0; i < 20; i++) {
      // The retained page renders an indeterminate progress bar, so a
      // settle here would hang.
      // fixed-wait-ok: steps the modal sheet's exit transition instead.
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  group('a re-key keeps the outgoing page mounted', () {
    testWidgets('the retained page renders the same ListView ELEMENT', (
      tester,
    ) async {
      await pumpScreen(tester);
      await scrollDown(tester);

      final Element before = tester.element(find.byKey(_resultsList));

      await reSort(tester);

      expect(
        find.byKey(_resultsList),
        findsOneWidget,
        reason: 'the list must survive the re-key, not become a skeleton',
      );
      expect(
        identical(tester.element(find.byKey(_resultsList)), before),
        isTrue,
        reason:
            'a differently-shaped loading branch fails Widget.canUpdate, so '
            'Flutter REPLACES the element — taking the ScrollPosition and all '
            '20 inflated cards with it',
      );
    });

    testWidgets('the ScrollPosition object itself survives', (tester) async {
      await pumpScreen(tester);
      final ScrollPosition before = await scrollDown(tester);

      await reSort(tester);

      expect(
        identical(listScrollable(tester).position, before),
        isTrue,
        reason:
            'a new ScrollPosition means a new Scrollable — the offset would be '
            'rebuilt from scratch at 0',
      );
    });

    testWidgets('the scroll offset is preserved exactly', (tester) async {
      await pumpScreen(tester);
      await scrollDown(tester);
      expect(listScrollable(tester).position.pixels, _scrollOffset);

      await reSort(tester);

      expect(
        listScrollable(tester).position.pixels,
        _scrollOffset,
        reason:
            'THE user-visible bug: re-keying halfway down the results '
            'used to teleport back to the top',
      );
    });

    testWidgets('the inflated cards are NOT re-created', (tester) async {
      await pumpScreen(tester);
      await scrollDown(tester);

      // A card that is actually on screen at this offset.
      final Finder card = find.byType(MasterResultCard).first;
      final Element cardBefore = tester.element(card);

      await reSort(tester);

      expect(find.byType(MasterResultCard), findsWidgets);
      expect(
        identical(
          tester.element(find.byType(MasterResultCard).first),
          cardBefore,
        ),
        isTrue,
        reason:
            're-inflating 20 neumorphic cards on every re-key is the '
            'cost this retention exists to avoid',
      );
    });

    testWidgets('the retained page is marked as refreshing', (tester) async {
      await pumpScreen(tester);
      await scrollDown(tester);

      await reSort(tester);

      expect(
        find.byKey(const Key('results_refreshing_bar')),
        findsOneWidget,
        reason:
            'the user must still be told a new search is running — retention '
            'without the progress bar looks like a dead tap',
      );
    });

    testWidgets('the skeleton is NOT shown while a page is retained', (
      tester,
    ) async {
      await pumpScreen(tester);
      await scrollDown(tester);

      await reSort(tester);

      expect(
        find.byType(ResultsSkeleton),
        findsNothing,
        reason:
            'the skeleton is only for a FIRST search with nothing to retain',
      );
    });

    testWidgets('the incoming page replaces the retained one once it lands', (
      tester,
    ) async {
      final repo = await pumpScreen(tester);
      await scrollDown(tester);
      await reSort(tester);

      repo.releaseSecond();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('results_refreshing_bar')),
        findsNothing,
        reason: 'isolation control — retention must be transient, not sticky',
      );
      expect(find.byKey(_resultsList), findsOneWidget);
    });
  });

  group('first search has nothing to retain', () {
    testWidgets('a re-key with an EMPTY outgoing page falls back to the '
        'skeleton', (tester) async {
      // Not the retained path: with no rendered results there is nothing worth
      // holding on screen, so the skeleton is correct. Pins the
      // `retained.data.items.isEmpty` half of the loading-branch guard.
      final repo = _EmptyThenGatedRepository();
      const SearchFilters seed = SearchFilters(query: 'манікюр');
      await tester.pumpWidget(
        ProviderScope(
          retry: beauticaProviderRetry,
          overrides: <Object>[
            searchRepositoryProvider.overrideWithValue(repo),
            searchFiltersControllerProvider.overrideWith(
              () => _SeededFiltersController(seed),
            ),
            favoriteToggleProvider.overrideWith(_NoopFavoriteToggle.new),
          ].cast(),
          child: const MaterialApp(
            localizationsDelegates: _delegates,
            supportedLocales: <Locale>[Locale('uk'), Locale('en')],
            locale: Locale('uk'),
            home: SearchResultsScreen(initialFilters: seed),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await reSort(tester);

      expect(find.byType(ResultsSkeleton), findsOneWidget);
    });
  });
}

/// Page 0 resolves EMPTY; the re-keyed fetch hangs.
class _EmptyThenGatedRepository implements SearchRepository {
  final Completer<void> _second = Completer<void>();
  int calls = 0;

  @override
  Future<SearchPage<MasterSearchItem>> searchMasters({
    required SearchFilters filters,
    required int page,
    int size = kSearchPageSize,
    CancelToken? cancelToken,
  }) async {
    calls++;
    if (calls > 1) await _second.future;
    return const SearchPage<MasterSearchItem>(
      items: <MasterSearchItem>[],
      page: 0,
      totalPages: 1,
      totalElements: 0,
    );
  }

  @override
  Future<SearchPage<SalonSearchItem>> searchSalons({
    required SearchFilters filters,
    required int page,
    int size = kSearchPageSize,
    CancelToken? cancelToken,
  }) async {
    if (calls > 1) await _second.future;
    return const SearchPage<SalonSearchItem>(
      items: <SalonSearchItem>[],
      page: 0,
      totalPages: 1,
      totalElements: 0,
    );
  }
}
