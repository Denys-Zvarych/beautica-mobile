// M515 — E2E: phone-first login and registration (AUTH-08 / AUTH-41 /
// AUTH-46 / AUTH-D11). Replaces the email-wizard flows
// `register_flow_test.dart` and `register_locality_persistence_flow_test.dart`
// (their email step and email-verification hop no longer exist in the app).
//
// Journeys:
//   1. CLIENT     — role → phone → SMS code → password → name → address
//                   (skip) → /done. No email anywhere on the wire.
//   2. MASTER     — same steps, address required → locality PATCH → /done
//                   (the session comes from register itself, no email OTP).
//   3. Login by phone  — `067 123 45 67` is sent as `+380671234567`.
//   4. Login by email  — sent unchanged as the identifier.
//   5. Login with a non-UA number — inline error, no request.
//   6. SALON_OWNER — same steps + salon name → register + POST /salons → /done.
//   7. App Check — the token rides ONLY on the SMS-send request (production
//      interceptor + generated client paths, recorded at the wire).
//   8. Wrong SMS code (400 INVALID_CODE) — inline error, stays on the code step.
//   9. 409 PHONE_ALREADY_REGISTERED — back to the phone step, «Увійти» → /login.
//  10. Expired ticket (400 REGISTRATION_TICKET_INVALID) at submit — back to the
//      phone step, which re-sends the code.
//  11. 403 APP_CHECK_FAILED on send — «update from Google Play» banner.
//
// NO PATROL FLOW: no OS permission, deep link, notification or WebView.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/state/register_draft.dart';
import 'package:beautica_mobile/features/auth/state/register_draft_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/utils/legal_versions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';
import 'support/e2e_boot_policy.dart';

Future<void> _enter(WidgetTester tester, String key, String text) async {
  final Finder f = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(f);
  await tester.enterText(f, text);
  await tester.pump();
}

/// The register body must be the phone-first shape: ticket, consent triple,
/// and NO email / phoneNumber (the ticket carries the verified phone).
void _expectPhoneFirstRegisterBody(FakeBackend fb, {required String role}) {
  final Map<String, dynamic>? body = fb.lastRegisterBody;
  expect(body, isNotNull, reason: 'register must reach the wire');
  expect(body!['registrationTicket'], FakeBackend.kFakeTicket);
  expect(body.containsKey('email'), isFalse, reason: 'no email (AUTH-D11)');
  expect(body.containsKey('phoneNumber'), isFalse);
  expect(body['termsAccepted'], isTrue);
  expect(body['termsVersion'], kTermsVersion);
  expect(body['privacyPolicyVersion'], kPrivacyPolicyVersion);
  if (role != 'INDEPENDENT_MASTER') expect(body['role'], role);
}

const String _kE2eAppCheckToken = 'e2e-app-check-token';

AppLocalizations get _l10n => lookupAppLocalizations(const Locale('uk'));

/// The phone step's error banner carries [message].
void _expectSendBanner(String message) {
  expect(
    find.descendant(
      of: find.byKey(const ValueKey<String>('phone_send_error')),
      matching: find.text(message),
    ),
    findsOneWidget,
  );
}

/// Role → phone + consent → «Надіслати код». Stops wherever the send lands
/// (the full happy path is [AppHarness.registerPhoneFirstSteps]).
Future<void> _submitPhoneStep(
  WidgetTester tester,
  GoRouter router, {
  String roleKey = 'role_client',
  String phone = '067 123 45 67',
}) async {
  router.go(RouteNames.registerRole);
  await tester.pumpAndSettle();
  await AppHarness.tapVisible(tester, find.byKey(ValueKey<String>(roleKey)));
  await AppHarness.tapVisible(
    tester,
    find.byKey(const ValueKey<String>('role_continue')),
  );
  await tester.pumpAndSettle();
  await _enter(tester, 'step1_phone', phone);
  await AppHarness.tapVisible(
    tester,
    find.byKey(const ValueKey<String>('step1_terms_checkbox')),
  );
  await AppHarness.tapVisible(
    tester,
    find.byKey(const ValueKey<String>('step1_submit')),
  );
  await tester.pumpAndSettle();
}

Future<void> _submitCode(WidgetTester tester) async {
  await _enter(tester, 'phone_code_input', '123456');
  await AppHarness.tapVisible(
    tester,
    find.byKey(const ValueKey<String>('phone_code_submit')),
  );
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('CLIENT registers phone → code → password → name → /done', (
    tester,
  ) async {
    final fb = FakeBackend()..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(tester, fb);

    await AppHarness.registerPhoneFirstSteps(
      tester,
      router,
      roleKey: 'role_client',
      phone: '067 123 45 67',
    );
    expect(fb.registrationCodeSendCalls, 1);
    expect(fb.lastRegistrationCodePhone, '+380671234567');
    expect(fb.registrationCodeVerifyCalls, 1);
    expect(
      find.byKey(const ValueKey<String>('step2_phone')),
      findsNothing,
      reason: 'the phone is step 1 now; the name step has no phone field',
    );

    await _enter(tester, 'step2_first_name', 'Олена');
    await _enter(tester, 'step2_last_name', 'Коваль');
    await AppHarness.tapVisible(
      tester,
      find.byKey(const ValueKey<String>('step2_submit')),
    );
    await tester.pumpAndSettle();
    AppHarness.expectLocation(router, RouteNames.registerStep3);

    await AppHarness.tapVisible(
      tester,
      find.byKey(const ValueKey<String>('address_skip')),
    );
    await AppHarness.pumpUntilCondition(
      tester,
      () => AppHarness.location(router) == RouteNames.done,
      description: 'phone-first register → /done',
    );
    _expectPhoneFirstRegisterBody(fb, role: 'CLIENT');
    expect(fb.verifyEmailCalls, 0, reason: 'no email verification hop');
  });

  testWidgets('INDEPENDENT_MASTER registers with no email and saves the '
      'address with the new session', (tester) async {
    final fb = FakeBackend()..currentRole = UserRole.independentMaster;
    final GoRouter router = await AppHarness.boot(tester, fb);

    await AppHarness.registerPhoneFirstSteps(
      tester,
      router,
      roleKey: 'role_master',
      phone: '+380 50 333 22 11',
    );
    expect(fb.lastRegistrationCodePhone, '+380503332211');

    await _enter(tester, 'step2_first_name', 'Ірина');
    await _enter(tester, 'step2_last_name', 'Майстер');
    await AppHarness.tapVisible(
      tester,
      find.byKey(const ValueKey<String>('step2_submit')),
    );
    await tester.pumpAndSettle();
    AppHarness.expectLocation(router, RouteNames.registerStep3);

    await AppHarness.pickSettlement(tester, 'city-kyiv');
    await _enter(tester, 'address_street', 'вул. Хрещатик');
    await _enter(tester, 'address_building', '1');
    await AppHarness.tapVisible(
      tester,
      find.byKey(const ValueKey<String>('address_submit')),
    );
    await AppHarness.pumpUntilCondition(
      tester,
      () => AppHarness.location(router) == RouteNames.done,
      description: 'register + locality PATCH → /done',
    );
    _expectPhoneFirstRegisterBody(fb, role: 'INDEPENDENT_MASTER');
    expect(fb.patchMasterLocalityCalls, 1);
    expect(fb.verifyEmailCalls, 0);
  });

  testWidgets('login by phone sends the normalised +380 identifier', (
    tester,
  ) async {
    final fb = FakeBackend(appCheckToken: _kE2eAppCheckToken)
      ..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(tester, fb);

    await AppHarness.loginAs(
      tester,
      fb,
      UserRole.client,
      identifier: '067 123 45 67',
    );

    AppHarness.expectLocation(router, RouteNames.clientHome);
    expect(fb.loginCalls, 1);
    expect(fb.lastLoginBody?['identifier'], '+380671234567');
    expect(fb.lastLoginBody?.containsKey('email'), isFalse);
    expect(
      fb.appCheckHeaderLog.where((r) => r.path.endsWith('/auth/login')),
      isNotEmpty,
    );
    expect(
      fb.appCheckHeaderLog.where((r) => r.header != null),
      isEmpty,
      reason: 'login (and nothing else here) sends no SMS → no App Check',
    );
  });

  testWidgets('login by email sends the email as the identifier', (
    tester,
  ) async {
    final fb = FakeBackend()..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(tester, fb);

    await AppHarness.loginAs(tester, fb, UserRole.client);

    AppHarness.expectLocation(router, RouteNames.clientHome);
    expect(fb.lastLoginBody?['identifier'], 'client@beautica.ua');
  });

  testWidgets('login refuses a non-UA number inline, before any request', (
    tester,
  ) async {
    final fb = FakeBackend()..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.pumpUntilFound(
      tester,
      find.byKey(const ValueKey<String>('login_email')),
    );

    await _enter(tester, 'login_email', '+48 512 345 678');
    await _enter(tester, 'login_password', 'Secret1234');
    await AppHarness.tapVisible(
      tester,
      find.byKey(const ValueKey<String>('login_submit')),
    );
    await tester.pumpAndSettle();

    expect(find.text(_l10n.errPhoneNotUaMobile), findsOneWidget);
    expect(fb.loginCalls, 0);
    AppHarness.expectLocation(router, RouteNames.login);
  });

  testWidgets('SALON_OWNER registers with a salon name and no email → /done', (
    tester,
  ) async {
    final fb = FakeBackend()..currentRole = UserRole.salonOwner;
    final GoRouter router = await AppHarness.boot(tester, fb);

    await AppHarness.registerPhoneFirstSteps(
      tester,
      router,
      roleKey: 'role_salon_owner',
      phone: '063 555 44 33',
    );
    expect(fb.lastRegistrationCodePhone, '+380635554433');

    await _enter(tester, 'step2_first_name', 'Марта');
    await _enter(tester, 'step2_last_name', 'Власниця');
    await _enter(tester, 'step2_salon_name', 'Салон Марти');
    await AppHarness.tapVisible(
      tester,
      find.byKey(const ValueKey<String>('step2_submit')),
    );
    await tester.pumpAndSettle();
    AppHarness.expectLocation(router, RouteNames.registerStep3);

    await AppHarness.pickSettlement(tester, 'city-kyiv');
    await _enter(tester, 'address_street', 'вул. Саксаганського');
    await _enter(tester, 'address_building', '12');
    await AppHarness.tapVisible(
      tester,
      find.byKey(const ValueKey<String>('address_submit')),
    );
    await AppHarness.pumpUntilCondition(
      tester,
      () => AppHarness.location(router) == RouteNames.done,
      description: 'owner register + POST /salons → /done',
    );
    _expectPhoneFirstRegisterBody(fb, role: 'SALON_OWNER');
    expect(fb.lastRegisterBody?['businessName'], 'Салон Марти');
    expect(fb.createSalonCalls, 1);
    expect(fb.verifyEmailCalls, 0);
  });

  testWidgets('App Check token rides only on the SMS-send request', (
    tester,
  ) async {
    final fb = FakeBackend(appCheckToken: _kE2eAppCheckToken)
      ..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(tester, fb);

    await AppHarness.registerPhoneFirstSteps(
      tester,
      router,
      roleKey: 'role_client',
      phone: '067 123 45 67',
    );
    await _enter(tester, 'step2_first_name', 'Олена');
    await _enter(tester, 'step2_last_name', 'Коваль');
    await AppHarness.tapVisible(
      tester,
      find.byKey(const ValueKey<String>('step2_submit')),
    );
    await tester.pumpAndSettle();
    await AppHarness.tapVisible(
      tester,
      find.byKey(const ValueKey<String>('address_skip')),
    );
    await AppHarness.pumpUntilCondition(
      tester,
      () => AppHarness.location(router) == RouteNames.done,
      description: 'phone-first register → /done',
    );

    final sends = fb.appCheckHeaderLog.where(
      (r) => r.path.endsWith('/auth/register/phone/otp/send'),
    );
    expect(sends, hasLength(1));
    expect(sends.single.header, _kE2eAppCheckToken);
    final others = fb.appCheckHeaderLog.where(
      (r) => !r.path.endsWith('/auth/register/phone/otp/send'),
    );
    expect(
      others.map((r) => r.path),
      containsAll(<Matcher>[
        endsWith('/auth/register/phone/otp/verify'),
        endsWith('/auth/register'),
      ]),
    );
    expect(
      others.where((r) => r.header != null).map((r) => r.path),
      isEmpty,
      reason: 'the token is a credential — SMS-send paths only',
    );
  });

  testWidgets('wrong SMS code shows the inline error and stays on the code '
      'step', (tester) async {
    final fb = FakeBackend(registrationCodeVerifyFailure: (400, 'INVALID_CODE'))
      ..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(tester, fb);

    await _submitPhoneStep(tester, router);
    AppHarness.expectLocation(router, RouteNames.registerCode);
    await _submitCode(tester);

    AppHarness.expectLocation(router, RouteNames.registerCode);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('phone_code_error')),
        matching: find.text(_l10n.errPhoneCodeInvalid),
      ),
      findsOneWidget,
    );
    expect(fb.registrationCodeVerifyCalls, 1);
    expect(fb.registerCalls, 0);
  });

  testWidgets('409 PHONE_ALREADY_REGISTERED returns to the phone step and '
      'its sign-in action opens /login', (tester) async {
    final fb = FakeBackend(
      registrationCodeVerifyFailure: (409, 'PHONE_ALREADY_REGISTERED'),
    )..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(tester, fb);

    await _submitPhoneStep(tester, router);
    await _submitCode(tester);

    AppHarness.expectLocation(router, RouteNames.register);
    _expectSendBanner(_l10n.errPhoneAlreadyRegistered);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('phone_send_error')),
        matching: find.byKey(const ValueKey<String>('auth_banner_action')),
      ),
      findsOneWidget,
    );

    await AppHarness.tapVisible(
      tester,
      find.byKey(const ValueKey<String>('auth_banner_action')),
    );
    await tester.pumpAndSettle();
    AppHarness.expectLocation(router, RouteNames.login);
    expect(fb.registerCalls, 0);
  });

  testWidgets('expired ticket at submit returns to the phone step, which '
      're-sends the code', (tester) async {
    final fb = FakeBackend(
      registerFailure: (400, 'REGISTRATION_TICKET_INVALID'),
    )..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(tester, fb);

    await AppHarness.registerPhoneFirstSteps(
      tester,
      router,
      roleKey: 'role_client',
      phone: '067 123 45 67',
    );
    await _enter(tester, 'step2_first_name', 'Олена');
    await _enter(tester, 'step2_last_name', 'Коваль');
    await AppHarness.tapVisible(
      tester,
      find.byKey(const ValueKey<String>('step2_submit')),
    );
    await tester.pumpAndSettle();
    expect(
      _draft(tester)?.registrationTicket,
      isNotNull,
      reason: 'precondition: the SMS step minted a ticket',
    );
    await AppHarness.tapVisible(
      tester,
      find.byKey(const ValueKey<String>('address_skip')),
    );
    await AppHarness.pumpUntilCondition(
      tester,
      () => AppHarness.location(router) == RouteNames.register,
      description: 'ticket rejected → back to the phone step',
    );
    expect(fb.registerCalls, 1);
    _expectSendBanner(_l10n.errRegistrationTicketInvalid);
    // The refused ticket is a dead credential — wiped from the draft.
    final RegisterDraft? draft = _draft(tester);
    expect(draft, isNotNull);
    expect(draft?.registrationTicket, isNull);

    // The phone and consent survive in the draft — one tap re-sends.
    await AppHarness.tapVisible(
      tester,
      find.byKey(const ValueKey<String>('step1_submit')),
    );
    await tester.pumpAndSettle();
    AppHarness.expectLocation(router, RouteNames.registerCode);
    expect(fb.registrationCodeSendCalls, 2);
    expect(fb.lastRegistrationCodePhone, '+380671234567');
  });

  testWidgets('403 APP_CHECK_FAILED on send shows the update-from-Play '
      'banner and stays on the phone step', (tester) async {
    final fb = FakeBackend(
      registrationCodeSendFailure: (403, 'APP_CHECK_FAILED'),
    )..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(tester, fb);

    await _submitPhoneStep(tester, router);

    AppHarness.expectLocation(router, RouteNames.register);
    _expectSendBanner(_l10n.errAppCheckFailed);
    expect(fb.registrationCodeSendCalls, 1);
    expect(fb.registrationCodeVerifyCalls, 0);
    expect(fb.logoutCalls, 0, reason: 'a 403 never enters the 401 path');
  });
}

/// The live registration draft from the harness container.
RegisterDraft? _draft(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(E2eHarnessApp)),
).read(registerDraftProvider);
