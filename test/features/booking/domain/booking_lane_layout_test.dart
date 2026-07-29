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

// ===========================================================================
// mobile-qa (2026-07-26) — MINIMALITY / COMPACTNESS ORACLE
// ===========================================================================
//
// The regression this closes (`fe018d3`, see `booking_lane_layout.dart`'s own
// file header): pass 2 read pass 1's SHARED `laneEnd` array, whose lane-0
// entry by the time pass 2 ran held the end of the day's LAST active
// booking — not of anything actually overlapping the cancelled booking being
// placed. Every test in this file before this addition only ever asserted
// "no two OVERLAPPING bookings share a lane" (`_overlapsForTest` above) — a
// pure SAFETY property. The `fe018d3` bug never violated it: a cancelled
// booking wrongly bumped to lane 1 with nothing else in lane 1 is still
// "safe" by that measure alone. What it violates is MINIMALITY — the
// booking sits higher than it had to — and nothing in this file checked that
// before now. `_expectMinimalLane` is the independent oracle for it.
//
// "Independent" specifically means: `floor` is recomputed HERE from the
// fixture and the [lanes] result's own ACTIVE assignments — never by calling
// `assignLanes` internals or duplicating its `floor`-scanning loop verbatim
// against non-test data. A bug that corrupts assignLanes's real floor
// computation still gets caught, because this derives the expected floor
// from first principles instead of trusting the code under test to have
// gotten it right.

/// Mirrors `_isActiveClass` in the production file — this file's own
/// independent read of the same status contract (see [BookingStatus]),
/// not a call into the production helper. Needed so [_expectMinimalLane]
/// can group bookings into the same two classes assignLanes does.
bool _isActiveForTest(BookingStatus status) => switch (status) {
  BookingStatus.confirmed => true,
  BookingStatus.completed => true,
  BookingStatus.unknown => true,
  BookingStatus.cancelled => false,
  BookingStatus.declined => false,
  BookingStatus.notCompleted => false,
};

/// Asserts `bookings[index]` sits in the LOWEST lane [assignLanes] could
/// legally have placed it in, given the ALREADY-COMPUTED [lanes] result.
///
/// `floor` is independently recomputed: 0 for an ACTIVE-class booking (an
/// active booking is never demoted by anything cancelled-class), or 1 + the
/// highest lane of every OVERLAPPING active booking for a CANCELLED-class
/// one — read straight off [lanes], not off any production `floor` value.
///
/// For every lane strictly between `floor` and the booking's actual lane,
/// this demands a WITNESS: another booking of the SAME status class,
/// already resolved earlier in `assignLanes`'s own processing order
/// (earlier `startAt`, or a tie broken by original index — mirroring
/// `_byStartThenOriginalIndex`), occupying that lane and genuinely
/// overlapping `bookings[index]`. Without a witness, nothing stopped
/// `assignLanes` from using that lane instead, and landing higher than that
/// is exactly the shape of the `fe018d3` bug: a lane read as "busy" against
/// a watermark left by a booking that never actually contested it.
void _expectMinimalLane({
  required List<Booking> bookings,
  required List<int> lanes,
  required int index,
}) {
  final Booking booking = bookings[index];
  final bool activeClass = _isActiveForTest(booking.status);

  int floor = 0;
  if (!activeClass) {
    for (int i = 0; i < bookings.length; i++) {
      if (i == index) continue;
      if (_isActiveForTest(bookings[i].status) &&
          _overlapsForTest(bookings[i], booking)) {
        if (lanes[i] + 1 > floor) floor = lanes[i] + 1;
      }
    }
  }

  final int lane = lanes[index];
  expect(
    lane,
    greaterThanOrEqualTo(floor),
    reason:
        '${booking.id} sits in lane $lane, below its own independently '
        'recomputed floor $floor — a safety violation, not just a '
        'minimality one',
  );

  for (int candidate = floor; candidate < lane; candidate++) {
    bool witnessed = false;
    for (int i = 0; i < bookings.length; i++) {
      if (i == index) continue;
      final Booking other = bookings[i];
      if (_isActiveForTest(other.status) != activeClass) continue;
      if (lanes[i] != candidate) continue;
      if (!_overlapsForTest(other, booking)) continue;
      final int byStart = other.startAt.compareTo(booking.startAt);
      final bool placedFirst = byStart != 0 ? byStart < 0 : i < index;
      if (placedFirst) {
        witnessed = true;
        break;
      }
    }
    expect(
      witnessed,
      isTrue,
      reason:
          '${booking.id} landed in lane $lane, but no earlier-placed '
          'booking of the same status class occupies lane $candidate and '
          'overlaps it — assignLanes should have used lane $candidate '
          "instead (minimality violation, the fe018d3 bug's shape)",
    );
  }
}

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

    test('an ISOLATED cancelled booking sandwiched between two unrelated '
        'active bookings still lands in lane 0 — the exact fe018d3 '
        'regression (minimal repro)', () {
      // 09:00-10:00 CONFIRMED, 14:00-15:00 CANCELLED (overlaps NEITHER
      // active booking), 17:00-18:00 CONFIRMED. Pass 1 places both active
      // bookings in lane 0 (they don't overlap each other either), so by
      // the time pass 1 finishes, the pre-fix shared `laneEnd[0]` holds
      // 18:00 — the END OF THE LAST ACTIVE BOOKING OF THE WHOLE DAY, which
      // has nothing to do with the cancelled booking at 14:00. Reading that
      // watermark as "lane 0 busy" (`18:00.isAfter(14:00)` is true) bumped
      // the cancelled booking to lane 1 for no reason — see
      // `booking_lane_layout.dart`'s file header. The fixed algorithm's
      // pass 2 tracks its OWN `cancelledLaneEnd`, starts empty, and finds
      // lane 0 genuinely free.
      final Booking firstActive = _booking(
        id: 'first-active',
        startAt: _at(9),
        endAt: _at(10),
      );
      final Booking isolatedCancelled = _booking(
        id: 'isolated-cancelled',
        startAt: _at(14),
        endAt: _at(15),
        status: BookingStatus.cancelled,
      );
      final Booking lastActive = _booking(
        id: 'last-active',
        startAt: _at(17),
        endAt: _at(18),
      );
      final List<Booking> bookings = <Booking>[
        firstActive,
        isolatedCancelled,
        lastActive,
      ];

      final List<int> lanes = assignLanes(bookings);

      expect(
        lanes,
        <int>[0, 0, 0],
        reason:
            'the isolated cancelled booking overlaps NOTHING and must stay '
            'in lane 0 — a master reading it as still-blocking the slot is '
            'the exact user-visible symptom this fix exists for',
      );
      expect(laneCount(lanes), 1);
      for (int i = 0; i < bookings.length; i++) {
        _expectMinimalLane(bookings: bookings, lanes: lanes, index: i);
      }
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

        final List<Booking> bookings = <Booking>[cancelled, declined];
        final List<int> lanes = assignLanes(bookings);

        expect(lanes, <int>[0, 1]);
        expect(laneCount(lanes), 2);
        for (int i = 0; i < bookings.length; i++) {
          _expectMinimalLane(bookings: bookings, lanes: lanes, index: i);
        }
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

      // mobile-qa (2026-07-26) — this fixture is the ONE that already
      // contained the fe018d3 failing case and the suite never noticed:
      // `not-completed-1` (11:00-11:30) overlaps NOTHING in this fixture
      // (the nearest active booking, `a-1`/`a-2`, ends by 10:30; `a-3`
      // starts at 13:00), yet against the pre-fix shared-`laneEnd` code it
      // landed in lane 1 — bumped by `laneEnd[0]`'s leftover watermark
      // (14:00, left by `a-3`, the LAST active booking pass 1 placed in
      // lane 0), which the safety-only assertions above never caught
      // because nothing else occupies lane 1 at 11:00-11:30 to collide
      // with. This is the exact structural gap this file's 2026-07-26
      // pass closes — see `_expectMinimalLane`'s own doc.
      expect(
        lanes[4],
        0,
        reason:
            'not-completed-1 (11:00-11:30) overlaps no active booking in '
            'this fixture and must land in lane 0 — the fe018d3 regression '
            'this exact fixture already contained without any assertion '
            'noticing',
      );
      for (int i = 0; i < bookings.length; i++) {
        _expectMinimalLane(bookings: bookings, lanes: lanes, index: i);
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

      final List<Booking> bookings = <Booking>[
        active,
        overlappingCancelled,
        ...farCancelled,
      ];
      final List<int> lanes = assignLanes(bookings);

      expect(
        laneCount(lanes),
        2,
        reason:
            '6 cancelled-class bookings exist in total, but only ONE '
            'overlaps an active booking — laneCount must track that one '
            'overlap, not the total cancelled count',
      );
      for (int i = 0; i < bookings.length; i++) {
        _expectMinimalLane(bookings: bookings, lanes: lanes, index: i);
      }
    });

    // ── mobile-qa (2026-07-26) — cases (d) and (e): closing the structural
    //      gap this file's header documents (see the block above `main()`).
    //      Every case above only ever checked SAFETY (no two overlapping
    //      bookings share a lane); these two check MINIMALITY specifically
    //      at the boundary the fe018d3 bug lived in. ────────────────────────
    test('the cancelled-vs-cancelled mirror: an early cancelled booking is '
        'never demoted by a LATER, non-overlapping cancelled booking\'s '
        'watermark', () {
      // Three CANCELLED-class bookings, no active bookings at all:
      //   earlyA  09:00-09:30 — overlaps earlyB only.
      //   earlyB  09:15-09:45 — overlaps earlyA; forced into a second lane.
      //   late    17:00-18:00 — overlaps NEITHER; processed LAST (pass 2
      //           walks in ascending startAt order), and by then lane 0 has
      //           long been vacated by earlyA (which ended at 09:30).
      //
      // The mirror of the fe018d3 shape: `late`'s own eventual high `endAt`
      // (18:00) must never leak backwards and contaminate `earlyA`'s lane-0
      // placement, which happens chronologically BEFORE `late` is even
      // considered. A regression that pre-sized or shared `cancelledLaneEnd`
      // across the whole cancelled-class sweep up front (rather than
      // building it incrementally, in start order) would show up here.
      final Booking earlyA = _booking(
        id: 'early-a',
        startAt: _at(9),
        endAt: _at(9, 30),
        status: BookingStatus.cancelled,
      );
      final Booking earlyB = _booking(
        id: 'early-b',
        startAt: _at(9, 15),
        endAt: _at(9, 45),
        status: BookingStatus.declined,
      );
      final Booking late = _booking(
        id: 'late',
        startAt: _at(17),
        endAt: _at(18),
        status: BookingStatus.notCompleted,
      );
      final List<Booking> bookings = <Booking>[earlyA, earlyB, late];

      final List<int> lanes = assignLanes(bookings);

      expect(
        lanes[0],
        0,
        reason:
            'early-a must land in lane 0 — nothing has placed anything in '
            'a lane it could collide with at the time it is processed',
      );
      expect(
        lanes[1],
        1,
        reason: 'early-b genuinely overlaps early-a and must take lane 1',
      );
      expect(
        lanes[2],
        0,
        reason:
            'late overlaps neither earlier booking and reuses lane 0 once '
            'it is free again — its own far-future end must never '
            'retroactively demote early-a, which was already placed before '
            'late is even considered',
      );
      expect(laneCount(lanes), 2);
      for (int i = 0; i < bookings.length; i++) {
        _expectMinimalLane(bookings: bookings, lanes: lanes, index: i);
      }
    });

    test('a cancelled booking overlapping an active one sitting in lane 1 '
        '(not lane 0) is still floored at lane 2 — the fix must not weaken '
        'the demotion rule fe018d3 exists to provide', () {
      // active-A 09:00-10:00 — lane 0.
      // active-B 09:30-10:30 — overlaps active-A, forced to lane 1.
      // cancelled-C 10:15-10:45 — overlaps ONLY active-B (lane 1); it ends
      //   after active-A's 10:00, so it does NOT overlap active-A at all.
      //   floor must be computed from the HIGHEST overlapping active lane
      //   (1), not merely "some active overlaps" — so floor = 2, not 1.
      final Booking activeA = _booking(
        id: 'active-a',
        startAt: _at(9),
        endAt: _at(10),
      );
      final Booking activeB = _booking(
        id: 'active-b',
        startAt: _at(9, 30),
        endAt: _at(10, 30),
        status: BookingStatus.completed,
      );
      final Booking cancelledC = _booking(
        id: 'cancelled-c',
        startAt: _at(10, 15),
        endAt: _at(10, 45),
        status: BookingStatus.cancelled,
      );
      final List<Booking> bookings = <Booking>[activeA, activeB, cancelledC];

      final List<int> lanes = assignLanes(bookings);

      expect(lanes[0], 0, reason: 'active-a opens lane 0');
      expect(
        lanes[1],
        1,
        reason: 'active-b overlaps active-a and is forced to lane 1',
      );
      expect(
        lanes[2],
        2,
        reason:
            'cancelled-c overlaps ONLY active-b, which sits in lane 1 — its '
            'floor must be 1 + 1 = 2, not 1 + 0; a fix that floored on '
            '"any overlapping active" rather than the highest overlapping '
            'active lane would wrongly let it land in lane 1, sharing a '
            'lane with active-b',
      );
      expect(
        bookings[1].startAt.isBefore(cancelledC.endAt) &&
            cancelledC.startAt.isBefore(bookings[1].endAt),
        isTrue,
        reason: 'fixture guard: cancelled-c must genuinely overlap active-b',
      );
      expect(
        activeA.startAt.isBefore(cancelledC.endAt) &&
            cancelledC.startAt.isBefore(activeA.endAt),
        isFalse,
        reason:
            'fixture guard: cancelled-c must NOT overlap active-a, or this '
            'stops isolating floor-by-highest-lane from floor-by-any-overlap',
      );
      for (int i = 0; i < bookings.length; i++) {
        _expectMinimalLane(bookings: bookings, lanes: lanes, index: i);
      }
    });
  });
}
