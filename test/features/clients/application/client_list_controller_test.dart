// M509 — ClientListController: paging, search debounce / `q` rule, refresh,
// retry, scope → call mapping, and the session-boundary rebuild.
//
// Search timing: the debounce is a real `Timer`. These tests create it inside
// a `FakeAsync` zone and `elapse` the window explicitly — no wall-clock waits.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/clients/application/client_list_controller.dart';
import 'package:beautica_mobile/features/clients/data/client_repository.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_notification_repository.dart';
import '../../../helpers/test_container.dart';

class _Call {
  _Call(this.scope, this.q, this.page, this.size, this.token);
  final ClientListScope scope;
  final String? q;
  final int page;
  final int size;
  final CancelToken? token;
}

/// Serves `total` rows in pages of `pageSize`; a per-call hook can delay or
/// fail a request.
class _FakeClientRepository implements ClientRepository {
  _FakeClientRepository({this.total = 45});

  final int total;
  final int pageSize = 20;
  final List<_Call> calls = <_Call>[];

  /// Return a future to take over a call (null = serve normally).
  Future<PageResponse<ClientSummary>>? Function(_Call call)? hook;

  /// Names rows `Клієнт <q?> <n>` so a test can tell result sets apart.
  @override
  Future<PageResponse<ClientSummary>> list(
    ClientListScope scope, {
    String? q,
    int page = 0,
    int size = kClientPageSize,
    CancelToken? cancelToken,
  }) {
    final _Call call = _Call(scope, q, page, size, cancelToken);
    calls.add(call);
    final Future<PageResponse<ClientSummary>>? taken = hook?.call(call);
    if (taken != null) return taken;
    return Future<PageResponse<ClientSummary>>.value(_serve(q, page));
  }

  PageResponse<ClientSummary> _serve(String? q, int page) {
    final int from = page * pageSize;
    final int to = (from + pageSize).clamp(0, total);
    return PageResponse<ClientSummary>(
      items: <ClientSummary>[for (int i = from; i < to; i++) row(i, q: q)],
      page: page,
      totalPages: (total / pageSize).ceil(),
      totalElements: total,
    );
  }

  static ClientSummary row(int i, {String? q}) => ClientSummary(
    ref: ClientRef.registered('u$i'),
    displayName: 'Клієнт ${q ?? ''} $i',
  );
}

const ClientListScope _me = ClientListScope.me();
const ClientListScope _salon = ClientListScope.salon(salonId: 'salon-1');
const ClientListScope _ownerMaster = ClientListScope.salon(
  salonId: 'salon-1',
  masterId: 'm-1',
);

ProviderContainer _container(_FakeClientRepository repo) => makeTestContainer(
  // No provider retry: the error test asserts the FIRST failure surfaces.
  retry: (_, _) => null,
  overrides: <Object>[
    clientRepositoryProvider.overrideWithValue(repo),
    authProvider.overrideWith(() => FixedRoleAuth(UserRole.independentMaster)),
  ],
);

/// Keeps the autoDispose list alive for the whole test (a bare `.future` read
/// would let it be disposed mid-load) and returns its first value.
Future<ClientListState> _load(
  ProviderContainer c,
  ClientListScope scope,
) async {
  // Settle the session first: the list watches the user id, so a session that
  // settles AFTER the first fetch would (correctly) trigger a second one.
  await c.read(authProvider.future);
  final ProviderSubscription<AsyncValue<ClientListState>> sub = c.listen(
    clientListControllerProvider(scope),
    (_, _) {},
  );
  addTearDown(sub.close);
  return c.read(clientListControllerProvider(scope).future);
}

/// Runs [type] (the `setQuery` calls) inside a [FakeAsync] zone so the
/// debounce `Timer` is virtual; the caller drives it with `elapse`.
FakeAsync _typing(void Function() type) {
  final FakeAsync fa = FakeAsync();
  fa.run((_) => type());
  return fa;
}

/// Lets the debounce fire and the resulting re-query settle (virtual time).
void _settle(FakeAsync fa) {
  fa.elapse(kClientSearchDebounce);
  fa.flushMicrotasks();
}

/// One keystroke burst, fully settled.
void _type(ClientListController notifier, String raw) =>
    _settle(_typing(() => notifier.setQuery(raw)));

/// A fixed-role session that can also sign OUT (→ unauthenticated).
class _LogoutAuth extends FixedRoleAuth {
  _LogoutAuth() : super(UserRole.independentMaster);

  void signOut() =>
      state = const AsyncData<AuthSession>(AuthSession.unauthenticated());
}

void main() {
  group('first page + paging', () {
    test('build fetches page 0 with size 20 and no q', () async {
      final repo = _FakeClientRepository();
      final c = _container(repo);
      final ClientListState s = await _load(c, _me);
      expect(s.items, hasLength(20));
      expect(s.page, 0);
      expect(s.hasMore, isTrue);
      expect(s.query, isNull);
      expect(repo.calls.single.page, 0);
      expect(repo.calls.single.size, 20);
      expect(repo.calls.single.q, isNull);
    });

    test(
      'loadMore appends page 1 then page 2 and stops on the last page',
      () async {
        final repo = _FakeClientRepository(); // 45 rows → 3 pages
        final c = _container(repo);
        await _load(c, _me);
        final notifier = c.read(clientListControllerProvider(_me).notifier);

        await notifier.loadMore();
        ClientListState s = c
            .read(clientListControllerProvider(_me))
            .requireValue;
        expect(s.items, hasLength(40));
        expect(s.page, 1);
        expect(s.hasMore, isTrue);

        await notifier.loadMore();
        s = c.read(clientListControllerProvider(_me)).requireValue;
        expect(s.items, hasLength(45));
        expect(s.hasMore, isFalse);
        expect(s.items.map((ClientSummary r) => r.id).toSet(), hasLength(45));

        final int before = repo.calls.length;
        await notifier.loadMore();
        expect(repo.calls.length, before, reason: 'last page: no request');
      },
    );

    test(
      'a loadMore while one is in flight is a no-op (double-fetch guard)',
      () async {
        final repo = _FakeClientRepository();
        final c = _container(repo);
        await _load(c, _me);
        final Completer<PageResponse<ClientSummary>> gate =
            Completer<PageResponse<ClientSummary>>();
        repo.hook = (_Call call) => call.page == 1 ? gate.future : null;

        final notifier = c.read(clientListControllerProvider(_me).notifier);
        final Future<void> first = notifier.loadMore();
        expect(
          c.read(clientListControllerProvider(_me)).requireValue.isLoadingMore,
          isTrue,
        );
        await notifier.loadMore(); // ignored
        expect(repo.calls.where((_Call x) => x.page == 1), hasLength(1));

        gate.complete(repo._serve(null, 1));
        await first;
        expect(
          c.read(clientListControllerProvider(_me)).requireValue.isLoadingMore,
          isFalse,
        );
      },
    );

    test('a failed loadMore keeps the list, clears the spinner and PAUSES '
        'auto-append until a refresh', () async {
      final repo = _FakeClientRepository();
      final c = _container(repo);
      await _load(c, _me);
      repo.hook = (_Call call) => call.page == 1
          ? Future<PageResponse<ClientSummary>>.error(const NetworkFailure())
          : null;

      final notifier = c.read(clientListControllerProvider(_me).notifier);
      await notifier.loadMore();
      ClientListState s = c
          .read(clientListControllerProvider(_me))
          .requireValue;
      expect(s.items, hasLength(20), reason: 'the rendered list survives');
      expect(s.isLoadingMore, isFalse);
      expect(s.loadMoreFailed, isTrue);
      expect(s.canLoadMore, isFalse);

      final int before = repo.calls.length;
      await notifier.loadMore();
      expect(repo.calls.length, before, reason: 'no retry storm on scroll');

      repo.hook = null;
      await notifier.refresh();
      s = c.read(clientListControllerProvider(_me)).requireValue;
      expect(s.loadMoreFailed, isFalse);
      expect(s.canLoadMore, isTrue);
    });
  });

  group('search (B507 q: 2–50 chars, 300 ms debounce)', () {
    test(
      'typing 2 chars re-queries page 0 with q after the debounce only',
      () async {
        final repo = _FakeClientRepository();
        final c = _container(repo);
        await _load(c, _me);
        final notifier = c.read(clientListControllerProvider(_me).notifier);

        final FakeAsync fa = _typing(() {
          notifier.setQuery('о');
          notifier.setQuery('ол');
        });
        fa.elapse(kClientSearchDebounce - const Duration(milliseconds: 1));
        fa.flushMicrotasks();
        expect(repo.calls, hasLength(1), reason: 'nothing before the debounce');
        fa.elapse(const Duration(milliseconds: 1));
        fa.flushMicrotasks();

        expect(repo.calls, hasLength(2));
        expect(repo.calls.last.q, 'ол');
        expect(repo.calls.last.page, 0);
        final ClientListState s = c
            .read(clientListControllerProvider(_me))
            .requireValue;
        expect(s.query, 'ол');
        expect(s.items.first.displayName, contains('ол'));
      },
    );

    test('blank, whitespace and 1-char input never send q', () async {
      final repo = _FakeClientRepository();
      final c = _container(repo);
      await _load(c, _me);
      final notifier = c.read(clientListControllerProvider(_me).notifier);

      for (final String raw in <String>['', '   ', 'о', ' о ']) {
        _type(notifier, raw);
      }
      expect(repo.calls, hasLength(1), reason: 'only the initial load');
      expect(repo.calls.single.q, isNull);
    });

    test('shrinking a term back below 2 chars re-queries WITHOUT q', () async {
      final repo = _FakeClientRepository();
      final c = _container(repo);
      await _load(c, _me);
      final notifier = c.read(clientListControllerProvider(_me).notifier);

      _type(notifier, 'ол');
      _type(notifier, 'о');

      expect(repo.calls, hasLength(3));
      expect(repo.calls.last.q, isNull);
      expect(
        c.read(clientListControllerProvider(_me)).requireValue.query,
        isNull,
      );
    });

    test('a 51+ char term is capped at 50', () async {
      final repo = _FakeClientRepository();
      final c = _container(repo);
      await _load(c, _me);
      _type(c.read(clientListControllerProvider(_me).notifier), 'я' * 70);
      expect(repo.calls.last.q, 'я' * 50);
    });

    test(
      'a different raw text with the SAME effective q costs no request',
      () async {
        final repo = _FakeClientRepository();
        final c = _container(repo);
        await _load(c, _me);
        final notifier = c.read(clientListControllerProvider(_me).notifier);
        _type(notifier, 'ол');
        _type(notifier, '  ол ');
        expect(repo.calls, hasLength(2));
      },
    );

    test('loadMore keeps the applied q on page 2', () async {
      final repo = _FakeClientRepository();
      final c = _container(repo);
      await _load(c, _me);
      final notifier = c.read(clientListControllerProvider(_me).notifier);
      _type(notifier, 'ол');
      await notifier.loadMore();
      expect(repo.calls.last.page, 1);
      expect(repo.calls.last.q, 'ол');
    });

    test(
      'a slow page 2 of the OLD search is dropped after a new search',
      () async {
        final repo = _FakeClientRepository();
        final c = _container(repo);
        await _load(c, _me);
        final Completer<PageResponse<ClientSummary>> slow =
            Completer<PageResponse<ClientSummary>>();
        repo.hook = (_Call call) =>
            call.page == 1 && call.q == null ? slow.future : null;

        final notifier = c.read(clientListControllerProvider(_me).notifier);
        final Future<void> stale = notifier.loadMore();
        _type(notifier, 'ол');

        slow.complete(repo._serve(null, 1));
        await stale;

        final ClientListState s = c
            .read(clientListControllerProvider(_me))
            .requireValue;
        expect(s.query, 'ол');
        expect(
          s.items,
          hasLength(20),
          reason: 'old page 2 must not be appended',
        );
        expect(
          s.items.every((ClientSummary r) => r.displayName!.contains('ол')),
          isTrue,
        );
      },
    );
  });

  group('refresh + errors', () {
    test('refresh resets to page 0 (drops appended pages)', () async {
      final repo = _FakeClientRepository();
      final c = _container(repo);
      await _load(c, _me);
      final notifier = c.read(clientListControllerProvider(_me).notifier);
      await notifier.loadMore();
      expect(
        c.read(clientListControllerProvider(_me)).requireValue.items,
        hasLength(40),
      );

      await notifier.refresh();
      final ClientListState s = c
          .read(clientListControllerProvider(_me))
          .requireValue;
      expect(s.items, hasLength(20));
      expect(s.page, 0);
      expect(repo.calls.last.page, 0);
    });

    test('refresh keeps the applied q', () async {
      final repo = _FakeClientRepository();
      final c = _container(repo);
      await _load(c, _me);
      final notifier = c.read(clientListControllerProvider(_me).notifier);
      _type(notifier, 'ол');
      await notifier.refresh();
      expect(repo.calls.last.q, 'ол');
    });

    test('first-page error surfaces as AsyncError, retry recovers', () async {
      final repo = _FakeClientRepository();
      int failures = 1;
      repo.hook = (_Call call) => failures-- > 0
          ? Future<PageResponse<ClientSummary>>.error(const NetworkFailure())
          : null;
      final c = _container(repo);
      await c.read(authProvider.future);
      final sub = c.listen(clientListControllerProvider(_me), (_, _) {});
      addTearDown(sub.close);
      await expectLater(
        c.read(clientListControllerProvider(_me).future),
        throwsA(isA<NetworkFailure>()),
      );
      expect(c.read(clientListControllerProvider(_me)).hasError, isTrue);

      await c.read(clientListControllerProvider(_me).notifier).refresh();
      expect(c.read(clientListControllerProvider(_me)).hasError, isFalse);
      expect(
        c.read(clientListControllerProvider(_me)).requireValue.items,
        hasLength(20),
      );
    });
  });

  group('scope → call', () {
    test('me', () async {
      final repo = _FakeClientRepository();
      await _load(_container(repo), _me);
      expect(repo.calls.single.scope, isA<MyClientListScope>());
    });

    test('salon without masterId (the shell tab) and with it (owner master '
        'mode) are separate lists with the right scope', () async {
      final repo = _FakeClientRepository();
      final c = _container(repo);
      await _load(c, _salon);
      await _load(c, _ownerMaster);

      final SalonClientListScope shell =
          repo.calls[0].scope as SalonClientListScope;
      final SalonClientListScope own =
          repo.calls[1].scope as SalonClientListScope;
      expect(shell.salonId, 'salon-1');
      expect(shell.masterId, isNull);
      expect(own.masterId, 'm-1');
    });

    test('equal scopes share ONE list (freezed family key)', () async {
      final repo = _FakeClientRepository();
      final c = _container(repo);
      await c.read(authProvider.future);
      final sub = c.listen(
        clientListControllerProvider(
          const ClientListScope.salon(salonId: 'salon-1', masterId: 'm-1'),
        ),
        (_, _) {},
      );
      addTearDown(sub.close);
      await _load(c, _ownerMaster);
      expect(repo.calls, hasLength(1));
    });
  });

  test('session boundary: a different signed-in user rebuilds the list '
      '(never repaints the previous account\'s clients)', () async {
    final repo = _FakeClientRepository(total: 5);
    final FixedRoleAuth auth = FixedRoleAuth(UserRole.independentMaster);
    final c = makeTestContainer(
      retry: (_, _) => null,
      overrides: <Object>[
        clientRepositoryProvider.overrideWithValue(repo),
        authProvider.overrideWith(() => auth),
      ],
    );
    await c.read(authProvider.future);
    final sub = c.listen(clientListControllerProvider(_me), (_, _) {});
    addTearDown(sub.close);
    final ClientListState a = await _load(c, _me);
    expect(repo.calls, hasLength(1));
    expect(a.items.first.ref, const ClientRef.registered('u0'));

    auth.switchUser('another-user');
    final ClientListState b = await _load(c, _me);
    expect(repo.calls, hasLength(2), reason: 'identity change → refetch');
    expect(b.items, hasLength(5));
    // A's rows are gone: the state is B's freshly fetched list, not A's.
    expect(identical(b, a), isFalse);
    expect(b.items, isNot(same(a.items)));
    expect(repo.calls.last.token, isNot(same(repo.calls.first.token)));
  });

  // M509 QA — the applied search term is PER-SESSION state: account B must
  // never open on account A's filter (nor see A's filtered rows).
  test(
    'session boundary: a different signed-in user starts from a CLEAN list — '
    'the previous account\'s search term is dropped',
    () async {
      final repo = _FakeClientRepository(total: 5);
      final FixedRoleAuth auth = FixedRoleAuth(UserRole.independentMaster);
      final c = makeTestContainer(
        retry: (_, _) => null,
        overrides: <Object>[
          clientRepositoryProvider.overrideWithValue(repo),
          authProvider.overrideWith(() => auth),
        ],
      );
      await c.read(authProvider.future);
      await _load(c, _me);
      final notifier = c.read(clientListControllerProvider(_me).notifier);
      _type(notifier, 'ол');
      expect(repo.calls.last.q, 'ол', reason: 'precondition: A filtered');

      auth.switchUser('another-user');
      final ClientListState s = await _load(c, _me);

      expect(
        repo.calls.last.q,
        isNull,
        reason: 'B\'s first fetch is unfiltered',
      );
      expect(s.query, isNull);
      expect(
        s.items.every(
          (ClientSummary r) => !(r.displayName ?? '').contains('ол'),
        ),
        isTrue,
        reason: 'no row of A\'s filtered result set survives',
      );
    },
  );

  test('session boundary: A\'s in-flight page 2 never reaches B', () async {
    final repo = _FakeClientRepository();
    final FixedRoleAuth auth = FixedRoleAuth(UserRole.independentMaster);
    final c = makeTestContainer(
      retry: (_, _) => null,
      overrides: <Object>[
        clientRepositoryProvider.overrideWithValue(repo),
        authProvider.overrideWith(() => auth),
      ],
    );
    await c.read(authProvider.future);
    await _load(c, _me);
    final Completer<PageResponse<ClientSummary>> slow =
        Completer<PageResponse<ClientSummary>>();
    repo.hook = (_Call call) => call.page == 1 ? slow.future : null;
    final Future<void> stale = c
        .read(clientListControllerProvider(_me).notifier)
        .loadMore();

    auth.switchUser('another-user');
    final ClientListState b = await _load(c, _me);
    slow.complete(repo._serve(null, 1));
    await stale;

    final ClientListState after = c
        .read(clientListControllerProvider(_me))
        .requireValue;
    expect(b.items, hasLength(20));
    expect(after.items, hasLength(20), reason: 'A\'s page 2 is dropped');
    expect(after.page, 0);
    expect(after.isLoadingMore, isFalse);
  });

  test('logged out: an empty list and NO fetch (build and sign-out)', () async {
    final repo = _FakeClientRepository();
    final _LogoutAuth auth = _LogoutAuth();
    final c = makeTestContainer(
      retry: (_, _) => null,
      overrides: <Object>[
        clientRepositoryProvider.overrideWithValue(repo),
        authProvider.overrideWith(() => auth),
      ],
    );
    await c.read(authProvider.future);
    await _load(c, _me);
    expect(repo.calls, hasLength(1));

    auth.signOut();
    final ClientListState s = await _load(c, _me);
    expect(s.items, isEmpty);
    expect(s.hasMore, isFalse);
    expect(repo.calls, hasLength(1), reason: 'sign-out costs no request');
  });

  group('cancellation', () {
    test('a superseded search request is cancelled and its late failure is '
        'not surfaced', () async {
      final repo = _FakeClientRepository();
      final c = _container(repo);
      await _load(c, _me);
      final Completer<PageResponse<ClientSummary>> first =
          Completer<PageResponse<ClientSummary>>();
      repo.hook = (_Call call) => call.q == 'ол' ? first.future : null;
      final notifier = c.read(clientListControllerProvider(_me).notifier);

      _type(notifier, 'ол');
      final CancelToken firstToken = repo.calls.last.token!;
      expect(firstToken.isCancelled, isFalse);

      _type(notifier, 'ола');
      expect(firstToken.isCancelled, isTrue, reason: 'superseded → cancelled');
      expect(repo.calls.last.token!.isCancelled, isFalse);

      first.completeError(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.cancel,
        ),
      );
      await Future<void>.value();
      final AsyncValue<ClientListState> now = c.read(
        clientListControllerProvider(_me),
      );
      expect(now.hasError, isFalse, reason: 'a cancel is not an error');
      expect(now.requireValue.query, 'ола');
    });

    test('a refresh cancels the previous generation\'s request', () async {
      final repo = _FakeClientRepository();
      final c = _container(repo);
      await _load(c, _me);
      final CancelToken initial = repo.calls.first.token!;
      await c.read(clientListControllerProvider(_me).notifier).refresh();
      expect(initial.isCancelled, isTrue);
      expect(repo.calls.last.token!.isCancelled, isFalse);
    });
  });

  test('a refresh keeps the previous rows while in flight', () async {
    final repo = _FakeClientRepository();
    final c = _container(repo);
    await _load(c, _me);
    final Completer<PageResponse<ClientSummary>> gate =
        Completer<PageResponse<ClientSummary>>();
    repo.hook = (_Call call) => gate.future;

    final Future<void> refreshing = c
        .read(clientListControllerProvider(_me).notifier)
        .refresh();
    final AsyncValue<ClientListState> mid = c.read(
      clientListControllerProvider(_me),
    );
    expect(mid.isLoading, isTrue);
    expect(mid.value?.items, hasLength(20), reason: 'rows stay visible');
    expect(mid.value?.isSearching, isFalse, reason: 'refresh is not a search');

    gate.complete(repo._serve(null, 0));
    await refreshing;
    expect(c.read(clientListControllerProvider(_me)).isLoading, isFalse);
  });

  test(
    'a NEW search flags isSearching while in flight, clears on result',
    () async {
      final repo = _FakeClientRepository();
      final c = _container(repo);
      await _load(c, _me);
      final Completer<PageResponse<ClientSummary>> gate =
          Completer<PageResponse<ClientSummary>>();
      repo.hook = (_Call call) => call.q == 'ол' ? gate.future : null;
      final notifier = c.read(clientListControllerProvider(_me).notifier);

      _type(notifier, 'ол');
      final AsyncValue<ClientListState> mid = c.read(
        clientListControllerProvider(_me),
      );
      expect(mid.isLoading, isTrue);
      expect(mid.value?.isSearching, isTrue, reason: 'old rows must be hidden');

      gate.complete(repo._serve('ол', 0));
      await Future<void>.value();
      await Future<void>.value();
      final ClientListState done = c
          .read(clientListControllerProvider(_me))
          .requireValue;
      expect(done.isSearching, isFalse);
      expect(done.query, 'ол');
    },
  );

  test(
    'loadMore during a reload fires no page+1 and the fresh rows win',
    () async {
      final repo = _FakeClientRepository();
      final c = _container(repo);
      await _load(c, _me);
      final Completer<PageResponse<ClientSummary>> gate =
          Completer<PageResponse<ClientSummary>>();
      repo.hook = (_Call call) => call.q == 'ол' ? gate.future : null;
      final notifier = c.read(clientListControllerProvider(_me).notifier);

      _type(notifier, 'ол');
      final int before = repo.calls.length;
      await notifier.loadMore();
      expect(repo.calls.length, before, reason: 'no request while reloading');
      expect(repo.calls.where((_Call x) => x.page == 1), isEmpty);

      gate.complete(repo._serve('ол', 0));
      await Future<void>.value();
      await Future<void>.value();
      final ClientListState s = c
          .read(clientListControllerProvider(_me))
          .requireValue;
      expect(s.query, 'ол');
      expect(
        s.items.every((ClientSummary r) => r.displayName!.contains('ол')),
        isTrue,
      );
      expect(s.items, hasLength(repo._serve('ол', 0).items.length));
    },
  );
}
