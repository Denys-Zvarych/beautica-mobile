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
// Second test: the Account page «Сповіщення» switch round trip through the
// REAL router + lifecycle — OFF while the (faked) OS permission is denied, a
// tap opens Android settings without flipping, the user grants there and the
// app resume turns it ON; a resume while «Змінити пароль» covers Account is
// replayed on pop; a revisit re-reads the permission.
//
// All taps are key-based — no raw Ukrainian find.text() tap drivers. See
// integration_test/support/app_harness.dart for the policy rationale.

import 'package:beautica_mobile/core/push/notification_permission_provider.dart';
import 'package:beautica_mobile/core/push/notification_tray_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/l10n/app_localizations_uk.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// The faked OS side of the «Сповіщення» switch: what Android currently
/// allows, how often the app read it, how often it opened Android settings.
class _Os {
  NotificationPermissionStatus status = NotificationPermissionStatus.denied;
  int reads = 0;
  int opens = 0;
}

/// Leaves the app (e.g. into Android settings) and comes back — the only legal
/// lifecycle order (`AppLifecycleListener` asserts on a direct jump).
Future<void> _leaveAndReturn(WidgetTester tester) async {
  for (final AppLifecycleState s in <AppLifecycleState>[
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
  await tester.pumpAndSettle();
}

final AppLocalizationsUk _l10n = AppLocalizationsUk();
const Key _row = Key('row-notifications');

void _expectSwitch(WidgetTester tester, {required bool on}) {
  expect(tester.getSemantics(find.byKey(_row)), isSemantics(isToggled: on));
  expect(
    find.descendant(
      of: find.byKey(_row),
      matching: find.text(
        on
            ? _l10n.accountNotificationsSubtitle
            : _l10n.accountNotificationsOffSubtitle,
      ),
    ),
    findsOneWidget,
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'settings change-password journey: logged in → change password → OTP → '
    'new password → forced logout → lands on login',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      AppHarness.expectLocation(router, RouteNames.masterProfile);

      // ── Step 1 — open the master settings hub ────────────────────────────
      await tester.tap(find.byKey(const Key('btn-menu-master')));
      await tester.pumpAndSettle();
      AppHarness.expectLocation(router, RouteNames.masterMenu);

      // ── Step 2 — Account row → /settings ──────────────────────────────────
      await tester.tap(find.byKey(const Key('row-account')));
      await tester.pumpAndSettle();
      AppHarness.expectLocation(router, RouteNames.settings);

      // ── Step 3 — "Змінити пароль" row: sends the first OTP, then navigates
      await tester.ensureVisible(find.byKey(const Key('row-change-password')));
      await tester.tap(find.byKey(const Key('row-change-password')));
      await tester.pumpAndSettle();

      expect(fb.requestChangePasswordOtpCalls, equals(1));
      AppHarness.expectLocation(router, RouteNames.changePassword);
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
      AppHarness.expectLocation(router, RouteNames.resetPassword);
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
      // Deliberately NOT pumpAndSettle() first — the forced-logout VelvetSnack
      // has its own timer and pumpAndSettle() would pump straight past it,
      // leaving nothing to assert. Bounded pumps let the async
      // confirmPasswordReset → logout → snackbar → context.go chain settle
      // while the VelvetSnack is still visible.
      await tester.pump();
      await tester.pump();
      // fixed-wait-ok: real-async step — the forced-logout VelvetSnack must still be visible below.
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
      AppHarness.expectLocation(router, RouteNames.login);
    },
  );

  testWidgets(
    'settings notifications switch: master menu → Account → «Сповіщення» OFF '
    '(denied) → tap opens Android settings, no flip → user grants → resume → '
    'ON; resume while covered replays on pop; revisit re-reads',
    (tester) async {
      final _Os os = _Os();
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        extraOverrides: <Object>[
          notificationPermissionReaderProvider.overrideWithValue(() async {
            os.reads++;
            return os.status;
          }),
          notificationSettingsOpenerProvider.overrideWithValue(() async {
            os.opens++;
          }),
        ],
      );
      final SemanticsHandle handle = tester.ensureSemantics();

      // ── Step 1 — reach Account; the switch mirrors «denied» ──────────────
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await tester.tap(find.byKey(const Key('btn-menu-master')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('row-account')));
      await tester.pumpAndSettle();
      AppHarness.expectLocation(router, RouteNames.settings);
      _expectSwitch(tester, on: false);

      // ── Step 2 — tap opens Android settings; never flips optimistically ─
      await tester.tap(find.byKey(const Key('switch-notifications')));
      await tester.pumpAndSettle();
      expect(os.opens, equals(1));
      _expectSwitch(tester, on: false);
      AppHarness.expectLocation(router, RouteNames.settings);

      // ── Step 3 — the user enables notifications there and comes back ────
      os.status = NotificationPermissionStatus.granted;
      await _leaveAndReturn(tester);
      _expectSwitch(tester, on: true);
      expect(os.opens, equals(1), reason: 'a resume never re-opens settings');

      // ── Step 4 — a resume while «Змінити пароль» covers Account is not
      // read then, but replayed once Account is on top again.
      await tester.ensureVisible(find.byKey(const Key('row-change-password')));
      await tester.tap(find.byKey(const Key('row-change-password')));
      await tester.pumpAndSettle();
      AppHarness.expectLocation(router, RouteNames.changePassword);
      final int readsWhileCovered = os.reads;
      os.status = NotificationPermissionStatus.denied;
      await _leaveAndReturn(tester);
      expect(os.reads, equals(readsWhileCovered), reason: 'covered → no read');
      router.pop();
      await tester.pumpAndSettle();
      AppHarness.expectLocation(router, RouteNames.settings);
      expect(os.reads, equals(readsWhileCovered + 1));
      _expectSwitch(tester, on: false);

      // ── Step 5 — leave Account and revisit: the visit re-reads ──────────
      router.pop();
      await tester.pumpAndSettle();
      AppHarness.expectLocation(router, RouteNames.masterMenu);
      os.status = NotificationPermissionStatus.granted;
      await tester.tap(find.byKey(const Key('row-account')));
      await tester.pumpAndSettle();
      AppHarness.expectLocation(router, RouteNames.settings);
      _expectSwitch(tester, on: true);
      expect(os.opens, equals(1));
      handle.dispose();
    },
  );
}
