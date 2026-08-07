// Shared assertions for VelvetSnack (`lib/shared/feedback/`) — the unified
// in-app notification component that is replacing raw
// `ScaffoldMessenger.of(context).showSnackBar(...)` call sites across the
// app, one screen at a time.
//
// READ THIS BEFORE PORTING A SNACKBAR TEST TO A MIGRATED SCREEN.
//
// WHY UNSCOPED FINDERS ARE REQUIRED
// ----------------------------------
// A VelvetSnack is shown via `Overlay.of(context, rootOverlay: true)`
// (`velvet_snack_host.dart`), NOT `ScaffoldMessenger`. The inserted
// `OverlayEntry` is attached to the app's ROOT overlay, so it is a SIBLING of
// the routed screen subtree — never a descendant of it. Any finder of the
// shape `find.descendant(of: find.byType(Scaffold)/SnackBar/..., matching:
// find.text(...))` will therefore ALWAYS return `findsNothing` against a
// VelvetSnack, no matter how long you pump. There is also exactly one root
// overlay per test app, so an unscoped `find.text(message)` /
// `find.byType(VelvetSnack)` cannot accidentally match something unrelated —
// scoping buys nothing here and actively breaks the assertion.
//
// WHY DRAINING THE DWELL TIMER IS MANDATORY
// ------------------------------------------
// Every shown VelvetSnack starts a dwell `Timer` (`_VelvetSnackScopeState`)
// that fires the exit animation and removes the `OverlayEntry`. Two
// consequences, both proven root causes in this migration's first four
// screens:
//   1. `flutter_test` fails any test that ends with a pending `Timer` still
//      alive (the leak check in `tearDown`). A test that asserts a snack
//      appeared and then just calls `pumpAndSettle()`/ends will NOT drain a
//      timer whose fire time is still in the future relative to virtual
//      time — you must pump PAST it explicitly.
//   2. A still-mounted snack is bottom-anchored and can sit directly over a
//      screen's primary CTA. `ScaffoldMessenger.of(...).hideCurrentSnackBar()`
//      is a no-op against a VelvetSnack (wrong host entirely) — it neither
//      cancels the timer nor triggers the exit animation. A test that taps
//      through a still-showing snack hit-tests into the Overlay's
//      `_RenderTheater` instead of the button underneath, and the intended
//      tap silently does nothing. (Root-caused via `git stash -u` A/B on
//      `weekly_template_editor_screen_test.dart`'s M6 second-Save test —
//      passed on clean HEAD, failed once VelvetSnack replaced the snackbar.)
//
// Always pair a snack-triggering action with [pumpVelvetSnackIn] (or drive
// straight to [pumpPastVelvetSnack] if you don't need to assert the snack's
// content) and, before doing anything else that depends on the screen
// underneath being interactive again, call [pumpPastVelvetSnack].

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps a just-triggered [VelvetSnack] through its entrance animation to
/// completion.
///
/// Call this immediately after the action that shows the snack (a button
/// tap, a submitted form, …). The first `pump()` lets the triggering future
/// resolve and mounts the `OverlayEntry`; the second drives
/// [VelvetSnackMotion.enter] to completion so the snack is fully settled
/// (not mid-slide/fade) before you assert against it.
Future<void> pumpVelvetSnackIn(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(VelvetSnackMotion.enter);
}

/// Asserts a [VelvetSnack] is currently showing [message].
///
/// Finders here are deliberately UNSCOPED — see this file's header for why a
/// root-overlay snack can never be a descendant of the screen subtree.
/// Optionally asserts the [variant] (success/error/info/warning) and, when
/// the snack carries a trailing action, [actionLabel].
void expectVelvetSnack(
  String message, {
  String? actionLabel,
  VelvetSnackVariant? variant,
}) {
  final Finder snackFinder = find.byType(VelvetSnack);
  expect(snackFinder, findsOneWidget);
  expect(find.text(message), findsOneWidget);

  if (variant != null) {
    final VelvetSnack snack =
        snackFinder.evaluate().single.widget as VelvetSnack;
    expect(
      snack.variant,
      variant,
      reason: 'expected the showing VelvetSnack to be $variant',
    );
  }

  if (actionLabel != null) {
    expect(find.text(actionLabel), findsOneWidget);
  }
}

/// Advances virtual time past a shown [VelvetSnack]'s FULL lifecycle
/// (entrance + dwell + exit) and settles, so:
///   * the dwell `Timer` fires and is drained (no pending-timer leak), and
///   * the `OverlayEntry` is removed, so a bottom-anchored CTA it may have
///     covered becomes hit-testable again.
///
/// Pass [hasAction] `true` when the snack carries a trailing action — those
/// dwell for [VelvetSnackMotion.dwellWithAction] (6s) instead of the default
/// [VelvetSnackMotion.dwell] (4s), matching the approved design spec.
///
/// Safe to call even if the snack already fully entered/settled earlier in
/// the test (e.g. after an intervening `pumpAndSettle()`) — pumping past its
/// lifecycle again is a harmless no-op once the timer has already fired.
Future<void> pumpPastVelvetSnack(
  WidgetTester tester, {
  bool hasAction = false,
}) async {
  final Duration dwell = hasAction
      ? VelvetSnackMotion.dwellWithAction
      : VelvetSnackMotion.dwell;
  await tester.pump(VelvetSnackMotion.enter + dwell + VelvetSnackMotion.exit);
  await tester.pumpAndSettle();
}
