// M510 — one visit on the client card's timeline (B508 `ClientVisitResponse`).
//
// `masterDisplayName` / `masterId` are NOT mapped: no master name is ever
// shown on a visit (D2). `BookingStatus.fromWire` is unknown-safe.
//
// Pure Dart: no Flutter imports.

import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:beautica_mobile/features/booking/domain/booking_status.dart';

part 'client_visit.freezed.dart';

/// How many visit pages the next-visit lookahead may load (D4).
const int kClientVisitLookaheadMaxPages = 5;

@freezed
abstract class ClientVisitItem with _$ClientVisitItem {
  const factory ClientVisitItem({
    required String bookingId,
    required String serviceName,
    required BookingStatus status,
    required DateTime startsAt,
    double? price,
    double? priceMax,
  }) = _ClientVisitItem;
}

@freezed
abstract class ClientVisit with _$ClientVisit {
  const factory ClientVisit({
    required String visitKey,
    required DateTime startsAt,
    required List<ClientVisitItem> items,
  }) = _ClientVisit;

  const ClientVisit._();

  /// The booking the visit card opens (the first item; scope is enforced
  /// server-side).
  String get firstBookingId => items.first.bookingId;

  /// The one status when every item shares it, else `null`. A data-layer fact
  /// only: the card renders one row per booking ([clientVisitsPerBooking]).
  BookingStatus? get sharedStatus {
    final BookingStatus first = items.first.status;
    return items.every((ClientVisitItem i) => i.status == first) ? first : null;
  }

  /// The earliest CONFIRMED item strictly after [now], or `null`.
  DateTime? upcomingConfirmedAt(DateTime now) {
    DateTime? best;
    for (final ClientVisitItem i in items) {
      if (i.status == BookingStatus.confirmed && i.startsAt.isAfter(now)) {
        if (best == null || i.startsAt.isBefore(best)) best = i.startsAt;
      }
    }
    return best;
  }
}

/// D4 — the visit holding the earliest CONFIRMED item after [now], or `null`.
ClientVisit? pickNextVisit(List<ClientVisit> visits, DateTime now) {
  ClientVisit? best;
  DateTime? bestAt;
  for (final ClientVisit v in visits) {
    final DateTime? at = v.upcomingConfirmedAt(now);
    if (at != null && (bestAt == null || at.isBefore(bestAt))) {
      best = v;
      bestAt = at;
    }
  }
  return best;
}

/// D4 lookahead — pages come newest first, so while EVERY loaded visit is
/// still in the future, an older page may hold an earlier upcoming visit.
bool nextVisitLookaheadPending(List<ClientVisit> visits, DateTime now) =>
    visits.isNotEmpty &&
    visits.every((ClientVisit v) => v.startsAt.isAfter(now));

/// BOOK-05 — one booking = one service. The API may group bookings that share
/// an appointment (a slot-reservation id that never surfaces in UI) into one
/// [ClientVisit]; the timeline shows ONE row per BOOKING instead. Each item
/// becomes its own single-item visit keyed by its `bookingId`, newest first
/// within the group (ties keep the server order), so the newest-first page
/// order is preserved.
List<ClientVisit> clientVisitsPerBooking(Iterable<ClientVisit> visits) {
  final List<ClientVisit> out = <ClientVisit>[];
  for (final ClientVisit v in visits) {
    if (v.items.length == 1) {
      out.add(_perBookingVisit(v.items.first));
      continue;
    }
    final List<(int, ClientVisitItem)> indexed =
        <(int, ClientVisitItem)>[
          for (int k = 0; k < v.items.length; k++) (k, v.items[k]),
        ]..sort((a, b) {
          final int byTime = b.$2.startsAt.compareTo(a.$2.startsAt);
          return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
        });
    for (final (int _, ClientVisitItem item) in indexed) {
      out.add(_perBookingVisit(item));
    }
  }
  return out;
}

ClientVisit _perBookingVisit(ClientVisitItem item) => ClientVisit(
  visitKey: item.bookingId,
  startsAt: item.startsAt,
  items: <ClientVisitItem>[item],
);
