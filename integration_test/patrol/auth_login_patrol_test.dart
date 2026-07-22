// Phase 17.5 — patrol TEMPLATE flow (ported from the pure-Flutter
// integration_test/auth_login_flow_test.dart).
//
// PURPOSE
// -------
// This is the reference for converting an existing integration_test flow to a
// patrol binding. It runs the SAME deterministic fake-backend journey
// (cold-start → /login → fill credentials → submit → role-appropriate home) but
// through `patrolTest(...)` + `PatrolIntegrationTester ($)` instead of
// `testWidgets(...)` + `WidgetTester`.
//
// The original integration_test/auth_login_flow_test.dart is NOT deleted — the
// pure-Flutter version stays on the FAST headless job
// (`flutter test integration_test/all_tests.dart`). Only flows that genuinely
// need `$.native.*` get promoted to patrol. This file exists as the porting
// template + to exercise the patrol toolchain on a known-good journey.
//
// HOW TO RUN (native instrumentation — NOT `flutter test`):
//   dart pub global activate patrol_cli   # once
//   patrol test --target integration_test/patrol/auth_login_patrol_test.dart
// Requires a running Android emulator/device. See integration_test/patrol/README.md.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:patrol/patrol.dart';

import 'support/patrol_harness.dart';

void main() {
  // Defaults are fine for a fake-backend tree; declared explicitly so the
  // native settle policy is visible at the call site.
  const config = PatrolTesterConfig(settlePolicy: SettlePolicy.trySettle);

  tearDown(PatrolHarness.tearDownHarness);

  void expectLocation(GoRouter router, String expected) {
    final current = router.routerDelegate.currentConfiguration.uri.toString();
    expect(
      current,
      startsWith(expected),
      reason: 'Expected router location to start with $expected, got $current',
    );
  }

  patrolTest(
    'INDEPENDENT_MASTER login navigates to master profile route (patrol template)',
    config: config,
    ($) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      final router = await PatrolHarness.boot($, fb);

      // Cold start with no stored token → login form is visible.
      expect(
        find.byKey(const ValueKey<String>('login_email')),
        findsOneWidget,
        reason: 'Login form must be visible on cold start',
      );

      await PatrolHarness.loginAs($, fb, UserRole.independentMaster);

      expectLocation(router, RouteNames.masterProfile);
      expect(fb.loginCalls, equals(1));
    },
  );

  // ⚠️ TEMPORARY BISECT — REVERT THIS SKIP ONCE THE ANSWER IS IN. ⚠️
  //
  // This test is not broken. It is skipped for exactly one CI run, to answer a
  // single question about a device-loss failure that is NOT a flake.
  //
  // Observed twice, byte-for-byte identical on two different commits:
  //   test 1 (INDEPENDENT_MASTER login)  → ✅ passes in 6s
  //   test 2 (this one)                  → device dies
  //   `device 'emulator-5554' not found`; run ends ~87s
  //   patrol's own summary: 1 successful, 0 FAILED, 2 skipped
  // No assertion failed. The emulator went away underneath the run.
  //
  // Ruled out already: the background app-link re-approval loop (cadence was
  // cut 5x from 1s to 5s — failure was unchanged, so adb contention from that
  // loop is NOT the cause). Also note the captured logcat contains ZERO
  // `beautica` lines and ends during boot chatter, i.e. the background
  // `adb logcat` lost the device before the app ever started, and
  // `[EmulatorConsole]: Failed to start Emulator console for 5554` is printed
  // before any test runs.
  //
  // THE QUESTION THIS SKIP ANSWERS:
  //   • If the run now dies on the NEXT test instead → the failure is
  //     POSITIONAL (the second app restart / second PatrolHarness.boot kills
  //     the adb session), and nothing is wrong with this test.
  //   • If the remaining tests all pass → the failure is SPECIFIC to this
  //     CLIENT login flow, and the hunt narrows to what it does differently.
  // Either outcome halves the search space; neither depends on a hypothesis
  // being right first.
  patrolTest(
    'CLIENT login navigates to home placeholder route (patrol template) '
    '(TEMPORARILY SKIPPED: one-run bisect for the emulator device-loss '
    'failure — see the comment above; restore as soon as the run reports)',
    skip: true,
    config: config,
    ($) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final router = await PatrolHarness.boot($, fb);

      expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);

      await PatrolHarness.loginAs($, fb, UserRole.client);

      expectLocation(router, RouteNames.home);
      expect(fb.loginCalls, equals(1));
    },
  );
}
