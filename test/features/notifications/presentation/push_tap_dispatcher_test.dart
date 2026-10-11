// Phase 069 — PushTapDispatcher: pending tap -> mark read -> openNotificationTarget.
//
// A mini router stands in for the app's (unmatched locations render
// `errorBuilder`, which records the pushed LOCATION). The pending tap is a
// scripted stub; its real filling is covered by pending_push_tap_notifier_test.

import 'package:beautica_mobile/features/notifications/presentation/notification_navigation.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/notifications/data/notification_repository.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/notifications/domain/app_notification.dart';
import 'package:beautica_mobile/features/notifications/domain/notifications_feed_state.dart';
import 'package:beautica_mobile/features/notifications/domain/push_tap.dart';
import 'package:beautica_mobile/features/notifications/presentation/notifications_feed_notifier.dart';
import 'package:beautica_mobile/features/notifications/presentation/pending_push_tap_notifier.dart';
import 'package:beautica_mobile/features/notifications/presentation/push_tap_dispatcher.dart';
import 'package:beautica_mobile/features/notifications/presentation/unread_notifications_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_notification_repository.dart';
import '../../../helpers/test_container.dart';

const String _id = '00000000-0000-4000-8000-0000000000a1';
const String _bk = '00000000-0000-4000-8000-0000000000b1';

class _Pending extends PendingPushTap {
  @override
  PushTap? build() => null;

  void put(PushTap t) => state = t;
}

class _FeedWithRow extends NotificationsFeed {
  static final List<String> marked = <String>[];

  @override
  Future<NotificationsFeedState> build() async => NotificationsFeedState(
    items: <AppNotification>[notif(_id)],
    nextPage: 0,
    hasMore: false,
  );

  @override
  Future<bool> markRead(String id) async {
    marked.add(id);
    return true;
  }
}

class _Mys extends MySalons {
  @override
  Future<List<Salon>> build() async => const <Salon>[
    Salon(id: 'S1', name: 'Salon 1'),
  ];
}

class _Anon extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.unauthenticated();
}

const PushTap _bookingTap = PushTap(
  notificationId: _id,
  type: AppNotificationType.bookingCreated,
  target: NotificationTarget.booking(bookingId: _bk),
);

class _Rig {
  _Rig({
    String initial = '/',
    UserRole? role = UserRole.independentMaster,
    Object? markReadError,
    this.feedAlive = false,
  }) : repo = FakeNotificationRepository()..markReadError = markReadError,
       _role = role {
    router = GoRouter(
      initialLocation: initial,
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext c, GoRouterState s) => const SizedBox(),
        ),
        GoRoute(
          path: RouteNames.splash,
          builder: (BuildContext c, GoRouterState s) => const SizedBox(),
        ),
      ],
      errorBuilder: (BuildContext c, GoRouterState s) {
        seen.add(s.uri.toString());
        return const SizedBox();
      },
    );
  }

  final FakeNotificationRepository repo;
  final UserRole? _role;
  final bool feedAlive;
  final List<String> seen = <String>[];
  late final GoRouter router;
  final RecordingUnread unread = RecordingUnread(0);

  Future<ProviderContainer> pump(WidgetTester tester) async {
    final ProviderContainer container = makeTestContainer(
      overrides: [
        appRouterProvider.overrideWithValue(router),
        authProvider.overrideWith(
          () => _role == null ? _Anon() : FixedRoleAuth(_role),
        ),
        pendingPushTapProvider.overrideWith(_Pending.new),
        mySalonsProvider.overrideWith(_Mys.new),
        notificationRepositoryProvider.overrideWithValue(repo),
        unreadNotificationsProvider.overrideWith(() => unread),
        if (feedAlive) notificationsFeedProvider.overrideWith(_FeedWithRow.new),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (BuildContext c, WidgetRef ref, _) {
            ref.listen(pushTapDispatcherProvider, (_, _) {});
            ref.watch(authProvider);
            return MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('uk'),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (feedAlive) {
      container.listen(notificationsFeedProvider, (_, _) {});
      _FeedWithRow.marked.clear();
      await tester.pumpAndSettle();
    }
    return container;
  }

  _Pending pending(ProviderContainer c) =>
      c.read(pendingPushTapProvider.notifier) as _Pending;
}

void main() {
  tearDown(resetNotificationNavigationStateForTest);

  testWidgets('should_markReadAndOpenRouteForOutput_when_authenticated', (
    tester,
  ) async {
    final _Rig rig = _Rig();
    final ProviderContainer c = await rig.pump(tester);
    rig.pending(c).put(_bookingTap);
    await tester.pumpAndSettle();
    expect(rig.repo.markedRead, <String>[_id]);
    expect(rig.unread.refreshCalls, 1);
    expect(rig.seen.length, 1);
    expect(rig.seen.single, contains(RouteNames.masterBookingDetail(_bk)));
    expect(c.read(pendingPushTapProvider), isNull);
  });

  testWidgets('should_dispatchOnce_when_routerNotifiesAgain', (tester) async {
    final _Rig rig = _Rig();
    final ProviderContainer c = await rig.pump(tester);
    rig.pending(c).put(_bookingTap);
    await tester.pumpAndSettle();
    rig.router.go('/');
    await tester.pumpAndSettle();
    expect(rig.repo.markedRead.length, 1);
    expect(rig.seen.length, 1);
  });

  testWidgets('should_holdTapAtSplash_untilRouterLeavesIt', (tester) async {
    final _Rig rig = _Rig(initial: RouteNames.splash);
    final ProviderContainer c = await rig.pump(tester);
    rig.pending(c).put(_bookingTap);
    await tester.pumpAndSettle();
    expect(rig.seen, isEmpty);
    expect(rig.repo.markedRead, isEmpty);
    expect(c.read(pendingPushTapProvider), isNotNull);
    rig.router.go('/');
    await tester.pumpAndSettle();
    expect(rig.repo.markedRead, <String>[_id]);
    expect(rig.seen.length, 1);
  });

  testWidgets('should_dropTap_withoutNavigationOrMarkRead_when_anonymous', (
    tester,
  ) async {
    final _Rig rig = _Rig(role: null);
    final ProviderContainer c = await rig.pump(tester);
    rig.pending(c).put(_bookingTap);
    await tester.pumpAndSettle();
    expect(rig.seen, isEmpty);
    expect(rig.repo.markedRead, isEmpty);
    expect(c.read(pendingPushTapProvider), isNull);
  });

  testWidgets('should_stillNavigate_when_markReadThrows', (tester) async {
    final _Rig rig = _Rig(markReadError: const NetworkFailure());
    final ProviderContainer c = await rig.pump(tester);
    rig.pending(c).put(_bookingTap);
    await tester.pumpAndSettle();
    expect(rig.repo.markedRead, <String>[_id]);
    expect(rig.seen.length, 1);
    expect(rig.seen.single, contains(RouteNames.masterBookingDetail(_bk)));
  });

  testWidgets('should_openSalonReviews_when_ownerReviewReceivedPush', (
    tester,
  ) async {
    final _Rig rig = _Rig(role: UserRole.salonOwner);
    final ProviderContainer c = await rig.pump(tester);
    rig
        .pending(c)
        .put(
          const PushTap(
            notificationId: _id,
            type: AppNotificationType.reviewReceived,
            target: NotificationTarget.booking(bookingId: _bk, salonId: 'S1'),
          ),
        );
    await tester.pumpAndSettle();
    expect(rig.seen, <String>['/salons/S1/shell?tab=reviews']);
    expect(rig.repo.markedRead, <String>[_id]);
  });

  testWidgets('should_openStaffDetail_when_ownerBookingCreatedPush', (
    tester,
  ) async {
    final _Rig rig = _Rig(role: UserRole.salonOwner);
    final ProviderContainer c = await rig.pump(tester);
    rig
        .pending(c)
        .put(
          const PushTap(
            notificationId: _id,
            type: AppNotificationType.bookingCreated,
            target: NotificationTarget.booking(bookingId: _bk, salonId: 'S1'),
          ),
        );
    await tester.pumpAndSettle();
    expect(rig.seen.single, contains(RouteNames.salonStaffBookingDetail(_bk)));
  });

  testWidgets('should_openFeed_when_targetLeadsNowhere', (tester) async {
    final _Rig rig = _Rig();
    final ProviderContainer c = await rig.pump(tester);
    rig
        .pending(c)
        .put(
          const PushTap(
            notificationId: _id,
            type: AppNotificationType.unknown,
            target: NotificationTarget.none(),
          ),
        );
    await tester.pumpAndSettle();
    expect(rig.seen, <String>[RouteNames.notifications]);
    expect(rig.repo.markedRead, <String>[_id]);
  });

  testWidgets('should_openFeed_when_targetNotForRole', (tester) async {
    final _Rig rig = _Rig(role: UserRole.independentMaster);
    final ProviderContainer c = await rig.pump(tester);
    rig
        .pending(c)
        .put(
          const PushTap(
            notificationId: _id,
            type: AppNotificationType.reviewRequested,
            target: NotificationTarget.bookingReview(bookingId: _bk),
          ),
        );
    await tester.pumpAndSettle();
    expect(rig.seen, <String>[RouteNames.notifications]);
  });

  testWidgets('should_notRefreshUnreadCount_when_feedHoldsRow', (tester) async {
    final _Rig rig = _Rig(feedAlive: true);
    final ProviderContainer c = await rig.pump(tester);
    rig.pending(c).put(_bookingTap);
    await tester.pumpAndSettle();
    expect(_FeedWithRow.marked, <String>[_id]);
    expect(rig.repo.markedRead, isEmpty);
    expect(rig.unread.refreshCalls, 0, reason: 'feed markRead is optimistic');
    expect(rig.seen.length, 1);
  });

  testWidgets('should_openDestinationOnlyAfterAFrame', (tester) async {
    final _Rig rig = _Rig();
    final ProviderContainer c = await rig.pump(tester);
    int navigations = 0; // router-delegate notifications = navigation asked
    void spy() => navigations++;
    rig.router.routerDelegate.addListener(spy);
    addTearDown(() => rig.router.routerDelegate.removeListener(spy));
    rig.pending(c).put(_bookingTap);
    await tester.idle(); // microtasks only: no frame yet
    expect(c.read(pendingPushTapProvider), isNull, reason: 'consumed');
    expect(
      navigations,
      0,
      reason: 'the router must not be asked to navigate before a frame',
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(rig.seen.length, 1);
    expect(navigations, greaterThan(0));
  });
}
