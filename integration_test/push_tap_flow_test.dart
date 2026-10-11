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

import 'package:beautica_mobile/features/notifications/presentation/notification_navigation.dart';
import 'dart:async';

import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/push/firebase_messaging_provider.dart';
import 'package:beautica_mobile/core/push/push_available_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/notifications/presentation/notifications_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/profile_tab_bar.dart';
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

/// Phase 391 — a push of [type] (default `REVIEW_RECEIVED`) for a booking of
/// [salonId].
RemoteMessage _reviewPush(
  String notificationId,
  String salonId, {
  String type = 'REVIEW_RECEIVED',
}) => RemoteMessage(
  data: <String, dynamic>{
    'v': '1',
    'notificationId': notificationId,
    'type': type,
    'targetKind': 'BOOKING',
    'bookingId': FakeBackend.kNotificationBookingId,
    'salonId': salonId,
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
  tearDown(() {
    resetNotificationNavigationStateForTest();
    AppHarness.tearDownHarness();
  });

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

  testWidgets('a REVIEW_RECEIVED push tap for the SALON_OWNER opens the '
      'booking salon shell on «Відгуки», not the booking detail', (
    tester,
  ) async {
    // The mapper drops non-UUID ids, so the salon is a UUID-shaped extra salon
    // the owner holds (the guard admits it via `mySalons`).
    const String salonUuid = '5a1f0000-0000-4000-8000-0000000000b2';
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.salonOwner;
    fb.mySalons.add(<String, dynamic>{
      'id': salonUuid,
      'ownerId': 'user-owner-1',
      'name': 'Студія Краси «Камелія»',
      'city': 'Київ',
      'cityId': 'city-kyiv',
      'oblastId': 'oblast-kyiv',
      'street': 'вул. Хрещатик',
      'buildingNo': '12',
      'isActive': true,
      'isPrimary': false,
    });
    final String id = fb.seedNotification(
      type: 'REVIEW_RECEIVED',
      bookingId: FakeBackend.kNotificationBookingId,
      salonId: salonUuid,
    );
    final _TapFixture fcm = _TapFixture();
    addTearDown(fcm.dispose);
    final GoRouter router = await AppHarness.boot(
      tester,
      fb,
      storage: FakeSecureStorage(),
      extraOverrides: fcm.overrides,
      mountPushTapDispatcher: true,
    );
    await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
    await AppHarness.pumpUntilCondition(
      tester,
      () => fcm.openedSubscriptions > 0,
      description: 'the push-tap listener attached after login',
    );
    await AppHarness.settle(tester);

    fcm.opened.add(_reviewPush(id, salonUuid));
    await AppHarness.pumpUntilCondition(
      tester,
      () =>
          AppHarness.location(router) == '/salons/$salonUuid/shell?tab=reviews',
      description: 'the salon shell opened on «Відгуки»',
    );
    await AppHarness.settle(tester);

    expect(find.byType(BookingDetailScreen), findsNothing);
    // The UUID-shaped extra salon has no served detail, so the sub-tab row
    // never renders here (the salon-tab-3 selected state is asserted in
    // `notification_tap_to_detail_flow_test.dart`, where the fake serves the
    // salon in full): assert the shell is the reviews landing instead.
    expect(
      tester
          .widget<SalonShellScreen>(find.byType(SalonShellScreen).last)
          .openReviewsTab,
      isTrue,
    );
    await AppHarness.pumpUntilCondition(
      tester,
      () => fb.notificationMarkedReadIds.contains(id),
      description: 'the review notification was marked read',
    );
  });

  testWidgets('a REVIEW_RECEIVED push tap for a SALON_OWNER with a salon id '
      'NOT in mySalons lands on the booking detail, never the salon shell', (
    tester,
  ) async {
    // Phase 391 audit L1: the owner's list resolves WITHOUT this salon, so the
    // tap must not enter the unverified salon shell.
    const String foreignSalon = '5a1f0000-0000-4000-8000-0000000000f1';
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.salonOwner;
    fb.mySalons.add(<String, dynamic>{
      'id': '5a1f0000-0000-4000-8000-0000000000a1',
      'ownerId': 'user-owner-1',
      'name': 'Студія Краси «Камелія»',
      'city': 'Київ',
      'cityId': 'city-kyiv',
      'oblastId': 'oblast-kyiv',
      'street': 'вул. Хрещатик',
      'buildingNo': '12',
      'isActive': true,
      'isPrimary': true,
    });
    final String id = fb.seedNotification(
      type: 'REVIEW_RECEIVED',
      bookingId: FakeBackend.kNotificationBookingId,
      salonId: foreignSalon,
    );
    final _TapFixture fcm = _TapFixture();
    addTearDown(fcm.dispose);
    final GoRouter router = await AppHarness.boot(
      tester,
      fb,
      storage: FakeSecureStorage(),
      extraOverrides: fcm.overrides,
      mountPushTapDispatcher: true,
    );
    await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
    await AppHarness.pumpUntilCondition(
      tester,
      () => fcm.openedSubscriptions > 0,
      description: 'the push-tap listener attached after login',
    );
    await AppHarness.settle(tester);

    fcm.opened.add(_reviewPush(id, foreignSalon));
    await AppHarness.pumpUntilFound(tester, find.byType(BookingDetailScreen));
    await AppHarness.settle(tester);

    expect(
      AppHarness.location(router),
      startsWith(
        RouteNames.salonStaffBookingDetail(FakeBackend.kNotificationBookingId),
      ),
    );
    expect(find.byType(SalonShellScreen), findsNothing);
    expect(AppHarness.location(router), isNot(contains('/shell')));
    await AppHarness.pumpUntilCondition(
      tester,
      () => fb.notificationMarkedReadIds.contains(id),
      description: 'the review notification was marked read',
    );
  });

  testWidgets('a REVIEW_RECEIVED push tap for a SALON_MASTER opens the staff '
      'booking detail, never the salon shell', (tester) async {
    const String salonUuid = '5a1f0000-0000-4000-8000-0000000000b3';
    final FakeBackend fb = FakeBackend(
      masterRowId: 'master-removable',
      masterSalonId: salonUuid,
    );
    final String id = fb.seedNotification(
      type: 'REVIEW_RECEIVED',
      bookingId: FakeBackend.kNotificationBookingId,
      salonId: salonUuid,
    );
    final _TapFixture fcm = _TapFixture();
    addTearDown(fcm.dispose);
    final GoRouter router = await AppHarness.boot(
      tester,
      fb,
      storage: FakeSecureStorage(),
      extraOverrides: fcm.overrides,
      mountPushTapDispatcher: true,
    );
    await AppHarness.loginAs(tester, fb, UserRole.salonMaster);
    await AppHarness.pumpUntilCondition(
      tester,
      () => fcm.openedSubscriptions > 0,
      description: 'the push-tap listener attached after login',
    );
    await AppHarness.settle(tester);

    fcm.opened.add(_reviewPush(id, salonUuid));
    await AppHarness.pumpUntilFound(tester, find.byType(BookingDetailScreen));
    await AppHarness.settle(tester);

    expect(
      AppHarness.location(router),
      startsWith(
        RouteNames.salonMasterBookingDetail(FakeBackend.kNotificationBookingId),
      ),
    );
    expect(find.byType(SalonShellScreen), findsNothing);
    expect(find.byType(ProfileTabBar), findsNothing);
  });

  testWidgets('a BOOKING_CREATED push tap (with a salonId) for the SALON_OWNER '
      'opens the staff booking detail, not the «Відгуки» tab', (tester) async {
    const String salonUuid = '5a1f0000-0000-4000-8000-0000000000b4';
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.salonOwner;
    fb.mySalons.add(<String, dynamic>{
      'id': salonUuid,
      'ownerId': 'user-owner-1',
      'name': 'Студія Краси «Камелія»',
      'city': 'Київ',
      'cityId': 'city-kyiv',
      'oblastId': 'oblast-kyiv',
      'street': 'вул. Хрещатик',
      'buildingNo': '12',
      'isActive': true,
      'isPrimary': false,
    });
    final String id = fb.seedNotification(
      type: 'BOOKING_CREATED',
      bookingId: FakeBackend.kNotificationBookingId,
      salonId: salonUuid,
    );
    final _TapFixture fcm = _TapFixture();
    addTearDown(fcm.dispose);
    final GoRouter router = await AppHarness.boot(
      tester,
      fb,
      storage: FakeSecureStorage(),
      extraOverrides: fcm.overrides,
      mountPushTapDispatcher: true,
    );
    await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
    await AppHarness.pumpUntilCondition(
      tester,
      () => fcm.openedSubscriptions > 0,
      description: 'the push-tap listener attached after login',
    );
    await AppHarness.settle(tester);

    fcm.opened.add(_reviewPush(id, salonUuid, type: 'BOOKING_CREATED'));
    await AppHarness.pumpUntilFound(tester, find.byType(BookingDetailScreen));
    await AppHarness.settle(tester);

    expect(
      AppHarness.location(router),
      startsWith(
        RouteNames.salonStaffBookingDetail(FakeBackend.kNotificationBookingId),
      ),
    );
    expect(AppHarness.location(router), isNot(contains('tab=reviews')));
    expect(
      find.byKey(const Key('salon-manage-tab-body-reviews')),
      findsNothing,
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
