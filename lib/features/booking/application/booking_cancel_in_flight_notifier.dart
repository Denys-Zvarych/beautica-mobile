// Phase 225 fix pass (mobile-perf MEDIUM) — shared "a booking-cancel
// navigation is currently loading" flag.
//
// Mirrors `BookingRescheduleInFlight` (booking_reschedule_in_flight_notifier
// .dart) exactly, for the same reason: `startBookingCancel`
// (booking_cancel_navigation.dart) awaits `bookingDetailProvider(id).future`
// before it can even show the confirmation dialog. On the «Деталі запису»
// screen that provider is already watched/cached so the await is instant —
// but the Home Hub «Найближчий запис» card only carries a bare booking id, so
// there this is a genuine network round trip with no visible feedback. Without
// a guard, a double-tap on «Скасувати» over a slow network fires two
// concurrent `startBookingCancel` calls, stacking two confirmation dialogs and
// potentially two `cancelBooking` writes for the same booking.
//
// This tiny autoDispose `bool` Notifier is the single source of truth for
// that in-flight window: `startBookingCancel` calls [begin] at the top (after
// the re-entrancy check) and [end] in a `finally` so it clears on success,
// error, AND every early short-circuit (booking failed to load, user backed
// out of the dialog, cancelBooking failed). Every cancel trigger watches the
// value to show a spinner/disabled state — and, just like the reschedule
// flag, `startBookingCancel` itself reads it FIRST to skip re-entrant taps
// outright rather than relying on the UI alone to grey the button out.
// autoDispose (the `@riverpod` default) drops the flag once no surface
// watches it.

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'booking_cancel_in_flight_notifier.g.dart';

/// Whether a CLIENT booking-cancel navigation is currently loading (the
/// booking-detail GET that runs before the confirmation dialog can show).
@riverpod
class BookingCancelInFlight extends _$BookingCancelInFlight {
  @override
  bool build() => false;

  /// Marks a cancel navigation as in-flight.
  void begin() {
    if (ref.mounted) state = true;
  }

  /// Clears the in-flight flag (call from a `finally` so it clears on
  /// success, error, and every early short-circuit alike).
  ///
  /// `ref.mounted`-guarded: this autoDispose provider is kept alive by the
  /// watching cancel buttons in the real app, but a caller with no watcher
  /// (e.g. a direct-drive unit test) lets it self-dispose across the seeding
  /// `await`s — writing `state` after that would throw `UnmountedRefException`.
  /// If it has been disposed, the flag is already effectively cleared.
  void end() {
    if (ref.mounted) state = false;
  }
}
