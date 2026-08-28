// Phase 17.3 — E2E: Auth Login Flow
//
// Journey: cold-start (no stored token) → /login renders → user fills
// credentials → taps Submit → app navigates to the role-appropriate home.
//
// Three cases:
//   1. CLIENT        → lands on /home (the Phase 13.1 5-tab client shell)
//   2. SALON_OWNER   → lands on /salons/mine (Phase 21.1 My Salons Hub)
//   3. INDEPENDENT_MASTER → lands on /master/profile (Phase 4.2)
//
// SALON_OWNER case UPDATED 2026-08-28 (Phase 21.1 Step 5) — `roleHomePath
// (UserRole.salonOwner)` used to fall through to the `_` wildcard and land on
// the bare `_Placeholder('home')` at `/`; it now points at
// `RouteNames.mySalons`. This test previously pinned the OLD placeholder
// landing and went RED the moment `role_home.dart` shipped the fix (a stale
// assertion, not a regression) — see `integration_test/
// salon_owner_landing_flow_test.dart` for the dedicated regression pin
// (resolved location AND page type) this phase's own Step 7 calls for; this
// file's case 3 is kept in sync so the pre-existing suite does not
// contradict it.
//
// All taps are key-based — no raw Ukrainian find.text() tap drivers.
// See integration_test/support/app_harness.dart for the policy rationale.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/salon/presentation/my_salons_screen.dart';
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

  // ── Test 3 — SALON_OWNER → My Salons Hub ──────────────────────────────────

  testWidgets('SALON_OWNER login navigates to /salons/mine (My Salons Hub)', (
    tester,
  ) async {
    final fb = FakeBackend()..currentRole = UserRole.salonOwner;
    final GoRouter router = await AppHarness.boot(tester, fb);

    expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);

    await AppHarness.loginAs(tester, fb, UserRole.salonOwner);

    // Phase 21.1 Step 5 — SALON_OWNER now lands on the My Salons Hub, not the
    // `/` placeholder. Assert BOTH the exact resolved location AND the
    // mounted page TYPE (not merely "some widget rendered") — the same
    // belt-and-braces shape `salon_owner_landing_flow_test.dart` uses for its
    // dedicated regression pin.
    expect(
      AppHarness.location(router),
      equals(RouteNames.mySalons),
      reason: 'SALON_OWNER must land exactly on ${RouteNames.mySalons}',
    );
    expect(find.byType(MySalonsScreen), findsOneWidget);
    expect(fb.loginCalls, equals(1));
  });
}
