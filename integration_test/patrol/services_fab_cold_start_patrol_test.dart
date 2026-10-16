// Device-level regression for the «+ Додати послуги» freeze — REAL vsync.
//
// THE BUG
// -------
// flutter_riverpod 3.1.0 called a mid-frame `ProviderScope.setState` from
// `_flutterVsync` while `finalizeTree` disposed an auto-dispose provider that
// had just lost its last listener. Flutter's frame scheduler was left wedged:
// taps were still delivered, but no frame was ever drawn again. On the SM-M127F
// it hit about half of the cold starts that went straight to «Мої послуги»
// (4/8 on 3.1.0, 0/12 on 3.3.1). The fix is the 3.3.1 upgrade.
//
// WHY THIS IS A PATROL TEST AND NOT AN integration_test FLOW
// ---------------------------------------------------------
// Every `flutter test` harness drives frames itself with `pump`, which papers
// over a wedged scheduler: the pump draws the frame the engine never would.
// Here, after login, NOTHING calls `pump`/`pumpAndSettle`. Taps go through
// the raw `WidgetTester.tap` (which dispatches the pointer and returns without
// pumping), and every wait is a wall-clock poll of the element tree — which
// only changes when the ENGINE draws a real frame (`PatrolBinding` is a
// `LiveTestWidgetsFlutterBinding`, so engine-scheduled frames run on their
// own). If the scheduler wedges, the setup screen never builds and the poll
// times out.
//
// COLD STARTS
// -----------
// Five separate `patrolTest` cases rather than a loop in one body: under
// PatrolJUnitRunner + ANDROIDX_TEST_ORCHESTRATOR every case runs in a FRESH
// app process (clearPackageData stays false — see build.gradle.kts), so each
// case is a genuine cold start. Five, because the bug hit ~50% of runs:
// 0.5^5 ≈ 3% chance a regression slips through one CI run.
//
// RUNS ON CI ONLY — the nightly / labelled patrol job (`patrol test --target
// integration_test/patrol`); this file is picked up by that directory target.
//
// No `/` in any test description (AndroidTestOrchestrator per-test filename).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/services/presentation/service_setup_screen.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import '../support/app_harness.dart' show AppHarness;
import 'support/patrol_harness.dart';

/// How long a REAL frame may take to show the next screen. Generous: a
/// healthy route lands in well under a second even on the CI emulator; a
/// wedged scheduler never lands at all.
const Duration _frameTimeout = Duration(seconds: 15);

/// Polls [finder] on the wall clock until it matches, WITHOUT pumping. The
/// element tree only changes when the engine draws a frame, so this proves
/// real frames are flowing.
Future<void> _waitForRealFrame(
  Finder finder,
  String what, {
  bool gone = false,
}) async {
  final Stopwatch elapsed = Stopwatch()..start();
  while (finder.evaluate().isEmpty != gone) {
    if (elapsed.elapsed > _frameTimeout) {
      fail(
        'no frame showed $what within ${_frameTimeout.inSeconds}s of real '
        'time — the frame scheduler is wedged (the flutter_riverpod 3.1.0 '
        'mid-frame ProviderScope.setState freeze) or the tap never landed',
      );
    }
    // fixed-wait-ok: wall-clock poll interval of a condition-based wait; deliberately NOT a pump — the test proves the ENGINE draws frames on its own.
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  const PatrolTesterConfig config = PatrolTesterConfig(
    settlePolicy: SettlePolicy.trySettle,
  );

  tearDown(PatrolHarness.tearDownHarness);

  for (int run = 1; run <= 5; run++) {
    patrolTest(
      'cold start run $run of 5 - INDEPENDENT_MASTER services tab then add '
      'services FAB opens the setup screen on real frames',
      config: config,
      ($) async {
        final FakeBackend fb = FakeBackend()
          ..currentRole = UserRole.independentMaster;
        final router = await PatrolHarness.boot($, fb);
        await PatrolHarness.loginAs($, fb, UserRole.independentMaster);
        AppHarness.expectLocation(router, RouteNames.masterProfile);

        // ── From here on: NO pump. Raw taps + real-frame polls only. ────────
        await $.tester.tap(find.byKey(const Key('master-nav-tile-0')));
        final Finder fab = find.byKey(const Key('btn-create-service'));
        await _waitForRealFrame(fab.hitTestable(), '«Мої послуги» (the FAB)');
        expect(find.byType(ServicesListScreen), findsOneWidget);

        await $.tester.tap(fab);
        final Finder close = find.byKey(const Key('btn-setup-close'));
        await _waitForRealFrame(close.hitTestable(), 'the setup screen');
        expect(
          find.byType(ServiceSetupScreen, skipOffstage: false),
          findsOneWidget,
          reason: 'one FAB tap must open exactly one setup screen',
        );

        await $.tester.tap(close);
        await _waitForRealFrame(
          find.byType(ServiceSetupScreen, skipOffstage: false),
          'the setup screen popped',
          gone: true,
        );
        await _waitForRealFrame(
          fab.hitTestable(),
          'the return to «Мої послуги»',
        );
      },
    );
  }
}
