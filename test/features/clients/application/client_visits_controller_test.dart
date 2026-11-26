// Client-profile audit (2026-11-22) — ClientVisitsController:
//   • a failed LOOKAHEAD page keeps the loaded pages (no timeline error), stops
//     the lookahead and pauses auto-append behind the retry footer;
//   • page 0 failing is still the timeline's error;
//   • refreshNow re-reads the injected clock (app resume) with no request, so
//     a head whose start passed moves into the history;
//   • the booking-mutation fan-out (`invalidateClientViews`) drops a cached
//     (unlistened, inside the 30 s window) instance — the next read refetches.
// The lookahead / paging / cache-for basics live in
// client_card_controllers_test.dart.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/clients/application/client_views_invalidation.dart';
import 'package:beautica_mobile/features/clients/application/client_visits_controller.dart';
import 'package:beautica_mobile/features/clients/data/client_repository.dart';
import 'package:beautica_mobile/features/clients/domain/client_card.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/clients/domain/client_visit.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_notification_repository.dart';
import '../../../helpers/test_container.dart';

const ClientListScope _me = ClientListScope.me();
const ClientRef _client = ClientRef.registered('u-1');

final DateTime _now = DateTime.utc(2026, 11, 20, 12);

ClientVisit _visit(String key, DateTime at, BookingStatus status) =>
    ClientVisit(
      visitKey: key,
      startsAt: at,
      items: <ClientVisitItem>[
        ClientVisitItem(
          bookingId: key,
          serviceName: 'Манікюр',
          status: status,
          startsAt: at,
        ),
      ],
    );

ClientVisit _future(String key, Duration ahead) =>
    _visit(key, _now.add(ahead), BookingStatus.confirmed);
ClientVisit _past(String key, int days) =>
    _visit(key, _now.subtract(Duration(days: days)), BookingStatus.completed);

class _Repo implements ClientRepository {
  _Repo(this.pages);

  List<List<ClientVisit>> pages;
  final List<int> visitPages = <int>[];
  final Set<int> failPages = <int>{};

  @override
  Future<ClientCard> getCard(
    ClientListScope scope,
    ClientRef client, {
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<PageResponse<ClientVisit>> getVisits(
    ClientListScope scope,
    ClientRef client, {
    int page = 0,
    int size = kClientPageSize,
    CancelToken? cancelToken,
  }) async {
    visitPages.add(page);
    if (failPages.contains(page)) throw const NetworkFailure();
    return PageResponse<ClientVisit>(
      items: pages[page],
      page: page,
      totalPages: pages.length,
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

/// The injected clock's current value (mutable for the resume tests).
DateTime _clock = _now;

ProviderContainer _container(_Repo repo) {
  _clock = _now;
  return makeTestContainer(
    retry: (_, _) => null,
    overrides: <Object>[
      clientRepositoryProvider.overrideWithValue(repo),
      clockProvider.overrideWithValue(() => _clock),
      authProvider.overrideWith(
        () => FixedRoleAuth(UserRole.independentMaster),
      ),
    ],
  );
}

ClientVisitsControllerProvider get _provider =>
    clientVisitsControllerProvider(_me, _client);

Future<ClientVisitsState> _visits(ProviderContainer c) async {
  await c.read(authProvider.future);
  final sub = c.listen(_provider, (_, _) {});
  addTearDown(sub.close);
  return c.read(_provider.future);
}

void main() {
  group('lookahead failure', () {
    test('a failed lookahead page keeps the loaded pages, stops, and pauses '
        'auto-append (retry footer) instead of failing the timeline', () async {
      final _Repo repo = _Repo(<List<ClientVisit>>[
        <ClientVisit>[_future('f3', const Duration(days: 30))],
        <ClientVisit>[_future('f2', const Duration(days: 20))],
        <ClientVisit>[_future('f1', const Duration(days: 5)), _past('p1', 3)],
      ])..failPages.add(1);
      final ProviderContainer c = _container(repo);
      final ClientVisitsState s = await _visits(c);

      expect(c.read(_provider).hasError, isFalse);
      expect(repo.visitPages, <int>[0, 1], reason: 'the lookahead stopped');
      expect(s.visits.map((ClientVisit v) => v.visitKey), <String>['f3']);
      expect(s.page, 0, reason: 'the cursor stays on the last loaded page');
      expect(s.hasMore, isTrue);
      expect(s.loadMoreFailed, isTrue);
      expect(s.canLoadMore, isFalse, reason: 'no retry storm');
      expect(s.nextVisit?.visitKey, 'f3', reason: 'what is loaded is shown');
    });

    test('retry after a failed lookahead re-issues the failed page', () async {
      final _Repo repo = _Repo(<List<ClientVisit>>[
        <ClientVisit>[_future('f2', const Duration(days: 20))],
        <ClientVisit>[_future('f1', const Duration(days: 5)), _past('p1', 3)],
      ])..failPages.add(1);
      final ProviderContainer c = _container(repo);
      await _visits(c);
      repo.failPages.clear();
      await c.read(_provider.notifier).retryLoadMore();
      final ClientVisitsState? s = c.read(_provider).value;
      expect(repo.visitPages, <int>[0, 1, 1]);
      expect(s?.loadMoreFailed, isFalse);
      expect(s?.nextVisit?.visitKey, 'f1');
    });

    test('page 0 failing is still the timeline error', () async {
      final _Repo repo = _Repo(<List<ClientVisit>>[
        <ClientVisit>[_past('p1', 3)],
      ])..failPages.add(0);
      final ProviderContainer c = _container(repo);
      await expectLater(_visits(c), throwsA(isA<NetworkFailure>()));
    });
  });

  group('refreshNow (app resume)', () {
    test('re-reads the clock: a head whose start passed moves into the '
        'history, no request', () async {
      final _Repo repo = _Repo(<List<ClientVisit>>[
        <ClientVisit>[_future('soon', const Duration(hours: 1)), _past('p', 3)],
      ]);
      final ProviderContainer c = _container(repo);
      final ClientVisitsState before = await _visits(c);
      expect(before.nextVisit?.visitKey, 'soon');

      _clock = _now.add(const Duration(hours: 2));
      c.read(_provider.notifier).refreshNow();
      final ClientVisitsState? after = c.read(_provider).value;
      expect(after?.asOf, _clock);
      expect(after?.nextVisit, isNull);
      expect(after?.history.map((ClientVisit v) => v.visitKey), <String>[
        'soon',
        'p',
      ]);
      expect(repo.visitPages, <int>[0], reason: 'no refetch');
    });

    test('an unchanged clock emits nothing new', () async {
      final _Repo repo = _Repo(<List<ClientVisit>>[
        <ClientVisit>[_past('p', 3)],
      ]);
      final ProviderContainer c = _container(repo);
      final ClientVisitsState before = await _visits(c);
      c.read(_provider.notifier).refreshNow();
      expect(identical(c.read(_provider).value, before), isTrue);
    });
  });

  test('invalidateClientViews drops a cached (unlistened) instance inside '
      'the cache window: the next read refetches', () async {
    final _Repo repo = _Repo(<List<ClientVisit>>[
      <ClientVisit>[_past('p', 3)],
    ]);
    final ProviderContainer c = _container(repo);
    await c.read(authProvider.future);
    final sub = c.listen(_provider, (_, _) {});
    await c.read(_provider.future);
    sub.close();
    await Future<void>.delayed(Duration.zero);
    expect(c.exists(_provider), isTrue, reason: 'cached for 30 s');

    // The same tear-off shape every booking mutation helper passes.
    invalidateClientViews(c.invalidate);
    repo.pages = <List<ClientVisit>>[
      <ClientVisit>[_past('p-new', 1)],
    ];
    final ClientVisitsState s = await _visits(c);
    expect(repo.visitPages, <int>[0, 0]);
    expect(s.visits.single.visitKey, 'p-new');
  });
}
