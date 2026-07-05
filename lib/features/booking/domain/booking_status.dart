// Phase 14.0 — Client booking data foundation: [BookingStatus].
//
// Mirrors the backend booking state machine 1:1 (see `ARCHITECTURE-mobile.md`
// § "Booking state machine" / CLAUDE.md "Domain Rules"):
//   PENDING → CONFIRMED → COMPLETED (review allowed)
//   PENDING → DECLINED
//   CONFIRMED → CANCELLED
//   CONFIRMED → NOT_COMPLETED
//
// [fromWire] decodes the wire status string carried by `BookingDetailResponse
// .status` (and the raw `status` query param the repository sends back for
// `GET /bookings/me`). [wireValue] is the inverse — used by the repository to
// serialise a status filter back onto the wire.
//
// Pure Dart: no Flutter imports.

/// The lifecycle status of a booking, mirroring the backend state machine.
enum BookingStatus {
  pending,
  confirmed,
  completed,
  declined,
  cancelled,
  notCompleted;

  /// Decodes the backend wire status string (`BookingDetailResponse.status`,
  /// e.g. `"PENDING"`) into a [BookingStatus].
  ///
  /// Throws [ArgumentError] on an unrecognised value — a new backend status
  /// value must be a deliberate client-side decision, not a silent fallback,
  /// since a booking's status directly drives which actions (cancel,
  /// reschedule, review) the UI offers.
  static BookingStatus fromWire(String w) => switch (w) {
    'PENDING' => pending,
    'CONFIRMED' => confirmed,
    'COMPLETED' => completed,
    'DECLINED' => declined,
    'CANCELLED' => cancelled,
    'NOT_COMPLETED' => notCompleted,
    _ => throw ArgumentError('Unknown BookingStatus: $w'),
  };

  /// The exact backend wire string for this status (the inverse of
  /// [fromWire]). Used when the repository forwards a status filter to
  /// `GET /bookings/me?status=...`.
  String get wireValue => switch (this) {
    BookingStatus.pending => 'PENDING',
    BookingStatus.confirmed => 'CONFIRMED',
    BookingStatus.completed => 'COMPLETED',
    BookingStatus.declined => 'DECLINED',
    BookingStatus.cancelled => 'CANCELLED',
    BookingStatus.notCompleted => 'NOT_COMPLETED',
  };
}
