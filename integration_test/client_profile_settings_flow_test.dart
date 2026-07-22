// CLIENT profile / settings + location-display — E2E flow (Step 2.7 Rule 3b).
//
// WHY THIS FILE EXISTS
// --------------------
// The widget tier proves each screen in isolation against a mocked repository
// (client_settings_hub_screen_test.dart, client_contacts_edit_screen_test.dart,
// client_location_edit_screen_test.dart) and the unit tier proves the request
// body shape (client_profile_repository_test.dart) and the route gate
// (client_menu_route_guard_test.dart). NONE of them exercises the REAL user
// journey end-to-end: a CLIENT logging in through the real login form, opening
// the home-hub burger, landing on the real /client/menu hub, navigating into a
// real edit screen, saving through the REAL ClientProfileRepository onto the
// REAL `PATCH /users/me` contract, and the value round-tripping on re-fetch.
//
// This flow boots the REAL app via AppHarness (FakeBackend DioAdapter — no real
// socket, FakeSecureStorage — no platform channel, fixed clock, overflow guard)
// and drives the full journey with the real go_router, real Riverpod notifiers,
// and the real generated UserControllerApi against the fake `/users/me`
// endpoints (GET seeds the edit screens; PATCH persists + round-trips).
//
// WHAT IT PROVES (the gate)
// -------------------------
//   1. Home hub → burger (btn-menu-client) → /client/menu hub renders.
//   2. Hub → Contacts edit (row-contacts) → change phone → Save
//      (btn-save-contacts) → the PATCH hits the fake `/users/me`, the body
//      carries the new phone and NEVER an `instagram` key, and the value
//      round-trips (the next GET /users/me reflects it). The save then lands
//      back on the home hub and the profile card shows the NEW phone WITHOUT a
//      restart (refreshUser() re-fetched /users/me) — the stale-home-card
//      regression guard (a profile edit used to surface on the card only after
//      a cold start).
//   3. Hub → Location edit (row-location) → the three free-text address fields
//      (street / buildingNo / locationNote) are GONE → the CLIENT picks
//      oblast → city through the REAL cascade picker sheets → Save
//      (btn-save-location) → the PATCH location slice carries the selected
//      cityId WITHOUT any address key (and no instagram), the save SUCCEEDS, the
//      screen leaves the editor, and the city round-trips on re-fetch.
//
// LOCATION NOTE (forward-compat — see QA brief)
// ---------------------------------------------
// A parallel backend change adds `oblastId` to the profile response so the
// Location screen can drop its oblast-resolution scan. This flow asserts the
// SAVE / null-city BEHAVIOR (stable contract), NOT the internal pre-population
// mechanism (about to change), so it survives that refactor.
//
// NATIVE TIER: NONE NEEDED.
// This journey has no OS permission / deep-link / FCM / biometric / WebView
// surface — every interaction is in-app Flutter widgets + HTTP. No patrol /
// `$.native.*` flow is warranted; a fake-backed integration_test flow is the
// correct and sufficient end-to-end tier here.
//
// EXECUTION (ARCHITECTURE-mobile §12): integration_test/ is LOCAL-ONLY (it
// requires a connected emulator; GitHub-hosted runners have no KVM). Run with:
//   flutter test integration_test/client_profile_settings_flow_test.dart -d <emulator>
// or via the aggregated entrypoint:
//   flutter test integration_test/all_tests.dart -d <emulator>
//
// KEY POLICY (from AppHarness): all TAPS use key-based finders; raw Ukrainian
// text may appear in CONTENT ASSERTIONS only.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/home/presentation/client_settings_hub_screen.dart';
import 'package:beautica_mobile/features/home/presentation/home_hub_screen.dart';
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

  /// Logs in as CLIENT, lands on /home, opens the burger, and settles on the
  /// /client/menu settings hub. Returns the live router for location asserts.
  Future<GoRouter> openSettingsHub(WidgetTester tester, FakeBackend fb) async {
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.client);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    AppHarness.expectLocation(router, RouteNames.clientHome);

    // Open the home-hub burger → pushes /client/menu.
    await tester.tap(find.byKey(const Key('btn-menu-client')));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    AppHarness.expectLocation(router, RouteNames.clientMenu);
    expect(
      find.byType(ClientSettingsHubScreen),
      findsOneWidget,
      reason: 'the burger must push the CLIENT settings hub',
    );
    return router;
  }

  // ── Test 1 — Contacts edit: change phone → save → PATCH round-trips ───────

  testWidgets(
    'CLIENT edits phone on the Contacts screen → PATCH /users/me persists the '
    'new phone (no instagram) and the value round-trips',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      // Seed a known starting phone so the field is dirty after we change it.
      fb.clientPhone = '+380 50 000 00 00';

      final router = await openSettingsHub(tester, fb);

      // Open Contacts edit from the hub.
      await tester.tap(find.byKey(const Key('row-contacts')));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      AppHarness.expectLocation(router, RouteNames.clientEditContacts);

      // The phone field pre-populates from the cached /users/me profile.
      expect(
        find.byKey(const Key('field-phone')),
        findsOneWidget,
        reason: 'Contacts edit must render the phone field',
      );
      // Clients have NO Instagram field.
      expect(
        find.byKey(const Key('field-instagram')),
        findsNothing,
        reason: 'the CLIENT contacts screen must not render an Instagram field',
      );

      final int patchesBefore = fb.patchMeCalls;

      // Change the phone, then Save.
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-phone')),
          matching: find.byType(TextField),
        ),
        '+380 67 111 22 33',
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('btn-save-contacts')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-save-contacts')));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // The PATCH must have fired exactly once for this save.
      expect(
        fb.patchMeCalls,
        equals(patchesBefore + 1),
        reason: 'Save must issue exactly one PATCH /users/me',
      );

      // The body carried the new phone and NEVER an instagram key.
      final body = fb.lastPatchMeBody;
      expect(body, isNotNull, reason: 'PATCH /users/me body must be captured');
      expect(
        body!['phoneNumber'],
        contains('67 111 22 33'),
        reason: 'the PATCH body must carry the edited phone',
      );
      expect(
        body.containsKey('instagram'),
        isFalse,
        reason:
            'ClientProfileRepository must NEVER send instagram — the key must '
            'be absent from the wire body',
      );
      // The name + location slices are NOT owned by the Contacts screen, so they
      // must be omitted (merge-onto-cache preserves them server-side).
      expect(body.containsKey('cityId'), isFalse);
      expect(body.containsKey('firstName'), isFalse);

      // Save navigated home; the new phone round-trips through the fake state.
      AppHarness.expectLocation(router, RouteNames.clientHome);
      expect(
        fb.clientPhone,
        '+380 67 111 22 33',
        reason: 'the fake /users/me state must reflect the persisted phone',
      );

      // ── REGRESSION (stale home card) ─────────────────────────────────────
      // The home-hub profile card derives from the auth session User. The save
      // path calls AuthNotifier.refreshUser() (→ GET /users/me) BEFORE
      // invalidating the profile providers, so the freshly-persisted phone must
      // surface on the home card WITHOUT restarting the app. Before the fix this
      // showed the STALE phone until a cold start.
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(
        find.byType(HomeHubScreen),
        findsOneWidget,
        reason: 'save must land back on the home hub',
      );
      expect(
        find.textContaining('67 111 22 33'),
        findsOneWidget,
        reason:
            'the home-hub profile card must show the NEW phone in-session '
            '(refreshUser re-fetched /users/me) — a stale phone here is the '
            'regression this flow guards',
      );
      expect(
        find.textContaining('50 000 00 00'),
        findsNothing,
        reason: 'the stale pre-edit phone must no longer appear on the card',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  // ── Test 2 — Location edit: locality-only save (NO address fields) ─────────
  //
  // Address-field removal guard: the CLIENT Location screen no longer renders or
  // sends the free-text street / building / note fields. This flow proves the
  // E2E journey still works with ONLY the locality cascade — the user picks
  // oblast → city through the REAL picker sheets, saves, and the PATCH carries
  // the selected cityId WITHOUT any address key (street / buildingNo /
  // locationNote) and WITHOUT instagram. The picked city round-trips on the next
  // GET /users/me. Selecting a city (vs. the old "type a street") is now what
  // makes the form dirty, since the address fields are gone.

  testWidgets(
    'CLIENT picks a city on the Location screen (no address fields) → save '
    'SUCCEEDS, the PATCH carries the cityId with NO street/buildingNo/'
    'locationNote keys, and the city round-trips',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      // No city seeded — the CLIENT starts with an empty location.

      final router = await openSettingsHub(tester, fb);

      // Open Location edit from the hub.
      await tester.tap(find.byKey(const Key('row-location')));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      AppHarness.expectLocation(router, RouteNames.clientEditLocation);

      // The locality cascade renders…
      expect(
        find.byKey(const Key('location-cascade')),
        findsOneWidget,
        reason: 'Location edit must render the locality cascade',
      );
      // …and the three free-text address fields are GONE (the removal guard).
      expect(
        find.byKey(const Key('field-street')),
        findsNothing,
        reason: 'the CLIENT Location screen must NOT render a street field',
      );
      expect(
        find.byKey(const Key('field-buildingNo')),
        findsNothing,
        reason: 'the CLIENT Location screen must NOT render a building field',
      );
      expect(
        find.byKey(const Key('field-locationNote')),
        findsNothing,
        reason: 'the CLIENT Location screen must NOT render a note field',
      );

      final int patchesBefore = fb.patchMeCalls;

      // Drive the REAL cascade: tap the Область row → pick the seeded oblast.
      await tester.tap(find.byKey(const Key('locality_row_oblast')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.tap(
        find.byKey(const ValueKey<String>('locality_picker_tile_oblast-kyiv')),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Tap the Місто row → pick the seeded city (no districts → cascade done).
      await tester.tap(find.byKey(const Key('locality_row_city')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.tap(
        find.byKey(const ValueKey<String>('locality_picker_tile_city-kyiv')),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await tester.ensureVisible(find.byKey(const Key('btn-save-location')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-save-location')));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // The save must SUCCEED — exactly one PATCH /users/me for the location.
      expect(
        fb.patchMeCalls,
        equals(patchesBefore + 1),
        reason: 'a city-selected save must issue exactly one PATCH /users/me',
      );

      final body = fb.lastPatchMeBody;
      expect(body, isNotNull);
      // The location slice IS touched here, so cityId is present and carries the
      // selected city id.
      expect(
        body!.containsKey('cityId'),
        isTrue,
        reason: 'the touched location slice must carry the cityId key',
      );
      expect(
        body['cityId'],
        'city-kyiv',
        reason: 'the PATCH body must carry the city the CLIENT selected',
      );
      // ── ADDRESS-FIELD REMOVAL GUARD (the contract this flow protects) ──────
      // The CLIENT only edits the locality cascade — the free-text address keys
      // must NEVER appear on the wire body (the backend preserves any existing
      // values). A present key here is the regression this flow guards.
      expect(
        body.containsKey('street'),
        isFalse,
        reason: 'the CLIENT location PATCH must NEVER carry a street key',
      );
      expect(
        body.containsKey('buildingNo'),
        isFalse,
        reason: 'the CLIENT location PATCH must NEVER carry a buildingNo key',
      );
      expect(
        body.containsKey('locationNote'),
        isFalse,
        reason: 'the CLIENT location PATCH must NEVER carry a locationNote key',
      );
      expect(
        body.containsKey('instagram'),
        isFalse,
        reason: 'the location slice must never carry an instagram key',
      );

      // Save left the editor (navigated home) — proving no validation block.
      AppHarness.expectLocation(router, RouteNames.clientHome);
      // The picked city round-trips through the fake /users/me state.
      expect(
        fb.clientCityId,
        'city-kyiv',
        reason: 'the fake /users/me state must reflect the persisted city',
      );
      // The address state was never touched by this CLIENT save.
      expect(
        fb.clientStreet,
        isNull,
        reason: 'a CLIENT location save must never persist a street value',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
