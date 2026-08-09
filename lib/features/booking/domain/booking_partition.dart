// Phase 226 (audit-fix cycle 1) — [BookingPartition]: typed domain enum for
// the backend's Phase 28.2/29.3 time-based `partition` query param on
// `GET /bookings/me`.
//
// The backend declares `partition` as an inline
// `enum: [UPCOMING, PAST, CANCELLED, AWAITING_CLOSURE]` directly on the query
// parameter (no `$ref`), so the OpenAPI generator emits a plain `String?`
// rather than a generated `EnumClass`. `BookingRepository.getMyBookings` /
// `HttpBookingRepository.getMyBookings` originally mirrored that raw
// `String?` — but the backend's documented precedence rule is that when
// `partition` is present it OVERRIDES `status` entirely, and an UNKNOWN
// `partition` value is silently DROPPED by Spring, degrading the request to
// `status`-only filtering. That fallback is a deliberate backend rollout
// safety valve, but it is only safe if the client can *only* ever send one
// of these four literals — a free-form `String?` lets a typo silently return
// the wrong result set with no error and no signal. This enum closes that
// gap: the compiler, not string discipline, now guarantees only a known
// literal ever reaches the wire.
//
// Unlike `BookingStatus` (see `booking_status.dart`), this enum has neither
// an `unknown` member nor a `fromWire` decoder. `partition` is a
// REQUEST-only parameter — the backend never echoes it back on any response
// body — so there is no "unrecognised wire value arrived and must be kept
// without granting capability" case to defend against. The client fully
// constructs every value it sends, so [values] is already exhaustive; only
// the outbound [wireValue] direction is needed.
//
// **No caller constructs this yet** (Phase 226) — wired through
// `BookingRepository.getMyBookings`'s signature so the typed-enum
// serialisation boundary lands as its own reviewable diff ahead of Phase
// 227, which is the actual cutover that starts passing a value.
//
// Pure Dart: no Flutter imports.

/// The backend's Phase 28.2/29.3 time-based partition for
/// `GET /bookings/me`, mirroring the backend's inline query-parameter enum
/// `[UPCOMING, PAST, CANCELLED, AWAITING_CLOSURE]`.
///
/// When present, the backend applies this filter and silently IGNORES any
/// `status` params on the same request (see
/// `BookingRepository.getMyBookings`'s doc for the full precedence rule).
/// [wireValue] is the sole serialisation path onto the wire — always go
/// through it, never `.name` or `.toString()`.
enum BookingPartition {
  upcoming,
  past,
  cancelled,
  awaitingClosure;

  /// The exact backend wire string for this partition (the enum's sole
  /// serialisation path — see the class doc for why there is no inverse
  /// `fromWire`).
  String get wireValue => switch (this) {
    BookingPartition.upcoming => 'UPCOMING',
    BookingPartition.past => 'PAST',
    BookingPartition.cancelled => 'CANCELLED',
    BookingPartition.awaitingClosure => 'AWAITING_CLOSURE',
  };
}
