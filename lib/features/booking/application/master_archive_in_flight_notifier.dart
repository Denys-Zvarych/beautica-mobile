// Phase 231 — shared "a master «Архів» close-visit write is currently in
// flight" flag.
//
// Mirrors `BookingCancelInFlight` (`booking_cancel_in_flight_notifier.dart`)
// exactly, and for the same reason: `MasterArchiveScreen`'s «Виконано» row
// action opens `CompleteBookingDialog` and then writes
// `completeBooking`/`completeAppointment`. Without a guard, a double-tap on a
// row fires two concurrent close flows.
//
// ## Deliberately ONE flag, not keyed per booking id
//
// Unlike a single-booking detail screen (where at most one «Завершити» CTA
// is ever visible at once), the archive list can show SEVERAL
// `awaitingClosure` rows on screen simultaneously, each with its own
// «Виконано» button. This flag is still a single shared bool, not a
// per-row/per-id map: while ANY row's close flow is in flight, EVERY row's
// button is disabled. That is a deliberate simplification, not an oversight
// — it trades "the master can close two different visits at the same
// instant" (a vanishingly rare and low-value case) for the same proven,
// simple guard shape every other close/cancel/reschedule flow in this
// feature already uses, rather than inventing a keyed variant this phase's
// scope does not call for. See `master_archive_screen.dart`'s close-flow doc
// for the full flow this guards.
//
// autoDispose (the `@riverpod` default) — the flag drops the instant nothing
// watches it (the archive screen is popped), so a stale `true` can never
// leak into a fresh visit to the screen.

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'master_archive_in_flight_notifier.g.dart';

/// Whether a master «Архів» close-visit write (dialog + `/complete` or
/// `/appointments/{id}/complete`) is currently in flight. See file header for
/// why this is ONE shared flag rather than a per-booking one.
@riverpod
class MasterArchiveInFlight extends _$MasterArchiveInFlight {
  @override
  bool build() => false;

  /// Marks a close-visit flow as in-flight.
  void begin() {
    if (ref.mounted) state = true;
  }

  /// Clears the in-flight flag (call from a `finally` so it clears on
  /// success, error, and every early short-circuit alike — dialog dismissed
  /// included).
  ///
  /// `ref.mounted`-guarded for the same reason as
  /// `BookingCancelInFlight.end` — a caller with no watcher lets this
  /// autoDispose provider self-dispose across an awaited call; writing
  /// `state` after that would throw `UnmountedRefException`.
  void end() {
    if (ref.mounted) state = false;
  }
}
