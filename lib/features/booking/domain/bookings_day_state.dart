// Phase 7.9 — BookingsDayState: the WHOLE set of bookings for one Kyiv
// calendar day, for [bookingsDayProvider].
//
// Retires `MasterBookingsState` (Phase 7.1–7.8), whose `page`/`hasMore`/
// `isLoadingMore` paging fields have no equivalent here — a single request
// (`size: 100, page: 0`) is fetched unconditionally regardless of how many
// bookings the day actually holds; see `bookings_day_notifier.dart`'s "one
// day is NOT provably bounded" note. [isTruncated] is therefore a
// GENUINELY REACHABLE case, not a defensive one — it is what catches
// whatever that single request doesn't cover.
//
// ## Why not reuse `MyBookingsState` [carried from `MasterBookingsState`'s
// header — the reasoning still holds]
//
// The shipped client-side `MyBookingsState` (`application/my_bookings_notifier
// .dart`) is not reused for the same two reasons as before:
//
//   1. The master's toolbar renders a total count («N записів») straight from
//      the server's `totalElements`. `MyBookingsState` has no such field, and
//      widening a shipped, tested client type to serve a master-only need
//      would make one screen's state shape a hostage to the other's.
//   2. `MyBookingsState` is a hand-written `@immutable` class, not freezed —
//      extending it means hand-maintaining `==`/`hashCode`/`copyWith` for a
//      field the client never reads.
//
// [totalElements] survives for the same reason: with a fully-materialised day
// it equals `items.length`, but it is still read from the server so the
// rendered count and the rendered set can never disagree.

import 'package:freezed_annotation/freezed_annotation.dart';

import 'booking.dart';

part 'bookings_day_state.freezed.dart';

/// An immutable snapshot of ONE Kyiv calendar day's bookings — the whole set,
/// not a page of it.
@freezed
abstract class BookingsDayState with _$BookingsDayState {
  const factory BookingsDayState({
    /// Every booking on this day, in **server order** (`startsAt` ASC —
    /// see `bookings_day_notifier.dart`). Rendered directly — never re-sorted
    /// client-side; Phase 7.10's lane assignment depends on this order.
    required List<Booking> items,

    /// Total matching bookings for this day, as reported by the server. With
    /// a fully-materialised day this equals `items.length`, but it is read
    /// from the server rather than derived so the two can never disagree.
    required int totalElements,

    /// `true` when the server reports more results than were returned in
    /// this single request — the belt-and-braces case for the "one day fits
    /// in one page" bound (see `bookings_day_notifier.dart`). Phase 7.11
    /// renders an explicit "day too dense" notice off this flag rather than
    /// looping to page 1 (locked decision, 2026-07-18).
    @Default(false) bool isTruncated,
  }) = _BookingsDayState;

  const BookingsDayState._();

  /// `true` when the day has no bookings at all — the empty-state gate.
  bool get isEmpty => items.isEmpty;
}
