// Phase 336 — «Вихідний»: the predicate that tells a master who is NOT
// WORKING on the shown day apart from one who is working and simply has
// nothing booked.
//
// ═══════════════════════════════════════════════════════════════════════════
// THE BUG THIS FILE PINS
// ═══════════════════════════════════════════════════════════════════════════
// Before this phase both states rendered as the SAME empty column, so an owner
// scanning the board could not tell "free — book them here" from "off — do not
// book them at all". The fix is NOT "no bookings ⇒ day off": that inference is
// the bug wearing a different hat, and `columnsFor marks NOTHING on a working
// master with zero bookings` below is the test that forbids it.
//
// ═══════════════════════════════════════════════════════════════════════════
// AND THE THREE UNKNOWNS
// ═══════════════════════════════════════════════════════════════════════════
// `masterDayOff` must answer `false` — "not known to be off", never
// "working" — whenever it has not been TOLD the master is off:
//   1. the roster schedule has not resolved (or failed) — `null` map;
//   2. the master has no entry in the map at all;
//   3. no [EffectiveDay] in that entry carries the selected date.
// Each gets its own case. Case 1 is the one that matters most on a cold
// mount: greying every column for a frame and un-greying them the next would
// be a lie told twice, and it is the failure mode that made the
// roster-COMPLETE contract on `SalonRosterScheduleRepository
// .salonRosterEffectiveSchedule` load-bearing in the first place.
//
// CLOCK: every fixture is anchored to one fixed PAST Kyiv date. Nothing here
// reads the host clock, so the dev VM's Europe/Kyiv setting cannot mask
// anything and `TZ=UTC` changes no expectation.

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_bookings_screen.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';

/// The board's day — a fixed PAST Kyiv date, so no expectation here drifts.
// future-date-ok: fixed PAST date; every fixture below is derived from it
final DateTime _day = DateTime(2026, 6, 15);

/// The SAME calendar day expressed with a time component and as a UTC
/// instant — the shapes a `DateTime` can arrive in from the rail and from the
/// wire. The predicate compares y/m/d, never the instant, and these two cases
/// are what prove it.
final DateTime _dayWithTime = DateTime(2026, 6, 15, 14, 30);

/// A different day in the same month.
final DateTime _otherDay = DateTime(2026, 6, 16);

DateTime _kyivAt(int hour) => DateTime.utc(2026, 6, 15, hour - 3);

Booking _booking({
  required String id,
  required String masterId,
  int hour = 10,
}) {
  final DateTime start = _kyivAt(hour);
  return Booking(
    id: id,
    masterId: masterId,
    masterFirstName: 'Оля',
    masterLastName: 'Коваль',
    masterType: 'SALON_MASTER',
    clientFirstName: 'Марія',
    clientLastName: 'Іванюк',
    serviceId: 'service-1',
    serviceName: 'Манікюр',
    durationMinutes: 60,
    price: 500,
    startAt: start,
    endAt: start.add(const Duration(minutes: 60)),
    status: BookingStatus.confirmed,
    canReview: false,
  );
}

SalonMasterSummary _master(String id) => SalonMasterSummary(
  masterId: id,
  firstName: 'Майстер',
  lastName: id.toUpperCase(),
  type: MasterType.salonMaster,
  professionalTitle: 'Стиліст',
  avgRating: 4.8,
  reviewCount: 12,
);

EffectiveDay _working(int startHour, int endHour, {DateTime? date}) =>
    EffectiveDay(
      date: date ?? _day,
      source: EffectiveSource.template,
      intervals: <WorkInterval>[
        WorkInterval(
          start: TimeOfDay(hour: startHour, minute: 0),
          end: TimeOfDay(hour: endHour, minute: 0),
        ),
      ],
    );

EffectiveDay _dayOff({DateTime? date}) => EffectiveDay(
  date: date ?? _day,
  source: EffectiveSource.overrideDayOff,
  intervals: const <WorkInterval>[],
);

EffectiveDay _unscheduled({DateTime? date}) => EffectiveDay(
  date: date ?? _day,
  source: EffectiveSource.noSchedule,
  intervals: const <WorkInterval>[],
);

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  // 1. THE PREDICATE — what counts as "off"
  // ═════════════════════════════════════════════════════════════════════════
  group('SalonBookingsScreen.masterDayOff — positive', () {
    test('a settled OVERRIDE_DAY_OFF is a day off', () {
      expect(
        SalonBookingsScreen.masterDayOff(
          'm1',
          _day,
          <String, List<EffectiveDay>>{
            'm1': <EffectiveDay>[_dayOff()],
          },
        ),
        isTrue,
      );
    });

    test('NO_SCHEDULE is a day off — the roster-complete zero-rows master', () {
      // This is the shape the contract promises for a master with no
      // schedule rows at all. If it did not read as a day off, the
      // roster-completeness guarantee would buy nothing.
      expect(
        SalonBookingsScreen.masterDayOff(
          'm1',
          _day,
          <String, List<EffectiveDay>>{
            'm1': <EffectiveDay>[_unscheduled()],
          },
        ),
        isTrue,
      );
    });

    test('a WORKING source whose intervals resolved empty is a day off '
        '(defensive — same third case scheduleWindowFor already folds)', () {
      expect(
        SalonBookingsScreen.masterDayOff(
          'm1',
          _day,
          <String, List<EffectiveDay>>{
            'm1': <EffectiveDay>[
              EffectiveDay(
                date: _day,
                source: EffectiveSource.template,
                intervals: const <WorkInterval>[],
              ),
            ],
          },
        ),
        isTrue,
      );
    });

    test('the date is matched on y/m/d, not on the instant', () {
      // The rail hands the view a day that may carry a time component. A
      // `==` on `DateTime` would make this case `false` and silently stop
      // greying every column on the board.
      expect(
        SalonBookingsScreen.masterDayOff(
          'm1',
          _dayWithTime,
          <String, List<EffectiveDay>>{
            'm1': <EffectiveDay>[_dayOff()],
          },
        ),
        isTrue,
      );
    });
  });

  group('SalonBookingsScreen.masterDayOff — the three unknowns', () {
    test('UNKNOWN 1: a null roster schedule is NOT a day off', () {
      // THE COLD-MOUNT CASE. `null` is "the hours have not resolved, or the
      // fetch failed" — never "everybody is off".
      expect(SalonBookingsScreen.masterDayOff('m1', _day, null), isFalse);
    });

    test('UNKNOWN 2: a master absent from the map is NOT a day off', () {
      // The response is roster-COMPLETE, so an absent key means the roster
      // strip and the schedule batch disagree about who is on the team —
      // which is not evidence about anybody's hours.
      expect(
        SalonBookingsScreen.masterDayOff(
          'm1',
          _day,
          <String, List<EffectiveDay>>{
            'm2': <EffectiveDay>[_dayOff()],
          },
        ),
        isFalse,
      );
    });

    test(
      'UNKNOWN 3: no EffectiveDay for the selected date is NOT a day off',
      () {
        // The board fetches KYIV-TODAY's month; paging the rail out of it
        // leaves the selected date unrepresented. Degrades to "no marks",
        // exactly as boardWindowFor degrades to the booking-derived window.
        expect(
          SalonBookingsScreen.masterDayOff(
            'm1',
            _otherDay,
            <String, List<EffectiveDay>>{
              'm1': <EffectiveDay>[_dayOff()],
            },
          ),
          isFalse,
        );
      },
    );

    test('an EMPTY day list for a present master is NOT a day off', () {
      expect(
        SalonBookingsScreen.masterDayOff(
          'm1',
          _day,
          <String, List<EffectiveDay>>{'m1': const <EffectiveDay>[]},
        ),
        isFalse,
      );
    });

    test('a master who works the day is NOT a day off', () {
      expect(
        SalonBookingsScreen.masterDayOff(
          'm1',
          _day,
          <String, List<EffectiveDay>>{
            'm1': <EffectiveDay>[_working(9, 18)],
          },
        ),
        isFalse,
      );
    });

    test('an EXPLICIT_TIMES day with declared starts is NOT a day off', () {
      expect(
        SalonBookingsScreen.masterDayOff(
          'm1',
          _day,
          <String, List<EffectiveDay>>{
            'm1': <EffectiveDay>[
              EffectiveDay(
                date: _day,
                source: EffectiveSource.template,
                intervals: const <WorkInterval>[],
                times: const <TimeOfDay>[TimeOfDay(hour: 11, minute: 0)],
              ),
            ],
          },
        ),
        isFalse,
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // 2. THE SEAM — columnsFor carries the mark onto the columns
  // ═════════════════════════════════════════════════════════════════════════
  group('SalonBookingsScreen.columnsFor — the dayOff mark', () {
    final List<SalonMasterSummary> roster = <SalonMasterSummary>[
      _master('m1'),
      _master('m2'),
      _master('m3'),
    ];

    test(
      'BACK-COMPAT: the two-argument call marks nothing — every pre-existing '
      'caller renders exactly as before',
      () {
        final List<TimelineBoardColumn> columns =
            SalonBookingsScreen.columnsFor(<Booking>[
              _booking(id: 'a', masterId: 'm1'),
            ], roster);
        expect(
          columns.map((TimelineBoardColumn c) => c.header.dayOff),
          everyElement(isFalse),
        );
      },
    );

    test('a day passed WITHOUT a schedule still marks nothing', () {
      final List<TimelineBoardColumn> columns = SalonBookingsScreen.columnsFor(
        const <Booking>[],
        roster,
        day: _day,
      );
      expect(
        columns.map((TimelineBoardColumn c) => c.header.dayOff),
        everyElement(isFalse),
      );
    });

    test('marks exactly the masters the schedule says are off', () {
      final List<TimelineBoardColumn> columns = SalonBookingsScreen.columnsFor(
        const <Booking>[],
        roster,
        day: _day,
        rosterSchedule: <String, List<EffectiveDay>>{
          'm1': <EffectiveDay>[_working(9, 18)],
          'm2': <EffectiveDay>[_dayOff()],
          'm3': <EffectiveDay>[_unscheduled()],
        },
      );
      expect(
        columns.map((TimelineBoardColumn c) => c.header.dayOff).toList(),
        <bool>[false, true, true],
      );
    });

    test('THE BUG: a WORKING master with zero bookings is NOT marked off', () {
      // The whole point. m1 works 09–18 and nobody booked them: that is
      // «Вільний день», not «Вихідний». Any implementation that infers the
      // mark from `bookings.isEmpty` fails right here.
      final List<TimelineBoardColumn> columns = SalonBookingsScreen.columnsFor(
        const <Booking>[],
        roster,
        day: _day,
        rosterSchedule: <String, List<EffectiveDay>>{
          'm1': <EffectiveDay>[_working(9, 18)],
          'm2': <EffectiveDay>[_working(9, 18)],
          'm3': <EffectiveDay>[_working(9, 18)],
        },
      );
      expect(
        columns.every((TimelineBoardColumn c) => c.bookings.isEmpty),
        isTrue,
        reason: 'fixture precondition — all three columns ARE empty',
      );
      expect(
        columns.map((TimelineBoardColumn c) => c.header.dayOff),
        everyElement(isFalse),
      );
    });

    test(
      'NO DATA LOSS: an off master who still carries a booking keeps it',
      () {
        // A walk-in placed onto a master's day off. The salon board never
        // drops a booking (that is phase 335's whole premise), so the mark
        // must be orthogonal to the partition.
        final List<TimelineBoardColumn> columns =
            SalonBookingsScreen.columnsFor(
              <Booking>[_booking(id: 'walkin', masterId: 'm2')],
              roster,
              day: _day,
              rosterSchedule: <String, List<EffectiveDay>>{
                'm1': <EffectiveDay>[_working(9, 18)],
                'm2': <EffectiveDay>[_dayOff()],
                'm3': <EffectiveDay>[_working(9, 18)],
              },
            );
        expect(columns[1].header.dayOff, isTrue);
        expect(columns[1].bookings.map((Booking b) => b.id), <String>[
          'walkin',
        ]);
        expect(columns[1].header.bookingCount, 1);
      },
    );

    test('a null roster schedule with a day marks nothing (cold mount)', () {
      final List<TimelineBoardColumn> columns = SalonBookingsScreen.columnsFor(
        const <Booking>[],
        roster,
        day: _day,
        rosterSchedule: null,
      );
      expect(
        columns.map((TimelineBoardColumn c) => c.header.dayOff),
        everyElement(isFalse),
      );
    });
  });
}
