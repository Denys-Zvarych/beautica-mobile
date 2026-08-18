// Phase 237 — BEAUTY WISH LIST notifier.
//
// ONE provider backs BOTH surfaces. The passport page renders `take(2)` of it,
// the full-list page renders all of it, and both `ref.watch` this same
// [wishlistProvider] — so an un-favourite on either is already reflected on the
// other, with no callback plumbing between them. The approved preview's
// `onChanged` callback exists only because the preview is a `Navigator`-based
// mockup with no shared store; it is deliberately NOT ported.
//
// ## THREE RIVERPOD TRAPS THIS FILE IS BUILT AROUND
//
// 1. NEVER invalidate THIS provider from a screen. Riverpod 3 PAUSES covered
//    consumers, and the full-list page COVERS the passport page. Invalidating
//    an autoDispose provider whose only remaining listeners are paused DISPOSES
//    it; the refetch then lands on resume rather than immediately, so a removal
//    made on the full list would appear to do nothing until the user navigates
//    back and the page rebuilds. [removeService] therefore MUTATES `state` in
//    place — a pure local list edit, no round trip, correct on both surfaces at
//    once. `forbid_provider_self_invalidation.sh` guards the general shape; the
//    specific ban here is asserted by this feature's own tests.
//
// 2. `ref.invalidate` RETAINS the previous `.value`. So no reload-detection
//    anywhere may gate on `value == null` — it would never fire. Nothing in
//    this file does; the note is here because it is the natural thing to reach
//    for when writing a test against it.
//
// 3. `AsyncLoading(retrying: true)` STILL SATISFIES `hasError`. A screen must
//    branch `isLoading` → `hasError` → value explicitly rather than through
//    `.when()`, exactly as `passport_screen.dart` already does. This notifier
//    keeps that possible by NEVER passing through `AsyncLoading` on the
//    optimistic path: [removeService] writes `AsyncData` straight over
//    `AsyncData`, so a removal can never flash a spinner or a spurious error
//    onto a list that is fully loaded and on screen.
//
// ## The un-favourite is optimistic AND reversible, in step with the toggle
//
// The wire call goes through the existing `favoriteToggleProvider`, which is
// already generic over target type and already reverts its OWN entry on
// failure. This notifier must revert in step or the two stores disagree: the
// heart on a master's profile would read "not favourited" while the wish list
// still listed the service, or vice versa. So the list restores the removed
// entry AT ITS ORIGINAL INDEX, not appended — the backend ranks this list, and
// a failed removal that silently reordered it would be a second, invisible bug
// riding on the first.

import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/errors/failures.dart';
import '../../favorites/application/favorite_toggle_notifier.dart';
import '../../favorites/data/favorite_repository_provider.dart';
import '../../favorites/domain/favorite_target.dart';
import '../data/wishlist_repository.dart';
import '../domain/wishlist_service.dart';

part 'wishlist_notifier.g.dart';

/// How long a fetched wish list stays cached before the keep-alive link is
/// dropped, so the next read re-fetches.
///
/// The SAME window `passportProvider` uses, and deliberately not a second
/// constant with a second value: the two providers back one page, and a client
/// who saw them refresh at different moments would read that as a bug. Both
/// hold data that only changes on an explicit user action, so a generous window
/// costs nothing.
const Duration _wishlistCacheTtl = Duration(minutes: 5);

/// Binds the wish-list repository to the live `GET /favorites/services`
/// endpoint. Override in tests with a fake — never construct
/// [HttpWishlistRepository] directly in tests.
@riverpod
WishlistRepository wishlistRepository(Ref ref) =>
    HttpWishlistRepository(ref.watch(favoriteApiProvider));

/// The CLIENT's beauty wish list, shared by the passport page and the full-list
/// page. Kept alive with a [_wishlistCacheTtl] TTL so tab-hopping does not
/// re-fetch on every visit.
@riverpod
class Wishlist extends _$Wishlist {
  @override
  Future<List<WishlistService>> build() async {
    // Keep the result cached after all listeners drop, but only for the TTL —
    // then release the link so the next read re-fetches.
    final link = ref.keepAlive();
    final Timer timer = Timer(_wishlistCacheTtl, link.close);
    ref.onDispose(timer.cancel);

    if (kDebugMode) {
      log(
        'wishlist: fetching GET /favorites/services',
        name: 'feature.wishlist',
        level: 700,
      );
    }
    return ref.watch(wishlistRepositoryProvider).getMyWishlist();
  }

  /// Optimistically removes the entry keyed by [targetId]
  /// ([WishlistService.favoriteTargetId] — `masterServiceId` for a MASTER
  /// row, `serviceDefId` for a SALON row) from the list and un-favourites it
  /// on the wire, restoring it at its original index if the call fails.
  ///
  /// Returns `null` on success, or the [Failure] so the calling screen can
  /// surface a snackbar. Returns `null` (a no-op) when the list is not loaded
  /// or the id is not in it — a double-tap on a row already animating out must
  /// not fire a second request.
  Future<Failure?> removeService(String targetId) async {
    final List<WishlistService>? current = state.value;
    if (current == null) return null;

    final int index = current.indexWhere(
      (WishlistService s) => s.favoriteTargetId == targetId,
    );
    if (index < 0) return null;
    final WishlistService removed = current[index];

    // 1. Optimistic removal. AsyncData over AsyncData — never AsyncLoading, so
    //    a loaded list on screen cannot flash a spinner (see trap 3 above).
    state = AsyncData<List<WishlistService>>(
      List<WishlistService>.unmodifiable(<WishlistService>[
        ...current.sublist(0, index),
        ...current.sublist(index + 1),
      ]),
    );

    // The target TYPE follows the row's own arm — a SALON row un-favourites
    // through `SALON_SERVICE`, never `SERVICE` (that wire value is scoped to
    // a master's own service assignment; sending a SALON row's
    // `service_definitions.id` through it would ask the backend to remove a
    // `master_services` row that does not exist).
    final FavoriteTarget target = FavoriteTarget(
      type: removed.sourceType == WishlistSourceType.salon
          ? FavoriteTargetType.salonService
          : FavoriteTargetType.service,
      id: removed.favoriteTargetId,
    );

    // 2. The toggle notifier decides add-vs-remove from ITS OWN map, and a
    //    target it has never seen reads as `false` — which would make this
    //    toggle an ADD. Every entry in this list is favourited by definition,
    //    so seed that fact first. `primeIfAbsent` never stomps an entry the
    //    user just toggled, so this cannot fight a heart elsewhere on screen.
    final FavoriteToggleNotifier toggle = ref.read(
      favoriteToggleProvider.notifier,
    );
    toggle.primeIfAbsent(target, isFavorite: true);

    // refreshWishlist: false — this call already mutates THIS notifier's own
    // state in place (below) and restores at the original index on failure;
    // letting `toggle` invalidate `wishlistProvider` too would refetch out
    // from under that in-flight optimistic edit. See
    // `favorite_toggle_notifier.dart`'s "Audit cycle 3 fix" for the other
    // direction (a direct un-heart from `ServiceSelectorSheet`, which takes
    // the default and DOES refresh).
    final Failure? failure = await toggle.toggle(
      target,
      refreshWishlist: false,
    );
    if (failure == null) return null;

    // 3. Restore AT THE ORIGINAL INDEX. `favoriteToggleProvider` has already
    //    reverted its own entry; the two must move together.
    //
    //    Re-read `state` rather than reusing `current`: another removal may
    //    have settled while this request was in flight, and rewriting the
    //    pre-removal snapshot would resurrect an entry the user successfully
    //    deleted. The index is clamped for the same reason — the list it is
    //    being inserted back into may be shorter than the one it came from.
    final List<WishlistService> latest =
        state.value ?? const <WishlistService>[];
    if (latest.any((WishlistService s) => s.favoriteTargetId == targetId)) {
      // Already back (a concurrent refetch beat us to it) — leave it alone.
      return failure;
    }
    final int at = index.clamp(0, latest.length);
    state = AsyncData<List<WishlistService>>(
      List<WishlistService>.unmodifiable(<WishlistService>[
        ...latest.sublist(0, at),
        removed,
        ...latest.sublist(at),
      ]),
    );
    return failure;
  }
}
