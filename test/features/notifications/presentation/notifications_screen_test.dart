// Phase 363 — the «Сповіщення» feed screen.
//
// Every test builds the real screen + real feed notifier over a scriptable
// repository ([FakeNotificationRepository]). The bell's count notifier is a
// recording double ([RecordingUnread]) so the assertions can see exactly which
// `setCount` / `decrement` calls were made and for WHICH USER.
//
// Explicit pumps only. `pumpAndSettle` is used solely while nothing animates
// forever (a footer spinner never settles) and it fires no Timer, so every
// countdown is driven by [_advance].
//
// Copy is looked up through [uk] (the generated Ukrainian localizations), never
// by a Cyrillic literal in a finder.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/my_bookings_states.dart';
import 'package:beautica_mobile/features/notifications/data/notification_repository.dart';
import 'package:beautica_mobile/features/notifications/domain/app_notification.dart';
import 'package:beautica_mobile/features/notifications/presentation/notifications_feed_notifier.dart';
import 'package:beautica_mobile/features/notifications/presentation/notifications_screen.dart';
import 'package:beautica_mobile/features/notifications/presentation/unread_notifications_notifier.dart';
import 'package:beautica_mobile/features/notifications/presentation/widgets/notification_feed_parts.dart';
import 'package:beautica_mobile/features/notifications/presentation/widgets/notification_tile.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/l10n/app_localizations_uk.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_notification_repository.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/velvet_snack_matchers.dart';

final AppLocalizations uk = AppLocalizationsUk();

/// A server-supplied name as the feed shows it: isolated (FSI..PDI) so it can
/// never reorder the sentence. Spelled with char codes, never literal bidi
/// characters.
String iso(String s) =>
    '${String.fromCharCode(0x2068)}$s${String.fromCharCode(0x2069)}';

/// A fixed "now": 12:00Z on 2026-09-30 = 15:00 in Kyiv, so Kyiv "today" is
/// 30 September whatever zone the host runs in. Advanced only by [_advance].
final DateTime _start = DateTime.utc(2026, 9, 30, 12);
DateTime _clockNow = _start;

const Duration _second = Duration(seconds: 1);
const Duration _flip = Duration(milliseconds: 400);

Future<void> _advance(WidgetTester tester, int seconds) async {
  for (int i = 0; i < seconds; i++) {
    _clockNow = _clockNow.add(_second);
    await tester.pump(_second);
  }
}

class _CountingObserver extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }
}

typedef _Harness = ({
  ProviderContainer container,
  FakeNotificationRepository repo,
  RecordingUnread unread,
});

List<Object> _overrides(
  FakeNotificationRepository repo,
  RecordingUnread unread,
  UserRole role,
  String? salonId,
) => <Object>[
  authProvider.overrideWith(() => FixedRoleAuth(role, salonId: salonId)),
  notificationRepositoryProvider.overrideWithValue(repo),
  unreadNotificationsProvider.overrideWith(() => unread),
  clockProvider.overrideWithValue(() => _clockNow),
];

Future<_Harness> _pumpFeed(
  WidgetTester tester,
  FakeNotificationRepository repo, {
  UserRole role = UserRole.independentMaster,
  int unread = 0,
  String? salonId,
  bool settle = true,
  double? width,
  double? height,
  Locale locale = const Locale('uk'),
}) async {
  final RecordingUnread fake = RecordingUnread(unread);
  await tester.pumpApp(
    const NotificationsScreen(),
    width: width,
    height: height,
    locale: locale,
    // A failed first page must surface, not be retried away by the policy.
    retry: (int _, Object _) => null,
    overrides: _overrides(repo, fake, role, salonId),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
  final ProviderContainer container = ProviderScope.containerOf(
    tester.element(find.byType(NotificationsScreen)),
  );
  return (container: container, repo: repo, unread: fake);
}

FakeNotificationRepository _repoOf(
  List<AppNotification> items, {
  int unread = 0,
}) => FakeNotificationRepository(
  pages: <NotificationPage>[onePage(items)],
  unread: unread,
);

/// Two pages (20 read rows, then 2) whose second fetch fails with [pageTwoError].
FakeNotificationRepository _pagedRepo(Object pageTwoError) {
  List<AppNotification> rows(String prefix, int n, int day) =>
      <AppNotification>[
        for (int i = 0; i < n; i++)
          notif(
            '$prefix$i',
            read: true,
            createdAt: DateTime.utc(2026, 9, day, 10, 59 - i),
          ),
      ];
  return FakeNotificationRepository(
    pages: <NotificationPage>[
      pageOf(0, 2, rows('a', 20, 30)),
      pageOf(1, 2, rows('b', 2, 29)),
    ],
  )..fetchErrors[1] = pageTwoError;
}

Finder _tile(String id) => find.byKey(Key('notification-tile-$id'));
Finder _check(String id) => find.byKey(NotificationTile.markReadKey(id));

bool _readInState(_Harness h, String id) => h.container
    .read(notificationsFeedProvider)
    .value!
    .items
    .firstWhere((AppNotification n) => n.id == id)
    .read;

/// Scrolls the list to its far end and lets the lazily built footer fire.
Future<void> _scrollToEnd(WidgetTester tester) async {
  await tester.drag(
    find.byKey(NotificationsScreen.listKey),
    const Offset(0, -6000),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() => _clockNow = _start);

  group('rendering', () {
    testWidgets('should_renderEveryType_withItsTitle_forAProvider', (
      WidgetTester tester,
    ) async {
      final Map<AppNotificationType, String>
      expected = <AppNotificationType, String>{
        AppNotificationType.bookingCreated: uk.notificationTitleBookingCreated,
        AppNotificationType.bookingCancelledByClient:
            uk.notificationTitleCancelledByClient,
        AppNotificationType.bookingDeclined:
            uk.notificationTitleDeclinedProvider,
        AppNotificationType.bookingRescheduled:
            uk.notificationTitleRescheduledProvider,
        AppNotificationType.inviteAccepted: uk.notificationTitleInviteAccepted,
        AppNotificationType.bookingNotCompleted:
            uk.notificationTitleNotCompleted,
        AppNotificationType.reviewRequested:
            uk.notificationTitleReviewRequested,
        AppNotificationType.reviewReceived: uk.notificationTitleReviewReceived,
        AppNotificationType.bookingCancelledSalonClosed:
            uk.notificationTitleSalonClosed,
        AppNotificationType.bookingCancelledMasterRemoved:
            uk.notificationTitleMasterRemoved,
        AppNotificationType.unknown: uk.notificationTitleUnknown,
      };
      int i = 0;
      final List<AppNotification> items = <AppNotification>[
        for (final AppNotificationType t in expected.keys)
          notif('n${i++}', type: t, read: true),
      ];
      await _pumpFeed(tester, _repoOf(items), width: 400, height: 4000);

      for (final String title in expected.values) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
    });

    testWidgets('should_renderClientCopy_forAClient', (
      WidgetTester tester,
    ) async {
      await _pumpFeed(
        tester,
        _repoOf(<AppNotification>[
          notif('d', type: AppNotificationType.bookingDeclined),
          notif('r', type: AppNotificationType.bookingRescheduled),
        ]),
        role: UserRole.client,
        width: 600,
        height: 1200,
      );

      expect(find.text(uk.notificationTitleDeclinedClient), findsOneWidget);
      expect(find.text(uk.notificationTitleRescheduledClient), findsOneWidget);
      // A client reads service first and the provider last.
      expect(
        find.text(
          uk.notificationBodyClientRescheduled(
            iso('Олена Коваль'),
            iso('Манікюр'),
            'сб, 3 жовтня, 14:30',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('should_composeProviderBody_withPlusN_inKyivTime', (
      WidgetTester tester,
    ) async {
      await _pumpFeed(
        tester,
        _repoOf(<AppNotification>[
          notif(
            'n1',
            params: NotificationParams(
              counterpartName: 'Олена Коваль',
              serviceName: 'Манікюр',
              serviceCount: 3,
              // 23:30Z on the 2nd is 02:30 on the 3rd in Kyiv (UTC+3).
              startsAt: DateTime.utc(2026, 10, 2, 23, 30),
            ),
          ),
        ]),
        width: 800,
      );

      expect(
        find.text(
          uk.notificationBodyProvider(
            iso('Олена Коваль'),
            uk.notificationServiceWithExtra(iso('Манікюр'), 2),
            'сб, 3 жовтня, 02:30',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('should_showParamsGone_andNoTargetHint_when_paramsAreNull', (
      WidgetTester tester,
    ) async {
      await _pumpFeed(
        tester,
        _repoOf(<AppNotification>[
          notif(
            'n1',
            params: NotificationParams.empty,
            target: const NotificationTarget.none(),
          ),
        ]),
      );

      expect(find.text(uk.notificationsParamsGone), findsOneWidget);
      expect(find.text(uk.notificationsNoTarget), findsOneWidget);
    });

    testWidgets('should_renderInviteAccepted_withRole', (
      WidgetTester tester,
    ) async {
      await _pumpFeed(
        tester,
        _repoOf(<AppNotification>[
          notif(
            'n1',
            type: AppNotificationType.inviteAccepted,
            params: const NotificationParams(
              subjectName: 'Ірина',
              subjectRole: 'SALON_ADMIN',
              salonName: 'Beautica Центр',
            ),
            target: const NotificationTarget.salonTeam(salonId: 's1'),
          ),
        ]),
        role: UserRole.salonOwner,
        width: 800,
      );

      expect(
        find.text(
          uk.notificationBodyInviteAccepted(
            iso('Ірина'),
            uk.notificationRoleSalonAdmin,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('should_groupByKyivDay_withTodayYesterdayAndDateHeaders', (
      WidgetTester tester,
    ) async {
      await _pumpFeed(
        tester,
        _repoOf(<AppNotification>[
          notif('a', createdAt: DateTime.utc(2026, 9, 30, 9)),
          // 21:30Z on the 29th is 00:30 on the 30th in Kyiv: still «today».
          notif('b', createdAt: DateTime.utc(2026, 9, 29, 21, 30)),
          notif('c', createdAt: DateTime.utc(2026, 9, 29, 9)),
          notif('d', createdAt: DateTime.utc(2026, 9, 28, 9)),
        ]),
        width: 400,
        height: 1200,
      );

      expect(find.text(uk.relativeDateToday), findsOneWidget);
      expect(find.text(uk.relativeDateYesterday), findsOneWidget);
      const String monday28 = 'Пн, 28 вересня';
      expect(find.text(monday28), findsOneWidget);
    });

    testWidgets('should_hideSalonLabel_when_salonNameNull', (
      WidgetTester tester,
    ) async {
      await _pumpFeed(tester, _repoOf(<AppNotification>[notif('n1')]));

      expect(find.byType(SalonLabel), findsNothing);
    });

    testWidgets(
      'should_showItemsFromBothSalons_withSalonLabels_andCombinedCount_forOwnerWithTwoSalons',
      (WidgetTester tester) async {
        NotificationParams at(String salon) => NotificationParams(
          counterpartName: 'Олена Коваль',
          serviceName: 'Манікюр',
          serviceCount: 1,
          startsAt: DateTime.utc(2026, 10, 3, 11, 30),
          salonName: salon,
        );
        await _pumpFeed(
          tester,
          _repoOf(<AppNotification>[
            notif('a', params: at('Beautica Центр')),
            notif('b', params: at('Beautica Оболонь')),
            notif('c', params: at('Beautica Центр')),
          ]),
          role: UserRole.salonOwner,
          unread: 3,
          salonId: 's1',
          width: 800,
          height: 1000,
        );

        // Salon names are data (from the backend), not UI copy.
        final String centre = iso('Beautica Центр');
        final String obolon = iso('Beautica Оболонь');
        expect(find.text(centre), findsNWidgets(2));
        expect(find.text(obolon), findsOneWidget);
        // One combined count across both salons.
        expect(find.text(uk.notificationsUnreadCount(3)), findsOneWidget);
      },
    );

    testWidgets('should_keepFeedAndCount_when_activeSalonSwitched', (
      WidgetTester tester,
    ) async {
      final FakeNotificationRepository repo = _repoOf(<AppNotification>[
        notif('a'),
        notif('b'),
      ]);
      final _Harness h = await _pumpFeed(
        tester,
        repo,
        role: UserRole.salonOwner,
        unread: 2,
        salonId: 's1',
      );
      expect(repo.fetchedPages, <int>[0]);

      (h.container.read(authProvider.notifier) as FixedRoleAuth).switchSalon(
        's2',
      );
      await tester.pumpAndSettle();

      expect(repo.fetchedPages, <int>[
        0,
      ], reason: 'no refetch on a salon switch');
      expect(_tile('a'), findsOneWidget);
      expect(_tile('b'), findsOneWidget);
      expect(h.unread.calls, isEmpty, reason: 'the count is not reset either');
      expect(h.container.read(unreadNotificationsProvider).value, 2);
    });
  });

  group('states', () {
    testWidgets('should_showSkeleton_whileLoading', (
      WidgetTester tester,
    ) async {
      final FakeNotificationRepository repo = _repoOf(<AppNotification>[])
        ..pageGate = Completer<void>();
      await _pumpFeed(tester, repo, settle: false);

      expect(find.byType(BookingsSkeleton), findsOneWidget);
      expect(find.byType(NotificationsSkeletonRow), findsWidgets);

      repo.pageGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(BookingsSkeleton), findsNothing);
    });

    testWidgets('should_showEmptyState_when_noNotifications', (
      WidgetTester tester,
    ) async {
      await _pumpFeed(tester, _repoOf(<AppNotification>[]));

      expect(find.byKey(NotificationsScreen.emptyKey), findsOneWidget);
      expect(find.text(uk.notificationsEmptyTitle), findsOneWidget);
      expect(find.byKey(NotificationsMarkAllBar.actionKey), findsNothing);
    });

    testWidgets('should_showErrorWithRetry_thenRecover', (
      WidgetTester tester,
    ) async {
      final FakeNotificationRepository repo = _repoOf(<AppNotification>[
        notif('n1'),
      ])..fetchErrors[0] = const NetworkFailure();
      await _pumpFeed(tester, repo);

      expect(find.byKey(const Key('my_bookings_error')), findsOneWidget);
      await tester.tap(find.byKey(const Key('my_bookings_error_retry')));
      await tester.pumpAndSettle();

      expect(_tile('n1'), findsOneWidget);
      expect(repo.fetchedPages, <int>[0, 0]);
    });

    testWidgets('should_disableRetryWithCountdown_when_429OnOpen', (
      WidgetTester tester,
    ) async {
      final FakeNotificationRepository repo =
          _repoOf(<AppNotification>[notif('n1')])
            ..fetchErrors[0] = const NotificationsRateLimitedFailure(
              retryAfterSeconds: 12,
            );
      await _pumpFeed(tester, repo, settle: false);

      expect(find.text(uk.boardRetryCooldown(12)), findsOneWidget);
      // The disabled button swallows the tap.
      await tester.tap(find.byKey(const Key('my_bookings_error_retry')));
      await tester.pump();
      expect(repo.fetchedPages, <int>[0]);

      await _advance(tester, 12);
      expect(find.text(uk.retryLabel), findsOneWidget);
      await tester.tap(find.byKey(const Key('my_bookings_error_retry')));
      await tester.pumpAndSettle();
      expect(_tile('n1'), findsOneWidget);
    });
  });

  group('mark read', () {
    testWidgets('should_showMarkReadButton_onlyOnUnreadRows', (
      WidgetTester tester,
    ) async {
      await _pumpFeed(
        tester,
        _repoOf(<AppNotification>[notif('u1'), notif('r1', read: true)]),
        unread: 1,
      );

      expect(_check('u1'), findsOneWidget);
      expect(_check('r1'), findsNothing);
    });

    testWidgets('should_markReadWithoutNavigating_when_markReadButtonTapped', (
      WidgetTester tester,
    ) async {
      final _CountingObserver observer = _CountingObserver();
      final FakeNotificationRepository repo = _repoOf(<AppNotification>[
        notif('u1'),
      ]);
      final GoRouter router = GoRouter(
        initialLocation: '/n',
        observers: <NavigatorObserver>[observer],
        routes: <RouteBase>[
          GoRoute(
            path: '/n',
            builder: (BuildContext _, GoRouterState _) =>
                const NotificationsScreen(),
          ),
          GoRoute(
            path: '/booking',
            builder: (BuildContext _, GoRouterState _) =>
                const Scaffold(body: Text('booking-detail')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpRoutedApp(
        router,
        retry: (int _, Object _) => null,
        overrides: _overrides(repo, RecordingUnread(1), UserRole.client, null),
      );
      await tester.pumpAndSettle();
      final int before = observer.pushes;

      await tester.tap(_check('u1'));
      await tester.pumpAndSettle();

      expect(repo.markedRead, <String>['u1']);
      expect(observer.pushes, before, reason: 'the check never navigates');
      expect(find.text('booking-detail'), findsNothing);
      expect(find.byType(NotificationsScreen), findsOneWidget);
    });

    testWidgets(
      'should_haveMin48dpTapTargetAndSemanticsLabel_forMarkReadButton',
      (WidgetTester tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await _pumpFeed(
          tester,
          _repoOf(<AppNotification>[notif('u1')]),
          unread: 1,
        );

        // The RENDERED box, not a widget field: the visible face is smaller.
        final Size size = tester.getSize(_check('u1'));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));

        expect(
          tester.getSemantics(_check('u1')),
          isSemantics(label: uk.notificationsMarkOneRead, isButton: true),
        );

        // A tap on the margin around the 30 dp face (inside the 48 dp box)
        // still lands: the hit area is the box, not the disc.
        final Rect box = tester.getRect(_check('u1'));
        await tester.tapAt(box.topLeft + const Offset(2, 2));
        await tester.pumpAndSettle();
        expect(_check('u1'), findsNothing);
        handle.dispose();
      },
    );

    testWidgets('should_markReadAndDecrementDot_when_rowTapped', (
      WidgetTester tester,
    ) async {
      final FakeNotificationRepository repo = _repoOf(<AppNotification>[
        notif('u1'),
        notif('u2'),
      ]);
      final _Harness h = await _pumpFeed(tester, repo, unread: 2, width: 800);

      await tester.tap(_tile('u1'));
      await tester.pumpAndSettle();

      expect(repo.markedRead, <String>['u1']);
      expect(h.unread.calls, <String>['dec:u1']);
      expect(_check('u1'), findsNothing);
      expect(_check('u2'), findsOneWidget);
      expect(find.text(uk.notificationsUnreadCount(1)), findsOneWidget);
    });

    testWidgets(
      'should_flipStylingAndDecrementBellImmediately_beforeResponse',
      (WidgetTester tester) async {
        final FakeNotificationRepository repo = _repoOf(<AppNotification>[
          notif('u1'),
        ])..markReadGate = Completer<void>();
        final _Harness h = await _pumpFeed(tester, repo, unread: 1);

        await tester.tap(_check('u1'));
        await tester.pump();

        // The PATCH has not answered, and both the row and the dot have moved.
        expect(repo.markedRead, <String>['u1']);
        expect(_readInState(h, 'u1'), isTrue);
        expect(h.unread.calls, <String>['dec:u1']);
        expect(h.container.read(unreadNotificationsProvider).value, 0);
        await tester.pump(_flip);
        expect(_check('u1'), findsNothing);

        repo.markReadGate!.complete();
        await tester.pumpAndSettle();
        expect(_readInState(h, 'u1'), isTrue);
      },
    );

    testWidgets('should_rollBackAndShowSnackbar_when_markReadFails', (
      WidgetTester tester,
    ) async {
      final FakeNotificationRepository repo = _repoOf(<AppNotification>[
        notif('u1'),
      ])..markReadError = const NetworkFailure();
      final _Harness h = await _pumpFeed(tester, repo, unread: 1);

      await tester.tap(_check('u1'));
      await tester.pump();
      await tester.pump();
      await tester.pump(_flip);

      expect(_readInState(h, 'u1'), isFalse, reason: 'rolled back');
      expect(_check('u1'), findsOneWidget);
      // Rolled back by DELTA (one row back), never by an absolute snapshot.
      expect(h.unread.calls, <String>['dec:u1', 'inc:1:u1']);
      expect(h.container.read(unreadNotificationsProvider).value, 1);
      await pumpVelvetSnackIn(tester);
      expectVelvetSnack(
        uk.notificationsMarkReadFailed,
        variant: VelvetSnackVariant.error,
      );
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('should_treat404AsRead_withoutSnackbar', (
      WidgetTester tester,
    ) async {
      final FakeNotificationRepository repo = _repoOf(<AppNotification>[
        notif('u1'),
      ])..markReadError = const NotFoundFailure();
      final _Harness h = await _pumpFeed(tester, repo, unread: 1);

      await tester.tap(_check('u1'));
      await tester.pumpAndSettle();

      expect(_readInState(h, 'u1'), isTrue);
      expect(_check('u1'), findsNothing);
      expect(find.byType(VelvetSnack), findsNothing);
      expect(h.unread.calls, <String>['dec:u1'], reason: 'no rollback');
    });

    testWidgets('should_notMarkRead_just_becauseTheScreenOpened', (
      WidgetTester tester,
    ) async {
      final FakeNotificationRepository repo = _repoOf(<AppNotification>[
        notif('u1'),
      ]);
      await _pumpFeed(tester, repo, unread: 1);

      expect(repo.markedRead, isEmpty);
      expect(repo.markAllUpTo, isEmpty);
    });
  });

  group('mark all read', () {
    testWidgets('should_hideMarkAllAction_when_noUnread', (
      WidgetTester tester,
    ) async {
      await _pumpFeed(
        tester,
        _repoOf(<AppNotification>[notif('r1', read: true)]),
      );

      expect(find.byKey(NotificationsMarkAllBar.actionKey), findsNothing);
    });

    testWidgets(
      'should_markAllReadWithUpTo_andRefetchCount_when_markAllTapped',
      (WidgetTester tester) async {
        final DateTime newest = DateTime.utc(2026, 9, 30, 11, 40);
        final FakeNotificationRepository repo = _repoOf(<AppNotification>[
          notif('a', createdAt: DateTime.utc(2026, 9, 30, 8)),
          notif('b', createdAt: newest),
          notif('c', createdAt: DateTime.utc(2026, 9, 30, 9), read: true),
        ], unread: 1);
        final _Harness h = await _pumpFeed(tester, repo, unread: 2);

        await tester.tap(find.byKey(NotificationsMarkAllBar.actionKey));
        await tester.pumpAndSettle();

        expect(repo.markAllUpTo, <DateTime?>[newest]);
        expect(repo.unreadCountCalls, 1);
        // Optimistic zero first, then the server's remaining count.
        expect(h.unread.calls, <String>['set:0:u1', 'set:1:u1']);
        expect(_check('a'), findsNothing);
        expect(_check('b'), findsNothing);
      },
    );

    testWidgets('should_rollBackAll_andShowSnackbar_when_markAllFails', (
      WidgetTester tester,
    ) async {
      final FakeNotificationRepository repo = _repoOf(<AppNotification>[
        notif('a'),
        notif('b'),
      ])..markAllError = const NetworkFailure();
      final _Harness h = await _pumpFeed(tester, repo, unread: 2);

      await tester.tap(find.byKey(NotificationsMarkAllBar.actionKey));
      await tester.pump();
      await tester.pump();
      await tester.pump(_flip);

      expect(_readInState(h, 'a'), isFalse);
      expect(_readInState(h, 'b'), isFalse);
      // Zeroed optimistically, then given back by delta.
      expect(h.unread.calls, <String>['set:0:u1', 'inc:2:u1']);
      expect(h.container.read(unreadNotificationsProvider).value, 2);
      expect(_check('a'), findsOneWidget);
      await pumpVelvetSnackIn(tester);
      expectVelvetSnack(
        uk.notificationsMarkAllReadFailed,
        variant: VelvetSnackVariant.error,
      );
      await pumpPastVelvetSnack(tester);
    });
  });

  group('paging and refresh', () {
    List<AppNotification> rows(String prefix, int n, {int day = 30}) =>
        <AppNotification>[
          for (int i = 0; i < n; i++)
            notif(
              '$prefix$i',
              read: true,
              createdAt: DateTime.utc(2026, 9, day, 10, 59 - i),
            ),
        ];

    FakeNotificationRepository twoPages({Object? pageTwoError}) {
      final FakeNotificationRepository repo = FakeNotificationRepository(
        pages: <NotificationPage>[
          pageOf(0, 2, rows('a', 20)),
          pageOf(1, 2, rows('b', 2, day: 29)),
        ],
      );
      if (pageTwoError != null) repo.fetchErrors[1] = pageTwoError;
      return repo;
    }

    testWidgets('should_loadPageTwo_when_scrolledToTheEnd', (
      WidgetTester tester,
    ) async {
      final FakeNotificationRepository repo = twoPages();
      await _pumpFeed(tester, repo, settle: false);
      expect(repo.fetchedPages, <int>[0]);
      expect(_tile('b0'), findsNothing);

      await _scrollToEnd(tester);
      expect(repo.fetchedPages, <int>[0, 1]);

      await _scrollToEnd(tester);
      expect(_tile('b1'), findsOneWidget);
      // Last page reached: the footer is gone and nothing else is requested.
      await tester.pump();
      expect(repo.fetchedPages, <int>[0, 1]);
      expect(find.byType(MyBookingsLoadMoreSpinner), findsNothing);
    });

    testWidgets('should_buildRowsLazily_notAllTwentyAtOnce', (
      WidgetTester tester,
    ) async {
      await _pumpFeed(tester, twoPages(), settle: false);

      final int built = find.byType(NotificationTile).evaluate().length;
      expect(built, lessThan(20));
      expect(built, greaterThan(0));
    });

    testWidgets('should_refetchFirstPage_onPullToRefresh_andNudgeTheBell', (
      WidgetTester tester,
    ) async {
      final FakeNotificationRepository repo = _repoOf(<AppNotification>[
        notif('a', read: true),
      ]);
      final _Harness h = await _pumpFeed(tester, repo);

      await tester.fling(
        find.byKey(NotificationsScreen.listKey),
        const Offset(0, 300),
        1000,
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(repo.fetchedPages, <int>[0, 0]);
      expect(h.unread.refreshCalls, 1);
    });

    testWidgets('should_coalesceRefreshes_intoOneRequest', (
      WidgetTester tester,
    ) async {
      final FakeNotificationRepository repo = _repoOf(<AppNotification>[
        notif('a', read: true),
      ]);
      final _Harness h = await _pumpFeed(tester, repo);
      repo.pageGate = Completer<void>();

      final NotificationsFeed notifier = h.container.read(
        notificationsFeedProvider.notifier,
      );
      final Future<void> first = notifier.refresh();
      final Future<void> second = notifier.refresh();
      final Future<void> third = notifier.refresh();
      repo.pageGate!.complete();
      await Future.wait(<Future<void>>[first, second, third]);

      expect(repo.fetchedPages, <int>[0, 0], reason: 'one refetch, not three');
      expect(h.unread.refreshCalls, 1);
    });

    testWidgets('should_keepTheList_andSnack_when_refreshFails', (
      WidgetTester tester,
    ) async {
      final FakeNotificationRepository repo = _repoOf(<AppNotification>[
        notif('a', read: true),
      ]);
      await _pumpFeed(tester, repo);
      repo.fetchErrors[1] = const NetworkFailure();

      await tester.fling(
        find.byKey(NotificationsScreen.listKey),
        const Offset(0, 300),
        1000,
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(_flip);
      await tester.pump(_flip);

      expect(_tile('a'), findsOneWidget);
      expect(find.byType(VelvetSnack), findsOneWidget);
      await pumpPastVelvetSnack(tester);
    });

    testWidgets(
      'should_countDownThe429Footer_thenRetryOnce_withoutARefireLoop',
      (WidgetTester tester) async {
        final FakeNotificationRepository repo = twoPages(
          // 30 s is the floor of the clamp window (kUnreadMinRetryAfter).
          pageTwoError: const NotificationsRateLimitedFailure(
            retryAfterSeconds: 30,
          ),
        );
        await _pumpFeed(tester, repo, settle: false);

        await _scrollToEnd(tester);
        expect(repo.fetchedPages, <int>[0, 1]);
        expect(find.text(uk.masterArchiveLoadMorePaused(30)), findsOneWidget);

        // Scrolling away and back rebuilds the footer, and re-fires nothing:
        // the parked footer never asks for the page by itself.
        for (int i = 0; i < 4; i++) {
          await tester.drag(
            find.byKey(NotificationsScreen.listKey),
            const Offset(0, 500),
          );
          await tester.pump();
          await tester.drag(
            find.byKey(NotificationsScreen.listKey),
            const Offset(0, -500),
          );
          await tester.pump();
        }
        expect(repo.fetchedPages, <int>[0, 1], reason: 'no scroll refire loop');

        // The window is an absolute instant: it keeps counting across remounts.
        await _advance(tester, 1);
        expect(find.text(uk.masterArchiveLoadMorePaused(29)), findsOneWidget);
        await _scrollToEnd(tester);
        expect(find.text(uk.masterArchiveLoadMorePaused(29)), findsOneWidget);

        await _advance(tester, 29);
        await tester.pump();
        await tester.pump();
        expect(repo.fetchedPages, <int>[0, 1, 1], reason: 'one retry');
        await _scrollToEnd(tester);
        expect(_tile('b1'), findsOneWidget);
        expect(repo.fetchedPages, <int>[0, 1, 1]);
      },
    );

    testWidgets('should_offerRetry_andNotRefire_when_nextPageFailsOtherwise', (
      WidgetTester tester,
    ) async {
      final FakeNotificationRepository repo = twoPages(
        pageTwoError: const NetworkFailure(),
      );
      await _pumpFeed(tester, repo, settle: false);

      await _scrollToEnd(tester);
      expect(find.byKey(NotificationsLoadMoreFooter.retryKey), findsOneWidget);
      expect(repo.fetchedPages, <int>[0, 1]);

      await tester.pump();
      await tester.pump();
      expect(repo.fetchedPages, <int>[0, 1], reason: 'parked until tapped');

      await tester.tap(find.byKey(NotificationsLoadMoreFooter.retryKey));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(repo.fetchedPages, <int>[0, 1, 1]);
    });
  });

  group('compact row', () {
    testWidgets('should_pinTheCompactRowHeight', (WidgetTester tester) async {
      await _pumpFeed(
        tester,
        _repoOf(<AppNotification>[
          // No body line (unknown type): the row's floor.
          notif('floor', type: AppNotificationType.unknown),
          notif('floor-read', type: AppNotificationType.unknown, read: true),
        ]),
        unread: 1,
        width: 400,
        height: 1200,
      );

      // The floor is the 48 dp check hit box plus the row's own 4 dp vertical
      // padding and its 1 dp hairline on each side (48 + 8 + 2). The approved
      // preview's card was about 115 dp.
      final double unread = tester.getSize(_tile('floor')).height;
      final double read = tester.getSize(_tile('floor-read')).height;
      expect(unread, 58);
      expect(read, unread, reason: 'reading a row never changes its height');
    });

    testWidgets('should_capTheBodyAtTwoLines_soARowStaysCompact', (
      WidgetTester tester,
    ) async {
      await _pumpFeed(
        tester,
        _repoOf(<AppNotification>[notif('long', read: true)]),
        width: 280,
        height: 1200,
      );

      // Title line + at most two body lines + padding: never a tall card.
      expect(tester.getSize(_tile('long')).height, lessThanOrEqualTo(96));
    });

    testWidgets('should_useTheExistingPrimitives_notANewCardStyle', (
      WidgetTester tester,
    ) async {
      await _pumpFeed(
        tester,
        _repoOf(<AppNotification>[notif('u1')]),
        unread: 1,
      );

      expect(
        find.descendant(
          of: _tile('u1'),
          matching: find.byType(NeumorphicIconButton),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _tile('u1'), matching: find.byType(NeumorphicCard)),
        findsNothing,
        reason: 'no 24 dp card: the row is the settings-row family',
      );
    });
  });

  group('audit cycle 1', () {
    List<BoxShadow>? shadowOf(WidgetTester tester, String id) {
      final DecoratedBox box = tester.widget<DecoratedBox>(
        find
            .descendant(of: _tile(id), matching: find.byType(DecoratedBox))
            .first,
      );
      return (box.decoration as BoxDecoration).boxShadow;
    }

    testWidgets(
      'should_neverShowOrActOnThePreviousUsersRows_whenTheUserSwitches',
      (WidgetTester tester) async {
        final FakeNotificationRepository repo = _repoOf(<AppNotification>[
          notif('a'),
        ], unread: 1);
        final _Harness h = await _pumpFeed(tester, repo, unread: 1);
        expect(_tile('a'), findsOneWidget);

        // User two signs in; their first page is held open.
        repo.pageGate = Completer<void>();
        (h.container.read(authProvider.notifier) as FixedRoleAuth).switchUser(
          'u2',
        );
        await tester.pump();
        await tester.pump();

        expect(_tile('a'), findsNothing, reason: "u1's row must not be shown");
        expect(find.byType(BookingsSkeleton), findsOneWidget);
        expect(find.byKey(NotificationsMarkAllBar.actionKey), findsNothing);

        // ...and is not actionable either: a no-op, never a request.
        final NotificationsFeed feed = h.container.read(
          notificationsFeedProvider.notifier,
        );
        expect(await feed.markRead('a'), isTrue);
        expect(await feed.markAllRead(), isTrue);
        expect(repo.markedRead, isEmpty);
        expect(repo.markAllUpTo, isEmpty);

        repo.pageGate!.complete();
        await tester.pumpAndSettle();
        expect(_tile('a'), findsOneWidget, reason: "now it is u2's own row");
      },
    );

    testWidgets(
      'should_releaseTheMemoisedListAndRowCache_whenTheUserSwitches',
      (WidgetTester tester) async {
        final FakeNotificationRepository repo = _repoOf(<AppNotification>[
          notif('a'),
          notif('b'),
        ], unread: 2);
        final _Harness h = await _pumpFeed(tester, repo, unread: 2);
        final dynamic state = tester.state(find.byType(NotificationsScreen));
        expect(state.debugHasLayout, isTrue);
        expect(state.debugCachedRowCount, 2);

        repo.pageGate = Completer<void>();
        (h.container.read(authProvider.notifier) as FixedRoleAuth).switchUser(
          'u2',
        );
        await tester.pump();
        await tester.pump();

        expect(find.byType(BookingsSkeleton), findsOneWidget);
        expect(state.debugHasLayout, isFalse, reason: "u1's layout is dropped");
        expect(state.debugCachedRowCount, 0, reason: "u1's rows are dropped");

        repo.pageGate!.complete();
        await tester.pumpAndSettle();
        expect(state.debugHasLayout, isTrue);
      },
    );

    testWidgets('should_releaseTheMemoisedList_whenTheFeedTurnsEmpty', (
      WidgetTester tester,
    ) async {
      final FakeNotificationRepository repo = _repoOf(<AppNotification>[
        notif('a'),
      ], unread: 1);
      final _Harness h = await _pumpFeed(tester, repo, unread: 1);
      final dynamic state = tester.state(find.byType(NotificationsScreen));
      expect(state.debugHasLayout, isTrue);

      repo.pages = <NotificationPage>[onePage(<AppNotification>[])];
      await h.container.read(notificationsFeedProvider.notifier).refresh();
      await tester.pumpAndSettle();

      expect(find.byKey(NotificationsScreen.emptyKey), findsOneWidget);
      expect(state.debugHasLayout, isFalse);
      expect(state.debugCachedRowCount, 0);
    });

    testWidgets('should_isolateServerStrings_andStripBidiAndControlChars', (
      WidgetTester tester,
    ) async {
      final String rlo = String.fromCharCode(0x202E);
      await _pumpFeed(
        tester,
        _repoOf(<AppNotification>[
          notif(
            'x',
            read: true,
            params: NotificationParams(
              counterpartName: 'Олена$rlo\nКоваль',
              serviceName: 'Ман$rloікюр',
              serviceCount: 1,
              startsAt: DateTime.utc(2026, 10, 3, 11, 30),
              salonName: 'Beautica\n$rloЦентр',
            ),
          ),
        ]),
        role: UserRole.salonOwner,
        width: 800,
      );

      expect(
        find.text(
          uk.notificationBodyProvider(
            iso('Олена Коваль'),
            iso('Манікюр'),
            'сб, 3 жовтня, 14:30',
          ),
        ),
        findsOneWidget,
      );
      // i18n-finder-ok: a server-supplied salon name is data, not UI copy
      expect(find.text(iso('Beautica Центр')), findsOneWidget);
    });

    testWidgets('should_clampTheFeed429Cooldown_to30s_when_retryAfterIs1s', (
      WidgetTester tester,
    ) async {
      final FakeNotificationRepository repo = _pagedRepo(
        const NotificationsRateLimitedFailure(retryAfterSeconds: 1),
      );
      await _pumpFeed(tester, repo, settle: false);

      await _scrollToEnd(tester);

      expect(find.text(uk.masterArchiveLoadMorePaused(30)), findsOneWidget);
    });

    testWidgets(
      'should_clampTheFeed429Cooldown_to3600s_when_retryAfterIs999999',
      (WidgetTester tester) async {
        final FakeNotificationRepository repo = _pagedRepo(
          const NotificationsRateLimitedFailure(retryAfterSeconds: 999999),
        );
        await _pumpFeed(tester, repo, settle: false);

        await _scrollToEnd(tester);

        expect(find.text(uk.masterArchiveLoadMorePaused(3600)), findsOneWidget);
      },
    );

    testWidgets('should_dropTheShadowPairOfAReadRow_onceTheFlipHasSettled', (
      WidgetTester tester,
    ) async {
      await _pumpFeed(
        tester,
        _repoOf(<AppNotification>[notif('u'), notif('r', read: true)]),
        unread: 1,
      );

      // Unread: the raised pair. Born read: none at all.
      expect(shadowOf(tester, 'u'), hasLength(2));
      expect(shadowOf(tester, 'u')!.first.color.a, greaterThan(0));
      expect(shadowOf(tester, 'r') ?? const <BoxShadow>[], isEmpty);

      await tester.tap(_check('u'));
      await tester.pump();
      // fixed-wait-ok: mid-way through the fixed 320 ms row flip
      await tester.pump(const Duration(milliseconds: 100));
      // Mid-flip the faded pair is still there, so the shadow lerps.
      expect(shadowOf(tester, 'u'), hasLength(2));

      // fixed-wait-ok: past the fixed 320 ms flip, which arms the settle timer
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      // fixed-wait-ok: past the 150 ms shadow tween that follows the settle
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        shadowOf(tester, 'u') ?? const <BoxShadow>[],
        isEmpty,
        reason: 'two alpha-0 blurred shadows per read row are pure cost',
      );
    });

    testWidgets('should_rebuildOnlyTheFlippedRow_notTheOtherVisibleTiles', (
      WidgetTester tester,
    ) async {
      await _pumpFeed(
        tester,
        _repoOf(<AppNotification>[notif('a'), notif('b'), notif('c')]),
        unread: 3,
      );

      final Set<Key?> rebuiltTiles = <Key?>{};
      final Set<Type> rebuilt = <Type>{};
      final RebuildDirtyWidgetCallback? old = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (Element e, bool builtOnce) {
        rebuilt.add(e.widget.runtimeType);
        if (e.widget is NotificationTile) rebuiltTiles.add(e.widget.key);
        old?.call(e, builtOnce);
      };
      addTearDown(() => debugOnRebuildDirtyWidget = old);

      await tester.tap(_check('b'));
      await tester.pump();
      await tester.pump(_flip);

      expect(rebuilt, contains(NotificationsScreen), reason: 'control');
      expect(rebuiltTiles, contains(const Key('notification-tile-b')));
      expect(rebuiltTiles, isNot(contains(const Key('notification-tile-a'))));
      expect(rebuiltTiles, isNot(contains(const Key('notification-tile-c'))));
    });

    testWidgets('should_notRebuildTheScreen_when_aPollKeepsTheSameCount', (
      WidgetTester tester,
    ) async {
      final _Harness h = await _pumpFeed(
        tester,
        _repoOf(<AppNotification>[notif('a')]),
        unread: 1,
      );
      final Set<Type> rebuilt = <Type>{};
      final RebuildDirtyWidgetCallback? old = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (Element e, bool builtOnce) {
        rebuilt.add(e.widget.runtimeType);
        old?.call(e, builtOnce);
      };
      addTearDown(() => debugOnRebuildDirtyWidget = old);

      // A poll in flight: the AsyncValue changes, the integer does not.
      h.unread.emitRefreshing();
      await tester.pump();
      h.unread.emit(const AsyncData<int>(1));
      await tester.pump();
      expect(rebuilt, isNot(contains(NotificationsScreen)));

      // Control: a DIFFERENT count does rebuild it.
      h.unread.emit(const AsyncData<int>(2));
      await tester.pump();
      expect(rebuilt, contains(NotificationsScreen));
    });

    group('day headers across midnight (Europe/Kyiv)', () {
      Future<void> pumpAt(WidgetTester tester, DateTime now, DateTime row) {
        _clockNow = now;
        return _pumpFeed(
          tester,
          _repoOf(<AppNotification>[notif('a', read: true, createdAt: row)]),
        );
      }

      testWidgets('should_relabelTodayAsYesterday_when_theKyivMidnightPasses', (
        WidgetTester tester,
      ) async {
        // 20:30Z = 23:30 in Kyiv (UTC+3); the row is from 22:00 Kyiv.
        await pumpAt(
          tester,
          DateTime.utc(2026, 9, 30, 20, 30),
          DateTime.utc(2026, 9, 30, 19),
        );
        expect(find.text(uk.relativeDateToday), findsOneWidget);

        // 21:10Z = 00:10 on 1 October in Kyiv; the timer fires 30 min in.
        _clockNow = DateTime.utc(2026, 9, 30, 21, 10);
        // fixed-wait-ok: the midnight timer is armed for exactly 30 minutes
        await tester.pump(const Duration(minutes: 30));
        await tester.pump();

        expect(find.text(uk.relativeDateToday), findsNothing);
        expect(find.text(uk.relativeDateYesterday), findsOneWidget);
      });

      testWidgets('should_notRelabel_beforeTheKyivMidnight', (
        WidgetTester tester,
      ) async {
        // 20:59Z is 23:59 in Kyiv: still the same day when the timer fires.
        await pumpAt(
          tester,
          DateTime.utc(2026, 9, 30, 20, 30),
          DateTime.utc(2026, 9, 30, 19),
        );
        _clockNow = DateTime.utc(2026, 9, 30, 20, 59);
        // fixed-wait-ok: the midnight timer is armed for exactly 30 minutes
        await tester.pump(const Duration(minutes: 30));
        await tester.pump();

        expect(find.text(uk.relativeDateToday), findsOneWidget);
      });

      testWidgets('should_relabel_when_theAppResumesAfterMidnight', (
        WidgetTester tester,
      ) async {
        await pumpAt(
          tester,
          DateTime.utc(2026, 9, 30, 20, 30),
          DateTime.utc(2026, 9, 30, 19),
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        // The phone slept through midnight; no timer ran.
        _clockNow = DateTime.utc(2026, 10, 1, 6);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();

        expect(find.text(uk.relativeDateToday), findsNothing);
        expect(find.text(uk.relativeDateYesterday), findsOneWidget);
      });

      testWidgets('should_notWake_whileTheAppIsBackgrounded', (
        WidgetTester tester,
      ) async {
        addTearDown(
          () => tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          ),
        );
        await pumpAt(
          tester,
          DateTime.utc(2026, 9, 30, 20, 30),
          DateTime.utc(2026, 9, 30, 19),
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

        // Midnight passes while backgrounded; a live timer would relabel.
        _clockNow = DateTime.utc(2026, 9, 30, 21, 10);
        // fixed-wait-ok: the midnight timer would have fired 30 minutes in
        await tester.pump(const Duration(minutes: 30));
        await tester.pump();
        expect(find.text(uk.relativeDateToday), findsOneWidget);
      });

      testWidgets('should_rearmTheTimer_whenTheAppResumesBeforeMidnight', (
        WidgetTester tester,
      ) async {
        addTearDown(
          () => tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          ),
        );
        await pumpAt(
          tester,
          DateTime.utc(2026, 9, 30, 20, 30),
          DateTime.utc(2026, 9, 30, 19),
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        _clockNow = DateTime.utc(2026, 9, 30, 20, 40); // 23:40 Kyiv
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(find.text(uk.relativeDateToday), findsOneWidget);

        _clockNow = DateTime.utc(2026, 9, 30, 21, 10);
        // fixed-wait-ok: the re-armed timer fires 20 minutes after the resume
        await tester.pump(const Duration(minutes: 30));
        await tester.pump();
        expect(find.text(uk.relativeDateYesterday), findsOneWidget);
      });

      testWidgets('should_relabelAtTheRightMidnight_acrossTheOctoberFallBack', (
        WidgetTester tester,
      ) async {
        // 2026-10-25 is 25 h long in Kyiv (04:00 EEST -> 03:00 EET). Start at
        // 01:00 EEST (22:00Z on the 24th); midnight is 22:00Z on the 25th.
        await pumpAt(
          tester,
          DateTime.utc(2026, 10, 24, 22),
          DateTime.utc(2026, 10, 24, 22, 30),
        );
        expect(find.text(uk.relativeDateToday), findsOneWidget);

        for (int hour = 1; hour <= 23; hour++) {
          _clockNow = _clockNow.add(const Duration(hours: 1));
          // fixed-wait-ok: advancing the virtual clock one midnight-timer slice
          await tester.pump(const Duration(hours: 1));
        }
        // 21:00Z on the 25th = 23:00 EET: one hour to go.
        expect(_clockNow, DateTime.utc(2026, 10, 25, 21));
        expect(find.text(uk.relativeDateToday), findsOneWidget);

        _clockNow = _clockNow.add(const Duration(hours: 1));
        // fixed-wait-ok: the final midnight-timer slice, exactly one hour
        await tester.pump(const Duration(hours: 1));
        await tester.pump();

        expect(find.text(uk.relativeDateToday), findsNothing);
        expect(find.text(uk.relativeDateYesterday), findsOneWidget);
      });
    });
  });

  group('locale', () {
    testWidgets('should_renderEnglish_forTheEnLocale', (
      WidgetTester tester,
    ) async {
      await _pumpFeed(
        tester,
        _repoOf(<AppNotification>[notif('u1')]),
        unread: 1,
        locale: const Locale('en'),
      );

      expect(find.text('New booking'), findsOneWidget);
      expect(find.text('Mark all as read'), findsOneWidget);
    });
  });
}
