// M509 — the route a client list row opens: the M510 card, addressed by the
// row's [ClientRef] below the host's list route.
//
//   registered  →  <listRoute>/user/:userId
//   guest       →  <listRoute>/guest/:bookingId
//
// Owner master mode narrows the salon endpoint to the owner's own master row;
// its card route carries `?masterId=` ([kClientCardMasterIdQuery]).
//
// Pure function over `RouteNames` — no raw path literals.

import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/routing/route_names.dart';

/// The card location for [ref] below [listRoute] (`RouteNames.masterClients` /
/// `salonMasterClients`, or `RouteNames.salonClients(salonId)`).
String clientCardRoute(String listRoute, ClientRef ref, {String? masterId}) {
  final String path = switch (ref) {
    RegisteredClientRef(:final String userId) => RouteNames.clientCardUser(
      listRoute,
      userId,
    ),
    GuestClientRef(:final String bookingId) => RouteNames.clientCardGuest(
      listRoute,
      bookingId,
    ),
  };
  return masterId == null
      ? path
      : '$path?$kClientCardMasterIdQuery=${Uri.encodeQueryComponent(masterId)}';
}

/// M510 — «Рейтинг клієнта» below the card of [ref] (same `?masterId=` rule as
/// [clientCardRoute]).
String clientRatingRoute(String listRoute, ClientRef ref, {String? masterId}) {
  final String path = switch (ref) {
    RegisteredClientRef(:final String userId) => RouteNames.clientRatingUser(
      listRoute,
      userId,
    ),
    GuestClientRef(:final String bookingId) => RouteNames.clientRatingGuest(
      listRoute,
      bookingId,
    ),
  };
  return masterId == null
      ? path
      : '$path?$kClientCardMasterIdQuery=${Uri.encodeQueryComponent(masterId)}';
}

/// The booking-detail location a card's visit opens: [bookingPath] plus
/// `?fromClientCard=1` ([kBookingFromClientCardQuery]), so that detail's
/// client strip pops back to this card instead of pushing another one.
String bookingFromClientCard(String bookingPath) {
  final Uri uri = Uri.parse(bookingPath);
  return uri
      .replace(
        queryParameters: <String, String>{
          ...uri.queryParameters,
          kBookingFromClientCardQuery: '1',
        },
      )
      .toString();
}
