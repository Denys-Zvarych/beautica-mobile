// M545 (REV-44, CLI-60) — ClientCommentsController, the paged read behind
// the «Коментарі» section on «Рейтинг клієнта»:
//   • page 0 → rows + hasMore from the server page;
//   • loadMore appends the next page; the last page stops paging;
//   • two concurrent loadMore calls request the next page ONCE;
//   • a row that shifted onto the next page is not shown twice (E6);
//   • a failed append keeps the rows and pauses until retryLoadMore (E5);
//   • page 0 failing is the terminal AsyncError, and a rebuild recovers;
//   • an append resolving after a rebuild (another user) is dropped;
//   • signed out → empty, no request.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/clients/application/client_comments_controller.dart';
import 'package:beautica_mobile/features/clients/data/client_repository.dart';
import 'package:beautica_mobile/features/clients/domain/client_review_comment.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_notification_repository.dart';
import '../../../helpers/test_container.dart';

const ClientListScope _me = ClientListScope.me();
const ClientRef _client = ClientRef.registered('u-1');

ClientReviewComment _c(String id) => ClientReviewComment(
  reviewId: id,
  visitYear: 2026,
  visitMonth: 11,
  stars: 4,
  comment: 'text $id',
);

/// Serves [pages] verbatim (page i = pages[i]); records every requested page.
class _Repo implements ClientCommentsRepository {
  _Repo(this.pages);

  final List<List<ClientReviewComment>> pages;
  final List<int> requested = <int>[];
  final Set<int> failOnce = <int>{};

  /// When set, a request for page >= 1 waits for it.
  Completer<void>? gate;

  @override
  Future<PageResponse<ClientReviewComment>> getComments(
    ClientListScope scope,
    ClientRef client, {
    int page = 0,
    int size = kClientPageSize,
    CancelToken? cancelToken,
  }) async {
    requested.add(page);
    final Completer<void>? g = gate;
    if (page > 0 && g != null) await g.future;
    if (failOnce.remove(page)) throw const NetworkFailure();
    return PageResponse<ClientReviewComment>(
      items: pages[page],
      page: page,
      totalPages: pages.length,
      totalElements: 0,
    );
  }
}

class _SignedOut extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.unauthenticated();
}

ClientCommentsControllerProvider get _provider =>
    clientCommentsControllerProvider(_me, _client);

ProviderContainer _container(_Repo repo, {AuthNotifier Function()? auth}) =>
    makeTestContainer(
      retry: (_, _) => null,
      overrides: <Object>[
        clientCommentsRepositoryProvider.overrideWithValue(repo),
        authProvider.overrideWith(
          auth ?? () => FixedRoleAuth(UserRole.independentMaster),
        ),
      ],
    );

Future<ClientCommentsState> _load(ProviderContainer c) async {
  await c.read(authProvider.future);
  final ProviderSubscription<AsyncValue<ClientCommentsState>> sub = c.listen(
    _provider,
    (_, _) {},
  );
  addTearDown(sub.close);
  return c.read(_provider.future);
}

List<String> _ids(ProviderContainer c) => <String>[
  for (final ClientReviewComment x in c.read(_provider).requireValue.comments)
    x.reviewId,
];

void main() {
  test('page 0 → its rows, and hasMore from the server page', () async {
    final _Repo repo = _Repo(<List<ClientReviewComment>>[
      <ClientReviewComment>[_c('a'), _c('b')],
      <ClientReviewComment>[_c('c')],
    ]);
    final ProviderContainer c = _container(repo);

    final ClientCommentsState s = await _load(c);

    expect(repo.requested, <int>[0]);
    expect(_ids(c), <String>['a', 'b']);
    expect(s.page, 0);
    expect(s.hasMore, isTrue);
    expect(s.canLoadMore, isTrue);
  });

  test('loadMore appends page 1; on the last page further loadMore is a '
      'no-op', () async {
    final _Repo repo = _Repo(<List<ClientReviewComment>>[
      <ClientReviewComment>[_c('a')],
      <ClientReviewComment>[_c('b')],
    ]);
    final ProviderContainer c = _container(repo);
    await _load(c);

    await c.read(_provider.notifier).loadMore();

    expect(repo.requested, <int>[0, 1]);
    expect(_ids(c), <String>['a', 'b']);
    final ClientCommentsState s = c.read(_provider).requireValue;
    expect(s.page, 1);
    expect(s.hasMore, isFalse);
    expect(s.isLoadingMore, isFalse);

    await c.read(_provider.notifier).loadMore();
    expect(repo.requested, <int>[0, 1], reason: 'the last page stops paging');
  });

  test('two concurrent loadMore calls request page 1 ONCE', () async {
    final _Repo repo = _Repo(<List<ClientReviewComment>>[
      <ClientReviewComment>[_c('a')],
      <ClientReviewComment>[_c('b')],
      <ClientReviewComment>[_c('c')],
    ])..gate = Completer<void>();
    final ProviderContainer c = _container(repo);
    await _load(c);

    final ClientCommentsController n = c.read(_provider.notifier);
    final Future<void> first = n.loadMore();
    final Future<void> second = n.loadMore();
    expect(c.read(_provider).requireValue.isLoadingMore, isTrue);
    repo.gate!.complete();
    await Future.wait(<Future<void>>[first, second]);

    expect(repo.requested, <int>[0, 1]);
    expect(_ids(c), <String>['a', 'b']);
  });

  test(
    'E6: a row that shifted onto the next page is not shown twice',
    () async {
      final _Repo repo = _Repo(<List<ClientReviewComment>>[
        <ClientReviewComment>[_c('a'), _c('b')],
        <ClientReviewComment>[_c('b'), _c('c')],
      ]);
      final ProviderContainer c = _container(repo);
      await _load(c);

      await c.read(_provider.notifier).loadMore();

      expect(_ids(c), <String>['a', 'b', 'c']);
    },
  );

  test('E5: a failed append keeps the rows, pauses auto-append, and '
      'retryLoadMore re-requests the same page and appends', () async {
    final _Repo repo = _Repo(<List<ClientReviewComment>>[
      <ClientReviewComment>[_c('a')],
      <ClientReviewComment>[_c('b')],
    ])..failOnce.add(1);
    final ProviderContainer c = _container(repo);
    await _load(c);
    final ClientCommentsController n = c.read(_provider.notifier);

    await n.loadMore();

    final AsyncValue<ClientCommentsState> failed = c.read(_provider);
    expect(failed, isA<AsyncData<ClientCommentsState>>());
    expect(failed.requireValue.loadMoreFailed, isTrue);
    expect(failed.requireValue.isLoadingMore, isFalse);
    expect(failed.requireValue.canLoadMore, isFalse);
    expect(_ids(c), <String>['a']);

    await n.loadMore();
    expect(repo.requested, <int>[0, 1], reason: 'paused until retry');

    await n.retryLoadMore();
    expect(repo.requested, <int>[0, 1, 1]);
    expect(_ids(c), <String>['a', 'b']);
    expect(c.read(_provider).requireValue.loadMoreFailed, isFalse);
  });

  test('page 0 failure is the terminal AsyncError; a rebuild (the inline '
      'retry) recovers', () async {
    final _Repo repo = _Repo(<List<ClientReviewComment>>[
      <ClientReviewComment>[_c('a')],
    ])..failOnce.add(0);
    final ProviderContainer c = _container(repo);
    await c.read(authProvider.future);
    final ProviderSubscription<AsyncValue<ClientCommentsState>> sub = c.listen(
      _provider,
      (_, _) {},
    );
    addTearDown(sub.close);

    await expectLater(c.read(_provider.future), throwsA(isA<NetworkFailure>()));
    final AsyncValue<ClientCommentsState> err = c.read(_provider);
    expect(err, isA<AsyncError<ClientCommentsState>>());
    expect(err.error, isA<NetworkFailure>());

    c.invalidate(_provider);
    await c.read(_provider.future);
    expect(repo.requested, <int>[0, 0]);
    expect(_ids(c), <String>['a']);
  });

  test(
    'an append that resolves after a rebuild (another user) is dropped',
    () async {
      final _Repo repo = _Repo(<List<ClientReviewComment>>[
        <ClientReviewComment>[_c('a')],
        <ClientReviewComment>[_c('stale')],
      ])..gate = Completer<void>();
      final FixedRoleAuth auth = FixedRoleAuth(UserRole.independentMaster);
      final ProviderContainer c = _container(repo, auth: () => auth);
      await _load(c);

      final Future<void> pending = c.read(_provider.notifier).loadMore();
      auth.switchUser('u2');
      await c.read(_provider.future);
      repo.gate!.complete();
      await pending;

      expect(_ids(c), <String>['a']);
      expect(c.read(_provider).requireValue.page, 0);
    },
  );

  test('signed out → empty, no request', () async {
    final _Repo repo = _Repo(<List<ClientReviewComment>>[
      <ClientReviewComment>[_c('a')],
    ]);
    final ProviderContainer c = _container(repo, auth: _SignedOut.new);

    final ClientCommentsState s = await _load(c);

    expect(s.comments, isEmpty);
    expect(s.hasMore, isFalse);
    expect(repo.requested, isEmpty);
  });
}
