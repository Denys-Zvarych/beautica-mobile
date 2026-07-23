// Phase 14.0 — Client booking data foundation: [BookingStatus].
//
// Mirrors the backend booking state machine 1:1 (see `ARCHITECTURE-mobile.md`
// § "Booking state machine" / CLAUDE.md "Domain Rules"):
//   CONFIRMED → COMPLETED (review allowed)
//   CONFIRMED → CANCELLED   (client-initiated)
//   CONFIRMED → DECLINED    (provider-initiated)
//   CONFIRMED → NOT_COMPLETED (no-show)
//
// PENDING is GONE (Phase 7.1, folding in the retired Phase 7.4). Track 24.x
// made booking creation auto-confirm, so the backend enum has exactly the five
// values above and `"PENDING"` can no longer appear on the wire. The dead
// member was still being pattern-matched in four presentation files, where it
// silently doubled as "confirmed" — a decoy branch that made the real
// confirmed-booking logic look like it had a second entry point.
//
// [fromWire] decodes the wire status string carried by `BookingDetailResponse
// .status`. [wireValue] is the inverse — used by the repository to serialise a
// status filter back onto the wire.
//
// Pure Dart: no Flutter imports.

import 'dart:developer';

/// `package:flutter/foundation.dart`'s `kDebugMode`, restated in pure Dart.
///
/// This file is a DOMAIN file — "Pure Dart: no Flutter imports" (see the
/// header), and that invariant is worth more than the convenience import.
/// This is Flutter's own definition verbatim (`!kReleaseMode && !kProfileMode`,
/// both of which are themselves just these `dart.vm.*` environment constants),
/// so it is const-folded away by the AOT compiler identically.
const bool _kDebugMode =
    !bool.fromEnvironment('dart.vm.product') &&
    !bool.fromEnvironment('dart.vm.profile');

/// The lifecycle status of a booking, mirroring the backend state machine.
///
/// Declaration order is load-bearing: `MasterBookingsQuery` canonicalises a
/// status filter by `index`, so reordering these members changes the emitted
/// query-param order (harmless on the wire, but it will move the URL
/// assertions in `booking_repository_test.dart`). [unknown] is deliberately
/// LAST so adding it left every existing member's index untouched.
enum BookingStatus {
  confirmed,
  completed,
  declined,
  cancelled,
  notCompleted,

  /// A wire value this build does not recognise — see [fromWire].
  ///
  /// NOT a backend state. It exists so an unrecognised status can be carried
  /// through the domain as *itself* rather than being laundered into a real
  /// status, and so the compiler forces every `switch` over [BookingStatus]
  /// to make a deliberate decision about it.
  ///
  /// Its contract everywhere: **grant nothing**. Neutral badge, no subline,
  /// rebook-only actions, no add-to-calendar, no reschedule, no cancel, and
  /// never a member of any tab's or filter's status set. A row in this state
  /// is *visible* (the master can see it and tap through to a detail screen
  /// that re-fetches) but confers no capability.
  unknown;

  /// The statuses a client may actually FILTER on — every real backend state,
  /// excluding [unknown].
  ///
  /// [unknown] is a decode-only member: sending `status=UNKNOWN` would be a
  /// 400 from the backend, whose `@Size(max = 5)` cap is sized to exactly this
  /// list. Filter chips and status-set literals must enumerate this, never
  /// `BookingStatus.values`.
  static const List<BookingStatus> filterable = <BookingStatus>[
    confirmed,
    completed,
    declined,
    cancelled,
    notCompleted,
  ];

  /// Decodes the backend wire status string (`BookingDetailResponse.status`,
  /// e.g. `"CONFIRMED"`) into a [BookingStatus].
  ///
  /// An unrecognised value decodes to [unknown] and logs, rather than throwing.
  ///
  /// ## Why not throw (Phase 7.1)
  ///
  /// The original contract threw, and the throw was caught by
  /// `BookingMapper.fromDtoList`'s `on Failure { continue; }` loop, which
  /// DROPPED the offending row — a list never crashed, but a booking in an
  /// unknown status silently VANISHED from the master's «Мої записи». A
  /// dropped row is invisible and unrecoverable, and the master could no-show
  /// a client over it. So the row is kept.
  ///
  /// ## Why not fall back to [confirmed] (security S1, reversing the first cut)
  ///
  /// The first Phase 7.1 cut kept the row by relabelling it CONFIRMED. That
  /// fails open onto the single most privileged member of this enum: CONFIRMED
  /// is what unlocks reschedule, cancel, `BookingTab.upcoming` membership and
  /// — the one that actually bites — [BookingDisplayX.canAddToCalendar]. The
  /// "worst case is a 409 from the server" defence does not cover
  /// add-to-calendar: it is a purely LOCAL action with no server round-trip,
  /// so an unknown-status booking would be written into the device calendar
  /// (world-readable to any app holding `READ_CALENDAR`) as a live
  /// appointment.
  ///
  /// [unknown] keeps the row AND grants nothing, which is the property the
  /// original throw actually bought — a new backend status must be a
  /// deliberate decision here, enforced by every exhaustive `switch` failing
  /// to compile until it is handled — without paying for it in dropped rows.
  /// Keep this mapping current whenever the backend enum grows.
  static BookingStatus fromWire(String w) => switch (w) {
    'CONFIRMED' => confirmed,
    'COMPLETED' => completed,
    'DECLINED' => declined,
    'CANCELLED' => cancelled,
    'NOT_COMPLETED' => notCompleted,
    _ => _unknown(w),
  };

  static BookingStatus _unknown(String w) {
    // kDebugMode-gated to match every sibling log in this layer
    // (`booking_mapper.dart`, `booking_repository.dart`) — security S2. This
    // fires once PER ROW, so an ungated version emitted 20 identical release
    // log lines for a single page of a list.
    if (_kDebugMode) {
      log(
        'Unknown BookingStatus "$w" — decoded as BookingStatus.unknown. '
        'The backend enum has likely gained a member; add it here.',
        name: 'feature.booking.status',
        level: 900,
      );
    }
    return unknown;
  }

  /// The exact backend wire string for this status (the inverse of
  /// [fromWire]). Used when the repository forwards a status filter to
  /// `GET /bookings/me?status=...`.
  ///
  /// [unknown] has no wire representation — it is a decode-only member. It
  /// yields `'UNKNOWN'`, which the backend would reject with a 400, and the
  /// repository strips it from the status filter before serialising precisely
  /// so that never happens. Build filter sets from [filterable], not
  /// [values], and this value is unreachable.
  String get wireValue => switch (this) {
    BookingStatus.confirmed => 'CONFIRMED',
    BookingStatus.completed => 'COMPLETED',
    BookingStatus.declined => 'DECLINED',
    BookingStatus.cancelled => 'CANCELLED',
    BookingStatus.notCompleted => 'NOT_COMPLETED',
    BookingStatus.unknown => 'UNKNOWN',
  };
}
