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
//
// ## Phase 240 fix — a successful SERVICE add refreshes the wish list
//
// `wishlistProvider` primes its hearts from `favoriteToggleProvider` (see
// `ServiceSelectorSheet`'s `_CatalogueBodyState`), but the reverse link was
// missing: nothing ever told `wishlistProvider` a NEW favourite existed, so
// the wish list read stale data for the rest of the session. [toggle] closes
// that loop centrally — every SERVICE-add call site gets it for free, with no
// fork of `FavoriteHeartButton`.
//
// ## Audit cycle 3 fix — caller-selected refresh, not add-only
//
// The add-only version above left a REAL user-visible bug: un-hearting a
// service from `ServiceSelectorSheet` (the booking sheet) never refreshed
// `wishlistProvider` either, so a client who un-hearted a service there would
// still see it on the Beauty Passport for up to the 5-minute TTL. That
// affordance (un-hearting from the booking sheet at all) is itself new to
// this phase, so the staleness is in-diff, not a pre-existing gap.
//
// [toggle] now takes [refreshWishlist], defaulted to `true` — so
// `FavoriteHeartButton` (the booking sheet's only caller, which never passes
// it) refreshes on BOTH add and remove. `WishlistNotifier.removeService` is
// the ONE call site that passes `false`: it already does its own wire call
// through this exact method, then mutates its OWN state in place and restores
// at the original index on failure — a design its own file header requires
// specifically to dodge the paused-listener trap below. Invalidating here on
// every one of ITS removes too would refetch out from under that in-flight
// optimistic edit, discarding the restore-on-failure bookkeeping for a round
// trip it exists to avoid — a regression, not a fix. See
// `test/features/favorites/favorite_toggle_notifier_test.dart` (both
// directions pinned) and `test/features/wishlist/application/
// wishlist_notifier_test.dart`'s "does NOT refetch" case (the suppression
// direction, unchanged).
//
// Riverpod covered-consumer trap, checked not assumed — and, as of Phase 243,
// actually LANDED on us, not just theoretical:
//
// `wishlistProvider`'s ONLY remaining consumer is `PassportScreen`
// (`lib/routing/app_router.dart`'s `kClientPassportBranch`, one of five
// `StatefulShellBranch`es inside the CLIENT shell's `IndexedStack`).
// `ServiceSelectorSheet` used to hold its own active watch on
// `wishlistProvider` too (it primed every row's heart from it), which is what
// made the refetch below fire immediately at toggle time. Phase 243 replaced
// that priming source with `MasterService.isFavorite` off the payload the
// sheet already fetches, and dropped the watch entirely — see
// `service_selector_sheet.dart`'s Phase 243 header and this file's own
// "Audit cycle 3 fix" note above.
//
// So at toggle time — reached via `RouteNames.bookingNew`, a sibling
// `GoRoute` pushed ON TOP of the client shell (`app_router.dart`) —
// `PassportScreen` is mounted but COVERED, which Riverpod 3 reports to its
// `Consumer`/`ConsumerWidget`s as `TickerMode(enabled: false)`
// (`flutter_riverpod`'s `consumer.dart`): the covered branch's Navigator sits
// under go_router's own `Offstage` + `TickerMode(enabled: isActive)` wrapper.
// A `TickerMode`-disabled consumer's subscription is PAUSED, and invalidating
// an autoDispose provider whose only listener is paused DISPOSES it rather
// than reloading it — the refetch is deferred to resume, with no retained
// previous value in between (project memory: "Riverpod offstage-pause
// invalidate gotcha"; mirrors `wishlist_notifier.dart`'s own trap #1, which is
// exactly why THAT file's `removeService` mutates state in place instead of
// invalidating).
//
// ACCEPTED TRADE, not a bug to fix: a client who un-hearts a service from this
// booking sheet and then switches to the Passport tab sees a brief loading
// spinner instead of instant cached-fresh data — because the dispose-and-
// refetch actually happens on that tab switch (the resume), not before. We
// keep the invalidate anyway. The data ends up correct, the case is narrow
// (only a toggle from the booking sheet followed by a Passport visit), and a
// brief spinner is a fair price for removing a guaranteed network round trip
// from the app's hottest screen transition (see `wishlistProvider`'s own
// `_wishlistCacheTtl` comment for why a generous cache window is otherwise the
// norm here). Do not "fix" this by re-adding a watch to `ServiceSelectorSheet`
// — that regresses Phase 243's >20-favourites correctness fix.

import 'package:flutter/foundation.dart';
// `ProviderListenable.select` (used below to narrow the `authProvider` watch to
// the identity-bearing slice via [authUserIdOrNull]) is not part of
// `riverpod_annotation`'s show-list — same reason `bookings_day_notifier.dart`
// reaches for the full package.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/errors/failures.dart';

import '../../auth/presentation/auth_notifier.dart';
import '../../wishlist/application/wishlist_notifier.dart';
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
    //
    // NARROWED to the user id (mobile-perf LOW, 2026-09-01) — a CORRECTNESS
    // fix here, like `pending_service_preselection_provider.dart`. Rebuilding
    // this notifier empties the map, so the bare `ref.watch(authProvider)`
    // meant a silent token refresh (`AuthNotifier.setAccessToken` re-emits
    // `Authenticated` with a new accessToken) dropped every optimistic heart
    // the user had just tapped: the hearts on screen fell back to their
    // `.select` default of `false` until the next `primeIfAbsent`/refetch.
    // Only a different signed-in identity may clear this map — that is the
    // leak this watch was added to close.
    ref.watch(authProvider.select(authUserIdOrNull));
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
  ///
  /// [refreshWishlist] gates the `wishlistProvider` invalidation on a
  /// successful SERVICE-target toggle (add OR remove) — defaults to `true` so
  /// every caller except `WishlistNotifier.removeService` refreshes for free.
  /// See the file header ("Audit cycle 3 fix") for why that one call site
  /// passes `false`.
  Future<Failure?> toggle(
    FavoriteTarget target, {
    bool refreshWishlist = true,
  }) async {
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
      // Phase 240 fix, widened in audit cycle 3 — a successful SERVICE toggle
      // (add OR remove) tells the wish list to refetch, UNLESS the caller
      // opted out via [refreshWishlist] (see the file header).
      if (refreshWishlist && target.type == FavoriteTargetType.service) {
        // wishlistProvider.build() only ref.watches wishlistRepositoryProvider;
        // removeService() only ref.reads (never watches) this notifier — no
        // back-edge, so invalidating it here cannot close a cycle. Proved on
        // the real provider graph (not just code-read) by
        // test/core/provider_cycle_guard_test.dart's
        // "favoriteToggleProvider.notifier.toggle()" registry row.
        // cycle-safe: no back-edge from wishlistProvider to this notifier.
        ref.invalidate(wishlistProvider);
      }
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
