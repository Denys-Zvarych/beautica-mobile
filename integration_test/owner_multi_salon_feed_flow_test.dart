// Phase 365 — E2E: ONE owner, TWO salons, ONE global notification feed.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ----------------------------------------
// The feed is per USER, not per salon: locked in phases 359/360 (no `salonId`
// family arg, no salon provider watched by the unread count). That claim is only
// real if it survives the REAL router moving the owner between salon shells. The
// widget tier cannot prove it; this flow walks the five spec steps:
//
//  1. salon A's shell (the landing): the bell has its dot and the count is 2;
//  2. switch to salon B through «Мої салони»: the count is STILL 2 (no refetch /
//     reset on a salon switch) and B's bell shows the dot;
//  3. switch back to A, open the feed: BOTH items show, each with its salon
//     label;
//  4. tap the salon-B item: salon B's booking detail opens (`/salon/bookings/:id`,
//     NOT a move into B's shell);
//  5. Back, Back: the count is 1 and the owner is on salon A's shell — salon A is
//     still the active salon, reading a salon-B item never moved them.
//
// SCRIPTED repository (`ScriptedNotificationRepository`), not the HTTP fake: the
// salon-B target must carry `salon-xyz`, the only second salon the fake serves a
// shell for, and the mapper drops any non-UUID id on the wire path. The REAL
// `UnreadNotifications`, feed notifier, router and shells are all exercised.
//
// KEY POLICY: every tap/find is key- or type-based; salon names are Latin so no
// Cyrillic finder is needed. Fixtures anchor to [kFixedNow] (M15).

import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/notifications/data/notification_repository.dart';
import 'package:beautica_mobile/features/notifications/domain/app_notification.dart';
import 'package:beautica_mobile/features/notifications/presentation/notifications_screen.dart';
import 'package:beautica_mobile/features/notifications/presentation/widgets/notification_tile.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';
import 'support/notification_flow_support.dart';

/// The fake backend's seeded booking — the only detail it serves.
const String _kBookingId = 'booking-1';

/// Salon B: the owner's SECOND (non-primary) salon. Salon A is the landing
/// shell (`FakeBackend.kOwnerSalonId`).
const String _kSalonB = 'salon-xyz';

const Key _coverBell = Key('salon-manage-notifications');

void _seedSalonB(FakeBackend fb) {
  fb.mySalons.add(<String, dynamic>{
    'id': _kSalonB,
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
}

AppNotification _item(
  String id, {
  required Duration age,
  required String salonId,
  required String salonName,
}) => AppNotification(
  id: id,
  type: AppNotificationType.bookingCreated,
  createdAt: kFixedNow.subtract(age),
  read: false,
  target: NotificationTarget.booking(bookingId: _kBookingId, salonId: salonId),
  params: NotificationParams(
    counterpartName: 'Client $id',
    serviceName: 'Service $id',
    startsAt: kFixedNow.add(const Duration(days: 1)),
    salonName: salonName,
  ),
);

/// «Мої салони» -> the card of [salonId]: the owner's salon switch.
Future<void> _switchToSalon(
  WidgetTester tester,
  GoRouter router,
  String salonId,
) async {
  router.go(RouteNames.mySalons);
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.mySalons);
  await tester.tap(find.byKey(ValueKey<String>('my_salons_card_$salonId')));
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.salonShell(salonId));
  expect(find.byType(SalonShellScreen), findsOneWidget);
}

String _label(WidgetTester tester, String id) => tester
    .widget<SalonLabel>(
      find.descendant(
        of: notificationTile(id),
        matching: find.byType(SalonLabel),
      ),
    )
    .name;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('owner with salons A and B: the count is global across a salon '
      'switch, the feed labels both salons, a salon-B tap opens B\'s detail '
      'and salon A stays active', (tester) async {
    await mockNetworkImagesFor(() async {
      final ScriptedNotificationRepository repo =
          ScriptedNotificationRepository(<AppNotification>[
            _item(
              'item-a',
              age: const Duration(hours: 1),
              salonId: FakeBackend.kOwnerSalonId,
              salonName: 'Lotus Studio',
            ),
            _item(
              'item-b',
              age: const Duration(hours: 2),
              salonId: _kSalonB,
              salonName: 'Orchid Studio',
            ),
          ]);
      final fb = FakeBackend()..currentRole = UserRole.salonOwner;
      _seedSalonB(fb);
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        extraOverrides: <Object>[
          notificationRepositoryProvider.overrideWithValue(repo),
        ],
      );
      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.settle(tester);

      // 1. Salon A's shell: dot, count 2.
      final String salonAShell = RouteNames.salonShell(
        FakeBackend.kOwnerSalonId,
      );
      AppHarness.expectLocation(router, salonAShell);
      expect(unreadCountOf(tester), 2);
      expect(
        coverBellAsset(tester, _coverBell),
        BeauticaAssetIcons.notificationUnread,
      );

      // 2. Switch to salon B: still 2, B's bell has the dot too.
      await _switchToSalon(tester, router, _kSalonB);
      expect(unreadCountOf(tester), 2, reason: 'a salon switch must not reset');
      expect(
        coverBellAsset(tester, _coverBell),
        BeauticaAssetIcons.notificationUnread,
      );

      // 3. Back to A, open the feed: both items, each with its salon label.
      await _switchToSalon(tester, router, FakeBackend.kOwnerSalonId);
      await openFeed(tester, router, _coverBell);
      expect(notificationTile('item-a'), findsOneWidget);
      expect(notificationTile('item-b'), findsOneWidget);
      expect(_label(tester, 'item-a'), contains('Lotus Studio'));
      expect(_label(tester, 'item-b'), contains('Orchid Studio'));

      // 4. Tap the salon-B item: B's booking detail, not B's shell.
      await tester.tap(notificationTile('item-b'));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(
        router,
        RouteNames.salonStaffBookingDetail(_kBookingId),
      );
      expect(find.byType(BookingDetailScreen), findsOneWidget);
      expect(repo.markedRead, <String>['item-b']);

      // 5. Back, Back: count 1, salon A still the active shell.
      await tapBookingDetailBack(tester);
      AppHarness.expectLocation(router, RouteNames.notifications);
      expect(unreadCountOf(tester), 1);

      await tester.tap(find.byKey(NotificationsScreen.backKey));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, salonAShell);
      expect(find.byType(SalonShellScreen), findsOneWidget);
      expect(unreadCountOf(tester), 1);
      expect(
        coverBellAsset(tester, _coverBell),
        BeauticaAssetIcons.notificationUnread,
        reason: 'item-a (salon A) is still unread',
      );
    });
  });
}
