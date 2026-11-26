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
import 'package:beautica_mobile/features/clients/application/client_list_removal.dart'
    show kClientRemovalBroadcastDelay;
import 'package:beautica_mobile/features/clients/application/client_views_invalidation.dart';
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
  // M510 — the card reads are not exercised here.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

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

  /// M544 — server-side removals (`removeFromList` / `restoreToList`).
  final Set<ClientRef> removed = <ClientRef>{};
  final List<String> writes = <String>[];
  Object? removeError;
  Object? restoreError;

  @override
  Future<void> removeFromList(ClientListScope scope, ClientRef client) async {
    writes.add('remove');
    final Object? e = removeError;
    if (e != null) throw e;
    removed.add(client);
  }

  @override
  Future<void> restoreToList(ClientListScope scope, ClientRef client) async {
    writes.add('restore');
    final Object? e = restoreError;
    if (e != null) throw e;
    removed.remove(client);
  }

  PageResponse<ClientSummary> _serve(String? q, int page) {
    final int from = page * pageSize;
    final int to = (from + pageSize).clamp(0, total);
    return PageResponse<ClientSummary>(
      items: <ClientSummary>[
        for (int i = from; i < to; i++)
          if (!removed.contains(row(i).ref)) row(i, q: q),
      ],
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

    test('a failed refresh over loaded rows keeps them (incl. appended pages) '
        'and returns the error for the snack', () async {
      final repo = _FakeClientRepository();
      final c = _container(repo);
      await _load(c, _me);
      final notifier = c.read(clientListControllerProvider(_me).notifier);
      await notifier.loadMore();
      repo.hook = (_Call call) =>
          Future<PageResponse<ClientSummary>>.error(const NetworkFailure());

      final Object? error = await notifier.refresh();
      expect(error, isA<NetworkFailure>());
      final AsyncValue<ClientListState> st = c.read(
        clientListControllerProvider(_me),
      );
      expect(st.hasError, isFalse, reason: 'no full-page error');
      expect(st.requireValue.items, hasLength(40));
      expect(st.requireValue.page, 1);

      // The list stays usable: paging resumes from the kept cursor.
      repo.hook = null;
      await notifier.loadMore();
      expect(repo.calls.last.page, 2);
    });

    test('a successful refresh returns null', () async {
      final repo = _FakeClientRepository();
      final c = _container(repo);
      await _load(c, _me);
      expect(
        await c.read(clientListControllerProvider(_me).notifier).refresh(),
        isNull,
      );
    });
  });

  group('cache-for (kClientListCacheFor)', () {
    test('unlistened: pages + applied search survive inside the window, no '
        're-read; released after it', () {
      fakeAsync((FakeAsync fa) {
        final repo = _FakeClientRepository();
        final c = _container(repo);
        c.read(authProvider.future);
        fa.flushMicrotasks();
        ProviderSubscription<AsyncValue<ClientListState>> sub = c.listen(
          clientListControllerProvider(_me),
          (_, _) {},
        );
        fa.flushMicrotasks();
        final notifier = c.read(clientListControllerProvider(_me).notifier);
        notifier.loadMore();
        fa.flushMicrotasks();
        notifier.setQuery('ол');
        fa.elapse(kClientSearchDebounce);
        fa.flushMicrotasks();
        notifier.loadMore();
        fa.flushMicrotasks();
        final int calls = repo.calls.length;
        final ClientListState before = c
            .read(clientListControllerProvider(_me))
            .requireValue;
        expect(before.query, 'ол');

        sub.close(); // tab left with context.go — the screen unmounts
        fa.elapse(kClientListCacheFor - const Duration(seconds: 1));
        expect(c.exists(clientListControllerProvider(_me)), isTrue);
        sub = c.listen(clientListControllerProvider(_me), (_, _) {});
        fa.flushMicrotasks();
        expect(repo.calls.length, calls, reason: 'served from the cache');
        expect(c.read(clientListControllerProvider(_me)).requireValue, before);

        sub.close();
        fa.elapse(kClientListCacheFor + const Duration(seconds: 1));
        expect(c.exists(clientListControllerProvider(_me)), isFalse);
      });
    });

    test(
      'invalidateClientViews refetches a cached (unlistened) list',
      () async {
        final repo = _FakeClientRepository();
        final c = _container(repo);
        await c.read(authProvider.future);
        final sub = c.listen(clientListControllerProvider(_me), (_, _) {});
        await c.read(clientListControllerProvider(_me).future);
        sub.close();
        await Future<void>.delayed(Duration.zero);
        expect(c.exists(clientListControllerProvider(_me)), isTrue);
        final int calls = repo.calls.length;

        invalidateClientViews(c.invalidate);
        await _load(c, _me);
        expect(repo.calls.length, calls + 1);
        expect(repo.calls.last.page, 0);
      },
    );

    // M552 audit P2 — the picker host is its own instance with no cache-for.
    test('picker host: its own list (a picker search never touches the tab '
        'list) and released as soon as nothing listens', () {
      fakeAsync((FakeAsync fa) {
        final repo = _FakeClientRepository();
        final c = _container(repo);
        c.read(authProvider.future);
        fa.flushMicrotasks();
        final tabSub = c.listen(clientListControllerProvider(_me), (_, _) {});
        final pickerProvider = clientListControllerProvider(
          _me,
          host: ClientListHost.picker,
        );
        final pickerSub = c.listen(pickerProvider, (_, _) {});
        fa.flushMicrotasks();
        expect(repo.calls, hasLength(2), reason: 'two instances, two lists');

        c.read(pickerProvider.notifier).setQuery('ол');
        fa.elapse(kClientSearchDebounce);
        fa.flushMicrotasks();
        expect(c.read(pickerProvider).requireValue.query, 'ол');
        expect(
          c.read(clientListControllerProvider(_me)).requireValue.query,
          isNull,
          reason: 'the tab list is untouched',
        );

        pickerSub.close();
        // Riverpod's dispose pass runs on the next scheduler tick — far inside
        // the tab's 30 s window.
        fa.elapse(const Duration(milliseconds: 1));
        expect(c.exists(pickerProvider), isFalse, reason: 'no cache-for');
        final reopened = c.listen(pickerProvider, (_, _) {});
        fa.flushMicrotasks();
        expect(c.read(pickerProvider).requireValue.query, isNull);
        reopened.close();
        tabSub.close();
      });
    });

    test('cancelPendingSearch: a debounced term never fetches', () {
      fakeAsync((FakeAsync fa) {
        final repo = _FakeClientRepository();
        final c = _container(repo);
        c.read(authProvider.future);
        fa.flushMicrotasks();
        final sub = c.listen(clientListControllerProvider(_me), (_, _) {});
        fa.flushMicrotasks();
        final notifier = c.read(clientListControllerProvider(_me).notifier);
        final int calls = repo.calls.length;

        notifier.setQuery('ол');
        notifier.cancelPendingSearch();
        fa.elapse(kClientSearchDebounce * 2);
        fa.flushMicrotasks();

        expect(repo.calls.length, calls);
        expect(
          c.read(clientListControllerProvider(_me)).requireValue.query,
          isNull,
        );
        sub.close();
      });
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

  // M544 (CLI-86) — optimistic remove / undo.
  group('remove / restore (M544)', () {
    List<String> ids(ClientListState s) => <String>[
      for (final ClientSummary c in s.items) c.id,
    ];

    test('remove drops the row at once, keeps its index, and the list keeps '
        'its loaded pages (no refetch of its own)', () async {
      final _FakeClientRepository repo = _FakeClientRepository(total: 5);
      final ProviderContainer c = _container(repo);
      await _load(c, _me);
      final ClientListController notifier = c.read(
        clientListControllerProvider(_me).notifier,
      );
      final Future<ClientRemoval?> pending = notifier.remove(
        _FakeClientRepository.row(2),
      );
      // Optimistic: gone before the write resolves.
      expect(
        ids(c.read(clientListControllerProvider(_me)).requireValue),
        <String>['u0', 'u1', 'u3', 'u4'],
      );
      final ClientRemoval? removal = await pending;
      expect(removal?.index, 2);
      expect(removal?.error, isNull);
      expect(repo.writes, <String>['remove']);
      final int fetches = repo.calls.length;
      final ClientListState after = await c.read(
        clientListControllerProvider(_me).future,
      );
      expect(repo.calls.length, fetches, reason: 'perf: no self-refetch');
      expect(ids(after), <String>['u0', 'u1', 'u3', 'u4']);
    });

    test('the list keeps its appended pages through a remove', () async {
      final _FakeClientRepository repo = _FakeClientRepository(total: 45);
      final ProviderContainer c = _container(repo);
      await _load(c, _me);
      final ClientListController notifier = c.read(
        clientListControllerProvider(_me).notifier,
      );
      await notifier.loadMore();
      expect(
        c.read(clientListControllerProvider(_me)).requireValue.items,
        hasLength(40),
      );
      await notifier.remove(_FakeClientRepository.row(30));
      final ClientListState after = c
          .read(clientListControllerProvider(_me))
          .requireValue;
      expect(after.items, hasLength(39));
      expect(after.page, 1, reason: 'page 1 still loaded');
    });

    test('a failed remove puts the row back at the same index', () async {
      final _FakeClientRepository repo = _FakeClientRepository(total: 5)
        ..removeError = const NetworkFailure();
      final ProviderContainer c = _container(repo);
      await _load(c, _me);
      final int fetches = repo.calls.length;
      final ClientRemoval? removal = await c
          .read(clientListControllerProvider(_me).notifier)
          .remove(_FakeClientRepository.row(1));
      expect(removal?.error, isA<NetworkFailure>());
      expect(
        ids(c.read(clientListControllerProvider(_me)).requireValue),
        <String>['u0', 'u1', 'u2', 'u3', 'u4'],
      );
      expect(repo.calls.length, fetches, reason: 'no refetch on failure');
    });

    test('remove of a row that is not listed does nothing', () async {
      final _FakeClientRepository repo = _FakeClientRepository(total: 3);
      final ProviderContainer c = _container(repo);
      await _load(c, _me);
      final ClientRemoval? removal = await c
          .read(clientListControllerProvider(_me).notifier)
          .remove(_FakeClientRepository.row(9));
      expect(removal, isNull);
      expect(repo.writes, isEmpty);
    });

    test('restore puts the row back at its index and calls restore', () async {
      final _FakeClientRepository repo = _FakeClientRepository(total: 5);
      final ProviderContainer c = _container(repo);
      await _load(c, _me);
      final ClientSummary row = _FakeClientRepository.row(3);
      await c.read(clientListControllerProvider(_me).notifier).remove(row);
      await c.read(clientListControllerProvider(_me).future);
      final Future<Object?> pending = c
          .read(clientListControllerProvider(_me).notifier)
          .restore(row, 3);
      expect(
        ids(c.read(clientListControllerProvider(_me)).requireValue),
        <String>['u0', 'u1', 'u2', 'u3', 'u4'],
      );
      expect(await pending, isNull);
      expect(repo.writes, <String>['remove', 'restore']);
      expect(
        ids(await c.read(clientListControllerProvider(_me).future)),
        <String>['u0', 'u1', 'u2', 'u3', 'u4'],
      );
    });

    test('a failed restore returns the error and refetches the server '
        'truth (row stays gone)', () async {
      final _FakeClientRepository repo = _FakeClientRepository(total: 4);
      final ProviderContainer c = _container(repo);
      await _load(c, _me);
      final ClientSummary row = _FakeClientRepository.row(0);
      await c.read(clientListControllerProvider(_me).notifier).remove(row);
      await c.read(clientListControllerProvider(_me).future);
      repo.restoreError = const ServerFailure(statusCode: 500);
      final int fetches = repo.calls.length;
      final Object? error = await c
          .read(clientListControllerProvider(_me).notifier)
          .restore(row, 0);
      expect(error, isA<ServerFailure>());
      final ClientListState after = await c.read(
        clientListControllerProvider(_me).future,
      );
      expect(repo.calls.length, fetches + 1);
      expect(ids(after), <String>['u1', 'u2', 'u3']);
    });

    test('a swipe burst refreshes the OTHER lists ONCE, when the last '
        'undo window closes (CLI-82); the swiping list keeps its pages', () {
      final FakeAsync fa = FakeAsync();
      fa.run((FakeAsync fa) {
        final _FakeClientRepository repo = _FakeClientRepository(total: 4);
        final ProviderContainer c = _container(repo);
        int fetches(ClientListScope s) =>
            repo.calls.where((_Call call) => call.scope == s).length;
        unawaited(_load(c, _salon));
        unawaited(_load(c, _ownerMaster));
        fa.flushMicrotasks();
        final int salon0 = fetches(_salon);
        final int master0 = fetches(_ownerMaster);
        final ClientListController salon = c.read(
          clientListControllerProvider(_salon).notifier,
        );

        unawaited(salon.remove(_FakeClientRepository.row(1)));
        fa.flushMicrotasks();
        fa.elapse(const Duration(seconds: 2));
        unawaited(salon.remove(_FakeClientRepository.row(2)));
        fa.flushMicrotasks();
        // Inside the second swipe's window: nobody refetched yet.
        fa.elapse(kClientRemovalBroadcastDelay - const Duration(seconds: 1));
        expect(fetches(_ownerMaster), master0);

        fa.elapse(const Duration(seconds: 2));
        c.read(clientListControllerProvider(_ownerMaster));
        fa.flushMicrotasks();
        expect(fetches(_ownerMaster), master0 + 1, reason: 'ONE refresh');
        expect(fetches(_salon), salon0, reason: 'own burst: no refetch');
        expect(
          ids(c.read(clientListControllerProvider(_salon)).requireValue),
          <String>['u0', 'u3'],
        );
      });
    });

    /// Runs [body] in virtual time with a salon list, an owner master-mode
    /// list and a `me` list loaded; [fetches] counts list calls per scope.
    void burst(
      void Function(
        FakeAsync fa,
        ProviderContainer c,
        _FakeClientRepository repo,
        int Function(ClientListScope) fetches,
      )
      body,
    ) {
      FakeAsync().run((FakeAsync fa) {
        final _FakeClientRepository repo = _FakeClientRepository(total: 4);
        final ProviderContainer c = _container(repo);
        int fetches(ClientListScope s) =>
            repo.calls.where((_Call call) => call.scope == s).length;
        unawaited(_load(c, _salon));
        unawaited(_load(c, _ownerMaster));
        unawaited(_load(c, _me));
        fa.flushMicrotasks();
        body(fa, c, repo, fetches);
      });
    }

    /// Lets the burst flush and every invalidated list refetch.
    void flush(FakeAsync fa, ProviderContainer c) {
      fa.elapse(kClientRemovalBroadcastDelay + const Duration(seconds: 1));
      for (final ClientListScope s in <ClientListScope>[
        _salon,
        _ownerMaster,
        _me,
      ]) {
        c.read(clientListControllerProvider(s));
      }
      fa.flushMicrotasks();
    }

    test('the burst is keyed by the family key, not the notifier: a rebuild '
        'of the swiping list still counts as the source (no self-refetch at '
        'the flush); other scopes are left alone', () {
      burst((fa, c, repo, fetches) {
        unawaited(
          c
              .read(clientListControllerProvider(_salon).notifier)
              .remove(_FakeClientRepository.row(1)),
        );
        fa.flushMicrotasks();
        // A rebuild (new notifier instance) inside the window.
        c.invalidate(clientListControllerProvider(_salon));
        c.read(clientListControllerProvider(_salon));
        fa.flushMicrotasks();
        final int salon0 = fetches(_salon);
        final int master0 = fetches(_ownerMaster);
        final int me0 = fetches(_me);

        flush(fa, c);
        expect(fetches(_salon), salon0, reason: 'own burst across a rebuild');
        expect(fetches(_ownerMaster), master0 + 1, reason: 'same salon');
        expect(fetches(_me), me0, reason: 'another removal scope (CLI-82)');
      });
    });

    test('undo with no net change: nobody refetches at the flush', () {
      burst((fa, c, repo, fetches) {
        final ClientListController salon = c.read(
          clientListControllerProvider(_salon).notifier,
        );
        final ClientSummary row = _FakeClientRepository.row(2);
        unawaited(salon.remove(row));
        fa.flushMicrotasks();
        unawaited(salon.restore(row, 2));
        fa.flushMicrotasks();
        final int salon0 = fetches(_salon);
        final int master0 = fetches(_ownerMaster);

        flush(fa, c);
        expect(repo.writes, <String>['remove', 'restore']);
        expect(fetches(_salon), salon0);
        expect(fetches(_ownerMaster), master0, reason: 'remove + undo = 0');
      });
    });

    test('a failed restore refetches the family ONCE (the pending flush is '
        'cancelled)', () {
      burst((fa, c, repo, fetches) {
        final ClientListController salon = c.read(
          clientListControllerProvider(_salon).notifier,
        );
        final ClientSummary row = _FakeClientRepository.row(0);
        unawaited(salon.remove(row));
        fa.flushMicrotasks();
        // Baselines BEFORE the failing restore.
        final int salon0 = fetches(_salon);
        final int master0 = fetches(_ownerMaster);
        repo.restoreError = const ServerFailure(statusCode: 500);
        unawaited(
          c.read(clientListControllerProvider(_salon).notifier).restore(row, 0),
        );
        fa.flushMicrotasks();
        for (final ClientListScope s in <ClientListScope>[
          _salon,
          _ownerMaster,
        ]) {
          c.read(clientListControllerProvider(s));
        }
        fa.flushMicrotasks();
        expect(fetches(_salon), salon0 + 1, reason: 'family refetch: salon');
        expect(
          fetches(_ownerMaster),
          master0 + 1,
          reason: 'family refetch reaches the OTHER list too',
        );

        flush(fa, c);
        expect(fetches(_salon), salon0 + 1, reason: 'no second refetch');
        expect(fetches(_ownerMaster), master0 + 1, reason: 'no second refetch');
      });
    });

    test('a failed restore clears EVERY pending swipe: two lists each with a '
        'pending remove → after the window, no extra refetch', () {
      burst((fa, c, repo, fetches) {
        final ClientSummary a = _FakeClientRepository.row(1);
        final ClientSummary b = _FakeClientRepository.row(2);
        unawaited(
          c.read(clientListControllerProvider(_salon).notifier).remove(a),
        );
        unawaited(
          c.read(clientListControllerProvider(_ownerMaster).notifier).remove(b),
        );
        fa.flushMicrotasks();
        repo.restoreError = const ServerFailure(statusCode: 500);
        unawaited(
          c.read(clientListControllerProvider(_salon).notifier).restore(a, 1),
        );
        fa.flushMicrotasks();
        for (final ClientListScope s in <ClientListScope>[
          _salon,
          _ownerMaster,
        ]) {
          c.read(clientListControllerProvider(s));
        }
        fa.flushMicrotasks();
        final int salon1 = fetches(_salon);
        final int master1 = fetches(_ownerMaster);

        flush(fa, c);
        expect(fetches(_salon), salon1, reason: 'owner-master pending cleared');
        expect(fetches(_ownerMaster), master1, reason: 'salon pending cleared');
      });
    });
  });
}
