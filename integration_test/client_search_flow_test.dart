// Phase 13.3 — E2E: CLIENT Пошук (Search) filter → results-handoff journey.
//
// WHY THIS FILE EXISTS
// --------------------
// The widget tier (test/features/discovery/presentation/search_filters_screen_test.dart)
// proves ClientSearchScreen in isolation, and the controller tier proves the
// SearchFilters state machine. Neither exercises the REAL journey: a CLIENT
// logging in, tapping the elevated center «Пошук» nav disc to reach the real
// ClientSearchScreen branch, picking a city through the REAL locality picker
// cascade, selecting a category in the Variant A rail (which reveals the
// second-level service-chip drawer), dragging the price slider, and tapping
// «Показати майстрів» to push /search/results with the assembled SearchFilters
// in `extra`.
//
// VARIANT A («Рейка + послуги») COVERAGE: the rail tile reveals a service-chip
// drawer sourced from the REAL async categoryServiceOptionsProvider →
// CategoryServiceRepository → `GET /api/v1/service-types?categoryName=NAILS`
// (served by the fake backend). The fake's NAILS slice is a single
// PlatformServiceTypeResponse { slug: CLASSIC_MANICURE, nameUk: «Класичний
// манікюр» }, so the drawer renders one keyed chip whose key is
// `search_service_chip_CLASSIC_MANICURE` (chip key = `option.key` = slug). This
// exercises the real repository→provider→drawer path end to end. The selected
// service set is still INERT (SearchFilters has no service-key field — future
// wiring), so the E2E asserts what is rendered/carried and does NOT assert a
// service key on the filters.
//
// This boots the REAL app via AppHarness (FakeBackend socket, FakeSecureStorage,
// fixed clock, overflow guard) and drives the whole flow against the fake
// backend's seeded taxonomy:
//   • GET /service-categories/approved → NAILS («Нігті») + BROWS («Брови»)
//   • GET /locations/oblasts → «Київська» (oblast-kyiv)
//   • GET /locations/oblasts/oblast-kyiv/cities → «Київ» (city-kyiv, no districts)
//
// KEY POLICY: navigation taps are key-based (client-nav-search-center,
// search_service_type_NAILS, search_show_masters_cta, locality_picker_tile_*).
// Raw find.text(...) is used only for content assertions (city/category names
// are backend data). See integration_test/support/app_harness.dart.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/discovery/domain/search_filters.dart';
import 'package:beautica_mobile/features/discovery/presentation/search_results_screen.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/service_chip_drawer.dart';
import 'package:beautica_mobile/features/shell/presentation/client_shell.dart';
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

  void expectLocation(GoRouter router, String expected) {
    final String current = router.routerDelegate.currentConfiguration.uri
        .toString();
    expect(
      current,
      startsWith(expected),
      reason: 'Expected router location to start with $expected, got $current',
    );
  }

  /// Reads the SearchFilters the results screen received via `extra`.
  SearchFilters? receivedFilters(WidgetTester tester) {
    final SearchResultsScreen results = tester.widget<SearchResultsScreen>(
      find.byType(SearchResultsScreen),
    );
    return results.initialFilters;
  }

  /// Drives the THREE-field locality funnel through the REAL picker sheets:
  /// Region («Київська») then City («Київ»). City is gated on a Region, so the
  /// region MUST be picked first — tapping the city row before that is inert.
  /// The seeded «Київ» has hasDistricts:false, so the District field stays
  /// disabled and the (optional) district step is correctly skipped.
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

  testWidgets(
    'CLIENT taps the search disc, picks a city + service type + price, and '
    '«Показати майстрів» pushes /search/results carrying the filters',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);

      // ── Log in as CLIENT → land on the client shell at /home ──────────────
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expectLocation(router, RouteNames.clientHome);
      expect(find.byType(ClientShell), findsOneWidget);

      // ── Tap the elevated center «Пошук» disc → real ClientSearchScreen ────
      await tester.tap(find.byKey(const Key('client-nav-search-center')));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expectLocation(router, RouteNames.clientSearch);
      expect(
        find.byKey(const Key('client-branch-search')),
        findsOneWidget,
        reason: 'the search disc must mount the real ClientSearchScreen branch',
      );
      // All five filter sections are present (Variant A — category RAIL).
      expect(find.byKey(const Key('search_query_field')), findsOneWidget);
      expect(find.byKey(const Key('search_city_value')), findsOneWidget);
      expect(find.byKey(const Key('search_category_rail')), findsOneWidget);
      // The rail now renders EVERY approved category (no `take(6)` cap) and the
      // «Всі категорії» more-tile + its sheet are DELETED — so it is absent.
      expect(
        find.byKey(const Key('search_all_categories_tile')),
        findsNothing,
        reason: 'the «Всі категорії» more-tile was removed from the rail',
      );
      // Both seeded categories render real, tappable tiles (NAILS «Нігті» +
      // BROWS «Брови»). At least one real tile being present (and tapped below)
      // proves the rail is populated, not a single more-tile.
      expect(
        find.byKey(const Key('search_service_type_NAILS')),
        findsOneWidget,
        reason: 'every approved category renders a real, tappable rail tile',
      );
      // Пошук no longer passes onBurger to the shared ClientTopBar → no burger.
      // The bell stays; the burger key the screen used to pass is gone.
      expect(find.byKey(const Key('search_bell_button')), findsOneWidget);
      expect(
        find.byKey(const Key('btn-menu-search')),
        findsNothing,
        reason: 'the search top bar omits the burger (redundant settings hub)',
      );
      expect(find.byKey(const Key('search_price_slider')), findsOneWidget);
      expect(find.byKey(const Key('search_show_masters_cta')), findsOneWidget);

      // ── Pick a region → city through the REAL three-field cascade ─────────
      // The location control is now three gated fields: Region must be picked
      // first (it enables the City field), then City. Tap Region → oblast sheet
      // → «Київська»; then City → city sheet → «Київ».
      await pickRegionThenCity(tester);

      // The city label now shows the chosen city name (backend data).
      final Text cityValue = tester.widget<Text>(
        find.byKey(const Key('search_city_value')),
      );
      expect(cityValue.data, 'Київ');

      // ── Select a category in the rail (NAILS) → reveals the chip drawer ───
      await tester.tap(find.byKey(const Key('search_service_type_NAILS')));
      await tester.pumpAndSettle();

      // Variant A second level: the recessed service-chip drawer opens with the
      // NAILS family chips fetched live from the fake backend's
      // GET /service-types?categoryName=NAILS slice (slug CLASSIC_MANICURE).
      expect(
        find.byType(ServiceChipDrawer),
        findsOneWidget,
        reason: 'selecting a category must reveal its service-chip drawer',
      );
      expect(
        find.byKey(const Key('search_service_chip_CLASSIC_MANICURE')),
        findsOneWidget,
        reason:
            'the NAILS service-types endpoint slice renders a keyed chip '
            '(key = slug CLASSIC_MANICURE)',
      );

      // Tap a service chip — exercises the (currently INERT) second-level
      // selection. It toggles UI state but is NOT carried on SearchFilters yet.
      await tester.tap(
        find.byKey(const Key('search_service_chip_CLASSIC_MANICURE')),
      );
      await tester.pumpAndSettle();

      // ── Drag the price slider down from the «будь-яка» ceiling ────────────
      await tester.drag(
        find.byKey(const Key('search_price_slider')),
        const Offset(-160, 0),
      );
      await tester.pumpAndSettle();

      // ── Tap «Показати майстрів» → push /search/results ────────────────────
      await tester.tap(find.byKey(const Key('search_show_masters_cta')));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expectLocation(router, RouteNames.clientSearchResults);
      expect(
        find.byKey(const Key('client-search-results')),
        findsOneWidget,
        reason: 'the CTA must push the results screen onto the search branch',
      );

      // ── Assert the placeholder received the assembled filter set ──────────
      final SearchFilters? filters = receivedFilters(tester);
      expect(filters, isNotNull, reason: 'filters must be forwarded via extra');
      expect(
        filters!.cityId,
        'city-kyiv',
        reason: 'the picked city id must be carried to the results screen',
      );
      expect(
        filters.categoryKey,
        'NAILS',
        reason: 'the selected service-type slug must be carried',
      );
      expect(
        filters.maxPrice,
        isNotNull,
        reason: 'a dragged-down slider must carry a finite max price',
      );
      expect(filters.maxPrice, lessThan(5000));

      // ── Regression (Step 2.7 Rule 3b) — CLIENT 403 decoupling ─────────────
      // A CLIENT walking the entire search journey must NEVER hit the
      // master-only `GET /api/v1/masters/me`. The buggy
      // approvedCategoriesProvider → serviceRepositoryProvider →
      // masterProfileProvider chain would have called it (and against the real
      // backend it 403s, then Riverpod retries ~4×). The fake backend counts
      // every hit on that route, so a zero count proves the public
      // listApproved() sourcing kept the master profile out of the path.
      expect(
        fb.getMasterCalls,
        0,
        reason:
            'the CLIENT search journey must not touch GET /masters/me '
            '(403 decoupling regression)',
      );
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  // ──────────────────────────────────────────────────────────────────────────
  // Three-field locality funnel — E2E: City is GATED on a Region, and a
  // Region→City (no district) selection scopes the wire to location.cityId.
  //
  // WHY THIS FLOW EXISTS
  // --------------------
  // The combined «Місто · Район» row became three discrete, gated fields. The
  // widget tier pins the gating in isolation; THIS flow proves the funnel end to
  // end against the real picker sheets + the live SearchResultsNotifier →
  // HttpSearchRepository. It asserts:
  //   1. tapping the City field BEFORE a Region opens NO picker (it is inert),
  //   2. after picking a Region the City field enables and a city can be chosen,
  //   3. the seeded «Київ» (hasDistricts:false) leaves the District step skipped
  //      (district-optional) — yet the search still scopes to location.cityId.
  //
  // Step 2.7 Rule 3b: the gated funnel + locality picker + navigation +
  // provider→repository + the exact `location.cityId` query contract — the
  // widget tier cannot prove this composes end to end against the real backend.
  // ──────────────────────────────────────────────────────────────────────────
  testWidgets(
    'CLIENT three-field funnel: City is inert until a Region is picked, then a '
    'Region→City (no district) search scopes to location.cityId',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // ── Reach the search screen ─────────────────────────────────────────────
      await tester.tap(find.byKey(const Key('client-nav-search-center')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expectLocation(router, RouteNames.clientSearch);

      // ── Gating: tapping City BEFORE a Region opens NO picker sheet ──────────
      await tester.tap(find.byKey(const Key('search_city_value')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('locality_picker_search')),
        findsNothing,
        reason: 'the City field is gated on a Region — its tap must be inert',
      );

      // ── Pick Region → City (district skipped — «Київ» has none) ─────────────
      await pickRegionThenCity(tester);
      final Text cityValue = tester.widget<Text>(
        find.byKey(const Key('search_city_value')),
      );
      expect(cityValue.data, 'Київ');

      // ── Submit → the search scopes to the FLAT location.cityId ──────────────
      await tester.tap(find.byKey(const Key('search_show_masters_cta')));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expectLocation(router, RouteNames.clientSearchResults);
      expect(find.byKey(const Key('client-search-results')), findsOneWidget);

      // The region→city pick reached the wire as location.cityId on BOTH
      // endpoints; with no district picked, location.districtId is OMITTED
      // (district-optional) — null, not empty.
      expect(fb.lastSearchMastersCityId, 'city-kyiv');
      expect(fb.lastSearchSalonsCityId, 'city-kyiv');
      expect(
        fb.lastSearchMastersDistrictId,
        isNull,
        reason: 'a city with no districts skips the optional district step',
      );
      expect(fb.lastSearchSalonsDistrictId, isNull);

      expect(fb.getMasterCalls, 0);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  // ──────────────────────────────────────────────────────────────────────────
  // Phase 13.4 — E2E: results render REAL cards → favorite POST → loadMore.
  //
  // The first flow stops at the /search/results handoff. THIS flow continues
  // into the live results screen: with /search/masters + /search/salons now
  // wired in the fake backend, the family-keyed SearchResultsNotifier fires
  // BOTH endpoints, merges (masters-first), and renders real cards. Then it taps
  // the master heart (drives the optimistic toggle → POST /favorites) and
  // scrolls to fetch page 1 (loadMore → second master appended).
  //
  // Step 2.7 Rule 3b: this is the real user journey (screen + navigation +
  // provider→repository + API contract + favorites write) the widget tier
  // cannot prove end to end.
  // ──────────────────────────────────────────────────────────────────────────
  testWidgets('CLIENT search results render real cards, tapping a heart POSTs a '
      'favorite, and scrolling appends page 2', (tester) async {
    final fb = FakeBackend()..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(tester, fb);

    await AppHarness.loginAs(tester, fb, UserRole.client);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // ── Reach the search screen + submit with no filters (browse all) ───────
    await tester.tap(find.byKey(const Key('client-nav-search-center')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.byKey(const Key('search_show_masters_cta')));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expectLocation(router, RouteNames.clientSearchResults);
    expect(find.byKey(const Key('client-search-results')), findsOneWidget);

    // ── Page 0 fetched BOTH endpoints and rendered the merged cards ─────────
    expect(find.byKey(const Key('results_list')), findsOneWidget);
    expect(
      fb.searchMastersCalls,
      greaterThanOrEqualTo(1),
      reason: 'the results screen must query /search/masters',
    );
    expect(
      fb.searchSalonsCalls,
      greaterThanOrEqualTo(1),
      reason: 'the results screen must query /search/salons',
    );
    // The seeded page-0 master + salon both rendered (key = backend id).
    expect(find.byKey(const Key('favorite_master_master-aaa')), findsOneWidget);
    expect(find.byKey(const Key('favorite_salon_salon-xyz')), findsOneWidget);
    // Master price «від N грн» + salon price RANGE are the documented gaps.
    expect(find.text('від 450 грн'), findsOneWidget);

    // ── Tap the master heart → optimistic flip → POST /favorites ────────────
    expect(fb.addFavoriteCalls, 0);
    await tester.tap(find.byKey(const Key('favorite_master_master-aaa')));
    await tester.pumpAndSettle();

    expect(
      fb.addFavoriteCalls,
      1,
      reason: 'tapping an empty heart must POST exactly one favorite',
    );
    expect(fb.lastAddFavoriteBody?['targetType'], 'MASTER');
    expect(fb.lastAddFavoriteBody?['targetId'], 'master-aaa');

    // ── Scroll to the end → loadMore fetches page 1 (second master) ─────────
    final ScrollableState scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('results_list')),
        matching: find.byType(Scrollable),
      ),
    );
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    // loadMore fires, fetches the (fast, in-memory) last master page, and the
    // trailing spinner is removed once BOTH endpoints are spent — so the tree
    // settles. A settle is safe here precisely because the seeded fake leaves no
    // page pending (the integration binding forbids the pump(Duration) idiom the
    // widget tier uses for the mid-flight spinner case).
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(
      fb.lastSearchMastersPage,
      1,
      reason: 'scrolling to the end must request the next masters page',
    );
    // The second page's master row is now in the model; jump again to surface
    // the lazily-built card and assert it rendered.
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('favorite_master_master-bbb')), findsOneWidget);

    // The CLIENT results journey still never touched GET /masters/me.
    expect(fb.getMasterCalls, 0);
  }, timeout: const Timeout(Duration(seconds: 90)));

  // ──────────────────────────────────────────────────────────────────────────
  // Phase 19.x — E2E: free-text query + sort selection reach the wire.
  //
  // Types a name/service query on the Пошук screen, submits to the results
  // screen, opens the sort sheet, and picks «Спочатку дешевші» (PRICE_ASC). The
  // fake backend captures the `q` + `sort` carried on the most recent
  // /search/masters AND /search/salons request, proving Items 2 + 5 reach the
  // wire end to end (controller → SearchFilters → repository → request DTO).
  // ──────────────────────────────────────────────────────────────────────────
  testWidgets(
    'CLIENT query + sort selection reach BOTH search endpoints',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // ── Reach the search screen, type a query, submit ───────────────────────
      await tester.tap(find.byKey(const Key('client-nav-search-center')));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await tester.enterText(
        find.byKey(const Key('search_query_field')),
        'Манікюр',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('search_show_masters_cta')));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expectLocation(router, RouteNames.clientSearchResults);
      expect(find.byKey(const Key('client-search-results')), findsOneWidget);

      // Item 2 — the free-text query reached the wire on both endpoints with the
      // default ordering applied.
      expect(fb.lastSearchMastersQuery, 'Манікюр');
      expect(fb.lastSearchSalonsQuery, 'Манікюр');
      expect(fb.lastSearchMastersSort, 'RATING_DESC');

      // ── Open the sort sheet, pick «Спочатку дешевші» (PRICE_ASC) ─────────────
      await tester.tap(find.byKey(const Key('results_sort_button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(Key('sort_option_${SearchSort.priceAsc.name}')),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Item 5 — the new ordering re-queried both endpoints; the query persists.
      expect(fb.lastSearchMastersSort, 'PRICE_ASC');
      expect(fb.lastSearchSalonsSort, 'PRICE_ASC');
      expect(fb.lastSearchMastersQuery, 'Манікюр');

      expect(fb.getMasterCalls, 0);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  // ──────────────────────────────────────────────────────────────────────────
  // Phase 13.x — E2E REGRESSION: a picked city must SCOPE the search (the
  // all-regions wire-format bug).
  //
  // WHY THIS FLOW EXISTS
  // --------------------
  // The original bug: filtering by city returned masters from ALL regions. The
  // OpenAPI-generated client serialised the whole search DTO as ONE object query
  // param → Dio bracket-nested it (`request[location][cityId]=…`) → Spring's
  // @ModelAttribute binder could not read the bracketed keys → the backend bound
  // an all-null request → an unfiltered all-regions 200. The unit tier
  // (search_repository_test.dart) pins the FLAT wire at the repository seam; THIS
  // flow proves the same end to end: a CLIENT picking «Київ» through the REAL
  // locality cascade and submitting drives the live SearchResultsNotifier →
  // HttpSearchRepository → GET /search/{masters,salons}, and the fake backend
  // captures `location.cityId` as a FLAT key on BOTH endpoints. A reverted
  // object-query encoding would leave that capture null (bracketed keys never
  // bind), failing this flow.
  //
  // Step 2.7 Rule 3b: this is the real user journey (screen + locality picker +
  // navigation + provider→repository + the exact API query contract) the widget
  // tier cannot prove end to end.
  // ──────────────────────────────────────────────────────────────────────────
  testWidgets('CLIENT picks a city → the search scopes to location.cityId on BOTH '
      'endpoints (all-regions wire-format regression)', (tester) async {
    final fb = FakeBackend()..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(tester, fb);

    await AppHarness.loginAs(tester, fb, UserRole.client);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // ── Reach the search screen ─────────────────────────────────────────────
    await tester.tap(find.byKey(const Key('client-nav-search-center')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expectLocation(router, RouteNames.clientSearch);

    // ── Pick «Київ» through the REAL three-field region→city cascade ────────
    await pickRegionThenCity(tester);

    final Text cityValue = tester.widget<Text>(
      find.byKey(const Key('search_city_value')),
    );
    expect(cityValue.data, 'Київ');

    // ── Submit → results screen fires BOTH endpoints with the city scope ────
    await tester.tap(find.byKey(const Key('search_show_masters_cta')));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expectLocation(router, RouteNames.clientSearchResults);
    expect(find.byKey(const Key('client-search-results')), findsOneWidget);
    expect(fb.searchMastersCalls, greaterThanOrEqualTo(1));
    expect(fb.searchSalonsCalls, greaterThanOrEqualTo(1));

    // ── REGRESSION ASSERTION — the city reached the wire as a FLAT key ──────
    // The fake backend reads `location.cityId` straight off the FLAT query
    // map. A null here means the city scope never bound (the reverted
    // object-query / bracket-nested encoding) → an all-regions result.
    expect(
      fb.lastSearchMastersCityId,
      'city-kyiv',
      reason:
          'the picked city must scope /search/masters via the FLAT '
          'location.cityId key (not a bracket-nested request[...])',
    );
    expect(
      fb.lastSearchSalonsCityId,
      'city-kyiv',
      reason: 'the picked city must scope /search/salons too',
    );
    // No district was picked (the seeded city has none) → omitted, not empty.
    expect(fb.lastSearchMastersDistrictId, isNull);
    expect(fb.lastSearchSalonsDistrictId, isNull);

    expect(fb.getMasterCalls, 0);
  }, timeout: const Timeout(Duration(seconds: 90)));

  // ──────────────────────────────────────────────────────────────────────────
  // Search-page change (items 4, 5, 6, 7) — E2E: a region→city filter scopes
  // the results, the results screen shows the applied-filter chips, and the
  // salon card renders its price RANGE + services line + full street address.
  //
  // WHY THIS FLOW EXISTS
  // --------------------
  // The unit + widget tiers pin each piece in isolation (the controller cascade,
  // the salon card's price/services/address rendering, the mapper's addressLine
  // join). This flow proves they compose end to end: a CLIENT picking «Київська»
  // → «Київ» through the REAL locality cascade, submitting, and seeing the
  // results screen render the applied-filter chip strip AND a salon card whose
  // price/services/address all come from the (authenticated) /search/salons
  // response. The seeded salon-xyz now carries street/buildingNo (auth-gated)
  // and serviceNames, so the card's `addressLine` + `servicesLine` are live.
  //
  // Step 2.7 Rule 3b: this is the real user journey (locality cascade +
  // navigation + provider→repository + the rendered result card + chip strip)
  // the widget tier cannot prove end to end.
  // ──────────────────────────────────────────────────────────────────────────
  testWidgets(
    'CLIENT region→city filter → results show applied-filter chips + a salon '
    'card with price range, services line, and full address',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // ── Reach the search screen ─────────────────────────────────────────────
      await tester.tap(find.byKey(const Key('client-nav-search-center')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expectLocation(router, RouteNames.clientSearch);

      // ── Pick «Київська» → «Київ» through the REAL three-field cascade ───────
      await pickRegionThenCity(tester);

      final Text cityValue = tester.widget<Text>(
        find.byKey(const Key('search_city_value')),
      );
      expect(cityValue.data, 'Київ');

      // ── Submit → results screen fires the scoped search ─────────────────────
      await tester.tap(find.byKey(const Key('search_show_masters_cta')));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expectLocation(router, RouteNames.clientSearchResults);
      expect(find.byKey(const Key('client-search-results')), findsOneWidget);
      expect(find.byKey(const Key('results_list')), findsOneWidget);

      // ── Item 4 — the city scoped the wire AND the chips reflect it ──────────
      expect(fb.lastSearchSalonsCityId, 'city-kyiv');
      // The applied-filter chip strip renders, with a city chip (the picker set
      // the city label on the labels controller).
      expect(
        find.byKey(const Key('applied_filters_row')),
        findsOneWidget,
        reason: 'a picked locality must surface the applied-filter chip strip',
      );
      expect(
        find.byKey(const Key('filter_chip_locality')),
        findsOneWidget,
        reason: 'the picked city renders a removable locality chip',
      );

      // ── The seeded salon card rendered (keyed by backend id) ────────────────
      expect(find.byKey(const Key('favorite_salon_salon-xyz')), findsOneWidget);

      // Item 5 — the salon price RANGE renders (priceMin 300, priceMax 1200).
      expect(
        find.text('300–1200 грн'),
        findsOneWidget,
        reason: 'salon-xyz has priceMin<priceMax → a «N–M грн» range renders',
      );

      // Item 7 — the salon services preview line renders.
      final Finder servicesLine = find.byKey(const Key('salon_card_services'));
      expect(servicesLine, findsOneWidget);
      expect(
        tester.widget<Text>(servicesLine).data,
        'Манікюр · Стрижка',
        reason: 'the salon serviceNames join into the « · » preview line',
      );

      // Item 6 — the authenticated caller gets the auth-gated street address,
      // so the card shows the full address line in place of the locality.
      expect(
        find.text('вул. Хрещатик, 12'),
        findsOneWidget,
        reason:
            'an authenticated search carries the Bearer token, so the backend '
            'returns street/buildingNo and the card shows the full address.',
      );

      expect(fb.getMasterCalls, 0);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
