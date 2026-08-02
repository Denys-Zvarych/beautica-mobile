// Phase 225 audit-fix cycle 3 (mobile-perf LOW) — gates whether a cancel
// CTA's indeterminate spinner is actually TICKING, as opposed to
// `bookingCancelInFlightProvider` (booking_cancel_in_flight_notifier.dart)
// which gates whether the CTA is TAPPABLE.
//
// `bookingCancelInFlightProvider` spans the WHOLE cancel flow — load, confirm
// dialog, and the `cancelBooking` write — by design (cycle 2's security fix
// for the re-entrancy gap around the write). That flag is exactly right for
// disabling the CTA the whole time, but using it to drive a spinner's
// ANIMATION too would mean the spinner keeps ticking for as long as the
// confirmation dialog is open, which is a user-paced, unbounded duration —
// not a bounded network window.
//
// Why the existing offstage-pause machinery (`StatefulShellRoute.indexedStack`
// wrapping inactive branches in `TickerMode(enabled: false)`) does not cover
// this: `CancelBookingDialog` opens via `showDialog`, which defaults to
// `useRootNavigator: true` — it mounts on the ROOT Navigator, a different
// Navigator from the one hosting the branch underneath it. That branch stays
// the ACTIVE branch the whole time; it is merely visually covered by a
// non-opaque `DialogRoute` layered on top. Nothing about that disables the
// branch's `TickerMode`.
//
// This tiny autoDispose `bool` Notifier is the distinct signal that closes
// that gap: `startBookingCancel` calls [begin] immediately before
// `showCancelBookingDialog` and [end] immediately after it returns (success
// or backed-out alike, via a `finally`) — see `booking_cancel_navigation.dart`.
// A spinner-bearing consumer wraps its spinner in
// `TickerMode(enabled: !dialogVisible)` so the ticker freezes for exactly the
// dialog-open window and resumes for the pre-dialog load and the post-confirm
// write — the two genuinely bounded windows where an animating spinner is
// informative rather than a hidden, indeterminate battery/CPU cost behind an
// opaque modal barrier.
//
// That consumer used to be the Home Hub's inline «Скасувати» button
// (`HubOutlineButton`'s `spinnerPaused` param). The Home Hub now renders the
// shared, cancel-button-less `BookingCard` instead (its one affordance is
// tap-through to «Деталі запису»), and `startBookingCancel`'s sole remaining
// caller — `booking_detail_screen.dart`'s «Скасувати запис» CTA
// (`_DestructiveSecondaryButton`) — renders no spinner of its own. So this
// flag currently toggles true/false around the dialog-open window with no
// live UI reader; it is kept (not deleted) because `startBookingCancel` is a
// shared, surface-agnostic helper and a future spinner-bearing cancel CTA is
// exactly the case this Notifier exists to serve.
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
