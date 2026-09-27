// Phase 352 — E2E: «Пошук» suggestion list, place-scoped end to end.
//
// WHY THIS FILE EXISTS
// --------------------
// The widget tier (search_filters_screen_test.dart) and the provider tier
// (search_suggestions_provider_test.dart) each prove the pipeline against a
// FAKE repository. Neither exercises the real journey: a CLIENT picking a
// settlement through the real autocomplete, typing a term, waiting out the
// real debounce against a real (fake-backend) HTTP round trip, tapping a
// SERVICE suggestion, landing on real results, and — the core of Phase 352's
// Open Q2 — the list refetching when the chosen settlement changes while the
// term is still typed.
//
// LOCALITY-AWARE FAKE: `FakeBackend`'s `/api/v1/search/suggestions` handler
// (Phase 352) offers «Нарощення нігтів» (SERVICE, category NAILS, slug
// `nail-extension`) for `q` containing «нар» in settlement `city-kyiv` and
// nationally (no place chosen) — ABSENT for `city-lviv`. That is what proves
// the refetch end to end: the SAME typed term produces different rows
// depending on which settlement is active.
//
// PUMPING POLICY: `pump(kSearchSuggestionDebounce)` before every assertion
// that depends on the server layer, per the phase doc — `pumpAndSettle` fires
// no `Timer` on its own and would measure the pre-debounce state. Once the
// results screen is mounted, `pumpAndSettle` hangs (measured by sibling
// search E2E files) — `settleResults` below is the same bounded-pump
// workaround `client_search_query_shrink_flow_test.dart` uses.
//
// KEY POLICY: every interaction is key-based; «Нарощення нігтів» is asserted
// through the suggestion row's content-derived key
// (`search_suggestion_service_nail-extension`), not its Ukrainian text.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/discovery/domain/search_filters.dart';
import 'package:beautica_mobile/features/discovery/presentation/search_results_screen.dart';
import 'package:beautica_mobile/features/discovery/presentation/search_suggestions_provider.dart';
import 'package:beautica_mobile/features/discovery/presentation/state/search_filters_controller.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/master_result_card.dart';
import 'package:beautica_mobile/features/shell/presentation/client_shell.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

const Key _queryField = Key('search_query_field');
const Key _suggestionList = Key('search_suggestion_list');
const Key _nailServiceRow = Key('search_suggestion_service_nail-extension');
const Key _settlementField = Key('search_city_value');
const Key _settlementClear = Key('select-field-clear');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  /// Bounded replacement for `pumpAndSettle` while a results screen is
  /// mounted (measured hang — see `client_search_query_shrink_flow_test.dart`
  /// header).
  Future<void> settleResults(WidgetTester tester) async {
    for (int i = 0; i < 12; i++) {
      // fixed-wait-ok: pumpAndSettle hangs on the results-screen subtree.
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// Advances past the suggestion debounce and lets the (fake-backend) fetch
  /// resolve. Load-bearing: `pumpAndSettle` alone fires no `Timer`.
  Future<void> settleSuggestions(WidgetTester tester) async {
    await tester.pump(kSearchSuggestionDebounce);
    await tester.pumpAndSettle();
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(ClientShell)));

  SearchFilters? receivedFilters(WidgetTester tester) {
    final SearchResultsScreen results = tester.widget<SearchResultsScreen>(
      find.byType(SearchResultsScreen),
    );
    return results.initialFilters;
  }

  testWidgets(
    'place-scoped: pick A, type «нар», tap the SERVICE row → empty box + '
    'chip selected; switching to B refetches and the row disappears; '
    'clearing the place restores the national row',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.client);
      // fixed-wait-ok: real-async app boot, no single pump-until condition.
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await tester.tap(find.byKey(const Key('client-nav-search-center')));
      // fixed-wait-ok: shell-branch switch fans out to several fetches.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.clientSearch);

      // ── (1) Select settlement A («Київ») ────────────────────────────────
      await AppHarness.scrollFilterFieldIntoView(tester, _settlementField);
      await AppHarness.pickSettlement(
        tester,
        'city-kyiv',
        fieldKey: _settlementField,
      );

      // Type «нар» — a place is chosen, so NO local row before the server
      // answers (D2 — falsifies the debounce: without this explicit pump the
      // service-row assertion below would be vacuous).
      await AppHarness.scrollFilterFieldIntoView(tester, _queryField);
      await tester.enterText(find.byKey(_queryField), 'нар');
      await tester.pump();
      expect(
        find.byKey(_suggestionList),
        findsNothing,
        reason: 'place chosen → no local rows until the server answers',
      );

      await settleSuggestions(tester);
      expect(find.byKey(_nailServiceRow), findsOneWidget);
      expect(fb.lastSearchSuggestionsCityId, 'city-kyiv');
      final int callsForA = fb.searchSuggestionsCalls;
      expect(callsForA, greaterThan(0));

      // Tap the SERVICE row — the same push «Показати майстрів» would do.
      await tester.tap(find.byKey(_nailServiceRow), warnIfMissed: false);
      await settleResults(tester);

      expect(
        find.byType(SearchResultsScreen),
        findsOneWidget,
        reason: 'a suggestion tap must reach the results screen',
      );
      final SearchFilters? filters = receivedFilters(tester);
      expect(filters?.categoryKey, 'NAILS');
      expect(filters?.serviceTypeSlugs, contains('nail-extension'));
      expect(
        filters?.query,
        isNull,
        reason: 'Open Q1 — SERVICE filters by slug, never free text',
      );
      expect(filters?.cityId, 'city-kyiv');
      expect(
        find.byType(MasterResultCard),
        findsWidgets,
        reason: 'the tap must reach ≥1 result, same as any other search',
      );

      // ── Back on «Пошук»: chip selected, box empty, A still set ──────────
      await tester.tap(find.byKey(const Key('results_back_button')));
      await settleResults(tester);
      expect(find.byType(SearchResultsScreen), findsNothing);
      AppHarness.expectLocation(router, RouteNames.clientSearch);

      final container = containerOf(tester);
      expect(
        container.read(searchFiltersControllerProvider).categoryKey,
        'NAILS',
        reason: 'the rail shows the category the suggestion carried',
      );
      expect(
        container.read(searchServiceSelectionControllerProvider),
        contains('nail-extension'),
        reason: 'the chip drawer shows the service selected',
      );
      expect(
        tester.widget<TextField>(find.byKey(_queryField)).controller!.text,
        isEmpty,
        reason: 'Open Q1 — the box is left empty',
      );
      expect(
        container.read(searchFiltersControllerProvider).cityId,
        'city-kyiv',
        reason: 'the place the suggestion was scoped to is unchanged',
      );

      // ── (2) Retype «нар», then switch «Населений пункт» to B ────────────
      await AppHarness.scrollFilterFieldIntoView(tester, _queryField);
      await tester.enterText(find.byKey(_queryField), 'нар');
      await settleSuggestions(tester);
      expect(
        find.byKey(_nailServiceRow),
        findsOneWidget,
        reason: 'still settlement A — the row reappears',
      );

      await AppHarness.scrollFilterFieldIntoView(tester, _settlementField);
      await AppHarness.pickSettlement(
        tester,
        'city-lviv',
        fieldKey: _settlementField,
      );
      await settleSuggestions(tester);

      expect(
        find.byKey(_nailServiceRow),
        findsNothing,
        reason:
            'nail-extension is offered only in city-kyiv — the refetch for '
            'city-lviv must drop it (Open Q2 proven end-to-end)',
      );
      expect(fb.lastSearchSuggestionsCityId, 'city-lviv');
      expect(
        fb.searchSuggestionsCalls,
        greaterThan(callsForA),
        reason: 'the place change must issue a NEW request, not reuse A’s',
      );

      // ── (3) Clear the place → national → the row is back ────────────────
      await tester.tap(find.byKey(_settlementClear));
      await settleSuggestions(tester);

      expect(
        find.byKey(_nailServiceRow),
        findsOneWidget,
        reason: 'with no place chosen the national list offers it again',
      );
      expect(fb.lastSearchSuggestionsCityId, isNull);
    },
  );

  testWidgets('CATEGORY suggestion tap: free-text search runs with the label; '
      'results shown (national — the local instant row AND the fake '
      'backend’s server answer agree on «Брови», so the assertion holds no '
      'matter when the debounce lands)', (tester) async {
    final fb = FakeBackend()..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(tester, fb);

    await AppHarness.loginAs(tester, fb, UserRole.client);
    // fixed-wait-ok: real-async app boot, no single pump-until condition.
    await tester.pumpAndSettle(const Duration(seconds: 1));

    await tester.tap(find.byKey(const Key('client-nav-search-center')));
    // fixed-wait-ok: shell-branch switch fans out to several fetches.
    await tester.pumpAndSettle(const Duration(seconds: 1));
    AppHarness.expectLocation(router, RouteNames.clientSearch);

    // No settlement chosen — national — so «Брови» (an approved platform
    // category, seeded by the fake backend's
    // `/service-categories/approved`) renders as an INSTANT local row.
    await AppHarness.scrollFilterFieldIntoView(tester, _queryField);
    await tester.enterText(find.byKey(_queryField), 'бров');
    await tester.pump();

    const Key browsCategoryRow = Key('search_suggestion_category_BROWS');
    expect(
      find.byKey(browsCategoryRow),
      findsOneWidget,
      reason: 'the local matcher renders it before any debounce fires',
    );

    // Settle past the debounce too — the fake backend's own answer for
    // «бров» echoes the SAME category (see fake_backend.dart), so the row
    // is still there either way; this also proves the server round trip
    // itself doesn't wipe it.
    await settleSuggestions(tester);
    expect(find.byKey(browsCategoryRow), findsOneWidget);

    await AppHarness.scrollFilterFieldIntoView(tester, browsCategoryRow);
    await tester.tap(find.byKey(browsCategoryRow), warnIfMissed: false);
    await settleResults(tester);

    expect(
      find.byType(SearchResultsScreen),
      findsOneWidget,
      reason:
          'a CATEGORY tap must reach the results screen, same as a '
          'typed label + «Показати майстрів» would',
    );
    final SearchFilters? filters = receivedFilters(tester);
    expect(
      filters?.query,
      'Брови',
      reason: 'free text resolves the category label server-side',
    );
    expect(
      filters?.categoryKey,
      isNull,
      reason: 'CATEGORY search runs as free text, not a rail filter',
    );
    expect(
      find.byType(MasterResultCard),
      findsWidgets,
      reason: 'the tap must reach ≥1 result, same as any other search',
    );

    await tester.tap(find.byKey(const Key('results_back_button')));
    await settleResults(tester);
    expect(
      tester.widget<TextField>(find.byKey(_queryField)).controller!.text,
      'Брови',
      reason:
          'a CATEGORY tap leaves the label IN the field (unlike '
          'Open Q1’s SERVICE tap)',
    );
  });

  testWidgets(
    'place-scoped SERVICE tap clears a DIFFERENT previously-selected rail '
    'category + its chip (Q2), while the chosen settlement survives the tap',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.client);
      // fixed-wait-ok: real-async app boot, no single pump-until condition.
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await tester.tap(find.byKey(const Key('client-nav-search-center')));
      // fixed-wait-ok: shell-branch switch fans out to several fetches.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.clientSearch);

      await AppHarness.scrollFilterFieldIntoView(tester, _settlementField);
      await AppHarness.pickSettlement(
        tester,
        'city-kyiv',
        fieldKey: _settlementField,
      );

      // ── Select a DIFFERENT rail category + its chip FIRST ────────────────
      // (BROWS / BROW_CORRECTION — the suggestion below is NAILS /
      // nail-extension, so a same-category fixture could not tell "cleared"
      // from "untouched" apart.)
      await AppHarness.scrollFilterFieldIntoView(
        tester,
        const Key('search_service_type_BROWS'),
      );
      await tester.tap(find.byKey(const Key('search_service_type_BROWS')));
      await tester.pumpAndSettle();
      await AppHarness.scrollFilterFieldIntoView(
        tester,
        const Key('search_service_chip_BROW_CORRECTION'),
      );
      await tester.tap(
        find.byKey(const Key('search_service_chip_BROW_CORRECTION')),
      );
      await tester.pumpAndSettle();

      final container = containerOf(tester);
      expect(
        container.read(searchFiltersControllerProvider).categoryKey,
        'BROWS',
        reason: 'sanity: the prior category really is selected',
      );
      expect(
        container.read(searchServiceSelectionControllerProvider),
        contains('BROW_CORRECTION'),
        reason: 'sanity: the prior chip really is selected',
      );

      // ── Type «нар» (place chosen: city-kyiv offers nail-extension) ──────
      await AppHarness.scrollFilterFieldIntoView(tester, _queryField);
      await tester.enterText(find.byKey(_queryField), 'нар');
      await tester.pump();
      expect(
        find.byKey(_suggestionList),
        findsNothing,
        reason: 'place chosen → no local rows until the server answers',
      );

      await settleSuggestions(tester);
      expect(find.byKey(_nailServiceRow), findsOneWidget);

      await tester.tap(find.byKey(_nailServiceRow), warnIfMissed: false);
      await settleResults(tester);

      expect(find.byType(SearchResultsScreen), findsOneWidget);
      final SearchFilters? filters = receivedFilters(tester);
      expect(filters?.categoryKey, 'NAILS');
      expect(filters?.serviceTypeSlugs, contains('nail-extension'));
      expect(
        filters?.serviceTypeSlugs,
        isNot(contains('BROW_CORRECTION')),
        reason:
            'Q2 — the prior category’s slug must not leak onto the '
            'search that replaced it',
      );
      expect(
        filters?.cityId,
        'city-kyiv',
        reason: 'the settlement chosen before the tap must survive it',
      );
      expect(find.byType(MasterResultCard), findsWidgets);

      // ── Back on «Пошук»: BROWS + its chip are gone; NAILS + its chip are ─
      // ── selected; the settlement is unchanged ────────────────────────────
      await tester.tap(find.byKey(const Key('results_back_button')));
      await settleResults(tester);
      AppHarness.expectLocation(router, RouteNames.clientSearch);

      expect(
        container.read(searchFiltersControllerProvider).categoryKey,
        'NAILS',
        reason:
            'Q2 — the tap must clear BROWS and select the tapped '
            'suggestion’s own category',
      );
      expect(
        container.read(searchServiceSelectionControllerProvider),
        <String>{'nail-extension'},
        reason:
            'Q2 — BROW_CORRECTION must be gone, leaving ONLY the '
            'suggestion’s own slug',
      );
      expect(
        container.read(searchFiltersControllerProvider).cityId,
        'city-kyiv',
        reason: 'the settlement must survive the category swap',
      );
    },
  );
}
