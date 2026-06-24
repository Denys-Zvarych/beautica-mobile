// Phase 13.4 — Widget suite for [SearchResultsScreen] + the result cards.
//
// Layered on top of the dev's compile-and-mount smoke stub. Covers the four
// AsyncValue states (skeleton / cards / empty / error), the documented contract
// field-gaps (master ★rating + «від N грн» / «Без відгуків»; salon range /
// collapse / hide + NO rating), chip-clear re-query, infinite-scroll loadMore
// (bottom spinner, no double-fetch, last-page no-op), the optimistic favorite
// heart (flip / idempotent toggle / revert + snackbar on repo error / per-heart
// rebuild scope), and the card-tap nav intent (the 13.5/13.6 targets are not
// registered yet, so we assert the pushed route *constant*, not a destination
// screen).
//
// Pumping notes (mobile-backlog row 236): the screen is pumped under a plain
// `MaterialApp home:` (NOT `.router`) for the AsyncValue-state tests so the
// first error frame is captured with a single `pump()`. For the error state the
// mock throws a `StateError` (an Error, not an Exception) so the build() future
// surfaces a synchronous pure AsyncError instead of lingering in seamless
// AsyncLoading under Riverpod. The card-tap nav test uses a real `GoRouter`
// because asserting `context.push` needs a router.
//
// House rules honoured: ProviderScope is ALWAYS given overrides (fake search +
// fake favorite repos); finders are Key-based; UA copy is asserted via l10n
// lookups (never hardcoded strings).

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/discovery/data/search_repository.dart';
import 'package:beautica_mobile/features/discovery/data/search_repository_provider.dart';
import 'package:beautica_mobile/features/discovery/domain/master_search_item.dart';
import 'package:beautica_mobile/features/discovery/domain/salon_search_item.dart';
import 'package:beautica_mobile/features/discovery/domain/search_filters.dart';
import 'package:beautica_mobile/features/discovery/presentation/search_results_screen.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/applied_filters_row.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/master_result_card.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/salon_result_card.dart';
import 'package:beautica_mobile/features/discovery/presentation/state/search_filters_controller.dart';
import 'package:beautica_mobile/features/favorites/application/favorite_toggle_notifier.dart';
import 'package:beautica_mobile/features/favorites/data/favorite_repository.dart';
import 'package:beautica_mobile/features/favorites/data/favorite_repository_provider.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/overflow_guard.dart';

class _MockSearchRepository extends Mock implements SearchRepository {}

class _MockFavoriteRepository extends Mock implements FavoriteRepository {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

SearchPage<T> _page<T>(List<T> items, {int page = 0, int totalPages = 1}) =>
    SearchPage<T>(
      items: items,
      page: page,
      totalPages: totalPages,
      totalElements: items.length,
    );

MasterSearchItem _master(
  String id, {
  double? avgRating = 4.8,
  int? reviewCount = 12,
  double? minEffectivePrice = 600,
}) => MasterSearchItem(
  masterId: id,
  firstName: 'Марія',
  lastName: 'Іванюк',
  avatarUrl: null,
  avgRating: avgRating,
  reviewCount: reviewCount,
  cityLabel: 'Львів',
  districtLabel: 'Центр',
  minEffectivePrice: minEffectivePrice,
);

SalonSearchItem _salon(
  String id, {
  double? priceMin = 400,
  double? priceMax = 900,
}) => SalonSearchItem(
  salonId: id,
  name: 'Lviv Nails Studio',
  avatarUrl: null,
  avgRating: null,
  cityLabel: 'Львів',
  districtLabel: 'Центр',
  priceMin: priceMin,
  priceMax: priceMax,
);

const List<LocalizationsDelegate<Object?>> _delegates =
    <LocalizationsDelegate<Object?>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ];

const List<Locale> _locales = <Locale>[Locale('uk'), Locale('en')];

/// Plain `MaterialApp home:` host (single-pump error capture).
Widget _host(
  _MockSearchRepository repo, {
  _MockFavoriteRepository? favorites,
  SearchFilters filters = const SearchFilters(),
  List<Object> extraOverrides = const <Object>[],
}) {
  return ProviderScope(
    // ProviderScope.overrides expects List<Override>; the public name is not
    // exported by riverpod 2.x, so callers pass plain override expressions and
    // we cast (the same pattern as test/helpers/pump_app.dart).
    // ignore: avoid_dynamic_calls
    overrides: <Object>[
      searchRepositoryProvider.overrideWithValue(repo),
      if (favorites != null)
        favoriteRepositoryProvider.overrideWithValue(favorites),
      // Use the REAL toggle behaviour (optimistic flip + revert) but skip the
      // production build()'s ref.watch(authProvider) so the heart tests stay
      // auth-free and synchronous.
      favoriteToggleProvider.overrideWith(_AuthFreeFavoriteToggleNotifier.new),
      ...extraOverrides,
    ].cast(),
    child: MaterialApp(
      localizationsDelegates: _delegates,
      supportedLocales: _locales,
      locale: const Locale('uk'),
      home: SearchResultsScreen(initialFilters: filters),
    ),
  );
}

/// Resolves the active [AppLocalizations] from a pumped tree so assertions key
/// off the l10n value, never a hardcoded UA string.
AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(SearchResultsScreen)));

void main() {
  setUp(installOverflowGuard);

  setUpAll(() {
    registerFallbackValue(const SearchFilters());
    registerFallbackValue(
      const FavoriteTarget(type: FavoriteTargetType.master, id: 'fallback'),
    );
  });

  // -------------------------------------------------------------------------
  // 1 — the four AsyncValue states
  // -------------------------------------------------------------------------

  group('async states', () {
    testWidgets('shows the first-page skeleton while loading', (tester) async {
      final repo = _MockSearchRepository();
      final completer = Completer<SearchPage<MasterSearchItem>>();
      when(
        () => repo.searchMasters(filters: any(named: 'filters'), page: 0),
      ).thenAnswer((_) => completer.future);
      when(
        () => repo.searchSalons(filters: any(named: 'filters'), page: 0),
      ).thenAnswer((_) async => _page<SalonSearchItem>(const []));

      await tester.pumpWidget(_host(repo));
      await tester.pump();

      expect(find.byKey(const Key('results_skeleton')), findsOneWidget);
      completer.complete(_page<MasterSearchItem>(const []));
      await tester.pumpAndSettle();
    });

    testWidgets('renders master + salon cards on data', (tester) async {
      final repo = _MockSearchRepository();
      when(
        () => repo.searchMasters(filters: any(named: 'filters'), page: 0),
      ).thenAnswer((_) async => _page<MasterSearchItem>([_master('m1')]));
      when(
        () => repo.searchSalons(filters: any(named: 'filters'), page: 0),
      ).thenAnswer((_) async => _page<SalonSearchItem>([_salon('s1')]));

      await tester.pumpWidget(
        _host(repo, favorites: _MockFavoriteRepository()),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('results_list')), findsOneWidget);
      expect(find.byType(MasterResultCard), findsOneWidget);
      expect(find.byType(SalonResultCard), findsOneWidget);
      expect(find.byKey(const Key('favorite_master_m1')), findsOneWidget);
      expect(find.byKey(const Key('favorite_salon_s1')), findsOneWidget);
    });

    testWidgets('masters render before salons (merge order)', (tester) async {
      final repo = _MockSearchRepository();
      when(
        () => repo.searchMasters(filters: any(named: 'filters'), page: 0),
      ).thenAnswer((_) async => _page<MasterSearchItem>([_master('m1')]));
      when(
        () => repo.searchSalons(filters: any(named: 'filters'), page: 0),
      ).thenAnswer((_) async => _page<SalonSearchItem>([_salon('s1')]));

      await tester.pumpWidget(
        _host(repo, favorites: _MockFavoriteRepository()),
      );
      await tester.pumpAndSettle();

      final double masterY = tester
          .getTopLeft(find.byType(MasterResultCard))
          .dy;
      final double salonY = tester.getTopLeft(find.byType(SalonResultCard)).dy;
      expect(masterY, lessThan(salonY));
    });

    testWidgets('shows the empty state when no results match', (tester) async {
      final repo = _MockSearchRepository();
      when(
        () => repo.searchMasters(filters: any(named: 'filters'), page: 0),
      ).thenAnswer((_) async => _page<MasterSearchItem>(const []));
      when(
        () => repo.searchSalons(filters: any(named: 'filters'), page: 0),
      ).thenAnswer((_) async => _page<SalonSearchItem>(const []));

      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('results_empty')), findsOneWidget);
      expect(find.text(_l10n(tester).searchResultsEmptyTitle), findsOneWidget);
      expect(
        find.byKey(const Key('results_empty_edit_filters')),
        findsOneWidget,
      );
    });

    testWidgets('shows the error state + retry on failure', (tester) async {
      final repo = _MockSearchRepository();
      when(
        () => repo.searchMasters(filters: any(named: 'filters'), page: 0),
      ).thenThrow(StateError('boom'));
      when(
        () => repo.searchSalons(filters: any(named: 'filters'), page: 0),
      ).thenAnswer((_) async => _page<SalonSearchItem>(const []));

      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('results_error')), findsOneWidget);
      expect(find.byKey(const Key('results_error_retry')), findsOneWidget);
    });

    testWidgets('tapping retry re-queries both endpoints', (tester) async {
      final repo = _MockSearchRepository();
      var masterCalls = 0;
      when(
        () => repo.searchMasters(filters: any(named: 'filters'), page: 0),
      ).thenAnswer((_) async {
        masterCalls++;
        // Fail the first attempt, succeed on the retry.
        if (masterCalls == 1) throw StateError('boom');
        return _page<MasterSearchItem>([_master('m1')]);
      });
      when(
        () => repo.searchSalons(filters: any(named: 'filters'), page: 0),
      ).thenAnswer((_) async => _page<SalonSearchItem>(const []));

      await tester.pumpWidget(
        _host(repo, favorites: _MockFavoriteRepository()),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('results_error')), findsOneWidget);

      await tester.tap(find.byKey(const Key('results_error_retry')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('results_list')), findsOneWidget);
      expect(find.byKey(const Key('favorite_master_m1')), findsOneWidget);
      expect(masterCalls, 2);
    });
  });

  // -------------------------------------------------------------------------
  // 2 — card content + documented contract field-gaps
  // -------------------------------------------------------------------------

  group('card content', () {
    testWidgets('master card shows ★rating, «(N відгуків)» and «від N грн»', (
      tester,
    ) async {
      final repo = _MockSearchRepository();
      when(
        () => repo.searchMasters(filters: any(named: 'filters'), page: 0),
      ).thenAnswer(
        (_) async => _page<MasterSearchItem>([
          _master(
            'm1',
            avgRating: 4.8,
            reviewCount: 12,
            minEffectivePrice: 600,
          ),
        ]),
      );
      when(
        () => repo.searchSalons(filters: any(named: 'filters'), page: 0),
      ).thenAnswer((_) async => _page<SalonSearchItem>(const []));

      await tester.pumpWidget(
        _host(repo, favorites: _MockFavoriteRepository()),
      );
      await tester.pumpAndSettle();

      final l10n = _l10n(tester);
      expect(find.text('4.8'), findsOneWidget);
      expect(find.text(l10n.searchResultReviewCount(12)), findsOneWidget);
      expect(find.text(l10n.searchPriceFrom(600)), findsOneWidget);
      // Star icon present (the rating row renders it only when reviews exist).
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    });

    testWidgets('master card shows «Без відгуків» when reviewCount is 0', (
      tester,
    ) async {
      final repo = _MockSearchRepository();
      when(
        () => repo.searchMasters(filters: any(named: 'filters'), page: 0),
      ).thenAnswer(
        (_) async => _page<MasterSearchItem>([
          _master('m1', avgRating: 0, reviewCount: 0),
        ]),
      );
      when(
        () => repo.searchSalons(filters: any(named: 'filters'), page: 0),
      ).thenAnswer((_) async => _page<SalonSearchItem>(const []));

      await tester.pumpWidget(
        _host(repo, favorites: _MockFavoriteRepository()),
      );
      await tester.pumpAndSettle();

      expect(find.text(_l10n(tester).searchResultNoReviews), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsNothing);
    });

    testWidgets('salon card shows a price RANGE and NEVER a star rating', (
      tester,
    ) async {
      final repo = _MockSearchRepository();
      when(
        () => repo.searchMasters(filters: any(named: 'filters'), page: 0),
      ).thenAnswer((_) async => _page<MasterSearchItem>(const []));
      when(
        () => repo.searchSalons(filters: any(named: 'filters'), page: 0),
      ).thenAnswer(
        (_) async => _page<SalonSearchItem>([
          _salon('s1', priceMin: 400, priceMax: 900),
        ]),
      );

      await tester.pumpWidget(
        _host(repo, favorites: _MockFavoriteRepository()),
      );
      await tester.pumpAndSettle();

      final l10n = _l10n(tester);
      expect(find.text(l10n.searchResultPriceRange(400, 900)), findsOneWidget);
      // CONTRACT GAP: SalonSearchResult has no avgRating → no star ever.
      expect(find.byIcon(Icons.star_rounded), findsNothing);
    });

    testWidgets('salon card collapses an equal price band to «від N грн»', (
      tester,
    ) async {
      final repo = _MockSearchRepository();
      when(
        () => repo.searchMasters(filters: any(named: 'filters'), page: 0),
      ).thenAnswer((_) async => _page<MasterSearchItem>(const []));
      when(
        () => repo.searchSalons(filters: any(named: 'filters'), page: 0),
      ).thenAnswer(
        (_) async => _page<SalonSearchItem>([
          _salon('s1', priceMin: 500, priceMax: 500),
        ]),
      );

      await tester.pumpWidget(
        _host(repo, favorites: _MockFavoriteRepository()),
      );
      await tester.pumpAndSettle();

      final l10n = _l10n(tester);
      expect(find.text(l10n.searchPriceFrom(500)), findsOneWidget);
      expect(find.text(l10n.searchResultPriceRange(500, 500)), findsNothing);
    });

    testWidgets('salon card hides the price line when both bounds are null', (
      tester,
    ) async {
      final repo = _MockSearchRepository();
      when(
        () => repo.searchMasters(filters: any(named: 'filters'), page: 0),
      ).thenAnswer((_) async => _page<MasterSearchItem>(const []));
      when(
        () => repo.searchSalons(filters: any(named: 'filters'), page: 0),
      ).thenAnswer(
        (_) async => _page<SalonSearchItem>([
          _salon('s1', priceMin: null, priceMax: null),
        ]),
      );

      await tester.pumpWidget(
        _host(repo, favorites: _MockFavoriteRepository()),
      );
      await tester.pumpAndSettle();

      // The price text style is shared; assert no «грн» bearing price text by
      // confirming neither price variant rendered.
      final l10n = _l10n(tester);
      expect(find.text(l10n.searchPriceFrom(0)), findsNothing);
      expect(find.byType(SalonResultCard), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // 3 — chip-clear re-query
  // -------------------------------------------------------------------------

  group('applied filters chip', () {
    testWidgets('clearing the locality chip re-queries with cityId nulled', (
      tester,
    ) async {
      final repo = _MockSearchRepository();
      final List<SearchFilters> masterCallFilters = <SearchFilters>[];
      when(
        () => repo.searchMasters(filters: any(named: 'filters'), page: 0),
      ).thenAnswer((invocation) async {
        masterCallFilters.add(
          invocation.namedArguments[const Symbol('filters')] as SearchFilters,
        );
        return _page<MasterSearchItem>([_master('m1')]);
      });
      when(
        () => repo.searchSalons(filters: any(named: 'filters'), page: 0),
      ).thenAnswer((_) async => _page<SalonSearchItem>(const []));

      await tester.pumpWidget(
        _host(
          repo,
          favorites: _MockFavoriteRepository(),
          filters: const SearchFilters(cityId: 'city-1'),
          // Seed the label controller so the locality chip actually renders
          // (the chip row keys its specs off the display label, not the id).
          // Both filter controllers are overridden with auth-free test doubles
          // so the chip-clear path never pulls the real auth / secure-storage
          // stack (the production build()s ref.watch(authProvider)).
          extraOverrides: <Object>[
            searchFilterLabelsControllerProvider.overrideWith(
              () => _SeededLabelsController(
                const SearchFilterLabels(cityName: 'Львів'),
              ),
            ),
            searchFiltersControllerProvider.overrideWith(
              () => _SeededFiltersController(
                const SearchFilters(cityId: 'city-1'),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('applied_filters_row')), findsOneWidget);
      expect(
        find.byKey(Key('filter_chip_${AppliedFilterField.locality.name}')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(Key('filter_chip_${AppliedFilterField.locality.name}')),
      );
      await tester.pumpAndSettle();

      // A re-keyed family fetch fired with cityId cleared.
      expect(masterCallFilters.length, greaterThanOrEqualTo(2));
      expect(masterCallFilters.first.cityId, 'city-1');
      expect(masterCallFilters.last.cityId, isNull);
    });
  });

  // -------------------------------------------------------------------------
  // 4 — infinite scroll / loadMore
  // -------------------------------------------------------------------------

  group('loadMore', () {
    testWidgets('scrolling to the end fetches page 1 and appends it', (
      tester,
    ) async {
      final repo = _MockSearchRepository();
      // Page 0: a full page of masters (well past one viewport) with another
      // page available.
      when(
        () => repo.searchMasters(filters: any(named: 'filters'), page: 0),
      ).thenAnswer(
        (_) async => _page<MasterSearchItem>(
          List<MasterSearchItem>.generate(20, (i) => _master('m$i')),
          totalPages: 2,
        ),
      );
      when(
        () => repo.searchSalons(filters: any(named: 'filters'), page: 0),
      ).thenAnswer((_) async => _page<SalonSearchItem>(const []));
      // Page 1: the second master page (last page).
      when(
        () => repo.searchMasters(filters: any(named: 'filters'), page: 1),
      ).thenAnswer(
        (_) async => _page<MasterSearchItem>(
          <MasterSearchItem>[_master('m99')],
          page: 1,
          totalPages: 2,
        ),
      );

      await tester.pumpWidget(
        _host(repo, favorites: _MockFavoriteRepository()),
      );
      await tester.pumpAndSettle();

      // Page-1 has not been requested yet (only the first-page fetch fired).
      verifyNever(
        () => repo.searchMasters(filters: any(named: 'filters'), page: 1),
      );

      // Scroll to the end → the controller crosses the load-more threshold and
      // fires loadMore(). Jump the controller straight to the bottom so the
      // _onScroll listener fires deterministically (a single drag can fall
      // short of the threshold). Pump a few discrete frames (NOT
      // pumpAndSettle: the in-flight bottom CircularProgressIndicator animates
      // forever, so a settle would time out while it is briefly on screen).
      final ScrollableState scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('results_list')),
          matching: find.byType(Scrollable),
        ),
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      verify(
        () => repo.searchMasters(filters: any(named: 'filters'), page: 1),
      ).called(1);
      // Both endpoints are now spent → the trailing spinner slot is gone.
      expect(find.byKey(const Key('results_load_more_spinner')), findsNothing);
      // Page 1's row was appended to the model — re-jump to the (new) bottom
      // to bring the lazily-built m99 card into view and assert it rendered.
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump();
      expect(find.byKey(const Key('favorite_master_m99')), findsOneWidget);
    });

    testWidgets('a last-page list shows no load-more spinner', (tester) async {
      final repo = _MockSearchRepository();
      when(
        () => repo.searchMasters(filters: any(named: 'filters'), page: 0),
      ).thenAnswer(
        (_) async => _page<MasterSearchItem>([_master('m1')], totalPages: 1),
      );
      when(
        () => repo.searchSalons(filters: any(named: 'filters'), page: 0),
      ).thenAnswer((_) async => _page<SalonSearchItem>(const []));

      await tester.pumpWidget(
        _host(repo, favorites: _MockFavoriteRepository()),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('results_load_more_spinner')), findsNothing);
      // No page-1 fetch is ever issued on a single-page result.
      verifyNever(
        () => repo.searchMasters(filters: any(named: 'filters'), page: 1),
      );
    });
  });

  // -------------------------------------------------------------------------
  // 5 — favorite heart
  // -------------------------------------------------------------------------

  group('favorite heart', () {
    Future<void> pumpOneMaster(
      WidgetTester tester,
      _MockSearchRepository repo,
      _MockFavoriteRepository favorites,
    ) async {
      when(
        () => repo.searchMasters(filters: any(named: 'filters'), page: 0),
      ).thenAnswer((_) async => _page<MasterSearchItem>([_master('m1')]));
      when(
        () => repo.searchSalons(filters: any(named: 'filters'), page: 0),
      ).thenAnswer((_) async => _page<SalonSearchItem>(const []));
      await tester.pumpWidget(_host(repo, favorites: favorites));
      await tester.pumpAndSettle();
    }

    testWidgets('tapping the heart optimistically flips to filled', (
      tester,
    ) async {
      final repo = _MockSearchRepository();
      final favorites = _MockFavoriteRepository();
      when(() => favorites.add(any())).thenAnswer((_) async {});
      await pumpOneMaster(tester, repo, favorites);

      // Starts unfilled.
      expect(
        find.descendant(
          of: find.byKey(const Key('favorite_master_m1')),
          matching: find.byIcon(Icons.favorite_border_rounded),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('favorite_master_m1')));
      await tester.pump();

      // Optimistic flip is visible before the await settles.
      expect(
        find.descendant(
          of: find.byKey(const Key('favorite_master_m1')),
          matching: find.byIcon(Icons.favorite_rounded),
        ),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      verify(
        () => favorites.add(
          const FavoriteTarget(type: FavoriteTargetType.master, id: 'm1'),
        ),
      ).called(1);
    });

    testWidgets('a second tap removes (idempotent add→remove round-trip)', (
      tester,
    ) async {
      final repo = _MockSearchRepository();
      final favorites = _MockFavoriteRepository();
      when(() => favorites.add(any())).thenAnswer((_) async {});
      when(() => favorites.remove(any())).thenAnswer((_) async {});
      await pumpOneMaster(tester, repo, favorites);

      await tester.tap(find.byKey(const Key('favorite_master_m1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('favorite_master_m1')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('favorite_master_m1')),
          matching: find.byIcon(Icons.favorite_border_rounded),
        ),
        findsOneWidget,
      );
      verify(() => favorites.add(any())).called(1);
      verify(() => favorites.remove(any())).called(1);
    });

    testWidgets('a repo failure reverts the flag and shows a snackbar', (
      tester,
    ) async {
      final repo = _MockSearchRepository();
      final favorites = _MockFavoriteRepository();
      when(() => favorites.add(any())).thenThrow(const NetworkFailure());
      await pumpOneMaster(tester, repo, favorites);

      await tester.tap(find.byKey(const Key('favorite_master_m1')));
      await tester.pump(); // optimistic fill
      await tester.pumpAndSettle(); // add() rejects → revert + snackbar

      // Reverted to the outlined heart.
      expect(
        find.descendant(
          of: find.byKey(const Key('favorite_master_m1')),
          matching: find.byIcon(Icons.favorite_border_rounded),
        ),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('toggling one heart does not flip an unrelated card heart', (
      tester,
    ) async {
      final repo = _MockSearchRepository();
      final favorites = _MockFavoriteRepository();
      when(() => favorites.add(any())).thenAnswer((_) async {});
      when(
        () => repo.searchMasters(filters: any(named: 'filters'), page: 0),
      ).thenAnswer(
        (_) async => _page<MasterSearchItem>([_master('m1'), _master('m2')]),
      );
      when(
        () => repo.searchSalons(filters: any(named: 'filters'), page: 0),
      ).thenAnswer((_) async => _page<SalonSearchItem>(const []));
      await tester.pumpWidget(_host(repo, favorites: favorites));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('favorite_master_m1')));
      await tester.pumpAndSettle();

      // m1 is now filled, m2 untouched (per-target select scope).
      expect(
        find.descendant(
          of: find.byKey(const Key('favorite_master_m1')),
          matching: find.byIcon(Icons.favorite_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('favorite_master_m2')),
          matching: find.byIcon(Icons.favorite_border_rounded),
        ),
        findsOneWidget,
      );
    });
  });

  // -------------------------------------------------------------------------
  // 6 — card-tap nav intent (targets not registered yet)
  // -------------------------------------------------------------------------

  group('card nav', () {
    testWidgets('tapping a master card pushes /masters/{id}', (tester) async {
      final repo = _MockSearchRepository();
      when(
        () => repo.searchMasters(filters: any(named: 'filters'), page: 0),
      ).thenAnswer((_) async => _page<MasterSearchItem>([_master('m1')]));
      when(
        () => repo.searchSalons(filters: any(named: 'filters'), page: 0),
      ).thenAnswer((_) async => _page<SalonSearchItem>(const []));

      String? pushedLocation;
      final router = GoRouter(
        initialLocation: '/results',
        routes: <RouteBase>[
          GoRoute(
            path: '/results',
            builder: (_, _) =>
                const SearchResultsScreen(initialFilters: SearchFilters()),
          ),
          // Stand-in destination so the push resolves; records the location.
          GoRoute(
            path: '/masters/:id',
            builder: (BuildContext context, GoRouterState state) {
              pushedLocation = state.uri.toString();
              return const Scaffold(key: Key('master_profile_stub'));
            },
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          // ignore: avoid_dynamic_calls
          overrides: <Object>[
            searchRepositoryProvider.overrideWithValue(repo),
            favoriteRepositoryProvider.overrideWithValue(
              _MockFavoriteRepository(),
            ),
            favoriteToggleProvider.overrideWith(
              _AuthFreeFavoriteToggleNotifier.new,
            ),
          ].cast(),
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: _delegates,
            supportedLocales: _locales,
            locale: const Locale('uk'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the card body (not the heart) — the GestureDetector wraps the card.
      await tester.tap(find.byType(MasterResultCard));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('master_profile_stub')), findsOneWidget);
      expect(pushedLocation, '/masters/m1');
    });
  });
}

/// Test double for the keepAlive labels controller — seeds a fixed label set so
/// the applied-filters chip row renders its chips (the row keys its specs off
/// the display labels, not the raw filter ids). Overrides build() to skip the
/// production ref.watch(authProvider) so the test stays auth-free.
class _SeededLabelsController extends SearchFilterLabelsController {
  _SeededLabelsController(this._seed);

  final SearchFilterLabels _seed;

  @override
  SearchFilterLabels build() => _seed;
}

/// Test double for the keepAlive filters controller — seeds a fixed filter set
/// and skips the production ref.watch(authProvider). The chip-clear path reads
/// `.notifier` and calls selectCity(...), which mutates this double's state via
/// the inherited copyWith logic.
class _SeededFiltersController extends SearchFiltersController {
  _SeededFiltersController(this._seed);

  final SearchFilters _seed;

  @override
  SearchFilters build() => _seed;
}

/// Real [FavoriteToggleNotifier] behaviour with the auth-watch stripped from
/// build(). Inherits the production toggle/primeIfAbsent/_set logic (so the
/// optimistic-flip + revert path is genuinely exercised) but never touches the
/// auth / secure-storage stack the production build() depends on.
class _AuthFreeFavoriteToggleNotifier extends FavoriteToggleNotifier {
  @override
  Map<FavoriteTarget, FavoriteEntry> build() =>
      const <FavoriteTarget, FavoriteEntry>{};
}
