// Phase 365 — E2E: the notification feed over the REAL HTTP path.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ----------------------------------------
// The phase 361/363/364 flows override `notificationRepositoryProvider` with a
// scripted fake. That proves the screens and the router, but NOT the wire: the
// generated `NotificationsApi`, the mapper's DTO -> domain rules, the real Dio
// stack and the stateful unread count behind it. This file overrides NOTHING —
// `FakeBackend` now serves `/api/v1/notifications` (+ `/unread-count`,
// `/{id}/read`, `/read-all`) statefully (this phase), and the app runs its real
// `HttpNotificationRepository` against it.
//
// Journeys (CLIENT):
//  1. poll answers 1 -> the bell shows the dot -> open the feed -> tap a
//     `BOOKING_DECLINED` item -> `BookingDetailScreen` is the page TYPE on the
//     feed-scoped alias -> back, back -> Головна: the dot is gone, and the
//     SERVER agrees (0 unread, one PATCH for that id).
//  2. ✓ on one of three rows (server 3 -> 2, dot stays), then «Позначити всі»
//     (server 0, `upTo` sent, bar gone) -> back: no dot.
//  3. the app is backgrounded, a notification lands server-side, and a RESUME
//     past the min-gap re-reads the count (1 -> 2) with no feed interaction.
//
// KEY POLICY: every tap/find is key- or type-based. Fixtures anchor to
// [kFixedNow], the clock the harness injects; journey 3 injects a MOVABLE clock
// that starts at [kFixedNow], so the fixture clock and the app clock stay the
// same clock (M15).

import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/notifications/presentation/notifications_screen.dart';
import 'package:beautica_mobile/features/notifications/presentation/unread_notifications_notifier.dart';
import 'package:beautica_mobile/features/notifications/presentation/widgets/notification_feed_parts.dart';
import 'package:beautica_mobile/features/notifications/presentation/widgets/notification_tile.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';
import 'support/notification_flow_support.dart';

const Key _clientBell = Key('home_hub_bell_button');

Finder _markRead(String id) => find.byKey(NotificationTile.markReadKey(id));
Finder _markAll() => find.byKey(NotificationsMarkAllBar.actionKey);

/// resumed -> inactive -> hidden -> paused: the only legal order (the
/// `AppLifecycleListener` asserts on a direct `resumed -> paused`).
void _background(WidgetTester tester) {
  for (final AppLifecycleState s in <AppLifecycleState>[
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
}

/// paused -> hidden -> inactive -> resumed; a no-op when already resumed.
void _foreground(WidgetTester tester) {
  if (tester.binding.lifecycleState == AppLifecycleState.resumed) return;
  for (final AppLifecycleState s in <AppLifecycleState>[
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('CLIENT: the poll returns 1, the bell shows the dot, tapping a '
      'BOOKING_DECLINED item opens the booking detail, and back the dot is '
      'gone', (tester) async {
    await mockNetworkImagesFor(() async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final String id = fb.seedNotification(
        type: 'BOOKING_DECLINED',
        bookingId: FakeBackend.kNotificationBookingId,
      );
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.clientHome);

      expect(fb.notificationUnreadCountCalls, greaterThan(0));
      expect(unreadCountOf(tester), 1);
      expect(
        bellAsset(tester, _clientBell),
        BeauticaAssetIcons.notificationUnread,
      );

      await openFeed(tester, router, _clientBell);
      expect(notificationTile(id), findsOneWidget);
      expect(fb.notificationFeedCalls, greaterThan(0));

      await tester.tap(notificationTile(id));
      await AppHarness.settle(tester);

      AppHarness.expectLocation(
        router,
        RouteNames.notificationBookingDetail(
          FakeBackend.kNotificationBookingId,
        ),
      );
      expect(find.byType(BookingDetailScreen), findsOneWidget);
      expect(fb.notificationMarkedReadIds, <String>[id]);
      expect(fb.unreadNotificationCount, 0);

      await tapBookingDetailBack(tester);
      AppHarness.expectLocation(router, RouteNames.notifications);
      expect(_markRead(id), findsNothing, reason: 'the item stays read');

      await tester.tap(find.byKey(NotificationsScreen.backKey));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.clientHome);
      expect(
        bellAsset(tester, _clientBell),
        BeauticaAssetIcons.notificationPlain,
        reason: 'the dot is gone after the tap marked the item read',
      );
      expect(unreadCountOf(tester), 0);
    });
  });

  testWidgets('CLIENT: ✓ on one of three rows then «Позначити всі» go through '
      'the real wire, the server count follows and the bell loses its dot', (
    tester,
  ) async {
    final fb = FakeBackend()..currentRole = UserRole.client;
    final String a = fb.seedNotification(
      type: 'BOOKING_CREATED',
      age: const Duration(hours: 1),
    );
    final String b = fb.seedNotification(
      type: 'BOOKING_CREATED',
      age: const Duration(hours: 2),
    );
    final String c = fb.seedNotification(
      type: 'BOOKING_CREATED',
      age: const Duration(hours: 3),
    );
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.client);
    await AppHarness.settle(tester);
    expect(unreadCountOf(tester), 3);

    await openFeed(tester, router, _clientBell);
    expect(_markRead(a), findsOneWidget);
    expect(_markRead(c), findsOneWidget);

    await tester.tap(_markRead(b));
    await AppHarness.settle(tester);

    expect(fb.notificationMarkedReadIds, <String>[b]);
    expect(fb.unreadNotificationCount, 2);
    expect(unreadCountOf(tester), 2);
    expect(_markRead(b), findsNothing, reason: 'row b flipped to read');
    expect(_markAll(), findsOneWidget, reason: 'two unread remain');

    await tester.tap(_markAll());
    await AppHarness.settle(tester);

    expect(fb.notificationMarkAllCalls, 1);
    expect(
      fb.notificationMarkAllUpTo.single,
      isNotNull,
      reason: 'mark-all must send upTo = the newest loaded createdAt',
    );
    expect(fb.unreadNotificationCount, 0);
    expect(unreadCountOf(tester), 0);
    expect(_markAll(), findsNothing);
    expect(_markRead(a), findsNothing);
    expect(_markRead(c), findsNothing);

    await tester.tap(find.byKey(NotificationsScreen.backKey));
    await AppHarness.settle(tester);
    expect(
      bellAsset(tester, _clientBell),
      BeauticaAssetIcons.notificationPlain,
    );
  });

  testWidgets('CLIENT: a notification that lands while the app is backgrounded '
      'is picked up on resume (count 1 -> 2) with no feed interaction', (
    tester,
  ) async {
    DateTime now = kFixedNow;
    final fb = FakeBackend()..currentRole = UserRole.client;
    fb.seedNotification(type: 'BOOKING_CREATED');
    final GoRouter router = await AppHarness.boot(tester, fb, clock: () => now);
    await AppHarness.loginAs(tester, fb, UserRole.client);
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.clientHome);
    expect(unreadCountOf(tester), 1);

    addTearDown(() => _foreground(tester));
    // No pump while paused: frames are disabled until the resume below.
    _background(tester);
    fb.seedNotification(
      type: 'BOOKING_CREATED',
      age: const Duration(minutes: 5),
    );
    // Past the resume min-gap, on the SAME injected clock the app reads.
    now = kFixedNow.add(kUnreadResumeMinGap + const Duration(seconds: 5));
    final int callsBefore = fb.notificationUnreadCountCalls;

    _foreground(tester);
    await AppHarness.settle(tester);

    expect(
      fb.notificationUnreadCountCalls,
      greaterThan(callsBefore),
      reason: 'a resume past the gap must re-read the count',
    );
    expect(unreadCountOf(tester), 2);
    expect(
      bellAsset(tester, _clientBell),
      BeauticaAssetIcons.notificationUnread,
    );
  });
}
