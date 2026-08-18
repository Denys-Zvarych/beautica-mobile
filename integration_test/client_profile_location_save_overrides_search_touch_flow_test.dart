// E2E REGRESSION — a profile-location SAVE must always win over an EARLIER
// manual pick made through Пошук's OWN locality picker, even though both
// write through the very same `SearchFiltersController._userTouchedLocality`
// guard. Patched FIVE times before the fix (search_filters_controller.dart's
// `applyProfileLocationSave` doc carries the incident history).
//
// THE REPORTED BUG
// ----------------
// `_userTouchedLocality` is set by `selectOblast`/`selectCity`/`selectDistrict`
// — i.e. by the user tapping Пошук's OWN locality picker — and is never
// cleared for the rest of the session. `prefillFromProfileIfNeeded()` (the
// PASSIVE, anti-clobber prefill) returns early whenever that flag is set.
// `ClientLocationEditScreen._save()` used to call THAT guarded method after a
// successful profile-location PATCH. Result: once a CLIENT had EVER tapped
// Пошук's own locality picker in a session, `_userTouchedLocality` stayed
// permanently true, and every SUBSEQUENT profile-location save silently
// no-op'd on Search — deterministic given that precondition, never
// otherwise, which is why it read as intermittent across five bug reports.
//
// THE FIX (search_filters_controller.dart)
// ----------------------------------------
// A second, AUTHORITATIVE entry point — `applyProfileLocationSave` —
// unconditionally clears `_userTouchedLocality`, resets `_lastSeeded*`, and
// writes the just-saved locality straight through. `ClientLocationEditScreen
// ._save()` now calls that instead of the passive `prefillFromProfileIfNeeded`.
//
// WHY THIS FLOW EXISTS (Step 2.7 Rule 3b)
// ---------------------------------------
// The widget tier (client_location_edit_screen_test.dart) arms the guard
// directly on the controller and proves the state-level fix. The controller
// tier (search_filters_profile_prefill_test.dart) proves the PASSIVE half in
// isolation. NEITHER proves the actual reported journey end to end: a CLIENT
// logging in, reaching the REAL Search tab, tapping the REAL locality picker
// sheets (which is what actually flips `_userTouchedLocality` in production —
// no test before this one drove that precondition through real UI), navigating
// by REAL routing (burger → settings hub → Location edit), saving a DIFFERENT
// city through the REAL `ClientProfileRepository` PATCH, and re-entering the
// Search tab through a REAL `ClientShell` tab switch (the branch is kept alive
// in a `StatefulShellRoute.indexedStack`, so nothing re-runs `initState`) to
// observe the composed outcome. Three existing flows each cover ONE leg of
// this composition and none the whole thing:
//   • search_prefill_survives_name_edit_flow_test.dart — a NAME edit
//     (refreshUser), not a locality edit; never taps Search's own picker.
//   • client_profile_settings_flow_test.dart — saves a location, never
//     continues into Search afterwards.
//   • client_search_flow_test.dart — drives Search's picker, never follows
//     with a later profile-location save.
// This flow is the missing composition.
//
// NATIVE TIER: NONE NEEDED. In-app Flutter widgets + HTTP only (no OS
// permission / deep-link / FCM / biometric / WebView surface), so a
// fake-backed integration_test flow is the correct and sufficient tier.
//
// EXECUTION (ARCHITECTURE-mobile §12): integration_test/ is LOCAL/CI-emulator
// only. Run standalone with:
//   flutter test integration_test/client_profile_location_save_overrides_search_touch_flow_test.dart -d <emulator>
// or via the split CI aggregators (all_tests_part1.dart) / the full
// all_tests.dart entrypoint.
//
// KEY POLICY (from AppHarness): all TAPS use key-based finders; raw Ukrainian
// text appears in CONTENT ASSERTIONS only.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/discovery/presentation/state/search_filters_controller.dart';
import 'package:beautica_mobile/features/shell/presentation/client_shell.dart';
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

  /// Reads the live keepAlive [SearchFiltersController] off the root
  /// [ProviderContainer] (reachable from the always-mounted [ClientShell]).
  /// Reading a keepAlive provider does not re-seed it.
  ProviderContainer rootContainer(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(ClientShell)));

  testWidgets(
    'CLIENT manually picks a city through the Пошук locality picker, then '
    'saves a DIFFERENT city on the profile Location screen — returning to '
    'Пошук (real tab switch, no restart) shows the NEWLY SAVED city, never '
    'the earlier touched one, never blank',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      // No saved profile locality — the CLIENT starts with an empty Search
      // filter and picks everything through real UI in this flow.

      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle();
      AppHarness.expectLocation(router, RouteNames.clientHome);

      // ── 1. Reach Пошук → manually drive its OWN locality picker ────────────
      // This is what actually flips `_userTouchedLocality` in production — the
      // controller-level tests arm the guard by calling selectOblast/selectCity
      // directly, which is faithful to the CODE path but never proves the REAL
      // picker sheets (rendered here) are what a user actually taps.
      await tester.tap(find.byKey(const Key('client-nav-search-center')));
      await tester.pumpAndSettle();
      AppHarness.expectLocation(router, RouteNames.clientSearch);
      expect(find.byKey(const Key('client-branch-search')), findsOneWidget);

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

      expect(
        tester.widget<Text>(find.byKey(const Key('search_city_value'))).data,
        'Київ',
        reason: 'the manual Search-picker pick must render immediately',
      );
      expect(
        rootContainer(tester).read(searchFiltersControllerProvider).cityId,
        'city-kyiv',
        reason:
            'precondition: the guard is now armed via the REAL picker tap '
            '(selectOblast/selectCity), exactly as production users trigger '
            'it — city-kyiv is a DIFFERENT city from the one saved below',
      );

      // ── 2. Home → burger → settings hub → Location edit (real routing) ─────
      await tester.tap(find.byKey(const Key('client-nav-tile-0')));
      await tester.pumpAndSettle();
      AppHarness.expectLocation(router, RouteNames.clientHome);

      await tester.tap(find.byKey(const Key('btn-menu-client')));
      await tester.pumpAndSettle();
      AppHarness.expectLocation(router, RouteNames.clientMenu);

      await tester.tap(find.byKey(const Key('row-location')));
      await tester.pumpAndSettle();
      AppHarness.expectLocation(router, RouteNames.clientEditLocation);

      // ── 3. Pick a DIFFERENT city (Львів) through the REAL cascade → Save ────
      await tester.tap(find.byKey(const Key('locality_row_oblast')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('locality_picker_tile_oblast-kyiv')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('locality_row_city')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('locality_picker_tile_city-lviv')),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('btn-save-location')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-save-location')));
      await tester.pumpAndSettle();

      // The save must SUCCEED and persist the NEW city server-side.
      AppHarness.expectLocation(router, RouteNames.clientHome);
      expect(
        fb.clientCityId,
        'city-lviv',
        reason: 'the location save must persist the newly picked city',
      );

      // ── THE REGRESSION ASSERTION ────────────────────────────────────────────
      // Read the keepAlive SearchFiltersController straight off the live root
      // container, BEFORE re-entering the search tab (so no later re-seed can
      // mask the outcome). Pre-fix (`_save()` calling the PASSIVE
      // `prefillFromProfileIfNeeded()`), `_userTouchedLocality` is still true
      // from step 1, so the passive method returns immediately and this stays
      // at 'city-kyiv' — the STALE touched value, not even null. Only the
      // AUTHORITATIVE `applyProfileLocationSave` path lands on the new city.
      expect(
        rootContainer(tester).read(searchFiltersControllerProvider).cityId,
        'city-lviv',
        reason:
            'an explicit profile-location save must ALWAYS win over an '
            'earlier Search-picker touch — this is the five-times-patched bug',
      );
      expect(
        rootContainer(
          tester,
        ).read(searchFilterLabelsControllerProvider).cityName,
        'Львів',
        reason: 'the sibling label controller must be updated too',
      );

      // ── 4. Re-enter Пошук through a REAL ClientShell tab switch ─────────────
      // The Search branch is kept alive in `StatefulShellRoute.indexedStack`,
      // so this switch does NOT re-run `initState` / the passive prefill — the
      // rendered city must already reflect what `applyProfileLocationSave`
      // wrote directly onto the controller.
      await tester.tap(find.byKey(const Key('client-nav-search-center')));
      await tester.pumpAndSettle();
      AppHarness.expectLocation(router, RouteNames.clientSearch);

      expect(
        tester.widget<Text>(find.byKey(const Key('search_city_value'))).data,
        'Львів',
        reason:
            'returning to Пошук after the profile-location save must show the '
            'NEWLY SAVED city — never the earlier Search-picker touch '
            '(city-kyiv) and never a blanked placeholder',
      );

      // Self-consistency of `_lastSeeded*` after `applyProfileLocationSave` is
      // pinned at the WIDGET tier (client_location_edit_screen_test.dart),
      // which reads the profile through a controllable stub. It is
      // deliberately NOT re-proven here: this flow's CLIENT starts with NO
      // saved locality at all, and `ClientProfileUpdate`'s wire body never
      // carries `oblastId` (only cityId/districtId — the location screen never
      // sends it) — FakeBackend has no server-side city→oblast derivation, so
      // a subsequent GET /users/me here echoes back cityId WITHOUT the
      // matching oblastId, a FakeBackend fidelity gap unrelated to the
      // `_userTouchedLocality`/`applyProfileLocationSave` regression this flow
      // exists to pin.

      // The CLIENT journey never touched the master-only GET /masters/me.
      expect(fb.getMasterCalls, 0);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
