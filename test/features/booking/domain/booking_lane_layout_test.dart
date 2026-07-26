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
  BookingStatus status = BookingStatus.confirmed,
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
  status: status,
  canReview: false,
);

/// Every OVERLAPPING pair in [bookings] (per [assignLanes]'s own
/// touching-endpoints-don't-count rule) must land in different lanes — the
/// one invariant that must hold regardless of status mix. Used by case (f)'s
/// integrity check.
bool _overlapsForTest(Booking a, Booking b) =>
    a.startAt.isBefore(b.endAt) && b.startAt.isBefore(a.endAt);

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

  // ===========================================================================
  // STATUS-AWARE LANE ASSIGNMENT (2026-07-26) — the demotion path
  // ===========================================================================
  //
  // Real bug report: a master cancels a booking and a NEW confirmed booking
  // is created for the same slot (the backend's overlap guard only blocks on
  // CONFIRMED, never on a cancelled-class status). Every fixture above pins
  // `status: BookingStatus.confirmed`, so none of it ever exercised
  // `_isActiveClass`/pass 2 — the entire demotion path had ZERO coverage.
  // See `booking_lane_layout.dart`'s own file header for the full mechanism.
  group('status-aware lane assignment — the cancelled-demotion path', () {
    test('a CONFIRMED booking overlapping a CANCELLED one in the same slot: '
        'confirmed lands in lane 0, cancelled is demoted to lane >= 1 '
        '(the user-reported bug)', () {
      // The cancelled booking starts STRICTLY EARLIER than the confirmed
      // one — under the pre-fix pure-`startAt` sort this is exactly the
      // fixture shape that puts the cancelled card in lane 0 (sorted
      // first, opens lane 0; the confirmed booking sorts second, overlaps
      // it, and is pushed to lane 1). See this test file's header note on
      // how this was confirmed to fail against the pre-fix algorithm.
      final Booking cancelled = _booking(
        id: 'cancelled-first',
        startAt: _at(9),
        endAt: _at(10),
        status: BookingStatus.cancelled,
      );
      final Booking confirmed = _booking(
        id: 'confirmed-second',
        startAt: _at(9, 15),
        endAt: _at(10, 15),
      );

      final List<int> lanes = assignLanes(<Booking>[cancelled, confirmed]);

      expect(
        lanes[1],
        0,
        reason:
            'the LIVE confirmed booking must win lane 0 — the only lane '
            'visible without horizontal scrolling',
      );
      expect(
        lanes[0],
        greaterThanOrEqualTo(1),
        reason:
            'the dead cancelled booking must never sit at or below a '
            'confirmed booking it genuinely overlaps',
      );
    });

    test('an UNKNOWN-status booking is treated as ACTIVE — not demoted — when '
        'overlapping a cancelled booking, even when the cancelled booking '
        'starts first', () {
      // Cancelled starts EARLIER than unknown, so a naive "demote whatever
      // sorts after CANCELLED" implementation would still demote unknown
      // here. unknown must win lane 0 regardless of arrival order — its
      // whole contract is "might still be live, never treat as less
      // important than a definitively cancelled booking".
      final Booking cancelled = _booking(
        id: 'cancelled-early',
        startAt: _at(9),
        endAt: _at(10),
        status: BookingStatus.cancelled,
      );
      final Booking unknown = _booking(
        id: 'unknown-late',
        startAt: _at(9, 15),
        endAt: _at(10, 15),
        status: BookingStatus.unknown,
      );

      final List<int> lanes = assignLanes(<Booking>[cancelled, unknown]);

      expect(
        lanes[1],
        0,
        reason: 'unknown is fail-safe ACTIVE and must win lane 0',
      );
      expect(lanes[0], 1, reason: 'cancelled is demoted behind it');
    });

    test('DECLINED and NOT_COMPLETED are demoted exactly like CANCELLED, '
        'behind an overlapping CONFIRMED booking', () {
      final Booking confirmed = _booking(
        id: 'confirmed',
        startAt: _at(9),
        endAt: _at(10),
      );
      final Booking declined = _booking(
        id: 'declined',
        startAt: _at(9),
        endAt: _at(10),
        status: BookingStatus.declined,
      );
      final Booking notCompleted = _booking(
        id: 'not-completed',
        startAt: _at(9),
        endAt: _at(10),
        status: BookingStatus.notCompleted,
      );

      final List<int> lanes = assignLanes(<Booking>[
        confirmed,
        declined,
        notCompleted,
      ]);

      expect(lanes[0], 0, reason: 'the active booking keeps lane 0');
      expect(
        lanes[1],
        greaterThanOrEqualTo(1),
        reason: 'DECLINED must be demoted behind the active booking',
      );
      expect(
        lanes[2],
        greaterThanOrEqualTo(1),
        reason: 'NOT_COMPLETED must be demoted behind the active booking',
      );
    });

    test('a time range containing ONLY cancelled-class bookings still starts '
        'at lane 0 — demotion is a per-overlap floor, not a blanket rule', () {
      final Booking declined = _booking(
        id: 'declined-only',
        startAt: _at(9),
        endAt: _at(10),
        status: BookingStatus.declined,
      );

      final List<int> lanes = assignLanes(<Booking>[declined]);

      expect(lanes, <int>[0]);
      expect(laneCount(lanes), 1);
    });

    test(
      'two overlapping cancelled-class bookings partition normally between '
      'themselves — no mutual demotion when neither overlaps anything active',
      () {
        final Booking cancelled = _booking(
          id: 'c1',
          startAt: _at(9),
          endAt: _at(10),
          status: BookingStatus.cancelled,
        );
        final Booking declined = _booking(
          id: 'd1',
          startAt: _at(9, 30),
          endAt: _at(10, 30),
          status: BookingStatus.declined,
        );

        final List<int> lanes = assignLanes(<Booking>[cancelled, declined]);

        expect(lanes, <int>[0, 1]);
        expect(laneCount(lanes), 2);
      },
    );

    test('output integrity over a mixed active/cancelled fixture: every input '
        'gets exactly one non-negative lane, and no two overlapping bookings '
        'share a lane', () {
      final List<Booking> bookings = <Booking>[
        _booking(id: 'a-1', startAt: _at(9), endAt: _at(10)),
        _booking(
          id: 'cancelled-1',
          startAt: _at(9, 15),
          endAt: _at(9, 45),
          status: BookingStatus.cancelled,
        ),
        _booking(
          id: 'a-2',
          startAt: _at(9, 30),
          endAt: _at(10, 30),
          status: BookingStatus.completed,
        ),
        _booking(
          id: 'declined-1',
          startAt: _at(9),
          endAt: _at(9, 20),
          status: BookingStatus.declined,
        ),
        _booking(
          id: 'not-completed-1',
          startAt: _at(11),
          endAt: _at(11, 30),
          status: BookingStatus.notCompleted,
        ),
        _booking(id: 'a-3', startAt: _at(13), endAt: _at(14)),
      ];

      final List<int> lanes = assignLanes(bookings);

      expect(lanes.length, bookings.length);
      for (final int lane in lanes) {
        expect(lane, greaterThanOrEqualTo(0));
      }
      for (int i = 0; i < bookings.length; i++) {
        for (int j = i + 1; j < bookings.length; j++) {
          if (_overlapsForTest(bookings[i], bookings[j])) {
            expect(
              lanes[i],
              isNot(lanes[j]),
              reason:
                  '${bookings[i].id} and ${bookings[j].id} overlap in wall '
                  'clock time and must not share a lane',
            );
          }
        }
      }
    });

    test('touching endpoints (a.endAt == b.startAt) share a lane across the '
        'active/cancelled boundary too', () {
      final Booking active = _booking(
        id: 'active-touch',
        startAt: _at(9),
        endAt: _at(10),
      );
      final Booking cancelled = _booking(
        id: 'cancelled-touch',
        startAt: _at(10), // touches active.endAt exactly
        endAt: _at(11),
        status: BookingStatus.cancelled,
      );

      final List<int> lanes = assignLanes(<Booking>[active, cancelled]);

      expect(
        lanes,
        <int>[0, 0],
        reason:
            'a 09-10 active booking and a 10-11 cancelled one do not '
            'overlap and must not be pushed into separate lanes',
      );
      expect(laneCount(lanes), 1);
    });

    test('laneCount growth from demotion is bounded by the number of '
        'OVERLAPPING cancelled bookings, not the total cancelled count', () {
      final Booking active = _booking(
        id: 'active',
        startAt: _at(9),
        endAt: _at(10),
      );
      // The ONE cancelled booking that actually overlaps the active
      // booking — this is the only one that should ever force a new lane.
      final Booking overlappingCancelled = _booking(
        id: 'cancelled-overlapping',
        startAt: _at(9, 15),
        endAt: _at(9, 45),
        status: BookingStatus.cancelled,
      );
      // Five more cancelled bookings, all AFTER the active booking ends
      // and all mutually non-overlapping — none of them contests an
      // active lane, so all five should be free to reuse lane 0.
      final List<Booking> farCancelled = <Booking>[
        for (int i = 0; i < 5; i++)
          _booking(
            id: 'far-cancelled-$i',
            startAt: _at(11 + i, 0),
            endAt: _at(11 + i, 30),
            status: BookingStatus.declined,
          ),
      ];

      final List<int> lanes = assignLanes(<Booking>[
        active,
        overlappingCancelled,
        ...farCancelled,
      ]);

      expect(
        laneCount(lanes),
        2,
        reason:
            '6 cancelled-class bookings exist in total, but only ONE '
            'overlaps an active booking — laneCount must track that one '
            'overlap, not the total cancelled count',
      );
    });
  });
}
