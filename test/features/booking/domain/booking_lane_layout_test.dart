// Phase 7.10 — pure unit tests for [assignLanes]/[laneCount].
//
// Pure Dart, no widget pump — mirrors the "no Flutter import" contract of the
// production file under test.
//
// ## NO ABSOLUTE FUTURE LITERALS (2026-07-22, ratchet turn)
//
// Every instant below used to be a hand-rolled `DateTime.utc(2026, 7, 20, …)`,
// and this file was grandfathered into `scripts/.stale_future_date_allow` for
// exactly that. Those literals have since ELAPSED, which is the whole failure
// mode the allow-list's own header calls a time bomb — so they are converted
// here and the file is DELISTED. [_at] anchors every fixture to a now-relative
// day ([_anchorDay], via `futureBookingStart()`); only the RELATIVE offsets
// between instants have ever carried meaning for `assignLanes`, which is pure
// interval arithmetic and reads no wall clock at all.

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_lane_layout.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/booking_fixture_dates.dart';

/// UTC midnight of a calendar day comfortably in the future, derived from the
/// real clock — never an absolute literal. See the file header.
final DateTime _anchorDay = _midnightOf(futureBookingStart());

DateTime _midnightOf(DateTime instant) =>
    DateTime.utc(instant.year, instant.month, instant.day);

/// `hour:minute` on [_anchorDay], in UTC — the replacement for this file's
/// retired `DateTime.utc(2026, 7, 20, hour, minute)` literals.
DateTime _at(int hour, [int minute = 0]) =>
    _anchorDay.add(Duration(hours: hour, minutes: minute));

Booking _booking({
  required String id,
  required DateTime startAt,
  required DateTime endAt,
}) => Booking(
  id: id,
  masterId: 'master-1',
  masterFirstName: 'Оля',
  masterLastName: 'Коваль',
  masterType: 'INDEPENDENT_MASTER',
  serviceId: 'service-1',
  serviceName: 'Манікюр',
  durationMinutes: endAt.difference(startAt).inMinutes,
  price: 500,
  startAt: startAt,
  endAt: endAt,
  status: BookingStatus.confirmed,
  canReview: false,
);

void main() {
  group('assignLanes', () {
    test('non-overlapping bookings all land in lane 0', () {
      final Booking a = _booking(id: 'a', startAt: _at(9), endAt: _at(10));
      final Booking b = _booking(id: 'b', startAt: _at(11), endAt: _at(12));
      final Booking c = _booking(id: 'c', startAt: _at(13), endAt: _at(14));

      final List<int> lanes = assignLanes(<Booking>[a, b, c]);

      expect(lanes, <int>[0, 0, 0]);
      expect(laneCount(lanes), 1);
    });

    test('two overlapping bookings land in lanes 0 and 1', () {
      final Booking a = _booking(id: 'a', startAt: _at(9), endAt: _at(10));
      final Booking b = _booking(
        id: 'b',
        startAt: _at(9, 30),
        endAt: _at(10, 30),
      );

      final List<int> lanes = assignLanes(<Booking>[a, b]);

      expect(lanes, <int>[0, 1]);
      expect(laneCount(lanes), 2);
    });

    test('three mutually overlapping bookings land in lanes 0, 1, 2', () {
      final Booking a = _booking(id: 'a', startAt: _at(9), endAt: _at(11));
      final Booking b = _booking(
        id: 'b',
        startAt: _at(9, 30),
        endAt: _at(10, 30),
      );
      final Booking c = _booking(
        id: 'c',
        startAt: _at(9, 45),
        endAt: _at(10, 45),
      );

      final List<int> lanes = assignLanes(<Booking>[a, b, c]);

      expect(lanes, <int>[0, 1, 2]);
      expect(laneCount(lanes), 3);
    });

    test('a gap frees a lane for reuse (C lands back in lane 0)', () {
      // A 09:00–10:00 lane 0; B 09:30–10:30 lane 1 (overlaps A);
      // C 10:15–11:00 — starts after A ended (10:00), so lane 0 is free again.
      final Booking a = _booking(id: 'a', startAt: _at(9), endAt: _at(10));
      final Booking b = _booking(
        id: 'b',
        startAt: _at(9, 30),
        endAt: _at(10, 30),
      );
      final Booking c = _booking(id: 'c', startAt: _at(10, 15), endAt: _at(11));

      final List<int> lanes = assignLanes(<Booking>[a, b, c]);

      expect(lanes, <int>[0, 1, 0]);
      expect(laneCount(lanes), 2);
    });

    test('touching endpoints (endAt == startAt) share a lane', () {
      final Booking a = _booking(id: 'a', startAt: _at(10), endAt: _at(11));
      final Booking b = _booking(
        id: 'b',
        startAt: _at(11), // touches A's endAt exactly
        endAt: _at(12),
      );

      final List<int> lanes = assignLanes(<Booking>[a, b]);

      expect(lanes, <int>[
        0,
        0,
      ], reason: 'a 10-11 and an 11-12 booking are not an overlap');
      expect(laneCount(lanes), 1);
    });

    test('the input list is not mutated and the result aligns positionally '
        'with the INPUT order, not start-time order', () {
      // Deliberately out-of-chronological-order input: b starts before a.
      final Booking a = _booking(id: 'a', startAt: _at(11), endAt: _at(12));
      final Booking b = _booking(id: 'b', startAt: _at(9), endAt: _at(10));
      final List<Booking> input = <Booking>[a, b];
      final List<Booking> inputSnapshot = List<Booking>.of(input);

      final List<int> lanes = assignLanes(input);

      // Both are non-overlapping (b ends before a starts) so both land in
      // lane 0 regardless of order — the meaningful assertion here is the
      // POSITIONAL alignment and non-mutation, not the lane values.
      expect(lanes, <int>[0, 0]);
      expect(
        input,
        inputSnapshot,
        reason: 'assignLanes must not mutate or reorder the caller list',
      );
      expect(identical(input[0], a), isTrue);
      expect(identical(input[1], b), isTrue);
    });

    test('empty input yields empty output and laneCount 0', () {
      final List<int> lanes = assignLanes(const <Booking>[]);

      expect(lanes, isEmpty);
      expect(laneCount(lanes), 0);
    });
  });

  // ===========================================================================
  // mobile-qa (2026-07-22) — DEGENERATE DURATIONS
  // ===========================================================================
  //
  // The backend validates a service's duration as `@Min(1)`, so a ONE-MINUTE
  // booking is a legitimate wire value, and a zero-length interval
  // (`startAt == endAt`) is reachable from any malformed/edge payload the
  // mapper does not reject. Nothing in this suite exercised either: every
  // fixture above is >= 15 minutes. Both cases hit `assignLanes`'s occupancy
  // test (`laneEnd[lane].isAfter(booking.startAt)`) at its exact boundary,
  // which is where an `isAfter` → `!isBefore` slip (the design's original,
  // deliberately-fixed behaviour — see `booking_lane_layout.dart`'s doc) would
  // show up first.
  group('degenerate durations (backend permits @Min(1))', () {
    test('a ZERO-length booking does not open a lane against a neighbour that '
        'merely touches it', () {
      // 09:00–10:00, then a zero-length marker AT 10:00. The marker's start is
      // not strictly inside A, so lane 0 is free for it.
      final Booking a = _booking(id: 'a', startAt: _at(9), endAt: _at(10));
      final Booking zero = _booking(
        id: 'zero',
        startAt: _at(10),
        endAt: _at(10), // startAt == endAt
      );

      final List<int> lanes = assignLanes(<Booking>[a, zero]);

      expect(zero.durationMinutes, 0, reason: 'fixture guard');
      expect(lanes, <int>[0, 0]);
      expect(laneCount(lanes), 1);
    });

    test('a ZERO-length booking landing INSIDE a live booking still opens a '
        'second lane — it is an overlap, not a touch', () {
      final Booking a = _booking(id: 'a', startAt: _at(9), endAt: _at(10));
      final Booking zero = _booking(
        id: 'zero',
        startAt: _at(9, 30),
        endAt: _at(9, 30),
      );

      final List<int> lanes = assignLanes(<Booking>[a, zero]);

      expect(lanes, <int>[0, 1]);
      expect(laneCount(lanes), 2);
    });

    test('a zero-length booking occupies its lane for zero time — the NEXT '
        'booking at the same instant reuses lane 0', () {
      // The property that distinguishes a correct zero-length handling from a
      // lane leak: after the marker, lane 0's `laneEnd` is the marker's own
      // start, so a booking starting at that same instant is not blocked.
      final Booking zero = _booking(
        id: 'zero',
        startAt: _at(10),
        endAt: _at(10),
      );
      final Booking next = _booking(
        id: 'next',
        startAt: _at(10),
        endAt: _at(11),
      );

      final List<int> lanes = assignLanes(<Booking>[zero, next]);

      expect(lanes, <int>[0, 0]);
      expect(
        laneCount(lanes),
        1,
        reason:
            'a zero-length interval must not reserve a lane past its own '
            'instant',
      );
    });

    test('two back-to-back ONE-MINUTE bookings pack into a single lane', () {
      final Booking first = _booking(
        id: 'min-1',
        startAt: _at(10),
        endAt: _at(10, 1),
      );
      final Booking second = _booking(
        id: 'min-2',
        startAt: _at(10, 1), // touches first.endAt exactly
        endAt: _at(10, 2),
      );

      final List<int> lanes = assignLanes(<Booking>[first, second]);

      expect(first.durationMinutes, 1, reason: 'fixture guard');
      expect(second.durationMinutes, 1, reason: 'fixture guard');
      expect(lanes, <int>[0, 0]);
      expect(laneCount(lanes), 1);
    });

    test('a ONE-MINUTE booking overlapping a longer one opens a second lane, '
        'and a later one-minute booking reclaims lane 0', () {
      final Booking long = _booking(
        id: 'long',
        startAt: _at(10),
        endAt: _at(11),
      );
      final Booking insideIt = _booking(
        id: 'inside',
        startAt: _at(10, 30),
        endAt: _at(10, 31),
      );
      final Booking after = _booking(
        id: 'after',
        startAt: _at(11),
        endAt: _at(11, 1),
      );

      final List<int> lanes = assignLanes(<Booking>[long, insideIt, after]);

      expect(lanes, <int>[0, 1, 0]);
      expect(laneCount(lanes), 2);
    });
  });
}
