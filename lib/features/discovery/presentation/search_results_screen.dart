// Phase 13.4 — CLIENT discovery results screen («Результати»).
//
// Ports the approved preview `docs/signup-designs/SearchBooking/lib/screens/
// search_results_screen.dart` into the real Riverpod + go_router structure:
//   • top bar — back affordance · centred «Результати» title · filter icon
//     (SVG funnel) that re-opens the 13.3 filter controls (pops back to the
//     still-populated filters screen), with a «(N)» active-filter-count badge
//     beside it when one or more facets are applied;
//   • a scrolling list of master + salon result cards, infinite-scroll via a
//     ScrollController calling loadMore() near the end + a bottom spinner;
//   • the four AsyncValue states (skeleton / cards / empty / error).
//
// The screen owns the live [SearchFilters] in local state (seeded from the
// `extra:` forwarded by 13.3). The filter set re-keys the family-scoped
// [searchResultsProvider] — a fresh page-0 fetch. The active-filter count is
// derived directly from [SearchFilters.activeFilterCount].
//
// go_router only — the back/filter affordances use context.pop(); cards push the
// public-profile routes. No Navigator anywhere.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import '../application/search_results_notifier.dart';
import '../domain/search_filters.dart';
import '../domain/search_result_item.dart';
import 'state/search_filters_controller.dart';
import 'widgets/master_result_card.dart';
import 'widgets/results_states.dart';
import 'widgets/salon_result_card.dart';
import 'widgets/sort_options_sheet.dart';

/// The discovery results screen. Receives the assembled [SearchFilters] via the
/// router's `extra`.
class SearchResultsScreen extends ConsumerStatefulWidget {
  const SearchResultsScreen({super.key, required this.initialFilters});

  /// The filter set forwarded from the Пошук screen. Null when reached without
  /// `extra` (e.g. a deep link) — treated as an empty filter set (browse all).
  final SearchFilters? initialFilters;

  @override
  ConsumerState<SearchResultsScreen> createState() =>
      _SearchResultsScreenState();
}

class _SearchResultsScreenState extends ConsumerState<SearchResultsScreen> {
  /// Pixels-from-bottom threshold that triggers the next-page fetch.
  static const double _loadMoreThreshold = 320;

  late SearchFilters _filters;
  final ScrollController _scrollController = ScrollController();

  // Cheap scroll-listener guards, refreshed from the watched provider each
  // build. They let _onScroll short-circuit before re-resolving the family on
  // every scroll pixel; the notifier-level double-fetch guard is the backstop.
  bool _hasMore = false;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _filters = widget.initialFilters ?? const SearchFilters();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Short-circuit before re-resolving the family: nothing left to fetch, or a
    // fetch is already in flight.
    if (!_hasMore || _isLoadingMore) return;
    if (!_scrollController.hasClients) return;
    final ScrollPosition pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - _loadMoreThreshold) {
      // The notifier itself guards against double-fetch + last-page no-op.
      ref.read(searchResultsProvider(_filters).notifier).loadMore();
    }
  }

  /// Re-opens the filter controls — pops back to the 13.3 filters screen, where
  /// the keepAlive controllers still hold the current selection.
  void _openFilters() {
    if (context.canPop()) {
      context.pop();
    }
  }

  /// Applies a new sort ordering: updates the keepAlive controller (so the
  /// selection survives a pop back to the filters screen) and re-keys the
  /// results notifier by rebuilding with the amended filter set (fresh page 0).
  void _setSort(SearchSort sort) {
    if (sort == _filters.sort) return;
    ref.read(searchFiltersControllerProvider.notifier).setSort(sort);
    setState(() => _filters = _filters.copyWith(sort: sort));
  }

  void _showFavoriteError(Failure failure) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(failure.userMessage(context)),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<SearchResultsState> resultsAsync = ref.watch(
      searchResultsProvider(_filters),
    );
    // Refresh the cheap scroll-listener guards from the latest snapshot. When
    // there is no data yet (loading / error) nothing can be loaded more.
    final SearchResultsState? resultsData = resultsAsync.value;
    _hasMore = resultsData?.hasMore ?? false;
    _isLoadingMore = resultsData?.isLoadingMore ?? false;

    // Evaluate the active-filter count once and reuse it for both the badge and
    // the screen-reader label (the getter walks the filter facets each call).
    final int activeFilterCount = _filters.activeFilterCount;

    return Scaffold(
      key: const Key('client-search-results'),
      backgroundColor: BrandColors.base,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                VelvetSpacing.lg,
                VelvetSpacing.md,
                VelvetSpacing.lg,
                VelvetSpacing.sm,
              ),
              child: _ResultsTopBar(
                title: l10n.searchResultsTitle,
                backLabel: l10n.searchResultsBack,
                filterLabel: l10n.searchResultsOpenFilters,
                activeFilterCount: activeFilterCount,
                activeFiltersSemanticLabel: l10n.searchResultsActiveFilters(
                  activeFilterCount,
                ),
                activeSort: _filters.sort,
                onSort: _setSort,
                onBack: _openFilters,
                onFilter: _openFilters,
              ),
            ),
            Expanded(
              child: resultsAsync.when(
                loading: () => const ResultsSkeleton(),
                error: (Object e, _) => ResultsError(
                  error: e,
                  onRetry: () =>
                      ref.invalidate(searchResultsProvider(_filters)),
                ),
                data: (SearchResultsState data) {
                  if (data.items.isEmpty) {
                    return ResultsEmpty(
                      onEditFilters: _openFilters,
                      serviceFilterActive: _filters.serviceTypeSlugs.isNotEmpty,
                    );
                  }
                  return _ResultsList(
                    scrollController: _scrollController,
                    data: data,
                    onFavoriteError: _showFavoriteError,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Results list (cards + bottom load-more spinner).
// ---------------------------------------------------------------------------

class _ResultsList extends StatelessWidget {
  const _ResultsList({
    required this.scrollController,
    required this.data,
    required this.onFavoriteError,
  });

  final ScrollController scrollController;
  final SearchResultsState data;
  final void Function(Failure failure) onFavoriteError;

  @override
  Widget build(BuildContext context) {
    // +1 trailing slot for the load-more spinner when another page exists.
    final int extra = data.hasMore ? 1 : 0;
    return ListView.separated(
      key: const Key('results_list'),
      controller: scrollController,
      padding: kResultsListPadding,
      itemCount: data.items.length + extra,
      separatorBuilder: (_, _) => const SizedBox(height: VelvetSpacing.md),
      itemBuilder: (BuildContext context, int i) {
        if (i >= data.items.length) {
          return const _LoadMoreSpinner();
        }
        final SearchResultItem item = data.items[i];
        // Isolate each animated card subtree so a heart scale / image decode
        // never repaints its siblings while the list scrolls. Key by the item's
        // stable id so element/boundary identity survives list re-orders.
        return RepaintBoundary(
          key: ValueKey<String>(item.id),
          child: switch (item) {
            MasterResultItem(:final master) => MasterResultCard(
              master: master,
              onFavoriteError: onFavoriteError,
            ),
            SalonResultItem(:final salon) => SalonResultCard(
              salon: salon,
              onFavoriteError: onFavoriteError,
            ),
          },
        );
      },
    );
  }
}

class _LoadMoreSpinner extends StatelessWidget {
  const _LoadMoreSpinner();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      key: Key('results_load_more_spinner'),
      padding: EdgeInsets.symmetric(vertical: VelvetSpacing.md),
      child: Center(
        child: SizedBox(
          height: 26,
          width: 26,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: BrandColors.accent,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar — back · title · filter icon.
// ---------------------------------------------------------------------------

class _ResultsTopBar extends StatelessWidget {
  const _ResultsTopBar({
    required this.title,
    required this.backLabel,
    required this.filterLabel,
    required this.activeFilterCount,
    required this.activeFiltersSemanticLabel,
    required this.activeSort,
    required this.onSort,
    required this.onBack,
    required this.onFilter,
  });

  final String title;
  final String backLabel;
  final String filterLabel;

  /// Number of active filter facets — drives the «(N)» badge beside the filter
  /// icon. Hidden entirely when 0.
  final int activeFilterCount;

  /// Screen-reader label announcing the active-filter count (e.g. «2 активні
  /// фільтри»). Routed through l10n by the host.
  final String activeFiltersSemanticLabel;

  final SearchSort activeSort;
  final ValueChanged<SearchSort> onSort;
  final VoidCallback onBack;
  final VoidCallback onFilter;

  // Hoisted (perf #109/#114): the SVG tint is constant and the count style is
  // built once at class-load, so build() allocates neither a Color nor a
  // TextStyle per frame.
  static const Color _filterIconColor = BrandColors.textSecondary;
  static final TextStyle _countStyle = VelvetText.body().copyWith(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: BrandColors.accent,
  );

  @override
  Widget build(BuildContext context) {
    // Isolate the top bar's layer: it rebuilds with every searchResultsProvider
    // emission (incl. isLoadingMore toggles during pagination) although its
    // visual output is unchanged while paging, so a boundary keeps those frames
    // from repainting alongside the results list.
    return RepaintBoundary(
      child: Row(
        children: <Widget>[
          NeumorphicIconButton(
            key: const Key('results_back_button'),
            icon: Icons.arrow_back_ios_new_rounded,
            semanticLabel: backLabel,
            onTap: onBack,
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: VelvetText.subheading(),
            ),
          ),
          SortPillButton(activeSort: activeSort, onSelected: onSort),
          const SizedBox(width: VelvetSpacing.sm),
          // Filter button with the active-filter count as a bottom-right corner
          // badge. The SVG is wrapped in a Center so it renders at its intended
          // `size` — NeumorphicIconButton's 48px Container forces tight
          // constraints on a bare child, which would otherwise stretch the SVG
          // to fill the whole box.
          Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              NeumorphicIconButton(
                key: const Key('results_filter_button'),
                iconWidget: const Center(
                  child: AppIcon(
                    BeauticaAssetIcons.filter,
                    size: 20,
                    color: _filterIconColor,
                  ),
                ),
                semanticLabel: filterLabel,
                onTap: onFilter,
              ),
              if (activeFilterCount > 0)
                Positioned(
                  right: 3,
                  bottom: 1,
                  child: Semantics(
                    label: activeFiltersSemanticLabel,
                    child: Text(
                      // Parenthesised digit only — no translatable copy here.
                      '($activeFilterCount)',
                      key: const Key('results_active_filter_count'),
                      style: _countStyle,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
