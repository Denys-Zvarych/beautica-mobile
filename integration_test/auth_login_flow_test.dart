// Phase 17.3 — E2E: Auth Login Flow
//
// Journey: cold-start (no stored token) → /login renders → user fills
// credentials → taps Submit → app navigates to the role-appropriate home.
//
// Three cases:
//   1. CLIENT        → lands on / (placeholder home; this role is post-MVP)
//   2. SALON_OWNER   → lands on / (placeholder home; this role is post-MVP)
//   3. INDEPENDENT_MASTER → lands on /master/profile (Phase 4.2)
//
// All taps are key-based — no raw Ukrainian find.text() tap drivers.
// See integration_test/support/app_harness.dart for the policy rationale.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
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

  // ── Helper: assert the router landed on [expectedPath] ───────────────────

  /// Reads the current route from the [GoRouter] instance returned by
  /// [AppHarness.boot]. Using the router reference directly avoids the
  /// [GoRouter.of(context)] pitfall: [InheritedGoRouter] is a DESCENDANT of
  /// [MaterialApp.router], so a context obtained at the [MaterialApp] level
  /// does not have GoRouter in its ancestor chain and throws
  /// "No GoRouter found in context".
  void expectLocation(GoRouter router, String expected) {
    final String current = router.routerDelegate.currentConfiguration.uri
        .toString();
    expect(
      current,
      startsWith(expected),
      reason: 'Expected router location to start with $expected, got $current',
    );
  }

  // ── Test 1 — INDEPENDENT_MASTER → masterProfile ──────────────────────────

  testWidgets('INDEPENDENT_MASTER login navigates to /master/profile', (
    tester,
  ) async {
    final fb = FakeBackend()..currentRole = UserRole.independentMaster;
    final GoRouter router = await AppHarness.boot(tester, fb);

    // Should be on /login after cold-start (no stored token).
    expect(
      find.byKey(const ValueKey<String>('login_email')),
      findsOneWidget,
      reason: 'Login form must be visible on cold start',
    );

    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

    // Auth succeeded → router should have navigated to master profile.
    expectLocation(router, RouteNames.masterProfile);

    // Confirm the fake backend was called.
    expect(fb.loginCalls, equals(1));
  });

  // ── Test 2 — CLIENT → home placeholder ───────────────────────────────────

  testWidgets('CLIENT login navigates to / (home placeholder)', (tester) async {
    final fb = FakeBackend()..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(tester, fb);

    expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);

    await AppHarness.loginAs(tester, fb, UserRole.client);

    // CLIENT is post-MVP → router lands on the home placeholder.
    expectLocation(router, RouteNames.home);
    expect(fb.loginCalls, equals(1));
  });

  // ── Test 3 — SALON_OWNER → home placeholder ──────────────────────────────

  testWidgets('SALON_OWNER login navigates to / (home placeholder)', (
    tester,
  ) async {
    final fb = FakeBackend()..currentRole = UserRole.salonOwner;
    final GoRouter router = await AppHarness.boot(tester, fb);

    expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);

    await AppHarness.loginAs(tester, fb, UserRole.salonOwner);

    // SALON_OWNER is post-MVP → lands on home placeholder.
    expectLocation(router, RouteNames.home);
    expect(fb.loginCalls, equals(1));
  });
}
