// Phase 364 — tapping a notification opens the right EXISTING screen.
//
// The REAL `appRouterProvider` router, entered at a role's landing and then
// `push`ed to the feed (so the landing stays underneath, exactly like the
// bell). Navigation is detected by the resolved PAGE TYPE (never by a location
// string: a shadowed route keeps the string right while the wrong screen
// renders — memory: go_router literal-vs-dynamic shadowing) and by the id the
// page carries. `router.go` is never used to navigate; `push` leaves
// `fullPath` unchanged, so no location is read off the router.
//
// Booking detail loads are a never-completing read (the page type and its
// `bookingId` are what is asserted) except where a test scripts a failure.

import 'dart:async';

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/leave_review_screen.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/notifications/data/notification_repository.dart';
import 'package:beautica_mobile/features/notifications/domain/app_notification.dart';
import 'package:beautica_mobile/features/notifications/presentation/notifications_screen.dart';
import 'package:beautica_mobile/features/notifications/presentation/widgets/notification_tile.dart';
import 'package:beautica_mobile/features/notifications/presentation/unread_notifications_notifier.dart';
import 'package:beautica_mobile/features/rating/application/my_rating_notifier.dart';
import 'package:beautica_mobile/features/rating/domain/client_rating.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_shell_provider.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/l10n/app_localizations_uk.dart';
import 'package:beautica_mobile/features/notifications/presentation/notification_navigation.dart'
    show kFromNotificationQuery, kFromNotificationValue;
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/role_home.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_master_repository.dart';
import '../../../helpers/fakes/fake_notification_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import '../../../helpers/fakes/fake_service_repository.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/test_container.dart';
import '../../../helpers/velvet_snack_matchers.dart';

final AppLocalizations uk = AppLocalizationsUk();

const String _salonA = 'salon-a';
const String _salonB = 'salon-b';
const String _uuid = '00000000-0000-4000-8000-0000000000b1';

/// A booking read that is scripted per id: never completes by default, or
/// throws [errors]`[id]`. Records every id it is asked for.
class _BookingRepo implements BookingRepository {
  final Map<String, Object> errors = <String, Object>{};
  final List<String> asked = <String>[];

  @override
  Future<Booking> getBookingById(String id) {
    asked.add(id);
    final Object? error = errors[id];
    if (error != null) return Future<Booking>.error(error);
    return Completer<Booking>().future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unreachable from a notification tap');
}

class _Mys extends MySalons {
  @override
  Future<List<Salon>> build() async => const <Salon>[
    Salon(id: _salonA, name: 'Salon A', isPrimary: true),
    Salon(id: _salonB, name: 'Salon B'),
  ];
}

class _Profile extends SalonManagementProfile {
  @override
  Future<SalonManagementProfileData> build(String salonId) async =>
      (Salon(id: salonId, name: 'Salon $salonId'), const <SalonStaffMember>[]);
}

class _SettledMaster extends MasterProfile {
  @override
  Future<Master> build() async => const Master(
    id: 'u1',
    firstName: 'Test',
    lastName: 'Master',
    avgRating: 0,
    reviewCount: 0,
    type: MasterType.independentMaster,
  );
}

typedef _Harness = ({
  GoRouter router,
  ProviderContainer container,
  FakeNotificationRepository repo,
  _BookingRepo bookings,
  RecordingUnread unread,
});

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  // fixed-wait-ok: two route-transition lengths (Material page transitions are
  // ~300 ms and a pushed detail never settles — its skeleton shimmers forever,
  // so pumpAndSettle is unusable); the post-frame onUnavailable hop rides them.
  await tester.pump(const Duration(milliseconds: 400));
  // fixed-wait-ok: second transition slice, see above.
  await tester.pump(const Duration(milliseconds: 400));
}

/// Lands [role], then PUSHES the feed on top of the landing (the bell's way).
Future<_Harness> _open(
  WidgetTester tester,
  UserRole role,
  List<AppNotification> items, {
  int unread = 3,
}) async {
  final FakeNotificationRepository repo = FakeNotificationRepository(
    pages: <NotificationPage>[onePage(items)],
    unread: unread,
  );
  final _BookingRepo bookings = _BookingRepo();
  final RecordingUnread bell = RecordingUnread(unread);
  final ProviderContainer container = makeTestContainer(
    retry: (_, _) => null,
    overrides: <Object>[
      authProvider.overrideWith(
        () => FixedRoleAuth(
          role,
          salonId: role == UserRole.salonAdmin ? _salonA : null,
        ),
      ),
      authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
      secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
      notificationRepositoryProvider.overrideWithValue(repo),
      unreadNotificationsProvider.overrideWith(() => bell),
      clockProvider.overrideWithValue(() => DateTime.utc(2026, 9, 30, 12)),
      bookingRepositoryProvider.overrideWithValue(bookings),
      // Landing data, settled (see role_landing_chrome_test.dart).
      masterProfileProvider.overrideWith(_SettledMaster.new),
      masterRepositoryProvider.overrideWith((_) => FakeMasterRepository()),
      serviceRepositoryProvider.overrideWith((_) => FakeServiceRepository()),
      publicServiceRepositoryProvider.overrideWith(
        (_) => FakeServiceRepository(),
      ),
      approvedCategoriesProvider.overrideWith(
        (_) async => const <ServiceCategoryOption>[],
      ),
      clientProfileProvider.overrideWith(
        (_) async => const ClientProfileSummary(
          firstName: 'Test',
          lastName: 'Client',
          city: '',
          phone: '',
          clientRating: null,
          memberSinceYear: 2026,
        ),
      ),
      nextAppointmentProvider.overrideWith((_) async => null),
      favoriteMastersProvider.overrideWith(
        (_) async => const <FavoriteMasterItem>[],
      ),
      beautyTimelineProvider.overrideWith((_) async => const <TimelineEntry>[]),
      myRatingProvider.overrideWith((_) async => const ClientRating()),
      mySalonsProvider.overrideWith(_Mys.new),
      salonManagementProfileProvider(_salonA).overrideWith(_Profile.new),
      salonManagementProfileProvider(_salonB).overrideWith(_Profile.new),
    ],
  );
  final GoRouter router = container.read(appRouterProvider);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
      ),
    ),
  );
  await _frames(tester);
  unawaited(router.push<Object?>(RouteNames.notifications));
  await _frames(tester);
  expect(find.byType(NotificationsScreen), findsOneWidget);
  return (
    router: router,
    container: container,
    repo: repo,
    bookings: bookings,
    unread: bell,
  );
}

Finder _tile(String id) => find.byKey(Key('notification-tile-$id'));

Finder _detail(String bookingId) => find.byWidgetPredicate(
  (Widget w) => w is BookingDetailScreen && w.bookingId == bookingId,
);

NotificationTarget _bookingTarget({String? salonId, String? appointmentId}) =>
    NotificationTarget.booking(
      bookingId: 'bk-1',
      salonId: salonId,
      appointmentId: appointmentId,
    );

Future<void> _tapAndSettle(WidgetTester tester, String id) async {
  await tester.ensureVisible(_tile(id));
  await tester.tap(_tile(id));
  await _frames(tester);
}

bool _isRead(_Harness h, String id) => h.repo.markedRead.contains(id);

void main() {
  setUp(
    () => AppStartTime.setStartForTest(
      DateTime.now().subtract(const Duration(seconds: 5)),
    ),
  );
  tearDown(AppStartTime.resetForTest);

  group('BookingDetailScreen.onUnavailable', () {
    Future<_BookingRepo> pumpDetail(
      WidgetTester tester, {
      VoidCallback? onUnavailable,
    }) async {
      final _BookingRepo repo = _BookingRepo()
        ..errors['bk-1'] = const NotFoundFailure();
      await tester.pumpApp(
        BookingDetailScreen(bookingId: 'bk-1', onUnavailable: onUnavailable),
        retry: (_, _) => null,
        overrides: <Object>[bookingRepositoryProvider.overrideWithValue(repo)],
      );
      await tester.pump();
      await tester.pump();
      return repo;
    }

    testWidgets('should_keepTodaysErrorState_when_noCallbackGiven', (
      WidgetTester tester,
    ) async {
      await pumpDetail(tester);
      expect(
        find.byKey(const Key('booking-detail-error-retry')),
        findsOneWidget,
      );
    });

    testWidgets('should_callOnUnavailableOnce_andNotShowError_when_404', (
      WidgetTester tester,
    ) async {
      int calls = 0;
      await pumpDetail(tester, onUnavailable: () => calls++);
      await tester.pump();
      expect(calls, 1);
      expect(find.byKey(const Key('booking-detail-error-retry')), findsNothing);
    });
  });

  group('booking target opens BookingDetailScreen for each role', () {
    for (final UserRole role in <UserRole>[
      UserRole.client,
      UserRole.independentMaster,
      UserRole.salonOwner,
      UserRole.salonAdmin,
      UserRole.salonMaster,
    ]) {
      testWidgets(
        'should_openBookingDetail_andMarkRead_when_bookingTargetTapped '
        '(${role.name})',
        (WidgetTester tester) async {
          final _Harness h = await _open(tester, role, <AppNotification>[
            notif('n1', target: _bookingTarget(salonId: _salonA)),
          ]);

          await _tapAndSettle(tester, 'n1');

          expect(_detail('bk-1'), findsOneWidget);
          expect(h.bookings.asked, contains('bk-1'));
          // Optimistic mark-read ran, and the bell followed.
          expect(_isRead(h, 'n1'), isTrue);
          expect(h.unread.calls, contains('dec:u1'));
          // Back returns to the feed for EVERY role (the client rides the
          // feed-scoped alias route), the item stays read, the bell stays down.
          expect(
            find.byType(NotificationsScreen, skipOffstage: false),
            findsOneWidget,
          );
          h.router.pop();
          await _frames(tester);
          expect(find.byType(BookingDetailScreen), findsNothing);
          expect(find.byType(NotificationsScreen), findsOneWidget);
          expect(_isRead(h, 'n1'), isTrue);
          expect(
            h.unread.calls.where((String c) => c == 'dec:u1'),
            hasLength(1),
          );
        },
      );
    }
  });

  testWidgets('should_openReviewFlow_when_reviewTargetTapped', (
    WidgetTester tester,
  ) async {
    final _Harness h = await _open(tester, UserRole.client, <AppNotification>[
      notif(
        'n1',
        type: AppNotificationType.reviewRequested,
        target: const NotificationTarget.bookingReview(bookingId: 'bk-1'),
      ),
    ]);

    await _tapAndSettle(tester, 'n1');

    expect(
      find.byWidgetPredicate(
        (Widget w) => w is LeaveReviewScreen && w.bookingId == 'bk-1',
      ),
      findsOneWidget,
    );
    expect(find.byType(BookingDetailScreen), findsNothing);
    expect(_isRead(h, 'n1'), isTrue);
    expect(h.unread.calls, contains('dec:u1'));
  });

  testWidgets(
    'should_backToFeed_withItemReadAndBellDecremented_when_clientReviewTarget',
    (WidgetTester tester) async {
      // A `push` of the nested review alias adds just that page (memory:
      // go_router push excludes the parent), so Back lands on the feed.
      final _Harness h = await _open(tester, UserRole.client, <AppNotification>[
        notif(
          'n1',
          type: AppNotificationType.reviewRequested,
          target: const NotificationTarget.bookingReview(bookingId: 'bk-1'),
        ),
      ]);

      await _tapAndSettle(tester, 'n1');
      expect(find.byType(LeaveReviewScreen), findsOneWidget);

      h.router.pop();
      await _frames(tester);
      expect(find.byType(LeaveReviewScreen), findsNothing);
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(_isRead(h, 'n1'), isTrue);
      expect(h.unread.calls.where((String c) => c == 'dec:u1'), hasLength(1));
    },
  );

  testWidgets('should_onlyMarkRead_noSnack_when_unknownTypeNoTargetTapped', (
    WidgetTester tester,
  ) async {
    final _Harness h =
        await _open(tester, UserRole.independentMaster, <AppNotification>[
          notif(
            'n1',
            type: AppNotificationType.unknown,
            target: const NotificationTarget.none(),
          ),
        ]);

    await _tapAndSettle(tester, 'n1');

    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(find.byType(BookingDetailScreen), findsNothing);
    expect(_isRead(h, 'n1'), isTrue);
    await tester.pump();
    // fixed-wait-ok: one snack-entrance length; a snack would be mounted by now.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(VelvetSnack), findsNothing);
    expect(find.text(uk.notificationsBookingUnavailable), findsNothing);
  });

  testWidgets('should_markReadAndSnackbar_when_bookingTypeHasNoTarget', (
    WidgetTester tester,
  ) async {
    final _Harness h = await _open(tester, UserRole.client, <AppNotification>[
      notif(
        'n1',
        type: AppNotificationType.bookingDeclined,
        target: const NotificationTarget.none(),
      ),
    ]);

    await _tapAndSettle(tester, 'n1');

    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(find.byType(BookingDetailScreen), findsNothing);
    expect(_isRead(h, 'n1'), isTrue);
    expectVelvetSnack(uk.notificationsBookingUnavailable);
    await pumpPastVelvetSnack(tester);
  });

  testWidgets(
    'should_markReadAndSnackbar_stayOnFeed_when_bookingNoLongerVisible',
    (WidgetTester tester) async {
      final _Harness h = await _open(tester, UserRole.client, <AppNotification>[
        // The backend nulled the params: the viewer lost access.
        notif('n1', target: _bookingTarget(), params: NotificationParams.empty),
      ]);

      await _tapAndSettle(tester, 'n1');

      expect(find.byType(BookingDetailScreen), findsNothing);
      expect(h.bookings.asked, isEmpty, reason: 'no push, no detail load');
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(_isRead(h, 'n1'), isTrue);
      expectVelvetSnack(uk.notificationsBookingUnavailable);
      await pumpPastVelvetSnack(tester);
    },
  );

  group('detail answers 403/404 after the push', () {
    for (final UserRole role in <UserRole>[
      UserRole.client,
      UserRole.salonMaster,
    ]) {
      for (final (String, Object) failure in <(String, Object)>[
        ('404', const NotFoundFailure()),
        (
          '403',
          UnknownFailure(
            cause: DioException(
              requestOptions: RequestOptions(path: '/bookings/bk-1'),
              response: Response<Object?>(
                requestOptions: RequestOptions(path: '/bookings/bk-1'),
                statusCode: 403,
              ),
            ),
          ),
        ),
      ]) {
        testWidgets(
          'should_popToFeedWithSnackbar_when_detailReturns${failure.$1} '
          '(${role.name})',
          (WidgetTester tester) async {
            final _Harness h = await _open(tester, role, <AppNotification>[
              notif('n1', target: _bookingTarget()),
            ]);
            h.bookings.errors['bk-1'] = failure.$2;

            await tester.tap(_tile('n1'));
            await _frames(tester);
            await _frames(tester);

            expect(find.byType(BookingDetailScreen), findsNothing);
            expect(find.byType(NotificationsScreen), findsOneWidget);
            expect(_isRead(h, 'n1'), isTrue);
            expectVelvetSnack(uk.notificationsBookingUnavailable);
            await pumpPastVelvetSnack(tester);
          },
        );
      }
    }
  });

  testWidgets('should_keepReadState_when_navigationFails', (
    WidgetTester tester,
  ) async {
    // A 500 is NOT "unavailable": the detail keeps its retryable error state
    // and the feed row must stay read regardless.
    final _Harness h = await _open(tester, UserRole.client, <AppNotification>[
      notif('n1', target: _bookingTarget()),
    ]);
    h.bookings.errors['bk-1'] = const ServerFailure(statusCode: 500);

    await tester.tap(_tile('n1'));
    await _frames(tester);

    expect(_detail('bk-1'), findsOneWidget);
    expect(find.byKey(const Key('booking-detail-error-retry')), findsOneWidget);
    h.router.pop();
    await _frames(tester);
    expect(_isRead(h, 'n1'), isTrue);
    expect(h.unread.calls.where((String c) => c == 'inc:u1'), isEmpty);
  });

  testWidgets(
    'should_openVisitDetail_viaRepresentativeBooking_when_multiServiceItem',
    (WidgetTester tester) async {
      final _Harness h =
          await _open(tester, UserRole.independentMaster, <AppNotification>[
            notif(
              'n1',
              target: _bookingTarget(appointmentId: 'ap-1'),
              params: NotificationParams(
                counterpartName: 'Олена',
                serviceName: 'Манікюр',
                serviceCount: 3,
                startsAt: DateTime.utc(2026, 10, 3, 11, 30),
              ),
            ),
          ]);

      await _tapAndSettle(tester, 'n1');

      expect(_detail('bk-1'), findsOneWidget);
      expect(h.bookings.asked, <String>['bk-1']);
    },
  );

  group('salon owner, salon A active (its shell is under the feed)', () {
    testWidgets(
      'should_openSalonBBookingDetail_withoutChangingActiveSalon_when_'
      'salonAIsActive',
      (WidgetTester tester) async {
        final _Harness h = await _open(
          tester,
          UserRole.salonOwner,
          <AppNotification>[
            notif('n1', target: _bookingTarget(salonId: _salonB)),
          ],
        );
        expect(
          find.byWidgetPredicate(
            (Widget w) => w is SalonShellScreen && w.salonId == _salonA,
            skipOffstage: false,
          ),
          findsOneWidget,
          reason: 'precondition: the owner is inside salon A',
        );

        await _tapAndSettle(tester, 'n1');

        expect(_detail('bk-1'), findsOneWidget);
        // Salon A is still the one mounted, and salon B was never entered.
        expect(
          find.byWidgetPredicate(
            (Widget w) => w is SalonShellScreen && w.salonId == _salonA,
            skipOffstage: false,
          ),
          findsOneWidget,
        );
        expect(
          find.byWidgetPredicate(
            (Widget w) => w is SalonShellScreen && w.salonId == _salonB,
            skipOffstage: false,
          ),
          findsNothing,
        );
        expect(h.container.read(salonShellProvider(_salonA)), 0);
        expect(h.container.read(salonShellProvider(_salonB)), 0);
        // Back lands on the feed, then on salon A.
        h.router.pop();
        await _frames(tester);
        expect(find.byType(NotificationsScreen), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (Widget w) => w is SalonShellScreen && w.salonId == _salonB,
            skipOffstage: false,
          ),
          findsNothing,
        );
      },
    );

    testWidgets('should_openTeamTab_forSalon_when_salonTeamTargetTapped', (
      WidgetTester tester,
    ) async {
      final _Harness h =
          await _open(tester, UserRole.salonAdmin, <AppNotification>[
            notif(
              'n1',
              type: AppNotificationType.inviteAccepted,
              target: const NotificationTarget.salonTeam(salonId: _salonA),
            ),
          ]);

      await _tapAndSettle(tester, 'n1');

      expect(
        find.byWidgetPredicate(
          (Widget w) => w is SalonShellScreen && w.salonId == _salonA,
        ),
        findsOneWidget,
      );
      expect(h.container.read(salonShellProvider(_salonA)), 2);
      expect(h.container.read(salonManageTabProvider(_salonA)), 1);
      expect(_isRead(h, 'n1'), isTrue);
    });

    testWidgets(
      'should_notLeakTeamTab_when_salonReopenedNormally_afterLeavingViaGo',
      (WidgetTester tester) async {
        final _Harness h =
            await _open(tester, UserRole.salonOwner, <AppNotification>[
              notif(
                'n1',
                type: AppNotificationType.inviteAccepted,
                target: const NotificationTarget.salonTeam(salonId: _salonB),
              ),
            ]);
        await _tapAndSettle(tester, 'n1');
        expect(h.container.read(salonShellProvider(_salonB)), 2);

        // Leave the shell WITHOUT popping (logout / redirect / salon switch).
        h.router.go(RouteNames.mySalons);
        await _frames(tester);
        await _frames(tester);
        expect(
          find.byWidgetPredicate(
            (Widget w) => w is SalonShellScreen && w.salonId == _salonB,
            skipOffstage: false,
          ),
          findsNothing,
        );

        // Reopen the same salon normally (no tab request) — default tab, not
        // «Команда». Nothing was held alive, so the providers rebuilt to 0.
        h.router.go(RouteNames.salonShell(_salonB));
        await _frames(tester);
        await _frames(tester);
        expect(
          find.byWidgetPredicate(
            (Widget w) => w is SalonShellScreen && w.salonId == _salonB,
          ),
          findsOneWidget,
        );
        expect(h.container.read(salonShellProvider(_salonB)), 0);
        expect(h.container.read(salonManageTabProvider(_salonB)), 0);
      },
    );

    testWidgets(
      'should_openSalonBTeamTab_when_salonTeamTargetForSalonB_whileAActive',
      (WidgetTester tester) async {
        final _Harness h =
            await _open(tester, UserRole.salonOwner, <AppNotification>[
              notif(
                'n1',
                type: AppNotificationType.inviteAccepted,
                target: const NotificationTarget.salonTeam(salonId: _salonB),
              ),
            ]);

        await _tapAndSettle(tester, 'n1');

        expect(
          find.byWidgetPredicate(
            (Widget w) => w is SalonShellScreen && w.salonId == _salonB,
          ),
          findsOneWidget,
          reason: 'navigating INTO salon B is the point of a team item',
        );
        expect(h.container.read(salonShellProvider(_salonB)), 2);
        expect(h.container.read(salonManageTabProvider(_salonB)), 1);
        // Salon A's own tab selection is untouched.
        expect(h.container.read(salonShellProvider(_salonA)), 0);
      },
    );
  });

  testWidgets('should_pushOnlyOneDestination_when_tileTappedTwiceInOneFrame', (
    WidgetTester tester,
  ) async {
    final _Harness h = await _open(tester, UserRole.client, <AppNotification>[
      notif('n1', target: _bookingTarget()),
    ]);

    await tester.ensureVisible(_tile('n1'));
    await tester.tap(_tile('n1'));
    await tester.tap(_tile('n1'));
    await _frames(tester);

    expect(_detail('bk-1'), findsOneWidget);
    h.router.pop();
    await _frames(tester);
    expect(find.byType(BookingDetailScreen), findsNothing);
    expect(find.byType(NotificationsScreen), findsOneWidget);
  });

  testWidgets('should_releaseGuardAfterPush_when_pushFutureNeverCompletes', (
    WidgetTester tester,
  ) async {
    final _Harness h = await _open(tester, UserRole.client, <AppNotification>[
      notif('n1', target: _bookingTarget()),
      notif('n2', target: _bookingTarget()),
    ]);

    await _tapAndSettle(tester, 'n1');
    expect(_detail('bk-1'), findsOneWidget);

    // The first tap's push future is still PENDING (destination on the
    // stack, never popped — exactly the state a `go()` replacement leaves
    // behind). The feed is offstage, so fire n2's tile callback directly on
    // the SAME screen state: the guard must already be released.
    final NotificationTile n2 = tester.widget<NotificationTile>(
      find.byKey(const Key('notification-tile-n2'), skipOffstage: false),
    );
    n2.onOpen!();
    await _frames(tester);

    expect(
      find.byType(BookingDetailScreen, skipOffstage: false),
      findsNWidgets(2),
    );
    expect(_isRead(h, 'n2'), isTrue);
  });

  testWidgets(
    'should_snackAndGoHome_notStickOnSkeleton_when_unavailableWithNothingToPop',
    (WidgetTester tester) async {
      final _Harness h = await _open(
        tester,
        UserRole.salonMaster,
        <AppNotification>[notif('n1', target: _bookingTarget())],
      );
      h.bookings.errors['bk-1'] = const NotFoundFailure();

      // A cold entry: `go` leaves nothing underneath to pop to.
      h.router.go(
        '${RouteNames.salonMasterBookingDetail('bk-1')}'
        '?$kFromNotificationQuery=$kFromNotificationValue',
      );
      await _frames(tester);
      await _frames(tester);

      expect(find.byType(BookingDetailScreen), findsNothing);
      expect(
        h.router.routeInformationProvider.value.uri.path,
        roleHomePath(UserRole.salonMaster),
      );
      expectVelvetSnack(uk.notificationsBookingUnavailable);
      await pumpPastVelvetSnack(tester);
    },
  );

  // Security L3 — the alias routes carry their OWN `clientOnlyGuard`, a second
  // layer independent of `authRedirect`'s `/notifications/bookings` prefix gate.
  group('alias routes bounce a non-client (per-route guard)', () {
    for (final UserRole role in <UserRole>[
      UserRole.independentMaster,
      UserRole.salonOwner,
      UserRole.salonAdmin,
      UserRole.salonMaster,
    ]) {
      for (final String location in <String>[
        RouteNames.notificationBookingDetail(_uuid),
        RouteNames.notificationBookingReview(_uuid),
      ]) {
        testWidgets(
          'should_bounceToLanding_when_${role.name}_goes_to_$location',
          (WidgetTester tester) async {
            final _Harness h = await _open(tester, role, <AppNotification>[]);

            h.router.go(location);
            await _frames(tester);
            await _frames(tester);

            expect(find.byType(BookingDetailScreen), findsNothing);
            expect(find.byType(LeaveReviewScreen), findsNothing);
            expect(h.bookings.asked, isEmpty);
            expect(
              h.router.routeInformationProvider.value.uri.path,
              // A salon home resolves one hop further, so assert "left the feed".
              isNot(startsWith(RouteNames.notifications)),
            );
          },
        );
      }
    }
  });
}
