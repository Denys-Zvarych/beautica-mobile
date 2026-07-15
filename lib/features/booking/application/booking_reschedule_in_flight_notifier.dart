// Track 24.x — shared "a reschedule navigation is currently loading" flag.
//
// `startBookingReschedule` (reschedule_navigation.dart) is fire-and-forget
// (`unawaited`) and does up to two sequential GETs
// (`bookingDetailProvider` → `publicMasterProfileProvider`) before it can
// `context.push` the slot picker. During that gap the triggering button would
// otherwise be visually inert (reads as a freeze) AND a second tap could spawn
// a second overlapping chain (duplicate GETs + two stacked slot pickers).
//
// This tiny autoDispose `bool` Notifier is the single source of truth for that
// in-flight window: `startBookingReschedule` calls [begin] at the top and
// [end] in a `finally`, and every reschedule trigger watches the value to show
// a spinner / disabled state (and to skip re-entrant taps). autoDispose (the
// `@riverpod` default) drops the flag once no surface watches it.

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'booking_reschedule_in_flight_notifier.g.dart';

/// Whether a CLIENT booking-reschedule navigation is currently loading (the
/// up-to-two seeding GETs before the slot picker is pushed).
@riverpod
class BookingRescheduleInFlight extends _$BookingRescheduleInFlight {
  @override
  bool build() => false;

  /// Marks a reschedule navigation as in-flight.
  void begin() {
    if (ref.mounted) state = true;
  }

  /// Clears the in-flight flag (call from a `finally` so it clears on success,
  /// error, and every early short-circuit alike).
  ///
  /// `ref.mounted`-guarded: this autoDispose provider is kept alive by the
  /// watching reschedule buttons in the real app, but a caller with no watcher
  /// (e.g. a direct-drive unit test) lets it self-dispose across the seeding
  /// `await`s — writing `state` after that would throw `UnmountedRefException`.
  /// If it has been disposed, the flag is already effectively cleared.
  void end() {
    if (ref.mounted) state = false;
  }
}
