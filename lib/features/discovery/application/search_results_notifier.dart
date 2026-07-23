// Phase 13.4 — Discovery results notifier (network + pagination).
//
// A `@riverpod` AsyncNotifier seeded with the [SearchFilters] forwarded from the
// Пошук filters screen (13.3) via `context.push(extra:)`. It queries BOTH
// discovery endpoints — `/search/masters` AND `/search/salons` — because the
// approved results screen mixes master and salon cards in a single list.
//
// Pagination: masters and salons are paged INDEPENDENTLY (each endpoint has its
// own page cursor + hasMore). The notifier merges each fetched page as
// `[…masters, …salons]` appended to the running list. [loadMore] advances only
// the endpoints that still have pages, guards against a double-fetch (an
// in-flight [loadMore] is a no-op), and is a no-op once both endpoints are
// exhausted.
//
// The four AsyncValue states the screen renders map onto this notifier:
//   • AsyncLoading (no data)        → first-page skeleton,
//   • AsyncData (non-empty)         → the card list (+ bottom spinner while
//                                     [isLoadingMore] is true),
//   • AsyncData (empty)             → the empty state,
//   • AsyncError                    → the retry state.
//
// Error path note (mobile-backlog row 236): the repository throws a typed
// [Failure] (an Error-like sealed type implementing Exception). A widget test
// that wants a synchronous pure AsyncError can override the repo to throw a
// `StateError` and pump once; the build() future then completes with an error
// on the first frame rather than lingering in seamless AsyncLoading.

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/search_repository.dart';
import '../data/search_repository_provider.dart';
import '../domain/master_search_item.dart';
import '../domain/salon_search_item.dart';
import '../domain/search_filters.dart';
import '../domain/search_result_item.dart';

part 'search_results_notifier.g.dart';

/// Immutable snapshot of the merged results list + paging cursors.
@immutable
class SearchResultsState {
  const SearchResultsState({
    required this.items,
    required this.masterPage,
    required this.masterHasMore,
    required this.salonPage,
    required this.salonHasMore,
    this.isLoadingMore = false,
  });

  /// The merged master + salon results accumulated so far, in display order.
  final List<SearchResultItem> items;

  /// Zero-based index of the last fetched masters page.
  final int masterPage;

  /// Whether `/search/masters` has another page beyond [masterPage].
  final bool masterHasMore;

  /// Zero-based index of the last fetched salons page.
  final int salonPage;

  /// Whether `/search/salons` has another page beyond [salonPage].
  final bool salonHasMore;

  /// Whether a [SearchResultsNotifier.loadMore] fetch is currently in flight.
  /// The screen shows the bottom spinner while this is true.
  final bool isLoadingMore;

  /// Whether any endpoint still has a page to fetch.
  bool get hasMore => masterHasMore || salonHasMore;

  SearchResultsState copyWith({
    List<SearchResultItem>? items,
    int? masterPage,
    bool? masterHasMore,
    int? salonPage,
    bool? salonHasMore,
    bool? isLoadingMore,
  }) {
    return SearchResultsState(
      items: items ?? this.items,
      masterPage: masterPage ?? this.masterPage,
      masterHasMore: masterHasMore ?? this.masterHasMore,
      salonPage: salonPage ?? this.salonPage,
      salonHasMore: salonHasMore ?? this.salonHasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

/// Paged discovery results for a given [filters] set.
///
/// Family-keyed by [SearchFilters] so two different searches never share a
/// cache entry. autoDispose (the default for a `@riverpod class`) so the cache
/// is dropped when the results screen is popped — a fresh search rebuilds from
/// page 0.
@riverpod
class SearchResultsNotifier extends _$SearchResultsNotifier {
  @override
  Future<SearchResultsState> build(SearchFilters filters) async {
    return _fetchFirstPage(filters);
  }

  /// Fetches page 0 of BOTH endpoints in parallel and merges them.
  Future<SearchResultsState> _fetchFirstPage(SearchFilters filters) async {
    final SearchRepository repo = ref.read(searchRepositoryProvider);
    final results = await Future.wait(<Future<dynamic>>[
      repo.searchMasters(filters: filters, page: 0),
      repo.searchSalons(filters: filters, page: 0),
    ]);
    final masters = results[0] as SearchPage<MasterSearchItem>;
    final salons = results[1] as SearchPage<SalonSearchItem>;

    return SearchResultsState(
      items: _merge(masters.items, salons.items),
      masterPage: 0,
      masterHasMore: masters.hasMore,
      salonPage: 0,
      salonHasMore: salons.hasMore,
    );
  }

  /// Appends the next page from whichever endpoint(s) still have one.
  ///
  /// No-op when: the notifier has no data yet (still loading / errored), a
  /// load-more is already in flight, or both endpoints are exhausted.
  Future<void> loadMore() async {
    final SearchResultsState? current = state.value;
    if (current == null) return;
    if (current.isLoadingMore) return; // double-fetch guard
    if (!current.hasMore) return; // last page no-op

    // Flag the in-flight load WITHOUT flipping the whole provider to
    // AsyncLoading (we keep the current data on screen + show a bottom spinner).
    state = AsyncData(current.copyWith(isLoadingMore: true));

    final SearchRepository repo = ref.read(searchRepositoryProvider);

    try {
      final int nextMasterPage = current.masterPage + 1;
      final int nextSalonPage = current.salonPage + 1;

      final results = await Future.wait(<Future<dynamic>>[
        if (current.masterHasMore)
          repo.searchMasters(filters: filters, page: nextMasterPage)
        else
          Future<SearchPage<MasterSearchItem>?>.value(null),
        if (current.salonHasMore)
          repo.searchSalons(filters: filters, page: nextSalonPage)
        else
          Future<SearchPage<SalonSearchItem>?>.value(null),
      ]);

      final masters = results[0] as SearchPage<MasterSearchItem>?;
      final salons = results[1] as SearchPage<SalonSearchItem>?;

      final List<SearchResultItem> appended = _merge(
        masters?.items ?? const <MasterSearchItem>[],
        salons?.items ?? const <SalonSearchItem>[],
      );

      state = AsyncData(
        current.copyWith(
          items: <SearchResultItem>[...current.items, ...appended],
          masterPage: masters != null ? nextMasterPage : current.masterPage,
          masterHasMore: masters?.hasMore ?? current.masterHasMore,
          salonPage: salons != null ? nextSalonPage : current.salonPage,
          salonHasMore: salons?.hasMore ?? current.salonHasMore,
          isLoadingMore: false,
        ),
      );
    } catch (_) {
      // A failed load-more must not blow away the already-rendered list (that is
      // the first-page error state's job). Just clear the spinner and keep the
      // current page so the user can scroll to retry the next page.
      state = AsyncData(current.copyWith(isLoadingMore: false));
    }
  }

  /// Merges a master page and a salon page into the display order:
  /// masters first, then salons (matching the approved preview's grouping).
  List<SearchResultItem> _merge(
    List<MasterSearchItem> masters,
    List<SalonSearchItem> salons,
  ) {
    return <SearchResultItem>[
      for (final MasterSearchItem m in masters) MasterResultItem(m),
      for (final SalonSearchItem s in salons) SalonResultItem(s),
    ];
  }
}
