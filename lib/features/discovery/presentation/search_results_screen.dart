// Phase 13.4 — CLIENT discovery results screen («Результати»).
//
// Ports the approved preview `docs/signup-designs/SearchBooking/lib/screens/
// search_results_screen.dart` into the real Riverpod + go_router structure:
//   • top bar — back affordance · centred «Результати» title · filter icon
//     (SVG funnel) that re-opens the 13.3 filter controls (pops back to the
//     still-populated filters screen), with a «(N)» active-filter-count badge
//     beside it when one or more facets are applied;
//   • a LIVE search field ([SearchQueryField], the very same pill control the
//     filters screen hosts) directly under the top bar, plus an applied-query
//     chip beneath it;
//   • a scrolling list of master + salon result cards, infinite-scroll via a
//     ScrollController calling loadMore() near the end + a bottom spinner;
//   • the four AsyncValue states (skeleton / cards / empty / error).
//
// The screen owns the live [SearchFilters] in local state (seeded from the
// `extra:` forwarded by 13.3). The filter set re-keys the family-scoped
// [searchResultsProvider] — a fresh page-0 fetch. The active-filter count is
// derived directly from [SearchFilters.activeFilterCount].
//
// LIVE SEARCH (defect G). Typing used to change nothing until «Показати
// майстрів» was tapped again, and the results screen showed neither the query
// nor a field to change it. It now re-runs the search as the user types, behind
// a hard 500 ms DEBOUNCE: `query` participates in freezed's `==`/`hashCode` and
// therefore in the [searchResultsProvider] family key, so an undebounced write
// would fire one full page-0 request per keystroke. Below-minimum terms (1–2
// characters) are additionally suppressed at the controller — see
// [kSearchMinQueryLength] — so they never reach the wire at all. Whatever DOES
// settle and is then superseded has its two GETs cancelled by the notifier's
// CancelToken (perf/sec MEDIUM-1).
//
// RE-KEYING KEEPS THE PREVIOUS PAGE ON SCREEN (perf LOW-2). A settled query
// points [searchResultsProvider] at a virgin family member with no cached value,
// so `.when(loading:)` fires and would otherwise unmount the whole rendered
// list — skeleton flash, 20 neumorphic cards re-inflated on one frame, scroll
// offset silently reset to 0 because the `Expanded` child swapped widget type.
// The outgoing page is therefore captured into [_retained] at the moment of the
// re-key and rendered behind a thin progress bar until the new page resolves.
// Both the retained and the fresh branch return the SAME widget shape
// (`_ResultsView`), which is what actually preserves the ListView's element and
// its scroll position.
//
// The field shows what is being TYPED; the chip shows what is currently
// APPLIED. They diverge exactly while a term is too short to search, which is
// precisely when the field's min-length helper is explaining why.
//
// go_router only — the back/filter affordances use context.pop(); cards push the
// public-profile routes. No Navigator anywhere.

import 'dart:async';

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
import 'widgets/search_query_field.dart';
import 'widgets/service_chip_drawer.dart';
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

  /// Quiet window after the last keystroke before the query is applied.
  ///
  /// MANDATORY, not a nicety: applying per-keystroke would re-key
  /// [searchResultsProvider] (query is part of [SearchFilters]'s `==`/`hashCode`)
  /// and issue a page-0 request for every character typed.
  ///
  /// 500 ms, not 400 (perf MEDIUM-1): each settled term costs a TWO-endpoint
  /// fan-out of wildcard-LIKE scans, and 400 ms does not cover a normal
  /// inter-word pause — it fired a full search mid-phrase.
  static const Duration _queryDebounce = Duration(milliseconds: 500);

  late SearchFilters _filters;
  final ScrollController _scrollController = ScrollController();

  /// Raw text of the live search field — the term being TYPED, which may be
  /// shorter than [kSearchMinQueryLength] and therefore not yet applied.
  final TextEditingController _queryController = TextEditingController();

  /// Pending debounced apply; cancelled on every new keystroke and on dispose.
  Timer? _queryDebounceTimer;

  /// The page rendered by the OUTGOING filter set, kept on screen while the new
  /// family member resolves (perf LOW-2), paired with the filters that produced
  /// it so the retained cards still carry the right booking-flow preselection.
  ///
  /// Captured in [_applyFilters] — i.e. in an event handler, never in `build()`
  /// — by reading the provider that is about to be re-keyed away. Null before
  /// the first successful search, and deliberately ignored when it holds an
  /// empty page (there is nothing worth retaining).
  ({SearchFilters filters, SearchResultsState data})? _retained;

  @override
  void initState() {
    super.initState();
    _filters = widget.initialFilters ?? const SearchFilters();
    // Seed the live field from the query the search was launched with, so the
    // user can refine it rather than retype it.
    _queryController.text = _filters.query ?? '';
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _queryDebounceTimer?.cancel();
    _queryController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Cheapest test first: geometry, straight off the controller. Only once the
    // threshold is crossed do we touch Riverpod at all.
    if (!_scrollController.hasClients) return;
    final ScrollPosition pos = _scrollController.position;
    if (pos.pixels < pos.maxScrollExtent - _loadMoreThreshold) return;

    // Derived HERE rather than cached from `build()` (perf LOW-3): a `build()`
    // that writes State fields turns into a rebuild loop the moment anyone adds
    // a `setState` beside it. `ref.read` on an already-watched provider is a
    // map lookup — no new subscription, no re-resolve of the family.
    final SearchResultsState? data = ref
        .read(searchResultsProvider(_filters))
        .value;
    if (data == null || !data.hasMore || data.isLoadingMore) return;

    // The notifier itself guards against double-fetch + last-page no-op.
    ref.read(searchResultsProvider(_filters).notifier).loadMore();
  }

  /// Keystroke handler for the live search field. Restarts the debounce window;
  /// nothing is applied (and no request is issued) until it elapses.
  void _onQueryChanged(String raw) {
    _queryDebounceTimer?.cancel();
    _queryDebounceTimer = Timer(_queryDebounce, () => _applyQuery(raw));
  }

  /// Commits a settled query — the ONLY path that re-keys the results provider
  /// from the search field.
  ///
  /// Normalisation is delegated wholesale to [SearchFiltersController.setQuery]
  /// (trim → blank clears, 1–2 characters are HELD, 3+ applies), so the
  /// below-minimum rule lives in exactly one place. Whatever it settles on is
  /// then read back and compared: an unchanged applied query means the keystroke
  /// was a hold or a no-op, and no `setState` — hence no re-key, hence no
  /// request — happens.
  ///
  /// Writing through the keepAlive controller also keeps the filters screen in
  /// sync, so popping back shows the query that is actually applied.
  void _applyQuery(String raw) {
    if (!mounted) return;
    ref.read(searchFiltersControllerProvider.notifier).setQuery(raw);
    final String? applied = ref.read(searchFiltersControllerProvider).query;
    if (applied == _filters.query) return;
    _applyFilters(_filters.copyWith(query: applied));
  }

  /// The single re-key path: swaps [_filters] (and therefore the
  /// [searchResultsProvider] family member) after snapshotting the page that is
  /// about to be discarded.
  ///
  /// The snapshot is what lets the new, cache-less family member render the
  /// PREVIOUS results behind a progress bar instead of a full-screen skeleton
  /// (perf LOW-2). Taking it here — in the handler, from the still-live provider
  /// — keeps `build()` free of side effects; the outgoing member is autoDisposed
  /// immediately afterwards and its in-flight requests cancelled.
  void _applyFilters(SearchFilters next) {
    if (next == _filters) return;
    final SearchResultsState? outgoing = ref
        .read(searchResultsProvider(_filters))
        .value;
    // `?? _retained` — NOT a reload-detection gate (that is `ref.watch`'s job),
    // just a placeholder fallback: refining twice inside one round trip leaves
    // the outgoing member itself value-less, and dropping to a skeleton there
    // would defeat the whole point. Keep the last page we actually rendered.
    if (outgoing != null) {
      _retained = (filters: _filters, data: outgoing);
    }
    setState(() => _filters = next);
  }

  /// Clears the applied query from the chip — empties the field and applies
  /// immediately (no point debouncing an explicit, single-shot action).
  void _clearQuery() {
    _queryDebounceTimer?.cancel();
    _queryController.clear();
    _applyQuery('');
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
    _applyFilters(_filters.copyWith(sort: sort));
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

    // Evaluate the active-filter count once and reuse it for both the badge and
    // the screen-reader label (the getter walks the filter facets each call).
    final int activeFilterCount = _filters.activeFilterCount;

    // The query is deliberately NOT part of `activeFilterCount` — it has its own
    // always-visible representation right below the badge (see the getter's
    // doc comment).
    final String? appliedQuery = _filters.query;

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
            // Live search — the same pill field the filters screen hosts, so
            // typing has somewhere to happen without a round trip through the
            // previous screen. Below it, the APPLIED query echoed as a chip
            // (tap to clear), reusing the selected-[ServiceChip] treatment
            // verbatim so an active query reads exactly like any other active
            // selection in this feature.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                VelvetSpacing.lg,
                0,
                VelvetSpacing.lg,
                VelvetSpacing.sm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SearchQueryField(
                    fieldKey: const Key('results_query_field'),
                    controller: _queryController,
                    hintText: l10n.searchFieldHint,
                    minLengthHint: l10n.searchQueryMinLengthHint,
                    onChanged: _onQueryChanged,
                  ),
                  if (appliedQuery != null) ...<Widget>[
                    const SizedBox(height: VelvetSpacing.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ServiceChip(
                        key: const Key('results_query_chip'),
                        label: appliedQuery,
                        selected: true,
                        onTap: _clearQuery,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              // All four states stay explicit. The only change from a plain
              // `.when` is that `loading:` prefers the retained page over the
              // skeleton when one exists, and routes it through the SAME
              // `_ResultsView` the data branch uses — identical widget shape, so
              // the ListView element (and its scroll offset) survives the
              // re-key. See the file header, perf LOW-2.
              child: resultsAsync.when(
                loading: () {
                  final retained = _retained;
                  if (retained == null || retained.data.items.isEmpty) {
                    return const ResultsSkeleton();
                  }
                  return _ResultsView(
                    scrollController: _scrollController,
                    data: retained.data,
                    // The filters the retained cards were fetched WITH, not the
                    // pending ones — a card tapped mid-transition must still
                    // preselect the services its own search matched.
                    activeFilters: retained.filters,
                    onFavoriteError: _showFavoriteError,
                    refreshing: true,
                  );
                },
                error: (Object e, _) => ResultsError(
                  error: e,
                  onRetry: () =>
                      ref.invalidate(searchResultsProvider(_filters)),
                ),
                data: (SearchResultsState data) {
                  if (data.items.isEmpty) {
                    return ResultsEmpty(onEditFilters: _openFilters);
                  }
                  return _ResultsView(
                    scrollController: _scrollController,
                    data: data,
                    activeFilters: _filters,
                    onFavoriteError: _showFavoriteError,
                    refreshing: false,
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
// Results view — the list plus the re-key progress affordance.
// ---------------------------------------------------------------------------

/// Wraps [_ResultsList] in the shape BOTH the `data:` and the retained
/// `loading:` branch return (perf LOW-2).
///
/// The list is always Stack child 0, so toggling [refreshing] adds/removes only
/// the trailing overlay — `Widget.canUpdate` still matches the list positionally
/// and its element, `ScrollPosition` and inflated cards all survive. Returning a
/// different widget type per branch is exactly what used to unmount 20
/// neumorphic cards and reset the scroll offset to 0 on every refined query.
class _ResultsView extends StatelessWidget {
  const _ResultsView({
    required this.scrollController,
    required this.data,
    required this.activeFilters,
    required this.onFavoriteError,
    required this.refreshing,
  });

  final ScrollController scrollController;
  final SearchResultsState data;
  final SearchFilters activeFilters;
  final void Function(Failure failure) onFavoriteError;

  /// Whether [data] is the OUTGOING page, held on screen while a re-keyed
  /// search resolves. Drives the top progress bar.
  final bool refreshing;

  /// Height of the re-key progress bar — deliberately hairline so the retained
  /// results stay fully readable underneath it.
  static const double _progressBarHeight = 3;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        _ResultsList(
          scrollController: scrollController,
          data: data,
          activeFilters: activeFilters,
          onFavoriteError: onFavoriteError,
        ),
        if (refreshing)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              key: const Key('results_refreshing_bar'),
              minHeight: _progressBarHeight,
              backgroundColor: Colors.transparent,
              color: BrandColors.accent,
              semanticsLabel: AppLocalizations.of(context).loadingLabel,
            ),
          ),
      ],
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
    required this.activeFilters,
    required this.onFavoriteError,
  });

  final ScrollController scrollController;
  final SearchResultsState data;

  /// The filter set the results were fetched with — forwarded to each card so a
  /// service filter can pre-check the matching service(s) in the booking flow.
  final SearchFilters activeFilters;
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
              activeFilters: activeFilters,
              onFavoriteError: onFavoriteError,
            ),
            SalonResultItem(:final salon) => SalonResultCard(
              salon: salon,
              activeFilters: activeFilters,
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
  static final TextStyle _countStyle = VelvetText.discResultCount;

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
