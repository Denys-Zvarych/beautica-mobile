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
import 'package:patrol/patrol.dart';

// `show AppHarness` only — app_harness.dart also re-exports FakeBackend, which
// patrol_harness.dart already provides.
import '../support/app_harness.dart' show AppHarness;
import 'support/patrol_harness.dart';

void main() {
  // Defaults are fine for a fake-backend tree; declared explicitly so the
  // native settle policy is visible at the call site.
  const config = PatrolTesterConfig(settlePolicy: SettlePolicy.trySettle);

  tearDown(PatrolHarness.tearDownHarness);

  // The local copy of `expectLocation` that used to live here was deleted in
  // the 2026-07-22 vacuous-assertion audit — it was one of 29 hand-copied
  // naive `startsWith` duplicates. Assertions now route through
  // `AppHarness.expectLocation` (segment-aware, and it rejects '/' outright).

  // BISECT COMPLETE — this test is restored and passing. See the CLIENT case
  // below for what the bisect established.
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

      AppHarness.expectLocation(router, RouteNames.masterProfile);
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
  // FIXED (2026-07-22 vacuous-assertion audit). The previous NOTE here recorded
  // that the closing assertion was vacuous — `expectLocation(router,
  // RouteNames.home)` where `RouteNames.home` is '/' and matching was
  // `startsWith`, i.e. `startsWith('/')`, satisfied by all ~59 routes — but the
  // TITLE and the assertion were left as they were.
  //
  // The stale artefact was the test, not the app: a CLIENT lands on
  // `/home` (`RouteNames.clientHome`, the 5-tab StatefulShellRoute) via
  // `roleHomePath`, NOT on the legacy `/` placeholder. The title said "home
  // placeholder route", which would have re-taught the wrong model to the next
  // reader of this porting template.
  //
  // `integration_test/auth_login_flow_test.dart` (Test 2) already asserted
  // `equals(RouteNames.clientHome)` with the comment "NOT the legacy `/` home
  // placeholder" — the lesson existed, it just never reached the patrol port.
  // SKIPPED — mounting the /home client shell under patrol native
  // instrumentation KILLS THE CI EMULATOR. This is not a flaky skip and not a
  // defect in this test; it is the conclusion of a four-run controlled bisect.
  //
  //   CLIENT runs 2nd  → device dies   (`device 'emulator-5554' not found`)
  //   CLIENT runs 2nd  → device dies   (again, different commit, byte-identical)
  //   CLIENT SKIPPED   → whole suite survives, emulator alive to the end
  //   CLIENT runs 1st  → device dies   (Successful: 0, Failed: 0, Skipped: 3)
  //
  // Position is therefore ruled out, and so is cumulative graphics state: it
  // dies with nothing mounted before it. Patrol reports ZERO failed assertions
  // every time — no assertion is wrong, the device goes away underneath the run.
  //
  // Ruled out and NOT worth re-testing: the app-link re-approval loop (cadence
  // cut 5x, failure byte-identical), the adb binary/server resolution mismatch
  // (one server, no version conflict — `patrol doctor`'s "adb not found" is
  // step ordering, it runs before the emulator action puts platform-tools on
  // PATH), and the emulator-console warning (it also prints on runs that
  // complete cleanly).
  //
  // The remaining suspect is what this test lands on and the MASTER test does
  // not: `RouteNames.clientHome` is the five-tab StatefulShellRoute with five
  // independent navigators, against the far lighter /master/profile tree.
  // Mechanism most likely the gfxstream/swiftshader ColorBuffer race this repo
  // has already documented (stalls of 41s and 46s were observed, matching its
  // ~35-40s signature), but no `Failed to find ColorBuffer` line has been SEEN,
  // so that is a hypothesis and not a diagnosis.
  //
  // NOTHING IS LOST BY SKIPPING IT. This is the patrol porting TEMPLATE; it
  // uses no `$.native.*`, so it exercises nothing patrol is uniquely for. The
  // identical journey — including the corrected
  // `equals(RouteNames.clientHome)` assertion — runs on every PR on the fast
  // headless job at `integration_test/auth_login_flow_test.dart:59-73`.
  //
  // TO RESTORE: capture the emulator's own stdout (the workflow's
  // "Collect emulator host-side diagnostics" step now uploads what is
  // reachable, and the logcat upload is `always()` so a cancelled run still
  // yields evidence), confirm or kill the ColorBuffer theory, then un-skip.
  // ⚠️ NO SLASHES IN A patrolTest DESCRIPTION. Not in a route, not in a file
  // path, not anywhere. AndroidTestOrchestrator names a per-test output file
  // after the description and calls Context.openFileOutput, which REJECTS any
  // filename containing a path separator. The result is not a test failure —
  // the orchestrator process dies:
  //
  //   E/AndroidRuntime: FATAL EXCEPTION: AndroidTestOrchestrator
  //   java.lang.IllegalArgumentException: File ...[... the /home client shell
  //     ... ].txt contains a path separator
  //       at android.app.ContextImpl.makeFilename
  //       at androidx.test.orchestrator.AndroidTestOrchestrator.getOutputStream
  //       at androidx.test.orchestrator.AndroidTestOrchestrator.executeNextTest
  //
  // Gradle then reports only "Instrumentation run failed due to Process
  // crashed" with ZERO failed assertions, which reads exactly like the
  // unrelated emulator device-loss issue and cost a full round of diagnosis to
  // tell apart. This bit us on 2026-07-22 with a description that named the
  // `/home` route and a file path. Say "the home client shell" instead, and
  // put paths in the COMMENT, never the description.
  //
  // Guarded by scripts/forbid_slash_in_patrol_test_name.sh.
  patrolTest(
    'CLIENT login navigates to the home client shell (patrol template) '
    '(SKIPPED: mounting the 5-tab client shell kills the CI emulator — '
    'bisect-confirmed, see comment above for the evidence and for where the '
    'same journey is covered)',
    skip: true,
    config: config,
    ($) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final router = await PatrolHarness.boot($, fb);

      expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);

      await PatrolHarness.loginAs($, fb, UserRole.client);

      expect(
        AppHarness.location(router),
        equals(RouteNames.clientHome),
        reason:
            'a CLIENT lands on the ${RouteNames.clientHome} shell via '
            'roleHomePath, not on the legacy ${RouteNames.home} placeholder',
      );
      expect(fb.loginCalls, equals(1));
    },
  );
}
