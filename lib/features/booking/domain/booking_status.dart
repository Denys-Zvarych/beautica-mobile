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

  /// The statuses a PROVIDER's own day list hides unless the master ticks
  /// «Скасовані» in the filter sheet (locked product decision, 2026-08-13).
  ///
  /// Both members, never one: [declined] (provider-initiated) and [cancelled]
  /// (client-initiated) render the identical «Скасовано» badge app-wide (the
  /// who-cancelled distinction was collapsed 2026-07-15) and
  /// `BookingStatusFilterGroup.cancelled` already selects them as ONE row, so
  /// they must hide and re-appear together or the filter row becomes a lie.
  ///
  /// [notCompleted] is deliberately ABSENT: a no-show is the master's own
  /// record of a client who did not turn up and it feeds the two-sided client
  /// rating. It stays visible.
  static const Set<BookingStatus> hiddenFromDayListByDefault = <BookingStatus>{
    declined,
    cancelled,
  };

  /// [filterable] minus [hiddenFromDayListByDefault] — the wire status set the
  /// provider's day list sends when the master has selected NO status group.
  ///
  /// ## Why the wire carries an inclusion list at all
  ///
  /// `GET /bookings/me` has no "exclude" parameter, so hiding two statuses
  /// means naming the other three. Doing it on the WIRE rather than dropping
  /// rows after the fetch is load-bearing: `BookingsDayNotifier` fetches a day
  /// in ONE `size: 100` request with no paging, so cancelled bookings spending
  /// that budget could silently truncate the live ones the master came to see.
  ///
  /// ## DERIVED from [filterable], never hand-listed
  ///
  /// Adding a member to [filterable] — already the documented obligation for
  /// any new backend status — is enough to keep this set current. A
  /// hand-written `{confirmed, completed, notCompleted}` literal would keep
  /// excluding a newly-added status forever, silently.
  ///
  /// ## Being derived does NOT make a future status reachable here
  ///
  /// This is an INCLUSION list, and the DEFAULT one at that. A build that
  /// predates a new backend status cannot name it, so the server's
  /// `status IN (...)` predicate drops it from this list — and the backend
  /// ships before the client, so that is the NORMAL order of events, not an
  /// edge case. `fromWire`'s header spells out why a silently-dropped row is
  /// the worst outcome on this screen ("the master could no-show a client over
  /// it"); this set alone does not buy that back.
  ///
  /// What buys it back is [dayListWireStatuses]: ticking every filter group
  /// resolves to the EMPTY set, which omits `status` from the request
  /// entirely, so a status this build has never heard of is still reachable —
  /// through one deliberate user action rather than by default. See that
  /// method's doc.
  ///
  /// The backend's `@Size(max = 5)` cap is sized to [filterable] exactly, so
  /// this subset can never exceed it.
  static final Set<BookingStatus> visibleInDayListByDefault =
      Set<BookingStatus>.unmodifiable(
        filterable.where(
          (BookingStatus s) => !hiddenFromDayListByDefault.contains(s),
        ),
      );

  /// Resolves the provider day list's USER status selection into the set that
  /// actually goes on the WIRE.
  ///
  /// The ONE definition of that mapping. `BookingsDayQuery.dayList` is its only
  /// caller, and every day-list query — the live one `BookingsDiscoveryView`
  /// watches AND the ones post-write invalidation targets — is built through
  /// that factory, so the three call sites cannot drift apart. (They did: the
  /// two invalidation sites kept building the plain, empty-status member while
  /// the screen had moved to the default-visible one, so nothing invalidated
  /// what the screen actually read.)
  ///
  /// Three cases:
  ///
  ///   * [selected] is EMPTY — the master chose nothing → resolves to
  ///     [visibleInDayListByDefault] (CANCELLED/DECLINED hidden, locked
  ///     2026-08-13).
  ///   * [selected] covers ALL of [maximal] — "show me everything" →
  ///     resolves to the EMPTY set, which `BookingRepository.getMyBookings`
  ///     serialises by OMITTING `status` from the request entirely. Naming
  ///     every status THIS build knows would make even the maximal filter an
  ///     inclusion list, leaving a status the backend gained after this build
  ///     shipped unreachable through every filter combination — re-introducing
  ///     at the wire the exact silent drop [fromWire] exists to prevent. Such a
  ///     row decodes to [unknown] and is rendered inert, which is the intended
  ///     outcome; being invisible is not.
  ///   * anything else — honoured verbatim, so ticking «Скасовані» sends
  ///     exactly `{CANCELLED, DECLINED}` (REPLACE, never union with the
  ///     default).
  ///
  /// ## [maximal] — mobile-security LOW-1 (2026-08-13), generalised
  ///
  /// [maximal] is the status universe "select every row" is compared against,
  /// and defaults to [filterable] — every real backend state. It exists
  /// because the CALLER's filter UI does not always cover [filterable]
  /// exactly: since 2026-08-15 `BookingsFilterSheet` offers no row for
  /// [notCompleted] (nothing in the app can SET that status — see
  /// `BookingStatusFilterGroup`'s header), so the day-list screen passes the
  /// sheet's own four-status coverage here instead of the default five. Without
  /// this parameter, "the master ticks every row the sheet still shows" would
  /// resolve to `{CONFIRMED, COMPLETED, CANCELLED, DECLINED}` verbatim — an
  /// INCLUSION list that silently excludes [notCompleted] on the wire, hiding
  /// the master's own no-show record behind an action that reads as "show
  /// everything". Passing the caller's true maximal keeps the "select all ⇒
  /// omit `status` entirely" property this parameter's absence would otherwise
  /// break — the exact silent-narrowing failure mode mobile-security flagged
  /// for the backend-vs-build gap, now also guarding a build-vs-its-own-UI gap.
  ///
  /// NOT idempotent — all of [maximal] maps to `{}`, which maps in turn to
  /// [visibleInDayListByDefault]. Apply it exactly ONCE, at query
  /// construction; that is why the view holds the master's RAW selection and
  /// never a pre-resolved wire set.
  ///
  /// UI state is deliberately untouched by all of this: the funnel badge and
  /// the empty-state copy count the MASTER's selection, so "every group
  /// ticked" still reads as an active filter even though the wire set is
  /// empty, and an untouched screen still reports zero even though the wire
  /// set is not.
  static Set<BookingStatus> dayListWireStatuses(
    Set<BookingStatus> selected, {
    Set<BookingStatus>? maximal,
  }) {
    if (selected.isEmpty) return visibleInDayListByDefault;
    // `maximal ?? filterable` rather than a literal default: a default
    // parameter value must be a compile-time constant, and `filterable` is
    // already the ONE list of every real backend state — copying its members
    // into a second literal here would be exactly the kind of hand-maintained
    // duplicate this file's own doc comments warn against elsewhere.
    if (selected.containsAll(maximal ?? filterable)) {
      return const <BookingStatus>{};
    }
    return selected;
  }

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
