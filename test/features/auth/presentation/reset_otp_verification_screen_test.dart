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
//   6b. Resend PasswordResetRateLimitedFailure (per-IP 429) shows the
//      try-later copy and KEEPS the resend link on cooldown.
//   6c. Resend ResendThrottledFailure with a NULL retryAfterSeconds (the
//      change-password per-IP 3600 s filter shape) also KEEPS the link on
//      cooldown rather than clearing it.
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

    // ── 6b. Resend hits the SAME per-IP bucket as the original request ──────
    //
    // The resend and the forgot-password submit that got the user here share
    // one 3-requests/hour per-IP bucket (`AuthRateLimitFilter`). Before the
    // fix a 429 landed in the generic catch arm, which returns `null` — and
    // `OtpResendRow` reads `null` as "generic error, let them retry now",
    // cancelling the cooldown and re-enabling the link. The next tap would
    // then burn one of the three attempts the user has left, against a bucket
    // that is still closed.
    //
    // Two things are asserted, because either alone would pass while the bug
    // remained: the inline copy must be the rate-limit copy (NOT the generic
    // «Щось пішло не так»), and the link must still be counting down rather
    // than tappable.
    testWidgets(
      '6b. resend PasswordResetRateLimitedFailure shows the try-later copy '
      'AND keeps the resend link on cooldown (does not re-enable it)',
      (tester) async {
        int resendCalls = 0;
        await _pump(
          tester,
          onRequestOtp: () async {
            resendCalls++;
            throw const PasswordResetRateLimitedFailure();
          },
          onVerify: (code) async => 'ticket',
        );

        // fixed-wait-ok: TTL crossing — see the identical drain above.
        await tester.pump(const Duration(seconds: 31));
        await tester.tap(
          find.byKey(const ValueKey<String>('reset_otp_resend')),
        );
        await tester.pump();
        await tester.pump();
        // fixed-wait-ok: real-async integration step — lets the throttled
        // onRequestOtp resolve.
        await tester.pump(const Duration(milliseconds: 50));

        final l10n = AppLocalizations.of(
          tester.element(
            find.byKey(const ValueKey<String>('reset_otp_submit')),
          ),
        );
        expect(find.text(l10n.authResetErrRateLimited), findsOneWidget);
        expect(find.text(l10n.errUnknown), findsNothing);

        // The link is still showing the countdown label, not the tappable
        // resend label — proving the handler returned a cooldown instead of
        // the generic arm's null.
        expect(find.text(l10n.resetOtpResendBtn), findsNothing);
        expect(resendCalls, 1);

        // And a further tap cannot spend another attempt while it counts down.
        await tester.tap(
          find.byKey(const ValueKey<String>('reset_otp_resend')),
          warnIfMissed: false,
        );
        await tester.pump();
        expect(resendCalls, 1);
      },
    );

    // ── 6c. The SIBLING arm of the same defect ──────────────────────────────
    //
    // mobile-security MEDIUM (2026-09-16). Test 6 above drives
    // ResendThrottledFailure with a NUMERIC retryAfterSeconds, which is only
    // the per-ACCOUNT producer (`ResendThrottledException`, small
    // `data.retryAfterSeconds`). The change-password entry point
    // (app_router.dart's second registration, `fromChangePassword: true`)
    // resends against `/users/me/change-password/request-otp`, which ALSO
    // sits behind the per-IP `changePasswordOtpBuckets` filter — 3/hour,
    // `Retry-After: 3600`. That 3600 is above the interceptor's 600 s UX
    // ceiling, so `_extractRetryAfterSecondsNullable` clamps it to `null` and
    // the SAME ResendThrottledFailure arrives carrying NO seconds.
    //
    // A null returned to OtpResendRow means "generic error, retry now": it
    // cancels the cooldown and re-enables the link, against a bucket that is
    // still closed. That is verbatim the defect test 6b guards on the other
    // arm, and it survived here because no test drove the null shape.
    //
    // Both halves are asserted, because either alone passes with the bug
    // present: the banner must carry the null-seconds copy (cooldownTryLater,
    // NOT the numeric throttle string), and the link must stay disabled.
    testWidgets(
      '6c. resend ResendThrottledFailure with NULL retryAfterSeconds (the '
      'per-IP 3600 s filter shape) keeps the resend link on cooldown',
      (tester) async {
        int resendCalls = 0;
        await _pump(
          tester,
          fromChangePassword: true,
          onRequestOtp: () async {
            resendCalls++;
            throw const ResendThrottledFailure(retryAfterSeconds: null);
          },
          onVerify: (code) async => 'ticket',
        );

        // fixed-wait-ok: TTL crossing — drains the screen's 30 s mount
        // cooldown so the resend link is tappable, same as tests 6 / 6b.
        await tester.pump(const Duration(seconds: 31));
        await tester.tap(
          find.byKey(const ValueKey<String>('reset_otp_resend')),
        );
        await tester.pump();
        await tester.pump();
        // fixed-wait-ok: real-async integration step — lets the throttled
        // onRequestOtp resolve.
        await tester.pump(const Duration(milliseconds: 50));

        final l10n = AppLocalizations.of(
          tester.element(
            find.byKey(const ValueKey<String>('reset_otp_submit')),
          ),
        );
        expect(find.text(l10n.cooldownTryLater), findsOneWidget);
        expect(find.text(l10n.errUnknown), findsNothing);

        // THE assertion. With the null passed straight through, the row would
        // read it as "no cooldown", cancel the countdown and show the
        // tappable resend label again.
        expect(
          find.text(l10n.resetOtpResendBtn),
          findsNothing,
          reason:
              'a null-seconds throttle must be floored to the bucket window, '
              'not forwarded as null — null re-enables the link',
        );
        expect(resendCalls, 1);

        // And a further tap cannot spend another of the three hourly attempts.
        await tester.tap(
          find.byKey(const ValueKey<String>('reset_otp_resend')),
          warnIfMissed: false,
        );
        await tester.pump();
        expect(resendCalls, 1);
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
