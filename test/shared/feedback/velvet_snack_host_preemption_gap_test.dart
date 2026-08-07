// Regression tests for two related single-slot leaks in
// `lib/shared/feedback/velvet_snack_host.dart` — found by three independent
// audits (mobile-perf HIGH, mobile-security MEDIUM, mobile-qa INFO) from
// three different directions, but traced to the SAME root cause: the
// component's bookkeeping used to treat "the slot reads as free" and "the
// previous entry is genuinely gone from the Overlay" as the same moment.
// They are not, and every gap between them was a window where two snacks
// were simultaneously on screen — exactly the overlap the design doc's
// single-slot guarantee (`velvet_snack_host.dart`'s file header, "Why an
// `Overlay`, not `ScaffoldMessenger`") promises can never happen.
//
// WHY NEITHER EXISTING FILE CATCHES THIS
// ---------------------------------------
// `velvet_snack_host_race_test.dart` fires two `showVelvetSnack` calls in
// ONE synchronous tick with no `pump()` between them — it only exercises the
// SAME-TICK pre-claim branch in `_VelvetSnackOverlay.show`, not either bug
// below (both need a real elapsed-time gap to open the window).
// `velvet_snack_host_test.dart`'s "single-slot pre-emption across a real
// async gap" test drives exactly TWO overlapping `show()` calls to
// completion — it proves the two-hop case serializes, but a two-hop chain
// cannot reach either defect: bug 1 only appears on the THIRD call in a
// chain (a queued, not-yet-mounted occupant asked to retire while it is
// itself still waiting on its own predecessor); bug 2 needs a snack that
// reached its OWN dwell-timeout or action-tap retirement, not one pre-empted
// by another `show()` call.
//
// Both tests below were confirmed RED against the pre-fix code (`onSlotFreed`
// fired before the real exit; `retireAndClear` treated "not mounted" as
// "already fully gone" with no `pendingInsert` to chain onto) and GREEN
// after — see the mobile-dev handoff note for the exact revert used to prove
// it.

import 'dart:async';

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack_host.dart'
    show VelvetSnackHandle;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/velvet_snack_matchers.dart';

const Key _anchorKey = Key('velvet-snack-host-preemption-gap-test-anchor');

const Widget _anchor = Scaffold(body: SizedBox.shrink(key: _anchorKey));

void _fire(
  WidgetTester tester, {
  required String message,
  required VelvetSnackVariant variant,
}) => showVelvetSnack(
  tester.element(find.byKey(_anchorKey)),
  message: message,
  variant: variant,
);

/// Pumps in small [step]s for [total] virtual time, asserting at every
/// intermediate frame that never more than one [VelvetSnack] is mounted —
/// the single-slot invariant itself, checked continuously rather than only
/// at the end. A test that only asserts after `pumpAndSettle()` would miss a
/// transient overlap entirely; this is the whole reason these two tests
/// exist.
Future<void> _pumpAssertingSingleSlot(
  WidgetTester tester, {
  required Duration total,
  Duration step = const Duration(milliseconds: 15),
}) async {
  final int steps = (total.inMicroseconds / step.inMicroseconds).ceil();
  for (int i = 0; i < steps; i++) {
    await tester.pump(step);
    expect(
      find.byType(VelvetSnack).evaluate().length,
      lessThanOrEqualTo(1),
      reason:
          'never more than one VelvetSnack may be mounted at once, even '
          'mid pre-emption — saw more at step $i (t≈${step * (i + 1)})',
    );
  }
}

void main() {
  group('chained pre-emption across three show() calls', () {
    testWidgets('a third show() call, arriving while the second is still queued '
        "behind the first's in-flight exit, never lets two snacks coexist at "
        'any intermediate frame', (tester) async {
      await tester.pumpApp(_anchor);

      _fire(tester, message: 'First', variant: VelvetSnackVariant.info);
      await tester.pump();
      await tester.pump(VelvetSnackMotion.enter);
      expect(find.text('First'), findsOneWidget);

      // Pre-empt First with Second — Second's own insert is now deferred
      // behind First's real (120ms `replace`) exit.
      _fire(tester, message: 'Second', variant: VelvetSnackVariant.success);

      // A genuine gap — NOT the same synchronous tick — long enough that
      // Second is definitely still queued (First's replace exit is
      // 120ms) but nowhere near long enough for Second to have mounted.
      // fixed-wait-ok: lands Third's show() mid-flight while Second is queued-but-unmounted behind First's 120ms replace exit.
      await tester.pump(const Duration(milliseconds: 10));
      expect(
        find.text('Second'),
        findsNothing,
        reason: 'sanity check: Second must still be queued, not mounted',
      );

      // Pre-empt Second with Third *while Second is still queued and
      // unmounted behind First*. This is the exact shape mobile-perf's
      // HIGH finding named (triple-tapping «Зберегти»): before the fix,
      // Second's `retireAndClear` saw its own `key.currentState == null`
      // and reported itself "already gone" immediately, so Third's insert
      // fired without ever waiting for First's still-running exit.
      _fire(tester, message: 'Third', variant: VelvetSnackVariant.warning);

      // Step through First's remaining exit and Third's entrance — the
      // single-slot invariant must hold at every intermediate frame.
      await _pumpAssertingSingleSlot(
        tester,
        total:
            VelvetSnackMotion.replace +
            VelvetSnackMotion.enter +
            const Duration(milliseconds: 100),
      );
      await tester.pumpAndSettle();

      expect(find.text('Third'), findsOneWidget);
      expect(find.text('Second'), findsNothing);
      expect(find.text('First'), findsNothing);

      await pumpPastVelvetSnack(tester);
    });
  });

  group('retire-window collision with an unrelated show()', () {
    testWidgets(
      'an unrelated show() call fired while a dwell-timed-out snack is '
      'still mid-exit must wait for that exit to actually finish before '
      'inserting',
      (tester) async {
        await tester.pumpApp(_anchor);

        _fire(tester, message: 'First', variant: VelvetSnackVariant.info);
        await tester.pump();
        await tester.pump(VelvetSnackMotion.enter);
        expect(find.text('First'), findsOneWidget);

        // Run the clock right up to the dwell timeout — First's own retire
        // Timer fires at the very end of this pump and starts its normal
        // 200ms exit; not one frame of that exit has run yet.
        await tester.pump(VelvetSnackMotion.dwell);

        // An UNRELATED show() call, mid-exit — well inside the 200ms exit
        // window. This is the mobile-security MEDIUM finding's shape: the
        // documented 503-retry pattern (`service_setup_screen.dart`) fires
        // exactly this from an async network callback. Before the fix,
        // `_retire` freed the slot (`onSlotFreed`) BEFORE awaiting the
        // reverse animation, so this call would read `_current == null` and
        // insert immediately instead of pre-empting through
        // `retireAndClear`.
        _fire(tester, message: 'Other', variant: VelvetSnackVariant.error);

        // Step through First's remaining exit and Other's entrance — well
        // short of the 200ms exit alone at the earliest checkpoints — the
        // single-slot invariant must hold throughout.
        await _pumpAssertingSingleSlot(
          tester,
          total: VelvetSnackMotion.exit + VelvetSnackMotion.enter,
        );
        await tester.pumpAndSettle();

        expect(find.text('Other'), findsOneWidget);
        expect(find.text('First'), findsNothing);

        await pumpPastVelvetSnack(tester);
      },
    );
  });

  group('dismiss() on a queued, not-yet-mounted occupant', () {
    testWidgets(
      "calling a handle's dismiss() before its snack has mounted actually "
      'cancels it, instead of silently no-op-ing because '
      '`key.currentState` is still null',
      (tester) async {
        await tester.pumpApp(_anchor);

        _fire(tester, message: 'First', variant: VelvetSnackVariant.info);
        await tester.pump();
        await tester.pump(VelvetSnackMotion.enter);
        expect(find.text('First'), findsOneWidget);

        // Pre-empt First with Second. Second's own insert is now deferred
        // behind First's real (120ms `replace`) exit — Second's
        // `initState` has not run yet, so `key.currentState == null` for
        // it right now and for the rest of this test.
        final VelvetSnackHandle secondHandle = showVelvetSnack(
          tester.element(find.byKey(_anchorKey)),
          message: 'Second',
          variant: VelvetSnackVariant.success,
        );

        // Dismiss it immediately, synchronously, in this same tick — well
        // before Second could ever mount. Fire-and-forget, exactly like
        // `service_setup_screen.dart`'s `dispose()` calling
        // `unawaited(_retrySnack?.dismiss())`.
        unawaited(secondHandle.dismiss());

        // Step through the entire window First's exit AND Second's
        // would-be entrance would have spanned, asserting at every
        // intermediate frame — not just at the end — that Second's message
        // never appears. Before the fix, `dismiss()` read
        // `_key.currentState` (null, since Second never mounted) and
        // returned an instantly-resolved future that did nothing: Second
        // would still insert once First's exit finished and display for
        // its full dwell.
        final Duration window =
            VelvetSnackMotion.replace +
            VelvetSnackMotion.enter +
            VelvetSnackMotion.dwell +
            VelvetSnackMotion.exit;
        const Duration step = Duration(milliseconds: 15);
        final int steps = (window.inMicroseconds / step.inMicroseconds).ceil();
        for (int i = 0; i < steps; i++) {
          await tester.pump(step);
          expect(
            find.text('Second'),
            findsNothing,
            reason:
                'Second was dismissed while still queued and must never '
                'mount — saw it at step $i (t≈${step * (i + 1)})',
          );
        }
        await tester.pumpAndSettle();

        expect(find.text('Second'), findsNothing);
        expect(find.text('First'), findsNothing);
        expect(find.byType(VelvetSnack), findsNothing);

        await pumpPastVelvetSnack(tester);
      },
    );
  });
}
