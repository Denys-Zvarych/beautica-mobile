// Search-query + filters SIMULTANEITY — E2E regression coverage.
//
// WHY THIS FILE EXISTS
// --------------------
// `client_search_flow_test.dart` proves the free-text query reaches the wire,
// and — in a SEPARATE test with its own fresh app + FakeBackend — that a picked
// city reaches the wire. Neither proves the two facets ride the SAME request
// alongside a category and a price bound. A query-handling bug that rebuilds the
// request and silently drops the other filters (or vice versa) passes both
// existing tests and still ships. This file drives ONE journey that sets all four
// facets and asserts them off a SINGLE captured query map per endpoint.
//
// Free text is entered in exactly ONE place — the Пошук screen's search box.
// The results screen hosts no field (it only echoes the applied term as a
// clearable chip), so the term this journey types is the term that must survive
// the push intact, alongside every other facet.
//
// PUMPING POLICY (measured — do not "simplify" back to pumpAndSettle)
// -------------------------------------------------------------------
// `pumpAndSettle` HANGS once the results screen is mounted: something in that
// subtree keeps the frame pipeline non-quiescent, so settling never completes and
// the test dies on its own timeout with `_pendingFrame == null`. Every wait after
// the CTA push therefore uses BOUNDED `pump(Duration)` calls via [settleResults].
// This is not the banned pump-as-sleep idiom — a bounded pump is the only
// deterministic way to advance a screen that never goes quiescent.
//
// PRICE BOUND: the slider drag sets `minPrice` (measured: 5500.0 for a -160 dx
// drag), NOT `maxPrice`. The assertions derive the expected bound from the filter
// set the screen actually received rather than hard-coding either the key or the
// number, so a change to the slider's geometry cannot make them vacuous.
//
// KEY POLICY: every interaction is key-based. No content assertions — this file
// asserts wire + state only.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/discovery/domain/search_filters.dart';
import 'package:beautica_mobile/features/discovery/presentation/search_results_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  /// Bounded replacement for `pumpAndSettle` on the results screen (see header).
  Future<void> settleResults(WidgetTester tester) async {
    for (int i = 0; i < 12; i++) {
      // pumpAndSettle HANGS here: the results-screen subtree keeps the frame
      // pipeline non-quiescent, so settling never completes (measured).
      // fixed-wait-ok: bounded step is the only way to advance this screen.
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// Reads the [SearchFilters] the results screen received via `extra`.
  SearchFilters receivedFilters(WidgetTester tester) {
    final SearchResultsScreen results = tester.widget<SearchResultsScreen>(
      find.byType(SearchResultsScreen),
    );
    final SearchFilters? filters = results.initialFilters;
    expect(
      filters,
      isNotNull,
      reason: 'the CTA must forward the assembled filter set via extra',
    );
    return filters!;
  }

  /// Scrolls [key] into view. The flutter-tester canvas is 800x600 landscape, so
  /// the category rail and price slider sit below the fold once the locality
  /// cascade is committed. FORWARD-ONLY: the outer ListView can unbuild a widget
  /// scrolled far outside its cache extent, so no target is ever revisited.
  Future<void> ensureVisibleByKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key), skipOffstage: false));
    await tester.pumpAndSettle();
  }

  /// Region («Київська») → City («Київ») through the REAL picker sheets. City is
  /// gated on Region; the seeded «Київ» has no districts.
  Future<void> pickRegionThenCity(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('search_region_value')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('locality_picker_tile_oblast-kyiv')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search_city_value')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('locality_picker_tile_city-kyiv')),
    );
    await tester.pumpAndSettle();
  }

  /// Assembles city + Cyrillic query + NAILS category + a price bound on the
  /// Пошук screen, then pushes the results screen via the CTA.
  ///
  /// The query is typed BEFORE any scrolling: it sits at the top of the fold and
  /// [ensureVisibleByKey] is forward-only. Ordering is a canvas concession — the
  /// screen submits nothing until the CTA tap.
  Future<void> assembleAndPush(
    WidgetTester tester, {
    required String term,
  }) async {
    await pickRegionThenCity(tester);

    await tester.enterText(find.byKey(const Key('search_query_field')), term);
    await tester.pumpAndSettle();

    await ensureVisibleByKey(tester, 'search_service_type_NAILS');
    await tester.tap(find.byKey(const Key('search_service_type_NAILS')));
    await tester.pumpAndSettle();

    await ensureVisibleByKey(tester, 'search_price_slider');
    await tester.drag(
      find.byKey(const Key('search_price_slider')),
      const Offset(-160, 0),
    );
    await tester.pumpAndSettle();

    // The CTA is a sticky footer OUTSIDE the scrollable body, so it needs no
    // ensureVisible regardless of how far the body is scrolled.
    await tester.tap(find.byKey(const Key('search_show_masters_cta')));
    await settleResults(tester);
  }

  /// Asserts every price bound the filter set carries reached [map] identically.
  void expectPriceBounds(
    Map<String, dynamic> map,
    SearchFilters filters,
    String endpoint,
  ) {
    expect(
      filters.minPrice != null || filters.maxPrice != null,
      isTrue,
      reason:
          'the slider drag must produce at least one finite bound, or the '
          'simultaneity assertion has nothing to check and passes vacuously',
    );
    if (filters.minPrice != null) {
      expect(
        map['minPrice'],
        filters.minPrice.toString(),
        reason:
            'the price floor must reach $endpoint as `minPrice` on the SAME '
            'request as the query — a bound silently dropped by a query change '
            'is the exact defect class this file exists to catch',
      );
    }
    if (filters.maxPrice != null) {
      expect(
        map['maxPrice'],
        filters.maxPrice.toString(),
        reason: 'the price ceiling must reach $endpoint on the SAME request',
      );
    }
  }

  /// The four-facet simultaneity assertion for one endpoint's captured query
  /// map. Everything is pulled from ONE map, so this proves the facets travelled
  /// TOGETHER rather than each having reached the wire at some point.
  void expectAllFacets(
    Map<String, dynamic>? map,
    SearchFilters filters, {
    required String endpoint,
    required String term,
  }) {
    expect(
      map,
      isNotNull,
      reason: 'the push must fire at least one $endpoint GET',
    );
    expect(
      map!['q'],
      term,
      reason:
          'the typed Cyrillic term must reach $endpoint as `q` on the SAME '
          'request that carries the other filters',
    );
    expect(
      map['location.cityId'],
      'city-kyiv',
      reason:
          'the picked city must reach $endpoint as a FLAT `location.cityId` on '
          'the SAME request as the query',
    );
    expect(
      map['category'],
      isNotNull,
      reason: 'the category must actually be set, not null on both sides',
    );
    expect(
      map['category'],
      filters.categoryKey,
      reason:
          'the selected category must reach $endpoint as the EXACT value the '
          'filter set carries, on the SAME request as the query',
    );
    expectPriceBounds(map, filters, endpoint);
  }

  testWidgets(
    'a Cyrillic term reaches BOTH endpoints together with city, category and '
    'price',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.client);
      // Real-async app boot: FakeBackend socket + secure storage + router
      // redirect, with no single settle condition to key a pump-until off.
      // fixed-wait-ok: real-async boot; no single pump-until condition exists.
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await tester.tap(find.byKey(const Key('client-nav-search-center')));
      // The shell-branch switch fans out to the real locality +
      // approved-category fetches before Пошук becomes interactive.
      // fixed-wait-ok: multi-endpoint fan-out precedes an interactive screen.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.clientSearch);

      await assembleAndPush(tester, term: 'манікюр');

      expect(
        find.byKey(const Key('client-search-results')),
        findsOneWidget,
        reason: 'the CTA must push the results screen with the filter set',
      );

      final SearchFilters filters = receivedFilters(tester);

      expectAllFacets(
        fb.lastSearchMastersQueryMap,
        filters,
        endpoint: '/search/masters',
        term: 'манікюр',
      );
      // /search/salons is a SEPARATE call the repository fires independently —
      // a distinct regression surface, not a duplicate of the block above.
      expectAllFacets(
        fb.lastSearchSalonsQueryMap,
        filters,
        endpoint: '/search/salons',
        term: 'манікюр',
      );

      expect(
        fb.getMasterCalls,
        0,
        reason:
            'the CLIENT search journey must not touch GET /masters/me '
            '(403 decoupling regression)',
      );
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
