// Phase 068 — E2E: a FOREGROUND FCM message refreshes the bell / the open feed
// (Android push, fake-backed).
//
// What is REAL: the whole Dio -> generated `NotificationsApi` ->
// `HttpNotificationRepository` -> `UnreadNotifications` / `NotificationsFeed`
// stack, the REAL `PushRegistration` (login -> permission -> token POST), the
// REAL `pushMessageListener` (gate + debounce + max-wait + payload parse), the
// real bell glyph and the real feed screen. What is FAKE: `FirebaseMessaging`
// (mocktail), the `firebaseForegroundMessagesProvider` seam (a controller we
// push `RemoteMessage`s into), `pushAvailableProvider` (true — the host has no
// google-services.json) and the socket (`FakeBackend`).
//
// Journeys (CLIENT):
//  1. registered push + bell: a message lands, the 1.5 s debounce holds the
//     refresh back, then the unread count goes 0 -> 1 and the dot appears with
//     NO feed screen alive and no 60 s poll.
//  2. feed open on 20 loaded rows (more pages behind): a message lands, the new
//     row is MERGED into the head (21 rows, the loaded tail kept, scroll offset
//     kept, no skeleton) instead of resetting the list.
//  3. permission-DENIED user: the listener never subscribes to the seam and a
//     message (even after the max-wait) triggers no refresh at all.
//
// `E2eHarnessApp` does not mount `BeauticaApp`, so the test mirrors `main.dart`'s
// eager `ref.listen(pushRegistrationProvider / pushMessageListenerProvider)`.
//
// Real FCM delivery is NOT covered (no Firebase config in CI) — see the
// skip-marked case in `integration_test/patrol/deep_link_patrol_test.dart`.
//
// Runs headless: `flutter test integration_test/push_foreground_refresh_flow_test.dart
// -d flutter-tester`.

import 'dart:async';

import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/push/firebase_messaging_provider.dart';
import 'package:beautica_mobile/core/push/push_available_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/notifications/domain/app_notification.dart';
import 'package:beautica_mobile/features/notifications/domain/push_registration_state.dart';
import 'package:beautica_mobile/features/notifications/presentation/notifications_feed_notifier.dart';
import 'package:beautica_mobile/features/notifications/presentation/notifications_screen.dart';
import 'package:beautica_mobile/features/notifications/presentation/push_message_listener.dart';
import 'package:beautica_mobile/features/notifications/presentation/push_registration_notifier.dart';
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
import 'support/notification_flow_support.dart';

class _MockMessaging extends Mock implements FirebaseMessaging {}

const Key _clientBell = Key('home_hub_bell_button');

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

/// Fake FCM + the foreground-message seam. [seamCalls] counts how many times the
/// app asked for the stream (0 = it never subscribed).
class _PushFixture {
  _PushFixture({required AuthorizationStatus permission}) {
    when(() => messaging.getToken()).thenAnswer((_) async => 'fake-fcm-1');
    when(() => messaging.deleteToken()).thenAnswer((_) async {});
    when(
      () => messaging.requestPermission(),
    ).thenAnswer((_) async => _settings(permission));
    when(
      () => messaging.getNotificationSettings(),
    ).thenAnswer((_) async => _settings(permission));
    when(() => messaging.onTokenRefresh).thenAnswer((_) => refresh.stream);
  }

  final _MockMessaging messaging = _MockMessaging();
  final StreamController<String> refresh = StreamController<String>.broadcast();
  final StreamController<RemoteMessage> onMessage =
      StreamController<RemoteMessage>.broadcast();
  int seamCalls = 0;

  List<Object> get overrides => <Object>[
    pushAvailableProvider.overrideWith((_) async => true),
    firebaseMessagingProvider.overrideWithValue(messaging),
    firebaseForegroundMessagesProvider.overrideWithValue(() {
      seamCalls++;
      return onMessage.stream;
    }),
  ];

  /// A well-formed backend-339 foreground payload for [notificationId].
  void push(String notificationId) => onMessage.add(
    RemoteMessage(
      data: <String, dynamic>{
        'v': '1',
        'notificationId': notificationId,
        'type': 'BOOKING_CREATED',
        'targetKind': 'BOOKING',
        'bookingId': FakeBackend.kNotificationBookingId,
      },
    ),
  );

  Future<void> dispose() async {
    await refresh.close();
    await onMessage.close();
  }
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(E2eHarnessApp)));

/// Boots, mirrors main.dart's eager listens, logs the client in and waits for
/// the push registration to settle into [expected].
Future<(ProviderContainer, GoRouter)> _bootClient(
  WidgetTester tester,
  FakeBackend fb,
  _PushFixture fcm,
  PushRegistrationState expected,
) async {
  addTearDown(fcm.dispose);
  final GoRouter router = await AppHarness.boot(
    tester,
    fb,
    storage: FakeSecureStorage(),
    extraOverrides: fcm.overrides,
  );
  final ProviderContainer container = _container(tester);
  container.listen(pushRegistrationProvider, (_, _) {});
  container.listen(pushMessageListenerProvider, (_, _) {});
  await AppHarness.loginAs(tester, fb, UserRole.client);
  await AppHarness.pumpUntilCondition(
    tester,
    () => container.read(pushRegistrationProvider) == expected,
    description: 'push registration -> $expected',
  );
  await AppHarness.settle(tester);
  return (container, router);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('a foreground push refreshes the bell after the debounce: dot '
      'appears (0 -> 1) with no feed open and no poll', (tester) async {
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.client;
    final _PushFixture fcm = _PushFixture(
      permission: AuthorizationStatus.authorized,
    );
    await _bootClient(
      tester,
      fb,
      fcm,
      const PushRegistrationState.registered(),
    );
    expect(unreadCountOf(tester), 0);
    expect(
      bellAsset(tester, _clientBell),
      BeauticaAssetIcons.notificationPlain,
    );
    expect(fcm.seamCalls, 1, reason: 'registered user -> one subscription');

    final String id = fb.seedNotification(type: 'BOOKING_CREATED');
    final int callsBefore = fb.notificationUnreadCountCalls;
    fcm.push(id);
    // fixed-wait-ok: asserting the 1.5 s push debounce has not yet elapsed, so no fetch before 1 s
    await tester.pump(const Duration(milliseconds: 1000));
    expect(
      fb.notificationUnreadCountCalls,
      callsBefore,
      reason: 'inside the 1.5 s debounce nothing is fetched yet',
    );

    // fixed-wait-ok: advancing past the 1.5 s kPushRefreshDebounce to trigger the deferred fetch
    await tester.pump(const Duration(milliseconds: 600));
    await AppHarness.pumpUntilCondition(
      tester,
      () => unreadCountOf(tester) == 1,
      description: 'unread count 0 -> 1 after the debounced push refresh',
    );
    expect(fb.notificationUnreadCountCalls, greaterThan(callsBefore));
    expect(
      bellAsset(tester, _clientBell),
      BeauticaAssetIcons.notificationUnread,
    );
    expect(fb.notificationFeedCalls, 0, reason: 'no feed provider was created');
  });

  testWidgets('a foreground push with the feed open merges the new row at the '
      'top, keeping the loaded tail and the scroll offset', (tester) async {
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.client;
    for (int i = 0; i < 22; i++) {
      fb.seedNotification(
        type: 'BOOKING_CREATED',
        read: true,
        age: Duration(hours: 2 + i),
      );
    }
    final _PushFixture fcm = _PushFixture(
      permission: AuthorizationStatus.authorized,
    );
    final (ProviderContainer container, GoRouter router) = await _bootClient(
      tester,
      fb,
      fcm,
      const PushRegistrationState.registered(),
    );
    await openFeed(tester, router, _clientBell);
    expect(
      container.read(notificationsFeedProvider).value!.items,
      hasLength(20),
    );
    final ScrollableState scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(NotificationsScreen.listKey),
        matching: find.byType(Scrollable),
      ),
    );
    scrollable.position.jumpTo(300);
    await tester.pump();
    final int feedCallsBefore = fb.notificationFeedCalls;

    final String id = fb.seedNotification(
      type: 'BOOKING_CREATED',
      age: const Duration(minutes: 1),
    );
    fcm.push(id);
    await tester.pump(kPushRefreshDebounce + const Duration(milliseconds: 100));
    await AppHarness.pumpUntilCondition(
      tester,
      () => container.read(notificationsFeedProvider).value!.items.length == 21,
      description: 'the pushed row merged into the head of the loaded list',
    );

    final List<AppNotification> items = container
        .read(notificationsFeedProvider)
        .value!
        .items;
    expect(items.first.id, id, reason: 'newest row sits at the top');
    expect(fb.notificationFeedCalls, feedCallsBefore + 1, reason: 'one GET');
    expect(scrollable.position.pixels, 300, reason: 'scroll offset kept');
    scrollable.position.jumpTo(0);
    await tester.pump();
    expect(notificationTile(id), findsOneWidget);
  });

  testWidgets('a permission-DENIED user never subscribes: a message is ignored '
      'and triggers no refresh', (tester) async {
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.client;
    final _PushFixture fcm = _PushFixture(
      permission: AuthorizationStatus.denied,
    );
    await _bootClient(
      tester,
      fb,
      fcm,
      const PushRegistrationState.permissionDenied(),
    );
    final String id = fb.seedNotification(type: 'BOOKING_CREATED');
    final int callsBefore = fb.notificationUnreadCountCalls;

    fcm.push(id);
    await tester.pump(kPushRefreshMaxWait + const Duration(seconds: 1));

    expect(fcm.seamCalls, 0, reason: 'denied -> the stream is never read');
    expect(fb.notificationUnreadCountCalls, callsBefore);
    expect(fb.notificationFeedCalls, 0);
    expect(unreadCountOf(tester), 0);
    expect(
      bellAsset(tester, _clientBell),
      BeauticaAssetIcons.notificationPlain,
    );
  });
}
