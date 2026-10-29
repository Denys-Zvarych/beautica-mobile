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
import '../domain/favorite_target.dart';
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

    // An unfavorite must NEVER become an add. When the toggle map already
    // holds `isFavorite == false` for this target (it was unliked elsewhere —
    // a profile or search heart — and this row outlived that, e.g. because
    // the narrowed refresh failed), `toggle` would flip it to `true` and POST
    // an add. The server already has no favourite: drop the row locally only.
    final FavoriteEntry? known = ref.read(favoriteToggleProvider)[item.target];
    if (known != null && !known.isFavorite) return null;

    final notifier = ref.read(favoriteToggleProvider.notifier);
    notifier.primeIfAbsent(item.target, isFavorite: true);
    // `refreshFavorites: false` — this list already dropped the row above; a
    // refetch racing that optimistic edit would discard the restore below.
    final Failure? failure = await notifier.toggle(
      item.target,
      refreshFavorites: false,
    );

    // Disposed while the DELETE was in flight (logout): nothing to restore,
    // and `state =` on a disposed notifier throws.
    if (!ref.mounted) return failure;
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

  /// Whether a [refresh] arrived while [_refreshing] was outstanding — the
  /// trailing re-run is queued. At most ONE re-run is ever queued, however
  /// many calls land during the window.
  bool _rerunQueued = false;

  /// Scope of the queued re-run: one kind, or null for both endpoints. Two
  /// queued calls with different scopes widen it to null.
  FavoriteTargetType? _rerunOnly;

  /// Whether the queued re-run is a BACKGROUND one (keeps the rows on
  /// failure). ANDed across queued calls: one user-facing caller makes the
  /// re-run user-facing, so its error is shown.
  bool _rerunKeep = false;

  /// Set when a NARROWED refresh failed and its error was swallowed (the list
  /// kept its rows — see [_run]): the rows on screen may be out of date. The
  /// next narrowed [refresh] widens to a full reload, and `FavoritesScreen`
  /// runs one when the «Улюблені» tab becomes visible again. Cleared
  /// by any successful full reload. A fresh mount starts clean anyway
  /// (`autoDispose` builds a new notifier and loads both endpoints).
  bool _stale = false;

  /// Whether a swallowed narrowed-refresh failure left the list out of date.
  /// `FavoritesScreen` reads it whenever «Улюблені» is shown again and runs a
  /// full [refresh] if so — a plain tab switch never costs a round trip.
  bool get isStale => _stale;

  /// Re-fetches the list — the pull-to-refresh handler, and the post-toggle
  /// refresh from `FavoriteToggleNotifier.toggle`.
  ///
  /// [only] (ADDITIVE) narrows the reload to ONE kind (`master` / `salon`):
  /// that endpoint is refetched and merged into the current list, the other
  /// kind's rows are kept as they are. A toggled master must not refetch every
  /// salon. Null (the default) reloads both, exactly as before. A narrowed
  /// call against a list with no data yet (loading / error) falls back to a
  /// full load — there is nothing to merge into.
  ///
  /// Assigns the result directly instead of invalidating (see trap 1 in the
  /// file header). `AsyncValue.guard` so a failed refresh surfaces as an error
  /// state rather than an unhandled exception inside `RefreshIndicator`.
  ///
  /// The state is NOT set to `AsyncLoading` first: `RefreshIndicator` is
  /// already drawing the spinner, and blanking the list to a skeleton
  /// underneath it makes the rows flash away and back on every pull.
  ///
  /// **Single-flight with a trailing re-run.** A call while one is
  /// outstanding never starts a second concurrent fetch (two concurrent loads
  /// resolve in any order and the LAST one wins `state =`, which can be the
  /// older response). It returns the SAME future, and marks the in-flight run
  /// dirty: when the current fetch lands, it runs ONCE more. Without that, a
  /// toggle that succeeded after the in-flight GET was already answered would
  /// be missing from the list — the GET predates it. The shared future covers
  /// the trailing run too, so every caller awaits the newest data.
  ///
  /// The guard is cleared in a `finally` so a throwing load cannot wedge the
  /// screen into a permanently-refreshing state — though `AsyncValue.guard`
  /// means the failure is captured into `state`, not rethrown, so awaiting a
  /// shared future is safe for every caller.
  ///
  /// **Background refreshes keep the rows on failure.** A narrowed call
  /// ([only] set — the post-toggle follow-up) and a call with
  /// [keepRowsOnFailure] (ADDITIVE, default `false` — the screen's automatic
  /// stale repair) are not user-requested reloads: when one fails while the
  /// list has data, the current rows stay, the error is only logged, and the
  /// list is (or stays) [isStale]. A user-requested full refresh
  /// (pull-to-refresh, the error screen's retry) surfaces its error as before.
  Future<void> refresh({
    FavoriteTargetType? only,
    bool keepRowsOnFailure = false,
  }) {
    // Background-ness is the CALLER's intent, decided before a stale list
    // widens [only] to a full reload below.
    final bool keep = keepRowsOnFailure || only != null;
    // A stale list (an earlier narrowed refresh failed) is repaired whole.
    final FavoriteTargetType? scope = _stale ? null : only;
    final Future<void>? inFlight = _refreshing;
    if (inFlight != null) {
      if (!_rerunQueued) {
        _rerunQueued = true;
        _rerunOnly = scope;
        _rerunKeep = keep;
      } else {
        if (_rerunOnly != scope) _rerunOnly = null;
        _rerunKeep = _rerunKeep && keep;
      }
      return inFlight;
    }
    final Future<void> started = _run(scope, keep);
    _refreshing = started;
    return started;
  }

  /// The body of [refresh]. Safe to assign `_refreshing` only AFTER calling
  /// this: an `async` body runs synchronously to its first `await`, and the
  /// first fetch awaits — so the `finally` below cannot possibly null the
  /// field before [refresh] has set it.
  ///
  /// The result is loaded into a local and assigned only while the provider
  /// is still mounted: a refresh outliving a logout (the provider disposed
  /// mid-fetch) must not write — `state =` on a disposed provider throws.
  Future<void> _run(FavoriteTargetType? only, bool keepRows) async {
    try {
      FavoriteTargetType? scope = only;
      bool keep = keepRows;
      while (true) {
        final FavoriteTargetType? s = scope;
        final AsyncValue<List<FavoriteItem>> result = await AsyncValue.guard(
          () => _reload(s),
        );
        if (!ref.mounted) return;
        if (result is AsyncError<List<FavoriteItem>> &&
            keep &&
            state is AsyncData<List<FavoriteItem>>) {
          // A BACKGROUND refresh (narrowed post-toggle follow-up, or the
          // screen's automatic stale repair) is not a user-requested reload:
          // failing it must not swap a good list for the error screen — whose
          // retry runs the pull-to-refresh path and would cancel pending undo
          // windows. Keep the current rows, log only. A user-requested full
          // refresh (pull-to-refresh, retry) still surfaces its error as
          // before. Marked stale so the next tab visit / narrowed refresh
          // reloads both endpoints.
          _stale = true;
          if (kDebugMode) {
            log(
              'background refresh (${s?.name ?? 'full'}) failed — keeping '
              'the list: '
              '${result.error.runtimeType}',
              name: _tag,
              level: 900,
            );
          }
        } else {
          state = result;
          // `_reload(null)` and a narrowed call that fell back (no data) are
          // both full loads; only a full SUCCESS clears staleness.
          if (s == null && result is AsyncData<List<FavoriteItem>>) {
            _stale = false;
          }
        }
        if (!_rerunQueued) break;
        _rerunQueued = false;
        scope = _stale ? null : _rerunOnly;
        keep = _rerunKeep;
        _rerunOnly = null;
        _rerunKeep = false;
      }
    } finally {
      _refreshing = null;
      _rerunQueued = false;
      _rerunOnly = null;
      _rerunKeep = false;
    }
  }

  /// One fetch for [refresh]: both endpoints when [only] is null (or when
  /// there is no current list to merge into), else the [only] kind merged
  /// into the current list in the same masters-then-salons order [_load]
  /// produces.
  Future<List<FavoriteItem>> _reload(FavoriteTargetType? only) async {
    final FavoriteKind? kind = switch (only) {
      FavoriteTargetType.master => FavoriteKind.master,
      FavoriteTargetType.salon => FavoriteKind.salon,
      FavoriteTargetType.service ||
      FavoriteTargetType.salonService ||
      null => null,
    };
    final List<FavoriteItem>? current = state.value;
    if (kind == null || current == null) return _load();
    final repository = ref.read(favoriteRepositoryProvider);
    final List<FavoriteItem> fresh = kind == FavoriteKind.master
        ? await repository.getFavoriteMasters()
        : await repository.getFavoriteSalons();
    // Disposed mid-fetch: [_run] discards the result; never touch `state`.
    if (!ref.mounted) return current;
    // Re-read AFTER the await: an optimistic unfavorite may have landed.
    final List<FavoriteItem> latest = state.value ?? current;
    final List<FavoriteItem> others = <FavoriteItem>[
      for (final FavoriteItem i in latest)
        if (i.kind != kind) i,
    ];
    return kind == FavoriteKind.master
        ? <FavoriteItem>[...fresh, ...others]
        : <FavoriteItem>[...others, ...fresh];
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
