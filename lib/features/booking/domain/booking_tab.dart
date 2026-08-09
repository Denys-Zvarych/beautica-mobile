// Phase 14.3 — My Bookings tab partition.
//
// Mirrors the approved preview's `BookingTab` (`docs/signup-designs/
// MyBookings/lib/screens/my_bookings_data.dart`) 1:1. Three tabs, reflecting
// the backend track 24.x model (booking auto-confirm — `PENDING` retired,
// every booking is created `CONFIRMED` directly with no provider-approval
// step):
//
//   * Майбутні  — CONFIRMED only (a single-status tab now).
//   * Минулі    — COMPLETED + NOT_COMPLETED.
//   * Скасовані — CANCELLED + DECLINED. Both share the tab, but the card and
//     detail screen must render them distinctly — `CANCELLED` = the client
//     backed out ("ви скасували"); `DECLINED` = the provider backed out
//     ("салон/майстер скасував"). See `BookingStatusVisual`.
//
// Phase 227 — «Мої записи» cutover to the backend's server-side `partition`
// (Phase 28.2/29.3). [BookingTabX.partition] maps each of the three tabs to
// its [BookingPartition]; [statuses] below is UNTOUCHED — it stays exactly
// what it was, because its only remaining job is the Phase 227 rollout
// safety valve: [MyBookingsNotifier] now sends BOTH `partition` and `status`
// on every request. When the backend has Phase 28.2, `partition` wins and
// `status` is ignored server-side; when it does not (a Railway deploy lag, a
// stale environment), Spring silently drops the unrecognised `partition` key
// and `status` alone still filters — degrading to exactly pre-227 behaviour
// instead of returning the caller's entire unfiltered history. See
// `BookingRepository.getMyBookings`'s doc for the full precedence contract.
//
// Pure Dart — no Flutter imports.

import 'booking_partition.dart';
import 'booking_status.dart';

/// Which tab of «МОЇ ЗАПИСИ» a booking belongs to.
enum BookingTab { upcoming, past, cancelled }

extension BookingTabX on BookingTab {
  /// The LEGACY status partition sent to the backend alongside [partition]
  /// (Phase 227 rollout safety valve — see the file header). Do NOT "fix" or
  /// "improve" this to include elapsed `CONFIRMED` rows or otherwise mirror
  /// [partition]'s semantics: its only job now is to reproduce EXACTLY the
  /// pre-227 filtering an old backend without `partition` support would still
  /// apply. [MyBookingsNotifier] issues a single `getMyBookings` call per tab
  /// with this whole set as one multi-value `status` query param — the
  /// backend unions and paginates server-side (track 26.1), no per-status
  /// fan-out. Insertion order is deliberate: it keeps the query param order
  /// (and thus the request) deterministic across rebuilds and reproducible in
  /// tests.
  Set<BookingStatus> get statuses => switch (this) {
    BookingTab.upcoming => const <BookingStatus>{BookingStatus.confirmed},
    BookingTab.past => const <BookingStatus>{
      BookingStatus.completed,
      BookingStatus.notCompleted,
    },
    BookingTab.cancelled => const <BookingStatus>{
      BookingStatus.cancelled,
      BookingStatus.declined,
    },
  };

  /// The Phase 28.2/29.3 server-side time-based partition for this tab —
  /// the headline Phase 227 behaviour fix. Unlike [statuses] (a fixed status
  /// SET), the backend derives partition membership from elapsed time at
  /// READ time, so an elapsed `CONFIRMED` booking that [statuses] would keep
  /// in Майбутні forever lands under [BookingPartition.past] here instead —
  /// that reclassification is the whole point of this cutover.
  ///
  /// Total over the three [BookingTab] members. [BookingPartition
  /// .awaitingClosure] has NO tab of its own — it is a provider-facing
  /// subset of Минулі/PAST (mobile phase 229's needs-closure queue, not the
  /// client's tab bar), so it is deliberately unreachable from this getter;
  /// inventing a fourth tab to reach it would be wrong.
  BookingPartition get partition => switch (this) {
    BookingTab.upcoming => BookingPartition.upcoming,
    BookingTab.past => BookingPartition.past,
    BookingTab.cancelled => BookingPartition.cancelled,
  };
}
