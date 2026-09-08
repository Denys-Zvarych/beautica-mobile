// END-TO-END integration test for the CLIENT delete-account flow
// (Step 2.7 Rule 3b).
//
// WHY THIS FILE EXISTS
// ---------------------
// The `row-delete-account` row (`ClientSettingsHubScreen`, below
// `row-logout`) and its confirm→delete→teardown flow
// (`runDeleteAccountFlow`, `delete_account_flow.dart`) were wired into the
// CLIENT settings hub with ZERO test coverage anywhere in the suite — this
// closes that gap end-to-end, against a real `DELETE /api/v1/users/me`
// round trip through the fake backend (not a mocked repository — see the
// widget-level coverage in `client_settings_hub_screen_test.dart` and
// `delete_account_flow_test.dart` for that).
//
// WHAT THIS FLOW PROVES (the gate)
// ---------------------------------
//   1. Login as CLIENT → land on /client/home → open the burger →
//      /client/menu renders the real ClientSettingsHubScreen — same
//      preamble as `client_logout_flow_test.dart`.
//   2. CANCEL path: open the delete-account row → cancel → dialog
//      dismisses, stays on /client/menu, DELETE /api/v1/users/me is NEVER
//      called, the refresh token survives.
//   3. CONFIRM path (success): DELETE /api/v1/users/me fires exactly once,
//      POST /auth/logout fires (delete-account reuses runLogoutFlow's own
//      session teardown — see `delete_account_flow.dart`'s header), the
//      refresh token is wiped from secure storage (M5), the app redirects
//      to /login — and, closing the loop the task named explicitly, an
//      attempted deep-link back into an authenticated CLIENT route
//      (/client/home) is bounced straight back to /login by the live
//      router guard, with storage still empty.
//   4. FAILURE path (422 booking-limit): DELETE /api/v1/users/me fires,
//      the backend's own message renders verbatim in the error VelvetSnack,
//      the app stays on /client/menu (no navigation, no teardown), and the
//      row is usable again (a second attempt raises the dialog once more).
//
// NATIVE TIER: NONE NEEDED. Pure in-app Flutter widgets + HTTP + secure
// storage (faked) — no OS permission / deep-link / FCM / biometric / WebView
// surface. A fake-backed integration_test flow is the correct and
// sufficient E2E tier; no `integration_test/patrol/` flow is required for
// this feature, and this is stated explicitly rather than skip-marked.
//
// EXECUTION (ARCHITECTURE-mobile §12): integration_test/ is LOCAL-ONLY.
//   flutter test integration_test/client_delete_account_flow_test.dart -d <device>
// or via the aggregated entrypoints (all_tests.dart / all_tests_part1.dart).
//
// KEY-BASED NAVIGATION POLICY (enforced by AppHarness): all TAPS use
// key-based finders; the 422 message is asserted via the injected fixture
// string, never a Cyrillic literal typed into this file.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/home/presentation/client_settings_hub_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations_uk.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/fakes/fake_secure_storage.dart';
import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  final AppLocalizationsUk l10n = AppLocalizationsUk();

  /// Logs in as CLIENT, lands on /client/home, opens the burger, and settles
  /// on the /client/menu settings hub. Mirrors
  /// `client_logout_flow_test.dart`'s identical helper.
  Future<GoRouter> openClientHub(
    WidgetTester tester,
    FakeBackend fb,
    FakeSecureStorage storage,
  ) async {
    final GoRouter router = await AppHarness.boot(tester, fb, storage: storage);
    await AppHarness.loginAs(tester, fb, UserRole.client);
    // fixed-wait-ok: integration test, real async (auth+redirect); bounded pumpAndSettle is the recommended real-async settle.
    await tester.pumpAndSettle(const Duration(seconds: 2));

    AppHarness.expectLocation(router, RouteNames.clientHome);

    await tester.tap(find.byKey(const Key('btn-menu-client')));
    // fixed-wait-ok: integration test, real async (route push); bounded pumpAndSettle is the recommended real-async settle.
    await tester.pumpAndSettle(const Duration(seconds: 2));

    AppHarness.expectLocation(router, RouteNames.clientMenu);
    expect(
      find.byType(ClientSettingsHubScreen),
      findsOneWidget,
      reason: 'the burger must push the CLIENT settings hub',
    );
    return router;
  }

  /// Scrolls the delete-account row into view and taps it to raise the
  /// confirm dialog.
  Future<void> openDeleteAccountDialog(WidgetTester tester) async {
    expect(find.byKey(const Key('row-delete-account')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('row-delete-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('row-delete-account')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('btn-delete-account-confirm')),
      findsOneWidget,
      reason: 'the delete-account row must raise the confirm dialog',
    );
  }

  // ── Test 1 — CANCEL keeps the account (no wipe, no nav, no DELETE) ──────

  testWidgets('CLIENT delete-account CANCEL → dialog dismisses, stays on '
      '/client/menu, DELETE /api/v1/users/me never fires, the refresh token '
      'survives', (tester) async {
    final fb = FakeBackend()..currentRole = UserRole.client;
    final storage = FakeSecureStorage();

    final router = await openClientHub(tester, fb, storage);

    expect(
      await storage.readRefreshToken(),
      isNotNull,
      reason: 'login must persist a refresh token before this is exercised',
    );

    final int deleteCallsBefore = fb.deleteMyAccountCalls;

    await openDeleteAccountDialog(tester);
    await tester.tap(find.byKey(const Key('btn-delete-account-cancel')));
    await tester.pumpAndSettle();

    AppHarness.expectLocation(router, RouteNames.clientMenu);
    expect(find.byType(ClientSettingsHubScreen), findsOneWidget);
    expect(fb.deleteMyAccountCalls, equals(deleteCallsBefore));
    expect(
      await storage.readRefreshToken(),
      isNotNull,
      reason: 'cancelling must NOT wipe the refresh token',
    );
  }, timeout: const Timeout(Duration(seconds: 60)));

  // ── Test 2 — CONFIRM deletes: server hit, storage wiped, /login, and a ──
  // ── deep-link back into an authenticated route is bounced.           ──

  testWidgets('CLIENT delete-account CONFIRM → DELETE /api/v1/users/me fires once, '
      'session tears down (M5), the app redirects to /login, and a deep-link '
      'back into an authenticated route is redirected away', (tester) async {
    final fb = FakeBackend()..currentRole = UserRole.client;
    final storage = FakeSecureStorage();

    final router = await openClientHub(tester, fb, storage);

    expect(
      await storage.readRefreshToken(),
      isNotNull,
      reason: 'precondition: login must persist a refresh token',
    );

    final int deleteCallsBefore = fb.deleteMyAccountCalls;
    final int logoutCallsBefore = fb.logoutCalls;

    await openDeleteAccountDialog(tester);
    await tester.tap(find.byKey(const Key('btn-delete-account-confirm')));
    // fixed-wait-ok: integration test, real async (delete + teardown + redirect); bounded pumpAndSettle is the recommended real-async settle.
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 1) Landed on /login — if the call had thrown, context.go(login)
    //    would never run and we'd still be on /client/menu.
    AppHarness.expectLocation(router, RouteNames.login);
    expect(
      find.byKey(const ValueKey<String>('login_email')),
      findsOneWidget,
      reason: 'the login form must render after a successful account delete',
    );

    // 2) The real DELETE endpoint was hit exactly once, and the shared
    //    session-teardown path reused from runLogoutFlow also hit the
    //    server-side revocation endpoint once.
    expect(fb.deleteMyAccountCalls, equals(deleteCallsBefore + 1));
    expect(
      fb.logoutCalls,
      equals(logoutCallsBefore + 1),
      reason:
          'delete-account must reuse the SAME session teardown as an '
          'explicit logout (delete_account_flow.dart header)',
    );

    // 3) M5 — the refresh token is GONE.
    expect(
      await storage.readRefreshToken(),
      isNull,
      reason: 'a successful account delete must wipe the refresh token',
    );

    // 4) No delete-account failure snack.
    expect(find.text(l10n.errUnknown), findsNothing);

    // 5) Cannot navigate back into an authenticated route — the deleted
    //    account's deep-link into /client/home must bounce to /login,
    //    exactly like the post-logout guard
    //    (`client_logout_flow_test.dart`'s Test 3).
    router.go(RouteNames.clientHome);
    // fixed-wait-ok: integration test, real async (guard redirect to /login); bounded pumpAndSettle is the recommended real-async settle.
    await tester.pumpAndSettle(const Duration(seconds: 2));

    AppHarness.expectLocation(router, RouteNames.login);
    expect(
      find.byType(ClientSettingsHubScreen),
      findsNothing,
      reason:
          'the deep-link must never resurrect the settings hub for a '
          'deleted, unauthenticated account',
    );
    expect(
      await storage.readRefreshToken(),
      isNull,
      reason: 'the bounced deep-link must not resurrect any token',
    );
  }, timeout: const Timeout(Duration(seconds: 60)));

  // ── Test 3 — 422 booking-limit failure: server message verbatim, no ─────
  // ── navigation, no teardown, row usable again.                     ─────

  testWidgets(
    'CLIENT delete-account 422 (too many upcoming bookings) → the backend '
    'message renders verbatim, stays on /client/menu, and the row is '
    'usable again',
    (tester) async {
      const String marker =
          'FAKE-E2E-422: спочатку скасуйте бронювання №Q7 перед видаленням';
      // `deleteMyAccountFailureStatusCode`/`...Message` are CONSTRUCTOR-TIME
      // only (`DioAdapter.onRoute` bakes a route's status code in at
      // registration, which runs from FakeBackend's own constructor — the
      // identical constraint `masterMeNotFound` documents), so they cannot
      // be set via cascade after construction the way `currentRole` can.
      final fb = FakeBackend(
        deleteMyAccountFailureStatusCode: 422,
        deleteMyAccountFailureMessage: marker,
      )..currentRole = UserRole.client;
      final storage = FakeSecureStorage();

      final router = await openClientHub(tester, fb, storage);

      final int logoutCallsBefore = fb.logoutCalls;

      await openDeleteAccountDialog(tester);
      await tester.tap(find.byKey(const Key('btn-delete-account-confirm')));
      // fixed-wait-ok: integration test, real async (failed DELETE + error snack); bounded pumpAndSettle is the recommended real-async settle.
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // The server's own message reached the UI verbatim — proves the wire
      // round trip (ValidationFailure.serverMessage →
      // AccountDeleteBookingLimitFailure.serverMessage → the error snack),
      // not a generic fallback string that would pass regardless.
      expect(
        find.text(marker),
        findsOneWidget,
        reason: 'the backend 422 message must surface verbatim',
      );

      // Stayed put — no teardown, no navigation.
      AppHarness.expectLocation(router, RouteNames.clientMenu);
      expect(find.byType(ClientSettingsHubScreen), findsOneWidget);
      expect(
        fb.logoutCalls,
        equals(logoutCallsBefore),
        reason: 'a failed delete must NOT tear the session down',
      );
      expect(
        await storage.readRefreshToken(),
        isNotNull,
        reason: 'a failed delete must NOT wipe the refresh token',
      );

      // Row usable again — dismiss the snack, wait out its own timer, then
      // re-open the dialog.
      // fixed-wait-ok: integration test, real async (VelvetSnack auto-dismiss timer); bounded pumpAndSettle is the recommended real-async settle.
      await tester.pumpAndSettle(const Duration(seconds: 6));
      await openDeleteAccountDialog(tester);
      await tester.tap(find.byKey(const Key('btn-delete-account-cancel')));
      await tester.pumpAndSettle();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
