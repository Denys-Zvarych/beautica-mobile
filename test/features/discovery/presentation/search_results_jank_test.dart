// Phase 076 (10.2 jank audit) — pinning test for finding #6: an
// `isLoadingMore` flip (the scroll-threshold emission) must not rebuild every
// mounted result card when `data.items` content is unchanged.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/features/discovery/application/search_results_notifier.dart';
import 'package:beautica_mobile/features/discovery/data/search_repository.dart';
import 'package:beautica_mobile/features/discovery/data/search_repository_provider.dart';
import 'package:beautica_mobile/features/discovery/domain/master_search_item.dart';
import 'package:beautica_mobile/features/discovery/domain/salon_search_item.dart';
import 'package:beautica_mobile/features/discovery/domain/search_filters.dart';
import 'package:beautica_mobile/features/discovery/presentation/search_results_screen.dart';
import 'package:beautica_mobile/features/discovery/presentation/state/search_filters_controller.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/master_result_card.dart';
import 'package:beautica_mobile/features/favorites/application/favorite_toggle_notifier.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/overflow_guard.dart';

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

/// Page 0 resolves at once with `hasMore`; page 1 stays pending on [next].
class _PagedRepository implements SearchRepository {
  final Completer<SearchPage<MasterSearchItem>> next =
      Completer<SearchPage<MasterSearchItem>>();

  void completeNext() => next.complete(
    const SearchPage<MasterSearchItem>(
      items: <MasterSearchItem>[],
      page: 1,
      totalPages: 2,
      totalElements: 16,
    ),
  );

  @override
  Future<SearchPage<MasterSearchItem>> searchMasters({
    required SearchFilters filters,
    required int page,
    int size = kSearchPageSize,
    CancelToken? cancelToken,
  }) {
    if (page > 0) return next.future;
    return Future<SearchPage<MasterSearchItem>>.value(
      SearchPage<MasterSearchItem>(
        items: <MasterSearchItem>[for (int i = 0; i < 8; i++) _master('m$i')],
        page: 0,
        totalPages: 2,
        totalElements: 16,
      ),
    );
  }

  @override
  Future<SearchPage<SalonSearchItem>> searchSalons({
    required SearchFilters filters,
    required int page,
    int size = kSearchPageSize,
    CancelToken? cancelToken,
  }) async => const SearchPage<SalonSearchItem>(
    items: <SalonSearchItem>[],
    page: 0,
    totalPages: 1,
    totalElements: 0,
  );
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

/// Flips the flag in state with no repository round trip.
class _FlipFavoriteToggle extends FavoriteToggleNotifier {
  @override
  Map<FavoriteTarget, FavoriteEntry> build() =>
      const <FavoriteTarget, FavoriteEntry>{};

  @override
  Future<Failure?> toggle(
    FavoriteTarget target, {
    bool refreshWishlist = true,
  }) async {
    final bool now = state[target]?.isFavorite ?? false;
    state = <FavoriteTarget, FavoriteEntry>{
      ...state,
      target: FavoriteEntry(isFavorite: !now),
    };
    return null;
  }
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _PagedRepository repo,
  SearchFilters seed,
) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: beauticaProviderRetry,
      overrides: <Object>[
        searchRepositoryProvider.overrideWithValue(repo),
        searchFiltersControllerProvider.overrideWith(
          () => _SeededFiltersController(seed),
        ),
        favoriteToggleProvider.overrideWith(_FlipFavoriteToggle.new),
      ].cast(),
      child: MaterialApp(
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const <Locale>[Locale('uk'), Locale('en')],
        locale: const Locale('uk'),
        home: SearchResultsScreen(initialFilters: seed),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(installOverflowGuard);

  testWidgets('#6 — an isLoadingMore flip rebuilds no mounted result card', (
    tester,
  ) async {
    final repo = _PagedRepository();
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
          localizationsDelegates: <LocalizationsDelegate<Object>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: <Locale>[Locale('uk'), Locale('en')],
          locale: Locale('uk'),
          home: SearchResultsScreen(initialFilters: seed),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MasterResultCard), findsWidgets);

    int cardBuilds = 0;
    final RebuildDirtyWidgetCallback? old = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (Element e, bool builtOnce) {
      if (e.widget is MasterResultCard) cardBuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = old);

    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(SearchResultsScreen)),
    );
    unawaited(container.read(searchResultsProvider(seed).notifier).loadMore());
    await tester.pump();
    await tester.pump();
    expect(
      container.read(searchResultsProvider(seed)).value?.isLoadingMore,
      isTrue,
      reason: 'the flip must have happened or this pin is vacuous',
    );

    expect(cardBuilds, 0, reason: 'unchanged items must not rebuild cards');
    repo.completeNext();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'changing the filters clears the per-id card cache — every card is '
    'rebuilt with the NEW filters although the item content is unchanged',
    (tester) async {
      final repo = _PagedRepository();
      const SearchFilters seed = SearchFilters(query: 'манікюр');
      await _pumpScreen(tester, repo, seed);

      final Finder cards = find.byType(MasterResultCard);
      expect(cards, findsWidgets);
      expect(
        tester.widgetList<MasterResultCard>(cards).map((c) => c.activeFilters),
        everyElement(seed),
        reason: 'anti-vacuity: cards start on the seeded filters',
      );

      // Clearing the query chip re-keys the results with new filters; the fake
      // serves content-EQUAL items, so only the cache clear can refresh them.
      await tester.tap(find.byKey(const Key('results_query_chip')));
      await tester.pumpAndSettle();

      expect(cards, findsWidgets);
      expect(
        tester
            .widgetList<MasterResultCard>(cards)
            .map((c) => c.activeFilters?.query),
        everyElement(isNull),
        reason: 'a stale cached card would still carry query "манікюр"',
      );
    },
  );

  testWidgets(
    'a favourite toggle still updates the heart on a CACHED (not rebuilt) card',
    (tester) async {
      final repo = _PagedRepository();
      const SearchFilters seed = SearchFilters(query: 'манікюр');
      await _pumpScreen(tester, repo, seed);

      // Put the list into the cache-hit regime: an isLoadingMore flip.
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(SearchResultsScreen)),
      );
      unawaited(
        container.read(searchResultsProvider(seed).notifier).loadMore(),
      );
      await tester.pump();
      await tester.pump();

      final Finder heart = find.byKey(const Key('favorite_master_m0'));
      Finder icon(IconData d) =>
          find.descendant(of: heart, matching: find.byIcon(d));
      expect(icon(Icons.favorite_border_rounded), findsOneWidget);

      await tester.tap(heart);
      await tester.pump();

      expect(icon(Icons.favorite_rounded), findsOneWidget);
      expect(icon(Icons.favorite_border_rounded), findsNothing);
      repo.completeNext();
      await tester.pumpAndSettle();
    },
  );
}
