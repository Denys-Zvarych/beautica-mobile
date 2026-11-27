// Client-profile audit (2026-11-22) — ClientVisitsController:
//   • page 0 failing is still the timeline's error (M531: so does the card,
//     the head's source);
//   • refreshNow re-reads the injected clock (app resume) with no request, so
//     a head whose start passed moves into the history;
//   • the booking-mutation fan-out (`invalidateClientViews`) drops a cached
//     (unlistened, inside the 30 s window) instance — the next read refetches.
// The next-visit / paging / cache-for basics live in
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

  /// The card's `nextVisit` (B530), the timeline head's source.
  ClientVisit? nextVisit;
  Failure? cardFailure;

  @override
  Future<ClientCard> getCard(
    ClientListScope scope,
    ClientRef client, {
    CancelToken? cancelToken,
  }) async {
    final Failure? f = cardFailure;
    if (f != null) throw f;
    return ClientCard(ref: client, nextVisit: nextVisit);
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
  group('first load failures', () {
    test('page 0 failing is still the timeline error', () async {
      final _Repo repo = _Repo(<List<ClientVisit>>[
        <ClientVisit>[_past('p1', 3)],
      ])..failPages.add(0);
      final ProviderContainer c = _container(repo);
      await expectLater(_visits(c), throwsA(isA<NetworkFailure>()));
    });

    test('the card failing fails the timeline with the CARD failure; page 0 '
        'was already in flight (parallel) and its own failure stays '
        'handled', () async {
      final _Repo repo =
          _Repo(<List<ClientVisit>>[
              <ClientVisit>[_past('p1', 3)],
            ])
            ..cardFailure = const NotFoundFailure()
            ..failPages.add(0);
      final ProviderContainer c = _container(repo);
      await expectLater(_visits(c), throwsA(isA<NotFoundFailure>()));
      expect(repo.visitPages, <int>[0]);
    });
  });

  group('refreshNow (app resume)', () {
    test('re-reads the clock: a head whose start passed moves into the '
        'history, no request', () async {
      final _Repo repo = _Repo(<List<ClientVisit>>[
        <ClientVisit>[_future('soon', const Duration(hours: 1)), _past('p', 3)],
      ])..nextVisit = _future('soon', const Duration(hours: 1));
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
