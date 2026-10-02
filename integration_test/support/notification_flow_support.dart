// Phase 365 — shared helpers for the notification-feed E2E flows.
//
// One home for what the phase 363/364/365 flows all need, so a flow does not
// grow a private copy (REUSE-FIRST):
//   • [ScriptedNotificationRepository] — a STATEFUL scripted repository for the
//     flows that override `notificationRepositoryProvider` (salon-bound targets
//     cannot ride the HTTP fake: the mapper drops any non-UUID id and the fake
//     only serves `salon-owner-1` / `salon-xyz`);
//   • the bell / count / feed-open finders every flow repeats.
//
// The HTTP-path flows do NOT use the repository here — they seed
// `FakeBackend.seedNotification` and run the real Dio stack.

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/features/notifications/data/notification_repository.dart';
import 'package:beautica_mobile/features/notifications/domain/app_notification.dart';
import 'package:beautica_mobile/features/notifications/presentation/notifications_screen.dart';
import 'package:beautica_mobile/features/notifications/presentation/unread_notifications_notifier.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_cover_widgets.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/notification_bell_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'app_harness.dart';

/// Stateful scripted feed: one page, newest first. A mutation is visible to the
/// next fetch and the next unread count, exactly as the real backend behaves.
///
/// [markAllFailure], when non-null, is thrown by [markAllRead] (the rows are
/// then left untouched, like a request that never committed).
class ScriptedNotificationRepository implements NotificationRepository {
  ScriptedNotificationRepository(List<AppNotification> seed)
    : items = List<AppNotification>.of(seed);

  List<AppNotification> items;
  Object? markAllFailure;

  int fetchCalls = 0;
  final List<String> markedRead = <String>[];
  final List<DateTime?> markAllUpTo = <DateTime?>[];

  int get unread => items.where((AppNotification n) => !n.read).length;

  @override
  Future<int> unreadCount() async => unread;

  @override
  Future<NotificationPage> fetchPage({
    required int page,
    required int size,
  }) async {
    fetchCalls++;
    return NotificationPage(
      items: List<AppNotification>.of(items),
      page: page,
      size: size,
      totalElements: items.length,
      totalPages: 1,
    );
  }

  @override
  Future<void> markRead(String id) async {
    markedRead.add(id);
    items = <AppNotification>[
      for (final AppNotification n in items)
        if (n.id == id) n.copyWith(read: true) else n,
    ];
  }

  @override
  Future<int> markAllRead({DateTime? upTo}) async {
    markAllUpTo.add(upTo);
    final Object? failure = markAllFailure;
    if (failure != null) throw failure;
    int updated = 0;
    items = <AppNotification>[
      for (final AppNotification n in items)
        if (!n.read && (upTo == null || !n.createdAt.isAfter(upTo)))
          () {
            updated++;
            return n.copyWith(read: true);
          }()
        else
          n,
    ];
    return updated;
  }
}

/// `notification-tile-<id>` — the feed row.
Finder notificationTile(String id) => find.byKey(Key('notification-tile-$id'));

/// The live unread count read from the REAL container the app runs in (works
/// from any screen — it anchors on the app root, not on the feed).
int unreadCountOf(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp).first),
    ).read(unreadNotificationsProvider).value ??
    -1;

/// The bell glyph's asset under [buttonKey] — `notificationUnread` carries the
/// dot, `notificationPlain` does not.
String bellAsset(WidgetTester tester, Key buttonKey) => tester
    .widget<AppIcon>(
      find.descendant(
        of: find.byKey(buttonKey),
        matching: find.byKey(NotificationBellButton.bellIconKey),
      ),
    )
    .asset;

/// The glyph of the SALON COVER bell (a `CoverIconButton`, not a
/// `NotificationBellButton`) under [buttonKey].
String? coverBellAsset(WidgetTester tester, Key buttonKey) =>
    tester.widget<CoverIconButton>(find.byKey(buttonKey)).svgIcon;

/// Taps the bell under [bellKey] and asserts the feed route is mounted.
Future<void> openFeed(WidgetTester tester, GoRouter router, Key bellKey) async {
  await tester.tap(find.byKey(bellKey));
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.notifications);
  expect(find.byType(NotificationsScreen), findsOneWidget);
}

/// Taps the booking detail's back chevron.
Future<void> tapBookingDetailBack(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('booking-detail-back')));
  await AppHarness.settle(tester);
}
