// Phase 111 (old 13.10) — «Улюблені», the CLIENT shell's second tab (index 1).
//
// Ported from `docs/signup-designs/ClientFavorites/lib/screens/
// favorites_screen.dart`. A saved list of the masters and salons a client wants
// to come back to: two card kinds in one flat scroll, a category filter above
// it, pull-to-refresh, and an unlike that removes optimistically behind a
// 5-second undo.
//
// ── WHAT THE PREVIEW HAD THAT THIS DOES NOT ─────────────────────────────────
//
// The preview draws its own `_TopBar` — a back disc and a centred «Улюблені»
// title — and its own `ClientBottomNav`. Both are dropped here, and that is not
// a downgrade: in production BOTH are persistent chrome owned once by
// `ClientShell` (see its header on the wordmark-jump fix, and
// `scripts/forbid_client_branch_appbar.sh`, which hard-fails a branch root that
// grows its own bar). A branch root re-mounting either would re-lay-out the
// wordmark and make it jump on every tab hop. The screen's name reaches the
// client through the bottom-nav tile label instead.
//
// So this file is the branch BODY: filter, list, empty states. It carries the
// `client-branch-favorites` Key the placeholder it replaces exposed — every
// screen superseding a placeholder must, and
// `scripts/forbid_missing_client_branch_key.sh` enforces it.
//
// ── THE UNDO WINDOW LIVES HERE, NOT IN THE NOTIFIER ─────────────────────────
//
// Optimistic removal, staged so it never reads as a glitch:
//
//   1. the raised card is replaced IN ITS OWN SLOT by a recessed dent carrying
//      who was removed and a «Повернути» action — the list never jumps at the
//      moment of the tap, because the slot is held;
//   2. a camel hairline drains left→right over [_undoWindow] so the window is
//      visibly finite;
//   3. when it runs out the dent collapses (`AnimatedSize`, [_collapse]) and
//      ONLY THEN does the DELETE fire.
//
// The undo sits at the point of action rather than in a bottom snackbar, which
// on this screen would sit over the bottom nav. Which rows are denting, which
// are collapsing, and the timers driving both are presentation state and stay
// in this State object; `FavoritesNotifier.unfavorite` is called exactly once,
// at collapse. See `favorites_notifier.dart`'s header for why a `pending` set
// in the provider was rejected.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/staggered_reveal.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/loading_skeleton.dart';

import '../application/favorites_notifier.dart';
import '../domain/favorite_item.dart';
import 'widgets/favorite_cards.dart';
import 'widgets/favorites_empty_state.dart';
import 'widgets/favorites_filter.dart';

/// The one identity a row has on this screen: its KIND plus its id.
///
/// [FavoriteItem.id] is a `masterId` OR a `salonId` — two id spaces from two
/// different backend tables, merged into one flat list here. Every per-row
/// bookkeeping structure on this screen (the `ValueKey` reconciliation key, the
/// `findChildIndexCallback` index map, the pending/collapsing sets, the undo
/// timers) is a string map keyed on that id, so a master and a salon sharing a
/// UUID would collapse into ONE entry: the index map would return the wrong
/// row, and unliking the master would dent the salon. Nothing crashes — the
/// list just silently reuses the wrong row, which is the worst way for this to
/// fail. A cross-table UUID collision is vanishingly unlikely; qualifying the
/// key costs one interpolation and removes the failure mode entirely.
///
/// The per-row AnimatedSwitcher child keys inside `_buildRow`
/// (`favorites-dent-`, `favorites-master-`, `favorites-salon-`) deliberately
/// stay id-only: they are compared only against each other WITHIN a single
/// row's subtree, which this key already makes unique, so they have no cross-id
/// space to collide in.
String _favoriteRowId(FavoriteItem item) => '${item.kind.name}-${item.id}';

/// «Улюблені» — the CLIENT shell's branch-1 root.
class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  /// How long an unliked row stays undoable. The DELETE fires when it expires.
  static const Duration _undoWindow = Duration(seconds: 5);

  /// How long the dent takes to close once the window has run out.
  static const Duration _collapse = Duration(milliseconds: 280);

  /// Rows showing the undo dent, keyed by [_favoriteRowId] — kind + id, never
  /// the bare id (see that helper for the cross-table collision it closes).
  final Set<String> _pending = <String>{};

  /// Rows whose dent is animating shut.
  final Set<String> _collapsing = <String>{};

  /// One timer per denting row. Cancelled on undo and on dispose — a fired
  /// timer on a disposed State would call `ref` after teardown.
  final Map<String, Timer> _timers = <String, Timer>{};

  @override
  void dispose() {
    for (final Timer t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  /// Starts the undo window for [item]. Nothing is sent to the server yet.
  void _startUndoWindow(FavoriteItem item) {
    final String rowId = _favoriteRowId(item);
    setState(() => _pending.add(rowId));
    _timers[rowId]?.cancel();
    _timers[rowId] = Timer(_undoWindow, () {
      if (!mounted) return;
      setState(() => _collapsing.add(rowId));
      _timers[rowId] = Timer(_collapse, () {
        if (!mounted) return;
        _timers.remove(rowId);
        // The dent has finished closing — commit.
        unawaited(_commitUnfavorite(item));
      });
    });
  }

  /// Fires the DELETE and clears the row's presentation state.
  ///
  /// The pending/collapsing flags are cleared FIRST: the notifier drops the
  /// item from the list in the same turn, so leaving the id in `_pending` would
  /// have no row to attach to, and leaving it in `_collapsing` would strand a
  /// zero-height `AnimatedSize` in the builder if the removal were ever
  /// reverted.
  Future<void> _commitUnfavorite(FavoriteItem item) async {
    final String rowId = _favoriteRowId(item);
    setState(() {
      _pending.remove(rowId);
      _collapsing.remove(rowId);
    });
    final Failure? failure = await ref
        .read(favoritesProvider.notifier)
        .unfavorite(item);
    // `mounted` after the await, before touching context — otherwise a client
    // who hops tabs mid-DELETE gets a `ScaffoldMessenger` lookup on a
    // deactivated element.
    if (failure == null || !mounted) return;
    // The notifier has already put the row back at its original index; all
    // that is left is to say why it came back.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(failure.userMessage(context)),
        ),
      );
  }

  /// Cancels the window and restores the card in place. No network call was
  /// ever made, so there is nothing to undo server-side.
  void _undo(FavoriteItem item) {
    final String rowId = _favoriteRowId(item);
    _timers.remove(rowId)?.cancel();
    setState(() {
      _pending.remove(rowId);
      _collapsing.remove(rowId);
    });
  }

  Future<void> _refresh() async {
    // Cancel every in-flight undo window first. A refresh replaces the list
    // wholesale, so a timer still holding an id from the OLD list would fire a
    // DELETE for a row the client can no longer see — and `unfavorite` would
    // find no matching id and silently no-op, which looks like the unlike was
    // simply lost.
    for (final Timer t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    setState(() {
      _pending.clear();
      _collapsing.clear();
    });
    await ref.read(favoritesProvider.notifier).refresh();
  }

  void _openProfile(FavoriteItem item) {
    // RouteNames, never a hand-built '/masters/$id' — the backlog row against
    // `favorite_masters_card.dart:113` is exactly this defect, and a literal
    // path drifts silently the day a route is renamed.
    context.push(
      item.isMaster
          ? RouteNames.masterPublicProfile(item.id)
          : RouteNames.salonPublicProfile(item.id),
    );
  }

  void _openSearch() =>
      StatefulNavigationShell.of(context).goBranch(kClientSearchBranch);

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<FavoriteItem>> favorites = ref.watch(
      favoritesProvider,
    );
    final String? selectedCategory = ref.watch(favoritesCategoryFilterProvider);

    // The shell owns the top bar AND the single SafeArea(top), so this body
    // must not re-wrap either.
    return KeyedSubtree(
      key: const Key('client-branch-favorites'),
      child: StaggeredReveal(
        builder: (BuildContext context, RevealFn reveal) {
          // Explicit on all three AsyncValue states. `hasError` is never used
          // as the branch: `AsyncLoading(retrying: true)` satisfies it, so a
          // retry in flight would render as a permanent error.
          return switch (favorites) {
            AsyncData<List<FavoriteItem>>(:final List<FavoriteItem> value) =>
              _Loaded(
                items: value,
                selectedCategory: selectedCategory,
                pending: _pending,
                collapsing: _collapsing,
                reveal: reveal,
                undoWindow: _undoWindow,
                collapse: _collapse,
                onSelectCategory: (String? id) => ref
                    .read(favoritesCategoryFilterProvider.notifier)
                    .select(id),
                onOpen: _openProfile,
                onUnlike: _startUndoWindow,
                onUndo: _undo,
                onRefresh: _refresh,
                onFindMaster: _openSearch,
              ),
            AsyncError<List<FavoriteItem>>(:final Object error) => _ErrorBody(
              error: error,
              onRetry: () => unawaited(_refresh()),
            ),
            _ => const _LoadingBody(),
          };
        },
      ),
    );
  }
}

/// The loaded list — filter, rows, and whichever empty state applies.
class _Loaded extends StatelessWidget {
  const _Loaded({
    required this.items,
    required this.selectedCategory,
    required this.pending,
    required this.collapsing,
    required this.reveal,
    required this.undoWindow,
    required this.collapse,
    required this.onSelectCategory,
    required this.onOpen,
    required this.onUnlike,
    required this.onUndo,
    required this.onRefresh,
    required this.onFindMaster,
  });

  final List<FavoriteItem> items;
  final String? selectedCategory;

  /// Both sets hold [_favoriteRowId] values (kind + id), NOT bare item ids.
  final Set<String> pending;
  final Set<String> collapsing;
  final RevealFn reveal;
  final Duration undoWindow;
  final Duration collapse;
  final ValueChanged<String?> onSelectCategory;
  final void Function(FavoriteItem) onOpen;
  final void Function(FavoriteItem) onUnlike;
  final void Function(FavoriteItem) onUndo;
  final Future<void> Function() onRefresh;
  final VoidCallback onFindMaster;

  /// Prefix of every row's reconciliation key. See [_rowsSliver].
  static const String _rowKeyPrefix = 'favorites-row-';

  /// The list's entrance spreads across however many rows there are.
  ///
  /// `0.60 / (count - 1)`, CLAMPED — not a fixed step. A fixed step clamps out
  /// past ~13 rows: every row beyond that lands on the same interval and the
  /// tail of the list snaps in flat and simultaneous, which is exactly the
  /// stutter the stagger exists to avoid. Shrinking the step as the list grows
  /// keeps a 20-row list finishing in visual order. The lower bound (0.012)
  /// stops a very long list from collapsing to no perceptible cascade; the
  /// upper (0.05) keeps a 3-row list from crawling.
  ///
  /// Called ONCE per build, in [_rowsSliver] — never from the item builder,
  /// which would re-derive the same constant for every visible row on every
  /// scroll frame.
  static double _stepFor(int count) =>
      count > 1 ? (0.60 / (count - 1)).clamp(0.012, 0.05) : 0.05;

  /// Rounds a reveal bound to 2 decimal places.
  ///
  /// **This is load-bearing, not tidiness.** `StaggeredReveal` memoizes one
  /// `CurvedAnimation` per distinct `(start, end)` interval and each cached
  /// entry holds a status listener on the controller; the cache is
  /// `putIfAbsent`-only and this screen is a `StatefulShellRoute.indexedStack`
  /// branch, so it is never disposed for the whole session. [_stepFor] makes
  /// `start` a function of the list LENGTH, so without rounding every single
  /// unfavorite mints a fresh key: emptying a 40-row list one row at a time
  /// cached 486 `CurvedAnimation`s for 40 live rows. Every other `reveal(...)`
  /// caller in the app passes literal constants; this is the only computed one,
  /// which is why it is the only one that needs this.
  ///
  /// Quantizing bounds the key set to ~61 entries FOREVER, at a worst-case
  /// visual delta of 5 ms on a 1000 ms entrance — invisible. The matching debug
  /// budget assert lives in `staggered_reveal.dart` so the next computed caller
  /// trips immediately instead of leaking silently.
  static double _quantize(double v) => (v * 100).roundToDouble() / 100;

  @override
  Widget build(BuildContext context) {
    final List<FavoriteChoice> choices = FavoriteChoice.from(items);
    final List<FavoriteItem> visible = selectedCategory == null
        ? items
        : items
              .where((FavoriteItem i) => i.categoryId == selectedCategory)
              .toList(growable: false);

    // ONE scrollable, with the filter as its first sliver rather than a sibling
    // above an `Expanded`. In a Column the filter's 220 ms expand/collapse
    // re-constrains the list below it on every frame of the animation — a full
    // relayout of every visible row plus a re-raster of their shadows, for the
    // whole 220 ms, to open a control that never asked the rows to move. As a
    // header sliver its height change scrolls the rows instead of re-measuring
    // them. (Unreachable today: no favourites DTO carries a category, so
    // `choices` is empty and the filter renders `SizedBox.shrink()`. It stops
    // being unreachable the day categories ship, and this is cheaper to get
    // right now than to diagnose as jank later.)
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: BrandColors.accentDeep,
      backgroundColor: BrandColors.base,
      displacement: 28,
      child: CustomScrollView(
        // AlwaysScrollable so pull-to-refresh still works on a screen with
        // nothing to scroll — otherwise a client whose list is empty because a
        // request half-failed has no way to retry.
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          SliverToBoxAdapter(child: _header(choices)),
          if (visible.isEmpty)
            SliverToBoxAdapter(child: _emptyState(choices))
          else
            _rowsSliver(visible),
        ],
      ),
    );
  }

  /// A single deliberate step under the shell's top bar, then the filter.
  ///
  /// Both gaps collapse to nothing when the filter hides itself, so an
  /// unfiltered list does not carry the gap of a control that is not there.
  Widget _header(List<FavoriteChoice> choices) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (choices.isNotEmpty) const SizedBox(height: VelvetSpacing.md),
        reveal(
          start: 0.08,
          end: 0.38,
          child: FavoritesInlineFilter(
            choices: choices,
            selectedId: selectedCategory,
            onSelect: onSelectCategory,
          ),
        ),
        if (choices.isNotEmpty) const SizedBox(height: VelvetSpacing.sm + 2),
      ],
    );
  }

  Widget _emptyState(List<FavoriteChoice> choices) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const SizedBox(height: VelvetSpacing.md),
        if (selectedCategory == null)
          FavoritesEmptyState(onFindMaster: onFindMaster)
        else
          FavoritesCategoryEmptyState(
            categoryLabel:
                choices
                    .where((FavoriteChoice c) => c.id == selectedCategory)
                    .map((FavoriteChoice c) => c.label)
                    .firstOrNull ??
                '',
            onClearFilter: () => onSelectCategory(null),
          ),
      ],
    );
  }

  /// The rows.
  ///
  /// ── EVERY ROW CARRIES ITS OWN KEY ──────────────────────────────────────
  ///
  /// `SliverChildBuilderDelegate` reconciles by INDEX unless the built child
  /// has a key. Unkeyed, removing row 3 hands slot 3's existing element — and
  /// its existing `RenderAnimatedSize`, sitting at the old row's height — the
  /// NEXT row's content, and that render object dutifully animates from the
  /// height it had to the height it now needs. Measured: after a removal slot 0
  /// read 40.07 against a 60.0 target and took 280 ms to arrive. Every visible
  /// row below the removal did it at once, and it fired again on `refresh()`
  /// whenever the length changed and on the failure-restore path in
  /// `favorites_notifier.dart`. It is also simply not a designed behaviour: the
  /// design asks the DENT to collapse, not the rows beneath it to morph.
  ///
  /// A `ValueKey` per item id makes reconciliation follow the item, so a
  /// surviving row keeps the element it already had, at the height it already
  /// had, and does not animate at all. [findChildIndexCallback] is what lets a
  /// keyed child that MOVED (rather than being rebuilt) be found at its new
  /// index without tearing down its element — without it, keyed children in a
  /// lazy sliver still get rebuilt on every reorder.
  Widget _rowsSliver(List<FavoriteItem> visible) {
    final double step = _stepFor(visible.length);
    // Built once per build so the index lookup below is O(1); the callback is
    // invoked once per keyed child on every list mutation.
    final Map<String, int> indexByRowId = <String, int>{
      for (int i = 0; i < visible.length; i++) _favoriteRowId(visible[i]): i,
    };

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.sm,
        VelvetSpacing.lg,
        // Clears the shell's bottom nav so the last card is never half-hidden
        // behind it.
        VelvetSizes.bottomNavClearanceClient,
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (BuildContext context, int index) {
            final FavoriteItem item = visible[index];
            final double start = _quantize(
              (0.20 + index * step).clamp(0.0, 0.80),
            );
            return KeyedSubtree(
              key: ValueKey<String>('$_rowKeyPrefix${_favoriteRowId(item)}'),
              child: reveal(
                start: start,
                end: _quantize((start + 0.20).clamp(0.0, 1.0)),
                child: _buildRow(item),
              ),
            );
          },
          childCount: visible.length,
          findChildIndexCallback: (Key key) {
            // The delegate un-salts the key before handing it over, so this sees
            // exactly the ValueKey built above. Anything else is not ours.
            if (key is! ValueKey<String>) return null;
            final String raw = key.value;
            if (!raw.startsWith(_rowKeyPrefix)) return null;
            return indexByRowId[raw.substring(_rowKeyPrefix.length)];
          },
        ),
      ),
    );
  }

  /// One slot in the list. The slot never disappears the instant you unlike —
  /// the raised card is replaced in place by its dent, and only the dent
  /// collapses.
  ///
  /// ── THE `AnimatedSize` STAYS UNCONDITIONAL. MEASURED. ──────────────────
  ///
  /// A perf audit prescribed wrapping this in `AnimatedSize` only while the
  /// row is in `pending`/`collapsing`, on the reading that the wrapper was what
  /// morphed every row below a removal. It is not, and the narrower wrap was
  /// tried and reverted on evidence:
  ///
  ///   * with index-keyed rows and the unconditional wrap → the row below a
  ///     removal starts at the REMOVED row's height and crawls to its own
  ///     (measured 115 → 106 and 106 → 115 across five visible rows, 280 ms);
  ///   * with per-id keys and the unconditional wrap → every surviving row is
  ///     already at its settled height on the very next frame. No morph.
  ///
  /// So the KEY on [_rowsSliver] is the entire fix; the wrapper was never the
  /// cause. Making it conditional fixes nothing and costs a designed
  /// behaviour: the AnimatedSize element would then be CREATED at the moment
  /// the row goes pending, so it starts life already at the dent's height and
  /// the card→dent change snaps. Measured 115 → 88 in one frame — a 27dp jump
  /// of everything below it, at the exact instant this screen's header
  /// promises "the list never jumps at the moment of the tap". Unconditional,
  /// the same element carries the row from 115 to 88 over [collapse].
  ///
  /// What remains at rest is one `RenderAnimatedSize` per VISIBLE row that
  /// never animates, because its child's size never changes. That is the price
  /// of the tap morph, and it is the smaller of the two.
  Widget _buildRow(FavoriteItem item) {
    // Same composite key the sets are populated with in `_FavoritesScreenState`
    // — reading them with a bare `item.id` here would never match.
    final String rowId = _favoriteRowId(item);
    if (collapsing.contains(rowId)) {
      return AnimatedSize(
        duration: collapse,
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: const SizedBox(width: double.infinity),
      );
    }

    final Widget content = pending.contains(rowId)
        ? RemovedDent(
            key: ValueKey<String>('favorites-dent-${item.id}'),
            name: item.name,
            window: undoWindow,
            onUndo: () => onUndo(item),
          )
        : item.isMaster
        ? FavoriteMasterCard(
            key: ValueKey<String>('favorites-master-${item.id}'),
            item: item,
            onOpen: () => onOpen(item),
            onUnlike: () => onUnlike(item),
          )
        : FavoriteSalonCard(
            key: ValueKey<String>('favorites-salon-${item.id}'),
            item: item,
            onOpen: () => onOpen(item),
            onUnlike: () => onUnlike(item),
          );

    return AnimatedSize(
      duration: collapse,
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: Padding(
        // A touch more air than a sectioned layout would need: with no rules
        // breaking the scroll, the gap itself is what keeps a 12+ row list from
        // reading as a wall.
        padding: const EdgeInsets.only(bottom: VelvetSpacing.md + 2),
        child: content,
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  /// Enough rows to fill a phone viewport — a skeleton shorter than the fold
  /// reads as a short list that has already finished loading.
  static const int _rows = 5;

  @override
  Widget build(BuildContext context) {
    return const Padding(
      key: Key('favorites-loading'),
      padding: EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.lg,
        VelvetSpacing.lg,
        VelvetSizes.bottomNavClearanceClient,
      ),
      // The shared shimmer, not a favourites-shaped one: a placeholder that
      // mimics this card's exact silhouette would promise a layout the data
      // may not fill (a salon row and a two-line-note master row differ by
      // ~50dp), and every other list in the app waits with this.
      child: LoadingSkeleton.list(rows: _rows),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(VelvetSpacing.lg),
        child: ErrorState(
          key: const Key('favorites-error'),
          // The repository maps every DioException to a typed Failure, so the
          // fallback is for a genuinely unexpected throw — house pattern, see
          // `error_state.dart`'s own doc.
          failure: error is Failure
              ? error as Failure
              : UnknownFailure(cause: error),
          onRetry: onRetry,
        ),
      ),
    );
  }
}
