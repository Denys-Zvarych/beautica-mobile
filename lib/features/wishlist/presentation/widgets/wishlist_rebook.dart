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
// ## SALON rows re-enter the salon booking flow at its EXISTING step 2
//
// A MASTER row's «Записатись» has always pushed straight to the slot picker
// because BOTH ids the booking flow needs (`masterId` AND a
// `preselectedServiceId`) are already known. A SALON row has neither — the
// client favourited a catalogue entry with no master chosen yet. What it DOES
// know is "this salon, this one service", which is precisely the state the
// salon booking flow carries out of its step 1: a
// [SalonBookingMasterSelectionArgs] of `(salonId, selectedServiceIds)`.
//
// So the salon-arm CTA («Обрати майстра») pushes
// `RouteNames.salonBookingMasters` with that payload — landing the client on
// `SalonMasterSelectionScreen`, the SAME screen the ordinary flow reaches via
// salon profile → «Записатись на послугу» → pick a service → «Далі». Earlier
// cuts of this CTA instead opened the salon's public profile with its
// "Майстри" tab deep-link-filtered to the service; that was a second,
// parallel "masters who perform this service" UI on top of a step that
// already IS exactly that, and has been deleted (with the query-param
// deep link that drove it — see `route_names.dart`'s `salonPublicProfile`,
// now bare-path only). The service→masters filter reachable by TAPPING a
// service inside the salon profile's own "Послуги" tab is a DIFFERENT,
// unaffected feature and stays.
//
// Entering step 2 directly is safe: `SalonMasterSelectionScreen` reads no
// draft state that step 1 populates. Its three sources
// (`publicSalonProfileProvider`, `salonServiceCatalogProvider`,
// `salonMasterServiceCoverageProvider`) are all self-fetching families keyed
// on the salon id / these very args, its «Далі» resolves the step-3 payload
// from data it loaded itself, and its back control is a plain `context.pop()`
// — which, because we `push`, returns here to the wish list rather than
// walking into a step 1 that never rendered.
//
// `serviceDefId` is exactly the catalogue id the flow selects on
// (`SalonCatalogService.id` — the same `service_definitions.id` namespace,
// per `wishlist_service.dart`'s header), so it needs no translation into
// `selectedServiceIds`. If the service was withdrawn since the client
// favourited it, the coverage lookup degrades per-service to "no bookable
// masters" and the destination renders its own «жоден майстер» empty state —
// the DESTINATION's job, not this navigator's: [rebook] never pre-flight-
// checks the id before pushing (see below).
//
// Note both wish-list surfaces expose this CTA and NOTHING else navigates: the
// rows themselves have no `onTap` (`wishlist_compact_card.dart`,
// `wishlist_row.dart` wire only `onBook`), so this mixin is the single
// navigation entry point for a wish-list entry — there is no second,
// divergent path to keep in sync.
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
import '../../../booking/domain/salon_booking_args.dart';
import '../../application/wishlist_notifier.dart';
import '../../domain/wishlist_service.dart';

/// Adds the shared «Записатись» rebook sequence to a wish-list surface's
/// [State]. Mix into a `ConsumerState` and wire both `onBook` callbacks
/// (compact card + full row) to [rebook].
mixin WishlistRebookHost<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// For a MASTER row, opens the existing booking flow pre-seeded with
  /// [item]'s `(masterId, masterServiceId)`. For a SALON row, re-enters the
  /// salon booking flow at its step-2 master picker, with the favourited
  /// service as the whole selection — see the file header's SALON section.
  /// Either way, refreshes the wish list once the flow returns; see the file
  /// header for why there is no pre-flight check and why the refresh is
  /// deliberately unconditional and deferred to AFTER the push resolves.
  Future<void> rebook(WishlistService item) async {
    switch (item.sourceType) {
      case WishlistSourceType.master:
        final String? masterId = item.masterId;
        final String? masterServiceId = item.masterServiceId;
        assert(
          masterId != null && masterServiceId != null,
          'a MASTER wishlist row is missing masterId/masterServiceId — the '
          "mapper's per-arm null-guard should have refused to build this row",
        );
        if (masterId == null || masterServiceId == null) return;
        await context.push(
          RouteNames.bookingNew,
          extra: BookingEntryArgs(
            masterId: masterId,
            preselectedServiceId: masterServiceId,
          ),
        );
      case WishlistSourceType.salon:
        final String? salonId = item.salonId;
        final String? serviceDefId = item.serviceDefId;
        assert(
          salonId != null && serviceDefId != null,
          'a SALON wishlist row is missing salonId/serviceDefId — the '
          "mapper's per-arm null-guard should have refused to build this row",
        );
        if (salonId == null || serviceDefId == null) return;
        await context.push(
          RouteNames.salonBookingMasters,
          extra: SalonBookingMasterSelectionArgs(
            salonId: salonId,
            selectedServiceIds: <String>[serviceDefId],
          ),
        );
    }
    if (!mounted) return;
    ref.invalidate(wishlistProvider);
  }
}
