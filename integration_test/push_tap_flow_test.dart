// Phase 069 — E2E: tapping a push opens its destination (Android push,
// fake-backed).
//
// What is REAL: the Dio -> generated `NotificationsApi` ->
// `HttpNotificationRepository` stack, the REAL `PendingPushTap` +
// `pushTapDispatcher` (mounted from the first frame via
// `AppHarness.boot(mountPushTapDispatcher: true)`), the real router, the real
// `routeFor` / `openNotificationTarget`, the real bell. What is FAKE:
// `FirebaseMessaging` (mocktail: `getInitialMessage`), the
// `firebaseOpenedAppMessagesProvider` seam (a controller we push taps into),
// `pushAvailableProvider` (true — the host has no google-services.json) and
// the socket (`FakeBackend`).
//
// Journeys (CLIENT):
//  1. background tap: BOOKING push -> the booking detail opens, the PATCH
//     `/notifications/{id}/read` lands on the fake backend, the bell count
//     drops 1 -> 0 (and the dot is gone once back on home).
//  2. cold-start tap: `getInitialMessage` carries a push, the app boots with a
//     stored session -> home, then the destination on top of it.
//  3. cold start signed out with a launch tap -> sign in: NO navigation to the
//     tapped target, nothing marked read.
//  4. NoTarget push -> the notifications feed.
//
// Real tray delivery is NOT covered (no Firebase config in CI) — see the
// skip-marked case in `integration_test/patrol/deep_link_patrol_test.dart`.
//
// Runs headless: `flutter test integration_test/push_tap_flow_test.dart
// -d flutter-tester`.

import 'dart:async';

import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/push/firebase_messaging_provider.dart';
import 'package:beautica_mobile/core/push/push_available_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/notifications/presentation/notifications_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test/helpers/fakes/fake_secure_storage.dart';
import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';
import 'support/notification_flow_support.dart';

class _MockMessaging extends Mock implements FirebaseMessaging {}

const Key _clientBell = Key('home_hub_bell_button');

/// Fake FCM: a controller for `onMessageOpenedApp` and a scripted
/// `getInitialMessage`. [openedSubscriptions] counts how often the app asked
/// for the stream (so a flow can wait until the listener is attached).
class _TapFixture {
  _TapFixture({RemoteMessage? launchMessage}) {
    when(
      () => messaging.getInitialMessage(),
    ).thenAnswer((_) async => launchMessage);
  }

  final _MockMessaging messaging = _MockMessaging();
  final StreamController<RemoteMessage> opened =
      StreamController<RemoteMessage>.broadcast();
  int openedSubscriptions = 0;

  List<Object> get overrides => <Object>[
    pushAvailableProvider.overrideWith((_) async => true),
    firebaseMessagingProvider.overrideWithValue(messaging),
    firebaseOpenedAppMessagesProvider.overrideWithValue(() {
      openedSubscriptions++;
      return opened.stream;
    }),
  ];

  Future<void> dispose() => opened.close();
}

/// A well-formed backend-339 push payload tapped from the tray.
RemoteMessage _bookingPush(String notificationId) => RemoteMessage(
  data: <String, dynamic>{
    'v': '1',
    'notificationId': notificationId,
    'type': 'BOOKING_CREATED',
    'targetKind': 'BOOKING',
    'bookingId': FakeBackend.kNotificationBookingId,
  },
);

RemoteMessage _nonePush(String notificationId) => RemoteMessage(
  data: <String, dynamic>{
    'v': '1',
    'notificationId': notificationId,
    'type': 'BOOKING_CREATED',
    'targetKind': 'NONE',
  },
);

Future<GoRouter> _bootSignedInClient(
  WidgetTester tester,
  FakeBackend fb,
  _TapFixture fcm,
) async {
  addTearDown(fcm.dispose);
  final GoRouter router = await AppHarness.boot(
    tester,
    fb,
    storage: FakeSecureStorage(),
    extraOverrides: fcm.overrides,
    mountPushTapDispatcher: true,
  );
  await AppHarness.loginAs(tester, fb, UserRole.client);
  await AppHarness.pumpUntilCondition(
    tester,
    () => fcm.openedSubscriptions > 0,
    description: 'the push-tap listener attached after login',
  );
  await AppHarness.settle(tester);
  return router;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('a background push tap opens the booking detail, marks the '
      'notification read on the backend and drops the bell', (tester) async {
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.client;
    final String id = fb.seedNotification(
      type: 'BOOKING_CREATED',
      bookingId: FakeBackend.kNotificationBookingId,
    );
    final _TapFixture fcm = _TapFixture();
    await _bootSignedInClient(tester, fb, fcm);
    await AppHarness.pumpUntilCondition(
      tester,
      () => unreadCountOf(tester) == 1,
      description: 'the bell shows the one unread notification',
    );
    expect(
      bellAsset(tester, _clientBell),
      BeauticaAssetIcons.notificationUnread,
    );

    fcm.opened.add(_bookingPush(id));
    await AppHarness.pumpUntilFound(tester, find.byType(BookingDetailScreen));

    await AppHarness.pumpUntilCondition(
      tester,
      () => fb.notificationMarkedReadIds.contains(id),
      description: 'PATCH /notifications/{id}/read reached the backend',
    );
    expect(fb.notificationMarkedReadIds, <String>[id]);
    await AppHarness.pumpUntilCondition(
      tester,
      () => unreadCountOf(tester) == 0,
      description: 'the unread count dropped 1 -> 0',
    );
    await tapBookingDetailBack(tester);
    expect(find.byType(BookingDetailScreen), findsNothing);
    expect(
      bellAsset(tester, _clientBell),
      BeauticaAssetIcons.notificationPlain,
    );
  });

  testWidgets('a NoTarget push tap lands on the notifications feed and marks '
      'the notification read', (tester) async {
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.client;
    final String id = fb.seedNotification(type: 'BOOKING_CREATED');
    final _TapFixture fcm = _TapFixture();
    final GoRouter router = await _bootSignedInClient(tester, fb, fcm);

    fcm.opened.add(_nonePush(id));
    await AppHarness.pumpUntilFound(tester, find.byType(NotificationsScreen));

    AppHarness.expectLocation(router, RouteNames.notifications);
    expect(find.byType(BookingDetailScreen), findsNothing);
    await AppHarness.pumpUntilCondition(
      tester,
      () => fb.notificationMarkedReadIds.contains(id),
      description: 'the NoTarget notification is marked read too',
    );
  });

  testWidgets('a COLD-START push tap with a stored session lands on the '
      'destination after home', (tester) async {
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.client;
    final String id = fb.seedNotification(
      type: 'BOOKING_CREATED',
      bookingId: FakeBackend.kNotificationBookingId,
    );
    final FakeSecureStorage storage = FakeSecureStorage();
    await storage.writeRefreshToken('fake-refresh-token');
    final _TapFixture fcm = _TapFixture(launchMessage: _bookingPush(id));
    addTearDown(fcm.dispose);

    await AppHarness.boot(
      tester,
      fb,
      storage: storage,
      extraOverrides: fcm.overrides,
      mountPushTapDispatcher: true,
    );
    await AppHarness.pumpUntilFound(tester, find.byType(BookingDetailScreen));

    await AppHarness.pumpUntilCondition(
      tester,
      () => fb.notificationMarkedReadIds.contains(id),
      description: 'the launch notification was marked read',
    );
    verify(() => fcm.messaging.getInitialMessage()).called(1);
    // Home sits underneath the destination.
    await tapBookingDetailBack(tester);
    expect(find.byKey(_clientBell), findsOneWidget);
  });

  testWidgets('a cold start SIGNED OUT with a launch tap: signing in does NOT '
      'navigate to the old target', (tester) async {
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.client;
    final String id = fb.seedNotification(
      type: 'BOOKING_CREATED',
      bookingId: FakeBackend.kNotificationBookingId,
    );
    final _TapFixture fcm = _TapFixture(launchMessage: _bookingPush(id));
    addTearDown(fcm.dispose);
    await AppHarness.boot(
      tester,
      fb,
      storage: FakeSecureStorage(),
      extraOverrides: fcm.overrides,
      mountPushTapDispatcher: true,
    );

    await AppHarness.loginAs(tester, fb, UserRole.client);
    await AppHarness.settle(tester);

    expect(find.byKey(_clientBell), findsOneWidget, reason: 'plain home');
    expect(find.byType(BookingDetailScreen), findsNothing);
    expect(fb.notificationMarkedReadIds, isEmpty);
  });
}
