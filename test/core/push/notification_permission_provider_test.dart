// «Сповіщення» switch — the permission reader maps the OS state, never prompts,
// and short-circuits to `unavailable` when push is unavailable.

import 'package:beautica_mobile/core/push/firebase_messaging_provider.dart';
import 'package:beautica_mobile/core/push/notification_permission_provider.dart';
import 'package:beautica_mobile/core/push/push_available_provider.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockMessaging extends Mock implements FirebaseMessaging {}

NotificationSettings _settings(AuthorizationStatus status) =>
    NotificationSettings(
      alert: AppleNotificationSetting.notSupported,
      announcement: AppleNotificationSetting.notSupported,
      authorizationStatus: status,
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

ProviderContainer _container(
  _MockMessaging messaging, {
  bool available = true,
}) {
  final ProviderContainer c = ProviderContainer(
    overrides: [
      firebaseInitializerProvider.overrideWithValue(() async => available),
      firebaseMessagingProvider.overrideWithValue(messaging),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  const Map<AuthorizationStatus, NotificationPermissionStatus> expected =
      <AuthorizationStatus, NotificationPermissionStatus>{
        AuthorizationStatus.authorized: NotificationPermissionStatus.granted,
        AuthorizationStatus.provisional: NotificationPermissionStatus.granted,
        AuthorizationStatus.denied: NotificationPermissionStatus.denied,
        AuthorizationStatus.deniedPermanently:
            NotificationPermissionStatus.denied,
        AuthorizationStatus.notDetermined:
            NotificationPermissionStatus.notDetermined,
      };

  for (final MapEntry<AuthorizationStatus, NotificationPermissionStatus> e
      in expected.entries) {
    test('maps ${e.key.name} → ${e.value.name}, never prompts', () async {
      final _MockMessaging messaging = _MockMessaging();
      when(
        () => messaging.getNotificationSettings(),
      ).thenAnswer((_) async => _settings(e.key));
      final ProviderContainer c = _container(messaging);

      expect(await c.read(notificationPermissionReaderProvider)(), e.value);
      verifyNever(() => messaging.requestPermission());
    });
  }

  test('push unavailable → unavailable, Firebase never touched', () async {
    final _MockMessaging messaging = _MockMessaging();
    final ProviderContainer c = _container(messaging, available: false);

    expect(
      await c.read(notificationPermissionReaderProvider)(),
      NotificationPermissionStatus.unavailable,
    );
    verifyZeroInteractions(messaging);
  });

  test('a failing read never throws (reads as notDetermined)', () async {
    final _MockMessaging messaging = _MockMessaging();
    when(() => messaging.getNotificationSettings()).thenThrow(StateError('x'));
    final ProviderContainer c = _container(messaging);

    expect(
      await c.read(notificationPermissionReaderProvider)(),
      NotificationPermissionStatus.notDetermined,
    );
  });
}
