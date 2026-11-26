// M510 — the card's data controllers: the card provider (404 →
// NotFoundFailure for the not-found state) and the visits timeline (paging, D4
// next-visit lookahead stopping at the first past visit and at 5 pages, a
// failed append pausing auto-append). Signed out →
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
  _Repo({this.cardFailure, this.pages = const <List<ClientVisit>>[]});

  final Failure? cardFailure;

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
    final Failure? f = cardFailure;
    if (f != null) throw f;
    return ClientCard(ref: client, displayName: 'Оксана');
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

  group('visits — D4 next-visit lookahead', () {
    test('first page only when it already reaches a past visit', () async {
      final repo = _Repo(
        pages: <List<ClientVisit>>[
          <ClientVisit>[_future('f1', 5), _past('p1', 3)],
          <ClientVisit>[_past('p2', 9)],
        ],
      );
      final ClientVisitsState s = await _visits(_container(repo));
      expect(repo.visitPages, <int>[
        0,
      ], reason: 'a past visit ends the lookahead');
      expect(s.nextVisit?.visitKey, 'f1');
      expect(s.history.map((v) => v.visitKey), <String>['p1']);
      expect(s.hasMore, isTrue);
    });

    test(
      'a grouped API visit becomes ONE entry per booking (BOOK-05): key = '
      'bookingId, newest first; next = the earliest upcoming booking',
      () async {
        final DateTime at = _now.add(const Duration(days: 2));
        final repo = _Repo(
          pages: <List<ClientVisit>>[
            <ClientVisit>[
              ClientVisit(
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
              ),
              _past('p1', 3),
            ],
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
        expect(s.history.map((v) => v.visitKey), <String>['b-late', 'p1']);
      },
    );

    test('keeps loading while every visit is in the future', () async {
      final repo = _Repo(
        pages: <List<ClientVisit>>[
          <ClientVisit>[_future('f3', 30), _future('f2', 20)],
          <ClientVisit>[_future('f1', 5), _past('p1', 3)],
          <ClientVisit>[_past('p2', 9)],
        ],
      );
      final ClientVisitsState s = await _visits(_container(repo));
      expect(repo.visitPages, <int>[0, 1]);
      expect(
        s.nextVisit?.visitKey,
        'f1',
        reason: 'the earliest upcoming visit is on the OLDER page',
      );
      expect(s.history.any((v) => v.visitKey == 'f1'), isFalse);
    });

    test('stops at 5 pages even if all are still future', () async {
      final repo = _Repo(
        pages: <List<ClientVisit>>[
          for (int i = 0; i < 8; i++) <ClientVisit>[_future('f$i', 100 - i)],
        ],
      );
      final ClientVisitsState s = await _visits(_container(repo));
      expect(repo.visitPages, <int>[0, 1, 2, 3, 4]);
      expect(s.hasMore, isTrue);
    });

    test(
      'a cancelled / declined future visit is never the next visit',
      () async {
        final repo = _Repo(
          pages: <List<ClientVisit>>[
            <ClientVisit>[
              _visit(
                'x',
                _now.add(const Duration(days: 1)),
                status: BookingStatus.cancelled,
              ),
              _past('p1', 3),
            ],
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

      expect(repo.visitPages, <int>[], reason: 'no throwaway page-1 request');
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
