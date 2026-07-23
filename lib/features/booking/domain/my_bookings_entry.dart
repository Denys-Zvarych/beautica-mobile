// MO-5 — «Мої записи» list grouping: collapse the per-service `Booking` rows of
// ONE multi-service visit into a single list entry.
//
// `GET /bookings/me` still returns one `Booking` row PER service. A visit's
// rows now share a non-null `appointmentId` (MO-1). This file turns the flat,
// server-ordered `List<Booking>` the notifier holds into a `List<MyBookingsEntry>`
// where every group of rows sharing an `appointmentId` becomes ONE
// [VisitBookingEntry] and every legacy standalone booking (`appointmentId ==
// null`) stays its own [SingleBookingEntry].
//
// ## Client-side, no extra fetch
//
// The grouping is a PURE function over the rows already fetched for the list —
// there is NO per-row `getAppointment` call (that would be an N+1). The visit
// CARD derives its whole summary (ordered service names, summed duration, total
// price / band, the single start time, the shared status) from the grouped
// rows themselves; only the visit DETAIL screen calls `getAppointment`.
//
// ## Order is preserved
//
// The server orders the rows (soonest-first on Майбутні, most-recent-first on
// Минулі/Скасовані). [groupBookingsByAppointment] keeps that order: a visit
// takes the position of its FIRST-seen row, and a later row of the same visit
// folds into that existing entry rather than creating a new one. So the
// existing sort / filter / day-bucket semantics are untouched — grouping only
// merges adjacent-in-meaning rows, it never reorders.
//
// A visit's rows straddling a page boundary (its later services landing on the
// next page) self-heal: grouping runs over the WHOLE accumulated list each
// build, so once both pages are loaded the group is whole again. Between the
// two the visit simply renders with fewer services for a frame — never wrong,
// never duplicated.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:beautica_mobile/shared/formatters/booking_price_labels.dart';

import 'booking.dart';
import 'booking_display_x.dart';
import 'booking_status.dart';

part 'my_bookings_entry.freezed.dart';

/// One row of the «Мої записи» list AFTER grouping: either a single legacy
/// booking or a multi-service visit. Render a [SingleBookingEntry] with the
/// existing `BookingCard` (unchanged), a [VisitBookingEntry] with `VisitCard`.
@freezed
sealed class MyBookingsEntry with _$MyBookingsEntry {
  /// A standalone single-service booking (`appointmentId == null`) — the legacy
  /// shape, still the common case. Renders exactly as before.
  const factory MyBookingsEntry.single(Booking booking) = SingleBookingEntry;

  /// A multi-service visit — the N per-service bookings the client placed for
  /// ONE arrival, all sharing [appointmentId]. [bookings] holds those rows in
  /// the order the server returned them; use [VisitBookingEntryX] for the
  /// display-ordered, summarised view.
  const factory MyBookingsEntry.visit({
    required String appointmentId,
    required List<Booking> bookings,
  }) = VisitBookingEntry;
}

/// Groups a server-ordered [bookings] list into [MyBookingsEntry]s: rows sharing
/// a non-null `appointmentId` collapse into one [VisitBookingEntry]; a null
/// `appointmentId` is its own [SingleBookingEntry].
///
/// Pure, order-preserving, O(n). See the file header for the ordering + page-
/// straddle contract.
List<MyBookingsEntry> groupBookingsByAppointment(List<Booking> bookings) {
  final List<MyBookingsEntry> result = <MyBookingsEntry>[];

  // appointmentId -> index of its entry in [result], and its accumulating rows.
  final Map<String, int> visitSlot = <String, int>{};
  final Map<String, List<Booking>> visitRows = <String, List<Booking>>{};

  for (final Booking booking in bookings) {
    final String? appointmentId = booking.appointmentId;
    if (appointmentId == null) {
      result.add(MyBookingsEntry.single(booking));
      continue;
    }

    final int? existing = visitSlot[appointmentId];
    if (existing == null) {
      final List<Booking> rows = <Booking>[booking];
      visitRows[appointmentId] = rows;
      visitSlot[appointmentId] = result.length;
      result.add(
        MyBookingsEntry.visit(
          appointmentId: appointmentId,
          bookings: List<Booking>.unmodifiable(rows),
        ),
      );
    } else {
      final List<Booking> rows = visitRows[appointmentId]!..add(booking);
      // Re-emit the entry with the widened, still-unmodifiable snapshot.
      result[existing] = MyBookingsEntry.visit(
        appointmentId: appointmentId,
        bookings: List<Booking>.unmodifiable(rows),
      );
    }
  }

  return List<MyBookingsEntry>.unmodifiable(result);
}

/// Display-derived getters for a grouped visit — the visit CARD's whole summary,
/// computed from the grouped rows (no network call). All rows of one visit share
/// the same master and the same status (all-or-nothing on the wire), so those
/// read off the lead row.
extension VisitBookingEntryX on VisitBookingEntry {
  /// The rows ordered by their own start instant — the services run back-to-back
  /// within the visit, so this is the arrival order the client experiences.
  List<Booking> get orderedBookings {
    final List<Booking> sorted = List<Booking>.of(bookings);
    sorted.sort((Booking a, Booking b) => a.startAt.compareTo(b.startAt));
    return sorted;
  }

  /// The earliest row — carries the visit's shared master identity + status and
  /// its single start time.
  Booking get lead => orderedBookings.first;

  /// The visit's shared status (all rows share it).
  BookingStatus get status => lead.status;

  /// The visit's single start instant — the earliest item's start.
  DateTime get startAt => lead.startAt;

  /// How many services the visit bundles.
  int get serviceCount => bookings.length;

  /// The ordered service names.
  List<String> get serviceNames => <String>[
    for (final Booking b in orderedBookings) b.serviceName,
  ];

  /// Sum of the items' durations, in minutes.
  int get summedDurationMinutes =>
      bookings.fold<int>(0, (int sum, Booking b) => sum + b.durationMinutes);

  /// Whether money is a true statement about this visit — shared with the
  /// single-booking rule (`BookingDisplayX.showsPrice`): shown only on
  /// CONFIRMED / COMPLETED.
  bool get showsPrice => lead.showsPrice;

  /// The visit's total price label — «650 ₴» when every item resolved to a
  /// single price, or the summed band «300–500 ₴» when at least one item was a
  /// genuine RANGE at booking time. Routed through the shared
  /// [formatBookingTotalsFromTerms] so the visit card, the visit detail's
  /// «Разом» and the backend's own `totalPrice`/`totalPriceMax` can never drift
  /// on separator, rounding or the degenerate-band collapse.
  ///
  /// Orthogonal to [showsPrice] — the caller gates on that first.
  String get priceLabel => formatBookingTotalsFromTerms(<BookingTotalTerm>[
    for (final Booking b in bookings)
      (min: b.price, max: b.priceMax ?? b.price, minutes: b.durationMinutes),
  ]).priceLabel;
}
