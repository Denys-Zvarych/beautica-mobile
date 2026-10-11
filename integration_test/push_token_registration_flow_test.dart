// Phase 067 — E2E: FCM device-token registration across login / logout / the
// next user's login (Android push, fake-backed).
//
// What is REAL: the whole Dio -> generated `DeviceControllerApi` ->
// `HttpDeviceTokenRepository` -> `PushRegistration` notifier -> `AuthNotifier`
// logout hook stack, the real settings-hub logout UI, the real secure-storage
// flag logic (over `FakeSecureStorage`). What is FAKE: `FirebaseMessaging`
// (mocktail; `firebaseMessagingProvider`), `pushAvailableProvider` (true — the
// host has no google-services.json), and the network socket (`FakeBackend`
// records `POST`/`DELETE /api/v1/devices/token`).
//
// Journey: client login -> POST token-1 (permission asked once) -> logout ->
// DELETE token-1 + deleteToken() -> master login (another user on the same
// device) -> POST the FRESH token-2, and the permission dialog is NOT shown
// again (flag survives the logout wipe).
//
// `E2eHarnessApp` does not mount `BeauticaApp`, so the test mirrors
// `main.dart`'s `ref.listen(pushRegistrationProvider)` eager start.
//
// The native POST_NOTIFICATIONS dialog is NOT covered here (needs a device
// with Firebase config) — see `integration_test/patrol/deep_link_patrol_test.dart`.
//
// Runs headless: `flutter test integration_test/push_token_registration_flow_test.dart
// -d flutter-tester`.

import 'dart:async';

import 'package:beautica_mobile/core/push/firebase_messaging_provider.dart';
import 'package:beautica_mobile/core/push/push_available_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/notifications/domain/push_registration_state.dart';
import 'package:beautica_mobile/features/notifications/presentation/push_registration_notifier.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test/helpers/fakes/fake_secure_storage.dart';
import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';
import 'support/e2e_boot_policy.dart';

class _MockMessaging extends Mock implements FirebaseMessaging {}

NotificationSettings _authorized() => const NotificationSettings(
  alert: AppleNotificationSetting.notSupported,
  announcement: AppleNotificationSetting.notSupported,
  authorizationStatus: AuthorizationStatus.authorized,
  badge: AppleNotificationSetting.notSupported,
  carPlay: AppleNotificationSetting.notSupported,
  lockScreen: AppleNotificationSetting.notSupported,
  notificationCenter: AppleNotificationSetting.notSupported,
  showPreviews: AppleShowPreviewSetting.notSupported,
  timeSensitive: AppleNotificationSetting.notSupported,
  criticalAlert: AppleNotificationSetting.notSupported,
  sound: AppleNotificationSetting.notSupported,
  providesAppNotificationSettings: AppleNotificationSetting.notSupported,
);

/// A fake FCM: each `deleteToken()` rotates the token, like the real SDK (the
/// next `getToken()` yields a fresh one).
class _FcmFixture {
  _FcmFixture() {
    when(() => messaging.getToken()).thenAnswer((_) async => 'fake-fcm-$_gen');
    when(() => messaging.deleteToken()).thenAnswer((_) async {
      deleteTokenCalls++;
      _gen++;
    });
    when(() => messaging.requestPermission()).thenAnswer((_) async {
      requestPermissionCalls++;
      return _authorized();
    });
    when(
      () => messaging.getNotificationSettings(),
    ).thenAnswer((_) async => _authorized());
    when(() => messaging.onTokenRefresh).thenAnswer((_) => refresh.stream);
  }

  final _MockMessaging messaging = _MockMessaging();
  final StreamController<String> refresh = StreamController<String>.broadcast();
  int _gen = 1;
  int deleteTokenCalls = 0;
  int requestPermissionCalls = 0;

  String get token1 => 'fake-fcm-1';
  String get token2 => 'fake-fcm-2';
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(E2eHarnessApp)));

Future<void> _logoutFromClientHub(WidgetTester tester, GoRouter router) async {
  await tester.tap(find.byKey(const Key('btn-menu-client')));
  await tester.pumpAndSettle();
  AppHarness.expectLocation(router, RouteNames.clientMenu);
  await tester.ensureVisible(find.byKey(const Key('row-logout')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('row-logout')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('btn-logout-confirm')));
  await AppHarness.pumpUntilFound(
    tester,
    find.byKey(const ValueKey<String>('login_email')),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('login registers the FCM token; logout DELETEs it and drops the '
      'local token; the NEXT user registers a FRESH token; the permission is '
      'asked exactly once across both logins', (tester) async {
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.client;
    final FakeSecureStorage storage = FakeSecureStorage();
    final _FcmFixture fcm = _FcmFixture();
    addTearDown(fcm.refresh.close);
    final GoRouter router = await AppHarness.boot(
      tester,
      fb,
      storage: storage,
      extraOverrides: <Object>[
        pushAvailableProvider.overrideWith((_) async => true),
        firebaseMessagingProvider.overrideWithValue(fcm.messaging),
      ],
    );
    final ProviderContainer container = _container(tester);
    // Mirrors main.dart's eager `ref.listen(pushRegistrationProvider, ...)`.
    container.listen(pushRegistrationProvider, (_, _) {});
    expect(fb.deviceTokenCalls, isEmpty, reason: 'anonymous: no push calls');
    verifyNever(() => fcm.messaging.getToken());

    // 1) First user logs in -> permission asked once, token POSTed.
    await AppHarness.loginAs(tester, fb, UserRole.client);
    await AppHarness.pumpUntilCondition(
      tester,
      () => fb.registeredDeviceTokens.isNotEmpty,
      description: 'POST /devices/token after the client login',
    );
    AppHarness.expectLocation(router, RouteNames.clientHome);
    expect(fb.deviceTokenCalls, <String>['POST ${fcm.token1} ANDROID']);
    expect(fcm.requestPermissionCalls, 1, reason: 'permission asked once');
    expect(await storage.readPushPermissionAsked(), isTrue);
    expect(
      container.read(pushRegistrationProvider),
      const PushRegistrationState.registered(),
    );

    // 2) Logout -> DELETE the token (before the wipe) + local deleteToken().
    await _logoutFromClientHub(tester, router);
    AppHarness.expectLocation(router, RouteNames.login);
    expect(fb.deviceTokenCalls, <String>[
      'POST ${fcm.token1} ANDROID',
      'DELETE ${fcm.token1}',
    ]);
    expect(fcm.deleteTokenCalls, 1);
    expect(
      await storage.readPushRevokePending(),
      isFalse,
      reason: 'a completed deleteToken() settles the owed-revoke flag',
    );
    expect(
      await storage.readPushPermissionAsked(),
      isTrue,
      reason: 'the asked flag must survive the logout wipe',
    );

    // 3) ANOTHER user on the same device -> fresh token registered, no dialog.
    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
    await AppHarness.pumpUntilCondition(
      tester,
      () => fb.registeredDeviceTokens.length == 2,
      description: 'POST /devices/token after the next user logs in',
    );
    expect(fb.registeredDeviceTokens, <String>[fcm.token1, fcm.token2]);
    expect(fb.unregisteredDeviceTokens, <String>[fcm.token1]);
    expect(fcm.requestPermissionCalls, 1, reason: 'permission asked once');
    expect(
      container.read(pushRegistrationProvider),
      const PushRegistrationState.registered(),
    );
  });
}
