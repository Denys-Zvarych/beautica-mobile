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
}
