// 2026-10-30 «Графік» booked-slots overlay — test double for
// `bookingsDayProvider`.
//
// `MasterScheduleScreen` watches `bookingsDayProvider` for the selected day so
// it can paint booked cells. Unstubbed, that reaches the REAL
// `HttpBookingRepository` → Dio, whose zero-duration timer outlives the widget
// tree ("A Timer is still pending even after the widget tree was disposed").
// Every test that mounts the schedule screen without a fake booking
// repository adds [stubBookingsDayOverride] to its overrides.

import 'package:beautica_mobile/features/booking/application/bookings_day_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_query.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_state.dart';

/// Resolves EVERY `bookingsDayProvider(query)` member to [bookings] — no
/// network, no timer, no LRU touch.
class StubBookingsDay extends BookingsDayNotifier {
  StubBookingsDay([this._bookings = const <Booking>[]]);

  final List<Booking> _bookings;

  @override
  Future<BookingsDayState> build(BookingsDayQuery query) async =>
      BookingsDayState(
        items: stableBookingList(_bookings),
        totalElements: _bookings.length,
      );
}

/// The `bookingsDayProvider` override: every day resolves to [bookings]
/// (default: none). Typed [Object] to match the `<Object>[...].cast()`
/// override lists the schedule tests use.
Object stubBookingsDayOverride([List<Booking> bookings = const <Booking>[]]) =>
    bookingsDayProvider.overrideWith2((_) => StubBookingsDay(bookings));
