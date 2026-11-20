// M515 — Widget tests for [RegisterCodeScreen] (step 2 of the phone-first
// wizard) and the shared [PhoneCodeStep] it renders.
//
//   1. Chrome 2-of-4, the formatted phone in bold, CTA disabled until 6 digits.
//   2. A correct code stores the ticket and advances to /register/password.
//   3. 400 INVALID_CODE → «Невірний код…» banner; editing the code clears it.
//   4. 409 PHONE_ALREADY_REGISTERED → back to /register with the 409 banner
//      code as `extra` (never in the URL).
//   5. Resend is cooled down 60 s on arrival (explicit pumps — pumpAndSettle
//      fires no Timer): still blocked at 59 s, then re-sends the code for the
//      same phone.
//   6–9. M1 (AUTH-D27 a) — a failed resend: 429 keeps the cooldown (fallback
//      60 s, or the server's Retry-After), ResendThrottledFailure keeps its
//      seconds, a network error re-enables the link at once.
//   10–13. Audit cycle 1 — a Retry-After of 0 / negative (or a throttle with
//      0) still waits the full 60 s; an over-ceiling value shows «Недоступно»
//      instead of a countdown.

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/register_code_screen.dart';
import 'package:beautica_mobile/features/auth/presentation/register_flow_shell.dart';
import 'package:beautica_mobile/features/auth/presentation/widgets/phone_code_step.dart';
import 'package:beautica_mobile/features/auth/state/register_draft_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../../integration_test/support/app_harness.dart';
import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

const String _phone = '+380671234567';

({ProviderContainer container, FakeAuthRepository repo}) _setUp() {
  final repo = FakeAuthRepository();
  final container = ProviderContainer(
    retry: beauticaProviderRetry,
    overrides: [
      authRepositoryProvider.overrideWith((_) => repo),
      secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
    ],
  );
  container.read(registerDraftProvider.notifier)
    ..start(UserRole.client)
    ..updatePhone(phone: _phone, termsAccepted: true);
  return (container: container, repo: repo);
}

Object? _registerExtra;

Future<GoRouter> _pump(WidgetTester tester, ProviderContainer c) async {
  _registerExtra = null;
  final router = GoRouter(
    initialLocation: RouteNames.registerCode,
    routes: [
      GoRoute(
        path: RouteNames.registerCode,
        builder: (context, state) => const RegisterCodeScreen(),
      ),
      GoRoute(
        path: RouteNames.registerPassword,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('password-step'))),
      ),
      GoRoute(
        path: RouteNames.register,
        builder: (context, state) {
          _registerExtra = state.extra;
          return const Scaffold(body: Center(child: Text('phone-step')));
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
      ),
    ),
  );
  await tester.pump();
  return router;
}

NeumorphicButton _cta(WidgetTester tester) => tester.widget<NeumorphicButton>(
  find.byKey(const ValueKey<String>('phone_code_submit')),
);

Future<void> _enterCode(WidgetTester tester, String code) async {
  await tester.enterText(
    find.byKey(const ValueKey<String>('phone_code_input')),
    code,
  );
  await tester.pump();
}

Future<void> _confirm(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('phone_code_submit')));
  await tester.pump();
  await tester.pump();
}

void main() {
  final AppLocalizations l10n = lookupAppLocalizations(const Locale('uk'));

  testWidgets('1. 2-of-4 chrome, formatted phone, CTA gated on 6 digits', (
    tester,
  ) async {
    final h = _setUp();
    addTearDown(h.container.dispose);
    await _pump(tester, h.container);

    expect(find.byType(WizardStepChrome), findsOneWidget);
    expect(
      tester.widget<WizardStepChrome>(find.byType(WizardStepChrome)).step,
      2,
    );
    expect(
      find.textContaining('+380 67 123 45 67', findRichText: true),
      findsOneWidget,
    );
    expect(_cta(tester).onPressedAsync, isNull);
    await _enterCode(tester, '12345');
    expect(_cta(tester).onPressedAsync, isNull);
    await _enterCode(tester, '123456');
    expect(_cta(tester).onPressedAsync, isNotNull);
  });

  testWidgets('2. a correct code stores the ticket → /register/password', (
    tester,
  ) async {
    final h = _setUp();
    addTearDown(h.container.dispose);
    await _pump(tester, h.container);

    await _enterCode(tester, '123456');
    await _confirm(tester);
    await tester.pump();

    expect(h.repo.verifyRegistrationCodeCalls.single, (
      phone: _phone,
      code: '123456',
    ));
    expect(
      h.container.read(registerDraftProvider)?.registrationTicket,
      'ticket-1',
    );
    expect(find.text('password-step'), findsOneWidget);
  });

  testWidgets('3. INVALID_CODE → inline banner; editing clears it', (
    tester,
  ) async {
    final h = _setUp();
    addTearDown(h.container.dispose);
    h.repo.verifyRegistrationCodeResult = const PhoneIdentityFailure(
      code: PhoneIdentityErrorCode.invalidCode,
    );
    await _pump(tester, h.container);

    await _enterCode(tester, '000000');
    await _confirm(tester);

    expect(find.text(l10n.errPhoneCodeInvalid), findsOneWidget);
    expect(find.text('password-step'), findsNothing);

    await _enterCode(tester, '00000');
    expect(
      find.byKey(const ValueKey<String>('phone_code_error')),
      findsNothing,
    );
  });

  testWidgets('4. 409 PHONE_ALREADY_REGISTERED → /register with the code as '
      'extra', (tester) async {
    final h = _setUp();
    addTearDown(h.container.dispose);
    h.repo.verifyRegistrationCodeResult = const PhoneIdentityFailure(
      code: PhoneIdentityErrorCode.phoneAlreadyRegistered,
    );
    final router = await _pump(tester, h.container);

    await _enterCode(tester, '123456');
    await _confirm(tester);
    await tester.pump();

    expect(find.text('phone-step'), findsOneWidget);
    expect(_registerExtra, PhoneIdentityErrorCode.phoneAlreadyRegistered);
    expect(
      AppHarness.location(router),
      RouteNames.register,
      reason: 'no phone / code / ticket in the URL',
    );
  });

  testWidgets('5. resend cooled down 60 s, then re-sends for the same phone', (
    tester,
  ) async {
    final h = _setUp();
    addTearDown(h.container.dispose);
    await _pump(tester, h.container);

    // Mirrors PhoneCodeStep.resendTimerLabel (the unit suffix is code, not
    // an ARB string).
    final String fullCooldownLabel = l10n.resetOtpResendTimer(
      '$kPhoneCodeResendCooldownSeconds с',
    );
    expect(find.textContaining(fullCooldownLabel), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('phone_code_resend')));
    await tester.pump();
    expect(h.repo.sendRegistrationCodeCalls, isEmpty);

    // pumpAndSettle fires no Timer — advance the countdown explicitly.
    // One second short of the cooldown the resend is still blocked.
    // fixed-wait-ok: TTL crossing — the resend cooldown must fully elapse.
    await tester.pump(
      const Duration(seconds: kPhoneCodeResendCooldownSeconds - 1),
    );
    await tester.tap(find.byKey(const ValueKey<String>('phone_code_resend')));
    await tester.pump();
    expect(h.repo.sendRegistrationCodeCalls, isEmpty);

    // fixed-wait-ok: TTL crossing — the resend cooldown must fully elapse.
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey<String>('phone_code_resend')));
    await tester.pump();
    await tester.pump();
    expect(h.repo.sendRegistrationCodeCalls, <String>[_phone]);

    // Unmount so the fresh cooldown Timer is cancelled by dispose.
    await tester.pumpWidget(const SizedBox());
  });

  // ── M1 — failed resends (shared resendCooldownFor) ──────────────────────

  /// Lets the arrival cooldown run out, then taps «Надіслати знову» once.
  Future<void> resendAfterArrivalCooldown(WidgetTester tester) async {
    // fixed-wait-ok: TTL crossing — the arrival cooldown must fully elapse.
    await tester.pump(const Duration(seconds: kPhoneCodeResendCooldownSeconds));
    await tester.tap(find.byKey(const ValueKey<String>('phone_code_resend')));
    await tester.pump();
    await tester.pump();
  }

  Future<void> tapResend(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey<String>('phone_code_resend')));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('6. 429 rateLimited without Retry-After keeps the link '
      'disabled for the full 60 s (M1 regression)', (tester) async {
    final h = _setUp();
    addTearDown(h.container.dispose);
    h.repo.sendRegistrationCodeFailure = const PhoneIdentityFailure(
      code: PhoneIdentityErrorCode.rateLimited,
    );
    await _pump(tester, h.container);

    await resendAfterArrivalCooldown(tester);
    expect(h.repo.sendRegistrationCodeCalls, <String>[_phone]);
    expect(find.text(l10n.errPhoneCodeRateLimited), findsOneWidget);
    expect(
      find.textContaining(
        l10n.resetOtpResendTimer('$kPhoneCodeResendCooldownSeconds с'),
      ),
      findsOneWidget,
      reason: 'the 429 restarted the cooldown instead of re-enabling resend',
    );

    await tapResend(tester);
    expect(h.repo.sendRegistrationCodeCalls, hasLength(1));
    // fixed-wait-ok: TTL crossing — one second short of the 429 cooldown.
    await tester.pump(
      const Duration(seconds: kPhoneCodeResendCooldownSeconds - 1),
    );
    await tapResend(tester);
    expect(h.repo.sendRegistrationCodeCalls, hasLength(1));

    // fixed-wait-ok: TTL crossing — the 429 cooldown fully elapses.
    await tester.pump(const Duration(seconds: 1));
    await tapResend(tester);
    expect(h.repo.sendRegistrationCodeCalls, hasLength(2));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('7. 429 rateLimited with Retry-After 7 s cools down 7 s', (
    tester,
  ) async {
    final h = _setUp();
    addTearDown(h.container.dispose);
    h.repo.sendRegistrationCodeFailure = const PhoneIdentityFailure(
      code: PhoneIdentityErrorCode.rateLimited,
      retryAfterSeconds: 7,
    );
    await _pump(tester, h.container);

    await resendAfterArrivalCooldown(tester);
    expect(h.repo.sendRegistrationCodeCalls, hasLength(1));
    // fixed-wait-ok: TTL crossing — one second short of Retry-After.
    await tester.pump(const Duration(seconds: 6));
    await tapResend(tester);
    expect(h.repo.sendRegistrationCodeCalls, hasLength(1));
    // fixed-wait-ok: TTL crossing — Retry-After fully elapses.
    await tester.pump(const Duration(seconds: 1));
    await tapResend(tester);
    expect(h.repo.sendRegistrationCodeCalls, hasLength(2));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('8. ResendThrottledFailure keeps its own seconds', (
    tester,
  ) async {
    final h = _setUp();
    addTearDown(h.container.dispose);
    h.repo.sendRegistrationCodeFailure = const ResendThrottledFailure(
      retryAfterSeconds: 5,
    );
    await _pump(tester, h.container);

    await resendAfterArrivalCooldown(tester);
    // fixed-wait-ok: TTL crossing — one second short of the throttle.
    await tester.pump(const Duration(seconds: 4));
    await tapResend(tester);
    expect(h.repo.sendRegistrationCodeCalls, hasLength(1));
    // fixed-wait-ok: TTL crossing — the throttle fully elapses.
    await tester.pump(const Duration(seconds: 1));
    await tapResend(tester);
    expect(h.repo.sendRegistrationCodeCalls, hasLength(2));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('9. a network error re-enables the link at once', (tester) async {
    final h = _setUp();
    addTearDown(h.container.dispose);
    h.repo.sendRegistrationCodeFailure = const NetworkFailure();
    await _pump(tester, h.container);

    await resendAfterArrivalCooldown(tester);
    expect(h.repo.sendRegistrationCodeCalls, hasLength(1));
    await tapResend(tester);
    expect(h.repo.sendRegistrationCodeCalls, hasLength(2));

    await tester.pumpWidget(const SizedBox());
  });

  for (final (String name, Failure failure) in <(String, Failure)>[
    (
      '10. 429 with Retry-After 0',
      const PhoneIdentityFailure(
        code: PhoneIdentityErrorCode.rateLimited,
        retryAfterSeconds: 0,
      ),
    ),
    (
      '11. 429 with a negative Retry-After',
      const PhoneIdentityFailure(
        code: PhoneIdentityErrorCode.rateLimited,
        retryAfterSeconds: -5,
      ),
    ),
    (
      '12. ResendThrottledFailure with 0 s',
      const ResendThrottledFailure(retryAfterSeconds: 0),
    ),
  ]) {
    testWidgets('$name keeps resend disabled for the full 60 s', (
      tester,
    ) async {
      final h = _setUp();
      addTearDown(h.container.dispose);
      h.repo.sendRegistrationCodeFailure = failure;
      await _pump(tester, h.container);

      await resendAfterArrivalCooldown(tester);
      expect(h.repo.sendRegistrationCodeCalls, hasLength(1));
      await tapResend(tester);
      expect(h.repo.sendRegistrationCodeCalls, hasLength(1));
      // fixed-wait-ok: TTL crossing — one second short of the fallback.
      await tester.pump(
        const Duration(seconds: kPhoneCodeResendCooldownSeconds - 1),
      );
      await tapResend(tester);
      expect(h.repo.sendRegistrationCodeCalls, hasLength(1));
      // fixed-wait-ok: TTL crossing — the fallback fully elapses.
      await tester.pump(const Duration(seconds: 1));
      await tapResend(tester);
      expect(h.repo.sendRegistrationCodeCalls, hasLength(2));

      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('13. an over-ceiling Retry-After shows «Недоступно», not a '
      'countdown, and blocks resend', (tester) async {
    final h = _setUp();
    addTearDown(h.container.dispose);
    h.repo.sendRegistrationCodeFailure = const PhoneIdentityFailure(
      code: PhoneIdentityErrorCode.rateLimited,
      retryAfterSeconds: kMaxUxCooldownSeconds + 1,
    );
    await _pump(tester, h.container);

    await resendAfterArrivalCooldown(tester);
    expect(find.textContaining(l10n.resetOtpResendUnavailable), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'\(\d+ с\)')),
      findsNothing,
      reason: 'no numeric countdown above the UX ceiling',
    );
    await tapResend(tester);
    expect(h.repo.sendRegistrationCodeCalls, hasLength(1));

    await tester.pumpWidget(const SizedBox());
  });
}
