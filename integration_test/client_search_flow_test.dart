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

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/discovery/domain/search_filters.dart';
import 'package:beautica_mobile/features/discovery/presentation/search_results_screen.dart';
import 'package:beautica_mobile/features/discovery/presentation/state/search_filters_controller.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/service_chip_drawer.dart';
import 'package:beautica_mobile/features/shell/presentation/client_shell.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/slider_geometry.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  /// Reads the SearchFilters the results screen received via `extra`.
  SearchFilters? receivedFilters(WidgetTester tester) {
    final SearchResultsScreen results = tester.widget<SearchResultsScreen>(
      find.byType(SearchResultsScreen),
    );
    return results.initialFilters;
  }

  /// Scrolls the Пошук filters screen's outer (vertical) [ListView] until
  /// [key] is inflated AND visible.
  ///
  /// `-d flutter-tester`'s window is `Size(800, 600)` — short and wide, unlike
  /// any phone. The query field plus the three-field `_LocationSection`
  /// (Region/City/District) alone consume the whole 600px budget, pushing
  /// `_CategorySection` (the rail + service-chip drawer) and `_PriceSection`
  /// below the fold. The screen body is a plain `ListView(children: [...])`
  /// (search_filters_screen.dart, NOT `.builder`) — it still only inflates
  /// Elements near the viewport (`SliverChildListDelegate` under a
  /// `SliverList`), so an un-scrolled `find.byKey(...)` on anything below the
  /// locality block reports 0 matches. Plain `tester.ensureVisible` requires
  /// the target Element to already exist, so it cannot bring an un-inflated
  /// widget into view; `scrollUntilVisible` drags the enclosing scrollable in
  /// bounded steps and re-checks after each drag, which is what actually
  /// builds the element.
  ///
  /// `scrollUntilVisible` only ever drags in ONE fixed direction per call
  /// (derived once from the `Scrollable`'s current `axisDirection`) — it
  /// cannot recover a target ABOVE the current scroll offset, only one
  /// further along. Once a prior call has scrolled down to the category rail
  /// / price slider, a later call for a locality field back near the top
  /// would just keep dragging further down and exhaust `maxScrolls` without
  /// ever finding it (`Bad state: No element`). Jumping to offset 0 first
  /// makes every call direction-agnostic: fields at/near the top are
  /// immediately visible with nothing left to drag, and fields further down
  /// are then reached by the forward drag. `.first` on the `Scrollable`
  /// finder always resolves to the outer vertical list (a depth-first
  /// ancestor of the category rail's own nested horizontal
  /// `ListView.separated`), so this stays unambiguous once the rail mounts.
  Future<void> scrollFilterFieldIntoView(WidgetTester tester, Key key) async {
    final Finder outerScrollable = find.byType(Scrollable).first;
    tester.state<ScrollableState>(outerScrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(key),
      200,
      scrollable: outerScrollable,
    );
    await tester.pumpAndSettle();
  }

  /// Drives the THREE-field locality funnel through the REAL picker sheets:
  /// Region («Київська») then City («Київ»). City is gated on a Region, so the
  /// region MUST be picked first — tapping the city row before that is inert.
  /// The seeded «Київ» has hasDistricts:false, so the District field stays
  /// disabled and the (optional) district step is correctly skipped.
  ///
  /// Defensively scrolls each field into view before tapping it: a caller that
  /// already scrolled down to the category/price sections (below the fold)
  /// would otherwise find the region/city rows un-inflated. When the fields
  /// are already visible (the common case — nothing has scrolled yet) this is
  /// a cheap no-op.
  Future<void> pickRegionThenCity(WidgetTester tester) async {
    await scrollFilterFieldIntoView(tester, const Key('search_region_value'));
    await tester.tap(find.byKey(const Key('search_region_value')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('locality_picker_tile_oblast-kyiv')),
    );
    await tester.pumpAndSettle();
    await scrollFilterFieldIntoView(tester, const Key('search_city_value'));
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
      AppHarness.expectLocation(router, RouteNames.clientHome);
      expect(find.byType(ClientShell), findsOneWidget);

      // ── Tap the elevated center «Пошук» disc → real ClientSearchScreen ────
      await tester.tap(find.byKey(const Key('client-nav-search-center')));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      AppHarness.expectLocation(router, RouteNames.clientSearch);
      expect(
        find.byKey(const Key('client-branch-search')),
        findsOneWidget,
        reason: 'the search disc must mount the real ClientSearchScreen branch',
      );
      // All five filter sections are present (Variant A — category RAIL).
      expect(find.byKey(const Key('search_query_field')), findsOneWidget);
      expect(find.byKey(const Key('search_city_value')), findsOneWidget);
      // `_CategorySection` sits below the fold at the flutter-tester's short,
      // wide Size(800, 600) — scroll it into view before asserting anything
      // inside it (see [scrollFilterFieldIntoView]'s doc comment).
      await scrollFilterFieldIntoView(
        tester,
        const Key('search_category_rail'),
      );
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
      // `_PriceSection` sits further below the fold than the category rail —
      // scroll again before asserting on it.
      await scrollFilterFieldIntoView(tester, const Key('search_price_slider'));
      expect(find.byKey(const Key('search_price_slider')), findsOneWidget);
      // The sticky CTA is OUTSIDE the scrollable body (a fixed footer pinned by
      // the screen's own Column — see search_filters_screen.dart), so it is
      // always mounted and visible regardless of the ListView's scroll offset.
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
      // pickRegionThenCity's scrolls left the viewport on the locality block —
      // scroll back down to the rail before tapping it.
      await scrollFilterFieldIntoView(
        tester,
        const Key('search_service_type_NAILS'),
      );
      await tester.tap(find.byKey(const Key('search_service_type_NAILS')));
      await tester.pumpAndSettle();

      // Variant A second level: the recessed service-chip drawer opens with the
      // NAILS family chips fetched live from the fake backend's
      // GET /service-types?categoryName=NAILS slice (slug CLASSIC_MANICURE).
      await scrollFilterFieldIntoView(
        tester,
        const Key('search_service_chip_CLASSIC_MANICURE'),
      );
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
      await scrollFilterFieldIntoView(tester, const Key('search_price_slider'));
      // TWO independent facts govern this drag; both matter.
      //
      // (1) WHICH thumb moves. A `RangeSlider` starts with BOTH thumbs at the
      //     extremes (min at 0, max at the ceiling), so a drag started at the
      //     WIDGET's geometric CENTER is exactly equidistant from either thumb
      //     — an ambiguous tie that can grab the MIN thumb instead of the
      //     intended MAX one. Starting near the RIGHT edge, unambiguously
      //     inside the max thumb's hit region, resolves that.
      //
      // (2) WHERE it lands. This is what a fixed `Offset(-160, 0)` got wrong.
      //     `_RenderRangeSlider._handleDragUpdate` derives the new value from
      //     the ABSOLUTE final pointer x
      //     (`_getValueFromGlobalPosition(details.globalPosition)`) — NOT from
      //     the accumulated delta. So the drag distance carries no meaning at
      //     all; only the x-coordinate the pointer ends on does. A relative
      //     `-160` therefore landed on whatever value that absolute x mapped
      //     to (measured: 15500), not "160px worth of price lower".
      //
      // So: compute the target x from the value we want. The track is inset
      // from the widget rect by the `RoundSliderOverlayShape` radius on each
      // side, and `kSearchPriceDivisions` (40) quantises the ceiling into
      // 500-₴ steps, so a multiple of 500 snaps exactly.
      // [kSliderOverlayInset] is SHARED with the widget-tier pin in
      // `test/features/discovery/presentation/search_filters_price_slider_drag_test.dart`
      // via `test/helpers/slider_geometry.dart` — it used to be a second
      // hand-copied `24` here, kept honest only by a comment. If the slider
      // geometry ever drifts, that widget pin goes red first and names itself;
      // do not re-inline the literal.
      const double targetMax = 3000; // multiple of 500 → snaps exactly
      final Rect sliderRect = tester.getRect(
        find.byKey(const Key('search_price_slider')),
      );
      final double trackLeft = sliderRect.left + kSliderOverlayInset;
      final double trackWidth = sliderRect.width - 2 * kSliderOverlayInset;
      final Offset dragStart = Offset(
        sliderRect.right - 16,
        sliderRect.center.dy,
      );
      final double targetX =
          trackLeft + (targetMax / kSearchPriceCeiling) * trackWidth;
      await tester.dragFrom(dragStart, Offset(targetX - dragStart.dx, 0));
      await tester.pumpAndSettle();

      // ── Tap «Показати майстрів» → push /search/results ────────────────────
      // NOT `pumpAndSettle()`: FakeBackend's /search/masters fixture seeds
      // `totalPages: 2`, so the results screen mounts a trailing INDETERMINATE
      // `_LoadMoreSpinner` the instant page 0 loads — its repeating
      // AnimationController keeps a frame perpetually scheduled, so
      // `pumpAndSettle` would never observe quiescence. Pump-until-found
      // instead (see [AppHarness.pumpUntilFound]).
      await tester.tap(find.byKey(const Key('search_show_masters_cta')));
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('results_list')),
      );

      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.clientSearchResults,
      );
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
      // The computed drag lands the max thumb on an exact division boundary.
      expect(filters.maxPrice, targetMax);

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
      AppHarness.expectLocation(router, RouteNames.clientSearch);

      // ── Gating: tapping City BEFORE a Region opens NO picker sheet ──────────
      await tester.tap(find.byKey(const Key('search_city_value')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('locality_picker_search')),
        findsNothing,
        reason: 'the City field is gated on a Region — its tap must be inert',
      );

      // ── «Require a city» gate (Step 2.7 Rule 3b) — region-only is blocked ────
      // Pick ONLY a Region (no City). A region without a city is not a
      // searchable scope (region-only would send no location filter → providers
      // from EVERY city), so the search CTA must be DISABLED in this state. The
      // widget tier pins the disabled chrome in isolation; here we prove the
      // gate holds end to end against the REAL screen + picker + controller.
      await tester.tap(find.byKey(const Key('search_region_value')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('locality_picker_tile_oblast-kyiv')),
      );
      await tester.pumpAndSettle();

      NeumorphicButton ctaButton() => tester.widget<NeumorphicButton>(
        find.byKey(const Key('search_show_masters_cta')),
      );
      expect(
        ctaButton().onPressed,
        isNull,
        reason: 'region-only (no city) must disable «Показати майстрів»',
      );
      // Tapping the disabled CTA is inert — it must NOT navigate to results.
      await tester.tap(find.byKey(const Key('search_show_masters_cta')));
      // results-settle-ok: the CTA is DISABLED here (onPressed == null), so
      // this tap pushes nothing — the results screen never mounts and there is
      // no _LoadMoreSpinner to keep a frame scheduled. A plain settle is both
      // correct and necessary: the assertion below is that NOTHING happened,
      // so there is no arrival state for pumpUntilFound to wait on.
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('client-search-results')),
        findsNothing,
        reason:
            'a blocked region-only CTA tap must not push the results screen',
      );
      AppHarness.expectLocation(router, RouteNames.clientSearch);

      // ── Now pick the City → the gate releases, CTA enables ──────────────────
      await tester.tap(find.byKey(const Key('search_city_value')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('locality_picker_tile_city-kyiv')),
      );
      await tester.pumpAndSettle();
      final Text cityValue = tester.widget<Text>(
        find.byKey(const Key('search_city_value')),
      );
      expect(cityValue.data, 'Київ');
      expect(
        ctaButton().onPressed,
        isNotNull,
        reason: 'a committed Region + City re-enables the search CTA',
      );

      // ── Submit → the search scopes to the FLAT location.cityId ──────────────
      // Not `pumpAndSettle()` — see [AppHarness.pumpUntilFound]'s doc comment
      // (FakeBackend's masters fixture always leaves a page pending on first
      // load, so the trailing indeterminate spinner never lets pumpAndSettle
      // observe quiescence).
      await tester.tap(find.byKey(const Key('search_show_masters_cta')));
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('results_list')),
      );

      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.clientSearchResults,
      );
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
    // Not `pumpAndSettle()` — see [AppHarness.pumpUntilFound]'s doc comment
    // (FakeBackend's masters fixture always leaves a page pending on first
    // load, so the trailing indeterminate spinner never lets pumpAndSettle
    // observe quiescence).
    await tester.tap(find.byKey(const Key('search_show_masters_cta')));
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(const Key('results_list')),
    );

    AppHarness.expectNestedPushLocation(router, RouteNames.clientSearchResults);
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
    // Master price. `master-aaa` seeds a floor (450) and NO ceiling, so the
    // card takes MasterResultCard._priceLabel's `hi == null` branch and renders
    // the EXACT price — «450 ₴», with NO «від» prefix (b550428 dropped the
    // prefix for a fixed master price). The SALON card still prefixes an
    // open-ended floor via `searchPriceFrom`, which is why the two cards read
    // differently — that asymmetry is intentional, not a gap.
    //
    // This string is CLIENT-rendered from l10n (`searchResultPriceExact`), NOT
    // a raw backend `priceDisplay` — it always carries the mobile client's own
    // current currency glyph («₴»), independent of the backend's formatting.
    // Resolved off the PUMPED TREE rather than hard-coded: this flow runs only
    // on CI's emulator job, so a literal that drifts from the ARB can rot
    // unnoticed for weeks (it did — the old «від 450 ₴» literal outlived the
    // b550428 render change by a long way).
    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(SearchResultsScreen)),
    );
    expect(find.text(l10n.searchResultPriceExact(450)), findsOneWidget);

    // ── Tap the master heart → optimistic flip → POST /favorites ────────────
    expect(fb.addFavoriteCalls, 0);
    // `pumpUntilFound(results_list)` returns when the DATA lands, which is
    // unrelated to the route transition: /search/results is a plain
    // MaterialPage (app_router.dart:441) and the app pins
    // CupertinoPageTransitionsBuilder for every platform (app_theme.dart:37),
    // so the page slides in from the right over 500 ms. Mid-slide the heart is
    // in the TREE (findsOneWidget passes) but its global centre can sit past
    // the right edge of the 800x600 flutter-tester view — measured at x=898.6
    // on a red run, vs. a resting 746.0 with only 54 px of spare room. tap()
    // then hits NOTHING, onTap never runs, and the wait below can never
    // succeed. Gate on the widget being genuinely hit-testable.
    final Finder heart = find.byKey(const Key('favorite_master_master-aaa'));
    await AppHarness.pumpUntilFound(tester, heart.hitTestable());
    await tester.tap(heart);
    // Not `pumpAndSettle()` — page 0 already left the trailing indeterminate
    // spinner mounted (masterHasMore is still true; only the loadMore below
    // clears it), so pumpAndSettle still can't observe quiescence here. Wait
    // on the POST itself landing instead (see [AppHarness.pumpUntilCondition]).
    await AppHarness.pumpUntilCondition(
      tester,
      () => fb.addFavoriteCalls >= 1,
      description: 'POST /favorites to land',
    );

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
  // mobile-security MEDIUM (heart tap-target) — E2E: the 48×48 heart overlay
  // and the card's own navigate-on-tap gesture do not steal each other's taps.
  //
  // WHY THIS FLOW EXISTS
  // --------------------
  // The fix moved `FavoriteHeartButton` OUT of each result card's `Row` and
  // into a `Stack` overlay (`FavoriteHeartOverlay`) that paints LAST, so it
  // wins hit-tests inside its own 48×48 box and the card body wins everywhere
  // else. Both halves of that are behaviour a `Stack` can silently break: a
  // z-order slip makes the heart untappable, and an over-expanded box makes
  // the card untappable.
  //
  // The widget tier now pins the geometry precisely
  // (`test/features/discovery/presentation/widgets/{master,salon}_result_card_
  // favorite_heart_tap_target_test.dart`), but it pumps ONE card in isolation.
  // It cannot prove the same holds in the real screen — inside
  // `SearchResultsScreen`'s scrolling `ListView.separated`, on a card built
  // from a live `/search/masters` payload, with the real `favoriteToggle` →
  // `FavoriteRepository` → `POST /favorites` chain and the real go_router
  // push behind the card body. Step 2.7 Rule 3b: a screen + navigation +
  // provider→repository + API-contract change needs a fake-backed flow.
  //
  // `public_master_profile_flow_test.dart` reaches that profile by
  // `router.push(...)` directly (its own comment says driving real cards was
  // "non-deterministic"), so until now NO flow proved a real card TAP opens
  // the profile at all. This one does — and proves the heart does not hijack
  // it.
  //
  // MUTATION PROOF (run 2026-08-11; overlay restored byte-for-byte after,
  // 12/12 green again): inverting `FavoriteHeartOverlay.build()`'s `Stack`
  // z-order — painting the heart FIRST and `body` LAST, so the card's own
  // `GestureDetector` covers the heart — took this flow RED at half one
  // (`AppHarness.pumpUntilFound timed out after 0:00:10 waiting for … POST
  // /favorites to land`), i.e. the heart became untappable in the real
  // screen. The pre-existing "results render real cards" flow above went RED
  // with it. Green run: `+12`, mutated run: `+10 -2`. The two widget-tier
  // files' geometry pins do NOT catch this — the box measures 48×48 in both
  // trees; only a real hit test through the composed screen does.
  // ──────────────────────────────────────────────────────────────────────────
  testWidgets('CLIENT tapping the heart on a result card favourites WITHOUT '
      'navigating, and tapping the card body still opens the master profile', (
    tester,
  ) async {
    final fb = FakeBackend()..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(tester, fb);

    await AppHarness.loginAs(tester, fb, UserRole.client);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // ── Reach the live results screen (browse-all, no filters) ──────────────
    await tester.tap(find.byKey(const Key('client-nav-search-center')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    // Not `pumpAndSettle()` — FakeBackend seeds `totalPages: 2`, so the
    // trailing indeterminate `_LoadMoreSpinner` never lets the tree quiesce
    // (see [AppHarness.pumpUntilFound]).
    await tester.tap(find.byKey(const Key('search_show_masters_cta')));
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(const Key('results_list')),
    );
    AppHarness.expectNestedPushLocation(router, RouteNames.clientSearchResults);

    // ── HALF ONE — the heart favourites and does NOT navigate ──────────────
    expect(fb.addFavoriteCalls, 0);
    // Gate on hit-testability, not mere presence: /search/results rides in on
    // a 500 ms Cupertino slide, and mid-slide the heart's centre can sit past
    // the right edge of the 800x600 flutter-tester view — `tap()` would then
    // hit nothing and the wait below could never succeed.
    final Finder heart = find.byKey(const Key('favorite_master_master-aaa'));
    await AppHarness.pumpUntilFound(tester, heart.hitTestable());
    await tester.tap(heart);
    await AppHarness.pumpUntilCondition(
      tester,
      () => fb.addFavoriteCalls >= 1,
      description: 'POST /favorites to land',
    );

    expect(
      fb.addFavoriteCalls,
      1,
      reason: 'the heart must reach the favourites API exactly once',
    );
    expect(fb.lastAddFavoriteBody?['targetType'], 'MASTER');
    expect(fb.lastAddFavoriteBody?['targetId'], 'master-aaa');

    // …and the CARD's own gesture must NOT have fired underneath it. This is
    // the half a z-order/hit-test regression breaks: the overlay paints last
    // precisely so the card's `GestureDetector` never sees a tap inside the
    // heart's box.
    expect(
      find.byKey(const Key('public-master-profile-name')),
      findsNothing,
      reason: 'favouriting must not also open the public master profile',
    );
    expect(
      find.byKey(const Key('client-search-results')),
      findsOneWidget,
      reason: 'the client must still be standing on the results screen',
    );
    AppHarness.expectNestedPushLocation(router, RouteNames.clientSearchResults);
    expect(
      fb.getPublicMasterCalls,
      0,
      reason:
          'no profile fetch may have fired — the strongest evidence the card '
          'gesture stayed silent, independent of what is currently rendered',
    );

    // ── HALF TWO — the card BODY still navigates ───────────────────────────
    // The name `Text` is inside the `Expanded` column, far outside the
    // heart's 48×48 box (which sits 4dp in from the card's trailing edge).
    // The card is now the ONLY thing between this tap and the profile: a
    // regression that over-expands the heart's box, or that drops the card's
    // gesture while wiring the overlay, strands the user here.
    final Finder cardName = find.byKey(const Key('master_card_name')).first;
    await AppHarness.pumpUntilFound(tester, cardName.hitTestable());
    await tester.tap(cardName);
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(const Key('public-master-profile-name')),
    );

    AppHarness.expectNestedPushLocation(
      router,
      RouteNames.masterPublicProfile('master-aaa'),
    );
    expect(
      fb.getPublicMasterCalls,
      greaterThanOrEqualTo(1),
      reason:
          'the card tap must resolve the profile via public GET /masters/{id}',
    );
    expect(fb.lastGetPublicMasterId, 'master-aaa');
    // The body tap must NOT have also toggled the favourite (the mirror
    // hijack: a card gesture swallowing taps meant for the heart would show
    // up as an extra POST here, and an overlay that leaked its own gesture
    // across the card would show up as a second one).
    expect(
      fb.addFavoriteCalls,
      1,
      reason: 'tapping the card body must not fire the favourite again',
    );

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

      // Not `pumpAndSettle()` — see [AppHarness.pumpUntilFound]'s doc comment
      // (FakeBackend's masters fixture always leaves a page pending on first
      // load, so the trailing indeterminate spinner never lets pumpAndSettle
      // observe quiescence).
      await tester.tap(find.byKey(const Key('search_show_masters_cta')));
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('results_list')),
      );

      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.clientSearchResults,
      );
      expect(find.byKey(const Key('client-search-results')), findsOneWidget);

      // Item 2 — the free-text query reached the wire on both endpoints with the
      // default ordering applied.
      expect(fb.lastSearchMastersQuery, 'Манікюр');
      expect(fb.lastSearchSalonsQuery, 'Манікюр');
      expect(fb.lastSearchMastersSort, 'RATING_DESC');

      // ── Open the sort sheet, pick «Спочатку дешевші» (PRICE_ASC) ─────────────
      // Same mid-transition hazard as the heart tap above: `pumpUntilFound(
      // results_list)` returns on DATA, not on the 500 ms Cupertino slide that
      // /search/results (a plain MaterialPage) rides in on, so a bare tap here
      // can land off the right edge of the 800x600 view and hit nothing. Gate
      // on the button being genuinely hit-testable — a no-op once the page has
      // finished sliding home.
      final Finder sortBtn = find.byKey(const Key('results_sort_button'));
      await AppHarness.pumpUntilFound(tester, sortBtn.hitTestable());
      await tester.tap(sortBtn);
      // NOT `pumpAndSettle()` — the results screen UNDERNEATH the sheet still
      // has `data.hasMore` true (FakeBackend seeds `totalPages: 2`), so its
      // trailing `_LoadMoreSpinner` keeps an indeterminate
      // `CircularProgressIndicator` (no `value:` → `repeat()`ing controller)
      // mounted for the whole sheet-open animation. Quiescence is therefore
      // never reached and this settle hangs until the test's own timeout fires
      // mid-pump — which trips `!_expectingFrame` in
      // `LiveTestWidgetsFlutterBinding.postTest` and kills every LATER test in
      // the file with `!inTest`. Wait for the sheet's option row instead.
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(Key('sort_option_${SearchSort.priceAsc.name}')),
      );
      await tester.tap(
        find.byKey(Key('sort_option_${SearchSort.priceAsc.name}')),
      );
      // Re-keys the results notifier to a fresh family member (fresh page 0) —
      // same trailing-spinner hazard as the initial submit above, so a bounded
      // pump-until is needed rather than a raw `pumpAndSettle()`. Wait on
      // the wire-captured sort value actually flipping (the list/spinner Finder
      // stays non-empty across the re-key, so it cannot serve as the "did the
      // new page land" signal the way it does right after the first submit).
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.lastSearchMastersSort == 'PRICE_ASC',
        description: 'the re-keyed search to carry sort=PRICE_ASC',
      );

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
    AppHarness.expectLocation(router, RouteNames.clientSearch);

    // ── Pick «Київ» through the REAL three-field region→city cascade ────────
    await pickRegionThenCity(tester);

    final Text cityValue = tester.widget<Text>(
      find.byKey(const Key('search_city_value')),
    );
    expect(cityValue.data, 'Київ');

    // ── Submit → results screen fires BOTH endpoints with the city scope ────
    // Not `pumpAndSettle()` — see [AppHarness.pumpUntilFound]'s doc comment
    // (FakeBackend's masters fixture always leaves a page pending on first
    // load, so the trailing indeterminate spinner never lets pumpAndSettle
    // observe quiescence).
    await tester.tap(find.byKey(const Key('search_show_masters_cta')));
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(const Key('results_list')),
    );

    AppHarness.expectNestedPushLocation(router, RouteNames.clientSearchResults);
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
  // the results, the results screen shows the active-filter «(N)» count badge,
  // and the salon card renders its price RANGE + services line + full address.
  //
  // WHY THIS FLOW EXISTS
  // --------------------
  // The unit + widget tiers pin each piece in isolation (the controller cascade,
  // the salon card's price/services/address rendering, the mapper's addressLine
  // join). This flow proves they compose end to end: a CLIENT picking «Київська»
  // → «Київ» through the REAL locality cascade, submitting, and seeing the
  // results screen render the active-filter «(N)» count badge AND a salon card
  // whose price/services/address all come from the (authenticated) /search/salons
  // response. The seeded salon-xyz now carries street/buildingNo (auth-gated)
  // and serviceNames, so the card's `addressLine` + `servicesLine` are live.
  //
  // Step 2.7 Rule 3b: this is the real user journey (locality cascade +
  // navigation + provider→repository + the rendered result card + count badge)
  // the widget tier cannot prove end to end.
  // ──────────────────────────────────────────────────────────────────────────
  testWidgets(
    'CLIENT region→city filter → results show the «(N)» active-filter badge + a '
    'salon card with price range, services line, and full address',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // ── Reach the search screen ─────────────────────────────────────────────
      await tester.tap(find.byKey(const Key('client-nav-search-center')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.clientSearch);

      // ── Pick «Київська» → «Київ» through the REAL three-field cascade ───────
      await pickRegionThenCity(tester);

      final Text cityValue = tester.widget<Text>(
        find.byKey(const Key('search_city_value')),
      );
      expect(cityValue.data, 'Київ');

      // ── Submit → results screen fires the scoped search ─────────────────────
      // Not `pumpAndSettle()` — see [AppHarness.pumpUntilFound]'s doc comment
      // (FakeBackend's masters fixture always leaves a page pending on first
      // load, so the trailing indeterminate spinner never lets pumpAndSettle
      // observe quiescence).
      await tester.tap(find.byKey(const Key('search_show_masters_cta')));
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('results_list')),
      );

      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.clientSearchResults,
      );
      expect(find.byKey(const Key('client-search-results')), findsOneWidget);
      expect(find.byKey(const Key('results_list')), findsOneWidget);

      // ── Item 4 — the city scoped the wire AND the top-bar badge reflects it ─
      expect(fb.lastSearchSalonsCityId, 'city-kyiv');
      // The applied-filters chip ROW was replaced by an SVG funnel filter button
      // plus an active-filter «(N)» count badge.
      //
      // `SearchFilters.activeFilterCount` counts oblastId / cityId / districtId
      // as THREE SEPARATE facets (deliberate — pinned by
      // test/features/discovery/domain/search_filters_test.dart). The
      // three-field funnel means picking «Київ» necessarily sets BOTH oblastId
      // and cityId, so the badge reads «(2)», not «(1)». (The older "one facet
      // = the city" reading predates the funnel, when locality was a single
      // field.)
      expect(
        find.byKey(const Key('results_filter_button')),
        findsOneWidget,
        reason: 'the results top bar carries the SVG funnel filter button',
      );
      final Finder activeBadge = find.byKey(
        const Key('results_active_filter_count'),
      );
      expect(
        activeBadge,
        findsOneWidget,
        reason: 'a picked locality must surface the «(N)» count badge',
      );
      expect(
        tester.widget<Text>(activeBadge).data,
        '(2)',
        reason: 'region + city are two separate facets → «(2)»',
      );

      // ── The seeded salon card rendered (keyed by backend id) ────────────────
      expect(find.byKey(const Key('favorite_salon_salon-xyz')), findsOneWidget);

      // Item 5 — the salon price RANGE renders (priceMin 300, priceMax 1200).
      // CLIENT-rendered from l10n (`searchResultPriceRange`), NOT a raw backend
      // `priceDisplay` — it always carries the mobile client's own current
      // currency glyph («₴»), independent of the backend's formatting.
      expect(
        find.text('300–1200 ₴'),
        findsOneWidget,
        reason: 'salon-xyz has priceMin<priceMax → a «N–M ₴» range renders',
      );

      // Item 7 — the salon services preview line renders.
      final Finder servicesLine = find.byKey(const Key('salon_card_services'));
      expect(servicesLine, findsOneWidget);
      expect(
        tester.widget<Text>(servicesLine).data,
        'Манікюр · Стрижка',
        reason: 'the salon serviceNames join into the « · » preview line',
      );

      // Item 6 — two-line address: the authenticated caller gets the auth-gated
      // street + note, and the card renders BOTH the locality line (line 1) and
      // the full street·note line (line 2) together. Region/oblast is NOT in the
      // contract, so no oblast text ever appears.
      // formatLocality() joins the raw districtLabel/cityLabel with a
      // hard-coded ', ' and never touches AppLocalizations, so this renders
      // identically under EN — it is backend fixture data, not UI copy.
      //
      // TWO cards carry this exact line: the seeded master-aaa and salon-xyz
      // share the same city/district labels in the fake backend's fixtures, and
      // this flow renders both result kinds. Asserting `findsOneWidget` here
      // was simply miscounting the fixture, not detecting a missing line.
      expect(
        // i18n-finder-ok: locale-invariant backend data (see comment above)
        find.text('Печерський, Київ'),
        findsNWidgets(2),
        reason:
            'the two-line layout keeps the «district, city» locality line even '
            'when an auth-gated street line is also shown — on BOTH the seeded '
            'master and salon cards.',
      );
      // The mapper's _formatAddressLine() joins raw street/buildingNo/
      // locationNote with a hard-coded ', ' + ' · ' and never touches
      // AppLocalizations — backend fixture data, not UI copy.
      expect(
        // i18n-finder-ok: locale-invariant backend data (see comment above)
        find.text('вул. Хрещатик, 12 · 2 поверх'),
        findsOneWidget,
        reason:
            'an authenticated search carries the Bearer token, so the backend '
            'returns street/buildingNo/locationNote and the card folds them '
            'into the full «street, buildingNo · note» line.',
      );
      // The region/oblast is never rendered (it is not in the search contract).
      expect(find.textContaining('область'), findsNothing);

      expect(fb.getMasterCalls, 0);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  // ──────────────────────────────────────────────────────────────────────────
  // Phase 13.11–13.13 — E2E: per-service filter reaches the wire AND the matched
  // services surface on the result card.
  //
  // WHY THIS FLOW EXISTS
  // --------------------
  // The unit tier pins each piece in isolation: the repository emits a SORTED
  // repeated `serviceTypeSlugs` param (search_repository_transport_test.dart),
  // the mapper joins `matchedServiceNames` → `matchedServicesLine`
  // (search_repository_test.dart), and the card prefers the matched line
  // (master_result_card_test.dart). NONE of them proves the real journey: a
  // CLIENT opening the category drawer, tapping specific SERVICE chips, applying,
  // and the live SearchResultsNotifier → HttpSearchRepository → GET
  // /search/{masters,salons} carrying those exact slugs — then the rendered card
  // showing the backend's matched-service line built FROM those slugs.
  //
  // The fake backend echoes `matchedServiceNames` derived from whatever
  // `serviceTypeSlugs` it received, so the rendered line is NOT a fixture
  // constant — a broken wire (no slugs) would yield NO matched line (the master
  // row carries no generic serviceNames, so the line would be absent entirely).
  // The flow therefore asserts BOTH the captured wire param AND the rendered
  // line, locking the full chip → wire → response → card chain.
  //
  // Step 2.7 Rule 3b: the category rail + async service drawer + chip multi-select
  // + navigation + provider→repository + the exact repeated-param API contract +
  // the rendered matched-service card — the widget tier cannot prove this
  // composes end to end.
  // ──────────────────────────────────────────────────────────────────────────
  testWidgets(
    'CLIENT selects TWO service chips → both slugs reach BOTH endpoints AND the '
    'result card shows the matched-service line',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // ── Reach the search screen ─────────────────────────────────────────────
      await tester.tap(find.byKey(const Key('client-nav-search-center')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.clientSearch);

      // Before selecting a category the service drawer + count badge are absent.
      expect(find.byType(ServiceChipDrawer), findsNothing);
      expect(
        find.byKey(const Key('search_services_selected_count')),
        findsNothing,
      );

      // ── Select the NAILS category → the service-chip drawer reveals ─────────
      // `_CategorySection` sits below the fold at the flutter-tester's short,
      // wide Size(800, 600) — scroll it into view before tapping into it.
      await scrollFilterFieldIntoView(
        tester,
        const Key('search_service_type_NAILS'),
      );
      await tester.tap(find.byKey(const Key('search_service_type_NAILS')));
      await tester.pumpAndSettle();
      await scrollFilterFieldIntoView(
        tester,
        const Key('search_service_chip_CLASSIC_MANICURE'),
      );
      expect(find.byType(ServiceChipDrawer), findsOneWidget);
      // Both seeded NAILS service types render keyed chips (key = slug).
      expect(
        find.byKey(const Key('search_service_chip_CLASSIC_MANICURE')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('search_service_chip_GEL_MANICURE')),
        findsOneWidget,
      );

      // ── Select the FIRST service chip → the active-count badge appears ──────
      await tester.tap(
        find.byKey(const Key('search_service_chip_CLASSIC_MANICURE')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('search_services_selected_count')),
        findsOneWidget,
        reason: 'selecting one service must surface the active-count badge',
      );

      // ── Select the SECOND service chip (multi-select) ───────────────────────
      await tester.tap(
        find.byKey(const Key('search_service_chip_GEL_MANICURE')),
      );
      await tester.pumpAndSettle();
      // The badge persists with two services selected.
      expect(
        find.byKey(const Key('search_services_selected_count')),
        findsOneWidget,
      );

      // ── Apply → push /search/results, firing the scoped search ──────────────
      // Not `pumpAndSettle()` — see [AppHarness.pumpUntilFound]'s doc comment
      // (FakeBackend's masters fixture always leaves a page pending on first
      // load, so the trailing indeterminate spinner never lets pumpAndSettle
      // observe quiescence).
      await tester.tap(find.byKey(const Key('search_show_masters_cta')));
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('results_list')),
      );

      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.clientSearchResults,
      );
      expect(find.byKey(const Key('client-search-results')), findsOneWidget);

      // ── WIRE ASSERTION — BOTH selected slugs reached BOTH endpoints ─────────
      // A null/short list here means a chip selection never reached the request
      // (the per-service filter would be silently dropped).
      expect(
        fb.lastSearchMastersServiceTypeSlugs,
        isNotNull,
        reason: 'the selected service chips must reach /search/masters',
      );
      expect(
        fb.lastSearchMastersServiceTypeSlugs,
        containsAll(<String>['CLASSIC_MANICURE', 'GEL_MANICURE']),
        reason: 'both selected slugs must be carried (AND semantics)',
      );
      expect(fb.lastSearchMastersServiceTypeSlugs, hasLength(2));
      expect(
        fb.lastSearchSalonsServiceTypeSlugs,
        containsAll(<String>['CLASSIC_MANICURE', 'GEL_MANICURE']),
        reason: 'the salon endpoint must carry the same per-service filter',
      );

      // ── RENDER ASSERTION — the card shows the backend matched-service line ──
      // The fake echoed matchedServiceNames built from the slugs above; the
      // master row carries NO generic serviceNames, so a present line proves the
      // matched-service path (not a fallback) is what rendered.
      final Finder matchedLine = find.byKey(const Key('master_card_services'));
      expect(matchedLine, findsOneWidget);
      expect(
        tester.widget<Text>(matchedLine).data,
        'Класичний манікюр · Манікюр гель-лак',
        reason:
            'the card must surface the matched-service line derived from the '
            'two slugs it sent on the wire (not a fixture constant)',
      );

      expect(fb.getMasterCalls, 0);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  // ──────────────────────────────────────────────────────────────────────────
  // Phase 13.11 — E2E REGRESSION: switching category DROPS the prior service
  // selection (no stale cross-category slug on the wire).
  //
  // The per-service selection is scoped to the chosen category; the rail's
  // `_toggle` clears [SearchServiceSelectionController] on any category change,
  // and `_onShowMasters` snapshots the (now-empty) set. This flow proves the
  // whole chain: a CLIENT selects a NAILS service, then switches to BROWS, and
  // the applied search carries NO `serviceTypeSlugs` param — the stale
  // CLASSIC_MANICURE slug never reaches the request. The widget tier cannot
  // prove the rail-toggle → controller-clear → push-snapshot → wire composition.
  // ──────────────────────────────────────────────────────────────────────────
  testWidgets(
    'CLIENT switching category drops the prior service selection — no stale '
    'slug reaches the wire',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await tester.tap(find.byKey(const Key('client-nav-search-center')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.clientSearch);

      // ── Select NAILS + a NAILS service chip ─────────────────────────────────
      // `_CategorySection` sits below the fold at the flutter-tester's short,
      // wide Size(800, 600) — scroll it into view before tapping into it.
      await scrollFilterFieldIntoView(
        tester,
        const Key('search_service_type_NAILS'),
      );
      await tester.tap(find.byKey(const Key('search_service_type_NAILS')));
      await tester.pumpAndSettle();
      await scrollFilterFieldIntoView(
        tester,
        const Key('search_service_chip_CLASSIC_MANICURE'),
      );
      await tester.tap(
        find.byKey(const Key('search_service_chip_CLASSIC_MANICURE')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('search_services_selected_count')),
        findsOneWidget,
      );

      // ── Switch the category to BROWS → the prior selection must clear ───────
      await scrollFilterFieldIntoView(
        tester,
        const Key('search_service_type_BROWS'),
      );
      await tester.tap(find.byKey(const Key('search_service_type_BROWS')));
      await tester.pumpAndSettle();

      // The drawer repopulated with the BROWS service type; the NAILS chip is
      // gone and the active-count badge collapsed (selection cleared).
      await scrollFilterFieldIntoView(
        tester,
        const Key('search_service_chip_BROW_CORRECTION'),
      );
      expect(
        find.byKey(const Key('search_service_chip_BROW_CORRECTION')),
        findsOneWidget,
        reason: 'the drawer must repopulate with the new category services',
      );
      expect(
        find.byKey(const Key('search_service_chip_CLASSIC_MANICURE')),
        findsNothing,
        reason: 'the prior category service chip must no longer be offered',
      );
      expect(
        find.byKey(const Key('search_services_selected_count')),
        findsNothing,
        reason: 'switching category clears the selection → the badge collapses',
      );

      // ── Apply with NO BROWS service picked → NO serviceTypeSlugs on the wire ─
      // Not `pumpAndSettle()` — see [AppHarness.pumpUntilFound]'s doc comment
      // (FakeBackend's masters fixture always leaves a page pending on first
      // load, so the trailing indeterminate spinner never lets pumpAndSettle
      // observe quiescence).
      await tester.tap(find.byKey(const Key('search_show_masters_cta')));
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('results_list')),
      );

      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.clientSearchResults,
      );
      expect(find.byKey(const Key('client-search-results')), findsOneWidget);

      // The stale CLASSIC_MANICURE slug never reached the request — the param is
      // omitted entirely on BOTH endpoints.
      expect(
        fb.lastSearchMastersServiceTypeSlugs,
        isNull,
        reason:
            'a category switch must drop the prior service slug — no '
            'serviceTypeSlugs param may reach /search/masters',
      );
      expect(fb.lastSearchSalonsServiceTypeSlugs, isNull);

      expect(fb.getMasterCalls, 0);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  // ──────────────────────────────────────────────────────────────────────────
  // Search-page saved-location PREFILL — E2E: a CLIENT with a saved profile
  // location lands on Пошук with the locality filter ALREADY pre-filled from
  // GET /users/me; clearing it then re-entering the tab keeps the edit (no
  // re-seed).
  //
  // WHY THIS FLOW EXISTS
  // --------------------
  // The widget tier (search_filters_profile_prefill_test.dart) proves the
  // controller's prefill + one-shot + anti-clobber guards in isolation with a
  // STUBBED clientEditProfileProvider. It cannot prove the REAL chain: the CLIENT
  // logging in, the screen's initState firing prefillFromProfileIfNeeded(), the
  // real ClientEditProfile → GET /users/me carrying oblastId/cityId, the real
  // oblastListProvider/cityListProvider resolving the saved ids to names, and the
  // locality row rendering the saved city on FIRST open. This flow drives exactly
  // that against the fake backend's seeded taxonomy (oblast-kyiv «Київська» →
  // city-kyiv «Київ», no districts), with the profile's saved location injected
  // via the FakeBackend's mutable client state.
  //
  // Step 2.7 Rule 3b: this is the real user journey (auth → screen → initState →
  // provider→repository (/users/me) → taxonomy resolve → rendered locality row +
  // a branch-switch keepAlive survival) the widget tier cannot prove end to end.
  // ──────────────────────────────────────────────────────────────────────────
  testWidgets(
    'CLIENT with a saved location opens Пошук → the city filter shows the saved '
    'city on first open; clearing it then re-entering the tab keeps the edit',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        // Saved profile location: Київська обл. → Київ (no district — city-kyiv
        // has hasDistricts:false). GET /users/me echoes these so the prefill can
        // resolve the saved cascade.
        ..clientOblastId = 'oblast-kyiv'
        ..clientOblastName = 'Київська'
        ..clientCityId = 'city-kyiv'
        ..clientCityName = 'Київ';

      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.clientHome);

      // ── Open the search tab → the prefill fires from initState ──────────────
      await tester.tap(find.byKey(const Key('client-nav-search-center')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.clientSearch);
      expect(find.byKey(const Key('client-branch-search')), findsOneWidget);

      // ── PREFILL ASSERTION — the saved locality is rendered on FIRST open ────
      // No tap on the picker happened; the city/region rows carry the saved
      // names because the prefill resolved them through the REAL /users/me +
      // oblast/city taxonomy chain. A broken prefill would leave the placeholder.
      final Text cityValue = tester.widget<Text>(
        find.byKey(const Key('search_city_value')),
      );
      expect(
        cityValue.data,
        'Київ',
        reason: 'the saved-profile city must pre-fill the city filter on open',
      );
      final Text regionValue = tester.widget<Text>(
        find.byKey(const Key('search_region_value')),
      );
      expect(
        regionValue.data,
        'Київська',
        reason: 'the saved-profile oblast must pre-fill the region filter',
      );
      // A pre-filled city is a searchable scope → the CTA is enabled.
      expect(
        tester
            .widget<NeumorphicButton>(
              find.byKey(const Key('search_show_masters_cta')),
            )
            .onPressed,
        isNotNull,
        reason: 'a pre-filled city makes the search CTA enabled',
      );
      // The saved location came off GET /users/me (the prefill source).
      expect(
        fb.getMeCalls,
        greaterThanOrEqualTo(1),
        reason: 'the prefill must read the profile via GET /users/me',
      );

      // ── EDIT — clear the region (cascade-clears the city) ───────────────────
      await tester.tap(find.byKey(const Key('search_region_value_clear')));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
      Text cityRowText() =>
          tester.widget<Text>(find.byKey(const Key('search_city_value')));
      expect(
        cityRowText().data,
        l10n.searchCityPlaceholder,
        reason:
            'clearing the region cascade-clears the city back to placeholder',
      );

      // ── Re-enter the tab (Home → Search) → the edit MUST persist ───────────
      // The keepAlive filter/labels controllers survive a branch switch, and the
      // one-shot guard prevents the prefill from re-seeding the profile location
      // over the user's clear. So the city must STILL be the placeholder — never
      // re-seeded back to «Київ».
      await tester.tap(find.byKey(const Key('client-nav-tile-0')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.clientHome);

      await tester.tap(find.byKey(const Key('client-nav-search-center')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.clientSearch);

      expect(
        cityRowText().data,
        l10n.searchCityPlaceholder,
        reason:
            're-entering the search tab must NOT re-seed the saved location '
            'over a manual clear (one-shot + anti-clobber guard)',
      );
      expect(
        cityRowText().data,
        isNot('Київ'),
        reason:
            "the user's cleared edit must not be reverted to the profile city",
      );

      expect(fb.getMasterCalls, 0);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  // ──────────────────────────────────────────────────────────────────────────
  // Search-page saved-location PREFILL — E2E REGRESSION: a mid-session profile
  // locality CHANGE (no logout) reaches Пошук on the very next open.
  //
  // WHY THIS FLOW EXISTS
  // --------------------
  // The reported bug: a CLIENT who changed their saved locality on the
  // Location edit screen kept seeing the OLD city on Пошук until a full app
  // restart. Root cause (search_filters_controller.dart): a one-shot
  // `_seededFromProfile` latch that seeded the filter at most once per session
  // and never re-checked the profile again. The fix replaced it with
  // `_userTouchedLocality` (set ONLY by a manual pick) plus
  // `_lastSeeded{Oblast,City,District}Id` tracking, so
  // `prefillFromProfileIfNeeded()` re-reads the profile on EVERY call and
  // re-seeds whenever it drifts from what was last seeded.
  //
  // The prior flow in this file (above) proves the FIRST-open prefill + the
  // anti-clobber guard when the CLIENT edits the locality through Пошук's OWN
  // picker. It does NOT prove the actual reported journey: the CLIENT changes
  // their locality on a DIFFERENT screen (Location edit, reached via the
  // profile settings hub) and comes back to Пошук — the widget/unit tiers
  // (search_filters_profile_prefill_test.dart) call
  // `prefillFromProfileIfNeeded()` directly against a stubbed profile
  // provider; they cannot prove the real chain: real navigation to the
  // settings hub, the real Location edit screen's locality cascade + Save
  // (PATCH /users/me + the screen's own `ref.invalidate(...)` calls), and the
  // real Пошук screen's `initState` re-firing the prefill against the
  // now-current profile — all inside ONE authenticated session.
  //
  // Step 2.7 Rule 3b: screen + navigation + provider→repository (PATCH + GET
  // /users/me) + the keepAlive controller's cross-screen re-sync — the
  // widget/unit tier cannot prove this composes end to end.
  // ──────────────────────────────────────────────────────────────────────────
  testWidgets(
    'CLIENT changes their saved city on the Location edit screen mid-session '
    '(no logout) → returning to Пошук shows the NEW city, not the stale one',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        // Saved profile location starts at Київ — the ORIGINAL locality that
        // must NOT survive the in-session edit below.
        ..clientOblastId = 'oblast-kyiv'
        ..clientOblastName = 'Київська'
        ..clientCityId = 'city-kyiv'
        ..clientCityName = 'Київ';

      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.clientHome);

      // ── 1. Open Пошук → the prefill shows the ORIGINAL saved city ──────────
      await tester.tap(find.byKey(const Key('client-nav-search-center')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.clientSearch);
      expect(
        tester.widget<Text>(find.byKey(const Key('search_city_value'))).data,
        'Київ',
        reason: 'the first open must prefill from the saved Київ',
      );

      // ── 2. Home → burger → settings hub → Location edit ────────────────────
      await tester.tap(find.byKey(const Key('client-nav-tile-0')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.clientHome);

      await tester.tap(find.byKey(const Key('btn-menu-client')));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      AppHarness.expectLocation(router, RouteNames.clientMenu);

      await tester.tap(find.byKey(const Key('row-location')));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      AppHarness.expectLocation(router, RouteNames.clientEditLocation);

      // ── 3. Change the CITY to Львів (same region) → Save ───────────────────
      await tester.tap(find.byKey(const Key('locality_row_city')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.tap(
        find.byKey(const ValueKey<String>('locality_picker_tile_city-lviv')),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await tester.ensureVisible(find.byKey(const Key('btn-save-location')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-save-location')));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      AppHarness.expectLocation(router, RouteNames.clientHome);
      expect(
        fb.clientCityId,
        'city-lviv',
        reason: 'the location save must persist the new city',
      );

      // ── 4. Re-enter Пошук in the SAME session (no logout) ──────────────────
      // THE REGRESSION ASSERTION. Pre-fix, the one-shot `_seededFromProfile`
      // latch would already be true from step 1 and never re-arm, so this
      // second open would still render the STALE Київ — exactly the reported
      // bug (fixed only by a full app restart, which re-creates the provider
      // graph from scratch).
      await tester.tap(find.byKey(const Key('client-nav-search-center')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.clientSearch);

      expect(
        tester.widget<Text>(find.byKey(const Key('search_city_value'))).data,
        'Львів',
        reason:
            'a mid-session profile locality change must reach Пошук on the '
            'very next open — no app restart required',
      );

      expect(fb.getMasterCalls, 0);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  // ──────────────────────────────────────────────────────────────────────────
  // «Скинути фільтри» (Clear filters) — E2E: a CLIENT applies a filter then
  // taps the reset link; the non-location filter clears but the prefilled saved
  // location SURVIVES.
  //
  // WHY THIS FLOW EXISTS
  // --------------------
  // The controller tier proves clearFilters() preserves the locality ids in
  // isolation; the widget tier proves the reset link's visibility + the
  // location-preservation against a STUBBED prefill. Neither proves the REAL
  // journey: a CLIENT with a saved profile location logging in, the screen's
  // initState firing prefillFromProfileIfNeeded() against the live GET /users/me
  // + oblast/city taxonomy so the row renders «Київ» on open, then applying a
  // category and tapping «Скинути фільтри» — with the keepAlive controllers
  // driving the real rebuild — and the locality row STILL showing the saved
  // «Київ» afterward (never re-resolved, never wiped).
  //
  // Step 2.7 Rule 3b: screen + navigation + provider→repository (/users/me +
  // taxonomy) + the reset action + the prefill-preservation contract — the
  // widget/unit tier cannot prove this composes end to end.
  // ──────────────────────────────────────────────────────────────────────────
  testWidgets(
    'CLIENT applies a category then taps «Скинути фільтри» → the filter clears '
    'but the prefilled saved location survives',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        // Saved profile location: Київська обл. → Київ (city-kyiv has
        // hasDistricts:false → no district step). GET /users/me echoes these so
        // the prefill resolves the saved cascade on first open.
        ..clientOblastId = 'oblast-kyiv'
        ..clientOblastName = 'Київська'
        ..clientCityId = 'city-kyiv'
        ..clientCityName = 'Київ';

      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.clientHome);

      // ── Open Пошук → the prefill renders the saved city on first open ───────
      await tester.tap(find.byKey(const Key('client-nav-search-center')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.clientSearch);

      expect(
        tester.widget<Text>(find.byKey(const Key('search_city_value'))).data,
        'Київ',
        reason: 'the saved-profile city must prefill the locality row on open',
      );
      // With only the prefilled location, the reset link is hidden.
      expect(
        find.byKey(const Key('search_clear_filters')),
        findsNothing,
        reason: 'a location-only state never surfaces «Скинути фільтри»',
      );

      // ── Apply a category (NAILS) → the drawer opens + the reset link shows ──
      // `_CategorySection` is below the fold at the flutter-tester's
      // Size(800, 600) (query field + three-field locality block + the sticky
      // footer eat the budget), and the body's `SliverChildListDelegate` never
      // inflates it un-scrolled — an un-scrolled tap throws `Bad state: No
      // element`. See [scrollFilterFieldIntoView].
      await scrollFilterFieldIntoView(
        tester,
        const Key('search_service_type_NAILS'),
      );
      await tester.tap(find.byKey(const Key('search_service_type_NAILS')));
      await tester.pumpAndSettle();
      expect(find.byType(ServiceChipDrawer), findsOneWidget);
      expect(
        find.byKey(const Key('search_clear_filters')),
        findsOneWidget,
        reason: 'an active category must surface the reset link',
      );

      // ── Tap «Скинути фільтри» ────────────────────────────────────────────────
      await tester.ensureVisible(find.byKey(const Key('search_clear_filters')));
      await tester.tap(find.byKey(const Key('search_clear_filters')));
      await tester.pumpAndSettle();

      // The category cleared → the drawer collapses and the reset link hides.
      expect(
        find.byType(ServiceChipDrawer),
        findsNothing,
        reason: 'clearing the category collapses its service-chip drawer',
      );
      expect(find.byKey(const Key('search_clear_filters')), findsNothing);

      // ── REGRESSION — the prefilled location is UNTOUCHED ────────────────────
      // Scrolling down to the category rail pushed the locality rows out of
      // the viewport, so they are no longer inflated — scroll BACK to them
      // before reading their Text widgets (the same
      // `SliverChildListDelegate` inflation rule that required the scroll
      // down, applied in reverse).
      await scrollFilterFieldIntoView(tester, const Key('search_city_value'));
      expect(
        tester.widget<Text>(find.byKey(const Key('search_city_value'))).data,
        'Київ',
        reason: 'clearing filters must never wipe the prefilled saved location',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('search_region_value'))).data,
        'Київська',
        reason: 'the prefilled region survives the clear too',
      );
      // The pre-filled city keeps the search CTA enabled (a searchable scope
      // remains after the clear).
      expect(
        tester
            .widget<NeumorphicButton>(
              find.byKey(const Key('search_show_masters_cta')),
            )
            .onPressed,
        isNotNull,
        reason: 'a preserved city means the CTA stays enabled after a clear',
      );

      expect(fb.getMasterCalls, 0);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
