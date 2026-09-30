// Phase 361 — E2E: the shared notification bell (red dot + tap -> /notifications).
//
// WHY THIS FILE EXISTS
// --------------------
// The widget tier proves the bell glyph, the connected wrapper and each header
// in isolation. None of it proves the REAL journey: a logged-in user, on the
// real router, sees the global unread dot on their header, taps the bell, lands
// on the `/notifications` route, and comes back to the same header.
//
// The fake backend has no `/notifications/unread-count` route, so the flow
// overrides ONLY `notificationRepositoryProvider` (via `extraOverrides`) with a
// scripted repository. The REAL `UnreadNotifications` notifier, the REAL
// `hasUnreadNotificationsProvider`, the REAL bell widgets and the REAL router
// are all exercised.
//
// Surfaces covered: CLIENT shell (Головна), SALON_OWNER «Мої салони» and the
// SALON_OWNER salon cover (shell tab 0). The independent-master / salon-master
// headers carry no bell until the phase 362 design gate — not covered here.
//
// KEY POLICY: every tap/find is key-based.

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/notifications/data/notification_repository.dart';
import 'package:beautica_mobile/features/notifications/domain/app_notification.dart';
import 'package:beautica_mobile/features/notifications/presentation/notifications_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_cover_widgets.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/notification_bell_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// Scripted repository: always answers [count] for the unread count.
class _FixedUnreadRepo implements NotificationRepository {
  _FixedUnreadRepo(this.count);

  final int count;

  @override
  Future<int> unreadCount() async => count;

  @override
  Future<NotificationPage> fetchPage({required int page, required int size}) =>
      throw UnimplementedError();

  @override
  Future<void> markRead(String id) => throw UnimplementedError();

  @override
  Future<int> markAllRead({DateTime? upTo}) => throw UnimplementedError();
}

List<Object> _unread(int count) => <Object>[
  notificationRepositoryProvider.overrideWithValue(_FixedUnreadRepo(count)),
];

String _bellAsset(WidgetTester tester, Key buttonKey) => tester
    .widget<AppIcon>(
      find.descendant(
        of: find.byKey(buttonKey),
        matching: find.byKey(NotificationBellButton.bellIconKey),
      ),
    )
    .asset;

Future<void> _tapBellAndReturn(
  WidgetTester tester,
  GoRouter router,
  Finder bell,
  String returnLocation,
) async {
  await tester.tap(bell);
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.notifications);
  expect(find.byType(NotificationsScreen), findsOneWidget);

  await tester.tap(find.byKey(const Key('notifications-back')));
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, returnLocation);
  expect(find.byType(NotificationsScreen), findsNothing);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  const Key clientBell = Key('home_hub_bell_button');
  const Key mySalonsBell = Key('my_salons_bell_button');
  const Key coverBell = Key('salon-manage-notifications');

  testWidgets('CLIENT with unread > 0 sees the dot; tap opens /notifications '
      'and back returns to Головна', (tester) async {
    final fb = FakeBackend()..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(
      tester,
      fb,
      extraOverrides: _unread(3),
    );
    await AppHarness.loginAs(tester, fb, UserRole.client);
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.clientHome);

    expect(find.byKey(clientBell), findsOneWidget);
    expect(
      _bellAsset(tester, clientBell),
      BeauticaAssetIcons.notificationUnread,
      reason: 'unread 3 must render the dotted bell',
    );

    await _tapBellAndReturn(
      tester,
      router,
      find.byKey(clientBell),
      RouteNames.clientHome,
    );
  });

  testWidgets('CLIENT with unread == 0 sees the plain bell (no dot); tap '
      'still navigates', (tester) async {
    final fb = FakeBackend()..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(
      tester,
      fb,
      extraOverrides: _unread(0),
    );
    await AppHarness.loginAs(tester, fb, UserRole.client);
    await AppHarness.settle(tester);

    expect(
      _bellAsset(tester, clientBell),
      BeauticaAssetIcons.notificationPlain,
      reason: 'unread 0 must render the dotless bell',
    );

    await _tapBellAndReturn(
      tester,
      router,
      find.byKey(clientBell),
      RouteNames.clientHome,
    );
  });

  testWidgets('SALON_OWNER sees the same global dot on «Мої салони» and on '
      'the salon cover; each bell opens /notifications', (tester) async {
    final fb = FakeBackend()..currentRole = UserRole.salonOwner;
    final GoRouter router = await AppHarness.boot(
      tester,
      fb,
      extraOverrides: _unread(5),
    );
    await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
    await AppHarness.settle(tester);

    // Landing = salon shell, tab 0 = the salon cover with the live bell.
    final String shellLocation = AppHarness.location(router);
    expect(shellLocation, startsWith('/salons/'));
    expect(find.byKey(coverBell), findsOneWidget);
    expect(
      tester.widget<CoverIconButton>(find.byKey(coverBell)).svgIcon,
      BeauticaAssetIcons.notificationUnread,
      reason: 'the cover bell is live: dot follows the global unread flag',
    );
    await _tapBellAndReturn(
      tester,
      router,
      find.byKey(coverBell),
      shellLocation,
    );

    // «Мої салони» — same global dot.
    router.go(RouteNames.mySalons);
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.mySalons);
    expect(find.byKey(mySalonsBell), findsOneWidget);
    expect(
      _bellAsset(tester, mySalonsBell),
      BeauticaAssetIcons.notificationUnread,
      reason: 'the owner hub shows the same global dot as the salon cover',
    );
    await _tapBellAndReturn(
      tester,
      router,
      find.byKey(mySalonsBell),
      RouteNames.mySalons,
    );
  });
}
