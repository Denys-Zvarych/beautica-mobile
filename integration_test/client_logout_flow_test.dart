// END-TO-END integration test for the CLIENT logout flow (Step 2.7 Rule 3b).
//
// WHY THIS FILE EXISTS (the coverage gap it closes)
// -------------------------------------------------
// `logout_flow_test.dart` already proves the logout journey END-TO-END for an
// INDEPENDENT_MASTER (login → /master/profile → /master/menu hub → confirm →
// /login, no logoutFailed SnackBar, server revocation hit). NONE of the suite,
// however, drove logout from the CLIENT settings hub at /client/menu — the
// burger-menu surface the client app actually ships. The CLIENT path differs in
// every coordinate that matters: a different burger key (btn-menu-client), a
// different hub widget (ClientSettingsHubScreen), a different landing route
// (/client/home), and the /client/* role gate (auth_redirect.dart ~242-247).
//
// It ALSO adds the assertion the master flow omits entirely: that the local
// secure-storage refresh token is WIPED by logout(). M5 (secure-storage
// discipline) makes a token surviving an explicit logout a CRITICAL leak — the
// regression test for that wipe lived nowhere until this file. We inject our own
// FakeSecureStorage via the harness `extraOverrides` (last-wins over the
// harness's internal default) so we can read the token before and after.
//
// WHAT THIS FLOW PROVES (the gate)
// --------------------------------
//   1. Login as CLIENT → land on /client/home → the real login flow has
//      WRITTEN a refresh token into secure storage (precondition for the wipe
//      assertion to be meaningful).
//   2. Home-hub burger (btn-menu-client) → /client/menu renders the real
//      ClientSettingsHubScreen.
//   3. CANCEL path: open the logout row → tap btn-logout-cancel → the dialog
//      dismisses, the app STAYS on /client/menu, NO server logout fired, and the
//      refresh token is STILL present (a cancelled logout must not wipe).
//   4. CONFIRM path: open the logout row → tap btn-logout-confirm → the app
//      redirects to /login, the server revocation endpoint was hit, the
//      refresh token is GONE from secure storage (M5), and the logoutFailed
//      SnackBar is NOT shown.
//
// NATIVE TIER: NONE NEEDED. Pure in-app Flutter widgets + HTTP + secure-storage
// (faked). No OS permission / deep-link / FCM / biometric / WebView surface, so
// a fake-backed integration_test flow is the correct and sufficient E2E tier.
//
// EXECUTION (ARCHITECTURE-mobile §12): integration_test/ is LOCAL-ONLY (needs a
// connected emulator; GitHub-hosted runners have no KVM). Run with:
//   flutter test integration_test/client_logout_flow_test.dart -d <emulator>
// or via the aggregated entrypoint:
//   flutter test integration_test/all_tests.dart -d <emulator>
//
// KEY-BASED NAVIGATION POLICY (enforced by AppHarness): all TAPS use key-based
// finders; Ukrainian strings appear only in absence/content assertions.

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

  // Locale-pinned UK strings used ONLY for the absence assertion (the harness
  // pins the app to uk_UA). We must NOT see the logout-failure SnackBar.
  final AppLocalizationsUk l10n = AppLocalizationsUk();

  // ── Helper: assert the router landed on [expected] ───────────────────────
  void expectLocation(GoRouter router, String expected) {
    final String current = router.routerDelegate.currentConfiguration.uri
        .toString();
    expect(
      current,
      startsWith(expected),
      reason: 'Expected router to be at $expected, got $current',
    );
  }

  /// Logs in as CLIENT, lands on /client/home, opens the burger, and settles on
  /// the /client/menu settings hub. Returns the live router for location asserts.
  Future<GoRouter> openClientHub(
    WidgetTester tester,
    FakeBackend fb,
    FakeSecureStorage storage,
  ) async {
    final GoRouter router = await AppHarness.boot(
      tester,
      fb,
      // Inject OUR storage so we can read the refresh token before/after logout.
      // We pass it through boot()'s `storage:` param (NOT extraOverrides): the
      // harness installs the SINGLE secureStorageProvider override from it.
      // Overriding the same provider twice (one in boot's defaults, one in
      // extraOverrides) throws under Riverpod 3.x ("Tried to override a provider
      // twice within the same container").
      storage: storage,
    );
    await AppHarness.loginAs(tester, fb, UserRole.client);
    // fixed-wait-ok: integration test, real async (auth+redirect); bounded pumpAndSettle is the recommended real-async settle.
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expectLocation(router, RouteNames.clientHome);

    // Open the home-hub burger → pushes /client/menu.
    await tester.tap(find.byKey(const Key('btn-menu-client')));
    // fixed-wait-ok: integration test, real async (route push); bounded pumpAndSettle is the recommended real-async settle.
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expectLocation(router, RouteNames.clientMenu);
    expect(
      find.byType(ClientSettingsHubScreen),
      findsOneWidget,
      reason: 'the burger must push the CLIENT settings hub',
    );
    return router;
  }

  /// Scrolls the logout row into view and taps it to raise the confirm dialog.
  Future<void> openLogoutDialog(WidgetTester tester) async {
    expect(find.byKey(const Key('row-logout')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('row-logout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('row-logout')));
    await tester.pumpAndSettle();
  }

  // ── Test 1 — CANCEL keeps the session (no wipe, no nav, no server call) ────

  testWidgets(
    'CLIENT logout CANCEL → dialog dismisses, stays on /client/menu, the '
    'refresh token survives and no server logout fires',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final storage = FakeSecureStorage();

      final router = await openClientHub(tester, fb, storage);

      // The real login flow must have persisted a refresh token.
      expect(
        await storage.readRefreshToken(),
        isNotNull,
        reason: 'login must persist a refresh token before logout is exercised',
      );

      final int logoutsBefore = fb.logoutCalls;

      await openLogoutDialog(tester);
      expect(
        find.byKey(const Key('btn-logout-cancel')),
        findsOneWidget,
        reason:
            'the logout row must raise the confirm dialog with a cancel CTA',
      );

      // Cancel the dialog.
      await tester.tap(find.byKey(const Key('btn-logout-cancel')));
      await tester.pumpAndSettle();

      // Still on the hub — a cancelled logout must NOT navigate.
      expectLocation(router, RouteNames.clientMenu);
      expect(
        find.byType(ClientSettingsHubScreen),
        findsOneWidget,
        reason: 'cancelling logout must leave the user on the settings hub',
      );

      // No server revocation, and the token is intact.
      expect(
        fb.logoutCalls,
        equals(logoutsBefore),
        reason: 'cancelling must NOT call POST /auth/logout',
      );
      expect(
        await storage.readRefreshToken(),
        isNotNull,
        reason: 'cancelling logout must NOT wipe the refresh token',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  // ── Test 2 — CONFIRM logs out: server hit, storage wiped, redirect to login ─

  testWidgets(
    'CLIENT logout CONFIRM → POST /auth/logout fires, secure storage is wiped '
    '(M5), the app redirects to /login and no logoutFailed SnackBar shows',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final storage = FakeSecureStorage();

      final router = await openClientHub(tester, fb, storage);

      // Precondition: a token exists, so a post-logout null PROVES the wipe ran.
      expect(
        await storage.readRefreshToken(),
        isNotNull,
        reason: 'login must persist a refresh token before logout',
      );

      final int logoutsBefore = fb.logoutCalls;

      await openLogoutDialog(tester);
      expect(
        find.byKey(const Key('btn-logout-confirm')),
        findsOneWidget,
        reason: 'the logout row must raise the confirm dialog',
      );

      // Confirm → runLogoutFlow → REAL authProvider.logout():
      //   best-effort POST /auth/logout → secureStorage.deleteAll() →
      //   state = Unauthenticated → router redirect → context.go(/login).
      await tester.tap(find.byKey(const Key('btn-logout-confirm')));
      // fixed-wait-ok: integration test, real async (logout teardown+redirect); bounded pumpAndSettle is the recommended real-async settle.
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 1) Landed on /login. If logout() had thrown, context.go(login) would
      //    not run and we'd still be on /client/menu.
      expectLocation(router, RouteNames.login);
      expect(
        find.byKey(const ValueKey<String>('login_email')),
        findsOneWidget,
        reason: 'the login form must render after a successful client logout',
      );

      // 2) The server-side revocation endpoint was hit exactly once.
      expect(
        fb.logoutCalls,
        equals(logoutsBefore + 1),
        reason: 'logout() must call POST /auth/logout once before the wipe',
      );

      // 3) M5 — the refresh token is GONE. A token surviving an explicit logout
      //    is a CRITICAL leak; this is the regression guard for the wipe.
      expect(
        await storage.readRefreshToken(),
        isNull,
        reason: 'logout() must wipe the refresh token from secure storage (M5)',
      );

      // 4) The failure SnackBar must NOT be shown — logout succeeded.
      expect(
        find.text(l10n.logoutFailed),
        findsNothing,
        reason:
            'a clean logout must not surface the "${l10n.logoutFailed}" SnackBar',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  // ── Test 3 — post-logout deep-link to a protected route bounces to /login ──
  //
  // M5 + M10, END-TO-END. Test 2 proved logout clears secure storage and lands
  // on /login. This test then proves the SECOND half of the security contract
  // the router-tier test (test/routing/unauthenticated_deeplink_redirect_test.
  // dart) covers in isolation: once logged out, an UNAUTHENTICATED deep-link to
  // a protected CLIENT route (/passport) must NOT slip through to the protected
  // screen — the live GoRouter's auth guard must redirect it back to /login,
  // with secure storage still empty. This drives the guard through the REAL
  // router (not the pure seam), closing the deep-link-after-logout path E2E.

  testWidgets(
    'after CLIENT logout, a deep-link to a protected route (/passport) is '
    'redirected back to /login with secure storage still cleared (M5 + M10)',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final storage = FakeSecureStorage();

      final router = await openClientHub(tester, fb, storage);

      // Confirm logout → storage wiped, on /login (preconditions re-proved here
      // so this test stands alone, not coupled to Test 2's ordering).
      await openLogoutDialog(tester);
      await tester.tap(find.byKey(const Key('btn-logout-confirm')));
      // fixed-wait-ok: integration test, real async (logout teardown+redirect); bounded pumpAndSettle is the recommended real-async settle.
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expectLocation(router, RouteNames.login);
      expect(
        await storage.readRefreshToken(),
        isNull,
        reason: 'precondition: logout must have wiped the refresh token (M5)',
      );

      // Now attempt the unauthenticated deep-link to a protected CLIENT route.
      // The live GoRouter's redirect guard (authRedirect → authRedirectForLocation)
      // must bounce it straight back to /login.
      router.go(RouteNames.clientPassport);
      // fixed-wait-ok: integration test, real async (guard redirect to /login); bounded pumpAndSettle is the recommended real-async settle.
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 1) The guard redirected the deep-link back to /login — the protected
      //    passport screen must NOT have rendered.
      expectLocation(router, RouteNames.login);
      expect(
        find.byKey(const ValueKey<String>('login_email')),
        findsOneWidget,
        reason:
            'an unauthenticated deep-link to /passport must land on the login '
            'form, never the protected passport screen',
      );

      // 2) Secure storage is STILL empty — the bounced deep-link must not have
      //    resurrected any token.
      expect(
        await storage.readRefreshToken(),
        isNull,
        reason:
            'a redirected unauthenticated deep-link must leave secure storage '
            'cleared (M5)',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
