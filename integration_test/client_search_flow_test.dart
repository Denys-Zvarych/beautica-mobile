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
import 'package:beautica_mobile/features/discovery/presentation/widgets/service_chip_drawer.dart';
import 'package:beautica_mobile/features/shell/presentation/branch_placeholders.dart';
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

  /// Reads the SearchFilters the results placeholder received via `extra`.
  SearchFilters? receivedFilters(WidgetTester tester) {
    final ClientSearchResultsPlaceholderScreen results = tester
        .widget<ClientSearchResultsPlaceholderScreen>(
          find.byType(ClientSearchResultsPlaceholderScreen),
        );
    return results.filters;
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
      expect(
        find.byKey(const Key('search_all_categories_tile')),
        findsOneWidget,
        reason: 'the rail ends in the «Всі категорії» more-tile',
      );
      expect(find.byKey(const Key('search_price_slider')), findsOneWidget);
      expect(find.byKey(const Key('search_show_masters_cta')), findsOneWidget);

      // ── Pick a city through the REAL locality cascade ─────────────────────
      // Tap the city row → oblast sheet → tap «Київська» → city sheet → «Київ».
      await tester.tap(find.byKey(const Key('search_city_value')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('locality_picker_tile_oblast-kyiv')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('locality_picker_tile_city-kyiv')),
      );
      await tester.pumpAndSettle();

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
}
