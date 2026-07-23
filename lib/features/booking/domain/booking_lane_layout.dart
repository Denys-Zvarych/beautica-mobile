// Phase 7.10 — greedy interval-partition lane assignment for the master's
// «Мої записи» timeline grid (`BookingsTimelineGrid`).
//
// Transcribed from the approved design's `_TimelineGrid._assignLanes`
// (`docs/signup-designs/SalonManagementDesign/lib/widgets/
// bookings_toolbar.dart:1349-1365`), with one deliberate behavioural fix over
// the design: TOUCHING endpoints now share a lane (see [assignLanes]'s doc).
//
// Pure Dart, no Flutter import — unit-testable without a widget pump.

import 'booking.dart';

/// Greedy interval-partition over [bookings]: assigns each booking to the
/// first "lane" (a vertical column in the timeline) whose last occupant has
/// already ended by the time this booking starts, opening a new lane only
/// when none is free.
///
/// Returns a list of lane indices **positionally aligned with [bookings]**
/// (`result[i]` is the lane for `bookings[i]`) — NOT aligned with the
/// ascending-by-`startAt` order the algorithm walks internally. [bookings] is
/// sorted into a **copy** first; the caller's list (the day provider's
/// server-ordered `items`) is never mutated.
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
  // back to input position after sorting a copy by start time.
  final List<MapEntry<int, Booking>> byStart =
      <MapEntry<int, Booking>>[
        for (int i = 0; i < bookings.length; i++)
          MapEntry<int, Booking>(i, bookings[i]),
      ]..sort(
        (MapEntry<int, Booking> a, MapEntry<int, Booking> b) =>
            a.value.startAt.compareTo(b.value.startAt),
      );

  final List<int> laneByOriginalIndex = List<int>.filled(bookings.length, 0);
  // laneEnd[lane] == the endAt of the lane's current last occupant.
  final List<DateTime> laneEnd = <DateTime>[];

  for (final MapEntry<int, Booking> entry in byStart) {
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
