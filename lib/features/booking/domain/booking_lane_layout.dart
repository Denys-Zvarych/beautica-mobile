// Phase 7.10 — greedy interval-partition lane assignment for the master's
// «Мої записи» timeline grid (`BookingsTimelineGrid`).
//
// Transcribed from the approved design's `_TimelineGrid._assignLanes`
// (`docs/signup-designs/SalonManagementDesign/lib/widgets/
// bookings_toolbar.dart:1349-1365`), with one deliberate behavioural fix over
// the design: TOUCHING endpoints now share a lane (see [assignLanes]'s doc).
//
// Pure Dart, no Flutter import — unit-testable without a widget pump.
//
// ============================================================================
// STATUS-AWARE LANE ASSIGNMENT (2026-07-26) — WHY LANES ARE NOT PURE
// START-TIME ORDER
// ============================================================================
// Real bug report: a master cancels a booking, and a NEW confirmed booking
// then gets created for the same slot — legitimate, because the backend's
// overlap guard (`BookingRepository.existsOverlap`, and the Postgres EXCLUDE
// constraint in `V18__create_bookings.sql`) only blocks on PENDING/CONFIRMED,
// never on a cancelled-class status. On the timeline this produces two
// bookings that genuinely overlap in wall-clock time: the live replacement
// and the dead one it replaced. The ORIGINAL `assignLanes` sorted purely by
// `startAt`, so which of the two landed in lane 0 — the only lane visible
// without scrolling the grid horizontally — was pure accident of insertion
// order. The master would routinely see the CANCELLED card up front and the
// live booking pushed off-screen, and reasonably conclude the slot was still
// blocked.
//
// THE FIX — TWO PASSES, ACTIVE BEFORE CANCELLED-CLASS:
//
//   Pass 1 runs the ORIGINAL greedy partition over ACTIVE bookings only
//   (`BookingStatus.confirmed`, `.completed`, and `.unknown` — see
//   [_isActiveClass]; `unknown` is treated as active, fail-safe, matching
//   `BookingStatus.unknown`'s own "grant nothing, but never hide a booking
//   that might be live" contract). This is UNCHANGED from before except for
//   the input filter — active bookings partition exactly as they always did,
//   so an all-active day (still the overwhelming common case) produces a
//   byte-for-byte identical result to the pre-fix algorithm.
//
//   Pass 2 places every CANCELLED-CLASS booking (`.cancelled`, `.declined`,
//   `.notCompleted`) in `startAt` order, each into the first lane `>= floor`,
//   where `floor = 1 + (the highest lane index any OVERLAPPING active
//   booking landed in)`, or `0` if no active booking overlaps it at all.
//   "Free" is tested against every booking already placed by EITHER pass
//   (active or cancelled), via the same shared `laneEnd` bookkeeping pass 1
//   already used — a cancelled booking can still share a lane with another
//   cancelled booking once it is demoted, it just may never sit AT OR BELOW
//   an active booking it genuinely overlaps.
//
// WHY THIS ACHIEVES "EVERY ACTIVE LANE IS LEFT OF EVERY OVERLAPPING
// CANCELLED LANE": for any pair of overlapping bookings on the timeline,
// either (a) both are active — pass 1 handles that exactly as before, or (b)
// both are cancelled-class — pass 2's ordinary greedy step keeps them apart
// from each other, and neither has a `floor` imposed by the other, so they
// behave exactly like today's algorithm among themselves, or (c) one of
// each — the cancelled one's `floor` computation sees the active one's lane
// and refuses every lane at or below it. Case (c) is the one this fix exists
// for, and it is the only case that can ever place a cancelled booking to
// the right of an active one it overlaps.
//
// WHY A CANCELLED-ONLY TIME RANGE STILL STARTS AT LANE 0: `floor` is derived
// ONLY from OVERLAPPING active bookings. A stretch of the day with no active
// booking at all contributes `floor = 0` to every cancelled booking inside
// it, so they partition from lane 0 exactly as an all-active day would —
// nothing requires a cancelled booking to be reachable only by scrolling
// unless an active booking is actually contesting its slot. This is what
// makes the fix a per-overlap DEMOTION, never a blanket "cancelled bookings
// always start at lane N" rule.
//
// WHY THE TIEBREAK IS EXPLICIT, NOT LEFT TO SORT STABILITY: both passes sort
// by `startAt` and, for equal starts, by each booking's ORIGINAL index in
// [bookings] — spelled out in [_byStartThenOriginalIndex] rather than relied
// upon from `List.sort`'s stability. Two bookings sharing a `startAt` is
// reachable (a cancelled booking and its same-slot replacement, notably), and
// the lane each one lands in must not depend on incidental sort-algorithm
// behaviour.
//
// Touching endpoints (`a.endAt == b.startAt`) share a lane: a 10:00–11:00
// booking and an 11:00–12:00 booking are NOT an overlap and must not occupy
// two lanes. This is a deliberate fix over the design, whose
// `!laneEnd[lane]!.isBefore(b.dateTime)` occupancy test treats an exactly
// touching pair as still-occupied (`isBefore` is false when the two instants
// are equal) and would open a needless second lane for it. THE SAME RULE
// governs [_overlaps] below, which pass 2 uses to test active/cancelled
// overlap directly (the two bookings being compared are not necessarily
// adjacent in either pass's own sequence, so this cannot reuse the running
// `laneEnd` occupancy test the way pass 1 does) — touching bookings never
// count as overlapping there either.

import 'booking.dart';
import 'booking_status.dart';

/// Whether [status] belongs to the class pass 1 of [assignLanes] partitions
/// first, and that pass 2 never demotes behind a cancelled-class booking.
///
/// [BookingStatus.unknown] is deliberately included — see this file's header
/// and [BookingStatus.unknown]'s own doc: an unrecognised status must never
/// be treated as LESS important than a definitively cancelled one, because
/// that status might, in fact, still be live.
bool _isActiveClass(BookingStatus status) => switch (status) {
  BookingStatus.confirmed => true,
  BookingStatus.completed => true,
  BookingStatus.unknown => true,
  BookingStatus.cancelled => false,
  BookingStatus.declined => false,
  BookingStatus.notCompleted => false,
};

/// Two intervals overlap iff each starts before the other ends — the same
/// "touching endpoints don't count" rule [assignLanes]'s own running
/// occupancy test applies (`a.endAt == b.startAt` is NOT an overlap).
bool _overlaps(Booking a, Booking b) =>
    a.startAt.isBefore(b.endAt) && b.startAt.isBefore(a.endAt);

/// Sorts by `startAt`, then by each entry's ORIGINAL index in the caller's
/// list — an explicit, deterministic tiebreak so two bookings sharing a
/// `startAt` (a cancelled booking and its same-slot replacement, notably)
/// land in a reproducible order regardless of `List.sort`'s
/// implementation-defined stability.
int _byStartThenOriginalIndex(
  MapEntry<int, Booking> a,
  MapEntry<int, Booking> b,
) {
  final int byStart = a.value.startAt.compareTo(b.value.startAt);
  if (byStart != 0) return byStart;
  return a.key.compareTo(b.key);
}

/// Greedy interval-partition over [bookings]: assigns each booking to the
/// first "lane" (a vertical column in the timeline) whose last occupant has
/// already ended by the time this booking starts, opening a new lane only
/// when none is free — STATUS-AWARE (see this file's header): every ACTIVE
/// booking (`confirmed` / `completed` / `unknown`) is placed BEFORE any
/// CANCELLED-CLASS booking (`cancelled` / `declined` / `notCompleted`), and a
/// cancelled-class booking is additionally forbidden from landing at or
/// below the lane of any active booking it overlaps. Lane 0 — the only lane
/// visible without scrolling the grid — therefore never shows a cancelled
/// booking when an overlapping active booking exists.
///
/// Returns a list of lane indices **positionally aligned with [bookings]**
/// (`result[i]` is the lane for `bookings[i]`) — NOT aligned with either
/// pass's internal walk order. [bookings] is never mutated or reordered; the
/// caller's list (the day provider's server-ordered `items`) is read only.
///
/// Touching endpoints (`a.endAt == b.startAt`) share a lane: a 10:00–11:00
/// booking and an 11:00–12:00 booking are NOT an overlap and must not occupy
/// two lanes. This is a deliberate fix over the design, whose
/// `!laneEnd[lane]!.isBefore(b.dateTime)` occupancy test treats an exactly
/// touching pair as still-occupied (`isBefore` is false when the two instants
/// are equal) and would open a needless second lane for it.
List<int> assignLanes(List<Booking> bookings) {
  if (bookings.isEmpty) return const <int>[];

  // Pair each booking with its ORIGINAL index so the result can be mapped
  // back to input position once each pass sorts its own copy by start time.
  final List<MapEntry<int, Booking>> withIndex = <MapEntry<int, Booking>>[
    for (int i = 0; i < bookings.length; i++)
      MapEntry<int, Booking>(i, bookings[i]),
  ];

  // Single partitioning pass (rather than two `.where(...).toList()` walks)
  // so the ACTIVE/CANCELLED split costs one traversal and no extra closures.
  final List<MapEntry<int, Booking>> activeByStart = <MapEntry<int, Booking>>[];
  final List<MapEntry<int, Booking>> cancelledByStart =
      <MapEntry<int, Booking>>[];
  for (final MapEntry<int, Booking> entry in withIndex) {
    if (_isActiveClass(entry.value.status)) {
      activeByStart.add(entry);
    } else {
      cancelledByStart.add(entry);
    }
  }
  activeByStart.sort(_byStartThenOriginalIndex);
  cancelledByStart.sort(_byStartThenOriginalIndex);

  final List<int> laneByOriginalIndex = List<int>.filled(bookings.length, 0);
  // laneEnd[lane] == the endAt of the lane's current last occupant — shared
  // across both passes, so a cancelled booking placed in pass 2 correctly
  // sees (and can reuse, once vacated) every lane an active booking already
  // opened in pass 1.
  final List<DateTime> laneEnd = <DateTime>[];

  // Pass 1 — ACTIVE bookings only. Exactly the original (pre-status-aware)
  // greedy interval-partition, just over a filtered input.
  for (final MapEntry<int, Booking> entry in activeByStart) {
    final Booking booking = entry.value;
    int lane = 0;
    // A lane is free once its last occupant's endAt is <= this booking's
    // startAt (touching endpoints count as free — see doc above).
    while (lane < laneEnd.length && laneEnd[lane].isAfter(booking.startAt)) {
      lane++;
    }
    if (lane == laneEnd.length) {
      laneEnd.add(booking.endAt);
    } else {
      laneEnd[lane] = booking.endAt;
    }
    laneByOriginalIndex[entry.key] = lane;
  }

  // Pass 2 — CANCELLED-CLASS bookings, each demoted behind every ACTIVE
  // booking it genuinely overlaps (see this file's header). `floor` is
  // recomputed per booking from the now-final active lane assignments above;
  // pass 2 never revisits or mutates them.
  for (final MapEntry<int, Booking> entry in cancelledByStart) {
    final Booking booking = entry.value;
    int floor = 0;
    for (final MapEntry<int, Booking> activeEntry in activeByStart) {
      // `activeByStart` is sorted ascending by `startAt` (see
      // `_byStartThenOriginalIndex`). Once this entry starts at or after
      // `booking.endAt`, every later entry starts even later, so none of
      // them can overlap `booking` either — safe to stop scanning. This
      // `break` depends entirely on that ascending-start invariant; if
      // `activeByStart`'s sort ever changes, this early exit must go too.
      if (!activeEntry.value.startAt.isBefore(booking.endAt)) break;
      if (_overlaps(activeEntry.value, booking)) {
        final int activeLane = laneByOriginalIndex[activeEntry.key];
        if (activeLane + 1 > floor) floor = activeLane + 1;
      }
    }
    int lane = floor;
    while (lane < laneEnd.length && laneEnd[lane].isAfter(booking.startAt)) {
      lane++;
    }
    if (lane == laneEnd.length) {
      laneEnd.add(booking.endAt);
    } else {
      laneEnd[lane] = booking.endAt;
    }
    laneByOriginalIndex[entry.key] = lane;
  }

  return laneByOriginalIndex;
}

/// Total lanes [assignLanes] needs to render every booking side by side —
/// `max(lanes) + 1`, or `0` for an empty input.
int laneCount(List<int> lanes) {
  if (lanes.isEmpty) return 0;
  int highest = lanes[0];
  for (final int lane in lanes) {
    if (lane > highest) highest = lane;
  }
  return highest + 1;
}
