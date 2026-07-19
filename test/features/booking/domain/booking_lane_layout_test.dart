// Phase 7.10 — pure unit tests for [assignLanes]/[laneCount].
//
// Pure Dart, no widget pump — mirrors the "no Flutter import" contract of the
// production file under test.

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_lane_layout.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:flutter_test/flutter_test.dart';

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
      final Booking a = _booking(
        id: 'a',
        startAt: DateTime.utc(2026, 7, 20, 9),
        endAt: DateTime.utc(2026, 7, 20, 10),
      );
      final Booking b = _booking(
        id: 'b',
        startAt: DateTime.utc(2026, 7, 20, 11),
        endAt: DateTime.utc(2026, 7, 20, 12),
      );
      final Booking c = _booking(
        id: 'c',
        startAt: DateTime.utc(2026, 7, 20, 13),
        endAt: DateTime.utc(2026, 7, 20, 14),
      );

      final List<int> lanes = assignLanes(<Booking>[a, b, c]);

      expect(lanes, <int>[0, 0, 0]);
      expect(laneCount(lanes), 1);
    });

    test('two overlapping bookings land in lanes 0 and 1', () {
      final Booking a = _booking(
        id: 'a',
        startAt: DateTime.utc(2026, 7, 20, 9),
        endAt: DateTime.utc(2026, 7, 20, 10),
      );
      final Booking b = _booking(
        id: 'b',
        startAt: DateTime.utc(2026, 7, 20, 9, 30),
        endAt: DateTime.utc(2026, 7, 20, 10, 30),
      );

      final List<int> lanes = assignLanes(<Booking>[a, b]);

      expect(lanes, <int>[0, 1]);
      expect(laneCount(lanes), 2);
    });

    test('three mutually overlapping bookings land in lanes 0, 1, 2', () {
      final Booking a = _booking(
        id: 'a',
        startAt: DateTime.utc(2026, 7, 20, 9),
        endAt: DateTime.utc(2026, 7, 20, 11),
      );
      final Booking b = _booking(
        id: 'b',
        startAt: DateTime.utc(2026, 7, 20, 9, 30),
        endAt: DateTime.utc(2026, 7, 20, 10, 30),
      );
      final Booking c = _booking(
        id: 'c',
        startAt: DateTime.utc(2026, 7, 20, 9, 45),
        endAt: DateTime.utc(2026, 7, 20, 10, 45),
      );

      final List<int> lanes = assignLanes(<Booking>[a, b, c]);

      expect(lanes, <int>[0, 1, 2]);
      expect(laneCount(lanes), 3);
    });

    test('a gap frees a lane for reuse (C lands back in lane 0)', () {
      // A 09:00–10:00 lane 0; B 09:30–10:30 lane 1 (overlaps A);
      // C 10:15–11:00 — starts after A ended (10:00), so lane 0 is free again.
      final Booking a = _booking(
        id: 'a',
        startAt: DateTime.utc(2026, 7, 20, 9),
        endAt: DateTime.utc(2026, 7, 20, 10),
      );
      final Booking b = _booking(
        id: 'b',
        startAt: DateTime.utc(2026, 7, 20, 9, 30),
        endAt: DateTime.utc(2026, 7, 20, 10, 30),
      );
      final Booking c = _booking(
        id: 'c',
        startAt: DateTime.utc(2026, 7, 20, 10, 15),
        endAt: DateTime.utc(2026, 7, 20, 11),
      );

      final List<int> lanes = assignLanes(<Booking>[a, b, c]);

      expect(lanes, <int>[0, 1, 0]);
      expect(laneCount(lanes), 2);
    });

    test('touching endpoints (endAt == startAt) share a lane', () {
      final Booking a = _booking(
        id: 'a',
        startAt: DateTime.utc(2026, 7, 20, 10),
        endAt: DateTime.utc(2026, 7, 20, 11),
      );
      final Booking b = _booking(
        id: 'b',
        startAt: DateTime.utc(2026, 7, 20, 11), // touches A's endAt exactly
        endAt: DateTime.utc(2026, 7, 20, 12),
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
      final Booking a = _booking(
        id: 'a',
        startAt: DateTime.utc(2026, 7, 20, 11),
        endAt: DateTime.utc(2026, 7, 20, 12),
      );
      final Booking b = _booking(
        id: 'b',
        startAt: DateTime.utc(2026, 7, 20, 9),
        endAt: DateTime.utc(2026, 7, 20, 10),
      );
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
}
