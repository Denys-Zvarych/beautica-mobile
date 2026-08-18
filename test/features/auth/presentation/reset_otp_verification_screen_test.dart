// Beautica OTP task (Phase B3/B6) — widget tests for the generalized
// [ResetOtpVerificationScreen], reused by BOTH the forgot-password
// (unauthenticated) and settings change-password (authenticated) flows via
// constructor closures.
//
// Covered scenarios:
//   1. Fewer than 6 digits keeps the submit button disabled.
//   2. 6 digits enables the submit button; a successful onVerify navigates to
//      /reset-password with a ResetPasswordArgs carrying the returned ticket.
//   3. fromChangePassword: true is forwarded into ResetPasswordArgs.
//   4. onVerify throwing PasswordResetOtpFailure shows the mapped inline copy.
//   5. Resend calls onRequestOtp(); success clears the OTP input.
//   6. Resend ResendThrottledFailure adopts the server retryAfterSeconds.
//   7. The masked displayEmail is rendered.
//   8. Top-left back button navigates back (pop).

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/reset_password_args.dart';
import 'package:beautica_mobile/features/auth/presentation/reset_otp_verification_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

const _kEmail = 'anya@example.com';

/// Captures the extra carried into RouteNames.resetPassword by the screen.
ResetPasswordArgs? capturedArgs;

GoRouter _makeRouter({
  required Future<void> Function() onRequestOtp,
  required Future<String> Function(String code) onVerify,
  String displayEmail = _kEmail,
  bool fromChangePassword = false,
}) {
  capturedArgs = null;
  return GoRouter(
    initialLocation: RouteNames.resetOtpVerification,
    redirect: (context, state) => null,
    routes: <RouteBase>[
      GoRoute(
        path: RouteNames.resetOtpVerification,
        builder: (context, state) => ResetOtpVerificationScreen(
          onRequestOtp: onRequestOtp,
          onVerify: onVerify,
          displayEmail: displayEmail,
          fromChangePassword: fromChangePassword,
        ),
      ),
      GoRoute(
        path: RouteNames.resetPassword,
        builder: (context, state) {
          capturedArgs = state.extra as ResetPasswordArgs?;
          return const Scaffold(body: Center(child: Text('reset-password')));
        },
      ),
    ],
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required Future<void> Function() onRequestOtp,
  required Future<String> Function(String code) onVerify,
  String displayEmail = _kEmail,
  bool fromChangePassword = false,
}) async {
  final router = _makeRouter(
    onRequestOtp: onRequestOtp,
    onVerify: onVerify,
    displayEmail: displayEmail,
    fromChangePassword: fromChangePassword,
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: beauticaProviderRetry,
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _fillOtp(WidgetTester tester, String digits) async {
  await tester.enterText(
    find.byKey(const ValueKey<String>('reset_otp_code_input')),
    digits,
  );
  await tester.pump();
}

void main() {
  group('ResetOtpVerificationScreen', () {
    testWidgets('1. fewer than 6 digits keeps submit disabled', (tester) async {
      await _pump(
        tester,
        onRequestOtp: () async {},
        onVerify: (code) async => 'ticket',
      );

      await _fillOtp(tester, '12345');
      await tester.pump();

      final btn = tester.widget<NeumorphicButton>(
        find.byKey(const ValueKey<String>('reset_otp_submit')),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets(
      '2. 6 digits enables submit; success navigates to /reset-password '
      'with the returned ticket',
      (tester) async {
        String? capturedCode;
        await _pump(
          tester,
          onRequestOtp: () async {},
          onVerify: (code) async {
            capturedCode = code;
            return 'ticket-abc-123';
          },
        );

        await _fillOtp(tester, '123456');
        await tester.pumpAndSettle();

        final btn = tester.widget<NeumorphicButton>(
          find.byKey(const ValueKey<String>('reset_otp_submit')),
        );
        expect(btn.onPressed, isNotNull);

        await tester.tap(
          find.byKey(const ValueKey<String>('reset_otp_submit')),
        );
        await tester.pumpAndSettle();

        expect(capturedCode, '123456');
        expect(find.text('reset-password'), findsOneWidget);
        expect(capturedArgs?.resetTicket, 'ticket-abc-123');
        expect(capturedArgs?.fromChangePassword, isFalse);
      },
    );

    testWidgets(
      '3. fromChangePassword: true is forwarded into ResetPasswordArgs',
      (tester) async {
        await _pump(
          tester,
          onRequestOtp: () async {},
          onVerify: (code) async => 'ticket-xyz',
          fromChangePassword: true,
        );

        await _fillOtp(tester, '123456');
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('reset_otp_submit')),
        );
        await tester.pumpAndSettle();

        expect(capturedArgs?.resetTicket, 'ticket-xyz');
        expect(capturedArgs?.fromChangePassword, isTrue);
      },
    );

    testWidgets(
      '4. onVerify throwing PasswordResetOtpFailure shows the mapped inline '
      'copy',
      (tester) async {
        await _pump(
          tester,
          onRequestOtp: () async {},
          onVerify: (code) async => throw const PasswordResetOtpFailure(
            code: PasswordResetOtpErrorCode.invalidCode,
          ),
        );

        await _fillOtp(tester, '123456');
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(
            find.byKey(const ValueKey<String>('reset_otp_submit')),
          ),
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('reset_otp_submit')),
        );
        await tester.pumpAndSettle();

        expect(find.text(l10n.resetOtpErrInvalidCode), findsOneWidget);
        // Stays on the OTP screen (no navigation to /reset-password).
        expect(find.text('reset-password'), findsNothing);
      },
    );

    testWidgets('5. resend calls onRequestOtp(); success clears the OTP input', (
      tester,
    ) async {
      int resendCalls = 0;
      await _pump(
        tester,
        onRequestOtp: () async {
          resendCalls++;
        },
        onVerify: (code) async => 'ticket',
      );

      await _fillOtp(tester, '654321');
      // Drain the mount cooldown (OtpResendRow starts a REAL 30s Timer.periodic).
      // fixed-wait-ok: TTL crossing — must advance past exactly that window.
      await tester.pump(const Duration(seconds: 31));
      await tester.tap(find.byKey(const ValueKey<String>('reset_otp_resend')));
      await tester.pump();
      await tester.pump();
      // fixed-wait-ok: real-async integration step — lets onRequestOtp resolve.
      await tester.pump(const Duration(milliseconds: 50));

      expect(resendCalls, 1);
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('reset_otp_code_input')),
      );
      expect(field.controller?.text, isEmpty);
    });

    testWidgets(
      '6. resend ResendThrottledFailure adopts the server retryAfterSeconds',
      (tester) async {
        await _pump(
          tester,
          onRequestOtp: () async =>
              throw const ResendThrottledFailure(retryAfterSeconds: 42),
          onVerify: (code) async => 'ticket',
        );

        // fixed-wait-ok: TTL crossing — see the identical drain above.
        await tester.pump(const Duration(seconds: 31));
        await tester.tap(
          find.byKey(const ValueKey<String>('reset_otp_resend')),
        );
        await tester.pump();
        await tester.pump();
        // fixed-wait-ok: real-async integration step — lets throttled onRequestOtp resolve.
        await tester.pump(const Duration(milliseconds: 50));

        final l10n = AppLocalizations.of(
          tester.element(
            find.byKey(const ValueKey<String>('reset_otp_submit')),
          ),
        );
        expect(
          find.text(l10n.verificationErrResendThrottled(42)),
          findsOneWidget,
        );
      },
    );

    testWidgets('7. the masked displayEmail is rendered', (tester) async {
      await _pump(
        tester,
        onRequestOtp: () async {},
        onVerify: (code) async => 'ticket',
        displayEmail: 'someone@example.com',
      );

      expect(find.textContaining('@example.com'), findsWidgets);
    });

    testWidgets('8. top-left back button pops the route', (tester) async {
      final router = _makeRouter(
        onRequestOtp: () async {},
        onVerify: (code) async => 'ticket',
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          retry: beauticaProviderRetry,
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();
      router.go(RouteNames.resetPassword);
      await tester.pumpAndSettle();
      unawaited(router.push(RouteNames.resetOtpVerification));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('auth_scaffold_back')),
      );
      await tester.pumpAndSettle();

      expect(find.text('reset-password'), findsOneWidget);
    });

    // mobile-qa LOW — no existing test asserted the NeumorphicButton's
    // loading:true visual state DURING an in-flight submit (the closures
    // above all resolve immediately). Uses a Completer-backed onVerify so the
    // Future stays pending until explicitly completed, letting us pump once
    // and observe the intermediate loading state before resolving it.
    testWidgets(
      '9. NeumorphicButton(loading: _submitting) shows the spinner mid-submit '
      'and clears once onVerify resolves',
      (tester) async {
        final Completer<String> completer = Completer<String>();
        await _pump(
          tester,
          onRequestOtp: () async {},
          onVerify: (code) => completer.future,
        );

        await _fillOtp(tester, '123456');
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey<String>('reset_otp_submit')),
        );
        // One pump: onVerify has started but the completer has not resolved
        // yet, so the screen must stay in its loading state.
        await tester.pump();

        expect(
          find.byType(CircularProgressIndicator),
          findsOneWidget,
          reason:
              'Mid-submit: NeumorphicButton(loading: _submitting) must show '
              'a CircularProgressIndicator while onVerify is in flight.',
        );
        final NeumorphicButton btn = tester.widget<NeumorphicButton>(
          find.byKey(const ValueKey<String>('reset_otp_submit')),
        );
        expect(btn.loading, isTrue);
        expect(
          btn.onPressed,
          isNull,
          reason: 'the CTA must be disabled while submitting',
        );

        completer.complete('ticket-loading-test');
        await tester.pumpAndSettle();

        // Resolved: spinner gone, navigation to /reset-password completed.
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('reset-password'), findsOneWidget);
      },
    );
  });
}
