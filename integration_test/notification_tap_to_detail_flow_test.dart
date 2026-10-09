// Phase 364 — E2E: a notification TAP opens the per-role destination (and back).
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ----------------------------------------
// The widget tier drives `NotificationsScreen` against a hand-built router. It
// cannot prove the REAL journey: the real feed route, the real `routeFor`, the
// REAL router (client shell alias routes, the salon-staff detail, the salon
// shell `?tab=team` signal, the `onUnavailable` pop) and the real back stack,
// with the real unread-count notifier in the bell the user returns to.
//
// Like the phase 361/363 flows, the fake backend has no `/notifications`
// routes, so ONLY `notificationRepositoryProvider` is overridden with a small
// STATEFUL scripted repository (mark-read mutates what the next count answers).
// The booking detail itself is the fake backend's real `GET /bookings/booking-1`.
//
// Journeys:
//  1. CLIENT: bell -> feed -> tap a booking item -> `BookingDetailScreen` at the
//     FEED-SCOPED alias `/notifications/bookings/:id` (NOT the client shell's
//     `/bookings/:id`, which would duplicate the shell) -> Back -> feed; item
//     read, count 2 -> 1; the next Back lands on Головна.
//  2. SALON_OWNER (salon A = the landing shell, salon B = `salon-xyz`): tap a
//     salon-B booking item -> `/salon/bookings/:id` -> Back -> feed -> Back ->
//     the SAME salon-A shell: the owner was never moved to salon B.
//  3. SALON_OWNER: a `SalonTeamTarget` item -> the salon shell on «Команда».
//  4. CLIENT, unavailable booking (detail 404): tap -> back on the feed, the
//     «Запис більше недоступний» snack, item read.
//
// KEY POLICY: taps/finds are key- or type-based. The snack text is read from
// the generated ARB (`l10n.notificationsBookingUnavailable`), never a literal.
// Fixtures anchor to [kFixedNow], the clock the harness injects (M15).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/client_review_section.dart';
import 'package:beautica_mobile/features/notifications/data/notification_repository.dart';
import 'package:beautica_mobile/features/notifications/domain/app_notification.dart';
import 'package:beautica_mobile/features/notifications/presentation/notifications_screen.dart';
import 'package:beautica_mobile/features/notifications/presentation/unread_notifications_notifier.dart';
import 'package:beautica_mobile/features/notifications/presentation/widgets/notification_tile.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:beautica_mobile/shared/widgets/salon_bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/velvet_snack_matchers.dart';
import 'support/app_harness.dart';

/// The fake backend's seeded booking — the only detail it serves.
const String _kBookingId = 'booking-1';

/// Salon B: the salon whose detail + roster the fake serves in full and that
/// `salonManageGuard` admits once it is in `mySalons`. Salon A is the owner's
/// landing shell (`FakeBackend.kOwnerSalonId`).
const String _kSalonB = 'salon-xyz';

const Key _clientBell = Key('home_hub_bell_button');
const Key _coverBell = Key('salon-manage-notifications');

/// Fixture DATA: the seeded `booking-1` master's display name.
const String _kOwnMasterName = 'Софія Бондар';

/// Bottom-nav destination of «Команда» (`SalonBottomNav.ownerAdminItems`).
const int _navTeam = 2;

/// Phase 390 — wire comment of the client's review; must NEVER render for a
/// salon owner/admin (they read it in the salon «Відгуки» tab).
const String _kReviewComment = 'Чудовий майстер, дякую!';

Future<void> _expectNoClientReview(WidgetTester tester) async {
  expect(find.byType(BookingDetailScreen), findsOneWidget);
  expect(find.byType(ClientReviewSection), findsNothing);
  // i18n-finder-ok: seeded backend review body, not UI copy.
  expect(find.text(_kReviewComment), findsNothing);
}

/// Stateful scripted feed: one page, newest first.
class _FeedRepo implements NotificationRepository {
  _FeedRepo(List<AppNotification> seed)
    : items = List<AppNotification>.of(seed);

  List<AppNotification> items;
  final List<String> markedRead = <String>[];

  int get unread => items.where((AppNotification n) => !n.read).length;

  @override
  Future<int> unreadCount() async => unread;

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

AppNotification _notif(
  String id, {
  required Duration age,
  required NotificationTarget target,
  AppNotificationType type = AppNotificationType.bookingCreated,
  bool read = false,
}) => AppNotification(
  id: id,
  type: type,
  createdAt: kFixedNow.subtract(age),
  read: read,
  target: target,
  params: NotificationParams(
    counterpartName: 'Client $id',
    serviceName: 'Service $id',
    startsAt: kFixedNow.add(const Duration(days: 1)),
  ),
);

List<Object> _repo(_FeedRepo repo) => <Object>[
  notificationRepositoryProvider.overrideWithValue(repo),
];

Finder _tile(String id) => find.byKey(Key('notification-tile-$id'));
Finder _markRead(String id) => find.byKey(NotificationTile.markReadKey(id));

// `skipOffstage: false`: while the detail is pushed the feed is still mounted
// underneath (offstage) — which is exactly where the count must be readable.
int _count(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(NotificationsScreen, skipOffstage: false)),
    ).read(unreadNotificationsProvider).value ??
    -1;

Future<void> _openFeed(WidgetTester tester, GoRouter router, Key bell) async {
  await tester.tap(find.byKey(bell));
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.notifications);
  expect(find.byType(NotificationsScreen), findsOneWidget);
}

Future<void> _tapDetailBack(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('booking-detail-back')));
  await AppHarness.settle(tester);
}

/// `salon-xyz` as the owner's SECOND (non-primary) salon, so the landing shell
/// stays salon A and `salonManageGuard` admits salon B.
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

int _navIndex(WidgetTester tester) => tester
    .widget<SalonBottomNav>(find.byKey(const Key('salon-shell-bottom-nav')))
    .currentIndex;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('CLIENT taps a booking item: the detail opens on the feed-scoped '
      'alias, the item is read and the count drops; Back returns to the feed '
      'and then Головна', (tester) async {
    await mockNetworkImagesFor(() async {
      final _FeedRepo repo = _FeedRepo(<AppNotification>[
        _notif(
          'n1',
          age: const Duration(hours: 1),
          target: const NotificationTarget.booking(bookingId: _kBookingId),
        ),
        _notif(
          'n2',
          age: const Duration(hours: 2),
          target: const NotificationTarget.none(),
          type: AppNotificationType.unknown,
        ),
      ]);
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        extraOverrides: _repo(repo),
      );
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await AppHarness.settle(tester);
      await _openFeed(tester, router, _clientBell);
      expect(_count(tester), 2);

      await tester.tap(_tile('n1'));
      await AppHarness.settle(tester);

      AppHarness.expectLocation(
        router,
        RouteNames.notificationBookingDetail(_kBookingId),
      );
      expect(find.byType(BookingDetailScreen), findsOneWidget);
      expect(repo.markedRead, <String>['n1']);
      expect(_count(tester), 1, reason: 'bell count decremented on tap');

      await _tapDetailBack(tester);

      AppHarness.expectLocation(router, RouteNames.notifications);
      expect(find.byType(BookingDetailScreen), findsNothing);
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(_markRead('n1'), findsNothing, reason: 'n1 stays read');
      expect(_markRead('n2'), findsOneWidget, reason: 'n2 is still unread');
      expect(_count(tester), 1);

      await tester.tap(find.byKey(NotificationsScreen.backKey));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.clientHome);
    });
  });

  testWidgets('SALON_OWNER (salon A active) taps a salon-B booking item: the '
      'staff detail opens, Back returns to the feed, and the owner is still on '
      'the salon-A shell', (tester) async {
    await mockNetworkImagesFor(() async {
      final _FeedRepo repo = _FeedRepo(<AppNotification>[
        _notif(
          'b1',
          age: const Duration(hours: 1),
          target: const NotificationTarget.booking(
            bookingId: _kBookingId,
            salonId: _kSalonB,
          ),
        ),
      ]);
      final fb = FakeBackend()..currentRole = UserRole.salonOwner;
      _seedSalonB(fb);
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        extraOverrides: _repo(repo),
      );
      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.settle(tester);
      final String salonAShell = AppHarness.location(router);
      expect(salonAShell, startsWith('/salons/${FakeBackend.kOwnerSalonId}'));

      await _openFeed(tester, router, _coverBell);
      await tester.tap(_tile('b1'));
      await AppHarness.settle(tester);

      AppHarness.expectLocation(
        router,
        RouteNames.salonStaffBookingDetail(_kBookingId),
      );
      expect(find.byType(BookingDetailScreen), findsOneWidget);
      expect(repo.markedRead, <String>['b1']);

      await _tapDetailBack(tester);
      AppHarness.expectLocation(router, RouteNames.notifications);
      expect(_count(tester), 0);

      await tester.tap(find.byKey(NotificationsScreen.backKey));
      await AppHarness.settle(tester);
      expect(
        AppHarness.location(router),
        salonAShell,
        reason: 'reading a salon-B notification must not move the owner',
      );
      expect(find.byType(SalonShellScreen), findsOneWidget);
      expect(
        find.byKey(const Key('salon-shell-bottom-nav')),
        findsOneWidget,
        reason: 'exactly one (salon A) shell is on screen',
      );
    });
  });

  testWidgets('SALON_OWNER taps a notification for a booking they PERFORM '
      'themselves: the detail shows the performing-master strip with their '
      'master name and never reads /masters/me', (tester) async {
    await mockNetworkImagesFor(() async {
      final _FeedRepo repo = _FeedRepo(<AppNotification>[
        _notif(
          'own1',
          age: const Duration(hours: 1),
          target: const NotificationTarget.booking(
            bookingId: _kBookingId,
            salonId: FakeBackend.kOwnerSalonId,
          ),
        ),
      ]);
      // The owner's own master row id == the seeded booking's `masterId`.
      final fb = FakeBackend(masterRowId: 'master-aaa')
        ..currentRole = UserRole.salonOwner
        ..bookingMasterType = 'SALON_MASTER'
        ..bookingSalonName = 'Салон Камелія'
        ..bookingProviderCanReviewClient = false
        ..bookingReviewByClient = <String, Object?>{
          'rating': 5,
          'comment': _kReviewComment,
        };
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        extraOverrides: _repo(repo),
      );
      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.settle(tester);

      await _openFeed(tester, router, _coverBell);
      await tester.tap(_tile('own1'));
      await AppHarness.settle(tester);

      AppHarness.expectLocation(
        router,
        RouteNames.salonStaffBookingDetail(_kBookingId),
      );
      expect(find.byType(BookingDetailScreen), findsOneWidget);
      final Finder strip = find.byKey(
        const Key('booking-detail-performing-master-strip'),
      );
      expect(strip, findsOneWidget);
      expect(
        find.descendant(of: strip, matching: find.text(_kOwnMasterName)),
        findsOneWidget, // i18n-finder-ok: seeded fixture name, not UI copy
        reason: 'the strip names the performing master — here the owner',
      );
      expect(fb.getMasterCalls, 0);
      await _expectNoClientReview(tester);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('SALON_ADMIN taps a salon-booking item carrying the client '
      'review: the detail opens with no review section', (tester) async {
    await mockNetworkImagesFor(() async {
      final _FeedRepo repo = _FeedRepo(<AppNotification>[
        _notif(
          'adm1',
          age: const Duration(hours: 1),
          target: const NotificationTarget.booking(
            bookingId: _kBookingId,
            salonId: FakeBackend.kOwnerSalonId,
          ),
        ),
      ]);
      final fb = FakeBackend()
        ..currentRole = UserRole.salonAdmin
        ..bookingMasterType = 'SALON_MASTER'
        ..bookingSalonName = 'Салон Камелія'
        ..bookingReviewByClient = <String, Object?>{
          'rating': 5,
          'comment': _kReviewComment,
        };
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        extraOverrides: _repo(repo),
      );
      await AppHarness.loginAs(tester, fb, UserRole.salonAdmin);
      await AppHarness.settle(tester);

      await _openFeed(tester, router, _coverBell);
      await tester.tap(_tile('adm1'));
      await AppHarness.settle(tester);

      expect(find.byType(BookingDetailScreen), findsOneWidget);
      expect(
        find.byKey(const Key('booking-detail-performing-master-strip')),
        findsOneWidget,
        reason: 'anti-vacuity — the salon-viewer detail really rendered',
      );
      await _expectNoClientReview(tester);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('SALON_OWNER taps a SalonTeamTarget item: the salon shell opens '
      'on «Команда»', (tester) async {
    await mockNetworkImagesFor(() async {
      final _FeedRepo repo = _FeedRepo(<AppNotification>[
        _notif(
          't1',
          age: const Duration(hours: 1),
          type: AppNotificationType.inviteAccepted,
          target: const NotificationTarget.salonTeam(salonId: _kSalonB),
        ),
      ]);
      final fb = FakeBackend()..currentRole = UserRole.salonOwner;
      _seedSalonB(fb);
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        extraOverrides: _repo(repo),
      );
      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.settle(tester);

      await _openFeed(tester, router, _coverBell);
      await tester.tap(_tile('t1'));
      await AppHarness.settle(tester);

      AppHarness.expectLocation(router, RouteNames.salonShell(_kSalonB));
      expect(find.byType(SalonShellScreen), findsOneWidget);
      expect(_navIndex(tester), _navTeam, reason: 'shell opened on «Команда»');
      expect(repo.markedRead, <String>['t1']);
    });
  });

  testWidgets('CLIENT taps a booking item whose detail is gone (404): back on '
      'the feed with the unavailable snack, and the item is read', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      final _FeedRepo repo = _FeedRepo(<AppNotification>[
        _notif(
          'g1',
          age: const Duration(hours: 1),
          target: const NotificationTarget.booking(bookingId: _kBookingId),
        ),
      ]);
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        ..bookingDetailFailStatus = 404;
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        extraOverrides: _repo(repo),
      );
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await AppHarness.settle(tester);
      await _openFeed(tester, router, _clientBell);
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(NotificationsScreen)),
      );

      await tester.tap(_tile('g1'));
      await AppHarness.settle(tester);
      await pumpVelvetSnackIn(tester);

      AppHarness.expectLocation(router, RouteNames.notifications);
      expect(find.byType(BookingDetailScreen), findsNothing);
      expectVelvetSnack(
        l10n.notificationsBookingUnavailable,
        variant: VelvetSnackVariant.warning,
      );
      expect(repo.markedRead, <String>['g1']);
      expect(_count(tester), 0);
      expect(fb.getBookingDetailCalls, greaterThan(0));

      await pumpPastVelvetSnack(tester);
    });
  });
}
