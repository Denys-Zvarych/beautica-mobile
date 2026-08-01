// Phase 225 audit-fix cycle 3 (mobile-perf LOW) — gates whether the Home
// Hub cancel button's indeterminate spinner is actually TICKING, as opposed
// to `bookingCancelInFlightProvider` (booking_cancel_in_flight_notifier.dart)
// which gates whether the button is TAPPABLE.
//
// `bookingCancelInFlightProvider` spans the WHOLE cancel flow — load, confirm
// dialog, and the `cancelBooking` write — by design (cycle 2's security fix
// for the re-entrancy gap around the write). That flag is exactly right for
// disabling the button the whole time, but using it to drive the spinner's
// ANIMATION too means the spinner keeps ticking for as long as the
// confirmation dialog is open, which is a user-paced, unbounded duration —
// not a bounded network window.
//
// Why the existing offstage-pause machinery (`StatefulShellRoute.indexedStack`
// wrapping inactive branches in `TickerMode(enabled: false)`) does not cover
// this: `CancelBookingDialog` opens via `showDialog`, which defaults to
// `useRootNavigator: true` — it mounts on the ROOT Navigator, a different
// Navigator from the one hosting the Home Hub branch underneath it. The Home
// Hub branch stays the ACTIVE branch the whole time; it is merely visually
// covered by a non-opaque `DialogRoute` layered on top. Nothing about that
// disables the branch's `TickerMode`.
//
// This tiny autoDispose `bool` Notifier is the distinct signal that closes
// that gap: `startBookingCancel` calls [begin] immediately before
// `showCancelBookingDialog` and [end] immediately after it returns (success
// or backed-out alike, via a `finally`) — see `booking_cancel_navigation.dart`.
// `HubOutlineButton` wraps its spinner in `TickerMode(enabled: !dialogVisible)`
// so the ticker freezes for exactly the dialog-open window and resumes for
// the pre-dialog load and the post-confirm write — the two genuinely bounded
// windows where an animating spinner is informative rather than a hidden,
// indeterminate battery/CPU cost behind an opaque modal barrier.
//
// The re-entrancy GUARD stays entirely on `bookingCancelInFlightProvider`;
// this flag never gates tappability — see that file's own header for why
// weakening the guard is not an option.

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'booking_cancel_dialog_visible_notifier.g.dart';

/// Whether `CancelBookingDialog` (the CLIENT booking-cancel confirmation) is
/// currently on screen — see file header for why this is distinct from
/// [BookingCancelInFlight].
@riverpod
class BookingCancelDialogVisible extends _$BookingCancelDialogVisible {
  @override
  bool build() => false;

  /// Marks the confirmation dialog as visible (call right before
  /// `showCancelBookingDialog`).
  void begin() {
    if (ref.mounted) state = true;
  }

  /// Clears the dialog-visible flag once `showDialog` resolves.
  ///
  /// `ref.mounted`-guarded for the same reason as
  /// [BookingCancelInFlight.end] — a caller with no watcher lets this
  /// autoDispose provider self-dispose across the awaited `showDialog` call.
  void end() {
    if (ref.mounted) state = false;
  }
}
