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
// ## [history] (added for the master «Архів» HISTORY cutover) — a UNION
// view, and a HARDER backend-version requirement than the other four members
//
// `HISTORY` was added server-side in `beautica-backend` `81e8166`
// (`feat/booking-partition-history`) as `PAST ∪ CANCELLED` — i.e.
// `COMPLETED ∪ NOT_COMPLETED ∪ (CONFIRMED AND ends_at < now) ∪ CANCELLED ∪
// DECLINED`, equivalently "everything except UPCOMING". Like
// `AWAITING_CLOSURE`, it is deliberately NOT a member of the backend's
// disjoint `COVER` partition family — both are overlapping VIEWS composed
// from the four disjoint members, not a fifth disjoint bucket.
//
// ⚠ HARD SEQUENCING HAZARD: unlike rolling out a NEW query-parameter NAME
// (the Phase 227 valve, where an unrecognised param NAME is silently DROPPED
// by Spring and the request degrades to whatever other params it carries),
// `partition` is an EXISTING, KNOWN param name binding to a typed
// `BookingPartition` enum server-side
// (`@RequestParam(required = false) BookingPartition partition`). Sending a
// VALUE the enum doesn't recognise — `HISTORY` against any backend older
// than `81e8166` — is a conversion failure, not a silent drop: Spring raises
// `MethodArgumentTypeMismatchException`, which surfaces to the client as an
// HTTP 400. There is no graceful degrade for [history] the way there is for
// the other four members against a wholly partition-unaware backend (via the
// legacy `status` fallback — see `MasterArchiveNotifier`'s doc). A caller
// sending [history] hard-requires a HISTORY-capable backend; do not assume
// the additive-rollout safety valve protects this member the way it protects
// the rest of this enum.
//
// Pure Dart: no Flutter imports.

/// The backend's Phase 28.2/29.3/HISTORY-rollout time-based partition for
/// `GET /bookings/me`, mirroring the backend's inline query-parameter enum
/// `[UPCOMING, PAST, CANCELLED, AWAITING_CLOSURE, HISTORY]`.
///
/// When present, the backend applies this filter and silently IGNORES any
/// `status` params on the same request (see
/// `BookingRepository.getMyBookings`'s doc for the full precedence rule).
/// [wireValue] is the sole serialisation path onto the wire — always go
/// through it, never `.name` or `.toString()`.
///
/// See the file header for [history]'s union semantics and the HARD
/// SEQUENCING HAZARD it carries that the other four members do not.
enum BookingPartition {
  upcoming,
  past,
  cancelled,
  awaitingClosure,
  history;

  /// The exact backend wire string for this partition (the enum's sole
  /// serialisation path — see the class doc for why there is no inverse
  /// `fromWire`).
  String get wireValue => switch (this) {
    BookingPartition.upcoming => 'UPCOMING',
    BookingPartition.past => 'PAST',
    BookingPartition.cancelled => 'CANCELLED',
    BookingPartition.awaitingClosure => 'AWAITING_CLOSURE',
    BookingPartition.history => 'HISTORY',
  };
}
