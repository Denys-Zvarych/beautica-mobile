// REV-38..44 / CLI-93 — `invalidateClientViews`, the ONE fan-out a write
// calls when it changed what the provider's client views show. A client
// review submit (`LeaveClientFeedbackScreen`) calls it; this file pins WHICH
// views it re-fetches: the «Клієнти» list, the client card, the visit
// timeline and (M545) the «Рейтинг клієнта» comments list — a review may add
// a comment there. Each member is listened (mounted), so the invalidate is
// observed as a second repository read. Falsifiable: drop any `invalidate`
// line from the helper and that member's count stays at 1.

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/clients/application/client_card_controller.dart';
import 'package:beautica_mobile/features/clients/application/client_comments_controller.dart';
import 'package:beautica_mobile/features/clients/application/client_list_controller.dart';
import 'package:beautica_mobile/features/clients/application/client_views_invalidation.dart';
import 'package:beautica_mobile/features/clients/application/client_visits_controller.dart';
import 'package:beautica_mobile/features/clients/data/client_repository.dart';
import 'package:beautica_mobile/features/clients/domain/client_card.dart';
import 'package:beautica_mobile/features/clients/domain/client_review_comment.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/clients/domain/client_visit.dart';
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_notification_repository.dart';
import '../../../helpers/test_container.dart';

const ClientListScope _me = ClientListScope.me();
const ClientRef _client = ClientRef.registered('u-1');

PageResponse<T> _empty<T>(int page) => PageResponse<T>(
  items: List<T>.empty(),
  page: page,
  totalPages: 1,
  totalElements: 0,
);

/// Counts the first-page read of every client view.
class _Repo implements ClientRepository, ClientCommentsRepository {
  int listCalls = 0;
  int cardCalls = 0;
  int visitsCalls = 0;
  int commentsCalls = 0;

  @override
  Future<PageResponse<ClientSummary>> list(
    ClientListScope scope, {
    String? q,
    int page = 0,
    int size = kClientPageSize,
    CancelToken? cancelToken,
  }) async {
    if (page == 0) listCalls++;
    return _empty<ClientSummary>(page);
  }

  @override
  Future<ClientCard> getCard(
    ClientListScope scope,
    ClientRef client, {
    CancelToken? cancelToken,
  }) async {
    cardCalls++;
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
    if (page == 0) visitsCalls++;
    return _empty<ClientVisit>(page);
  }

  @override
  Future<PageResponse<ClientReviewComment>> getComments(
    ClientListScope scope,
    ClientRef client, {
    int page = 0,
    int size = kClientPageSize,
    CancelToken? cancelToken,
  }) async {
    if (page == 0) commentsCalls++;
    return _empty<ClientReviewComment>(page);
  }

  @override
  Future<void> removeFromList(ClientListScope scope, ClientRef client) =>
      throw UnimplementedError();

  @override
  Future<void> restoreToList(ClientListScope scope, ClientRef client) =>
      throw UnimplementedError();
}

/// Listens to (mounts) all four views and waits until each has loaded.
Future<void> _loadAll(ProviderContainer c) async {
  final List<ProviderSubscription<Object?>> subs =
      <ProviderSubscription<Object?>>[
        c.listen(clientListControllerProvider(_me), (_, _) {}),
        c.listen(clientCardProvider(_me, _client), (_, _) {}),
        c.listen(clientVisitsControllerProvider(_me, _client), (_, _) {}),
        c.listen(clientCommentsControllerProvider(_me, _client), (_, _) {}),
      ];
  for (final ProviderSubscription<Object?> sub in subs) {
    addTearDown(sub.close);
  }
  await Future.wait<Object?>(<Future<Object?>>[
    c.read(clientListControllerProvider(_me).future),
    c.read(clientCardProvider(_me, _client).future),
    c.read(clientVisitsControllerProvider(_me, _client).future),
    c.read(clientCommentsControllerProvider(_me, _client).future),
  ]);
}

void main() {
  test('invalidateClientViews re-fetches the list, card, visits and the '
      '«Рейтинг клієнта» comments', () async {
    final _Repo repo = _Repo();
    final ProviderContainer c = makeTestContainer(
      retry: (_, _) => null,
      overrides: <Object>[
        clientRepositoryProvider.overrideWithValue(repo),
        clientCommentsRepositoryProvider.overrideWithValue(repo),
        authProvider.overrideWith(
          () => FixedRoleAuth(UserRole.independentMaster),
        ),
      ],
    );
    await _loadAll(c);
    expect(
      <int>[repo.listCalls, repo.cardCalls, repo.visitsCalls],
      <int>[1, 1, 1],
    );
    expect(repo.commentsCalls, 1);

    invalidateClientViews(c.invalidate);
    await _loadAll(c);

    expect(repo.listCalls, 2, reason: 'the «Клієнти» list must re-fetch');
    expect(repo.cardCalls, 2, reason: 'the client card must re-fetch');
    expect(repo.visitsCalls, 2, reason: 'the visit timeline must re-fetch');
    expect(
      repo.commentsCalls,
      2,
      reason: 'M545: a review may add a comment — the comments must re-fetch',
    );
  });
}
