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
// Pure Dart — no Flutter imports.

import 'booking_status.dart';

/// Which tab of «МОЇ ЗАПИСИ» a booking belongs to.
enum BookingTab { upcoming, past, cancelled }

extension BookingTabX on BookingTab {
  /// The status partition sent to the backend. [MyBookingsNotifier] issues a
  /// single `getMyBookings` call per tab with this whole set as one
  /// multi-value `status` query param — the backend unions and paginates
  /// server-side (track 26.1), no per-status fan-out. Insertion order is
  /// deliberate: it keeps the query param order (and thus the request)
  /// deterministic across rebuilds and reproducible in tests.
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
}
