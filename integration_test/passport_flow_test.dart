// Phase 13.8 — E2E: CLIENT BEAUTY PASSPORT tab flow.
//
// WHY THIS FILE EXISTS
// --------------------
// The widget tier (test/features/passport/...) proves the PassportScreen and its
// PassportCard in isolation with mocked providers. The client-shell flow
// (client_shell_flow_test.dart) proves branch HOPPING in general. Neither
// exercises the REAL journey to the live PassportScreen: a CLIENT logging in
// through the real login form against the fake backend, hopping to the BEAUTY
// PASSPORT tab (branch index 4), and seeing the REAL PassportScreen render
// (Phase 13.8 replaced the index-4 placeholder with PassportScreen).
//
// This flow boots the REAL app via AppHarness (FakeBackend socket,
// FakeSecureStorage, fixed clock, overflow guard) and drives:
//
//   1. CLIENT login → lands on /home.
//   2. Tap the passport tab (client-nav-tile-4) → router at /passport, the real
//      PassportScreen mounted (keyed `client-branch-passport`).
//   3. The placeholder PassportRepository returns Passport.empty(), so the
//      screen renders its encouraging EMPTY variant (CTA present). This is the
//      supported state until backend 19.5 wires GET /clients/me/passport.
//
// NO PATROL FLOW NEEDED: this journey involves no native interaction (no OS
// permission dialog, deep link, FCM, WebView, biometric) — only in-app
// navigation and Riverpod state — so a standard integration_test flow is the
// correct (and sufficient) tier. The FLAG_SECURE acquire/release contract is
// covered at the widget tier (passport_screen_test.dart) where the native plugin
// is kDebugMode-guarded.
//
// FAKE-BACKEND NOTE: GET /clients/me/passport (backend 19.5) is not wired in
// FakeBackend; the PlaceholderPassportRepository returns Passport.empty() so the
// screen shows the empty state. The flow asserts the empty-state CTA key.
//
// KEY POLICY (from AppHarness): all TAPS use key-based finders. Raw Ukrainian
// text appears in CONTENT ASSERTIONS only.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/passport/presentation/passport_screen.dart';
import 'package:beautica_mobile/features/shell/presentation/client_shell.dart';
import 'package:beautica_mobile/features/shell/presentation/widgets/client_bottom_nav.dart';
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

  testWidgets(
    'CLIENT taps the passport tab → the real PassportScreen renders its empty '
    'variant (placeholder backend)',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expectLocation(router, RouteNames.clientHome);

      // Hop to the BEAUTY PASSPORT tab (flanking tile index 4).
      await tester.tap(find.byKey(const Key('client-nav-tile-4')));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Router moved to /passport, and the REAL PassportScreen is mounted —
      // a single ClientShell + bottom nav survive (goBranch, not push).
      expectLocation(router, RouteNames.clientPassport);
      expect(
        find.byType(ClientShell),
        findsOneWidget,
        reason: 'exactly one ClientShell must remain after hopping to passport',
      );
      expect(find.byType(ClientBottomNav), findsOneWidget);
      expect(
        find.byType(PassportScreen),
        findsOneWidget,
        reason:
            'the index-4 branch must mount the REAL PassportScreen '
            '(Phase 13.8 replaced the placeholder)',
      );
      // The screen carries the stable branch key the placeholder used to expose.
      expect(
        find.byKey(const Key('client-branch-passport')),
        findsOneWidget,
        reason: 'PassportScreen must carry the client-branch-passport key',
      );

      // Placeholder repository ⇒ Passport.empty() ⇒ the encouraging EMPTY
      // variant with its CTA (no populated document card).
      expect(
        find.byKey(const Key('passport_find_master_button')),
        findsOneWidget,
        reason:
            'until backend 19.5, the passport renders the empty-state CTA '
            '(Passport.empty() from the placeholder repository)',
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testWidgets(
    'the passport empty-state CTA navigates the CLIENT to the search tab',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await tester.tap(find.byKey(const Key('client-nav-tile-4')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expectLocation(router, RouteNames.clientPassport);

      // Tapping «Знайти майстра» routes to the discovery (search) tab.
      await tester.tap(find.byKey(const Key('passport_find_master_button')));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expectLocation(router, RouteNames.clientSearch);
      expect(
        find.byType(ClientShell),
        findsOneWidget,
        reason: 'the CTA hop stays inside the client shell (goBranch)',
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
