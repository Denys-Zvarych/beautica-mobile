// Audit LOW-4 (2026-09-20, user-directed) — the deferral slot that lets
// `booking_calendar_invalidation.dart` SKIP the salon board's share of the
// booking-created fan-out while the board's tab is not the selected one,
// without ever losing the refresh.
//
// ## Why a deferral slot and not a listener change
//
// `salon_shell_screen.dart` hosts the board in a plain `IndexedStack`, which
// sets neither `Offstage` nor `TickerMode` on its non-current children, so the
// board's `Consumer`s stay ACTIVE while the owner stands on another tab and
// every `ref.invalidate` aimed at them refetches against the backend's per-user
// 60/min budget with nothing on screen.
//
// The obvious-looking fix — hand the board a `visible:` flag and drop the watch
// when it is false — is the documented Riverpod 3 footgun and is NOT what this
// does: an autoDispose provider invalidated while only PAUSED listeners remain
// is DISPOSED outright rather than refreshed, and `invalidate` retains `.value`
// so nothing downstream can gate on `value == null` to notice the loss. This
// gate changes NO listener state at all. The board stays subscribed, active and
// unpaused exactly as it is today; only the DISPATCH of the invalidation moves.
//
// ## The contract
//
// Skipping an invalidation is only safe if it is replayed. A skipped fan-out
// therefore [markStale]s the salon here, and `SalonShellScreen._onNavSelected`
// [drainSalonBoardRefresh]s it the moment «Записи» becomes the selected tab —
// so the board is exactly as correct on return as it is today, one refetch
// later rather than one refetch earlier.
//
// `keepAlive` deliberately: the flag has to outlive the shell state that set
// the tab, and it is a bounded `Set<String>` of salon ids (one entry per salon
// the owner can even reach), never a cache.

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'salon_board_refresh_gate.g.dart';

/// Records salons whose «Записи» board has a booking-created refresh owed to
/// it because the fan-out fired while the board's tab was not selected.
///
/// Mutable-object-behind-a-provider, matching `DayKeepAliveLru`'s precedent in
/// this same feature (REUSE-FIRST — same shape, same reason): the state is a
/// bookkeeping set nothing rebuilds on, so publishing it as `Notifier` state
/// would rebuild listeners for a value no widget reads.
final class SalonBoardRefreshGate {
  final Set<String> _stale = <String>{};

  /// Whether [salonId]'s board is owed a deferred refresh. Read-only — the
  /// drain path uses [takeStale], which is the same question plus the clear.
  bool isStale(String salonId) => _stale.contains(salonId);

  /// Records that [salonId]'s board missed an invalidation.
  void markStale(String salonId) => _stale.add(salonId);

  /// Returns whether [salonId] was stale and clears the flag in one step, so
  /// two drains in a row cannot replay the same refresh twice.
  bool takeStale(String salonId) => _stale.remove(salonId);
}

/// The app-wide [SalonBoardRefreshGate].
@Riverpod(keepAlive: true)
SalonBoardRefreshGate salonBoardRefreshGate(Ref ref) => SalonBoardRefreshGate();
