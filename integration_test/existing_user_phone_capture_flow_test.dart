// M517 — E2E: existing-user phone capture, phone change, notifications email,
// forgot-password by identifier (AUTH-D12 / D13 / D17 / D18 / D19, AUTH-44,
// AUTH-45, AUTH-50, CLI-D09).
//
// Journeys (real app, FakeBackend, production ErrorMapperInterceptor):
//   1. Legacy CLIENT (unverified hand-typed phone) logs in → held on the
//      blocking add-phone step (no back) → a non-UA number is refused → a
//      DIFFERENT valid number → SMS code only (no password) → client home;
//      the confirmed number replaced the legacy one.
//   2. Legacy INDEPENDENT_MASTER logs in → the SAME blocking step (no provider
//      grace); «Вийти» is the only way out → /login.
//   3. Phone change: wrong current password → «Невірний поточний пароль»;
//      the correct one → saved, old number kept until then.
//   4. Phone change lockout: 10 wrong current passwords → the step locks;
//      they span two codes (5 tries per code — a 6th try on the spent code
//      is INVALID_CODE and does not count), as on the real server.
//   5. «Email для сповіщень»: the client hub row reads «Додати» → email →
//      code + current password (wrong, then right) → the row shows the
//      confirmed address.
//   6. Forgot password by phone: one identifier field, the normalised phone
//      reaches the wire, the code screen never names the channel.
//   QA additions (mobile-qa 2026-11-18):
//   7. Cold start from an App Link with a stored legacy session → the
//      blocking step, never the linked screen; a warm link while held there
//      changes nothing.
//   8. A 409 PHONE_NOT_VERIFIED mid-session → /users/me refresh → the blocking
//      step over the open screen.
//   9. (journey 4, extended) the lockout is one tally: the EMAIL step opens
//      locked with the same copy and sends nothing.
//  10. Email CHANGE end to end: the row shows the confirmed address → a new
//      one → wrong password (old kept) → right password → row shows the new.
//  11. Client booking-success card: shown once per user id (another account's
//      flag on the device does not hide it), never on the next booking.
//  12. Regression (2026-11-19): the provider home email card is gone — an
//      INDEPENDENT_MASTER / SALON_MASTER without a confirmed email sees no
//      card on the profile home, and no provider prompt state is written.
//  13. Phone-first hardening (AUTH-D28): a legacy account whose number is
//      verified on ANOTHER account → the code step's 409
//      PHONE_ALREADY_REGISTERED returns to the add-phone step with the
//      duplicate state (support link, editable field); «Вийти» → /login.
//
// App Links are delivered through the `flutter/navigation` channel (cold
// start = `defaultRouteName`), exactly as booking_review_app_link_flow_test
// does; the native intent half is the patrol tier's
// (integration_test/patrol/deep_link_patrol_test.dart), so NO new PATROL flow.

import 'dart:async';
import 'dart:convert';

import 'package:beautica_mobile/core/storage/storage_keys.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/booking_success_args.dart';
import 'package:beautica_mobile/features/booking/presentation/leave_review_screen.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/settings_row.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/fakes/fake_diagnostics_store.dart';
import '../test/helpers/fakes/fake_secure_storage.dart';
import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';
import 'support/e2e_boot_policy.dart';

AppLocalizations get _l10n => lookupAppLocalizations(const Locale('uk'));

Finder _key(String k) => find.byKey(ValueKey<String>(k));

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

/// A legacy account: the profile phone was typed by hand and never verified.
void _legacy(FakeBackend fb) {
  fb
    ..mePhoneVerified = false
    // `phoneRequiredBy` = today on the injected clock (its presence is the
    // signal; the app never compares it with a clock).
    ..mePhoneRequiredBy = kFixedNow.toIso8601String().substring(0, 10)
    ..meEmailVerified = true;
}

/// An account with a verified phone and no confirmed notifications email.
void _verified(FakeBackend fb) {
  fb
    ..mePhoneVerified = true
    ..meEmailVerified = false;
}

Future<void> _openContactsAndChangePhone(
  WidgetTester tester,
  GoRouter router,
  String phone,
) async {
  router.go(RouteNames.clientEditContacts);
  await AppHarness.settle(tester);
  final Finder field = find.descendant(
    of: find.byKey(const Key('field-phone')),
    matching: find.byType(TextField),
  );
  await _enter(tester, field, phone);
  await _tap(tester, find.byKey(const Key('btn-save-contacts')));
  await AppHarness.pumpUntilFound(tester, _key('phone_code_current_password'));
}

Future<void> _submitCode(
  WidgetTester tester, {
  String? password,
  String code = '123456',
}) async {
  await _enter(tester, _key('phone_code_input'), code);
  if (password != null) {
    await _enter(tester, _key('phone_code_current_password'), password);
  }
  await _tap(tester, _key('phone_code_submit'));
}

/// The emailed review CTA (prod host) — any signed-in deep link will do.
const String _kAppLink = 'https://beautica.app/bookings/booking-1/review';

/// Delivers [location] as Android does for an App Link reaching a running
/// app (`pushRouteInformation` on the navigation channel).
Future<void> _deliverAppLink(WidgetTester tester, String location) async {
  final ByteData message = SystemChannels.navigation.codec.encodeMethodCall(
    MethodCall('pushRouteInformation', <String, Object?>{
      'location': location,
      'state': null,
    }),
  );
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    message,
    (_) {},
  );
  await AppHarness.settle(tester);
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(E2eHarnessApp)));

/// The server phone gate (AUTH-45): every write to [path] answers 409
/// PHONE_NOT_VERIFIED through the production mapper. [status] / [code]
/// (additive, phone-first hardening) answer another envelope instead, e.g.
/// the AUTH-D28 409 PHONE_ALREADY_REGISTERED on the phone verify.
void _gateWrites(
  FakeBackend fb,
  String path, {
  int status = 409,
  String code = 'PHONE_NOT_VERIFIED',
}) {
  fb.dio.interceptors.insert(
    0,
    InterceptorsWrapper(
      onRequest: (RequestOptions o, RequestInterceptorHandler h) {
        if (o.path != path) return h.next(o);
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

const Master _kMaster = Master(
  id: 'master-aaa',
  firstName: 'Софія',
  lastName: 'Бондар',
  avgRating: 4.9,
  reviewCount: 20,
  type: MasterType.independentMaster,
);

final BookingSuccessArgs _kSuccess = BookingSuccessArgs(
  master: _kMaster,
  services: const <MasterService>[
    MasterService(
      id: 'pub-assign-1',
      serviceDefId: 'def-1',
      name: 'Манікюр з покриттям',
      durationMinutes: 60,
      priceMin: 500,
      priceDisplay: '500 ₴',
      category: 'MANICURE',
    ),
  ],
  startAt: kFixedNow.add(const Duration(days: 1)),
);

Map<String, dynamic> _promptState(FakeDiagnosticsStore store) =>
    jsonDecode(store.values[StorageKeys.emailPrompts] ?? '{}')
        as Map<String, dynamic>;

const Key _kClientCard = Key('booking-success-email-card');
const Key _kProviderCard = Key('provider-home-email-card');
Finder get _notNow => _key('auth_banner_secondary_action');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('legacy CLIENT is held on add-phone, replaces the legacy '
      'number with a confirmed one (code only) and lands home', (tester) async {
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.client;
    _legacy(fb);
    fb.clientPhone = '0441234567';
    final GoRouter router = await AppHarness.boot(tester, fb);

    await AppHarness.loginAs(tester, fb, UserRole.client);
    await AppHarness.pumpUntilFound(tester, _key('add_phone'));
    AppHarness.expectLocation(router, RouteNames.addPhone);
    expect(_key('auth_scaffold_back'), findsNothing);

    // Any other location bounces straight back (no data behind the step).
    router.go(RouteNames.clientBookings);
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.addPhone);

    await _enter(tester, _key('add_phone'), '044 123 45 67');
    await _tap(tester, _key('add_phone_submit'));
    expect(find.text(_l10n.errPhoneNotUaMobile), findsOneWidget);
    expect(fb.userPhoneSendCalls, isEmpty);

    await _enter(tester, _key('add_phone'), '093 111 22 33');
    await _tap(tester, _key('add_phone_submit'));
    expect(fb.userPhoneSendCalls, <String>['+380931112233']);
    await AppHarness.pumpUntilFound(tester, _key('phone_code_input'));
    expect(_key('phone_code_current_password'), findsNothing);

    await _submitCode(tester);
    await AppHarness.settle(tester);

    expect(fb.userPhoneVerifyBodies.single['phone'], '+380931112233');
    expect(
      fb.userPhoneVerifyBodies.single.containsKey('currentPassword') &&
          fb.userPhoneVerifyBodies.single['currentPassword'] != null,
      isFalse,
      reason: 'a first add needs only the code (AUTH-D19)',
    );
    AppHarness.expectLocation(router, RouteNames.clientHome);
    expect(_key('add_phone'), findsNothing);
  });

  testWidgets('legacy INDEPENDENT_MASTER gets the SAME blocking step; '
      '«Вийти» is the only way out', (tester) async {
    final FakeBackend fb = FakeBackend();
    _legacy(fb);
    final GoRouter router = await AppHarness.boot(tester, fb);

    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
    await AppHarness.pumpUntilFound(tester, _key('add_phone'));
    AppHarness.expectLocation(router, RouteNames.addPhone);

    router.go(RouteNames.masterProfile);
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.addPhone);

    await _tap(tester, _key('add_phone_logout'));
    await AppHarness.pumpUntilFound(tester, _key('login_email'));
    AppHarness.expectLocation(router, RouteNames.login);
    expect(fb.logoutCalls, 1);
  });

  testWidgets('phone change: wrong current password is refused inline, the '
      'right one saves the new number', (tester) async {
    final FakeBackend fb = FakeBackend(checkCurrentPassword: true)
      ..currentRole = UserRole.client;
    _verified(fb);
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.client);

    await _openContactsAndChangePhone(tester, router, '093 111 22 33');
    expect(fb.userPhoneSendCalls, <String>['+380931112233']);

    await _submitCode(tester, password: 'wrong-password');
    expect(find.text(_l10n.errCurrentPasswordInvalid), findsOneWidget);
    expect(fb.lastConfirmedPhone, isNull, reason: 'old number kept');

    await _submitCode(tester, password: FakeBackend.kCurrentPassword);
    await AppHarness.settle(tester);

    expect(fb.lastConfirmedPhone, '+380931112233');
    expect(
      fb.userPhoneVerifyBodies.last['currentPassword'],
      FakeBackend.kCurrentPassword,
    );
    AppHarness.expectLocation(router, RouteNames.clientHome);
  });

  testWidgets('phone change: 10 wrong current passwords lock the step', (
    tester,
  ) async {
    final FakeBackend fb = FakeBackend(checkCurrentPassword: true)
      ..currentRole = UserRole.client;
    _verified(fb);
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.client);

    // As on the real server, one code allows 5 tries (AUTH-D19): 10 wrong
    // passwords span two codes.
    await _openContactsAndChangePhone(tester, router, '093 111 22 33');
    for (int i = 0; i < FakeBackend.kCodeMaxTries; i++) {
      await _submitCode(tester, password: 'wrong-$i');
    }
    expect(find.text(_l10n.phoneCodeLocked), findsNothing);

    // The 6th try on the spent code: INVALID_CODE — not a password answer,
    // so it does not count toward the lockout.
    await _submitCode(tester, password: 'wrong-spent');
    expect(fb.userPhoneVerifyBodies, hasLength(6));
    expect(find.text(_l10n.errCurrentPasswordInvalid), findsNothing);
    expect(find.text(_l10n.phoneCodeLocked), findsNothing);

    // A fresh code: back to the contacts form (the step pops `false`, so the
    // form's save settles) and save again → a new send → 5 more wrong
    // passwords.
    await _tap(tester, _key('auth_scaffold_back'));
    await _tap(tester, find.byKey(const Key('btn-save-contacts')));
    await AppHarness.pumpUntilFound(
      tester,
      _key('phone_code_current_password'),
    );
    expect(fb.userPhoneSendCalls, hasLength(2));
    for (int i = 5; i < 10; i++) {
      await _submitCode(tester, password: 'wrong-$i');
    }

    expect(find.text(_l10n.phoneCodeLocked), findsOneWidget);
    expect(fb.userPhoneVerifyBodies, hasLength(11));
    await _tap(tester, _key('phone_code_submit'));
    expect(
      fb.userPhoneVerifyBodies,
      hasLength(11),
      reason: 'a locked step sends nothing',
    );

    // ONE lockout for both paths (AUTH-D19): the email step opens locked.
    router.go(RouteNames.clientHome);
    await AppHarness.settle(tester);
    unawaited(router.push(RouteNames.clientMenu));
    await AppHarness.settle(tester);
    await _tap(tester, find.byKey(const Key('row-notification-email')));
    await _enter(
      tester,
      find.byKey(const Key('field-notification-email')),
      'olena@beautica.ua',
    );
    await _tap(tester, find.byKey(const Key('btn-email-send-code')));
    await AppHarness.pumpUntilFound(tester, _key('phone_code_input'));

    expect(find.text(_l10n.phoneCodeLocked), findsOneWidget);
    await _submitCode(tester, password: FakeBackend.kCurrentPassword);
    expect(
      fb.notificationEmailVerifyBodies,
      isEmpty,
      reason: 'even the right password is not sent while locked',
    );
    expect(fb.meEmailVerified, isFalse);
  });

  testWidgets('«Email для сповіщень»: «Додати» → code + current password → '
      'the row shows the confirmed address', (tester) async {
    final FakeBackend fb = FakeBackend(checkCurrentPassword: true)
      ..currentRole = UserRole.client;
    _verified(fb);
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.client);

    unawaited(router.push(RouteNames.clientMenu));
    await AppHarness.settle(tester);
    const Key row = Key('row-notification-email');
    await AppHarness.pumpUntilFound(tester, find.byKey(row));
    expect(
      tester.widget<SettingsRow>(find.byKey(row)).value,
      _l10n.emailPromptAdd,
    );

    await _tap(tester, find.byKey(row));
    await _enter(
      tester,
      find.byKey(const Key('field-notification-email')),
      'olena@beautica.ua',
    );
    await _tap(tester, find.byKey(const Key('btn-email-send-code')));
    expect(fb.notificationEmailRequestCalls, <String>['olena@beautica.ua']);
    await AppHarness.pumpUntilFound(
      tester,
      _key('phone_code_current_password'),
    );

    await _submitCode(tester, password: 'wrong-password');
    expect(find.text(_l10n.errCurrentPasswordInvalid), findsOneWidget);

    await _submitCode(tester, password: FakeBackend.kCurrentPassword);
    await AppHarness.pumpUntilFound(tester, find.byKey(row));
    await AppHarness.settle(tester);

    expect(
      tester.widget<SettingsRow>(find.byKey(row)).value,
      'olena@beautica.ua',
    );
    expect(fb.meEmailVerified, isTrue);
  });

  testWidgets('forgot password by phone: one identifier field, normalised on '
      'the wire, neutral code screen', (tester) async {
    final FakeBackend fb = FakeBackend();
    final GoRouter router = await AppHarness.boot(tester, fb);

    await _tap(tester, _key('login_forgot'));
    AppHarness.expectLocation(router, RouteNames.forgotPassword);

    await _enter(tester, _key('forgot_identifier'), '067 123 45 67');
    await _tap(tester, _key('forgot_submit'));

    expect(fb.lastForgotPasswordEmail, '+380671234567');
    AppHarness.expectLocation(router, RouteNames.resetOtpVerification);
    expect(find.textContaining(_l10n.resetCodeSentNeutral), findsOneWidget);
    expect(find.textContaining('380'), findsNothing, reason: 'no channel');
  });

  testWidgets('COLD START from an App Link with a stored legacy session: the '
      'blocking step, never the linked screen', (tester) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = _kAppLink;
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final FakeBackend fb = FakeBackend()
      ..currentRole = UserRole.client
      ..bookingStatus = 'COMPLETED'
      ..bookingCanReview = true;
    _legacy(fb);
    final FakeSecureStorage storage = FakeSecureStorage();
    await storage.writeRefreshToken('fake-refresh-token');

    final GoRouter router = await AppHarness.boot(tester, fb, storage: storage);
    await AppHarness.pumpUntilFound(tester, _key('add_phone'));
    await AppHarness.settle(tester);

    AppHarness.expectLocation(router, RouteNames.addPhone);
    expect(find.byType(LeaveReviewScreen), findsNothing);

    // A warm link while held changes nothing.
    await _deliverAppLink(tester, _kAppLink);
    AppHarness.expectLocation(router, RouteNames.addPhone);
    expect(find.byType(LeaveReviewScreen), findsNothing);
  });

  testWidgets('a 409 PHONE_NOT_VERIFIED mid-session refreshes the profile '
      'and shows the blocking step over the open screen', (tester) async {
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.client;
    _verified(fb);
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.client);
    // The production `onPhoneNotVerified` hook is wired by the E2E boot
    // itself (FakeBackend + e2eProviderOverrides, as dioProvider does).
    router.go(RouteNames.clientBookings);
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.clientBookings);

    // The server now gates this account (its phone is not verified).
    _legacy(fb);
    _gateWrites(fb, '/api/v1/appointments');
    final int meBefore = fb.getMeCalls;
    await expectLater(
      fb.dio.post<dynamic>('/api/v1/appointments'),
      throwsA(isA<DioException>()),
    );
    await AppHarness.pumpUntilFound(tester, _key('add_phone'));
    await AppHarness.settle(tester);

    expect(fb.getMeCalls, meBefore + 1);
    AppHarness.expectLocation(router, RouteNames.addPhone);
    expect(_key('auth_scaffold_back'), findsNothing);
  });

  testWidgets('email CHANGE: the row shows the confirmed address; a wrong '
      'password keeps it, the right one replaces it', (tester) async {
    final FakeBackend fb = FakeBackend(checkCurrentPassword: true)
      ..currentRole = UserRole.client;
    _verified(fb);
    fb
      ..meEmailVerified = true
      ..meConfirmedEmail = 'old@beautica.ua';
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.client);

    unawaited(router.push(RouteNames.clientMenu));
    await AppHarness.settle(tester);
    const Key row = Key('row-notification-email');
    await AppHarness.pumpUntilFound(tester, find.byKey(row));
    expect(
      tester.widget<SettingsRow>(find.byKey(row)).value,
      'old@beautica.ua',
    );

    await _tap(tester, find.byKey(row));
    await _enter(
      tester,
      find.byKey(const Key('field-notification-email')),
      'new@beautica.ua',
    );
    await _tap(tester, find.byKey(const Key('btn-email-send-code')));
    expect(fb.notificationEmailRequestCalls, <String>['new@beautica.ua']);
    await AppHarness.pumpUntilFound(
      tester,
      _key('phone_code_current_password'),
    );

    await _submitCode(tester, password: 'wrong-password');
    expect(find.text(_l10n.errCurrentPasswordInvalid), findsOneWidget);
    expect(fb.meConfirmedEmail, 'old@beautica.ua');

    await _submitCode(tester, password: FakeBackend.kCurrentPassword);
    await AppHarness.pumpUntilFound(tester, find.byKey(row));
    await AppHarness.settle(tester);

    expect(fb.notificationEmailVerifyBodies.last['email'], 'new@beautica.ua');
    expect(
      fb.notificationEmailVerifyBodies.last['currentPassword'],
      FakeBackend.kCurrentPassword,
    );
    expect(
      tester.widget<SettingsRow>(find.byKey(row)).value,
      'new@beautica.ua',
    );
  });

  testWidgets('client booking-success email card: once per user id, never on '
      'the next booking', (tester) async {
    final FakeDiagnosticsStore diagnostics = FakeDiagnosticsStore()
      ..values[StorageKeys.emailPrompts] = jsonEncode(<String, dynamic>{
        'another-client': <String, dynamic>{'clientCardShown': true},
      });
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.client;
    _verified(fb);
    final GoRouter router = await AppHarness.boot(
      tester,
      fb,
      diagnostics: diagnostics,
    );
    await AppHarness.loginAs(tester, fb, UserRole.client);

    unawaited(router.push(RouteNames.bookingSuccess, extra: _kSuccess));
    await AppHarness.pumpUntilFound(tester, find.byKey(_kClientCard));
    expect(find.text(_l10n.bookingSuccessEmailPromptTitle), findsOneWidget);
    await _tap(tester, _notNow);
    expect(find.byKey(_kClientCard), findsNothing);

    router.go(RouteNames.clientHome);
    await AppHarness.settle(tester);
    unawaited(router.push(RouteNames.bookingSuccess, extra: _kSuccess));
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.bookingSuccess);
    expect(find.byKey(_kClientCard), findsNothing);

    final Map<String, dynamic> stored = _promptState(diagnostics);
    expect(
      (stored['user-client-1'] as Map<String, dynamic>)['clientCardShown'],
      isTrue,
    );
    expect(stored.containsKey('another-client'), isTrue);
  });

  testWidgets('regression: no provider home email card on any provider '
      'profile, even without a confirmed email', (tester) async {
    final FakeDiagnosticsStore diagnostics = FakeDiagnosticsStore();
    final FakeBackend fb = FakeBackend();
    _verified(fb);
    expect(fb.meEmailVerified, isFalse, reason: 'the old card\'s trigger');
    final GoRouter router = await AppHarness.boot(
      tester,
      fb,
      diagnostics: diagnostics,
    );

    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
    AppHarness.expectLocation(router, RouteNames.masterProfile);
    await AppHarness.settle(tester);
    expect(find.byKey(_kProviderCard), findsNothing);

    await _container(tester).read(authProvider.notifier).logout();
    await AppHarness.settle(tester);
    await AppHarness.loginAs(tester, fb, UserRole.salonMaster);
    AppHarness.expectLocation(router, RouteNames.salonMasterProfile);
    await AppHarness.settle(tester);
    expect(find.byKey(_kProviderCard), findsNothing);

    expect(
      diagnostics.values.containsKey(StorageKeys.emailPrompts),
      isFalse,
      reason: 'no provider prompt state is ever written',
    );
  });

  testWidgets('legacy duplicate (AUTH-D28): the verify-time 409 '
      'PHONE_ALREADY_REGISTERED shows the support state on the add-phone '
      'step; «Вийти» is still the way out', (tester) async {
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.client;
    _legacy(fb);
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.client);
    await AppHarness.pumpUntilFound(tester, _key('add_phone'));
    _gateWrites(
      fb,
      '/api/v1/users/me/phone/otp/verify',
      code: 'PHONE_ALREADY_REGISTERED',
    );

    await _enter(tester, _key('add_phone'), '093 111 22 33');
    await _tap(tester, _key('add_phone_submit'));
    await AppHarness.pumpUntilFound(tester, _key('phone_code_input'));
    await _submitCode(tester);
    await AppHarness.pumpUntilFound(tester, _key('add_phone_duplicate'));

    AppHarness.expectLocation(router, RouteNames.addPhone);
    expect(find.text(_l10n.addPhoneDuplicateMessage), findsOneWidget);
    expect(find.text(_l10n.addPhoneContactSupport), findsOneWidget);
    expect(fb.mePhoneVerified, isFalse, reason: 'nothing was confirmed');
    // Still blocking: any other location bounces back.
    router.go(RouteNames.clientBookings);
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.addPhone);

    await _tap(tester, _key('add_phone_logout'));
    await AppHarness.pumpUntilFound(tester, _key('login_email'));
    AppHarness.expectLocation(router, RouteNames.login);
    expect(fb.logoutCalls, 1);
  });
}
