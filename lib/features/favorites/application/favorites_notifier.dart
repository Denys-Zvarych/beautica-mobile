// Phase 111 (old 13.10) — the «Улюблені» list + its category filter.
//
// Two providers, deliberately separate:
//
//   * [Favorites]              — the async list (both endpoints, merged).
//   * [FavoritesCategoryFilter] — the selected category, plain sync state.
//
// Splitting them is what keeps a filter tap from touching the network. If the
// selection lived inside the async notifier, every chip tap would rebuild an
// `AsyncValue<List<FavoriteItem>>` and the list widget would have to re-derive
// its whole visible set from a new object identity; as two providers, the chips
// watch a `String?` and the rows watch a list, and neither invalidates the
// other.
//
// ── WHY THE UNDO WINDOW IS NOT IN THIS FILE ─────────────────────────────────
//
// The approved design replaces an unliked row, IN ITS OWN SLOT, with a recessed
// "dent" carrying a «Повернути» action and a 5-second draining hairline; the
// DELETE fires only when that window closes. That choreography — which rows are
// showing a dent, which are collapsing, and the timers driving both — is
// presentation state and lives in `FavoritesScreen`. This notifier exposes only
// the settled transition: [unfavorite] is called ONCE, at the moment the dent
// collapses, and from then on the row is gone from the model too.
//
// The alternative (a `pending` set in the notifier) was rejected: it would make
// the provider's value disagree with the endpoint for 5 seconds, so any other
// surface reading it would show a row as removed that is still favourited
// server-side and may yet be restored.
//
// ── RIVERPOD TRAPS CHECKED, NOT ASSUMED ─────────────────────────────────────
//
// 1. **No `ref.invalidate(self)` for reload.** [refresh] re-runs the fetch and
//    assigns the result directly. `ref.invalidate` on an autoDispose provider
//    whose only listeners are COVERED — and this screen is one of five branches
//    inside the client shell's `IndexedStack`, so it is covered whenever
//    another tab is showing — DISPOSES it instead of reloading it, deferring
//    the refetch to resume. A pull-to-refresh gesture must complete while the
//    user is looking at the list, so it cannot go through invalidate. (Same
//    trap `favorite_toggle_notifier.dart` documents against `wishlistProvider`,
//    and the reason `wishlist_notifier.removeService` mutates in place.)
//
// 2. **Reload detection never gates on `value == null`.** `ref.invalidate`
//    retains the previous `.value`, so a null check is not a reload signal.
//    Nothing here reads `.value` to decide anything; the screen renders off
//    `.when(...)` and its own pending set.
//
// 3. **`hasError` is not used as a branch.** `AsyncLoading(retrying: true)`
//    satisfies `hasError`, so a retry-in-flight would render as an error
//    screen. The screen pattern-matches the AsyncValue instead.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/errors/failures.dart';

import '../data/favorite_repository_provider.dart';
import '../domain/favorite_item.dart';
import 'favorite_toggle_notifier.dart';

part 'favorites_notifier.g.dart';

/// The signed-in client's saved masters + salons, as one flat list.
@riverpod
class Favorites extends _$Favorites {
  static const String _tag = 'feature.favorites';

  @override
  Future<List<FavoriteItem>> build() => _load();

  /// Fetches both endpoints CONCURRENTLY and merges them.
  ///
  /// `Future.wait`, not two sequential awaits: the calls are independent and
  /// serialising them would put a second full round trip in front of first
  /// paint on the client's second tab. `Future.wait` propagates the first
  /// error, which is the behaviour we want — a half-loaded favourites list
  /// (masters shown, salons silently missing) would be indistinguishable from
  /// a client who has simply saved no salons.
  ///
  /// **Merge order.** Masters first, then salons, each in the server's own
  /// newest-saved-first order. Neither DTO carries the `favorites.created_at`
  /// the backend sorts by, so a truthful cross-kind interleave is not
  /// derivable client-side; inventing one (alphabetical, kind-alternating)
  /// would assert an ordering the data does not support. This is the one place
  /// the port knowingly differs from the preview's interleaved sample list.
  Future<List<FavoriteItem>> _load() async {
    final repository = ref.watch(favoriteRepositoryProvider);
    final results = await Future.wait(<Future<List<FavoriteItem>>>[
      repository.getFavoriteMasters(),
      repository.getFavoriteSalons(),
    ]);
    return <FavoriteItem>[...results[0], ...results[1]];
  }

  /// Removes [item] from the list and from the server.
  ///
  /// Optimistic: the row leaves the model immediately, then `DELETE /favorites`
  /// fires. On failure the row is put back AT ITS ORIGINAL INDEX (not appended)
  /// so a failed unlike leaves the list exactly as the client last saw it, and
  /// the [Failure] is returned so the screen can surface a snack.
  ///
  /// Delegates the wire call to [FavoriteToggleNotifier.toggle] rather than
  /// calling `FavoriteRepository.remove` directly — that notifier is the single
  /// owner of every favourite flag in the session, so bypassing it would leave
  /// a stale filled heart on the search-results card and the public profile for
  /// the same provider. [FavoriteToggleNotifier.primeIfAbsent] seeds the flag
  /// to `true` first: every row on THIS screen is a favourite by definition,
  /// but the toggle map only knows the targets the user has touched, and an
  /// unseeded target reads `false` — so an unprimed toggle would ADD the
  /// favourite the client just asked to remove.
  ///
  /// Returns null on success.
  Future<Failure?> unfavorite(FavoriteItem item) async {
    final List<FavoriteItem> current = state.value ?? const <FavoriteItem>[];
    // Matched on kind AND id: `id` is a masterId or a salonId — two id spaces
    // from two tables merged into one list — so an id-only match could remove
    // the salon row that happens to share a UUID with the unliked master.
    final int index = current.indexWhere(
      (FavoriteItem i) => i.id == item.id && i.kind == item.kind,
    );
    if (index < 0) {
      // Already gone (a double-fire from two collapsing dents, or a refresh
      // that landed first). The DELETE is idempotent, but re-issuing it here
      // would be a round trip with nothing to show for it.
      return null;
    }

    final List<FavoriteItem> without = <FavoriteItem>[...current]
      ..removeAt(index);
    state = AsyncData<List<FavoriteItem>>(without);

    final notifier = ref.read(favoriteToggleProvider.notifier);
    notifier.primeIfAbsent(item.target, isFavorite: true);
    final Failure? failure = await notifier.toggle(item.target);

    if (failure != null) {
      if (kDebugMode) {
        log(
          'unfavorite ${item.kind.name} failed — restoring row at $index',
          name: _tag,
          level: 900,
        );
      }
      // Restore against the CURRENT list, not the captured one: a refresh may
      // have landed while the DELETE was in flight, and clobbering it with a
      // stale snapshot would resurrect rows the server has already dropped.
      final List<FavoriteItem> latest = state.value ?? const <FavoriteItem>[];
      final int at = index.clamp(0, latest.length);
      state = AsyncData<List<FavoriteItem>>(
        <FavoriteItem>[...latest]..insert(at, item),
      );
    }
    return failure;
  }

  /// The refresh currently in flight, or null. See [refresh].
  Future<void>? _refreshing;

  /// Re-fetches both endpoints — the pull-to-refresh handler.
  ///
  /// Assigns the result directly instead of invalidating (see trap 1 in the
  /// file header). `AsyncValue.guard` so a failed refresh surfaces as an error
  /// state rather than an unhandled exception inside `RefreshIndicator`.
  ///
  /// The state is NOT set to `AsyncLoading` first: `RefreshIndicator` is
  /// already drawing the spinner, and blanking the list to a skeleton
  /// underneath it makes the rows flash away and back on every pull.
  ///
  /// **Single-flight.** A second call while one is outstanding returns the
  /// SAME future instead of starting another fetch. `RefreshIndicator` already
  /// swallows a second *pull*, so this looked covered — but the error screen's
  /// retry button routes here directly and is tappable as fast as a finger
  /// moves. Two concurrent `_load()`s are two independent `Future.wait` pairs
  /// over four requests that can resolve in any order, and whichever finishes
  /// LAST wins the `state =` assignment: the client can end up looking at the
  /// older of two responses, with no signal that it happened. De-duplicating
  /// at the notifier is the only place that can see both calls.
  ///
  /// The guard is cleared in a `finally` so a throwing `_load` cannot wedge
  /// the screen into a permanently-refreshing state — though `AsyncValue.guard`
  /// means the failure is captured into `state`, not rethrown, so awaiting a
  /// shared future is safe for every caller.
  Future<void> refresh() {
    final Future<void>? inFlight = _refreshing;
    if (inFlight != null) return inFlight;
    final Future<void> started = _run();
    _refreshing = started;
    return started;
  }

  /// The body of [refresh]. Safe to assign `_refreshing` only AFTER calling
  /// this: an `async` body runs synchronously to its first `await`, and the
  /// first statement here awaits — so the `finally` below cannot possibly
  /// null the field before [refresh] has set it.
  Future<void> _run() async {
    try {
      state = await AsyncValue.guard(_load);
    } finally {
      _refreshing = null;
    }
  }
}

/// The category the «Улюблені» list is filtered to, or null for «Всі».
///
/// Kept OUT of [Favorites] so a chip tap never rebuilds the async list — see
/// the file header. Not `keepAlive`: the filter is a within-visit affordance,
/// and a selection surviving a logout would be one user's state shown to the
/// next.
@riverpod
class FavoritesCategoryFilter extends _$FavoritesCategoryFilter {
  @override
  String? build() => null;

  /// Selects [categoryId], or clears the filter when it is null («Всі»).
  void select(String? categoryId) => state = categoryId;
}
