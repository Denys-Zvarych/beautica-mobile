// Search-page saved-location PREFILL — E2E REGRESSION: a mid-session NAME edit
// (which fires `refreshUser()`) must NOT wipe the prefilled search locality.
//
// THE REPORTED BUG
// ----------------
// A CLIENT with a saved profile location opens Пошук → the locality filter is
// pre-filled from GET /users/me (e.g. «Київ»). They then edit their name+surname
// on the Особисті дані screen and Save. That save calls
// `authProvider.notifier.refreshUser()`, which emits a NEW `Authenticated`
// session — SAME user id, changed name, unchanged locality. Before the fix, the
// three search controllers `ref.watch(authProvider)`ed the WHOLE provider, so
// that same-user emission re-ran `build()` and reset the keepAlive filter to
// `const SearchFilters()` — WIPING the seeded locality. Because the Пошук screen
// is kept alive in the shell's `StatefulShellRoute.indexedStack`, its one-shot
// `initState` prefill never re-fired, so the location field stayed empty until a
// full app restart.
//
// THE FIX (search_filters_controller.dart)
// ----------------------------------------
// All three controllers narrow the watch to
// `authProvider.select((s) => settled Authenticated user id)`, so `build()`
// re-runs ONLY when the SETTLED user id changes (login / logout / account swap).
// A same-user re-emission (a name/phone edit) no longer resets the seed; a
// genuine account swap still does.
//
// WHY THIS FLOW EXISTS (Step 2.7 Rule 3b)
// ---------------------------------------
// The widget/unit tier (search_filters_profile_prefill_test.dart) pins the
// controller-level survival by emitting the same-user refresh directly on a
// keepAlive controller. It CANNOT prove the real reported journey: a CLIENT
// logging in, opening Пошук (real initState prefill → GET /users/me → taxonomy
// resolve → rendered «Київ»), navigating through the real burger → settings hub
// → Особисті дані, editing the name, Saving through the REAL
// ClientProfileRepository (PATCH /users/me) which then calls the REAL
// `refreshUser()` (GET /users/me → new Authenticated), and the REAL keepAlive
// SearchFiltersController surviving that emission while the Пошук branch stays
// alive in the IndexedStack. This flow drives exactly that against the fake
// backend's seeded taxonomy (oblast-kyiv «Київська» → city-kyiv «Київ»).
//
// THE DISCRIMINATING ASSERTION is read straight off the live root
// ProviderContainer immediately AFTER the name Save (before re-entering the
// search tab): the keepAlive SearchFiltersController.cityId must STILL be
// 'city-kyiv'. Pre-fix that read returns null (build() re-ran on the refreshUser
// emission and reset the filter); post-fix it survives. The subsequent search-tab
// re-entry then asserts the user-visible outcome (the city row still renders «Київ»).
//
// NATIVE TIER: NONE NEEDED. This journey is in-app Flutter widgets + HTTP only
// (no OS permission / deep-link / FCM / biometric / WebView surface), so a
// fake-backed integration_test flow is the correct and sufficient end-to-end tier.
//
// EXECUTION (ARCHITECTURE-mobile §12): integration_test/ is LOCAL/CI-emulator
// only. Run standalone with:
//   flutter test integration_test/search_prefill_survives_name_edit_flow_test.dart -d <emulator>
// or via the split CI aggregators (all_tests_part1.dart) / the full
// all_tests.dart entrypoint.
//
// KEY POLICY (from AppHarness): all TAPS use key-based finders; raw Ukrainian
// text appears in CONTENT ASSERTIONS only.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/discovery/presentation/state/search_filters_controller.dart';
import 'package:beautica_mobile/features/shell/presentation/client_shell.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      reason: 'Expected router to be at $expected, got $current',
    );
  }

  /// Reads the seeded city off the live keepAlive [SearchFiltersController] via
  /// the root [ProviderContainer] (reachable from the always-mounted
  /// [ClientShell]). Reading a keepAlive provider does not re-seed it.
  String? seededCityId(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(ClientShell)),
  ).read(searchFiltersControllerProvider).cityId;

  String? seededCityLabel(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(ClientShell)),
  ).read(searchFilterLabelsControllerProvider).cityName;

  testWidgets(
    'CLIENT with a saved location edits their name+surname mid-session '
    '(refreshUser) → the prefilled search locality SURVIVES (is not wiped)',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        // Saved profile location: Київська обл. → Київ (city-kyiv has
        // hasDistricts:false → no district step). GET /users/me echoes these so
        // the prefill resolves the saved cascade on first Пошук open.
        ..clientOblastId = 'oblast-kyiv'
        ..clientOblastName = 'Київська'
        ..clientCityId = 'city-kyiv'
        ..clientCityName = 'Київ';

      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expectLocation(router, RouteNames.clientHome);

      // ── 1. Open Пошук → the initState prefill renders the saved city ────────
      await tester.tap(find.byKey(const Key('client-nav-search-center')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expectLocation(router, RouteNames.clientSearch);
      expect(find.byKey(const Key('client-branch-search')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('search_city_value'))).data,
        'Київ',
        reason: 'the saved-profile city must prefill the locality row on open',
      );
      // The keepAlive controller now holds the resolved city id.
      expect(
        seededCityId(tester),
        'city-kyiv',
        reason: 'the prefill must seed the keepAlive SearchFiltersController',
      );

      // ── 2. Home → burger → settings hub → Особисті дані (name edit) ──────────
      // All three hops are `context.push` onto the ROOT navigator, so the shell
      // (and the alive Пошук branch in its IndexedStack) stays mounted underneath
      // — the exact keep-alive condition of the reported bug.
      await tester.tap(find.byKey(const Key('client-nav-tile-0')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expectLocation(router, RouteNames.clientHome);

      await tester.tap(find.byKey(const Key('btn-menu-client')));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expectLocation(router, RouteNames.clientMenu);

      await tester.tap(find.byKey(const Key('row-personal')));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expectLocation(router, RouteNames.clientEditPersonal);

      // ── 3. Change firstName + lastName → Save ───────────────────────────────
      final Finder firstNameField = find.descendant(
        of: find.byKey(const Key('field-firstName')),
        matching: find.byType(TextField),
      );
      final Finder lastNameField = find.descendant(
        of: find.byKey(const Key('field-lastName')),
        matching: find.byType(TextField),
      );
      // Pre-populated from GET /users/me (the seeded CLIENT fixture).
      expect(
        tester.widget<TextField>(firstNameField).controller?.text,
        'Дмитро',
      );

      await tester.tap(firstNameField);
      await tester.pumpAndSettle();
      await tester.enterText(firstNameField, 'Оновлене');
      await tester.pump();
      await tester.tap(lastNameField);
      await tester.pumpAndSettle();
      await tester.enterText(lastNameField, 'Прізвище');
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-personal')));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // The Save lands back on the client home hub.
      expectLocation(router, RouteNames.clientHome);
      // The PATCH mutated the backend name (round-trips on the next GET).
      expect(fb.clientFirstName, 'Оновлене', reason: 'PATCH must persist name');
      expect(fb.clientLastName, 'Прізвище');
      // The Save fired refreshUser() → a second GET /users/me (the emission that
      // pre-fix re-ran the controllers' build() and wiped the seed).
      expect(
        fb.getMeCalls,
        greaterThanOrEqualTo(2),
        reason:
            'the name Save must call refreshUser() → a fresh GET /users/me '
            '(the same-user Authenticated re-emission under test)',
      );

      // ── THE REGRESSION ASSERTION ────────────────────────────────────────────
      // Read the keepAlive SearchFiltersController straight off the live root
      // container, BEFORE re-entering the search tab (so no initState re-seed can
      // mask the wipe). Pre-fix, the refreshUser() emission re-ran build() and
      // reset the filter → cityId is null here. Post-fix, the `.select(user.id)`
      // narrow keeps the settled id (user-client-1) unchanged, so build() never
      // re-ran and the seed survives.
      expect(
        seededCityId(tester),
        'city-kyiv',
        reason:
            'a same-user name edit (refreshUser) must NOT wipe the seeded '
            'search locality — the keepAlive controller must still hold city-kyiv',
      );
      expect(
        seededCityLabel(tester),
        'Київ',
        reason: 'the resolved city label must survive the refreshUser emission',
      );

      // ── 4. Re-enter the search tab → the user-visible city is still «Київ» ───
      // Completes the reported journey: the CLIENT returns to Пошук and the
      // location field is STILL populated (never blanked). The keepAlive branch
      // survived, so the row renders the surviving seed.
      await tester.tap(find.byKey(const Key('client-nav-search-center')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expectLocation(router, RouteNames.clientSearch);

      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
      final String cityRow = tester
          .widget<Text>(find.byKey(const Key('search_city_value')))
          .data!;
      expect(
        cityRow,
        'Київ',
        reason:
            'returning to Пошук after a name edit must still show the saved '
            'city — never the empty placeholder (the reported symptom)',
      );
      expect(
        cityRow,
        isNot(l10n.searchCityPlaceholder),
        reason: "the location field must not have blanked to its placeholder",
      );

      // The CLIENT journey never touched the master-only GET /masters/me.
      expect(fb.getMasterCalls, 0);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
