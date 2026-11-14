// Phase 497 — E2E: a `BOOKING_REMINDER` feed row reads «Нагадування про візит»
// / «Ваш візит завтра о 14:00» and a tap opens the booking detail.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ----------------------------------------
// The unit tier proves the copy and `routeFor` in isolation. Only the real app
// proves the journey: the real feed route and screen (which hands the tile its
// Kyiv «today» from the injected clock), the real `openNotification`, the
// real router's feed-scoped client alias `/notifications/bookings/:id` and the
// real back stack.
//
// Like `notification_tap_to_detail_flow_test.dart`, the fake backend has no
// `/notifications` routes, so ONLY `notificationRepositoryProvider` is
// overridden with a small stateful scripted repository. The booking detail is
// the fake backend's real `GET /bookings/booking-1`.
//
// Journeys:
//  1. CLIENT: bell -> feed -> the reminder row shows title + «завтра о 14:00»
//     -> tap -> booking detail at the feed alias; the row is marked read ->
//     Back -> feed.
//  2. CLIENT, lost access (target NONE, params nulled): the row reads «params
//     gone»; a tap stays on the feed with «Запис більше недоступний», read.
//  3. CLIENT, REAL wire (mobile-qa): the fake backend serves a
//     `BOOKING_REMINDER` row as JSON, so the generated enum + mapper + copy
//     run end to end -> reminder title/body -> tap -> booking detail.
//  4. Background push tap (`pushTapFromData`) -> booking detail, PATCH read.
//  5. Cold-start push tap (`getInitialMessage`) -> booking detail.
//  6. Day words at render time on a MUTABLE injected clock: «сьогодні» /
//     «завтра» / the date, then a Kyiv-midnight rollover (21:30 UTC is still
//     the same UTC day) re-reads «today» on resume and every row re-words.
//
// KEY POLICY: taps/finds are key- or type-based; copy is read from the
// generated ARB, never a literal. Fixtures anchor to [kFixedNow], the clock
// the harness injects (M15) — 2026-06-14 12:00 UTC = 15:00 Kyiv.

import 'dart:async';

import 'package:beautica_mobile/core/push/firebase_messaging_provider.dart';
import 'package:beautica_mobile/core/push/push_available_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/notifications/data/notification_repository.dart';
import 'package:beautica_mobile/features/notifications/domain/app_notification.dart';
import 'package:beautica_mobile/features/notifications/presentation/notification_navigation.dart'
    show resetNotificationNavigationStateForTest;
import 'package:beautica_mobile/features/notifications/presentation/notifications_screen.dart';
import 'package:beautica_mobile/features/notifications/presentation/widgets/notification_tile.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:beautica_mobile/shared/formatters/uk_calendar.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/fakes/fake_secure_storage.dart';
import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// The fake backend's seeded booking — the only detail it serves.
const String _kBookingId = 'booking-1';

const Key _clientBell = Key('home_hub_bell_button');

/// Tomorrow (Kyiv) at 14:00 Kyiv = 11:00 UTC (EEST, +3), derived from the
/// injected clock [kFixedNow] (2026-06-14 12:00 UTC = 15:00 Kyiv), so the
/// «завтра» day word cannot drift with the host clock or across Kyiv midnight.
final DateTime _kTomorrow1400Kyiv = kFixedNow.add(const Duration(hours: 23));

/// Stateful scripted feed: one page, newest first.
class _FeedRepo implements NotificationRepository {
  _FeedRepo(List<AppNotification> seed)
    : items = List<AppNotification>.of(seed);

  List<AppNotification> items;
  final List<String> markedRead = <String>[];

  @override
  Future<int> unreadCount() async =>
      items.where((AppNotification n) => !n.read).length;

  @override
  Future<NotificationPage> fetchPage({
    required int page,
    required int size,
  }) async => NotificationPage(
    items: List<AppNotification>.of(items),
    page: page,
    size: size,
    totalElements: items.length,
    totalPages: 1,
  );

  @override
  Future<void> markRead(String id) async {
    markedRead.add(id);
    items = <AppNotification>[
      for (final AppNotification n in items)
        if (n.id == id) n.copyWith(read: true) else n,
    ];
  }

  @override
  Future<int> markAllRead({DateTime? upTo}) async => throw UnimplementedError();
}

AppNotification _reminder(String id) => AppNotification(
  id: id,
  type: AppNotificationType.bookingReminder,
  createdAt: kFixedNow.subtract(const Duration(hours: 1)),
  read: false,
  target: const NotificationTarget.booking(bookingId: _kBookingId),
  params: NotificationParams(
    counterpartName: 'Майстер $id',
    serviceName: 'Манікюр',
    serviceCount: 1,
    startsAt: _kTomorrow1400Kyiv,
  ),
);

AppNotification _lostAccess(String id) => AppNotification(
  id: id,
  type: AppNotificationType.bookingReminder,
  createdAt: kFixedNow.subtract(const Duration(hours: 1)),
  read: false,
  target: const NotificationTarget.none(),
  params: NotificationParams.empty,
);

Finder _tile(String id) => find.byKey(Key('notification-tile-$id'));

class _MockMessaging extends Mock implements FirebaseMessaging {}

/// Fake FCM (pattern from `push_tap_flow_test.dart`): a controller for
/// `onMessageOpenedApp` and a scripted `getInitialMessage`.
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

/// A backend-495 reminder push, as FCM hands it to the app.
RemoteMessage _reminderPush(String notificationId) => RemoteMessage(
  data: <String, dynamic>{
    'v': '1',
    'notificationId': notificationId,
    'type': 'BOOKING_REMINDER',
    'targetKind': 'BOOKING',
    'bookingId': FakeBackend.kNotificationBookingId,
  },
);

/// «нд, 14 червня» — the date form the body uses for a non-today/tomorrow day
/// (the shared uk calendar names, not a literal).
String _dateWord(int year, int month, int day) {
  final DateTime d = DateTime(year, month, day);
  return '${weekdayAbbrev(d.weekday)}, ${d.day} ${monthGenitive(d.month)}';
}

AppNotification _reminderAt(String id, DateTime startsAt, DateTime createdAt) =>
    AppNotification(
      id: id,
      type: AppNotificationType.bookingReminder,
      createdAt: createdAt,
      read: false,
      target: const NotificationTarget.booking(bookingId: _kBookingId),
      params: NotificationParams(
        counterpartName: 'Майстер $id',
        serviceName: 'Манікюр',
        serviceCount: 1,
        startsAt: startsAt,
      ),
    );

Finder _bodyIn(String id, String text) =>
    find.descendant(of: _tile(id), matching: find.text(text));

Future<(GoRouter, AppLocalizations)> _bootClientFeed(
  WidgetTester tester,
  _FeedRepo? repo, {
  FakeBackend? backend,
  DateTime Function()? clock,
}) async {
  final fb = backend ?? (FakeBackend()..currentRole = UserRole.client);
  final GoRouter router = await AppHarness.boot(
    tester,
    fb,
    clock: clock,
    extraOverrides: <Object>[
      if (repo != null) notificationRepositoryProvider.overrideWithValue(repo),
    ],
  );
  await AppHarness.loginAs(tester, fb, UserRole.client);
  await AppHarness.settle(tester);
  await tester.tap(find.byKey(_clientBell));
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.notifications);
  expect(find.byType(NotificationsScreen), findsOneWidget);
  final AppLocalizations l10n = AppLocalizations.of(
    tester.element(find.byType(NotificationsScreen)),
  );
  return (router, l10n);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(() {
    resetNotificationNavigationStateForTest();
    AppHarness.tearDownHarness();
  });

  testWidgets('CLIENT: the reminder row reads «завтра о 14:00»; a tap opens '
      'the booking detail at the feed alias and marks the row read', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      final _FeedRepo repo = _FeedRepo(<AppNotification>[_reminder('r1')]);
      final (GoRouter router, AppLocalizations l10n) = await _bootClientFeed(
        tester,
        repo,
      );

      final Finder tile = _tile('r1');
      expect(tile, findsOneWidget);
      expect(
        find.descendant(
          of: tile,
          matching: find.text(l10n.notificationTitleBookingReminder),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: tile,
          matching: find.text(
            l10n.notificationBodyBookingReminder(
              l10n.notificationReminderDayTomorrow,
              '14:00',
            ),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(NotificationTile.markReadKey('r1')),
        findsOneWidget,
        reason: 'unread row keeps its ✓',
      );

      await tester.tap(tile);
      await AppHarness.settle(tester);

      AppHarness.expectLocation(
        router,
        RouteNames.notificationBookingDetail(_kBookingId),
      );
      expect(find.byType(BookingDetailScreen), findsOneWidget);
      expect(repo.markedRead, <String>['r1']);

      await tester.tap(find.byKey(const Key('booking-detail-back')));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.notifications);
      expect(
        find.byKey(NotificationTile.markReadKey('r1')),
        findsNothing,
        reason: 'r1 stays read',
      );
    });
  });

  testWidgets('CLIENT, lost access: the row reads «params gone»; a tap stays '
      'on the feed with the unavailable snack and marks the row read', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      final _FeedRepo repo = _FeedRepo(<AppNotification>[_lostAccess('g1')]);
      final (GoRouter router, AppLocalizations l10n) = await _bootClientFeed(
        tester,
        repo,
      );

      final Finder tile = _tile('g1');
      expect(
        find.descendant(
          of: tile,
          matching: find.text(l10n.notificationsParamsGone),
        ),
        findsOneWidget,
      );

      await tester.tap(tile);
      await AppHarness.settle(tester);

      AppHarness.expectLocation(router, RouteNames.notifications);
      expect(find.byType(BookingDetailScreen), findsNothing);
      expect(repo.markedRead, <String>['g1']);
      expect(find.byType(VelvetSnack), findsOneWidget);
      expect(find.text(l10n.notificationsBookingUnavailable), findsOneWidget);
    });
  });

  testWidgets('CLIENT, real wire: a BOOKING_REMINDER JSON row maps through the '
      'generated enum to the reminder copy and opens the booking detail', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()..currentRole = UserRole.client;
      // Seeded `startsAt` = kFixedNow + 1 day = 2026-06-15 15:00 Kyiv.
      final String id = fb.seedNotification(
        type: 'BOOKING_REMINDER',
        bookingId: FakeBackend.kNotificationBookingId,
      );
      final (GoRouter router, AppLocalizations l10n) = await _bootClientFeed(
        tester,
        null,
        backend: fb,
      );

      expect(
        find.descendant(
          of: _tile(id),
          matching: find.text(l10n.notificationTitleBookingReminder),
        ),
        findsOneWidget,
        reason: 'BOOKING_REMINDER must not degrade to the unknown row',
      );
      expect(
        _bodyIn(
          id,
          l10n.notificationBodyBookingReminder(
            l10n.notificationReminderDayTomorrow,
            '15:00',
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(_tile(id));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(
        router,
        RouteNames.notificationBookingDetail(
          FakeBackend.kNotificationBookingId,
        ),
      );
      expect(find.byType(BookingDetailScreen), findsOneWidget);
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.notificationMarkedReadIds.contains(id),
        description: 'PATCH /notifications/{id}/read reached the backend',
      );
    });
  });

  testWidgets('a background BOOKING_REMINDER push tap opens the booking '
      'detail and marks the notification read', (tester) async {
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.client;
    final String id = fb.seedNotification(
      type: 'BOOKING_REMINDER',
      bookingId: FakeBackend.kNotificationBookingId,
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
    await AppHarness.loginAs(tester, fb, UserRole.client);
    await AppHarness.pumpUntilCondition(
      tester,
      () => fcm.openedSubscriptions > 0,
      description: 'the push-tap listener attached after login',
    );
    await AppHarness.settle(tester);

    fcm.opened.add(_reminderPush(id));
    await AppHarness.pumpUntilFound(tester, find.byType(BookingDetailScreen));
    await AppHarness.settle(tester);

    AppHarness.expectLocation(
      router,
      RouteNames.notificationBookingDetail(FakeBackend.kNotificationBookingId),
    );
    await AppHarness.pumpUntilCondition(
      tester,
      () => fb.notificationMarkedReadIds.contains(id),
      description: 'the reminder was marked read on the backend',
    );
    expect(fb.notificationMarkedReadIds, <String>[id]);
  });

  testWidgets('a COLD-START BOOKING_REMINDER push tap with a stored session '
      'lands on the booking detail', (tester) async {
    final FakeBackend fb = FakeBackend()..currentRole = UserRole.client;
    final String id = fb.seedNotification(
      type: 'BOOKING_REMINDER',
      bookingId: FakeBackend.kNotificationBookingId,
    );
    final FakeSecureStorage storage = FakeSecureStorage();
    await storage.writeRefreshToken('fake-refresh-token');
    final _TapFixture fcm = _TapFixture(launchMessage: _reminderPush(id));
    addTearDown(fcm.dispose);

    final GoRouter router = await AppHarness.boot(
      tester,
      fb,
      storage: storage,
      extraOverrides: fcm.overrides,
      mountPushTapDispatcher: true,
    );
    await AppHarness.pumpUntilFound(tester, find.byType(BookingDetailScreen));
    await AppHarness.settle(tester);

    AppHarness.expectLocation(
      router,
      RouteNames.notificationBookingDetail(FakeBackend.kNotificationBookingId),
    );
    await AppHarness.pumpUntilCondition(
      tester,
      () => fb.notificationMarkedReadIds.contains(id),
      description: 'the launch reminder was marked read',
    );
    verify(() => fcm.messaging.getInitialMessage()).called(1);
  });

  testWidgets('day words follow the injected Kyiv clock: today / tomorrow / '
      'date, and re-word after the Kyiv midnight on resume', (tester) async {
    await mockNetworkImagesFor(() async {
      // One mutable clock drives BOTH the app and the fixtures (M15).
      // kFixedNow (2026-06-14 12:00 UTC) + 8 h 30 = 20:30 UTC = 23:30 Kyiv
      // (EEST) on Sun 2026-06-14; every fixture below is a kFixedNow offset.
      DateTime now = kFixedNow.add(const Duration(hours: 8, minutes: 30));
      final DateTime created = now.subtract(const Duration(hours: 1));
      final _FeedRepo repo = _FeedRepo(<AppNotification>[
        // 22:00 Kyiv today.
        _reminderAt('t1', kFixedNow.add(const Duration(hours: 7)), created),
        // 00:30 Kyiv tomorrow — but still the 14th in UTC.
        _reminderAt(
          'n1',
          kFixedNow.add(const Duration(hours: 9, minutes: 30)),
          created,
        ),
        // 14:00 Kyiv tomorrow.
        _reminderAt('m1', kFixedNow.add(const Duration(hours: 23)), created),
        // 14:00 Kyiv Wed 17th.
        _reminderAt(
          'd1',
          kFixedNow.add(const Duration(days: 2, hours: 23)),
          created,
        ),
      ]);
      final (_, AppLocalizations l10n) = await _bootClientFeed(
        tester,
        repo,
        clock: () => now,
      );
      String reminder(String day, String time) =>
          l10n.notificationBodyBookingReminder(day, time);

      expect(
        _bodyIn('t1', reminder(l10n.notificationReminderDayToday, '22:00')),
        findsOneWidget,
      );
      expect(
        _bodyIn('m1', reminder(l10n.notificationReminderDayTomorrow, '14:00')),
        findsOneWidget,
      );
      expect(
        _bodyIn('d1', reminder(_dateWord(2026, 6, 17), '14:00')),
        findsOneWidget,
      );
      expect(
        _bodyIn('n1', reminder(l10n.notificationReminderDayTomorrow, '00:30')),
        findsOneWidget,
        reason: 'the visit day is the KYIV day, not the UTC day',
      );

      // 21:30 UTC — STILL 2026-06-14 in UTC, but 00:30 Mon 15th in Kyiv.
      now = kFixedNow.add(const Duration(hours: 9, minutes: 30));
      // `inactive`, not `paused`: a paused binding schedules no frames, so a
      // pump there never returns (measured: hang).
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await AppHarness.settle(tester);

      expect(
        _bodyIn('m1', reminder(l10n.notificationReminderDayToday, '14:00')),
        findsOneWidget,
        reason: 'tomorrow became today at the KYIV midnight',
      );
      expect(
        _bodyIn('n1', reminder(l10n.notificationReminderDayToday, '00:30')),
        findsOneWidget,
      );
      expect(
        _bodyIn('t1', reminder(_dateWord(2026, 6, 14), '22:00')),
        findsOneWidget,
        reason: 'a past visit names its date, never «сьогодні»',
      );
      expect(
        _bodyIn('d1', reminder(_dateWord(2026, 6, 17), '14:00')),
        findsOneWidget,
      );
    });
  });
}
