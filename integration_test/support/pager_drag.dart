// Shared hand-driven drag recipe for the «Мої записи» week-rail and
// month-calendar `PageView`/`PageScrollPhysics` pagers.
//
// WHY THIS EXISTS
// ----------------
// Both pagers only turn one page at a time and only build the current page
// (plus whatever the viewport's cache extent reaches), so an E2E test that
// needs to land on a specific week/month must drive a REAL page turn, not a
// scroll. `dragPagerByOnePage` is that recipe, hoisted here after FOUR
// independent hand-copies of it existed across `integration_test/`
// (`master_bookings_week_rail_flow_test.dart`,
// `master_bookings_month_step_flow_test.dart`,
// `master_bookings_working_hours_window_flow_test.dart`,
// `master_bookings_flow_test.dart`) and two of them silently drifted to a
// `steps = 4` copy that no longer reliably turns the page — see "THE STEPS=4
// REGRESSION" below. One definition here is the only way that cannot recur.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';

/// Turns the pager identified by [pagerKey] by exactly one page, [forward]
/// or back.
///
/// ⚠ NOT `tester.fling`. The E2E tier runs on
/// `IntegrationTestWidgetsFlutterBinding` — a LIVE binding, where `fling`'s
/// internally-pumped move sequence does not reliably deliver a velocity the
/// ballistic settle can act on: a single `fling(…, Offset(-300, 0), 800)`
/// against either pager was measured leaving it on its original page, with no
/// warning and no error (`master_bookings_week_rail_flow_test.dart` and
/// `master_bookings_month_step_flow_test.dart` both first landed on exactly
/// that and were RED — the only symptom was each file's own fixture guard,
/// e.g. "the month step did not relabel the calendar at all". The identical
/// call IS reliable at the widget tier, on the fake-async binding, which is
/// why the equivalent widget tests stayed green through it). A
/// `fling`-in-a-loop version fared no better: it FLAKED, reaching the target
/// on one run and exhausting every attempt on the next.
///
/// This drives the pointer by hand instead: one down, eight 40 ms-spaced
/// moves totalling 60% of the pager's own width, one up. That is past the
/// page midpoint on DISTANCE alone, so the settle lands on the next page even
/// if the velocity tracker reports nothing at all — the assertion is about
/// the page turning, not about `PageScrollPhysics`' fling tolerance. Each
/// move carries an explicit, advancing `timeStamp` and is followed by a pump
/// of the same length, so the sampled velocity is a real number rather than a
/// division by zero elapsed time.
///
/// THE STEPS=4 REGRESSION (mobile-debugger, 2026-08-14)
/// ------------------------------------------------------
/// Two of the four pre-hoist copies carried `steps = 4` instead of `8` —
/// half the sample density, same 60%-of-width total distance. That is not a
/// smaller, faster version of the same recipe: with 4 samples,
/// `PageController.page` was observed FREEZING mid-drag (stuck at `260.0`)
/// and never crossing the page boundary, even stretched to the same total
/// elapsed time as the 8-step version. The sample COUNT is what matters, not
/// the distance or the duration. Do not reduce `steps` below 8 to save time —
/// it does not save time, it produces a pager that never turns and a target
/// chip/label that never mounts, surfacing as an unrelated-looking assertion
/// failure or, in a caller that retries in a loop (see `_selectRailDay` in
/// the booking flows), a many-minute timeout.
///
/// Does not include a trailing debounce-window pump — some callers need one
/// (an assertion right after the turn cares whether a debounced selection
/// fired), some don't (callers that page in a bounded retry loop before a
/// single eventual tap, where a pump per iteration would multiply into a
/// needless multi-second tax). Add it at the call site when needed.
Future<void> dragPagerByOnePage(
  WidgetTester tester,
  Key pagerKey, {
  required bool forward,
}) async {
  final Finder finder = find.byKey(pagerKey);
  final double width = tester.getRect(finder).width;
  const int steps = 8;
  final double dx = (forward ? -1 : 1) * (width * 0.6) / steps;

  final TestGesture gesture = await tester.startGesture(
    tester.getCenter(finder),
  );
  Duration stamp = Duration.zero;
  for (int i = 0; i < steps; i++) {
    stamp += const Duration(milliseconds: 40);
    await gesture.moveBy(Offset(dx, 0), timeStamp: stamp);
    // fixed-wait-ok: advancing the pointer-sample clock in lockstep with the
    // synthetic move timestamps, not waiting on a condition.
    await tester.pump(const Duration(milliseconds: 40));
  }
  await gesture.up();
  await AppHarness.settle(tester);
}
