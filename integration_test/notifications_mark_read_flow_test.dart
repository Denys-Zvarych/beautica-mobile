// Phase 363 — E2E: the «Сповіщення» feed journey (mark read / mark all / refresh).
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ----------------------------------------
// The widget tier drives the feed screen against a hand-built router and a
// fake notifier container. None of it proves the REAL journey: a logged-in user
// taps the bell on their real header, the real `/notifications` route mounts the
// real feed, a per-row ✓ and «Позначити всі як прочитані» flow through the REAL
// feed notifier into the REAL `UnreadNotifications` count, and the bell on the
// header the user returns to reflects it.
//
// The fake backend has no `/notifications` routes, so — like the phase 361 bell
// flow — this file overrides ONLY `notificationRepositoryProvider` with a small
// STATEFUL scripted repository (a mark-read mutates the rows the next fetch and
// the next unread count answer from). Everything else is real.
//
// Journey (CLIENT): bell -> feed with 2 unread + 1 read -> ✓ on one (row flips,
// bar stays, count 2 -> 1) -> «Позначити всі» (bar + ✓ gone, count 0, repo saw an
// `upTo`) -> back: the bell has no dot -> reopen, a new item arrives, pull to
// refresh shows it and the bar returns.
// Journey (CLIENT, failure): «Позначити всі» fails (the scripted repo throws a
// `ServerFailure`) -> every row rolls back to unread, the error snack shows, the
// bar and ✓ come back, the count is restored and the bell keeps its dot
// (phase 365 — the rollback half of the spec's second run).
// Journey (SALON_OWNER): rows of two salons in ONE feed, each labelled; the row
// with no salon carries no label; the count spans both salons.
//
// NO PATROL FLOW: no native surface. Row tap only marks read until phase 364.
//
// KEY POLICY: every tap/find is key- or type-based; salon names are Latin so no
// Cyrillic finder is needed. The fixtures anchor to [kFixedNow], the clock the
// harness injects (M15: one clock per test).

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/notifications/data/notification_repository.dart';
import 'package:beautica_mobile/features/notifications/domain/app_notification.dart';
import 'package:beautica_mobile/features/notifications/presentation/notifications_screen.dart';
import 'package:beautica_mobile/features/notifications/presentation/unread_notifications_notifier.dart';
import 'package:beautica_mobile/features/notifications/presentation/widgets/notification_feed_parts.dart';
import 'package:beautica_mobile/features/notifications/presentation/widgets/notification_tile.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/notification_bell_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/velvet_snack_matchers.dart';
import 'support/app_harness.dart';
import 'support/notification_flow_support.dart';

AppNotification _notif(
  String id, {
  required Duration age,
  required bool read,
  String? salon,
}) => AppNotification(
  id: id,
  type: AppNotificationType.bookingCreated,
  createdAt: kFixedNow.subtract(age),
  read: read,
  target: const NotificationTarget.none(),
  params: NotificationParams(
    counterpartName: 'Client $id',
    serviceName: 'Service $id',
    startsAt: kFixedNow.add(const Duration(days: 1)),
    salonName: salon,
  ),
);

List<Object> _repo(ScriptedNotificationRepository repo) => <Object>[
  notificationRepositoryProvider.overrideWithValue(repo),
];

Finder _tile(String id) => find.byKey(Key('notification-tile-$id'));
Finder _markRead(String id) => find.byKey(NotificationTile.markReadKey(id));
Finder _markAll() => find.byKey(NotificationsMarkAllBar.actionKey);

/// The live unread count, read from the REAL container the app runs in.
int _count(WidgetTester tester) {
  final ProviderContainer c = ProviderScope.containerOf(
    tester.element(find.byType(NotificationsScreen)),
  );
  return c.read(unreadNotificationsProvider).value ?? -1;
}

String _bellAsset(WidgetTester tester, Key buttonKey) => tester
    .widget<AppIcon>(
      find.descendant(
        of: find.byKey(buttonKey),
        matching: find.byKey(NotificationBellButton.bellIconKey),
      ),
    )
    .asset;

Future<void> _openFeed(
  WidgetTester tester,
  GoRouter router,
  Key bellKey,
) async {
  await tester.tap(find.byKey(bellKey));
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.notifications);
  expect(find.byType(NotificationsScreen), findsOneWidget);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  const Key clientBell = Key('home_hub_bell_button');
  const Key coverBell = Key('salon-manage-notifications');

  testWidgets('CLIENT opens the feed from the bell, marks one row read, marks '
      'all read, the bell loses its dot, and pull-to-refresh brings a new '
      'item back', (tester) async {
    final ScriptedNotificationRepository repo =
        ScriptedNotificationRepository(<AppNotification>[
          _notif('a', age: const Duration(hours: 1), read: false),
          _notif('b', age: const Duration(hours: 2), read: false),
          _notif('c', age: const Duration(hours: 3), read: true),
        ]);
    final fb = FakeBackend()..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(
      tester,
      fb,
      extraOverrides: _repo(repo),
    );
    await AppHarness.loginAs(tester, fb, UserRole.client);
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.clientHome);
    expect(
      _bellAsset(tester, clientBell),
      BeauticaAssetIcons.notificationUnread,
    );

    await _openFeed(tester, router, clientBell);

    // Unread rows carry a ✓, the read row does not; the bar is offered.
    expect(_tile('a'), findsOneWidget);
    expect(_tile('c'), findsOneWidget);
    expect(_markRead('a'), findsOneWidget);
    expect(_markRead('b'), findsOneWidget);
    expect(_markRead('c'), findsNothing);
    expect(_markAll(), findsOneWidget);
    expect(_count(tester), 2);

    // ✓ on ONE row: it flips, the other stays unread, the bar and the dot stay.
    await tester.tap(_markRead('a'));
    await AppHarness.settle(tester);
    expect(repo.markedRead, <String>['a']);
    expect(_markRead('a'), findsNothing, reason: 'row a flipped to read');
    expect(_markRead('b'), findsOneWidget, reason: 'row b is still unread');
    expect(_markAll(), findsOneWidget, reason: 'one unread remains');
    expect(_count(tester), 1);
    AppHarness.expectLocation(router, RouteNames.notifications);

    // «Позначити всі»: bar and every ✓ disappear, the count reaches 0.
    await tester.tap(_markAll());
    await AppHarness.settle(tester);
    expect(repo.markAllUpTo, hasLength(1));
    expect(
      repo.markAllUpTo.single,
      isNotNull,
      reason: 'mark-all must pass upTo = newest loaded createdAt',
    );
    expect(_markAll(), findsNothing);
    expect(_markRead('b'), findsNothing);
    expect(_count(tester), 0);

    // Back on the header the bell has no dot.
    await tester.tap(find.byKey(NotificationsScreen.backKey));
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.clientHome);
    expect(
      _bellAsset(tester, clientBell),
      BeauticaAssetIcons.notificationPlain,
    );

    // A new unread item lands server-side; reopening + pull-to-refresh shows it.
    await _openFeed(tester, router, clientBell);
    expect(_markAll(), findsNothing);
    repo.items = <AppNotification>[
      _notif('d', age: const Duration(minutes: 5), read: false),
      ...repo.items,
    ];
    final int fetchesBefore = repo.fetchCalls;
    expect(_tile('d'), findsNothing);

    await tester.fling(
      find.byKey(NotificationsScreen.listKey),
      const Offset(0, 300),
      1000,
    );
    await AppHarness.settle(tester);

    expect(repo.fetchCalls, greaterThan(fetchesBefore));
    expect(_tile('d'), findsOneWidget);
    expect(_markRead('d'), findsOneWidget);
    expect(
      _markAll(),
      findsOneWidget,
      reason: 'the new unread row re-offers it',
    );
    expect(_count(tester), 1);
  });

  testWidgets('CLIENT: a failing «Позначити всі» rolls every row back to '
      'unread, shows the error snack, and the bell keeps its dot', (
    tester,
  ) async {
    final ScriptedNotificationRepository repo =
        ScriptedNotificationRepository(<AppNotification>[
          _notif('a', age: const Duration(hours: 1), read: false),
          _notif('b', age: const Duration(hours: 2), read: false),
          _notif('c', age: const Duration(hours: 3), read: true),
        ])..markAllFailure = const ServerFailure(statusCode: 500);
    final fb = FakeBackend()..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(
      tester,
      fb,
      extraOverrides: _repo(repo),
    );
    await AppHarness.loginAs(tester, fb, UserRole.client);
    await AppHarness.settle(tester);
    await _openFeed(tester, router, clientBell);
    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(NotificationsScreen)),
    );
    expect(_count(tester), 2);

    await tester.tap(_markAll());
    await AppHarness.settle(tester);
    await pumpVelvetSnackIn(tester);

    expect(repo.markAllUpTo, hasLength(1), reason: 'the request was issued');
    expectVelvetSnack(
      l10n.notificationsMarkAllReadFailed,
      variant: VelvetSnackVariant.error,
    );
    expect(_markRead('a'), findsOneWidget, reason: 'row a rolled back');
    expect(_markRead('b'), findsOneWidget, reason: 'row b rolled back');
    expect(_markRead('c'), findsNothing, reason: 'c was read all along');
    expect(_markAll(), findsOneWidget, reason: 'the bar is offered again');
    expect(_count(tester), 2, reason: 'the optimistic zero was undone');
    AppHarness.expectLocation(router, RouteNames.notifications);

    await pumpPastVelvetSnack(tester);
    await tester.tap(find.byKey(NotificationsScreen.backKey));
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.clientHome);
    expect(
      _bellAsset(tester, clientBell),
      BeauticaAssetIcons.notificationUnread,
      reason: 'the dot is back: nothing was marked read server-side',
    );
  });

  testWidgets('SALON_OWNER sees rows of BOTH salons in one feed, each '
      'labelled; the salon-less row has no label; the count spans both', (
    tester,
  ) async {
    final ScriptedNotificationRepository repo =
        ScriptedNotificationRepository(<AppNotification>[
          _notif(
            'lotus',
            age: const Duration(hours: 1),
            read: false,
            salon: 'Lotus Studio',
          ),
          _notif(
            'orchid',
            age: const Duration(hours: 2),
            read: false,
            salon: 'Orchid Studio',
          ),
          _notif('solo', age: const Duration(hours: 3), read: true),
        ]);
    final fb = FakeBackend()..currentRole = UserRole.salonOwner;
    final GoRouter router = await AppHarness.boot(
      tester,
      fb,
      extraOverrides: _repo(repo),
    );
    await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
    await AppHarness.settle(tester);

    await _openFeed(tester, router, coverBell);

    String labelIn(String id) => tester
        .widget<SalonLabel>(
          find.descendant(of: _tile(id), matching: find.byType(SalonLabel)),
        )
        .name;
    expect(labelIn('lotus'), contains('Lotus Studio'));
    expect(labelIn('orchid'), contains('Orchid Studio'));
    expect(
      find.descendant(of: _tile('solo'), matching: find.byType(SalonLabel)),
      findsNothing,
    );
    expect(_count(tester), 2, reason: 'unread spans both salons');

    // Marking one salon's row read leaves the other salon's row unread.
    await tester.tap(_markRead('lotus'));
    await AppHarness.settle(tester);
    expect(_markRead('lotus'), findsNothing);
    expect(_markRead('orchid'), findsOneWidget);
    expect(_count(tester), 1);
  });
}
