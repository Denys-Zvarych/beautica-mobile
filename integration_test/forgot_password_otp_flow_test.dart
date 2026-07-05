// Beautica OTP task (Phase B6) — E2E: Forgot-Password OTP Flow.
//
// Journey: cold-start (unauthenticated, /login) → tap "Forgot password?" →
// /forgot-password → submit email → /reset-password/otp (OTP screen) →
// submit 6-digit code → /reset-password (set new password) → submit →
// success state → tap "Увійти" → /login.
//
// This is the FULL replacement for the old emailed reset-link flow: every
// step now happens in-app against the fake `/auth/forgot-password`,
// `/auth/verify-password-reset-otp`, and `/auth/reset-password` endpoints —
// no deep link is involved anywhere in this journey.
//
// All taps are key-based — no raw Ukrainian find.text() tap drivers. See
// integration_test/support/app_harness.dart for the policy rationale.

import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

const _kEmail = 'recover-me@beautica.ua';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  void expectLocation(GoRouter router, String expected) {
    final String current = router.routerDelegate.currentConfiguration.uri
        .toString();
    expect(
      current,
      startsWith(expected),
      reason: 'Expected router location to start with $expected, got $current',
    );
  }

  testWidgets(
    'full forgot-password journey: email → OTP → new password → login',
    (tester) async {
      final fb = FakeBackend();
      final GoRouter router = await AppHarness.boot(tester, fb);

      // ── Step 0 — cold start lands on /login ──────────────────────────────
      expect(
        find.byKey(const ValueKey<String>('login_email')),
        findsOneWidget,
        reason: 'Login form must be visible on cold start',
      );

      // ── Step 1 — tap "Forgot password?" → /forgot-password ───────────────
      await tester.tap(find.byKey(const ValueKey<String>('login_forgot')));
      await tester.pumpAndSettle();
      expectLocation(router, RouteNames.forgotPassword);

      // ── Step 2 — submit email → POST /auth/forgot-password ───────────────
      await tester.enterText(
        find.byKey(const ValueKey<String>('forgot_email')),
        _kEmail,
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('forgot_submit')));
      await tester.pumpAndSettle();

      expect(fb.forgotPasswordCalls, equals(1));
      expect(fb.lastForgotPasswordEmail, equals(_kEmail));

      // ── Step 3 — navigated to the OTP screen ─────────────────────────────
      expectLocation(router, RouteNames.resetOtpVerification);
      expect(
        find.byKey(const ValueKey<String>('reset_otp_code_input')),
        findsOneWidget,
      );

      // ── Step 4 — submit the 6-digit code → POST /auth/verify-password-reset-otp
      await tester.enterText(
        find.byKey(const ValueKey<String>('reset_otp_code_input')),
        '123456',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('reset_otp_submit')));
      await tester.pumpAndSettle();

      expect(fb.verifyPasswordResetOtpCalls, equals(1));
      expect(fb.lastVerifyPasswordResetOtpEmail, equals(_kEmail));
      expect(fb.lastVerifyPasswordResetOtpCode, equals('123456'));

      // ── Step 5 — navigated to the set-new-password screen ────────────────
      expectLocation(router, RouteNames.resetPassword);
      expect(
        find.byKey(const ValueKey<String>('reset_password')),
        findsOneWidget,
      );

      // ── Step 6 — submit the new password → POST /auth/reset-password ────
      await tester.enterText(
        find.byKey(const ValueKey<String>('reset_password')),
        'N3wP@ssw0rd!',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('reset_confirm')),
        'N3wP@ssw0rd!',
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('reset_submit')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('reset_submit')));
      await tester.pumpAndSettle();

      expect(fb.resetPasswordCalls, equals(1));
      expect(fb.lastResetPasswordTicket, equals(fb.resetTicketToIssue));
      expect(fb.lastResetPasswordNewPassword, equals('N3wP@ssw0rd!'));

      // ── Step 7 — the forgot-password flow shows its own success state,
      // NOT the forced-logout flow (there is no session to log out of).
      expect(
        find.byKey(const ValueKey<String>('reset_back_login')),
        findsOneWidget,
      );
      expect(fb.logoutCalls, equals(0));

      // ── Step 8 — tap "Увійти" → /login ────────────────────────────────
      await tester.tap(find.byKey(const ValueKey<String>('reset_back_login')));
      await tester.pumpAndSettle();

      expectLocation(router, RouteNames.login);
    },
  );
}
