// Shared time-anchor helper for booking fixtures.
//
// THE BUG THIS PREVENTS
// ----------------------
// `BookingDisplayX.isPast` (lib/features/booking/domain/booking_display_x
// .dart) reads the REAL wall clock (`DateTime.now()`), so any booking
// fixture that wants to look "upcoming" (reschedule/cancel/add-to-calendar
// visible, the forward-looking subline, etc.) must have a `startAt`/`endAt`
// that is actually in the future AT TEST-RUN TIME — not at the time the test
// was written. An absolute literal like `DateTime.utc(2026, 7, 20, 15)`
// passes today and silently becomes a false negative the instant that clock
// tick elapses: the suite goes red on a DATE, not a code change. That
// happened for real on 2026-07-20 across four booking-detail specs, each of
// which had independently hand-rolled the same expired literal.
//
// THE FIX
// -------
// Anchor "upcoming" fixtures to `DateTime.now()` plus a generous offset, so
// the instant is always in the future no matter when the suite runs. Use
// this helper instead of a hand-rolled literal so the fix lives in one place.
//
// A fixed PAST literal (e.g. `DateTime.utc(2000, 1, 1)`) is a different,
// SAFE case — it can never become "upcoming" again — and is not what this
// helper is for.
//
// Guarded by `scripts/forbid_stale_future_date_fixture.sh`.

/// A `DateTime` comfortably in the future relative to the real wall clock,
/// suitable as a booking's `startAt` in any fixture that needs the booking to
/// read as "upcoming" (i.e. `BookingDisplayX.isPast` must be `false`).
///
/// [durationMinutes] should match the fixture's own booking duration so
/// `startAt + duration` (the `endAt` the gate actually compares against)
/// stays in the future too; it defaults to a booking-day-scale offset that
/// comfortably outlives any realistic service duration.
DateTime futureBookingStart({Duration aheadOfNow = const Duration(days: 30)}) =>
    DateTime.now().toUtc().add(aheadOfNow);
