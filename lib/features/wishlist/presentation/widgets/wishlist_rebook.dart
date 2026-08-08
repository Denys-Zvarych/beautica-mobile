// Phase 241 — the «Записатись» rebook gesture, shared by both wish-list
// surfaces (the passport page's compact-card line AND the full «Усі
// збережені» list). Mirrors `wishlist_removal.dart`'s existing pattern: one
// mixin, mixed into both `ConsumerState`s, so the two CTAs can never diverge —
// `WishlistCompactCard.onBook` and `WishlistRow.onBook` both take a plain
// `VoidCallback`; the cards themselves stay dumb.
//
// ## Reuses the EXISTING booking flow — no new endpoint, no second flow
//
// `RouteNames.bookingNew` (`ServiceSelectorSheet`, booking Step 1) already
// accepts a [BookingEntryArgs] carrying `(masterId, preselectedServiceId)` —
// the additive extension point phase 241 added alongside the route's
// original bare-masterId-`String` shape (see `booking_entry_args.dart`).
// `ServiceSelectorSheet.autoAdvance` then skips straight to the slot picker,
// so the client lands on slot selection rather than re-picking a service they
// already chose by favouriting it. Per backend phase 248's audited verdict,
// `POST /bookings` / `POST /appointments` carry no flow discriminator — a
// rebook is indistinguishable at the API from any other booking entry point,
// so nothing here talks to the network directly.
//
// ## No pre-flight validation
//
// [rebook] pushes immediately. It does NOT re-check that [WishlistService]'s
// service is still active before navigating — per backend 248/phase 241, a
// service can be deactivated between the wish-list load and the eventual
// `POST`, and a pre-check here would not close that race (the window would
// just move earlier), only add a round trip to every rebook. `Service
// SelectorSheet` and the flow's own creation step already surface a
// deactivated service as a normal booking-flow [Failure] — see their file
// headers — so the failure is handled where it is actually detected, not
// duplicated here.
//
// ## The refresh-after-return
//
// `wishlistProvider` (an autoDispose `AsyncNotifier`) is COVERED — paused —
// while the pushed booking flow sits on top of whichever wish-list surface
// triggered [rebook]. Invalidating a covered autoDispose provider whose only
// listeners are paused DISPOSES it rather than refetching, and the actual
// refetch would only land on resume — so [rebook] deliberately waits for the
// `await context.push(...)` to RETURN (the covering route is gone and this
// surface is the active route again, its listener no longer paused) before
// calling `ref.invalidate`. That is what makes a rebook that failed on a
// deactivated service actually drop the dead entry from the list: a
// successful `GET /favorites/services` refetch already excludes it
// (Phase 247's `is_active` filter). Refreshing unconditionally — on success,
// on failure, or on the client simply backing out — is deliberate too: any of
// the three can leave the on-screen list stale, and a refetch that finds
// nothing changed is a harmless no-op.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../routing/route_names.dart';
import '../../../booking/domain/booking_entry_args.dart';
import '../../application/wishlist_notifier.dart';
import '../../domain/wishlist_service.dart';

/// Adds the shared «Записатись» rebook sequence to a wish-list surface's
/// [State]. Mix into a `ConsumerState` and wire both `onBook` callbacks
/// (compact card + full row) to [rebook].
mixin WishlistRebookHost<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// Opens the existing booking flow pre-seeded with [item]'s
  /// `(masterId, masterServiceId)`, then refreshes the wish list once the
  /// flow returns. See the file header for why there is no pre-flight check
  /// and why the refresh is deliberately unconditional and deferred to AFTER
  /// the push resolves.
  Future<void> rebook(WishlistService item) async {
    await context.push(
      RouteNames.bookingNew,
      extra: BookingEntryArgs(
        masterId: item.masterId,
        preselectedServiceId: item.masterServiceId,
      ),
    );
    if (!mounted) return;
    ref.invalidate(wishlistProvider);
  }
}
