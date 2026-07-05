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
}) {
  return MaterialApp(
    home: Scaffold(
      body: OtpResendRow(
        key: rowKey,
        onResend: onResend,
        promptText: 'Prompt?',
        resendLabel: 'Resend now',
        resendTimerLabel: (seconds) => 'Resend in ${seconds}s',
        resendKey: _kResendKey,
        initialCooldown: initialCooldown,
        assumedCooldownSeconds: assumedCooldownSeconds,
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
  });
}
