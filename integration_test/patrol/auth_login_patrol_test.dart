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

  // ⚠️ TEMPORARY BISECT, ROUND 2 — REVERT THIS SKIP ONCE THE RUN REPORTS. ⚠️
  //
  // This test is not broken; it is the one that PASSES. It is skipped for one
  // run so that the CLIENT login case below runs FIRST instead of second.
  //
  // Round 1 skipped the CLIENT test and the emulator survived — including
  // through `deep_link_patrol_test`, which does its own full
  // `pumpWidgetAndSettle(ProviderScope(child: BeauticaApp()))`, i.e. a second
  // app mount. So "the second mount kills the session" is already falsified;
  // the failure tracks the CLIENT test specifically, not its position.
  //
  // Round 2 separates the last two possibilities:
  //   • CLIENT passes when it runs first  → the trigger needs a PRECEDING mount
  //     (cumulative GL/graphics state), not the CLIENT screen on its own.
  //   • CLIENT still kills the device     → it is that screen, full stop. The
  //     suspect is then the five-tab StatefulShellRoute client shell
  //     (RouteNames.clientHome == '/home', five independent navigators) versus
  //     the far lighter /master/profile tree test 1 lands on.
  patrolTest(
    'INDEPENDENT_MASTER login navigates to master profile route (patrol template) '
    '(TEMPORARILY SKIPPED: bisect round 2 — running CLIENT login first; '
    'restore as soon as the run reports)',
    skip: true,
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

  // ⚠️ RESTORED — this is the test under investigation. Do not skip it again
  // without reading the round-2 note above; it must RUN for that bisect.
  //
  // History, so nobody re-derives it: when this test ran SECOND it killed the
  // emulator every time — `device 'emulator-5554' not found`, twice on two
  // commits, byte-for-byte, with patrol reporting ZERO failed assertions. Test
  // 1 passed in 6s each time. Round 1 skipped this test and the emulator
  // survived the whole suite, which falsified "the second app mount kills the
  // session" (deep_link_patrol_test does its own full mount and was fine).
  //
  // Also already ruled out, do not re-propose: the background app-link
  // re-approval loop (cadence cut 5x, failure byte-identical), and the adb
  // binary/server resolution mismatch (one server, no version conflict —
  // `patrol doctor`'s "adb not found" is step-ordering, it runs before the
  // emulator action puts platform-tools on PATH).
  //
  // NOTE the assertion at the end of this test is currently vacuous:
  // `RouteNames.home` is '/', and expectLocation matches with startsWith, so it
  // admits every route in the app. Separately under review — do not treat a
  // green result here as proof the CLIENT lands anywhere in particular.
  patrolTest(
    'CLIENT login navigates to home placeholder route (patrol template)',
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
