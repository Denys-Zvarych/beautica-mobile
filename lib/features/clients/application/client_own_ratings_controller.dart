// M510 — «Ваші оцінки»: the viewer's own per-visit stars for one client (B526),
// paged 20, watched ONLY by the rating page (so the card never pays for it).
// Stars only — the contract and [ClientOwnRating] have no comment text.
//
// A failed append keeps the rows and pauses auto-append until [retryLoadMore].
// An append resolving after a rebuild/refresh is dropped ([_generation]).

import 'dart:developer';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderListenableSelect;
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/clients/data/client_repository.dart';
import 'package:beautica_mobile/features/clients/domain/client_own_rating.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';

part 'client_own_ratings_controller.freezed.dart';
part 'client_own_ratings_controller.g.dart';

@freezed
abstract class ClientOwnRatingsState with _$ClientOwnRatingsState {
  const factory ClientOwnRatingsState({
    required List<ClientOwnRating> items,
    required int page,
    required bool hasMore,
    @Default(false) bool isLoadingMore,
    @Default(false) bool loadMoreFailed,
  }) = _ClientOwnRatingsState;

  const ClientOwnRatingsState._();

  bool get canLoadMore => hasMore && !isLoadingMore && !loadMoreFailed;
}

@riverpod
class ClientOwnRatingsController extends _$ClientOwnRatingsController {
  static const String _tag = 'feature.clients';

  CancelToken? _token;

  /// Bumped on every build; a stale load-more result is dropped.
  int _generation = 0;

  @override
  Future<ClientOwnRatingsState> build(
    ClientListScope scope,
    ClientRef client,
  ) async {
    final String? userId = ref.watch(authProvider.select(authUserIdOrNull));
    _generation++;
    final CancelToken token = _token = CancelToken();
    ref.onDispose(token.cancel);
    if (userId == null) {
      return const ClientOwnRatingsState(
        items: <ClientOwnRating>[],
        page: 0,
        hasMore: false,
      );
    }
    final PageResponse<ClientOwnRating> page = await ref
        .read(clientRepositoryProvider)
        .getOwnRatings(scope, client, page: 0, cancelToken: token);
    return ClientOwnRatingsState(
      items: page.items,
      page: page.page,
      hasMore: page.hasMore,
    );
  }

  /// Appends the next page. No-op while loading or reloading (pull-to-refresh),
  /// exhausted or after a failed append.
  Future<void> loadMore() async {
    final ClientOwnRatingsState? current = state.value;
    if (state.isLoading || current == null || !current.canLoadMore) return;
    final int generation = _generation;
    state = AsyncData<ClientOwnRatingsState>(
      current.copyWith(isLoadingMore: true),
    );
    try {
      final PageResponse<ClientOwnRating> page = await ref
          .read(clientRepositoryProvider)
          .getOwnRatings(
            scope,
            client,
            page: current.page + 1,
            cancelToken: _token,
          );
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData<ClientOwnRatingsState>(
        current.copyWith(
          items: List<ClientOwnRating>.unmodifiable(<ClientOwnRating>[
            ...current.items,
            ...page.items,
          ]),
          page: page.page,
          hasMore: page.hasMore,
          isLoadingMore: false,
        ),
      );
    } catch (_) {
      if (!ref.mounted || generation != _generation) return;
      log('own ratings loadMore failed', name: _tag, level: 900);
      state = AsyncData<ClientOwnRatingsState>(
        current.copyWith(isLoadingMore: false, loadMoreFailed: true),
      );
    }
  }

  Future<void> retryLoadMore() async {
    final ClientOwnRatingsState? current = state.value;
    if (current == null || !current.loadMoreFailed) return;
    state = AsyncData<ClientOwnRatingsState>(
      current.copyWith(loadMoreFailed: false),
    );
    await loadMore();
  }
}
