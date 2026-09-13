// Shared pump-until helpers for the `test/routing/` route-guard suites.
//
// PROMOTED 2026-09-13 (audit D2). Three route-test files each carried a
// hand-copied private helper named `pumpWhile` —
//   `salon_manage_staff_services_route_test.dart:459`
//   `salon_master_own_services_route_test.dart:326`
//   `salon_manage_services_writable_route_test.dart:277`
// — and every copy RETURNED THE INSTANT ITS CONDITION HELD. It was a
// pump-UNTIL wearing a pump-WHILE name, and that inversion is the root cause
// of a whole defect class: handed a condition that is ALREADY TRUE ON ENTRY
// (`() => someFinder.evaluate().isEmpty`, right after a `router.go` that has
// not painted yet), it pumps ZERO frames and every assertion below it runs
// against the PRE-navigation tree. Two such rows were found dead by mutation
// — deleting the wait left them green
// (`salon_manage_staff_services_route_test.dart:1676` documents the first,
// `salon_master_own_services_route_test.dart` the second).
//
// So the helper is promoted here under its TRUE name, [pumpUntil], with the
// two finder shapes spelled out explicitly ([pumpUntilFound] /
// [pumpUntilGone]) so a call site can no longer read as its own opposite. No
// `pumpWhile` alias is left behind — an alias would keep the misleading
// spelling reachable, which is the whole thing being fixed.
//
// These are deliberately NOT the `PumpUntil` extension in
// `test/helpers/pump_app.dart`. That pair asserts on timeout and budgets 10 s
// in 100 ms steps; these poll 60 x 50 ms and return SILENTLY, because every
// route-suite call site follows the wait with its own explicit `expect` (very
// often a NEGATIVE one — `findsNothing`, `isNot(contains(...))`) where a
// timeout assertion inside the wait would fire before the row's real claim
// could be reported. Preserved byte-for-byte from the promoted copies so the
// rewire is behaviour-neutral.

import 'package:flutter_test/flutter_test.dart';

/// Pumps in 50 ms steps until [condition] holds, or the ~3 s budget runs out.
///
/// Returns the instant [condition] is true — so never hand it a condition that
/// is already true on entry, or it pumps nothing at all and whatever you
/// assert next is asserted against the tree you started with. Prefer
/// [pumpUntilFound] / [pumpUntilGone] whenever the thing being waited on is a
/// [Finder]; they name the direction of the wait for you.
Future<void> pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 60; i++) {
    if (condition()) return;
    // fixed-wait-ok: this IS pump-until — the loop exits the instant the
    // condition holds; 50 ms is only the polling step, not a guessed total.
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Pumps until [finder] has at least one match, or the budget runs out.
Future<void> pumpUntilFound(WidgetTester tester, Finder finder) =>
    pumpUntil(tester, () => finder.evaluate().isNotEmpty);

/// Pumps until [finder] matches NOTHING, or the budget runs out.
///
/// Only meaningful when [finder] currently matches something — otherwise the
/// condition holds on entry and this is a no-op.
Future<void> pumpUntilGone(WidgetTester tester, Finder finder) =>
    pumpUntil(tester, () => finder.evaluate().isEmpty);
