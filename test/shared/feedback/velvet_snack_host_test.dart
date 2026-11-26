// Widget-tier contract tests for the VelvetSnack HOST mechanism
// (`lib/shared/feedback/velvet_snack_host.dart`) — mobile-qa, 2026-08-06.
//
// WHY THIS FILE EXISTS
// ---------------------
// `velvet_snack_host_race_test.dart` guards exactly one invariant: two
// `showVelvetSnack` calls fired from the SAME synchronous tick must not both
// mount. That is the narrowest possible slice of the host's own contract.
// Nothing else about the mechanism the design doc promises — WHY 4s vs 6s,
// that `bottomInset` genuinely repositions the snack, that a swipe bypasses
// the dwell timer rather than merely looking like it does, and that the
// single-slot guarantee ALSO holds when a second call arrives after a real
// async gap (not the same tick) — had a test anywhere before this file.
//
// Every test here drives `showVelvetSnack` directly against a bare anchor
// widget's `BuildContext` rather than wiring up a button, since the host
// only needs SOME `BuildContext` under the root `Overlay` — this keeps each
// test's setup to the one line that actually matters.
//
// Finders here are UNSCOPED (root-overlay rule — see
// `velvet_snack_matchers.dart`'s file header) and dwell Timers are drained
// with `pumpPastVelvetSnack` before every test ends, per the same file's
// mandatory-drain rule.

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack_host.dart'
    show VelvetCountdownCurve, VelvetSnackHandle;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/velvet_snack_matchers.dart';

const Key _anchorKey = Key('velvet-snack-host-test-anchor');

/// A minimal pumped tree — just enough to hand `showVelvetSnack` a live
/// `BuildContext` under a `MaterialApp`'s root `Overlay`. No button, no
/// Scaffold chrome: nothing in this file is testing navigation or layout
/// around the trigger, only the host's own behaviour once triggered.
const Widget _anchor = Scaffold(body: SizedBox.shrink(key: _anchorKey));

/// Fires [showVelvetSnack] against a freshly-resolved anchor context —
/// re-resolved on every call (not cached) since the anchor's own
/// `BuildContext` can go stale across pumps in a long test.
VelvetSnackHandle _fire(
  WidgetTester tester, {
  required String message,
  required VelvetSnackVariant variant,
  String? actionLabel,
  VoidCallback? onAction,
  double bottomInset = 0,
}) => showVelvetSnack(
  tester.element(find.byKey(_anchorKey)),
  message: message,
  variant: variant,
  actionLabel: actionLabel,
  onAction: onAction,
  bottomInset: bottomInset,
);

void main() {
  group('dwell duration', () {
    testWidgets(
      'a plain snack (no action) retires at the 4s default — still up just '
      'before, gone just after',
      (tester) async {
        await tester.pumpApp(_anchor);
        _fire(tester, message: 'Plain', variant: VelvetSnackVariant.info);
        await tester.pump();
        await tester.pump(VelvetSnackMotion.enter);
        expect(find.byType(VelvetSnack), findsOneWidget);

        // Just short of the dwell window — must still be showing.
        await tester.pump(
          VelvetSnackMotion.dwell - const Duration(milliseconds: 200),
        );
        expect(
          find.byType(VelvetSnack),
          findsOneWidget,
          reason: 'must not retire before its 4s dwell has actually elapsed',
        );

        // Past dwell + the full exit animation — gone.
        await tester.pump(
          const Duration(milliseconds: 200) +
              VelvetSnackMotion.exit +
              const Duration(milliseconds: 50),
        );
        await tester.pumpAndSettle();
        expect(find.byType(VelvetSnack), findsNothing);
      },
    );

    testWidgets(
      'an action-bearing snack dwells 6s, not the 4s default — still up '
      'well past where the plain dwell would already have retired it',
      (tester) async {
        await tester.pumpApp(_anchor);
        _fire(
          tester,
          message: 'Retry me',
          variant: VelvetSnackVariant.error,
          actionLabel: 'Retry',
          onAction: () {},
        );
        await tester.pump();
        await tester.pump(VelvetSnackMotion.enter);
        expect(find.byType(VelvetSnack), findsOneWidget);

        // Past the PLAIN 4s dwell (+ margin) — must STILL be showing. If
        // `dwellWithAction` ever collapsed to the same value as `dwell`,
        // this snack would already be fully retired by this point (the
        // plain-dwell test above proves the 4s+exit window is enough time
        // for a full retirement).
        await tester.pump(
          VelvetSnackMotion.dwell + const Duration(milliseconds: 500),
        );
        expect(
          find.byType(VelvetSnack),
          findsOneWidget,
          reason:
              'an action snack must dwell 6s — it must not have retired yet '
              'at 4.5s',
        );

        // Now past the full 6s + exit — gone.
        await tester.pump(
          VelvetSnackMotion.dwellWithAction -
              VelvetSnackMotion.dwell -
              const Duration(milliseconds: 500) +
              VelvetSnackMotion.exit +
              const Duration(milliseconds: 100),
        );
        await tester.pumpAndSettle();
        expect(find.byType(VelvetSnack), findsNothing);
      },
    );
  });

  group('bottomInset positioning', () {
    testWidgets(
      'a larger bottomInset raises the snack further up the screen than 0',
      (tester) async {
        await tester.pumpApp(_anchor);

        _fire(tester, message: 'no inset', variant: VelvetSnackVariant.info);
        await tester.pump();
        await tester.pump(VelvetSnackMotion.enter);
        final double topNoInset = tester
            .getTopLeft(find.byType(VelvetSnack))
            .dy;
        await pumpPastVelvetSnack(tester);

        _fire(
          tester,
          message: 'with inset',
          variant: VelvetSnackVariant.info,
          bottomInset: VelvetSizes.bottomNavClearanceClient,
        );
        await tester.pump();
        await tester.pump(VelvetSnackMotion.enter);
        final double topWithInset = tester
            .getTopLeft(find.byType(VelvetSnack))
            .dy;

        expect(
          topWithInset,
          lessThan(topNoInset),
          reason:
              'a non-zero bottomInset must push the snack UP the screen '
              '(smaller top-edge dy) relative to bottomInset: 0 — equal '
              'positions would mean the caller-declared clearance never '
              'reaches the Positioned widget',
        );

        await pumpPastVelvetSnack(tester);
      },
    );
  });

  group('swipe-down dismissal', () {
    testWidgets(
      'a swipe-down dismisses immediately, well before the 4s dwell would '
      'have fired, and cancels the dwell Timer (no pending-timer leak)',
      (tester) async {
        await tester.pumpApp(_anchor);
        _fire(tester, message: 'swipe me', variant: VelvetSnackVariant.info);
        await tester.pump();
        await tester.pump(VelvetSnackMotion.enter);
        expect(find.byType(VelvetSnack), findsOneWidget);

        await tester.drag(
          find.byKey(const Key('velvet_snack_dismissible')),
          const Offset(0, 400),
        );
        await tester.pump();
        await tester.pumpAndSettle();

        expect(
          find.byType(VelvetSnack),
          findsNothing,
          reason:
              'a swipe-down must dismiss immediately — this pumpAndSettle() '
              'only drives the drag/fling animation to rest, nowhere near '
              'the 4s dwell, so a still-mounted snack here means the swipe '
              'path did not actually tear the entry down',
        );
        // Mutation-checked (mobile-qa): removing `widget.onRetired()` from
        // `_dismissImmediately` turns the assertion above red, as expected.
        // Separately removing its `_dwellTimer?.cancel()` line does NOT —
        // `_VelvetSnackScopeState.dispose()` (run when `onRetired()` removes
        // the `OverlayEntry`) cancels the same Timer as its own first
        // statement, so that specific line is redundant-but-harmless
        // defence in depth, not something this test (or the framework's
        // pending-Timer teardown check) can independently catch. Documented
        // here rather than left as an untested, unverifiable claim.
      },
    );
  });

  group('single-slot pre-emption across a real async gap', () {
    testWidgets(
      "a second show() call issued after a genuine gap (several pumps, NOT "
      'the same synchronous tick as the first) pre-empts the still-dwelling '
      'first snack — never two mounted at once, and the later call always '
      'wins the slot',
      (tester) async {
        await tester.pumpApp(_anchor);

        _fire(tester, message: 'First', variant: VelvetSnackVariant.info);
        await tester.pump();
        await tester.pump(VelvetSnackMotion.enter);
        expect(find.text('First'), findsOneWidget);

        // A real gap: time passes, several frames render, well inside the
        // first snack's 4s dwell — unlike
        // `velvet_snack_host_race_test.dart`, which fires both calls from
        // ONE synchronous handler and so can only ever exercise the
        // same-tick pre-claim branch in `_VelvetSnackOverlay.show`. This
        // drives the OTHER branch instead:
        // `previous.retireAndClear(...).then((_) => insert())`.
        // fixed-wait-ok: advances 500ms inside First's 4s dwell, well before the pre-empting call fires; nothing observable changes to pump-until on.
        await tester.pump(const Duration(milliseconds: 500));

        _fire(tester, message: 'Second', variant: VelvetSnackVariant.success);
        // Let the pre-empt's retire-then-insert chain (120ms replace exit,
        // then the new entrance) actually run to completion.
        await tester.pumpAndSettle();

        expect(
          find.byType(VelvetSnack),
          findsOneWidget,
          reason:
              'single-slot: never two overlapping snacks, even across a '
              'real async gap',
        );
        expect(find.text('Second'), findsOneWidget);
        expect(find.text('First'), findsNothing);

        await pumpPastVelvetSnack(tester);
      },
    );
  });

  // M544 — `showCountdown`: the bar drains over the dwell and is empty when
  // the dwell Timer retires the snack; reduced motion steps it per second.
  group('countdown (M544)', () {
    const Duration window = Duration(seconds: 5);
    final Finder bar = find.byKey(VelvetSnack.countdownKey);

    double value(WidgetTester tester) => tester
        .widget<FractionallySizedBox>(
          find.descendant(of: bar, matching: find.byType(FractionallySizedBox)),
        )
        .widthFactor!;

    void show(WidgetTester tester, {bool countdown = true}) => showVelvetSnack(
      tester.element(find.byKey(_anchorKey)),
      message: 'Клієнта прибрано зі списку',
      variant: VelvetSnackVariant.info,
      actionLabel: 'Повернути',
      onAction: () {},
      duration: window,
      showCountdown: countdown,
    );

    testWidgets('default: no bar', (tester) async {
      await tester.pumpApp(_anchor);
      show(tester, countdown: false);
      await pumpVelvetSnackIn(tester);
      expect(find.byType(VelvetSnack), findsOneWidget);
      expect(bar, findsNothing);
      await pumpPastVelvetSnack(tester, hasAction: true);
    });

    testWidgets('the bar is full through the entrance, drains over the '
        'dwell and reaches 0 as the snack retires', (tester) async {
      await tester.pumpApp(_anchor);
      show(tester);
      await tester.pump();
      await tester.pump(VelvetSnackMotion.enter);
      expect(value(tester), closeTo(1, 0.01));

      // fixed-wait-ok: samples the countdown at exact elapsed times — the
      // elapsed time IS the quantity under test.
      await tester.pump(const Duration(seconds: 2));
      final double mid = value(tester);
      expect(mid, closeTo(0.6, 0.02));

      // fixed-wait-ok: samples the countdown at exact elapsed times — the
      // elapsed time IS the quantity under test.
      await tester.pump(const Duration(seconds: 2));
      expect(value(tester), lessThan(mid));
      expect(value(tester), closeTo(0.2, 0.02));

      // The dwell Timer fires at enter + window: the bar is empty then.
      // fixed-wait-ok: samples the countdown at exact elapsed times — the
      // elapsed time IS the quantity under test.
      await tester.pump(const Duration(milliseconds: 1000));
      expect(value(tester), closeTo(0, 0.001));
      await tester.pump(VelvetSnackMotion.exit);
      await tester.pump(VelvetSnackMotion.exit);
      expect(find.byType(VelvetSnack), findsNothing);
    });

    testWidgets('reduced motion: the bar steps once per second (whole '
        'seconds left, rounded up) and still lasts the full window', (
      tester,
    ) async {
      // The snack lives in the ROOT overlay, so the switch must be the
      // platform's (MaterialApp's MediaQuery), not a local MediaQuery.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpApp(_anchor);
      show(tester);
      await tester.pump();
      await tester.pump(VelvetSnackMotion.enter);
      expect(value(tester), 1);
      // fixed-wait-ok: samples the countdown at exact elapsed times — the
      // elapsed time IS the quantity under test.
      await tester.pump(const Duration(milliseconds: 400));
      expect(value(tester), 1, reason: '4.6 s left → 5 of 5 steps');
      // fixed-wait-ok: samples the countdown at exact elapsed times — the
      // elapsed time IS the quantity under test.
      await tester.pump(const Duration(milliseconds: 700));
      expect(value(tester), 0.8, reason: '3.9 s left → 4 of 5 steps');
      // fixed-wait-ok: samples the countdown at exact elapsed times — the
      // elapsed time IS the quantity under test.
      await tester.pump(const Duration(seconds: 3));
      expect(value(tester), 0.2, reason: '0.9 s left → 1 of 5 steps');
      expect(find.byType(VelvetSnack), findsOneWidget);
      await pumpPastVelvetSnack(tester, hasAction: true);
    });

    test('curve: held full through the entrance, linear over the dwell', () {
      const VelvetCountdownCurve curve = VelvetCountdownCurve(
        enter: Duration(seconds: 1),
        dwell: Duration(seconds: 4),
      );
      expect(curve.transform(1), 1);
      expect(curve.transform(0.9), 1); // still inside the entrance
      expect(curve.transform(0.4), closeTo(0.5, 1e-9));
      expect(curve.transform(0), 0);
    });
  });

  testWidgets('reduced motion: the bar is told to rebuild only when the '
      'stepped value changes (once per second), not every frame', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpApp(_anchor);
    showVelvetSnack(
      tester.element(find.byKey(_anchorKey)),
      message: 'Клієнта прибрано зі списку',
      variant: VelvetSnackVariant.info,
      actionLabel: 'Повернути',
      onAction: () {},
      duration: const Duration(seconds: 5),
      showCountdown: true,
    );
    await tester.pump();
    final ValueListenable<double> countdown = tester
        .widget<VelvetSnack>(find.byType(VelvetSnack))
        .countdown!;
    int notifications = 0;
    countdown.addListener(() => notifications++);
    // 2 s of ~60 fps frames → at most 2 stepped changes (+1 for the
    // entrance boundary), never ~120.
    for (int i = 0; i < 125; i++) {
      // fixed-wait-ok: one frame step — counting per-frame notifications IS
      // the quantity under test.
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(notifications, lessThanOrEqualTo(3));
    expect(notifications, greaterThanOrEqualTo(1));
    await pumpPastVelvetSnack(tester, hasAction: true);
  });
}
