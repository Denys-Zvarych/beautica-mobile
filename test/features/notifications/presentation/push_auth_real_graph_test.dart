// Phase 067 — REAL provider graph: real `authProvider` + real
// `PushRegistration` (no auth stub). Guards the debug-only
// `CircularDependencyError` (Ref._debugAssertCanDependOn) that an
// `AuthNotifier -> ref.read(pushRegistrationProvider)` edge raises because
// `PushRegistration` watches `authProvider`. Stubbing auth (as
// push_registration_notifier_test does) hides that class of bug.

import 'dart:async';

import 'package:beautica_mobile/core/push/firebase_messaging_provider.dart';
import 'package:beautica_mobile/core/push/push_available_provider.dart';
import 'package:beautica_mobile/core/push/push_session_hooks.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/notifications/data/device_token_repository.dart';
import 'package:beautica_mobile/features/notifications/presentation/push_registration_notifier.dart';
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fakes/fake_secure_storage.dart';

class _MockAuthRepo extends Mock implements AuthRepository {}

class _MockMessaging extends Mock implements FirebaseMessaging {}

class _Repo implements DeviceTokenRepository {
  final List<String> unregistered = <String>[];

  @override
  Future<void> register(String token, {CancelToken? cancelToken}) async {}

  @override
  Future<void> unregister(String token) async => unregistered.add(token);
}

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

const User _user = User(id: 'u1', email: 'u1@e.com', role: UserRole.client);
const AuthTokens _tokens = AuthTokens(accessToken: 'at', refreshToken: 'rt');

void main() {
  late _MockAuthRepo repo;
  late _MockMessaging messaging;
  late _Repo devices;
  late FakeSecureStorage storage;
  late int deleteTokenCalls;

  ProviderContainer build() {
    final c = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWith((_) => repo),
        secureStorageProvider.overrideWith((_) => storage),
        pushAvailableProvider.overrideWith((_) async => true),
        firebaseMessagingProvider.overrideWithValue(messaging),
        deviceTokenRepositoryProvider.overrideWith((_) => devices),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() async {
    repo = _MockAuthRepo();
    messaging = _MockMessaging();
    devices = _Repo();
    storage = FakeSecureStorage();
    deleteTokenCalls = 0;
    await storage.writeRefreshToken('stored-refresh');
    when(() => repo.refresh('stored-refresh')).thenAnswer((_) async => _tokens);
    when(() => repo.me()).thenAnswer((_) async => _user);
    when(() => repo.logout()).thenAnswer((_) async {});
    when(() => messaging.getToken()).thenAnswer((_) async => 'tok-1');
    when(() => messaging.deleteToken()).thenAnswer((_) async {
      deleteTokenCalls++;
    });
    when(
      () => messaging.getNotificationSettings(),
    ).thenAnswer((_) async => _authorized());
    when(
      () => messaging.requestPermission(),
    ).thenAnswer((_) async => _authorized());
    when(
      () => messaging.onTokenRefresh,
    ).thenAnswer((_) => const Stream<String>.empty());
  });

  test('logout with REAL auth + REAL PushRegistration: DELETE + deleteToken, '
      'no CircularDependencyError', () async {
    final c = build();
    c.listen(pushRegistrationProvider, (_, _) {}); // main.dart's eager listen
    await c.read(authProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.read(pushSessionHooksProvider).onLogout, isNotNull);

    await c.read(authProvider.notifier).logout();

    expect(devices.unregistered, <String>['tok-1']);
    expect(deleteTokenCalls, 1);
    expect(await storage.readRefreshToken(), isNull);
  });

  test('forced logout with the real graph skips the DELETE but still '
      'deleteToken()s', () async {
    final c = build();
    c.listen(pushRegistrationProvider, (_, _) {});
    await c.read(authProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await c.read(authProvider.notifier).logoutForced();

    expect(devices.unregistered, isEmpty);
    expect(deleteTokenCalls, 1);
  });

  test('push never built: logout persists the revoke-pending flag itself '
      '(before the wipe) so the next start settles it', () async {
    final c = build(); // pushRegistrationProvider deliberately NOT read
    await c.read(authProvider.future);
    expect(c.read(pushSessionHooksProvider).onLogout, isNull);

    await c.read(authProvider.notifier).logout();

    expect(devices.unregistered, isEmpty);
    expect(await storage.readPushRevokePending(), isTrue);
    expect(await storage.readRefreshToken(), isNull);
  });
}
