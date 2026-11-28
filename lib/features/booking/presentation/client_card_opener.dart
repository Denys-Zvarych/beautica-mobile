// M569 (CLI-101 / CLI-D20) — the ONE route from a provider booking page's
// client strip into the M510 client card.
//
// PROMOTED from `booking_detail_screen.dart`'s private `_openClientFor`
// (2026-11-21) so the client-review compose, the reschedule confirm / done
// screens and the walk-in review / confirm / done screens open the card the
// same way as «Деталі запису» — one helper, never a copy (REUSE-FIRST).
//
//   registered  →  <base>/user/:userId
//   guest       →  <base>/guest/:bookingId   (CLI-42)
//
// `null` (an inert strip) whenever the mount has no card base or the client
// has no card. The card is pushed ON TOP (`pushOnce`), so back returns to the
// calling page with its state intact.
//
// PII: the ids ride the route path, as on every other card entry; nothing is
// logged here.

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/navigation/single_flight.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/routing/route_names.dart';

import '../domain/booking.dart';
import '../domain/booking_display_x.dart';

/// The card handle of [booking]'s client: the account when there is one, else
/// the guest keyed by this booking (CLI-42). `null` when the client cannot
/// have a card (anonymised / detached — `BookingDisplayX.clientCardReachable`).
ClientRef? clientRefOfBooking(Booking booking) {
  if (!booking.clientCardReachable) return null;
  final String? clientId = booking.clientId;
  return clientId == null
      ? ClientRef.guest(booking.id)
      : ClientRef.registered(clientId);
}

/// The strip's tap into [ref]'s card below the list route [base]
/// (`RouteNames.masterClients` / `salonMasterClients` /
/// `RouteNames.salonClients(salonId)`), or `null` (inert) when either is
/// missing.
///
/// [popBackToCard]: the calling page was itself pushed FROM that client's card
/// (`?fromClientCard=1`), so the tap pops back to it instead of stacking
/// another copy; falls back to the push when nothing can be popped.
VoidCallback? clientCardOpener(
  BuildContext context, {
  required String? base,
  required ClientRef? ref,
  bool popBackToCard = false,
}) {
  if (base == null || ref == null) return null;
  final String path = switch (ref) {
    RegisteredClientRef(:final String userId) => RouteNames.clientCardUser(
      base,
      userId,
    ),
    GuestClientRef(:final String bookingId) => RouteNames.clientCardGuest(
      base,
      bookingId,
    ),
  };
  return () {
    if (popBackToCard && context.canPop()) {
      context.pop();
      return;
    }
    context.pushOnce<void>(path);
  };
}
