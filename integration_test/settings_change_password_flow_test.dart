// Beautica OTP task (Phase B6) — E2E: Settings Change-Password Flow.
//
// Journey: already logged in (INDEPENDENT_MASTER) → open the master menu →
// Account → "Змінити пароль" row (sends the first OTP) → OTP entry screen →
// submit 6-digit code → set-new-password screen → submit → the app
// proactively logs the user out (the backend revokes the caller's own
// refresh token on any password reset) and lands on /login with the
// forced-logout message.
//
// This is the SAME generalized ResetOtpVerificationScreen + ResetPasswordScreen
// the forgot-password journey uses (see forgot_password_otp_flow_test.dart),
// exercised through its authenticated entry point instead.
//
// All taps are key-based — no raw Ukrainian find.text() tap drivers. See
// integration_test/support/app_harness.dart for the policy rationale.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

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
    'settings change-password journey: logged in → change password → OTP → '
    'new password → forced logout → lands on login',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      expectLocation(router, RouteNames.masterProfile);

      // ── Step 1 — open the master settings hub ────────────────────────────
      await tester.tap(find.byKey(const Key('btn-menu-master')));
      await tester.pumpAndSettle();
      expectLocation(router, RouteNames.masterMenu);

      // ── Step 2 — Account row → /settings ──────────────────────────────────
      await tester.tap(find.byKey(const Key('row-account')));
      await tester.pumpAndSettle();
      expectLocation(router, RouteNames.settings);

      // ── Step 3 — "Змінити пароль" row: sends the first OTP, then navigates
      await tester.ensureVisible(find.byKey(const Key('row-change-password')));
      await tester.tap(find.byKey(const Key('row-change-password')));
      await tester.pumpAndSettle();

      expect(fb.requestChangePasswordOtpCalls, equals(1));
      expectLocation(router, RouteNames.changePassword);
      expect(
        find.byKey(const ValueKey<String>('reset_otp_code_input')),
        findsOneWidget,
      );

      // ── Step 4 — submit the 6-digit code → verifies against the CALLER's
      // own email (never a client-supplied one — the settings row never
      // carries an email extra).
      await tester.enterText(
        find.byKey(const ValueKey<String>('reset_otp_code_input')),
        '654321',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('reset_otp_submit')));
      await tester.pumpAndSettle();

      expect(fb.verifyPasswordResetOtpCalls, equals(1));
      expect(fb.lastVerifyPasswordResetOtpEmail, equals('master@beautica.ua'));
      expect(fb.lastVerifyPasswordResetOtpCode, equals('654321'));

      // ── Step 5 — set-new-password screen ──────────────────────────────────
      expectLocation(router, RouteNames.resetPassword);
      expect(
        find.byKey(const ValueKey<String>('reset_password')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('reset_password')),
        'Br@ndNewPass1',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('reset_confirm')),
        'Br@ndNewPass1',
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('reset_submit')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('reset_submit')));
      // Deliberately NOT pumpAndSettle() first — the forced-logout SnackBar
      // has its own timer and pumpAndSettle() would pump straight past it,
      // leaving nothing to assert. Bounded pumps let the async
      // confirmPasswordReset → logout → snackbar → context.go chain settle
      // while the SnackBar is still visible.
      await tester.pump();
      await tester.pump();
      // fixed-wait-ok: real-async step — the forced-logout SnackBar must still be visible below.
      await tester.pump(const Duration(milliseconds: 100));

      expect(fb.resetPasswordCalls, equals(1));
      expect(fb.lastResetPasswordTicket, equals(fb.resetTicketToIssue));
      expect(fb.lastResetPasswordNewPassword, equals('Br@ndNewPass1'));

      // ── Step 6 — forced logout: the backend session was revoked, so the
      // app proactively logs out and lands on /login (NOT the normal
      // in-screen success state — the settings flow skips it entirely).
      expect(fb.logoutCalls, equals(1));
      expect(
        find.byKey(const ValueKey<String>('reset_back_login')),
        findsNothing,
      );

      await tester.pumpAndSettle();
      expectLocation(router, RouteNames.login);
    },
  );
}
