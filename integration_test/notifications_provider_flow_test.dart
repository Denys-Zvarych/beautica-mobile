// Phase 365 — E2E: a notification TAP for every PROVIDER role.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ----------------------------------------
// `notification_tap_to_detail_flow_test.dart` (phase 364) proves the CLIENT
// route, one salon-B owner detail and one «Команда» tap, all on a scripted
// repository. What no flow proves is the per-role `routeFor` table end to end on
// the wire: each provider role taps a `BOOKING_CREATED` item that arrived over
// the REAL Dio stack (`FakeBackend.seedNotification`, no repository override)
// and lands on the right pushed detail with the right capabilities.
//
// Journeys:
//  1. SALON_OWNER, `BOOKING_CREATED` (HTTP) -> the salon staff booking detail,
//     with the provider footer («Скасувати» = decline) offered; Back -> feed.
//  2. SALON_MASTER, `BOOKING_CREATED` (HTTP) -> the read-only staff detail: the
//     SAME booking, but NO transition (decline) is offered.
//  3. INDEPENDENT_MASTER, `BOOKING_CREATED` (HTTP) -> the master booking detail
//     with the provider footer offered.
//  4. SALON_OWNER, `INVITE_ACCEPTED` -> the salon shell on «Команда».
//     SCRIPTED repository, not HTTP: a `SALON_TEAM` target carries a salon id the
//     mapper only accepts as a UUID, and the fake serves a shell for
//     `salon-owner-1` / `salon-xyz` only. The target is the owner's OWN landing
//     salon — the common case (an invite accepted for the salon you are in) that
//     the phase 364 flow, which targets salon B, does not cover.
//
// NEGATIVE PATH (M14): journey 2 asserts the decline control is ABSENT. It is
// paired with journeys 1 and 3, which run the identical seeded booking and DO
// find it, so the absence cannot come from a fixture that never offers it.
//
// KEY POLICY: every tap/find is key- or type-based. Fixtures anchor to
// [kFixedNow], the clock the harness injects (M15).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/notifications/data/notification_repository.dart';
import 'package:beautica_mobile/features/notifications/domain/app_notification.dart';
import 'package:beautica_mobile/features/notifications/presentation/notifications_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/salon_bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';
import 'support/notification_flow_support.dart';

const Key _ownerBell = Key('salon-manage-notifications');
const Key _masterBell = Key('master_profile_bell_button');
const Key _salonMasterBell = Key('salon_master_profile_bell_button');

/// Provider footer controls of a CONFIRMED, not-yet-started booking.
const Key _declineKey = Key('booking-detail-decline');
const Key _rescheduleKey = Key('booking-detail-provider-reschedule');

/// Bottom-nav destination of «Команда» (`SalonBottomNav.ownerAdminItems`).
const int _navTeam = 2;

/// Boots [role] over a fake backend holding ONE unread `BOOKING_CREATED` item
/// for [FakeBackend.kNotificationBookingId], opens the feed from [bell], taps
/// the item, and returns the router with the detail mounted.
Future<({GoRouter router, FakeBackend fb, String id})> _tapBookingItem(
  WidgetTester tester,
  UserRole role,
  Key bell,
) async {
  final fb = FakeBackend()..currentRole = role;
  final String id = fb.seedNotification(
    type: 'BOOKING_CREATED',
    bookingId: FakeBackend.kNotificationBookingId,
  );
  final GoRouter router = await AppHarness.boot(tester, fb);
  await AppHarness.loginAs(tester, fb, role);
  await AppHarness.settle(tester);
  expect(unreadCountOf(tester), 1, reason: 'the poll counted the seeded item');

  await openFeed(tester, router, bell);
  await tester.tap(notificationTile(id));
  await AppHarness.settle(tester);

  expect(find.byType(BookingDetailScreen), findsOneWidget);
  expect(fb.notificationMarkedReadIds, <String>[id]);
  expect(unreadCountOf(tester), 0);
  return (router: router, fb: fb, id: id);
}

Future<void> _backToFeed(WidgetTester tester, GoRouter router) async {
  await tapBookingDetailBack(tester);
  AppHarness.expectLocation(router, RouteNames.notifications);
  expect(find.byType(BookingDetailScreen), findsNothing);
  expect(find.byType(NotificationsScreen), findsOneWidget);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'SALON_OWNER taps a BOOKING_CREATED item: the salon staff booking '
    'detail opens with the provider footer, and Back returns to the feed',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final r = await _tapBookingItem(
          tester,
          UserRole.salonOwner,
          _ownerBell,
        );

        AppHarness.expectLocation(
          r.router,
          RouteNames.salonStaffBookingDetail(
            FakeBackend.kNotificationBookingId,
          ),
        );
        expect(find.byKey(_declineKey), findsOneWidget);
        expect(find.byKey(_rescheduleKey), findsOneWidget);

        await _backToFeed(tester, r.router);
      });
    },
  );

  testWidgets('SALON_MASTER taps a BOOKING_CREATED item: the read-only staff '
      'detail opens with NO transition offered, and Back returns to the feed', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      final r = await _tapBookingItem(
        tester,
        UserRole.salonMaster,
        _salonMasterBell,
      );

      AppHarness.expectLocation(
        r.router,
        RouteNames.salonMasterBookingDetail(FakeBackend.kNotificationBookingId),
      );
      expect(
        find.byKey(_declineKey),
        findsNothing,
        reason: 'a SALON_MASTER is read-only for transitions',
      );
      expect(find.byKey(_rescheduleKey), findsNothing);

      await _backToFeed(tester, r.router);
    });
  });

  testWidgets('INDEPENDENT_MASTER taps a BOOKING_CREATED item: the master '
      'booking detail opens with the provider footer, and Back returns to the '
      'feed', (tester) async {
    await mockNetworkImagesFor(() async {
      final r = await _tapBookingItem(
        tester,
        UserRole.independentMaster,
        _masterBell,
      );

      AppHarness.expectLocation(
        r.router,
        RouteNames.masterBookingDetail(FakeBackend.kNotificationBookingId),
      );
      expect(find.byKey(_declineKey), findsOneWidget);
      expect(find.byKey(_rescheduleKey), findsOneWidget);

      await _backToFeed(tester, r.router);
    });
  });

  testWidgets('SALON_OWNER taps an INVITE_ACCEPTED item for the salon they are '
      'in: the salon shell opens on «Команда» and the item is read', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      final ScriptedNotificationRepository repo =
          ScriptedNotificationRepository(<AppNotification>[
            AppNotification(
              id: 'invite-1',
              type: AppNotificationType.inviteAccepted,
              createdAt: kFixedNow.subtract(const Duration(hours: 1)),
              read: false,
              target: const NotificationTarget.salonTeam(
                salonId: FakeBackend.kOwnerSalonId,
              ),
              params: const NotificationParams(
                subjectName: 'Master One',
                subjectRole: 'SALON_MASTER',
              ),
            ),
          ]);
      final fb = FakeBackend()..currentRole = UserRole.salonOwner;
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        extraOverrides: <Object>[
          notificationRepositoryProvider.overrideWithValue(repo),
        ],
      );
      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.settle(tester);
      await openFeed(tester, router, _ownerBell);

      await tester.tap(notificationTile('invite-1'));
      await AppHarness.settle(tester);

      AppHarness.expectLocation(
        router,
        RouteNames.salonShell(FakeBackend.kOwnerSalonId),
      );
      expect(find.byType(SalonShellScreen), findsOneWidget);
      expect(
        tester
            .widget<SalonBottomNav>(
              find.byKey(const Key('salon-shell-bottom-nav')),
            )
            .currentIndex,
        _navTeam,
        reason: 'the shell opened on «Команда»',
      );
      expect(repo.markedRead, <String>['invite-1']);
      expect(unreadCountOf(tester), 0);
    });
  });
}
