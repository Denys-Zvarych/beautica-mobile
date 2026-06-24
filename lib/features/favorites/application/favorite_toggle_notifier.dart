// Phase 13.4 — Favorite-toggle notifier (optimistic add/remove).
//
// A single keepAlive notifier holding the favorite flag for every target the
// user has interacted with this session, keyed by [FavoriteTarget]. Shared by
// the search results cards (13.4), the public master/salon profiles (13.5/13.6)
// and the Favorites screen (13.10).
//
// State shape: `Map<FavoriteTarget, FavoriteEntry>`. A target absent from the
// map has no known flag yet (the card seeds `false` on first build via
// [primeIfAbsent]); a present entry carries the current `isFavorite` flag plus
// a `pending` marker while a network call is in flight (so the heart can ignore
// rapid re-taps on the same target without dropping the final intent).
//
// Toggle flow (optimistic):
//   1. flip the flag in state immediately (UI reflects intent instantly),
//   2. call FavoriteRepository.add/remove,
//   3. on success → keep the flipped flag, clear pending,
//   4. on failure → revert to the pre-toggle flag, clear pending, and return
//      the [Failure] so the screen can surface a snackbar.
//
// Idempotency: the backend's add (200) / remove (204) are idempotent, so a
// double-tap that lands the same final state is harmless. We still guard against
// overlapping in-flight calls on ONE target via the `pending` flag.
//
// keepAlive + auth-watched: the flags survive the push from results into a
// profile and back, and reset to empty on a fresh session (logout → login) —
// the same self-clearing pattern every per-user keepAlive provider uses.

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/errors/failures.dart';

import '../../auth/presentation/auth_notifier.dart';
import '../data/favorite_repository_provider.dart';
import '../domain/favorite_target.dart';

part 'favorite_toggle_notifier.g.dart';

/// One target's favorite flag plus its in-flight marker.
@immutable
class FavoriteEntry {
  const FavoriteEntry({required this.isFavorite, this.pending = false});

  /// The current (optimistic) favorite flag.
  final bool isFavorite;

  /// Whether an add/remove call for this target is currently in flight.
  final bool pending;

  FavoriteEntry copyWith({bool? isFavorite, bool? pending}) => FavoriteEntry(
    isFavorite: isFavorite ?? this.isFavorite,
    pending: pending ?? this.pending,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FavoriteEntry &&
          other.isFavorite == isFavorite &&
          other.pending == pending;

  @override
  int get hashCode => Object.hash(isFavorite, pending);
}

/// Holds the favorite flag for every target touched this session.
@Riverpod(keepAlive: true)
class FavoriteToggleNotifier extends _$FavoriteToggleNotifier {
  @override
  Map<FavoriteTarget, FavoriteEntry> build() {
    // Reset to empty whenever the session changes (logout → login) so one
    // user's favorites never leak to the next login.
    ref.watch(authProvider);
    return const <FavoriteTarget, FavoriteEntry>{};
  }

  /// Seeds [target]'s flag to [isFavorite] only if it is not already tracked.
  ///
  /// Cards call this once when they first build so the heart starts in the
  /// correct state (from the search result's own favorited flag, or `false`
  /// when the search payload carries no flag). Never overwrites an existing
  /// entry — a later seed must not stomp a flag the user just toggled.
  void primeIfAbsent(FavoriteTarget target, {required bool isFavorite}) {
    if (state.containsKey(target)) return;
    // A stored `false` carries no information — an absent target already reads
    // `false` via the heart's `.select()` fallback. Skip it so this keepAlive
    // map doesn't accumulate one dead entry per card scrolled past.
    if (!isFavorite) return;
    state = <FavoriteTarget, FavoriteEntry>{
      ...state,
      target: const FavoriteEntry(isFavorite: true),
    };
  }

  /// Whether [target] is currently favorited (defaults to `false` when unseen).
  bool isFavorite(FavoriteTarget target) => state[target]?.isFavorite ?? false;

  /// Optimistically toggles [target]'s favorite flag, calling the repository
  /// and reverting on error.
  ///
  /// Returns `null` on success, or the [Failure] on error (so the caller can
  /// show a snackbar). A no-op (returns `null`) when a call for [target] is
  /// already in flight, so a rapid double-tap can't fire overlapping requests.
  Future<Failure?> toggle(FavoriteTarget target) async {
    final FavoriteEntry current =
        state[target] ?? const FavoriteEntry(isFavorite: false);
    if (current.pending) return null;

    final bool next = !current.isFavorite;

    // 1. Optimistic flip + mark pending.
    _set(target, FavoriteEntry(isFavorite: next, pending: true));

    try {
      // 2. Persist.
      if (next) {
        await ref.read(favoriteRepositoryProvider).add(target);
      } else {
        await ref.read(favoriteRepositoryProvider).remove(target);
      }
      // 3. Success — keep the flipped flag, clear pending.
      _set(target, FavoriteEntry(isFavorite: next));
      return null;
    } on Failure catch (failure) {
      // 4. Revert to the pre-toggle flag, clear pending.
      _set(target, FavoriteEntry(isFavorite: current.isFavorite));
      return failure;
    }
  }

  void _set(FavoriteTarget target, FavoriteEntry entry) {
    // Prune settled `false` entries (isFavorite == false && !pending): they
    // carry no information over the heart's `.select()` fallback, so retaining
    // them would let this keepAlive map grow unbounded. A `false` entry that is
    // still `pending` (an in-flight un-favorite) is retained so the double-tap
    // guard keeps working; it is pruned on settle.
    if (!entry.isFavorite && !entry.pending) {
      if (!state.containsKey(target)) return;
      final Map<FavoriteTarget, FavoriteEntry> next =
          <FavoriteTarget, FavoriteEntry>{...state}..remove(target);
      state = next;
      return;
    }
    state = <FavoriteTarget, FavoriteEntry>{...state, target: entry};
  }
}
