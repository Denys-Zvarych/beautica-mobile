// M521 (B520; AUTH-16/18/21/52/53, SAL-48) — staff invite by phone, end to
// end against the FakeBackend through the REAL Dio chain (App Check
// interceptor, ErrorMapperInterceptor, generated client).
//
//   1. The owner invites a master by phone: the form normalises the typed
//      number to `+380…`, `POST /salons/{id}/invite` carries `{phone, role}`
//      (no email), the success copy says an SMS went out, and the form pops.
//   2. The invitee opens the SMS link: salon + masked phone + role preview →
//      phone step → SMS code (B514 registration ticket) → password + name +
//      consent → accept with the ticket → the SALON_MASTER landing.
//
//   3. (mobile-qa) The owner's server-side refusals — 400 PHONE_NOT_UA_MOBILE,
//      409 PHONE_ALREADY_REGISTERED, 429 INVITE_SMS_LIMIT — keep the form
//      open with the right copy (AUTH-18, AUTH-52).
//   4. (mobile-qa) An expired / revoked link shows the invalid-invite copy
//      and its log-in action (AUTH-17).
//   5. (mobile-qa) A phone claimed meanwhile (409 on the code step) sends the
//      invitee back to the phone step; no account is created.
//
// The admin variant of (2) and the server mismatch case live in
// `invite_accept_admin_landing_flow_test.dart`; the pending list (phones +
// cancel) lives in `salon_pending_invites_flow_test.dart`.
//
// Finders: widget Keys and l10n-resolved strings only — never Cyrillic
// literals (`forbid_cyrillic_finder.sh`).

import 'dart:async';

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/accept_invite_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/invite_staff_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

const String _kSalonId = 'salon-xyz';
const String _kToken = 'staff-invite-by-phone-token';

/// `salonManageGuard` authorizes the owner against `GET /salons/mine`, which
/// the fake seeds with only `salon-owner-1` — same seed as
/// `salon_management_profile_flow_test.dart`.
void _seedSalonXyzIntoMySalons(FakeBackend fb) {
  fb.mySalons.add(<String, dynamic>{
    'id': _kSalonId,
    'ownerId': 'user-owner-1',
    'name': FakeBackend.kInviteSalonName,
    'city': 'Київ',
    'cityId': 'city-kyiv',
    'oblastId': 'oblast-kyiv',
    'street': 'вул. Хрещатик',
    'buildingNo': '12',
    'isActive': true,
    'isPrimary': false,
  });
}

Future<void> _fill(WidgetTester tester, String fieldKey, String value) async {
  final Finder field = find.byKey(ValueKey<String>(fieldKey));
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pump();
}

String? _errorText(WidgetTester tester, String fieldKey) => tester
    .widget<NeumorphicTextField>(find.byKey(ValueKey<String>(fieldKey)))
    .errorText;

/// Re-routes `GET /auth/invite/validate` to a typed 400 (AUTH-17). The fake's
/// DioAdapter matches the LAST registered route, so this overrides its 200.
void _failValidate(FakeBackend fb, String code) {
  (fb.dio.httpClientAdapter as DioAdapter).onRoute(
    '/api/v1/auth/invite/validate',
    (server) => server.reply(400, <String, dynamic>{
      'success': false,
      'message': 'FAKE-400',
      'data': <String, dynamic>{'code': code},
    }),
    request: const Request(method: RequestMethods.get),
  );
}

/// Owner logged in, invite form open for [_kSalonId].
Future<AppLocalizations> _openInviteForm(
  WidgetTester tester,
  FakeBackend fb,
) async {
  final GoRouter router = await AppHarness.boot(tester, fb);
  await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
  // fixed-wait-ok: settles the real async login/route-transition step.
  await tester.pumpAndSettle(const Duration(seconds: 1));
  router.go(RouteNames.salonManage(_kSalonId));
  // fixed-wait-ok: settles the real async route-transition step.
  await tester.pumpAndSettle(const Duration(seconds: 1));
  unawaited(router.push(RouteNames.salonInviteStaff(_kSalonId)));
  await AppHarness.pumpUntilFound(tester, find.byType(InviteStaffScreen));
  return AppLocalizations.of(tester.element(find.byType(InviteStaffScreen)));
}

/// Opens the invite link as an unauthenticated invitee.
Future<(GoRouter, AppLocalizations)> _openInviteLink(
  WidgetTester tester,
  FakeBackend fb,
) async {
  final GoRouter router = await AppHarness.boot(tester, fb);
  router.go('${RouteNames.acceptInvite}?token=$_kToken');
  await AppHarness.settle(tester);
  expect(find.byType(AcceptInviteScreen), findsOneWidget);
  return (
    router,
    AppLocalizations.of(tester.element(find.byType(AcceptInviteScreen))),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('the owner invites a master by phone: {phone, role} on the wire, '
      'the SMS success copy, the form pops', (tester) async {
    await mockNetworkImagesFor(() async {
      final fb = FakeBackend()..currentRole = UserRole.salonOwner;
      _seedSalonXyzIntoMySalons(fb);
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      // fixed-wait-ok: settles the real async login/route-transition step.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      router.go(RouteNames.salonManage(_kSalonId));
      // fixed-wait-ok: settles the real async route-transition step.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      unawaited(router.push(RouteNames.salonInviteStaff(_kSalonId)));
      await AppHarness.pumpUntilFound(tester, find.byType(InviteStaffScreen));
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(InviteStaffScreen)),
      );
      expect(find.text(l10n.inviteStaffPhoneHelper), findsOneWidget);

      await _fill(tester, 'invite_phone', '0931234567');
      await AppHarness.tapVisible(tester, find.byKey(const Key('send_invite')));
      await AppHarness.pumpUntilGone(tester, find.byType(InviteStaffScreen));

      expect(fb.inviteStaffCalls, 1);
      final Map<String, dynamic> body = fb.lastInviteStaffBody!;
      expect(body['phone'], '+380931234567');
      expect(body['role'], 'SALON_MASTER');
      expect(
        body.containsKey('email'),
        isFalse,
        reason: 'B520 — the email path is gone',
      );
      expect(find.text(l10n.inviteStaffSuccess), findsOneWidget);
      AppHarness.expectLocation(router, RouteNames.salonManage(_kSalonId));
    });
  });

  testWidgets(
    'the invitee opens the SMS link, confirms the phone by code, sets '
    'password + name + consent, and lands as SALON_MASTER',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()
          ..currentRole = UserRole.salonMaster
          // A fresh invitee has no confirmed notifications email (AUTH-D17).
          ..meEmailVerified = false;
        final GoRouter router = await AppHarness.boot(tester, fb);

        router.go('${RouteNames.acceptInvite}?token=$_kToken');
        await AppHarness.settle(tester);
        expect(find.byType(AcceptInviteScreen), findsOneWidget);
        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(AcceptInviteScreen)),
        );
        expect(fb.lastValidateInviteToken, _kToken);
        // i18n-finder-ok: the fixture salon name from the validate envelope.
        expect(find.text(FakeBackend.kInviteSalonName), findsOneWidget);
        expect(find.text(l10n.invitePhoneMaskedLabel), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('invite_accept')),
          findsNothing,
          reason: 'the password form only comes after the SMS code',
        );

        await _fill(tester, 'invite_phone', '0931234567');
        await AppHarness.tapVisible(
          tester,
          find.byKey(const ValueKey<String>('invite_send_code')),
        );
        await AppHarness.settle(tester);
        expect(fb.registrationCodeSendCalls, 1);
        expect(fb.lastRegistrationCodePhone, '+380931234567');

        await _fill(tester, 'phone_code_input', '123456');
        await AppHarness.tapVisible(
          tester,
          find.byKey(const ValueKey<String>('phone_code_submit')),
        );
        await AppHarness.settle(tester);
        expect(fb.registrationCodeVerifyCalls, 1);

        await _fill(tester, 'invite_password', 'StrongPassword12');
        await _fill(tester, 'invite_first_name', 'Тарас');
        await _fill(tester, 'invite_last_name', 'Майстренко');
        await AppHarness.tapVisible(
          tester,
          find.byKey(const ValueKey<String>('invite_terms_checkbox')),
        );
        await AppHarness.tapVisible(
          tester,
          find.byKey(const ValueKey<String>('invite_accept')),
        );
        await AppHarness.settle(tester);

        expect(fb.acceptInviteCalls, 1);
        final Map<String, dynamic> sent = fb.lastAcceptInviteBody!;
        expect(sent['token'], _kToken);
        expect(sent['registrationTicket'], FakeBackend.kFakeTicket);
        expect(sent['phoneNumber'], isNull);
        expect(sent['termsAccepted'], isTrue);
        expect(find.byType(AcceptInviteScreen), findsNothing);
        AppHarness.expectLocation(router, RouteNames.salonMasterProfile);

        // Device-check 2026-11-19 (AUTH-D17 c): the accept response leaves
        // `emailVerified` unknown, so acceptInvite re-reads `/users/me` and
        // the «Email для сповіщень» card shows at once — no restart.
        expect(
          fb.getMeCalls,
          greaterThanOrEqualTo(1),
          reason: 'acceptInvite must re-read /users/me',
        );
        final Finder emailCard = find.byKey(
          const Key('provider-home-email-card'),
        );
        await AppHarness.pumpUntilFound(tester, emailCard);
        expect(
          find.descendant(
            of: emailCard,
            matching: find.text(l10n.providerHomeEmailPromptTitle),
          ),
          findsOneWidget,
        );
      });
    },
  );

  testWidgets('the owner\'s invite refused by the server (400 not-UA, 409 '
      'registered, 429 SMS limit) keeps the form open with the right copy', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      final fb = FakeBackend()..currentRole = UserRole.salonOwner;
      _seedSalonXyzIntoMySalons(fb);
      final AppLocalizations l10n = await _openInviteForm(tester, fb);
      final Finder send = find.byKey(const Key('send_invite'));
      await _fill(tester, 'invite_phone', '0931234567');

      fb.forceInviteStaffFailure(400, errorCode: 'PHONE_NOT_UA_MOBILE');
      await AppHarness.tapVisible(tester, send);
      await AppHarness.settle(tester);
      expect(fb.inviteStaffCalls, 1);
      expect(_errorText(tester, 'invite_phone'), l10n.errPhoneNotUaMobile);

      fb.forceInviteStaffFailure(409, errorCode: 'PHONE_ALREADY_REGISTERED');
      await AppHarness.tapVisible(tester, send);
      await AppHarness.settle(tester);
      expect(
        _errorText(tester, 'invite_phone'),
        l10n.inviteStaffErrorPhoneAlreadyRegistered,
      );

      fb.forceInviteStaffFailure(429, errorCode: 'INVITE_SMS_LIMIT');
      await AppHarness.tapVisible(tester, send);
      await AppHarness.settle(tester);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('invite_staff_error')),
          matching: find.text(l10n.errInviteSmsLimit),
        ),
        findsOneWidget,
      );
      expect(find.byType(InviteStaffScreen), findsOneWidget);
      expect(find.text(l10n.inviteStaffSuccess), findsNothing);
    });
  });

  for (final String code in <String>['INVITE_EXPIRED', 'INVITE_REVOKED']) {
    testWidgets('a $code link shows the invalid-invite copy, no phone step, '
        'and its log-in action opens /login', (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.salonMaster;
        _failValidate(fb, code);
        final (GoRouter router, AppLocalizations l10n) = await _openInviteLink(
          tester,
          fb,
        );

        expect(find.text(l10n.inviteInvalidError), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('invite_phone')),
          findsNothing,
        );

        await AppHarness.tapVisible(tester, find.text(l10n.loginSubmit));
        await AppHarness.settle(tester);
        expect(find.byType(AcceptInviteScreen), findsNothing);
        AppHarness.expectLocation(router, RouteNames.login);
        expect(fb.registrationCodeSendCalls, 0);
        expect(fb.acceptInviteCalls, 0);
      });
    });
  }

  testWidgets('a phone registered meanwhile (409 on the code step) returns '
      'the invitee to the phone step with the copy; no account', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      final fb = FakeBackend(
        registrationCodeVerifyFailure: (409, 'PHONE_ALREADY_REGISTERED'),
      )..currentRole = UserRole.salonMaster;
      final (_, AppLocalizations l10n) = await _openInviteLink(tester, fb);

      await _fill(tester, 'invite_phone', '0931234567');
      await AppHarness.tapVisible(
        tester,
        find.byKey(const ValueKey<String>('invite_send_code')),
      );
      await AppHarness.settle(tester);
      await _fill(tester, 'phone_code_input', '123456');
      await AppHarness.tapVisible(
        tester,
        find.byKey(const ValueKey<String>('phone_code_submit')),
      );
      await AppHarness.settle(tester);

      expect(fb.registrationCodeVerifyCalls, 1);
      expect(
        _errorText(tester, 'invite_phone'),
        l10n.errPhoneAlreadyRegistered,
      );
      expect(find.byKey(const ValueKey<String>('invite_accept')), findsNothing);
      expect(fb.acceptInviteCalls, 0);
    });
  });
}
