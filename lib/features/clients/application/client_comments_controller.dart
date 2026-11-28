// M545 — the anonymous comments on «Рейтинг клієнта» (B565, REV-44): a paged
// AsyncNotifier family per (scope, client), page size 20, appended on scroll
// ([loadMore]). The [ClientVisitsController] paging pattern without its
// next-visit lookahead:
//
// A failed append keeps the loaded rows and raises
// [ClientCommentsState.loadMoreFailed], which pauses auto-append until
// [retryLoadMore] (E5). Every build bumps [_generation]; an append that
// resolves after a rebuild drops its result.
//
// PII: comment text is never logged.

import 'dart:developer';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderListenableSelect;
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/clients/data/client_repository.dart';
import 'package:beautica_mobile/features/clients/domain/client_review_comment.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';

part 'client_comments_controller.freezed.dart';
part 'client_comments_controller.g.dart';

@freezed
abstract class ClientCommentsState with _$ClientCommentsState {
  const factory ClientCommentsState({
    /// Every loaded comment, newest first (server order).
    required List<ClientReviewComment> comments,
    required int page,
    required bool hasMore,
    @Default(false) bool isLoadingMore,
    @Default(false) bool loadMoreFailed,
  }) = _ClientCommentsState;

  const ClientCommentsState._();

  bool get canLoadMore => hasMore && !isLoadingMore && !loadMoreFailed;
}

@riverpod
class ClientCommentsController extends _$ClientCommentsController {
  static const String _tag = 'feature.clients';

  CancelToken? _token;

  /// Bumped on every build; a load-more that resolves under an older value is
  /// stale and dropped.
  int _generation = 0;

  @override
  Future<ClientCommentsState> build(
    ClientListScope scope,
    ClientRef client,
  ) async {
    final String? userId = ref.watch(authProvider.select(authUserIdOrNull));
    _generation++;
    final CancelToken token = _token = CancelToken();
    ref.onDispose(token.cancel);
    if (userId == null) {
      return const ClientCommentsState(
        comments: <ClientReviewComment>[],
        page: 0,
        hasMore: false,
      );
    }
    final PageResponse<ClientReviewComment> page = await ref
        .read(clientCommentsRepositoryProvider)
        .getComments(scope, client, cancelToken: token);
    return ClientCommentsState(
      comments: page.items,
      page: page.page,
      hasMore: page.hasMore,
    );
  }

  /// Appends the next page. No-op while loading, exhausted or after a failed
  /// append.
  Future<void> loadMore() async {
    final ClientCommentsState? current = state.value;
    if (state.isLoading || current == null || !current.canLoadMore) return;
    final int generation = _generation;
    state = AsyncData<ClientCommentsState>(
      current.copyWith(isLoadingMore: true),
    );
    try {
      final PageResponse<ClientReviewComment> page = await ref
          .read(clientCommentsRepositoryProvider)
          .getComments(
            scope,
            client,
            page: current.page + 1,
            cancelToken: _token,
          );
      if (!ref.mounted || generation != _generation) return;
      // E6 — a row removed by moderation between pages is simply absent; a
      // row that shifted onto the next page is not shown twice.
      final Set<String> seen = <String>{
        for (final ClientReviewComment c in current.comments) c.reviewId,
      };
      state = AsyncData<ClientCommentsState>(
        current.copyWith(
          comments:
              List<ClientReviewComment>.unmodifiable(<ClientReviewComment>[
                ...current.comments,
                ...page.items.where(
                  (ClientReviewComment c) => !seen.contains(c.reviewId),
                ),
              ]),
          page: page.page,
          hasMore: page.hasMore,
          isLoadingMore: false,
        ),
      );
    } catch (_) {
      if (!ref.mounted || generation != _generation) return;
      log('comments loadMore failed', name: _tag, level: 900);
      state = AsyncData<ClientCommentsState>(
        current.copyWith(isLoadingMore: false, loadMoreFailed: true),
      );
    }
  }

  /// Retries a failed append (clears the pause, re-issues the same page).
  Future<void> retryLoadMore() async {
    final ClientCommentsState? current = state.value;
    if (current == null || !current.loadMoreFailed) return;
    state = AsyncData<ClientCommentsState>(
      current.copyWith(loadMoreFailed: false),
    );
    await loadMore();
  }

  /// M572 (REV-45, CLI-102) — deletes the viewer's OWN rating (the whole
  /// review, comment included) on the server. The list is NOT touched: the row
  /// stays exactly where it was, so a failure needs no restore and nothing
  /// flashes. The caller plays the row's collapse-out and then calls
  /// [dropComment].
  ///
  /// Returns `true` when the server deleted it, `false` when it was already
  /// gone (404); throws the [Failure] otherwise. The caller invalidates the
  /// dependent views (card summary, list row, pending count, booking detail)
  /// — never in here.
  Future<bool> deleteOwn(String reviewId) async {
    try {
      await ref
          .read(clientCommentsRepositoryProvider)
          .deleteOwnReview(reviewId);
      return true;
    } on NotFoundFailure {
      return false;
    } catch (_) {
      log('own comment delete failed', name: _tag, level: 900);
      rethrow;
    }
  }

  /// M572 — removes the row for [reviewId] from the loaded list (after its
  /// collapse-out). Returns `false` when it could not act — the provider is
  /// disposed or holds no loaded list — and `true` otherwise (the row is not
  /// in the list any more).
  bool dropComment(String reviewId) {
    if (!ref.mounted) return false;
    final ClientCommentsState? current = state.value;
    if (current == null) return false;
    state = AsyncData<ClientCommentsState>(
      current.copyWith(
        comments: List<ClientReviewComment>.unmodifiable(<ClientReviewComment>[
          for (final ClientReviewComment c in current.comments)
            if (c.reviewId != reviewId) c,
        ]),
      ),
    );
    return true;
  }
}
