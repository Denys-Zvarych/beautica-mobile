// Phone-first hardening — E2E: forgot password BY PHONE, completed past the
// code step (AUTH-12, AUTH-D18, AUTH-D26 b, AUTH-D27 c/d, AUTH-54).
//
// Journeys (real app, FakeBackend, production ErrorMapperInterceptor):
//   1. /login → «Забули пароль?» → a UA mobile number → the normalised phone
//      reaches `/auth/forgot-password` and `/auth/verify-password-reset-otp`
//      → the neutral code screen (no channel named) → code → new password →
//      success → «Увійти» → /login → sign in with the phone and the NEW
//      password → master home.
//   2. App Check 403 APP_CHECK_FAILED on the send → its own copy inline, the
//      form stays, no code screen.
//   3. App Check 503 APP_CHECK_UNAVAILABLE on the send → its own copy inline.
//
// The App Check answers are injected as the server's real
// `{success:false, data:{code}}` envelope in front of the fake route, so the
// production mapper turns them into `PhoneIdentityFailure` (as on device).
// All taps are key-based (see integration_test/support/app_harness.dart).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

AppLocalizations get _l10n => lookupAppLocalizations(const Locale('uk'));

Finder _key(String k) => find.byKey(ValueKey<String>(k));

const String _kTyped = '067 123 45 67';
const String _kNormalised = '+380671234567';
const String _kNewPassword = 'N3wP@ssw0rd!';

Future<void> _enter(WidgetTester tester, Finder f, String text) async {
  await AppHarness.pumpUntilFound(tester, f);
  await tester.ensureVisible(f);
  await tester.enterText(f, text);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await AppHarness.tapVisible(tester, f);
  await AppHarness.settle(tester);
}

/// The App Check guard in front of `/auth/forgot-password`: answers
/// [status] with `data.code` [code], the envelope the backend sends.
void _rejectForgotPassword(FakeBackend fb, int status, String code) {
  fb.dio.interceptors.insert(
    0,
    InterceptorsWrapper(
      onRequest: (RequestOptions o, RequestInterceptorHandler h) {
        if (!o.path.endsWith('/auth/forgot-password')) return h.next(o);
        h.reject(
          DioException(
            requestOptions: o,
            type: DioExceptionType.badResponse,
            response: Response<Map<String, dynamic>>(
              requestOptions: o,
              statusCode: status,
              data: <String, dynamic>{
                'success': false,
                'message': 'FAKE-$status',
                'data': <String, dynamic>{'code': code},
              },
            ),
          ),
          true,
        );
      },
    ),
  );
}

Future<void> _submitPhone(WidgetTester tester, GoRouter router) async {
  await _tap(tester, _key('login_forgot'));
  AppHarness.expectLocation(router, RouteNames.forgotPassword);
  await _enter(tester, _key('forgot_identifier'), _kTyped);
  await _tap(tester, _key('forgot_submit'));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('forgot password by phone: code → new password → sign in by '
      'phone with the new password', (tester) async {
    final FakeBackend fb = FakeBackend();
    final GoRouter router = await AppHarness.boot(tester, fb);

    await _submitPhone(tester, router);
    expect(fb.forgotPasswordCalls, 1);
    expect(fb.lastForgotPasswordEmail, _kNormalised);

    AppHarness.expectLocation(router, RouteNames.resetOtpVerification);
    expect(find.textContaining(_l10n.resetCodeSentNeutral), findsOneWidget);
    expect(find.textContaining('380'), findsNothing, reason: 'no channel');

    await _enter(tester, _key('reset_otp_code_input'), '123456');
    await _tap(tester, _key('reset_otp_submit'));
    expect(fb.verifyPasswordResetOtpCalls, 1);
    expect(fb.lastVerifyPasswordResetOtpEmail, _kNormalised);
    expect(fb.lastVerifyPasswordResetOtpCode, '123456');

    AppHarness.expectLocation(router, RouteNames.resetPassword);
    await _enter(tester, _key('reset_password'), _kNewPassword);
    await _enter(tester, _key('reset_confirm'), _kNewPassword);
    await _tap(tester, _key('reset_submit'));
    expect(fb.resetPasswordCalls, 1);
    expect(fb.lastResetPasswordTicket, fb.resetTicketToIssue);
    expect(fb.lastResetPasswordNewPassword, _kNewPassword);
    expect(fb.logoutCalls, 0, reason: 'no session to log out of');

    await _tap(tester, _key('reset_back_login'));
    AppHarness.expectLocation(router, RouteNames.login);

    // Sign in by phone with the new password (AUTH-46).
    fb.currentRole = UserRole.independentMaster;
    await _enter(tester, _key('login_email'), _kTyped);
    await _enter(tester, _key('login_password'), _kNewPassword);
    await _tap(tester, _key('login_submit'));
    await AppHarness.settle(tester);

    expect(fb.loginCalls, 1);
    expect(fb.lastLoginBody?['password'], _kNewPassword);
    AppHarness.expectLocation(router, RouteNames.masterProfile);
  });

  for (final (int status, String code, String Function() copy)
      in <(int, String, String Function())>[
        (403, 'APP_CHECK_FAILED', () => _l10n.errAppCheckFailed),
        (503, 'APP_CHECK_UNAVAILABLE', () => _l10n.errAppCheckUnavailable),
      ]) {
    testWidgets('forgot password by phone: App Check $status $code → inline '
        'copy, no code screen', (tester) async {
      final FakeBackend fb = FakeBackend();
      final GoRouter router = await AppHarness.boot(tester, fb);
      _rejectForgotPassword(fb, status, code);

      await _submitPhone(tester, router);

      expect(find.text(copy()), findsOneWidget);
      AppHarness.expectLocation(router, RouteNames.forgotPassword);
      expect(fb.forgotPasswordCalls, 0, reason: 'rejected before the route');
      expect(_key('reset_otp_code_input'), findsNothing);
    });
  }
}
