// Phase 480 — BookingsWeekState: one Kyiv week's bookings, grouped by Kyiv
// day, for [bookingsWeekProvider] (`application/bookings_week_notifier.dart`).

import 'package:freezed_annotation/freezed_annotation.dart';

import 'booking.dart';

part 'bookings_week_state.freezed.dart';

/// An immutable snapshot of one Mon–Sun Kyiv week of the master's bookings.
@freezed
abstract class BookingsWeekState with _$BookingsWeekState {
  const factory BookingsWeekState({
    /// The Monday date token this week starts on (== the query's
    /// `weekStart`).
    required DateTime weekStart,

    /// Exactly SEVEN keys — the week's Kyiv day tokens, Monday first — each
    /// mapping to that day's bookings in server order (`startAt` ASC). A day
    /// with no bookings maps to an empty list, never a missing key. A
    /// booking's day is `kyivDayOf(startAt)`, so a 23:30 Kyiv start (UTC next
    /// day) lands on its Kyiv day.
    ///
    /// Stored (map AND each list) as `EqualUnmodifiable*View`, so freezed's
    /// getter returns the SAME instance on every read and `identical(...)`
    /// memo gates downstream actually hit (see `bookings_day_state.dart`'s
    /// `stableBookingList`).
    required Map<DateTime, List<Booking>> byDay,

    /// `true` when the page loop hit its hard stop before collecting every
    /// booking the server reported — same flag, same semantics as
    /// `BookingsDayState.isTruncated`.
    @Default(false) bool isTruncated,
  }) = _BookingsWeekState;

  const BookingsWeekState._();

  /// Bookings on the Kyiv day token [day]; empty for a day outside the week.
  List<Booking> bookingsOn(DateTime day) => byDay[day] ?? const <Booking>[];
}
