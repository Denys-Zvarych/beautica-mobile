// M510 — the card's data controllers: the card provider (404 →
// NotFoundFailure for the not-found state) and the visits timeline (paging, a
// failed append pausing auto-append; M531 / CLI-89: the head is the card's
// `nextVisit` and the first load reads ONE visits page). Signed out →
// the card fails with UnauthorizedFailure and no request; an append that
// resolves after a refresh never overwrites the fresh state (generation guard).
// CLI-74: a salon scope with a `masterId` is its own visits family member and
// sends that `masterId` on every page (first load AND append).
// Cache-for: an unlistened visits instance stays cached for
// [kClientVisitsCacheFor] (a chip back-and-forth re-reads nothing), then
// disposes.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/clients/application/client_card_controller.dart';
import 'package:beautica_mobile/features/clients/application/client_visits_controller.dart';
import 'package:beautica_mobile/features/clients/data/client_repository.dart';
import 'package:beautica_mobile/features/clients/domain/client_card.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/clients/domain/client_visit.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_notification_repository.dart';
import '../../../helpers/test_container.dart';

const ClientListScope _me = ClientListScope.me();

/// One fake-async step: lets Riverpod's scheduler and the fake repo settle.
const Duration _tick = Duration(milliseconds: 1);
const ClientRef _client = ClientRef.registered('u-1');

final DateTime _now = DateTime.utc(2026, 11, 20, 12);

ClientVisit _visit(
  String key,
  DateTime at, {
  BookingStatus status = BookingStatus.confirmed,
}) => ClientVisit(
  visitKey: key,
  startsAt: at,
  items: <ClientVisitItem>[
    ClientVisitItem(
      // One row per BOOKING: the flattened key is the bookingId, so the
      // fixture uses the same id for both.
      bookingId: key,
      serviceName: 'Манікюр',
      status: status,
      startsAt: at,
    ),
  ],
);

class _SignedOutAuth extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.unauthenticated();
}

class _Repo implements ClientRepository {
  _Repo({
    this.cardFailure,
    this.pages = const <List<ClientVisit>>[],
    this.nextVisit,
  });

  Failure? cardFailure;

  /// When set, every card request waits on this.
  Completer<void>? cardGate;

  /// The card's `nextVisit` (B530), as the server would send it.
  ClientVisit? nextVisit;

  /// The scope of every card request, in order.
  final List<ClientListScope> cardScopes = <ClientListScope>[];

  /// Visit pages, newest first; the last page has no successor.
  List<List<ClientVisit>> pages;
  final List<int> visitPages = <int>[];

  /// The scope of every visits request, in order (CLI-74 `masterId`).
  final List<ClientListScope> visitScopes = <ClientListScope>[];
  int failVisitPage = -1;

  /// When set, the visits request for [gatedVisitPage] waits on this.
  Completer<void>? visitGate;
  int gatedVisitPage = -1;

  int cardCalls = 0;

  @override
  Future<ClientCard> getCard(
    ClientListScope scope,
    ClientRef client, {
    CancelToken? cancelToken,
  }) async {
    cardCalls++;
    cardScopes.add(scope);
    final Completer<void>? gate = cardGate;
    if (gate != null) await gate.future;
    final Failure? f = cardFailure;
    if (f != null) throw f;
    return ClientCard(ref: client, displayName: 'Оксана', nextVisit: nextVisit);
  }

  @override
  Future<PageResponse<ClientVisit>> getVisits(
    ClientListScope scope,
    ClientRef client, {
    int page = 0,
    int size = kClientPageSize,
    CancelToken? cancelToken,
  }) async {
    visitPages.add(page);
    visitScopes.add(scope);
    final List<List<ClientVisit>> served = pages;
    final Completer<void>? gate = visitGate;
    if (gate != null && page == gatedVisitPage) await gate.future;
    if (page == failVisitPage) throw const NetworkFailure();
    return PageResponse<ClientVisit>(
      items: served[page],
      page: page,
      totalPages: served.length,
      totalElements: 0,
    );
  }

  @override
  Future<PageResponse<ClientSummary>> list(
    ClientListScope scope, {
    String? q,
    int page = 0,
    int size = kClientPageSize,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<void> removeFromList(ClientListScope scope, ClientRef client) =>
      throw UnimplementedError();

  @override
  Future<void> restoreToList(ClientListScope scope, ClientRef client) =>
      throw UnimplementedError();
}

ProviderContainer _container(_Repo repo, {bool signedOut = false}) =>
    makeTestContainer(
      retry: (_, _) => null,
      overrides: <Object>[
        clientRepositoryProvider.overrideWithValue(repo),
        clockProvider.overrideWithValue(() => _now),
        authProvider.overrideWith(
          () => signedOut
              ? _SignedOutAuth()
              : FixedRoleAuth(UserRole.independentMaster),
        ),
      ],
    );

Future<ClientVisitsState> _visits(ProviderContainer c) async {
  await c.read(authProvider.future);
  final sub = c.listen(clientVisitsControllerProvider(_me, _client), (_, _) {});
  addTearDown(sub.close);
  return c.read(clientVisitsControllerProvider(_me, _client).future);
}

ClientVisit _future(String key, int days) =>
    _visit(key, _now.add(Duration(days: days)));
ClientVisit _past(String key, int days) => _visit(
  key,
  _now.subtract(Duration(days: days)),
  status: BookingStatus.completed,
);

void main() {
  group('card provider', () {
    test('404 surfaces as NotFoundFailure (the not-found state)', () async {
      final c = _container(_Repo(cardFailure: const NotFoundFailure()));
      await c.read(authProvider.future);
      final sub = c.listen(clientCardProvider(_me, _client), (_, _) {});
      addTearDown(sub.close);
      await expectLater(
        c.read(clientCardProvider(_me, _client).future),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test('data → the card for the requested handle', () async {
      final c = _container(_Repo());
      await c.read(authProvider.future);
      final sub = c.listen(clientCardProvider(_me, _client), (_, _) {});
      addTearDown(sub.close);
      final ClientCard card = await c.read(
        clientCardProvider(_me, _client).future,
      );
      expect(card.ref, _client);
    });

    test('signed out → UnauthorizedFailure, no request', () async {
      final repo = _Repo();
      final c = _container(repo, signedOut: true);
      await c.read(authProvider.future);
      final sub = c.listen(clientCardProvider(_me, _client), (_, _) {});
      addTearDown(sub.close);
      await expectLater(
        c.read(clientCardProvider(_me, _client).future),
        throwsA(isA<UnauthorizedFailure>()),
      );
      expect(repo.cardCalls, 0);
    });
  });

  group('visits — next visit from the card (M531 / CLI-89)', () {
    test('head = the card\'s nextVisit after ONE page, even when page 0 is '
        'all future; the history excludes it', () async {
      final repo = _Repo(
        nextVisit: _future('f1', 5),
        pages: <List<ClientVisit>>[
          <ClientVisit>[_future('f3', 30), _future('f2', 20)],
          <ClientVisit>[_future('f1', 5), _past('p1', 3)],
        ],
      );
      final ClientVisitsState s = await _visits(_container(repo));
      expect(repo.visitPages, <int>[0], reason: 'no lookahead');
      expect(repo.cardCalls, 1, reason: 'one card read, shared');
      expect(s.nextVisit?.visitKey, 'f1');
      expect(s.history.map((v) => v.visitKey), <String>['f3', 'f2']);
      expect(s.hasMore, isTrue);
    });

    test('60 future visits: one visits page on first open', () async {
      final repo = _Repo(
        nextVisit: _future('f0', 1),
        pages: <List<ClientVisit>>[
          for (int p = 0; p < 3; p++)
            <ClientVisit>[
              for (int i = 0; i < 20; i++)
                _future('f${60 - (p * 20 + i) - 1}', 60 - (p * 20 + i)),
            ],
        ],
      );
      final ClientVisitsState s = await _visits(_container(repo));
      expect(repo.visitPages, <int>[0]);
      expect(s.nextVisit?.visitKey, 'f0');
      expect(s.history, hasLength(20));
    });

    test('card nextVisit null → no head, one visits page', () async {
      final repo = _Repo(
        pages: <List<ClientVisit>>[
          <ClientVisit>[_future('f1', 5), _past('p1', 3)],
        ],
      );
      final ClientVisitsState s = await _visits(_container(repo));
      expect(repo.visitPages, <int>[0]);
      expect(s.nextVisit, isNull);
      expect(s.history.map((v) => v.visitKey), <String>['f1', 'p1']);
    });

    test('the head\'s booking on a later page is not duplicated', () async {
      final repo = _Repo(
        nextVisit: _future('f1', 5),
        pages: <List<ClientVisit>>[
          <ClientVisit>[_future('f2', 20)],
          <ClientVisit>[_future('f1', 5), _past('p1', 3)],
        ],
      );
      final c = _container(repo);
      await _visits(c);
      await c
          .read(clientVisitsControllerProvider(_me, _client).notifier)
          .loadMore();
      final ClientVisitsState s = c
          .read(clientVisitsControllerProvider(_me, _client))
          .requireValue;
      expect(s.visits.map((v) => v.visitKey), <String>['f2', 'f1', 'p1']);
      expect(s.nextVisit?.visitKey, 'f1');
      expect(s.history.map((v) => v.visitKey), <String>['f2', 'p1']);
    });

    test('card and visits invalidated together → one card and one page-0 '
        'read (pull-to-refresh, no double fetch)', () async {
      final repo = _Repo(
        nextVisit: _future('f1', 5),
        pages: <List<ClientVisit>>[
          <ClientVisit>[_future('f1', 5), _past('p1', 3)],
        ],
      );
      final c = _container(repo);
      await _visits(c);
      final cardSub = c.listen(clientCardProvider(_me, _client), (_, _) {});
      addTearDown(cardSub.close);
      await c.read(clientCardProvider(_me, _client).future);
      expect(repo.cardCalls, 1);
      c
        ..invalidate(clientCardProvider(_me, _client))
        ..invalidate(clientVisitsControllerProvider(_me, _client));
      await c.read(clientCardProvider(_me, _client).future);
      await c.read(clientVisitsControllerProvider(_me, _client).future);
      expect(repo.cardCalls, 2);
      expect(repo.visitPages, <int>[0, 0]);
    });

    test('a card refresh alone swaps the head in place: no page re-read, '
        'appended pages kept', () async {
      final repo = _Repo(
        nextVisit: _future('f2', 20),
        pages: <List<ClientVisit>>[
          <ClientVisit>[_future('f2', 20), _future('f1', 5)],
          <ClientVisit>[_past('p1', 3)],
        ],
      );
      final c = _container(repo);
      await _visits(c);
      await c
          .read(clientVisitsControllerProvider(_me, _client).notifier)
          .loadMore();
      repo.nextVisit = _future('f1', 5);
      c.invalidate(clientCardProvider(_me, _client));
      await c.read(clientCardProvider(_me, _client).future);
      final ClientVisitsState s = c
          .read(clientVisitsControllerProvider(_me, _client))
          .requireValue;
      expect(repo.cardCalls, 2);
      expect(repo.visitPages, <int>[0, 1]);
      expect(s.page, 1);
      expect(s.visits.map((v) => v.visitKey), <String>['f2', 'f1', 'p1']);
      expect(s.nextVisit?.visitKey, 'f1');
      expect(s.history.map((v) => v.visitKey), <String>['f2', 'p1']);
    });

    test('page 0 is requested before the card resolves (parallel)', () async {
      final repo = _Repo(
        nextVisit: _future('f1', 5),
        pages: <List<ClientVisit>>[
          <ClientVisit>[_future('f1', 5)],
        ],
      )..cardGate = Completer<void>();
      final c = _container(repo);
      await c.read(authProvider.future);
      final sub = c.listen(
        clientVisitsControllerProvider(_me, _client),
        (_, _) {},
      );
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);
      expect(repo.cardCalls, 1);
      expect(repo.visitPages, <int>[0]);
      expect(
        c.read(clientVisitsControllerProvider(_me, _client)).isLoading,
        isTrue,
      );
      repo.cardGate?.complete();
      final ClientVisitsState s = await c.read(
        clientVisitsControllerProvider(_me, _client).future,
      );
      expect(s.nextVisit?.visitKey, 'f1');
      expect(repo.visitPages, <int>[0]);
    });

    test('card failure → the timeline errors with the card failure; a card '
        'retry that succeeds rebuilds it', () async {
      final repo = _Repo(
        nextVisit: _future('f1', 5),
        pages: <List<ClientVisit>>[
          <ClientVisit>[_future('f1', 5), _past('p1', 3)],
        ],
      )..cardFailure = const NetworkFailure();
      final c = _container(repo);
      await expectLater(_visits(c), throwsA(isA<NetworkFailure>()));
      repo.cardFailure = null;
      c.invalidate(clientCardProvider(_me, _client));
      await c.read(clientCardProvider(_me, _client).future);
      final ClientVisitsState s = await c.read(
        clientVisitsControllerProvider(_me, _client).future,
      );
      expect(s.nextVisit?.visitKey, 'f1');
      expect(s.history.map((v) => v.visitKey), <String>['p1']);
      expect(repo.visitPages, <int>[0, 0]);
    });

    test('page 0 fails on refresh → a card-only refresh rebuilds the timeline '
        '(new page-0 read), never the stale pages as AsyncData', () async {
      final repo = _Repo(
        nextVisit: _future('f1', 5),
        pages: <List<ClientVisit>>[
          <ClientVisit>[_future('f1', 5), _past('p1', 3)],
        ],
      );
      final c = _container(repo);
      final provider = clientVisitsControllerProvider(_me, _client);
      await _visits(c);
      final cardSub = c.listen(clientCardProvider(_me, _client), (_, _) {});
      addTearDown(cardSub.close);
      repo.failVisitPage = 0;
      c
        ..invalidate(clientCardProvider(_me, _client))
        ..invalidate(provider);
      await c.read(clientCardProvider(_me, _client).future);
      await expectLater(
        c.read(provider.future),
        throwsA(isA<NetworkFailure>()),
      );
      final AsyncValue<ClientVisitsState> failed = c.read(provider);
      expect(failed.hasError, isTrue);
      expect(failed.value, isNotNull, reason: 'Riverpod 3 keeps the value');
      expect(repo.visitPages, <int>[0, 0]);

      repo
        ..failVisitPage = -1
        ..nextVisit = _future('f2', 9)
        ..pages = <List<ClientVisit>>[
          <ClientVisit>[_future('f2', 9), _past('p2', 1)],
        ];
      c.invalidate(clientCardProvider(_me, _client));
      await c.read(clientCardProvider(_me, _client).future);
      final ClientVisitsState s = await c.read(provider.future);
      expect(repo.visitPages, <int>[0, 0, 0], reason: 'rebuilt: new page 0');
      expect(c.read(provider).hasError, isFalse);
      expect(s.visits.map((v) => v.visitKey), <String>['f2', 'p2']);
      expect(s.nextVisit?.visitKey, 'f2');
    });

    test('an appointment as nextVisit: head = its earliest CONFIRMED future '
        'booking; the sibling booking stays in the history (CLI-78)', () async {
      final DateTime at = _now.add(const Duration(days: 2));
      final ClientVisit appointment = ClientVisit(
        visitKey: 'appt-1',
        startsAt: at,
        items: <ClientVisitItem>[
          ClientVisitItem(
            bookingId: 'b-early',
            serviceName: 'Губи',
            status: BookingStatus.confirmed,
            startsAt: at,
          ),
          ClientVisitItem(
            bookingId: 'b-late',
            serviceName: 'Пілінг шкіри голови',
            status: BookingStatus.confirmed,
            startsAt: at.add(const Duration(hours: 1)),
          ),
        ],
      );
      final repo = _Repo(
        nextVisit: appointment,
        pages: <List<ClientVisit>>[
          <ClientVisit>[appointment, _past('p1', 3)],
        ],
      );
      final ClientVisitsState s = await _visits(_container(repo));
      expect(s.visits.map((v) => v.visitKey), <String>[
        'b-late',
        'b-early',
        'p1',
      ]);
      expect(s.visits.every((v) => v.items.length == 1), isTrue);
      expect(s.nextVisit?.visitKey, 'b-early');
      expect(s.nextVisit?.items, hasLength(1));
      expect(s.history.map((v) => v.visitKey), <String>['b-late', 'p1']);
    });

    test(
      'a cancelled / declined future visit is never the next visit',
      () async {
        final ClientVisit cancelled = _visit(
          'x',
          _now.add(const Duration(days: 1)),
          status: BookingStatus.cancelled,
        );
        final repo = _Repo(
          nextVisit: cancelled,
          pages: <List<ClientVisit>>[
            <ClientVisit>[cancelled, _past('p1', 3)],
          ],
        );
        final ClientVisitsState s = await _visits(_container(repo));
        expect(s.nextVisit, isNull);
        expect(s.history, hasLength(2));
      },
    );

    test('empty client → empty state, no more pages', () async {
      final repo = _Repo(pages: <List<ClientVisit>>[<ClientVisit>[]]);
      final ClientVisitsState s = await _visits(_container(repo));
      expect(s.visits, isEmpty);
      expect(s.nextVisit, isNull);
      expect(s.hasMore, isFalse);
    });
  });

  group('visits — master filter (CLI-74)', () {
    const ClientListScope salon = ClientListScope.salon(salonId: 's-1');
    const ClientListScope filtered = ClientListScope.salon(
      salonId: 's-1',
      masterId: 'm-1',
    );

    test('a masterId scope reads with that masterId on first load and '
        'append; the unfiltered scope is a separate read', () async {
      final repo = _Repo(
        pages: <List<ClientVisit>>[
          <ClientVisit>[_past('a', 1)],
          <ClientVisit>[_past('b', 2)],
        ],
      );
      final c = _container(repo);
      await c.read(authProvider.future);
      final sub = c.listen(
        clientVisitsControllerProvider(filtered, _client),
        (_, _) {},
      );
      addTearDown(sub.close);
      await c.read(clientVisitsControllerProvider(filtered, _client).future);
      await c
          .read(clientVisitsControllerProvider(filtered, _client).notifier)
          .loadMore();
      expect(repo.visitScopes, <ClientListScope>[filtered, filtered]);

      final sub2 = c.listen(
        clientVisitsControllerProvider(salon, _client),
        (_, _) {},
      );
      addTearDown(sub2.close);
      await c.read(clientVisitsControllerProvider(salon, _client).future);
      expect(repo.visitScopes.last, salon);
      expect(repo.visitPages, <int>[0, 1, 0]);
      expect(repo.cardScopes, <ClientListScope>[
        filtered,
        salon,
      ], reason: 'the head follows the chip (E4)');
    });
  });

  group('visits — paging', () {
    test('loadMore appends; a failed append pauses until retry', () async {
      final repo = _Repo(
        pages: <List<ClientVisit>>[
          <ClientVisit>[_past('p1', 1)],
          <ClientVisit>[_past('p2', 2)],
          <ClientVisit>[_past('p3', 3)],
        ],
      );
      final c = _container(repo);
      await _visits(c);
      final notifier = c.read(
        clientVisitsControllerProvider(_me, _client).notifier,
      );
      repo.failVisitPage = 1;
      await notifier.loadMore();
      ClientVisitsState s = c
          .read(clientVisitsControllerProvider(_me, _client))
          .requireValue;
      expect(s.loadMoreFailed, isTrue);
      expect(s.visits, hasLength(1), reason: 'the list stays');
      expect(s.canLoadMore, isFalse);

      repo.visitPages.clear();
      await notifier.loadMore();
      expect(repo.visitPages, isEmpty, reason: 'auto-append is paused');

      repo.failVisitPage = -1;
      await notifier.retryLoadMore();
      s = c.read(clientVisitsControllerProvider(_me, _client)).requireValue;
      expect(s.visits.map((v) => v.visitKey), <String>['p1', 'p2']);
      expect(s.loadMoreFailed, isFalse);

      await notifier.loadMore();
      s = c.read(clientVisitsControllerProvider(_me, _client)).requireValue;
      expect(s.visits, hasLength(3));
      expect(s.hasMore, isFalse);
      await notifier.loadMore();
      expect(repo.visitPages.last, 2, reason: 'no page past the last');
    });

    for (final bool fails in <bool>[false, true]) {
      test('a refresh during an in-flight append keeps the FRESH state '
          '(${fails ? 'failed' : 'successful'} stale append)', () async {
        final repo = _Repo(
          pages: <List<ClientVisit>>[
            <ClientVisit>[_past('old1', 1)],
            <ClientVisit>[_past('old2', 2)],
          ],
        );
        final c = _container(repo);
        await _visits(c);
        final provider = clientVisitsControllerProvider(_me, _client);
        final gate = Completer<void>();
        repo
          ..visitGate = gate
          ..gatedVisitPage = 1
          ..failVisitPage = fails ? 1 : -1;
        final Future<void> append = c.read(provider.notifier).loadMore();

        // Refresh while page 1 is in flight; the server now serves new data.
        repo.pages = <List<ClientVisit>>[
          <ClientVisit>[_past('fresh', 1)],
          <ClientVisit>[_past('fresh2', 2)],
        ];
        c.invalidate(provider);
        final ClientVisitsState fresh = await c.read(provider.future);
        expect(fresh.visits.map((v) => v.visitKey), <String>['fresh']);

        gate.complete();
        await append;
        final ClientVisitsState s = c.read(provider).requireValue;
        expect(
          s.visits.map((v) => v.visitKey),
          <String>['fresh'],
          reason: 'the stale append must not overwrite the refreshed list',
        );
        expect(s.page, 0);
        expect(s.isLoadingMore, isFalse);
        expect(s.loadMoreFailed, isFalse);
      });
    }

    test('loadMore during a pull-to-refresh is a no-op: no request, the '
        'loading state is kept', () async {
      final repo = _Repo(
        pages: <List<ClientVisit>>[
          <ClientVisit>[_past('old1', 1)],
          <ClientVisit>[_past('old2', 2)],
        ],
      );
      final c = _container(repo);
      await _visits(c);
      final provider = clientVisitsControllerProvider(_me, _client);
      final gate = Completer<void>();
      repo
        ..visitGate = gate
        ..gatedVisitPage = 0;
      c.invalidate(provider);
      expect(c.read(provider).isLoading, isTrue);
      repo.visitPages.clear();

      await c.read(provider.notifier).loadMore();

      // Page 0 now lands after the card read (a microtask later), so only the
      // page-1 request is the thing that must not happen.
      expect(
        repo.visitPages,
        isNot(contains(1)),
        reason: 'no throwaway page-1 request',
      );
      expect(c.read(provider).isLoading, isTrue);
      gate.complete();
      final ClientVisitsState s = await c.read(provider.future);
      expect(s.visits.map((v) => v.visitKey), <String>['old1']);
      expect(s.isLoadingMore, isFalse);
    });
  });

  group('visits — cache-for (kClientVisitsCacheFor)', () {
    test('unlistened: cached inside the window (no re-read), the timer '
        'restarts on each cancel, disposed after it', () {
      fakeAsync((FakeAsync async) {
        final repo = _Repo(
          pages: <List<ClientVisit>>[
            <ClientVisit>[_past('p1', 1)],
          ],
        );
        final c = _container(repo);
        final provider = clientVisitsControllerProvider(_me, _client);
        const Duration almost = Duration(seconds: 29);
        expect(kClientVisitsCacheFor, const Duration(seconds: 30));

        ProviderSubscription<AsyncValue<ClientVisitsState>> sub = c.listen(
          provider,
          (_, _) {},
        );
        async.elapse(_tick);
        expect(c.read(provider).value?.visits.single.visitKey, 'p1');
        expect(repo.visitPages, <int>[0]);

        sub.close();
        async.elapse(almost);
        expect(c.exists(provider), isTrue, reason: 'still cached');
        sub = c.listen(provider, (_, _) {});
        async.elapse(_tick);
        expect(repo.visitPages, <int>[0], reason: 'no re-read in the window');
        expect(c.read(provider).value?.visits.single.visitKey, 'p1');

        // Resumed → the old timer is cancelled; a new cancel restarts it.
        sub.close();
        async.elapse(almost);
        expect(c.exists(provider), isTrue);
        async.elapse(const Duration(seconds: 2));
        async.elapse(_tick);
        expect(c.exists(provider), isFalse, reason: 'released after 30 s');

        sub = c.listen(provider, (_, _) {});
        async.elapse(_tick);
        expect(repo.visitPages, <int>[0, 0], reason: 'a fresh read');
        sub.close();
        c.dispose();
        async.flushTimers();
      });
    });
  });
}
