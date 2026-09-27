// E2E — the password-reset journey's per-IP 429, end to end.
//
// Guards the WIRE, which is the one thing the widget and unit tests cannot:
// `ErrorMapperInterceptor` (a real one, installed by FakeBackend exactly as
// `dioProvider` installs it in production) → AuthRepository → the screen's
// inline banner. The widget test for this branch injects
// `PasswordResetRateLimitedFailure` straight into a fake repository, so it
// would keep passing with the interceptor branch deleted; the interceptor
// test never renders anything. Only this file drives a real 429 response
// through both.
//
// The reported bug (2026-09-15): `POST /auth/forgot-password` is capped per
// IP by a servlet FILTER in front of the controller, so forgot-password's
// anti-enumeration generic-200 contract does not apply — the filter answers
// 429 with a bare `{"error":"Too many requests"}`. With no mapper branch it
// fell to UnknownFailure and a real, verified user was told «Щось пішло не
// так. Спробуйте ще раз.» — at three requests an hour, the one action that
// cannot work.
//
// All taps are key-based — no raw Ukrainian find.text() tap drivers. See
// integration_test/support/app_harness.dart for the policy rationale.

import 'package:beautica_mobile/l10n/app_localizations.dart';
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

  testWidgets(
    'a per-IP 429 on /auth/forgot-password renders the rate-limit copy, not '
    'errUnknown, and does not advance to the OTP screen',
    (tester) async {
      final fb = FakeBackend(forgotPasswordFailureStatusCode: 429);
      final GoRouter router = await AppHarness.boot(tester, fb);

      // ── Reach /forgot-password from the cold-start login screen ──────────
      expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('login_forgot')));
      await tester.pumpAndSettle();
      AppHarness.expectLocation(router, RouteNames.forgotPassword);

      // ── Submit → the filter answers 429 ──────────────────────────────────
      await tester.enterText(
        find.byKey(const ValueKey<String>('forgot_email')),
        _kEmail,
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('forgot_submit')));
      await tester.pumpAndSettle();

      // The request really did leave the app — otherwise the assertions below
      // would be about a client-side validation stop, not the 429.
      expect(fb.forgotPasswordCalls, equals(1));
      expect(fb.lastForgotPasswordEmail, equals(_kEmail));

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byKey(const ValueKey<String>('forgot_email'))),
      );

      expect(
        find.text(l10n.authResetErrRateLimited),
        findsOneWidget,
        reason:
            'the 429 must reach the screen as PasswordResetRateLimitedFailure '
            'through the real interceptor, not as a bare DioException',
      );
      expect(
        find.text(l10n.errUnknown),
        findsNothing,
        reason:
            'errUnknown is the exact copy the user reported — its absence is '
            'what proves the mapper branch is doing work on the wire',
      );

      // ── And the journey does NOT advance ─────────────────────────────────
      // A 200 here navigates to the OTP screen. Staying put is what stops the
      // user entering a code that was never sent.
      AppHarness.expectLocation(router, RouteNames.forgotPassword);
      expect(
        find.byKey(const ValueKey<String>('reset_otp_code_input')),
        findsNothing,
      );
    },
  );
}
