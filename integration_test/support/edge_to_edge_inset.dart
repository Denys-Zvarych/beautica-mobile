// Phase 422 (targetSdk 36, edge-to-edge) — shared E2E helpers for a device
// bottom system inset.
//
// On Android 16 at targetSdk 36 the app ALWAYS draws edge-to-edge, so the
// navigation bar's height reaches Flutter as `MediaQuery.padding.bottom` /
// `viewPadding.bottom` (24 dp gesture pill, 48 dp 3-button bar). The
// `-d flutter-tester` window has no system bars, so every E2E flow runs at a
// zero inset — exactly the surface on which a missing `SafeArea` is invisible.
// These helpers put a real inset on the test view so a flow can prove the
// shared layout widgets keep their tappable content above it.
//
// REUSE-FIRST — one copy, used by every inset flow
// (client_shell_flow_test, client_leave_review_flow_test,
// master_leave_client_feedback_flow_test, settlement_autocomplete_flow_test).

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The 3-button navigation bar height, the larger of the two real insets.
const double kThreeButtonNavInset = 48;

/// Simulates a device bottom system inset of [logical] dp on the test view,
/// scaled to physical pixels by the view's own device-pixel ratio, and resets
/// it at tearDown. Call BEFORE [AppHarness.boot] so the first frame already
/// sees it (as a real device does). Returns the logical inset.
double simulateBottomSystemInset(
  WidgetTester tester, {
  double logical = kThreeButtonNavInset,
}) {
  final double physical = logical * tester.view.devicePixelRatio;
  tester.view.padding = FakeViewPadding(bottom: physical);
  tester.view.viewPadding = FakeViewPadding(bottom: physical);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
  return logical;
}

/// The logical y of the top edge of the simulated system inset — everything
/// tappable must end at or above it.
double insetTopEdge(WidgetTester tester, double inset) {
  final double height =
      tester.view.physicalSize.height / tester.view.devicePixelRatio;
  return height - inset;
}

/// Asserts the single widget [finder] matches lies ENTIRELY above the
/// simulated bottom inset (its bottom edge at or above the inset's top edge).
void expectAboveBottomInset(
  WidgetTester tester,
  Finder finder,
  double inset, {
  required String what,
}) {
  final Rect rect = tester.getRect(finder);
  final double edge = insetTopEdge(tester, inset);
  expect(
    rect.bottom,
    lessThanOrEqualTo(edge),
    reason:
        '$what must sit entirely above the ${inset}dp system navigation bar '
        '(bottom ${rect.bottom} vs inset top $edge) — under edge-to-edge it '
        'would otherwise be drawn under the bar and the tap would land on the '
        'system UI',
  );
}
