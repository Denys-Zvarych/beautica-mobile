// M509 — the «Клієнти» list controller: a paged, searchable list per
// [ClientListScope] (salon / salon + masterId / me), backed by
// [ClientRepository] (B507).
//
// A `@riverpod` AsyncNotifier family keyed by the scope (freezed, so equal
// scopes share one list). Page size 20, append on scroll ([loadMore]), pull to
// refresh ([refresh]) and a 300 ms debounced name search ([setQuery]).
//
// SEARCH (B507): `q` is sent only for a trimmed 2–50-char term. Blank,
// whitespace-only or 1-char input sends NO `q` — a blank `q` is a 400 — and a
// longer one is capped at 50. A change of the EFFECTIVE `q` re-queries page 0
// behind the skeleton; typing that lands on the same effective `q` (e.g. «а»
// then «» — both none) costs nothing. The debounce is a `Timer`: tests must
// pump the duration explicitly (`pumpAndSettle` fires no Timer).
//
// STALE RESPONSES: every re-query / refresh bumps [_generation]; a load-more
// that resolves under an older generation is dropped, so a slow page 2 of the
// OLD search can never be appended to the NEW one.
//
// CANCELLATION: each generation owns a Dio [CancelToken]; a newer reload, a
// session change or dispose cancels the superseded request. A cancelled /
// stale result is dropped by the generation check, never surfaced as an error.
//
// A failed load-more keeps the rendered list, clears the spinner and raises
// [ClientListState.loadMoreFailed] — which BLOCKS further auto-appends (the
// scroll listener would otherwise re-fire the failing call on every frame)
// until the user pulls to refresh or changes the search.
//
// A failed PULL TO REFRESH with rows on screen keeps those rows (the state goes
// back to the previous data) and hands the error to the caller, which shows a
// snack; only a list with nothing loaded surfaces as the error state.
//
// CACHE-FOR: once nothing listens (the master «Клієнти» tab is left with
// `context.go`, unmounting it), the instance stays cached for
// [kClientListCacheFor] — pages, scroll-backing items and the applied search
// survive a quick tab round-trip. A new listener inside the window cancels the
// timer. Freshness is not traded away: a block / unblock and every booking
// mutation invalidate the WHOLE family (card / blocked-clients screen and
// `booking_calendar_invalidation.dart`).
//
// HOST (M552): the family key also carries a [ClientListHost]. The «Клієнти»
// tab ([ClientListHost.tab], the default) behaves exactly as above; the client
// picker ([ClientListHost.picker]) gets its OWN instance — its search never
// changes the tab's list — with no cache-for, so it is released when the sheet
// closes and every open starts with an empty search.
//
// REMOVE (M544, CLI-86): [remove] drops the row at once (optimistic, keeping
// its index) and calls the B564 write; a failure puts it back at the same
// index. [restore] (the undo snack) puts it back and calls restore. THIS list
// keeps its loaded pages; the other instances (owner `masterId` views, the
// picker) refetch once per swipe burst, when the undo window closes
// ([ClientListRemovalBroadcast], `client_list_removal.dart`). A failed
// restore refetches the whole family (server truth).
//
// PII: names are never logged.

import 'dart:async';
import 'dart:developer';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderListenableSelect;
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/clients/application/client_list_removal.dart';
import 'package:beautica_mobile/features/clients/data/client_repository.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';

part 'client_list_controller.freezed.dart';
part 'client_list_controller.g.dart';

/// Quiet period after the last keystroke before the search re-queries.
const Duration kClientSearchDebounce = Duration(milliseconds: 300);

/// How long an unlistened [ClientListController] instance stays cached.
const Duration kClientListCacheFor = Duration(seconds: 30);

/// Which surface hosts a [ClientListController] instance (part of the family
/// key, so the two never share a search).
enum ClientListHost {
  /// The «Клієнти» tab: cached for [kClientListCacheFor] once unlistened.
  tab,

  /// The client-picker sheet: released as soon as the sheet closes.
  picker,
}

/// What [ClientListController.remove] did: the row's former [index] (for the
/// undo) and the write's [error] (`null` = removed; else the row is back).
typedef ClientRemoval = ({int index, Object? error});

/// The loaded list and its paging cursor.
@freezed
abstract class ClientListState with _$ClientListState {
  const factory ClientListState({
    required List<ClientSummary> items,

    /// Zero-based index of the last fetched page.
    required int page,
    required bool hasMore,

    /// The `q` this list was fetched with (`null` = none sent).
    String? query,
    @Default(false) bool isLoadingMore,

    /// The last [ClientListController.loadMore] failed: the list stays, the
    /// footer spinner is gone and auto-append is paused (see the file header).
    @Default(false) bool loadMoreFailed,

    /// A NEW search (changed `q`) is loading: [items] still belong to the OLD
    /// query, so the screen shows the skeleton instead of them. Never set by a
    /// pull to refresh, which keeps its rows visible.
    @Default(false) bool isSearching,
  }) = _ClientListState;

  const ClientListState._();

  /// `true` when a scroll near the end may start another page.
  bool get canLoadMore => hasMore && !isLoadingMore && !loadMoreFailed;
}

@riverpod
class ClientListController extends _$ClientListController {
  static const String _tag = 'feature.clients';

  /// The applied search term — survives [ref.invalidateSelf] re-builds so a
  /// retry / refresh re-issues the SAME query.
  String? _query;
  Timer? _debounce;
  int _generation = 0;
  bool _refreshing = false;

  /// A page-0 reload (refresh or new search) is in flight: [loadMore] must not
  /// start, or its page+1 would race the fresh result.
  bool _reloading = false;

  /// The signed-in user this list was built for (see [build]).
  String? _userId;

  /// One per generation: cancelled when a newer reload / rebuild supersedes it.
  CancelToken? _token;

  @override
  Future<ClientListState> build(
    ClientListScope scope, {
    ClientListHost host = ClientListHost.tab,
  }) {
    // M544 — a swipe burst elsewhere changed what this list shows: refetch,
    // unless THIS instance made the whole burst (it already shows it).
    ref.listen<ClientListRemovalEpoch>(clientListRemovalBroadcastProvider, (
      ClientListRemovalEpoch? _,
      ClientListRemovalEpoch next,
    ) {
      if (clientListNeedsRefetch(next, _source)) ref.invalidateSelf();
    });
    ref.onDispose(() {
      _debounce?.cancel();
      _token?.cancel();
    });
    // Session-boundary PII watch (the master archive's phase 342 rule): the
    // list holds client names, so a different signed-in identity must rebuild
    // it instead of repainting the previous account's rows. Narrowed to the
    // user id — a silent token refresh re-emits the session with the same id
    // and must not drop the accumulated pages.
    final String? userId = ref.watch(authProvider.select(authUserIdOrNull));
    // A different identity (login as B, logout) must never inherit A's filter
    // or A's in-flight pages: drop the term and the pending debounce, bump the
    // generation (stale `loadMore` / reload results are then discarded) and
    // abort A's request. A same-user rebuild keeps the applied query.
    if (userId != _userId) {
      _userId = userId;
      _query = null;
      _debounce?.cancel();
    }
    final CancelToken token = _supersede();
    _reloading = false;
    // The picker keeps nothing between opens (see the file header).
    if (host == ClientListHost.tab) _cacheFor();
    // Logged out: nothing to show and nothing to fetch.
    if (userId == null) {
      return Future<ClientListState>.value(
        const ClientListState(
          items: <ClientSummary>[],
          page: 0,
          hasMore: false,
        ),
      );
    }
    return _fetchFirstPage(token);
  }

  /// The `ClientVisitsController` cache-for pattern: keep alive while
  /// unlistened for [kClientListCacheFor], then release.
  void _cacheFor() {
    // The link type is not exported by riverpod 3's public API.
    final link = ref.keepAlive();
    Timer? timer;
    ref
      ..onCancel(() {
        timer?.cancel();
        timer = Timer(kClientListCacheFor, link.close);
      })
      ..onResume(() => timer?.cancel())
      ..onDispose(() => timer?.cancel());
  }

  /// Starts a new generation: cancels the previous request and returns the
  /// token for the new one.
  CancelToken _supersede() {
    _generation++;
    _token?.cancel();
    return _token = CancelToken();
  }

  Future<ClientListState> _fetchFirstPage(CancelToken token) async {
    final String? query = _query;
    final PageResponse<ClientSummary> page = await ref
        .read(clientRepositoryProvider)
        .list(scope, q: query, page: 0, cancelToken: token);
    return ClientListState(
      items: page.items,
      page: page.page,
      hasMore: page.hasMore,
      query: query,
    );
  }

  /// Feeds the raw search-box text. Debounced by [kClientSearchDebounce]; the
  /// effective `q` ([clientQueryFor]) decides whether anything is re-queried.
  void setQuery(String raw) {
    _debounce?.cancel();
    _debounce = Timer(kClientSearchDebounce, () => _applyQuery(raw));
  }

  /// Drops a pending [setQuery] debounce, so a search typed just before the
  /// host closes never fetches (called from `ClientListView.dispose`).
  void cancelPendingSearch() {
    _debounce?.cancel();
    _debounce = null;
  }

  Future<void> _applyQuery(String raw) async {
    final String? next = clientQueryFor(raw);
    if (next == _query) return;
    _query = next;
    await _reload();
  }

  /// Re-fetches page 0 with the current query. A refresh ([keepRows]) keeps the
  /// rows on screen; a NEW search flags [ClientListState.isSearching] so the
  /// screen shows the skeleton, not the previous query's rows (Riverpod 3
  /// carries the previous value on `AsyncLoading` either way). The LAST reload
  /// wins: a result that resolves after a newer one started is dropped.
  ///
  /// A failed refresh ([keepRows]) over a loaded, non-searching list restores
  /// that list and returns the error; otherwise the error becomes the state
  /// and `null` is returned.
  Future<Object?> _reload({bool keepRows = false}) async {
    final CancelToken token = _supersede();
    final int generation = _generation;
    _reloading = true;
    final ClientListState? previous = state.hasError ? null : state.value;
    if (!keepRows && previous != null) {
      state = AsyncData<ClientListState>(previous.copyWith(isSearching: true));
    }
    state = const AsyncLoading<ClientListState>();
    final AsyncValue<ClientListState> result = await AsyncValue.guard(
      () => _fetchFirstPage(token),
    );
    if (!ref.mounted || generation != _generation) return null;
    _reloading = false;
    if (keepRows &&
        result.hasError &&
        previous != null &&
        !previous.isSearching) {
      state = AsyncData<ClientListState>(previous);
      return result.error;
    }
    state = result;
    return null;
  }

  /// Re-fetches page 0 with the current query — pull to refresh and the error
  /// state's retry. Coalesces concurrent calls. Returns the error of a failed
  /// refresh that KEPT the loaded rows (the screen snacks it), else `null`.
  Future<Object?> refresh() async {
    if (_refreshing) return null;
    _refreshing = true;
    try {
      return await _reload(keepRows: true);
    } finally {
      _refreshing = false;
    }
  }

  /// Retries a failed append: clears [ClientListState.loadMoreFailed] and
  /// re-issues the same page (the footer's retry button).
  Future<void> retryLoadMore() async {
    final ClientListState? current = state.value;
    if (current == null || !current.loadMoreFailed) return;
    state = AsyncData<ClientListState>(current.copyWith(loadMoreFailed: false));
    await loadMore();
  }

  /// Appends the next page. No-op while loading or reloading, in flight, exhausted, or
  /// after a failed append (see the file header).
  Future<void> loadMore() async {
    final ClientListState? current = state.value;
    if (_reloading || current == null || !current.canLoadMore) return;
    final int generation = _generation;
    final CancelToken? token = _token;
    state = AsyncData<ClientListState>(current.copyWith(isLoadingMore: true));
    try {
      final PageResponse<ClientSummary> page = await ref
          .read(clientRepositoryProvider)
          .list(
            scope,
            q: current.query,
            page: current.page + 1,
            cancelToken: token,
          );
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData<ClientListState>(
        current.copyWith(
          items: List<ClientSummary>.unmodifiable(<ClientSummary>[
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
      // Keep the rendered list; a first-page error is the error state's job.
      log('loadMore failed', name: _tag, level: 900);
      state = AsyncData<ClientListState>(
        current.copyWith(isLoadingMore: false, loadMoreFailed: true),
      );
    }
  }

  /// This instance's stable identity (its family key) for the removal
  /// broadcast — never `this` (see [ClientListSource]).
  ClientListSource get _source => (scope: scope, host: host);

  /// M544 — removes [item]'s row at once, then calls the removal write. On
  /// failure the row goes back at the same index (unless a reload replaced
  /// the list meanwhile — the server's page is the truth then). `null` when
  /// the row is not on the list (nothing to remove).
  Future<ClientRemoval?> remove(ClientSummary item) async {
    final ClientListState? current = state.value;
    if (current == null) return null;
    final int index = current.items.indexWhere(
      (ClientSummary s) => s.ref == item.ref,
    );
    if (index < 0) return null;
    final int generation = _generation;
    // Built once and handed to freezed as its own unmodifiable view (no
    // second copy; a stable `items` instance for identity memos).
    state = AsyncData<ClientListState>(
      current.copyWith(
        items: EqualUnmodifiableListView<ClientSummary>(
          List<ClientSummary>.of(current.items)..removeAt(index),
        ),
      ),
    );
    try {
      await ref.read(clientRepositoryProvider).removeFromList(scope, item.ref);
      // The other list instances hear about it once the undo window closes;
      // this one keeps its pages (see the file header).
      if (ref.mounted) {
        ref
            .read(clientListRemovalBroadcastProvider.notifier)
            .removed(_source, item.ref);
      }
      return (index: index, error: null);
    } catch (e) {
      if (kDebugMode) log('remove failed', name: _tag, level: 900);
      if (ref.mounted && generation == _generation) _reinsert(item, index);
      return (index: index, error: e);
    }
  }

  /// M544 — the undo: puts [item] back at [index] and calls restore. On
  /// success this list keeps its pages and the others hear about it with the
  /// burst; a failure refetches the whole family (the server's truth).
  /// Returns the restore error, or `null`.
  Future<Object?> restore(ClientSummary item, int index) async {
    _reinsert(item, index);
    try {
      await ref.read(clientRepositoryProvider).restoreToList(scope, item.ref);
    } catch (e) {
      if (ref.mounted) {
        // The whole family refetches now: no pending flush may do it a
        // second time (any source's).
        ref.read(clientListRemovalBroadcastProvider.notifier).cancelAll();
        ref.invalidate(clientListControllerProvider);
      }
      return e;
    }
    if (ref.mounted) {
      ref
          .read(clientListRemovalBroadcastProvider.notifier)
          .restored(_source, item.ref);
    }
    return null;
  }

  /// Inserts [item] at [index] (clamped) unless it is already listed.
  void _reinsert(ClientSummary item, int index) {
    final ClientListState? current = state.value;
    if (current == null ||
        current.items.any((ClientSummary s) => s.ref == item.ref)) {
      return;
    }
    state = AsyncData<ClientListState>(
      current.copyWith(
        items: EqualUnmodifiableListView<ClientSummary>(
          List<ClientSummary>.of(current.items)
            ..insert(index.clamp(0, current.items.length), item),
        ),
      ),
    );
  }
}
