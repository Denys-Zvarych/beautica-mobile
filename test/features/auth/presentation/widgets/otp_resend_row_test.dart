// Beautica OTP task (Phase B1/B6) — widget tests for the shared
// [OtpResendRow] extracted from `verification_screen.dart`'s original
// `_ResendRow`/`_ResendRowState` (Fix B / MEDIUM-2).
//
// Covered scenarios:
//   1. initialCooldown = 0 shows resendLabel immediately (no countdown).
//   2. initialCooldown > 0 shows the countdown, ticking down to 0 → resendLabel.
//   3. Tapping resend (cooldown 0) calls onResend and optimistically starts
//      the assumed cooldown BEFORE the Future resolves.
//   4. onResend resolves with a DIFFERENT cooldown (throttle) → the countdown
//      adopts the server value instead of the optimistic one.
//   5. onResend resolves with null (generic error) → cooldown cancelled
//      immediately, resend re-enabled.
//   6. resetCooldown() via GlobalKey zeroes the cooldown immediately.
//   7. Tapping while cooldown > 0 does not call onResend again.
//   8. A cooldown ABOVE the 10-min UX ceiling, with the opt-in label
//      supplied, renders that non-numeric label and runs NO PERIODIC timer.
//   9. The SAME cooldown with no opt-in label keeps the old numeric
//      countdown + timer — the change is additive, not a replacement.
//  10. A cooldown BELOW the ceiling still counts down even when the
//      opt-in label IS supplied (the threshold, not the parameter,
//      decides).
//  11. The unavailable window ELAPSES on a single one-shot tick — frozen
//      label during it, row re-enabled after it, zero per-second rebuilds.

import 'dart:async';

import 'package:beautica_mobile/features/auth/presentation/widgets/otp_resend_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _kResendKey = ValueKey<String>('test_otp_resend');

Widget _harness({
  Key? rowKey,
  required Future<int?> Function() onResend,
  int initialCooldown = 0,
  int assumedCooldownSeconds = kDefaultOtpResendCooldownSeconds,
  String? resendUnavailableLabel,
  void Function()? onTimerLabelBuilt,
}) {
  return MaterialApp(
    home: Scaffold(
      body: OtpResendRow(
        key: rowKey,
        onResend: onResend,
        promptText: 'Prompt?',
        resendLabel: 'Resend now',
        resendTimerLabel: (seconds) {
          onTimerLabelBuilt?.call();
          return 'Resend in ${seconds}s';
        },
        resendKey: _kResendKey,
        initialCooldown: initialCooldown,
        assumedCooldownSeconds: assumedCooldownSeconds,
        resendUnavailableLabel: resendUnavailableLabel,
      ),
    ),
  );
}

void main() {
  group('OtpResendRow', () {
    testWidgets('1. initialCooldown = 0 shows resendLabel immediately', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(onResend: () async => 30));

      expect(find.text('Resend now'), findsOneWidget);
      expect(find.textContaining('Resend in'), findsNothing);
    });

    testWidgets('2. initialCooldown > 0 shows the countdown, ticking down to 0', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(onResend: () async => 30, initialCooldown: 3),
      );

      expect(find.text('Resend in 3s'), findsOneWidget);

      // fixed-wait-ok: TTL crossing — advances the widget's real 1s Timer.periodic by one tick.
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Resend in 2s'), findsOneWidget);

      // fixed-wait-ok: TTL crossing (see above).
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Resend in 1s'), findsOneWidget);

      // fixed-wait-ok: TTL crossing (see above) — final tick reaches 0.
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Resend now'), findsOneWidget);
    });

    testWidgets(
      '3. tapping resend calls onResend and starts the optimistic cooldown '
      'before the Future resolves',
      (tester) async {
        final completer = Completer<int?>();
        int callCount = 0;
        await tester.pumpWidget(
          _harness(
            onResend: () {
              callCount++;
              return completer.future;
            },
          ),
        );

        await tester.tap(find.byKey(_kResendKey));
        await tester.pump();

        expect(callCount, 1);
        // Optimistic cooldown started immediately — before the Future resolves.
        expect(
          find.text('Resend in ${kDefaultOtpResendCooldownSeconds}s'),
          findsOneWidget,
        );

        completer.complete(kDefaultOtpResendCooldownSeconds);
        await tester.pump();
      },
    );

    testWidgets(
      '4. onResend resolves with a DIFFERENT cooldown (throttle) → adopts '
      'the server value',
      (tester) async {
        final completer = Completer<int?>();
        await tester.pumpWidget(_harness(onResend: () => completer.future));

        await tester.tap(find.byKey(_kResendKey));
        await tester.pump();
        // Optimistic cooldown (30s) showing.
        expect(
          find.text('Resend in ${kDefaultOtpResendCooldownSeconds}s'),
          findsOneWidget,
        );

        completer.complete(90);
        await tester.pump(); // resume _handleTap past the await
        await tester.pump(); // rebuild with the new cooldown

        expect(find.text('Resend in 90s'), findsOneWidget);
      },
    );

    testWidgets(
      '5. onResend resolves with null (generic error) → cooldown cancelled '
      'immediately',
      (tester) async {
        final completer = Completer<int?>();
        await tester.pumpWidget(_harness(onResend: () => completer.future));

        await tester.tap(find.byKey(_kResendKey));
        await tester.pump();
        expect(
          find.text('Resend in ${kDefaultOtpResendCooldownSeconds}s'),
          findsOneWidget,
        );

        completer.complete(null);
        await tester.pump(); // resume _handleTap past the await
        await tester.pump(); // rebuild with the cancelled cooldown

        expect(find.text('Resend now'), findsOneWidget);
      },
    );

    testWidgets('6. resetCooldown() via GlobalKey zeroes the cooldown', (
      tester,
    ) async {
      final rowKey = GlobalKey<OtpResendRowState>();
      await tester.pumpWidget(
        _harness(rowKey: rowKey, onResend: () async => 30, initialCooldown: 20),
      );

      expect(find.text('Resend in 20s'), findsOneWidget);

      rowKey.currentState!.resetCooldown();
      await tester.pump();

      expect(find.text('Resend now'), findsOneWidget);
    });

    testWidgets('7. tapping while cooldown > 0 does not call onResend again', (
      tester,
    ) async {
      int callCount = 0;
      await tester.pumpWidget(
        _harness(
          onResend: () async {
            callCount++;
            return 30;
          },
          initialCooldown: 10,
        ),
      );

      await tester.tap(find.byKey(_kResendKey));
      await tester.pump();

      expect(callCount, 0);
      expect(find.text('Resend in 10s'), findsOneWidget);
    });

    // ── 8/9/10. The 10-minute UX ceiling (kMaxUxCooldownSeconds) ────────────
    //
    // Context: the password-reset journey's per-IP 429 carries
    // `Retry-After: 3600`. Rendered numerically that reads «Надіслати знову
    // (3600 с)» — not a human unit — and drove a 1 Hz `Timer.periodic` for a
    // full hour to rebuild a string that changes by one digit.
    //
    // The link must STAY DISABLED throughout; re-enabling it is the original
    // defect (it spends the user's next attempt against a bucket that is
    // still closed). Only the label and the tick change.
    //
    // `_pumpedTimerLabels` counts calls to `resendTimerLabel`, which is only
    // reachable from `build()`. Test 10 is the positive control that proves
    // the counter really does register ticks, so test 8's `0` is a finding
    // rather than a vacuous pass.

    testWidgets(
      '8. above the ceiling with the opt-in label: non-numeric label, link '
      'still disabled, and NO periodic timer runs',
      (tester) async {
        int timerLabelBuilds = 0;
        int resendCalls = 0;
        await tester.pumpWidget(
          _harness(
            onResend: () async {
              resendCalls++;
              return 3600;
            },
            initialCooldown: 3600,
            resendUnavailableLabel: 'Unavailable',
            onTimerLabelBuilt: () => timerLabelBuilds++,
          ),
        );

        expect(find.text('Unavailable'), findsOneWidget);
        expect(find.textContaining('Resend in'), findsNothing);
        expect(find.text('Resend now'), findsNothing);

        // THE proof that no PERIODIC timer is running, taken INSIDE the
        // window. A 1 Hz timer would have drained 3600 → 60 over 59 minutes,
        // and 60 is below the 600 s ceiling, so the row would have flipped to
        // the numeric countdown. Because no periodic timer was started,
        // `_cooldown` is still 3600 and the label is still non-numeric.
        //
        // (`pump(Duration)` advances flutter_test's FakeAsync clock, so any
        // pending `Timer.periodic` WOULD fire here — this is not a no-op.)
        // fixed-wait-ok: TTL crossing, and the assertion IS the clock
        // advance — 59 minutes is deliberately just inside the 3600 s window,
        // so the one-shot timer (test 11) has not fired yet while a periodic
        // one would already have crossed the ceiling. Pump-until-condition is
        // inapplicable: the expected outcome is that NOTHING changes.
        await tester.pump(const Duration(minutes: 59));

        expect(
          find.text('Unavailable'),
          findsOneWidget,
          reason:
              'a running 1 Hz timer would have drained 3600 → 60 within 59 '
              'minutes, dropping below the ceiling and rendering a number',
        );
        expect(find.text('Resend now'), findsNothing);
        expect(
          timerLabelBuilds,
          0,
          reason:
              'resendTimerLabel is reachable only from build(); zero calls '
              'means no tick ever rebuilt the row with a number (see test 10 '
              'for the positive control)',
        );

        // Still disabled — the behaviour the whole fix exists to preserve.
        await tester.tap(find.byKey(_kResendKey), warnIfMissed: false);
        await tester.pump();
        expect(resendCalls, 0);
      },
    );

    testWidgets(
      '9. above the ceiling WITHOUT the opt-in label: unchanged numeric '
      'countdown and timer (the change is additive)',
      (tester) async {
        int timerLabelBuilds = 0;
        await tester.pumpWidget(
          _harness(
            onResend: () async => 3600,
            initialCooldown: 3600,
            // resendUnavailableLabel deliberately omitted — this is exactly
            // what every pre-existing caller passes.
            onTimerLabelBuilt: () => timerLabelBuilds++,
          ),
        );

        expect(find.text('Resend in 3600s'), findsOneWidget);
        final int atMount = timerLabelBuilds;

        // fixed-wait-ok: TTL crossing — three 1 Hz ticks is the exact
        // quantity under test (3600 → 3597), not a guess at how long some
        // work takes.
        await tester.pump(const Duration(seconds: 3));

        expect(find.text('Resend in 3597s'), findsOneWidget);
        expect(
          timerLabelBuilds,
          greaterThan(atMount),
          reason:
              'an opted-out caller must keep the old ticking behaviour '
              'byte-for-byte',
        );
      },
    );

    testWidgets(
      '10. below the ceiling WITH the opt-in label: still counts down — the '
      'threshold decides, not the presence of the parameter',
      (tester) async {
        int timerLabelBuilds = 0;
        await tester.pumpWidget(
          _harness(
            onResend: () async => 600,
            // 600 is the ceiling itself; the branch is `> ceiling`, so this
            // value must stay numeric. Pinning the boundary, not a value
            // comfortably inside the range, is what catches a `>=` slip.
            initialCooldown: 600,
            resendUnavailableLabel: 'Unavailable',
            onTimerLabelBuilt: () => timerLabelBuilds++,
          ),
        );

        expect(find.text('Resend in 600s'), findsOneWidget);
        expect(find.text('Unavailable'), findsNothing);

        // fixed-wait-ok: TTL crossing — see test 9; three ticks, 600 → 597.
        await tester.pump(const Duration(seconds: 3));

        expect(find.text('Resend in 597s'), findsOneWidget);
        expect(
          timerLabelBuilds,
          greaterThan(0),
          reason:
              'positive control for test 8: this counter does register the '
              'per-second rebuilds when a timer IS running',
        );
      },
    );

    // ── 11. The unavailable window must ELAPSE ──────────────────────────────
    //
    // mobile-perf LOW (2026-09-16). The first cut of the ceiling fix started
    // NO timer at all, which froze `_cooldown` forever: nothing else on the
    // password-reset OTP screen clears it (`resetCooldown()`'s only call site
    // is verification_screen.dart), so a row left mounted past the window
    // showed a stale «Недоступно» until the user navigated away and back.
    //
    // 601 — one second above the ceiling — is the sharpest probe available,
    // and it is what makes "ONE tick, not `seconds` ticks" *observable* from
    // outside the widget:
    //
    //   * a `Timer.periodic` would decrement 601 → 600 after the FIRST
    //     second, and 600 is NOT `> kMaxUxCooldownSeconds`, so `_label()`
    //     would immediately fall through to the numeric branch and call
    //     `resendTimerLabel`. `timerLabelBuilds` therefore catches a
    //     per-second tick at t = 1 s, not only in aggregate.
    //   * the one-shot leaves `_cooldown` at 601 for the whole window and
    //     fires exactly once, at the end — so the counter stays at 0 from
    //     start to finish even though the row does eventually re-enable.
    //
    // (`pump(Duration)` collapses a whole elapse into a single frame, so a
    // build counter alone cannot separate 1 tick from 3600. Stepping to the
    // boundary second, where the two implementations diverge in the LABEL, is
    // what makes the distinction assertable.)
    //
    // KNOWN LIMIT, measured (mobile-qa mutation M3, 2026-09-16). What this
    // test pins is the USER-VISIBLE contract — non-numeric label held for the
    // whole window, zero numeric rebuilds, row re-enabled at the end and
    // genuinely tappable. It does NOT discriminate the one-shot from a
    // `Timer.periodic(Duration(seconds: seconds))`, which fires at 601 s,
    // zeroes, and merely repeats thereafter: that mutant passes this entire
    // file. Separating them needs a white-box build counter inside the widget
    // for a difference no frame and no user can observe, so it is deliberately
    // not pinned. The mutants that DO matter are covered next door — test 8's
    // 59-minute probe goes red both for a 1 Hz timer and for a one-shot whose
    // deadline is hardcoded to the ceiling instead of `seconds` (the
    // re-enables-an-hour-early defect).
    testWidgets(
      '11. the unavailable window elapses via ONE single-shot tick: frozen '
      'label during it, row re-enabled after it, zero per-second rebuilds',
      (tester) async {
        int timerLabelBuilds = 0;
        int resendCalls = 0;
        await tester.pumpWidget(
          _harness(
            onResend: () async {
              resendCalls++;
              return 601;
            },
            initialCooldown: 601,
            resendUnavailableLabel: 'Unavailable',
            onTimerLabelBuilt: () => timerLabelBuilds++,
          ),
        );

        expect(find.text('Unavailable'), findsOneWidget);

        // t = 1 s. A 1 Hz tick would put `_cooldown` at 600 — below the
        // ceiling — and render 'Resend in 600s'. This single second is the
        // whole tick-count discriminator.
        // fixed-wait-ok: TTL crossing — one second is the exact quantity
        // under test (the first periodic tick), not a guess at a duration.
        await tester.pump(const Duration(seconds: 1));

        expect(
          find.text('Unavailable'),
          findsOneWidget,
          reason:
              'one 1 Hz tick would have dropped 601 → 600, below the ceiling, '
              'and rendered a number — so the label proves no per-second '
              'timer is running',
        );
        expect(find.textContaining('Resend in'), findsNothing);
        expect(timerLabelBuilds, 0);

        // Still disabled mid-window.
        await tester.tap(find.byKey(_kResendKey), warnIfMissed: false);
        await tester.pump();
        expect(resendCalls, 0);

        // t = 602 s — one second past the window. The single-shot fires.
        // fixed-wait-ok: TTL crossing — 601 s is the declared window and the
        // assertion IS that crossing it re-enables the row. Pump-until-
        // condition cannot express "the timer's own deadline".
        await tester.pump(const Duration(seconds: 601));

        expect(
          find.text('Resend now'),
          findsOneWidget,
          reason:
              'the one-shot must actually elapse — a frozen cooldown leaves '
              'the row permanently unavailable with no way back',
        );
        expect(find.text('Unavailable'), findsNothing);
        expect(
          timerLabelBuilds,
          0,
          reason:
              'not one numeric rebuild between mount and re-enable — see the '
              'KNOWN LIMIT above for what this does and does not separate',
        );

        // Genuinely re-enabled, not merely relabelled.
        await tester.tap(find.byKey(_kResendKey));
        await tester.pump();
        expect(resendCalls, 1);
      },
    );
  });
}
