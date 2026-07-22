// Phase 17.3 — E2E: Auth Login Flow
//
// Journey: cold-start (no stored token) → /login renders → user fills
// credentials → taps Submit → app navigates to the role-appropriate home.
//
// Three cases:
//   1. CLIENT        → lands on /home (the Phase 13.1 5-tab client shell)
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
    AppHarness.expectLocation(router, RouteNames.masterProfile);

    // Confirm the fake backend was called.
    expect(fb.loginCalls, equals(1));
  });

  // ── Test 2 — CLIENT → client home shell ──────────────────────────────────

  testWidgets('CLIENT login navigates to /home (client shell)', (tester) async {
    final fb = FakeBackend()..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(tester, fb);

    expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);

    await AppHarness.loginAs(tester, fb, UserRole.client);

    // Phase 13.1 — a CLIENT lands on the 5-tab client shell at /home (NOT the
    // legacy `/` home placeholder). Assert the exact landing path.
    final String current = AppHarness.location(router);
    expect(
      current,
      equals(RouteNames.clientHome),
      reason:
          'CLIENT must land exactly on ${RouteNames.clientHome}, got $current',
    );
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

    // SALON_OWNER is post-MVP → lands on the `/` home placeholder.
    //
    // TIGHTENED (2026-07-22 vacuous-assertion audit): this was
    // `expectLocation(router, RouteNames.home)`. `RouteNames.home` is '/' and
    // the helper matched with `startsWith`, so the assertion reduced to
    // `startsWith('/')` — true for every route in the app. It could not have
    // failed if SALON_OWNER had landed anywhere at all. `AppHarness
    // .expectLocation` now REJECTS '/' outright for exactly this reason, so
    // the exact landing path is asserted directly (the same shape Test 2 above
    // already uses for CLIENT).
    expect(
      AppHarness.location(router),
      equals(RouteNames.home),
      reason:
          'SALON_OWNER must land exactly on the ${RouteNames.home} placeholder',
    );
    expect(fb.loginCalls, equals(1));
  });
}
