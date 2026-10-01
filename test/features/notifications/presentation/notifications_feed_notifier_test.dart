// Phase 363 — the feed notifier, below the UI.
//
// Headline: the STALE-USER GUARD (phase 360 security INFO-1). The feed passes
// every `UnreadNotifications.setCount` / `decrement` the user id it captured
// WHEN THE REQUEST WAS ISSUED. This test uses the REAL auth notifier and the
// REAL count notifier: mark-all starts as user A, the session switches to user
// B before the PATCH answers, and B's count must not move.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/notifications/data/notification_repository.dart';
import 'package:beautica_mobile/features/notifications/domain/app_notification.dart';
import 'package:beautica_mobile/features/notifications/domain/notifications_feed_state.dart';
import 'package:beautica_mobile/features/notifications/presentation/notifications_feed_notifier.dart';
import 'package:beautica_mobile/features/notifications/presentation/unread_notifications_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_notification_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import '../../../helpers/test_container.dart';

User _user(String id) =>
    User(id: id, email: '$id@e.com', role: UserRole.salonOwner);

AuthTokens _tokens(String id) =>
    AuthTokens(accessToken: 'access-$id', refreshToken: 'refresh-$id');

typedef _Env = ({
  ProviderContainer container,
  FakeAuthRepository auth,
  FakeNotificationRepository repo,
});

Future<void> _login(_Env env, String id) async {
  env.auth
    ..loginResult = (_user(id), _tokens(id))
    ..meResult = _user(id);
  await env.container.read(authProvider.notifier).login('$id@e.com', 'pw');
  // Let the dependants (feed, count) rebuild and their first fetches land.
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

_Env _env(List<NotificationPage> pages, {DateTime Function()? clock}) {
  final FakeAuthRepository auth = FakeAuthRepository();
  final FakeNotificationRepository repo = FakeNotificationRepository(
    pages: pages,
  );
  final ProviderContainer container = makeTestContainer(
    overrides: <Object>[
      secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
      authRepositoryProvider.overrideWith((_) => auth),
      notificationRepositoryProvider.overrideWithValue(repo),
      if (clock != null) clockProvider.overrideWithValue(clock),
      // The REAL count notifier (not the zero double), on a long poll period so
      // no tick fires inside a test.
      unreadNotificationsProvider.overrideWith(UnreadNotifications.new),
      pollIntervalProvider.overrideWithValue(const Duration(hours: 1)),
    ],
    retry: (int _, Object _) => null,
  );
  return (container: container, auth: auth, repo: repo);
}

int? _count(_Env env) => env.container.read(unreadNotificationsProvider).value;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'should_dropTheLateMarkAllResult_when_theUserSwitchedMeanwhile',
    () async {
      final _Env env = _env(<NotificationPage>[
        onePage(<AppNotification>[notif('a'), notif('b'), notif('c')]),
      ]);
      env.container.listen(unreadNotificationsProvider, (_, _) {});
      env.container.listen(notificationsFeedProvider, (_, _) {});

      // User A: three unread, the count is 3.
      env.repo.unread = 3;
      await _login(env, 'A');
      expect(_count(env), 3);
      expect(
        env.container.read(notificationsFeedProvider).value!.items,
        hasLength(3),
      );

      // Mark all as A, and hold the PATCH open.
      env.repo.markAllGate = Completer<void>();
      final Future<bool> markAll = env.container
          .read(notificationsFeedProvider.notifier)
          .markAllRead();
      await Future<void>.delayed(Duration.zero);
      expect(_count(env), 0, reason: 'optimistic zero for A');

      // The session switches to B, whose count is 7.
      await env.container.read(authProvider.notifier).logout();
      await Future<void>.delayed(Duration.zero);
      env.repo.unread = 7;
      await _login(env, 'B');
      expect(_count(env), 7);

      // A's PATCH finally answers; the recount it triggers would say 55.
      env.repo.unread = 55;
      env.repo.markAllGate!.complete();
      await markAll;
      await Future<void>.delayed(Duration.zero);

      expect(_count(env), 7, reason: "A's late response must not reach B");
    },
  );

  test('should_dropTheLateRollback_when_theUserSwitchedMeanwhile', () async {
    final _Env env = _env(<NotificationPage>[
      onePage(<AppNotification>[notif('a')]),
    ]);
    env.container.listen(unreadNotificationsProvider, (_, _) {});
    env.container.listen(notificationsFeedProvider, (_, _) {});
    env.repo.unread = 1;
    await _login(env, 'A');

    env.repo.markReadGate = Completer<void>();
    env.repo.markReadError = const NetworkFailure();
    final Future<bool> markRead = env.container
        .read(notificationsFeedProvider.notifier)
        .markRead('a');
    await Future<void>.delayed(Duration.zero);

    await env.container.read(authProvider.notifier).logout();
    await Future<void>.delayed(Duration.zero);
    env.repo.unread = 4;
    await _login(env, 'B');
    expect(_count(env), 4);

    env.repo.markReadGate!.complete();
    final bool ok = await markRead;

    expect(ok, isFalse, reason: 'the failure is still reported to A');
    expect(_count(env), 4, reason: "A's rollback must not reach B");
  });

  test(
    'should_notFlipARowBackToUnread_when_aRefreshLandsBeforeItsPatch',
    () async {
      final _Env env = _env(<NotificationPage>[
        onePage(<AppNotification>[notif('a')]),
      ]);
      env.container.listen(notificationsFeedProvider, (_, _) {});
      await _login(env, 'A');

      env.repo.markReadGate = Completer<void>();
      final Future<bool> markRead = env.container
          .read(notificationsFeedProvider.notifier)
          .markRead('a');
      await Future<void>.delayed(Duration.zero);

      // The server has not applied the PATCH yet, so the refetch still says
      // unread; the optimistic flip must survive it.
      await env.container.read(notificationsFeedProvider.notifier).refresh();
      expect(
        env.container.read(notificationsFeedProvider).value!.items.single.read,
        isTrue,
      );

      env.repo.markReadGate!.complete();
      await markRead;
    },
  );

  test('should_dedupeRows_thatShiftedAcrossPages', () async {
    final _Env env = _env(<NotificationPage>[
      pageOf(0, 2, <AppNotification>[notif('a'), notif('b')]),
      pageOf(1, 2, <AppNotification>[notif('b'), notif('c')]),
    ]);
    env.container.listen(notificationsFeedProvider, (_, _) {});
    await _login(env, 'A');

    await env.container.read(notificationsFeedProvider.notifier).loadMore();

    final NotificationsFeedState state = env.container
        .read(notificationsFeedProvider)
        .value!;
    expect(state.items.map((AppNotification n) => n.id), <String>[
      'a',
      'b',
      'c',
    ]);
    expect(state.hasMore, isFalse);
  });

  test('should_issueOneRequest_when_loadMoreIsCalledRepeatedly', () async {
    final _Env env = _env(<NotificationPage>[
      pageOf(0, 2, <AppNotification>[notif('a')]),
      pageOf(1, 2, <AppNotification>[notif('b')]),
    ]);
    env.container.listen(notificationsFeedProvider, (_, _) {});
    await _login(env, 'A');

    env.repo.pageGate = Completer<void>();
    final NotificationsFeed notifier = env.container.read(
      notificationsFeedProvider.notifier,
    );
    final Future<void> first = notifier.loadMore();
    final Future<void> second = notifier.loadMore();
    final Future<void> third = notifier.loadMore();
    env.repo.pageGate!.complete();
    await Future.wait(<Future<void>>[first, second, third]);

    expect(env.repo.fetchedPages, <int>[0, 1]);
  });

  test('should_parkAFailedPage_untilRetryLoadMore', () async {
    final _Env env = _env(<NotificationPage>[
      pageOf(0, 2, <AppNotification>[notif('a')]),
      pageOf(1, 2, <AppNotification>[notif('b')]),
    ]);
    env.container.listen(notificationsFeedProvider, (_, _) {});
    await _login(env, 'A');
    env.repo.fetchErrors[1] = const NetworkFailure();
    final NotificationsFeed notifier = env.container.read(
      notificationsFeedProvider.notifier,
    );

    await notifier.loadMore();
    expect(
      env.container.read(notificationsFeedProvider).value!.loadMoreFailure,
      isA<NetworkFailure>(),
    );

    // Nothing re-fires by itself, however often it is asked.
    await notifier.loadMore();
    await notifier.loadMore();
    expect(env.repo.fetchedPages, <int>[0, 1]);

    await notifier.retryLoadMore();
    final NotificationsFeedState state = env.container
        .read(notificationsFeedProvider)
        .value!;
    expect(env.repo.fetchedPages, <int>[0, 1, 1]);
    expect(state.loadMoreFailure, isNull);
    expect(state.items, hasLength(2));
  });

  group('optimistic rollback is a DELTA', () {
    test('should_endAtTheRightCount_when_AFailsAfterBSucceeded', () async {
      final _Env env = _env(<NotificationPage>[
        onePage(<AppNotification>[notif('a'), notif('b')]),
      ]);
      env.container.listen(unreadNotificationsProvider, (_, _) {});
      env.container.listen(notificationsFeedProvider, (_, _) {});
      env.repo.unread = 2;
      await _login(env, 'A');
      expect(_count(env), 2);

      final NotificationsFeed feed = env.container.read(
        notificationsFeedProvider.notifier,
      );
      // A is held open and will FAIL; B answers at once and succeeds.
      env.repo.markReadGatesById['a'] = Completer<void>();
      env.repo.markReadErrorsById['a'] = const NetworkFailure();

      final Future<bool> a = feed.markRead('a'); // count 2 -> 1
      await Future<void>.delayed(Duration.zero);
      final bool bOk = await feed.markRead('b'); // count 1 -> 0
      expect(bOk, isTrue);
      expect(_count(env), 0);

      env.repo.markReadGatesById['a']!.complete();
      final bool aOk = await a; // A rolls back: +1, NOT back to its snapshot 2

      expect(aOk, isFalse);
      expect(_count(env), 1, reason: "B's decrement must survive A's rollback");
      final List<AppNotification> items = env.container
          .read(notificationsFeedProvider)
          .value!
          .items;
      expect(
        items.firstWhere((AppNotification n) => n.id == 'a').read,
        isFalse,
      );
      expect(items.firstWhere((AppNotification n) => n.id == 'b').read, isTrue);
    });

    test('should_giveBackExactlyTheZeroedCount_when_markAllFails', () async {
      final _Env env = _env(<NotificationPage>[
        onePage(<AppNotification>[notif('a'), notif('b'), notif('c')]),
      ]);
      env.container.listen(unreadNotificationsProvider, (_, _) {});
      env.container.listen(notificationsFeedProvider, (_, _) {});
      env.repo.unread = 3;
      await _login(env, 'A');

      env.repo.markAllError = const NetworkFailure();
      final bool ok = await env.container
          .read(notificationsFeedProvider.notifier)
          .markAllRead();

      expect(ok, isFalse);
      expect(_count(env), 3);
      expect(
        env.container
            .read(notificationsFeedProvider)
            .value!
            .items
            .where((AppNotification n) => !n.read),
        hasLength(3),
      );
    });
  });

  group('mark-all failure reconciles with the server', () {
    test(
      'should_endAtTheServerCount_not2N_when_aPollRacedTheFailedPatch',
      () async {
        final _Env env = _env(<NotificationPage>[
          onePage(<AppNotification>[notif('a'), notif('b'), notif('c')]),
        ]);
        env.container.listen(unreadNotificationsProvider, (_, _) {});
        env.container.listen(notificationsFeedProvider, (_, _) {});
        env.repo.unread = 3;
        await _login(env, 'A');
        expect(_count(env), 3);

        env.repo.markAllGate = Completer<void>();
        env.repo.markAllError = const NetworkFailure();
        final Future<bool> markAll = env.container
            .read(notificationsFeedProvider.notifier)
            .markAllRead();
        await Future<void>.delayed(Duration.zero);
        expect(_count(env), 0, reason: 'optimistic zero');

        // A poll issued after setCount(0) and answered with the OLD number.
        await env.container
            .read(unreadNotificationsProvider.notifier)
            .refresh();
        expect(_count(env), 3, reason: 'the racing poll re-emitted N');

        // The server's truth when the PATCH finally fails (one row was read on
        // another device meanwhile).
        env.repo.unread = 2;
        env.repo.markAllGate!.complete();
        expect(await markAll, isFalse);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(_count(env), 2, reason: 'reconciled, not N + N = 6');
      },
    );

    test(
      'should_refetchTheFeed_when_markAllFails_soACommittedPatchShows',
      () async {
        final _Env env = _env(<NotificationPage>[
          onePage(<AppNotification>[notif('a'), notif('b')]),
        ]);
        env.container.listen(unreadNotificationsProvider, (_, _) {});
        env.container.listen(notificationsFeedProvider, (_, _) {});
        env.repo.unread = 2;
        await _login(env, 'A');
        expect(env.repo.fetchedPages, <int>[0]);

        // The PATCH "times out" client-side, but the server committed: the next
        // read of the feed says everything is read.
        env.repo.markAllError = const NetworkFailure();
        env.repo.pages = <NotificationPage>[
          onePage(<AppNotification>[
            notif('a', read: true),
            notif('b', read: true),
          ]),
        ];
        env.repo.unread = 0;
        expect(
          await env.container
              .read(notificationsFeedProvider.notifier)
              .markAllRead(),
          isFalse,
        );
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(env.repo.fetchedPages, <int>[0, 0], reason: 're-fetched');
        expect(
          env.container
              .read(notificationsFeedProvider)
              .value!
              .items
              .every((AppNotification n) => n.read),
          isTrue,
        );
        expect(_count(env), 0);
      },
    );

    test('should_keepTheRolledBackList_when_theRefetchAlsoFails', () async {
      final _Env env = _env(<NotificationPage>[
        onePage(<AppNotification>[notif('a')]),
      ]);
      env.container.listen(unreadNotificationsProvider, (_, _) {});
      env.container.listen(notificationsFeedProvider, (_, _) {});
      env.repo.unread = 1;
      await _login(env, 'A');

      env.repo.markAllError = const NetworkFailure();
      env.repo.fetchErrors[1] = const NetworkFailure(); // the re-fetch
      expect(
        await env.container
            .read(notificationsFeedProvider.notifier)
            .markAllRead(),
        isFalse,
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final AsyncValue<NotificationsFeedState> v = env.container.read(
        notificationsFeedProvider,
      );
      expect(v.value!.items.single.read, isFalse);
    });
  });

  group('a row marked read stays read', () {
    test('should_notRevertAJustMarkedRow_when_aStaleRefreshLands', () async {
      final _Env env = _env(<NotificationPage>[
        onePage(<AppNotification>[notif('a'), notif('b')]),
      ]);
      env.container.listen(unreadNotificationsProvider, (_, _) {});
      env.container.listen(notificationsFeedProvider, (_, _) {});
      env.repo.unread = 2;
      await _login(env, 'A');
      final NotificationsFeed feed = env.container.read(
        notificationsFeedProvider.notifier,
      );

      expect(await feed.markRead('a'), isTrue); // PATCH committed + settled
      // A refresh whose GET began BEFORE the PATCH committed: still unread.
      await feed.refresh();

      final List<AppNotification> items = env.container
          .read(notificationsFeedProvider)
          .value!
          .items;
      expect(items.firstWhere((AppNotification n) => n.id == 'a').read, isTrue);
      expect(
        items.firstWhere((AppNotification n) => n.id == 'b').read,
        isFalse,
        reason: 'only the marked row is held',
      );
    });

    test('should_stillUpgradeARow_when_theServerSaysRead', () async {
      final _Env env = _env(<NotificationPage>[
        onePage(<AppNotification>[notif('a'), notif('b')]),
      ]);
      env.container.listen(notificationsFeedProvider, (_, _) {});
      await _login(env, 'A');
      final NotificationsFeed feed = env.container.read(
        notificationsFeedProvider.notifier,
      );
      env.repo.pages = <NotificationPage>[
        onePage(<AppNotification>[notif('a'), notif('b', read: true)]),
      ];
      await feed.refresh();
      final List<AppNotification> items = env.container
          .read(notificationsFeedProvider)
          .value!
          .items;
      expect(items.map((AppNotification n) => n.read), <bool>[false, true]);
    });

    test('should_forgetTheMark_when_theSingleMarkReadFails', () async {
      final _Env env = _env(<NotificationPage>[
        onePage(<AppNotification>[notif('a')]),
      ]);
      env.container.listen(notificationsFeedProvider, (_, _) {});
      await _login(env, 'A');
      final NotificationsFeed feed = env.container.read(
        notificationsFeedProvider.notifier,
      );
      env.repo.markReadError = const NetworkFailure();
      expect(await feed.markRead('a'), isFalse);
      env.repo.markReadError = null;
      await feed.refresh();
      expect(
        env.container.read(notificationsFeedProvider).value!.items.single.read,
        isFalse,
      );
    });
  });

  group('a mark-all success supersedes pending single mark-reads', () {
    test(
      'should_neitherUnreadNorCount_when_aSingleFailsAfterMarkAll',
      () async {
        final _Env env = _env(<NotificationPage>[
          onePage(<AppNotification>[notif('a'), notif('b')]),
        ]);
        env.container.listen(unreadNotificationsProvider, (_, _) {});
        env.container.listen(notificationsFeedProvider, (_, _) {});
        env.repo.unread = 2;
        await _login(env, 'A');
        final NotificationsFeed feed = env.container.read(
          notificationsFeedProvider.notifier,
        );

        env.repo.markReadGatesById['a'] = Completer<void>();
        env.repo.markReadErrorsById['a'] = const NetworkFailure();
        final Future<bool> single = feed.markRead('a'); // held open
        await Future<void>.delayed(Duration.zero);

        env.repo.unread = 0; // the server, after the mark-all
        expect(await feed.markAllRead(), isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(_count(env), 0);

        env.repo.markReadGatesById['a']!.complete();
        final bool ok = await single;
        await Future<void>.delayed(Duration.zero);

        expect(ok, isTrue, reason: 'superseded: not a failure to report');
        expect(_count(env), 0, reason: 'no +1 rollback');
        expect(
          env.container
              .read(notificationsFeedProvider)
              .value!
              .items
              .every((AppNotification n) => n.read),
          isTrue,
          reason: 'the server holds it read',
        );
      },
    );

    test(
      'should_rollBack_when_theSingleFailsAfterMarkAll_onARowNewerThanUpTo',
      () async {
        final DateTime t0 = DateTime.utc(2026, 9, 30, 11, 40);
        final _Env env = _env(<NotificationPage>[
          onePage(<AppNotification>[notif('a', createdAt: t0)]),
        ]);
        env.container.listen(unreadNotificationsProvider, (_, _) {});
        env.container.listen(notificationsFeedProvider, (_, _) {});
        env.repo.unread = 1;
        await _login(env, 'A');
        final NotificationsFeed feed = env.container.read(
          notificationsFeedProvider.notifier,
        );

        // Mark-all starts with upTo = t0 and is held open.
        env.repo.markAllGate = Completer<void>();
        final Future<bool> markAll = feed.markAllRead();
        await Future<void>.delayed(Duration.zero);

        // A refresh lands a row NEWER than upTo; the user taps it.
        env.repo.pages = <NotificationPage>[
          onePage(<AppNotification>[
            notif('b', createdAt: t0.add(const Duration(hours: 1))),
            notif('a', createdAt: t0),
          ]),
        ];
        await feed.refresh();
        env.repo.markReadGatesById['b'] = Completer<void>();
        env.repo.markReadErrorsById['b'] = const NetworkFailure();
        final Future<bool> single = feed.markRead('b');
        await Future<void>.delayed(Duration.zero);

        env.repo.unread = 1; // b was never covered by the mark-all
        env.repo.markAllGate!.complete();
        expect(await markAll, isTrue);
        env.repo.markReadGatesById['b']!.complete();
        final bool ok = await single;
        await Future<void>.delayed(Duration.zero);

        expect(ok, isFalse, reason: 'not covered: a real failure');
        final List<AppNotification> items = env.container
            .read(notificationsFeedProvider)
            .value!
            .items;
        expect(
          items.firstWhere((AppNotification n) => n.id == 'b').read,
          isFalse,
        );
        expect(
          items.firstWhere((AppNotification n) => n.id == 'a').read,
          isTrue,
        );
        expect(feed.debugRecentlyReadIds, isNot(contains('b')));
      },
    );

    test(
      'should_endAtTheServerCount_when_theUncoveredRollbackFollowsTheRecount',
      () async {
        final DateTime t0 = DateTime.utc(2026, 9, 30, 11, 40);
        final _Env env = _env(<NotificationPage>[
          onePage(<AppNotification>[notif('a', createdAt: t0)]),
        ]);
        env.container.listen(unreadNotificationsProvider, (_, _) {});
        env.container.listen(notificationsFeedProvider, (_, _) {});
        env.repo.unread = 1;
        await _login(env, 'A');
        final NotificationsFeed feed = env.container.read(
          notificationsFeedProvider.notifier,
        );

        env.repo.markAllGate = Completer<void>();
        final Future<bool> markAll = feed.markAllRead();
        await Future<void>.delayed(Duration.zero);

        env.repo.pages = <NotificationPage>[
          onePage(<AppNotification>[
            notif('b', createdAt: t0.add(const Duration(hours: 1))),
            notif('a', createdAt: t0),
          ]),
        ];
        await feed.refresh();
        env.repo.markReadGatesById['b'] = Completer<void>();
        env.repo.markReadErrorsById['b'] = const NetworkFailure();
        final Future<bool> single = feed.markRead('b');
        await Future<void>.delayed(Duration.zero);

        // The server count INCLUDES the uncovered row b.
        env.repo.unread = 1;
        env.repo.markAllGate!.complete();
        expect(await markAll, isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(_count(env), 1, reason: 'the recount applied');

        env.repo.markReadGatesById['b']!.complete();
        expect(await single, isFalse);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(_count(env), 1, reason: 'the server count, not +1');
      },
    );

    test('should_keepOnlyTheLatestUpTo_when_noSingleIsPending', () async {
      final _Env env = _env(<NotificationPage>[
        onePage(<AppNotification>[notif('a')]),
      ]);
      env.container.listen(unreadNotificationsProvider, (_, _) {});
      env.container.listen(notificationsFeedProvider, (_, _) {});
      env.repo.unread = 1;
      await _login(env, 'A');
      final NotificationsFeed feed = env.container.read(
        notificationsFeedProvider.notifier,
      );
      for (int i = 0; i < 5; i++) {
        env.repo.unread = 1; // keeps mark-all from short-circuiting
        env.container
            .read(unreadNotificationsProvider.notifier)
            .setCount(1, forUserId: 'A');
        expect(await feed.markAllRead(), isTrue);
        expect(feed.debugMarkAllUpToCount, lessThanOrEqualTo(1));
      }
      expect(feed.debugMarkAllUpToCount, 1);
    });

    test(
      'should_retainEntriesANewerThanPendingSingleNeeds_thenPruneOnSettle',
      () async {
        final _Env env = _env(<NotificationPage>[
          onePage(<AppNotification>[notif('a'), notif('b')]),
        ]);
        env.container.listen(unreadNotificationsProvider, (_, _) {});
        env.container.listen(notificationsFeedProvider, (_, _) {});
        env.repo.unread = 2;
        await _login(env, 'A');
        final NotificationsFeed feed = env.container.read(
          notificationsFeedProvider.notifier,
        );
        env.repo.markReadGatesById['a'] = Completer<void>();
        final Future<bool> single = feed.markRead('a'); // issued at gen 0
        await Future<void>.delayed(Duration.zero);

        for (int i = 0; i < 3; i++) {
          env.repo.unread = 1;
          env.container
              .read(unreadNotificationsProvider.notifier)
              .setCount(1, forUserId: 'A');
          expect(await feed.markAllRead(), isTrue);
        }
        expect(
          feed.debugMarkAllUpToCount,
          3,
          reason: 'all newer than the pending single',
        );

        env.repo.markReadGatesById['a']!.complete();
        expect(await single, isTrue);
        expect(feed.debugMarkAllUpToCount, 1, reason: 'pruned on settle');
      },
    );

    test('should_sweepExpiredHolds_when_aNewRowIsNoted', () async {
      DateTime now = DateTime.utc(2026, 9, 30, 12);
      final _Env env = _env(<NotificationPage>[
        onePage(<AppNotification>[notif('a'), notif('b')]),
      ], clock: () => now);
      env.container.listen(unreadNotificationsProvider, (_, _) {});
      env.container.listen(notificationsFeedProvider, (_, _) {});
      env.repo.unread = 2;
      await _login(env, 'A');
      final NotificationsFeed feed = env.container.read(
        notificationsFeedProvider.notifier,
      );
      expect(await feed.markRead('a'), isTrue);
      expect(feed.debugRecentlyReadIds, <String>{'a'});

      now = now.add(const Duration(minutes: 3)); // past the 2 min hold
      expect(await feed.markRead('b'), isTrue);
      expect(feed.debugRecentlyReadIds, <String>{'b'});
    });

    test('should_stillRollBack_when_theSingleFailsBeforeAnyMarkAll', () async {
      final _Env env = _env(<NotificationPage>[
        onePage(<AppNotification>[notif('a')]),
      ]);
      env.container.listen(unreadNotificationsProvider, (_, _) {});
      env.container.listen(notificationsFeedProvider, (_, _) {});
      env.repo.unread = 1;
      await _login(env, 'A');
      env.repo.markReadError = const NetworkFailure();
      final NotificationsFeed feed = env.container.read(
        notificationsFeedProvider.notifier,
      );
      expect(await feed.markRead('a'), isFalse);
      expect(_count(env), 1);
      expect(
        env.container.read(notificationsFeedProvider).value!.items.single.read,
        isFalse,
      );
    });
  });

  test(
    'should_ignoreAStateOwnedByThePreviousUser_whenAnActionArrives',
    () async {
      final _Env env = _env(<NotificationPage>[
        onePage(<AppNotification>[notif('a'), notif('b')]),
      ]);
      env.container.listen(unreadNotificationsProvider, (_, _) {});
      env.container.listen(notificationsFeedProvider, (_, _) {});
      env.repo.unread = 2;
      await _login(env, 'A');
      expect(
        env.container.read(notificationsFeedProvider).value!.ownerUserId,
        'A',
      );

      // B signs in; B's first page is held open, so Riverpod keeps A's rows as
      // the previous value.
      env.repo.pageGate = Completer<void>();
      await _login(env, 'B');
      final NotificationsFeedState stale = env.container
          .read(notificationsFeedProvider)
          .value!;
      expect(
        stale.ownerUserId,
        'A',
        reason: 'the retained value is still A\'s',
      );

      final NotificationsFeed feed = env.container.read(
        notificationsFeedProvider.notifier,
      );
      final int before = _count(env)!;
      expect(
        await feed.markRead('a'),
        isTrue,
        reason: 'a no-op, not a failure',
      );
      expect(await feed.markAllRead(), isTrue);
      await feed.loadMore();

      expect(env.repo.markedRead, isEmpty);
      expect(env.repo.markAllUpTo, isEmpty);
      expect(env.repo.fetchedPages, <int>[0, 0], reason: 'no foreign page 1');
      expect(_count(env), before);
      expect(
        env.container
            .read(notificationsFeedProvider)
            .value!
            .items
            .where((AppNotification n) => n.read),
        isEmpty,
        reason: "A's rows must not be flipped",
      );

      env.repo.pageGate!.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(
        env.container.read(notificationsFeedProvider).value!.ownerUserId,
        'B',
      );
    },
  );

  group('refresh during an in-flight loadMore', () {
    NotificationsFeed feedOf(_Env env) =>
        env.container.read(notificationsFeedProvider.notifier);
    NotificationsFeedState stateOf(_Env env) =>
        env.container.read(notificationsFeedProvider).value!;

    test('should_dropTheStalePage_andNotStartADuplicate', () async {
      final _Env env = _env(<NotificationPage>[
        pageOf(0, 3, <AppNotification>[notif('a'), notif('b')]),
        pageOf(1, 3, <AppNotification>[notif('c'), notif('d')]),
        pageOf(2, 3, <AppNotification>[notif('e')]),
      ]);
      env.container.listen(notificationsFeedProvider, (_, _) {});
      await _login(env, 'A');
      expect(env.repo.fetchedPages, <int>[0]);

      // fetch #1 (page 1, the loadMore) is held; fetch #2 (the refresh) lands.
      env.repo.fetchGates[1] = Completer<void>();
      final Future<void> loadMore = feedOf(env).loadMore();
      await Future<void>.delayed(Duration.zero);
      expect(stateOf(env).loadingMore, isTrue);

      await feedOf(env).refresh();
      expect(env.repo.fetchedPages, <int>[0, 1, 0]);
      expect(
        stateOf(env).loadingMore,
        isTrue,
        reason: 'the refresh must not release a request still on the wire',
      );

      // A footer rebuilt by the refresh asks again: it must NOT hit the wire.
      await feedOf(env).loadMore();
      expect(env.repo.fetchedPages, <int>[0, 1, 0], reason: 'no duplicate');

      // The old page finally lands: dropped, never appended to the new list.
      env.repo.fetchGates[1]!.complete();
      await loadMore;
      expect(stateOf(env).items.map((AppNotification n) => n.id), <String>[
        'a',
        'b',
      ]);
      expect(stateOf(env).nextPage, 1);
      expect(stateOf(env).loadingMore, isFalse, reason: 'footer released');

      // ...and the next page is now requested once, against the new list.
      await feedOf(env).loadMore();
      expect(env.repo.fetchedPages, <int>[0, 1, 0, 1]);
      expect(stateOf(env).items.map((AppNotification n) => n.id), <String>[
        'a',
        'b',
        'c',
        'd',
      ]);
    });

    test('should_dropTheStaleFailure_too', () async {
      final _Env env = _env(<NotificationPage>[
        pageOf(0, 2, <AppNotification>[notif('a')]),
        pageOf(1, 2, <AppNotification>[notif('b')]),
      ]);
      env.container.listen(notificationsFeedProvider, (_, _) {});
      await _login(env, 'A');
      env.repo.fetchGates[1] = Completer<void>();
      env.repo.fetchErrors[1] = const NetworkFailure();
      final Future<void> loadMore = feedOf(env).loadMore();
      await Future<void>.delayed(Duration.zero);
      await feedOf(env).refresh();

      env.repo.fetchGates[1]!.complete();
      await loadMore;

      expect(stateOf(env).loadMoreFailure, isNull, reason: 'stale: ignored');
      expect(stateOf(env).loadingMore, isFalse);
    });

    test('should_notStartLoadMore_whileARefreshIsPending', () async {
      final _Env env = _env(<NotificationPage>[
        pageOf(0, 2, <AppNotification>[notif('a')]),
        pageOf(1, 2, <AppNotification>[notif('b')]),
      ]);
      env.container.listen(notificationsFeedProvider, (_, _) {});
      await _login(env, 'A');
      env.repo.fetchGates[1] = Completer<void>(); // the refresh's fetch
      final Future<void> refresh = feedOf(env).refresh();
      await Future<void>.delayed(Duration.zero);

      await feedOf(env).loadMore();
      expect(env.repo.fetchedPages, <int>[
        0,
        0,
      ], reason: 'parked behind refresh');

      env.repo.fetchGates[1]!.complete();
      await refresh;
    });
  });

  test('should_loadNothing_andRequestNothing_whenSignedOut', () async {
    final _Env env = _env(<NotificationPage>[
      onePage(<AppNotification>[notif('a')]),
    ]);
    env.container.listen(notificationsFeedProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final NotificationsFeedState state = env.container
        .read(notificationsFeedProvider)
        .value!;
    expect(state.items, isEmpty);
    expect(env.repo.fetchedPages, isEmpty);
  });
}
