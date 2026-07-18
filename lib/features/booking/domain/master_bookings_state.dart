// Phase 7.1 — MasterBookingsState: the accumulated page window for the
// independent master's «Мої записи» list.
//
// ## Why not reuse `MyBookingsState`
//
// The shipped client-side `MyBookingsState` (`application/my_bookings_notifier
// .dart`) carries the same four paging fields and was the obvious candidate.
// It is deliberately NOT reused:
//
//   1. The master's toolbar renders a total count («N записів») straight from
//      the server's `totalElements`. `MyBookingsState` has no such field, and
//      widening a shipped, tested client type to serve a master-only need
//      would make one screen's state shape a hostage to the other's.
//   2. `MyBookingsState` is a hand-written `@immutable` class, not freezed —
//      extending it means hand-maintaining `==`/`hashCode`/`copyWith` for a
//      field the client never reads.
//
// Two small parallel state types are cheaper than one coupled one here. The
// paging SEMANTICS are intentionally identical, so the two notifiers stay
// diff-readable against each other.

import 'package:freezed_annotation/freezed_annotation.dart';

import 'booking.dart';

part 'master_bookings_state.freezed.dart';

/// An immutable snapshot of the master's booking list: the pages accumulated
/// so far plus the cursor needed to ask for the next one.
@freezed
abstract class MasterBookingsState with _$MasterBookingsState {
  const factory MasterBookingsState({
    /// The bookings accumulated so far, in **server order**. Rendered
    /// directly — never re-sorted client-side (see [MasterBookingsNotifier]).
    required List<Booking> items,

    /// Zero-based index of the last fetched page.
    required int page,

    /// Whether a subsequent page exists.
    required bool hasMore,

    /// Total matching bookings across ALL pages, as reported by the server.
    /// Drives the toolbar's «N записів» count, which must reflect the whole
    /// filtered result set — NOT `items.length`, which is only what has been
    /// paged in so far.
    required int totalElements,

    /// Whether a [MasterBookingsNotifier.loadMore] fetch is in flight. Drives
    /// the footer spinner without flipping the provider to `AsyncLoading`
    /// (which would blank the list).
    @Default(false) bool isLoadingMore,
  }) = _MasterBookingsState;

  const MasterBookingsState._();

  /// `true` when the server matched nothing at all — the empty-state gate.
  /// Distinct from "this page is empty", which can also happen on a
  /// past-the-end page.
  bool get isEmpty => totalElements == 0 && items.isEmpty;
}
