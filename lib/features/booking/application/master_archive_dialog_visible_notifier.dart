// Phase 231 audit-fix (mobile-perf/mobile-qa) — mirrors
// `booking_cancel_dialog_visible_notifier.dart` exactly, for the archive
// screen's «Виконано» close flow.
//
// `masterArchiveInFlightProvider` (`master_archive_in_flight_notifier.dart`)
// gates whether the CTA is TAPPABLE, and spans the WHOLE flow — dialog AND
// write — by design. Using that SAME flag to drive the row's
// `NeumorphicButton(loading: ...)` spinner too would keep an INDETERMINATE
// `CircularProgressIndicator` ticking for the entire, user-paced
// confirmation-dialog-open window — not a bounded network wait. Concretely,
// that ticking is what breaks `tester.pumpAndSettle()` in a widget test the
// instant the dialog opens (empirically reproduced while authoring this
// phase's own widget suite): `showDialog` mounts on the ROOT navigator, a
// DIFFERENT Navigator from the one hosting this screen, so nothing about the
// archive list's own `TickerMode` is touched by the dialog opening — the
// list stays the ACTIVE branch underneath the (non-opaque) `DialogRoute`,
// its spinner still animating, forever, from `pumpAndSettle`'s point of view.
//
// This tiny autoDispose `bool` Notifier is the distinct signal that closes
// that gap: `_confirmComplete` (`master_archive_screen.dart`) calls [begin]
// immediately before `showDialog` and [end] immediately after it returns
// (confirmed, backed out, or dismissed alike, via a `finally`). The screen
// wraps its list body in `TickerMode(enabled: !dialogVisible)`, freezing
// every ticker in that subtree — including the close button's spinner — for
// exactly the dialog-open window, and resuming it for the genuinely bounded
// post-confirm write.
//
// The re-entrancy GUARD stays entirely on `masterArchiveInFlightProvider`;
// this flag never gates tappability — see that file's own header.

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'master_archive_dialog_visible_notifier.g.dart';

/// Whether `CompleteBookingDialog` is currently on screen for the master
/// «Архів» page's close flow — see file header for why this is distinct from
/// [MasterArchiveInFlight] (`master_archive_in_flight_notifier.dart`).
@riverpod
class MasterArchiveDialogVisible extends _$MasterArchiveDialogVisible {
  @override
  bool build() => false;

  /// Marks the confirmation dialog as visible (call right before
  /// `showDialog`).
  void begin() {
    if (ref.mounted) state = true;
  }

  /// Clears the dialog-visible flag once `showDialog` resolves.
  ///
  /// `ref.mounted`-guarded for the same reason as
  /// [MasterArchiveInFlight.end] — a caller with no watcher lets this
  /// autoDispose provider self-dispose across the awaited `showDialog` call.
  void end() {
    if (ref.mounted) state = false;
  }
}
