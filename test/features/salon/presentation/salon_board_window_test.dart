// Phase 335 QA — the salon «Записи» board's UNION timeline window, and the
// one correctness property the whole phase exists to establish.
//
// ═══════════════════════════════════════════════════════════════════════════
// THE PROPERTY
// ═══════════════════════════════════════════════════════════════════════════
// `phase-244-master-timeline-working-hours-window.md` established, for the
// MASTER board: "a booking starting OUTSIDE the window is dropped entirely —
// never rendered". On a manager's board that same rule is DATA LOSS: a 22:00
// walk-in must not vanish because the master it belongs to finishes at 20:00.
//
// The salon board does not get a second filter, a flag or a branch — it gets a
// WIDER WINDOW, chosen so that the ONE existing filter
// (`bookingsInsideScheduleWindow`, unchanged, shared with the master path) is
// provably VACUOUS on it.
//
// ═══════════════════════════════════════════════════════════════════════════
// WHY `identical()` AND NOT A COUNT
// ═══════════════════════════════════════════════════════════════════════════
// `bookingsInsideScheduleWindow` returns its INPUT LIST INSTANCE when nothing
// was excluded, and a freshly-allocated `sublist`-seeded copy the moment
// anything was (see its own doc — the identity is a deliberate, documented
// memoisation contract, not an implementation accident). So `identical(out,
// in)` is an EXACT "excluded nothing" oracle.
//
// `out.length == in.length` is not. It would pass a filter that dropped one
// booking and duplicated another, and — more to the point here — it degrades
// into a tautology the moment a fixture happens to contain only bookings that
// sit comfortably inside the window. The `identical` assertion cannot be
// defanged that way, and the NEGATIVE CONTROL group below proves it has teeth
// on these exact fixtures: fed the per-MASTER window instead of the union, the
// very same call returns a DIFFERENT instance with the 22:00 walk-in missing.
// Without that control, every `identical` expectation here would be unfalsified.

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/schedule_timeline_window.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_bookings_screen.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';

/// The board's day. A fixed PAST Kyiv date, so nothing here drifts with the
/// host clock and the dev VM's Europe/Kyiv setting cannot mask a conversion
/// bug (this suite is also run under `TZ=UTC`).
// future-date-ok: fixed PAST date; every fixture below is derived from it
final DateTime _day = DateTime(2026, 6, 15);

/// A Kyiv wall-clock instant on [_day], expressed as the UTC instant a
/// `Booking.startAt` actually carries. Kyiv is UTC+3 in June.
DateTime _kyivAt(int hour, [int minute = 0]) =>
    DateTime.utc(2026, 6, 15, hour - 3, minute);

Booking _booking({
  required String id,
  required String masterId,
  required int hour,
  int minute = 0,
  int durationMinutes = 60,
}) {
  final DateTime start = _kyivAt(hour, minute);
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
    durationMinutes: durationMinutes,
    price: 500,
    startAt: start,
    endAt: start.add(Duration(minutes: durationMinutes)),
    status: BookingStatus.confirmed,
    canReview: false,
  );
}

/// An INTERVAL working day: `[startHour:00, endHour:00)`.
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

/// A settled day off — [scheduleWindowFor] returns `null` for it, so it must
/// contribute nothing to the union.
EffectiveDay _dayOff({DateTime? date}) => EffectiveDay(
  date: date ?? _day,
  source: EffectiveSource.overrideDayOff,
  intervals: const <WorkInterval>[],
);

/// A master the roster carries with NO schedule rows at all. The batch
/// endpoint is ROSTER-COMPLETE and emits exactly this — it is what makes "off
/// today" distinguishable from "not loaded".
EffectiveDay _noSchedule({DateTime? date}) => EffectiveDay(
  date: date ?? _day,
  source: EffectiveSource.noSchedule,
  intervals: const <WorkInterval>[],
);

/// An EXPLICIT_TIMES day — discrete declared start times, no interval ends.
EffectiveDay _declared(List<int> hours, {DateTime? date}) => EffectiveDay(
  date: date ?? _day,
  source: EffectiveSource.template,
  intervals: const <WorkInterval>[],
  times: <TimeOfDay>[for (final int h in hours) TimeOfDay(hour: h, minute: 0)],
);

/// Runs the union over [rosterDays] with [items]' own Kyiv span folded in —
/// exactly the composition `SalonBookingsScreen.boardWindowFor` performs.
ScheduleTimelineWindow? _unionFor(
  List<EffectiveDay> rosterDays,
  List<Booking> items,
) {
  final ({int firstStartMinute, int lastEndMinute})? span = bookingsMinuteSpan(
    items,
    _day,
  );
  return salonBoardWindow(
    rosterDays: rosterDays,
    bookingFirstMinute: span?.firstStartMinute,
    bookingLastEndMinute: span?.lastEndMinute,
  );
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // 1. salonBoardWindow — the union itself, as a pure function.
  // ═══════════════════════════════════════════════════════════════════════
  group('salonBoardWindow — the roster union', () {
    test('spans the union of every master\'s hours, not one master\'s', () {
      final ScheduleTimelineWindow? window = salonBoardWindow(
        rosterDays: <EffectiveDay>[_working(9, 18), _working(11, 20)],
        bookingFirstMinute: null,
        bookingLastEndMinute: null,
      );

      // 09:00 from the FIRST master, 20:00 from the SECOND — neither master's
      // own window is this pair, which is the whole point.
      expect(window?.firstMinute, 9 * 60);
      expect(window?.windowEndMinute, 20 * 60);
    });

    test('a day-off master contributes NOTHING to the union', () {
      final ScheduleTimelineWindow? window = salonBoardWindow(
        rosterDays: <EffectiveDay>[_working(10, 17), _dayOff()],
        bookingFirstMinute: null,
        bookingLastEndMinute: null,
      );

      expect(window?.firstMinute, 10 * 60);
      expect(window?.windowEndMinute, 17 * 60);
    });

    test(
      'a NO_SCHEDULE master (roster-complete, zero schedule rows) contributes '
      'NOTHING — it is not silently read as 00:00–00:00',
      () {
        final ScheduleTimelineWindow? window = salonBoardWindow(
          rosterDays: <EffectiveDay>[_noSchedule(), _working(12, 15)],
          bookingFirstMinute: null,
          bookingLastEndMinute: null,
        );

        expect(window?.firstMinute, 12 * 60);
        expect(window?.windowEndMinute, 15 * 60);
      },
    );

    test(
      'returns null when NO master works — the caller then renders exactly as '
      'before this feature (booking-derived bounds)',
      () {
        expect(
          salonBoardWindow(
            rosterDays: <EffectiveDay>[_dayOff(), _noSchedule()],
            // Bookings present, and STILL null: the function deliberately does
            // not degenerate into "a window equal to the booking span", which
            // would be the same pixels by a longer route AND would flip the
            // `window == null` tests `bookings_discovery_view.dart` keys
            // several pre-existing behaviours off.
            bookingFirstMinute: 22 * 60,
            bookingLastEndMinute: 23 * 60,
          ),
          isNull,
        );
      },
    );

    test('an empty roster returns null', () {
      expect(
        salonBoardWindow(
          rosterDays: const <EffectiveDay>[],
          bookingFirstMinute: null,
          bookingLastEndMinute: null,
        ),
        isNull,
      );
    });

    test('the bottom widens to the latest booking END, never narrows', () {
      final ScheduleTimelineWindow? window = salonBoardWindow(
        rosterDays: <EffectiveDay>[_working(9, 20)],
        bookingFirstMinute: 22 * 60,
        // 22:00 + 60min — past the 20:00 close.
        bookingLastEndMinute: 23 * 60,
      );

      expect(window?.windowEndMinute, 23 * 60);
      // …and the TOP still comes from the roster: a late-only booking day must
      // not chop the morning off the ruler.
      expect(window?.firstMinute, 9 * 60);
    });

    test('the top widens to the earliest booking START, never narrows', () {
      final ScheduleTimelineWindow? window = salonBoardWindow(
        rosterDays: <EffectiveDay>[_working(9, 20)],
        bookingFirstMinute: 7 * 60,
        bookingLastEndMinute: 8 * 60,
      );

      expect(window?.firstMinute, 7 * 60);
      // The bottom stays at the roster's close — a morning-only booking day
      // still draws ruler down to 20:00, which is why neither term alone is
      // the right answer.
      expect(window?.windowEndMinute, 20 * 60);
    });

    test(
      'the result is ALWAYS isExplicitTimes: false, even when a roster master '
      'declares discrete times — a union has no single declared-time list',
      () {
        final ScheduleTimelineWindow? window = salonBoardWindow(
          rosterDays: <EffectiveDay>[
            _declared(<int>[10, 14, 19]),
          ],
          bookingFirstMinute: null,
          bookingLastEndMinute: null,
        );

        expect(window?.isExplicitTimes, isFalse);
        // The latest DECLARED START enters the union as a window END.
        expect(window?.firstMinute, 10 * 60);
        expect(window?.windowEndMinute, 19 * 60);
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 2. THE VACUITY PROOF — the entire point of the phase.
  //
  //    `bookingsInsideScheduleWindow` returns the SAME LIST INSTANCE it was
  //    handed iff it excluded nothing. Asserted with `identical`, never a
  //    count — see this file's header.
  // ═══════════════════════════════════════════════════════════════════════
  group('the union makes bookingsInsideScheduleWindow VACUOUS', () {
    /// The shared assertion: under the union window, the filter is the
    /// identity function on [items].
    void expectNothingDropped(
      List<EffectiveDay> rosterDays,
      List<Booking> items,
    ) {
      final ScheduleTimelineWindow? window = _unionFor(rosterDays, items);
      expect(
        window,
        isNotNull,
        reason:
            'fixture bug: this group needs a resolved union window, '
            'otherwise the filter below is never exercised at all',
      );
      if (window == null) return;
      final List<Booking> visible = bookingsInsideScheduleWindow(
        items,
        _day,
        window,
      );
      expect(
        identical(visible, items),
        isTrue,
        reason:
            'bookingsInsideScheduleWindow returned a DIFFERENT list instance, '
            'which it only ever does when it excluded something. On a salon '
            'board that is data loss. Dropped: '
            '${items.length - visible.length} of ${items.length}.',
      );
    }

    test(
      'a 22:00 walk-in survives a roster that closes at 20:00 — THE bug this '
      'phase exists to make impossible',
      () {
        expectNothingDropped(
          <EffectiveDay>[_working(9, 20), _working(10, 18)],
          <Booking>[
            _booking(id: 'b-morning', masterId: 'm1', hour: 10),
            _booking(id: 'b-walkin', masterId: 'm2', hour: 22),
          ],
        );
      },
    );

    test('a 07:00 early bird survives a roster that opens at 09:00', () {
      expectNothingDropped(
        <EffectiveDay>[_working(9, 18)],
        <Booking>[
          _booking(id: 'b-early', masterId: 'm1', hour: 7),
          _booking(id: 'b-normal', masterId: 'm1', hour: 12),
        ],
      );
    });

    test('a booking starting exactly AT the union\'s top boundary survives '
        '(includesStart is INCLUSIVE at firstMinute)', () {
      expectNothingDropped(
        <EffectiveDay>[_working(9, 18)],
        <Booking>[_booking(id: 'b-open', masterId: 'm1', hour: 9)],
      );
    });

    test(
      'a booking starting exactly AT a roster master\'s CLOSING time survives '
      '— its own END is what pushes the end-EXCLUSIVE bottom past it',
      () {
        expectNothingDropped(
          <EffectiveDay>[_working(9, 18)],
          <Booking>[_booking(id: 'b-closing', masterId: 'm1', hour: 18)],
        );
      },
    );

    test(
      'a booking starting exactly AT an EXPLICIT_TIMES master\'s LAST declared '
      'time survives — the union drops the inclusive explicit-times boundary '
      'rule, so only the booking\'s own end can rescue it',
      () {
        expectNothingDropped(
          <EffectiveDay>[
            _declared(<int>[10, 19]),
          ],
          <Booking>[_booking(id: 'b-last-slot', masterId: 'm1', hour: 19)],
        );
      },
    );

    test(
      'a ZERO-DURATION booking at the union\'s bottom survives — the one shape '
      'that could reintroduce the loss, removed by bookingsMinuteSpan\'s '
      'one-minute duration floor',
      () {
        expectNothingDropped(
          <EffectiveDay>[_working(9, 18)],
          <Booking>[
            _booking(
              id: 'b-zero',
              masterId: 'm1',
              hour: 21,
              durationMinutes: 0,
            ),
          ],
        );
      },
    );

    test('an empty day is vacuously safe (same const instance back)', () {
      final ScheduleTimelineWindow? window = _unionFor(<EffectiveDay>[
        _working(9, 18),
      ], const <Booking>[]);
      expect(window, isNotNull);
      if (window == null) return;
      const List<Booking> items = <Booking>[];
      expect(
        identical(bookingsInsideScheduleWindow(items, _day, window), items),
        isTrue,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 3. NEGATIVE CONTROL — proving the `identical` assertions above are not
  //    tautologies on these fixtures.
  //
  //    Same bookings, same day, same filter — but the MASTER-scoped window
  //    (`scheduleWindowFor`, phase 244's rule) instead of the union. The
  //    filter MUST drop the walk-in and hand back a different instance. If
  //    this test ever goes green-by-identity, every expectation in group 2 has
  //    silently stopped meaning anything.
  // ═══════════════════════════════════════════════════════════════════════
  group('negative control — the per-MASTER window DOES drop the walk-in', () {
    test(
      'scheduleWindowFor(09:00–20:00) excludes a 22:00 walk-in and returns a '
      'DIFFERENT list instance',
      () {
        final List<Booking> items = <Booking>[
          _booking(id: 'b-morning', masterId: 'm1', hour: 10),
          _booking(id: 'b-walkin', masterId: 'm2', hour: 22),
        ];
        final ScheduleTimelineWindow? masterWindow = scheduleWindowFor(
          _working(9, 20),
        );
        expect(masterWindow, isNotNull);
        if (masterWindow == null) return;

        final List<Booking> visible = bookingsInsideScheduleWindow(
          items,
          _day,
          masterWindow,
        );

        expect(identical(visible, items), isFalse);
        expect(visible.map((Booking b) => b.id), <String>['b-morning']);
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 4. SalonBookingsScreen.boardWindowFor — the screen's own composition:
  //    pick the day's rows out of a MONTH-wide, roster-keyed map, fold in the
  //    bookings' Kyiv span, hand the union back.
  // ═══════════════════════════════════════════════════════════════════════
  group('SalonBookingsScreen.boardWindowFor', () {
    test('null when the hours fetch has not resolved (or failed)', () {
      expect(
        SalonBookingsScreen.boardWindowFor(
          <Booking>[_booking(id: 'b1', masterId: 'm1', hour: 10)],
          _day,
          null,
        ),
        isNull,
      );
    });

    test('unions across masters, keyed out of the roster map', () {
      final ScheduleTimelineWindow? window = SalonBookingsScreen.boardWindowFor(
        const <Booking>[],
        _day,
        <String, List<EffectiveDay>>{
          'm1': <EffectiveDay>[_working(9, 17)],
          'm2': <EffectiveDay>[_working(11, 21)],
        },
      );

      expect(window?.firstMinute, 9 * 60);
      expect(window?.windowEndMinute, 21 * 60);
    });

    test(
      'reads ONLY the selected day\'s rows out of the month — a neighbouring '
      'date\'s hours never leak into the window',
      () {
        final DateTime otherDay = DateTime(2026, 6, 16);
        final ScheduleTimelineWindow? window =
            SalonBookingsScreen.boardWindowFor(
              const <Booking>[],
              _day,
              <String, List<EffectiveDay>>{
                'm1': <EffectiveDay>[
                  _working(9, 17),
                  // A wildly different shift on the NEXT day. If the lookup
                  // ignored the date this would move both bounds.
                  _working(5, 23, date: otherDay),
                ],
              },
            );

        expect(window?.firstMinute, 9 * 60);
        expect(window?.windowEndMinute, 17 * 60);
      },
    );

    test('null when the selected day is outside the fetched month — the screen '
        'keys the fetch on Kyiv-today\'s month, so paging away degrades to the '
        'booking-derived window rather than to a wrong one', () {
      expect(
        SalonBookingsScreen.boardWindowFor(
          const <Booking>[],
          DateTime(2026, 7, 4),
          <String, List<EffectiveDay>>{
            'm1': <EffectiveDay>[_working(9, 17)],
          },
        ),
        isNull,
      );
    });

    // ─────────────────────────────────────────────────────────────────────
    // QA 2026-09-17 — THE TWO TESTS ABOVE DO NOT PIN THE MONTH OR THE YEAR.
    //
    // Both of them, and the neighbouring-date test before them, pick dates
    // whose DAY-OF-MONTH already differs from the fixture's (4 and 16 vs 15).
    // Mutation-proved: deleting `d.date.year == day.year &&
    // d.date.month == day.month` from `boardWindowFor`'s row filter — leaving
    // a bare `d.date.day == day.day` — kept ALL 24 tests in this file green.
    //
    // That is exactly the month-paging degradation the screen documents: the
    // fetch is keyed on Kyiv-TODAY's month, so paging the rail into another
    // month must find NO row and fall back to the booking-derived window.
    // Under the day-only predicate it would instead silently apply the SAME
    // day-number's hours from the fetched month — a wrong window, drawn
    // confidently, on a board whose whole point is that it is trustworthy.
    //
    // These two collide the day-of-month deliberately, so only the month (and
    // the year) component can decide the outcome.
    // ─────────────────────────────────────────────────────────────────────

    test(
      'null when the selected day shares its DAY-OF-MONTH with a fetched row '
      'but falls in a different MONTH — the row filter is a full date match, '
      'not a day-number match',
      () {
        expect(
          SalonBookingsScreen.boardWindowFor(
            const <Booking>[],
            // Same day-of-month as `_day` (the 15th), one month later.
            DateTime(2026, 7, 15),
            <String, List<EffectiveDay>>{
              'm1': <EffectiveDay>[_working(9, 17)],
            },
          ),
          isNull,
          reason:
              'June 15th\'s hours were applied to July 15th — the board would '
              'draw a confident, wrong window instead of degrading to the '
              'booking-derived one',
        );
      },
    );

    test(
      'null when the selected day shares its DAY and MONTH with a fetched row '
      'but falls in a different YEAR',
      () {
        expect(
          SalonBookingsScreen.boardWindowFor(
            const <Booking>[],
            // A PAST year, so this fixture can never age into a future date.
            DateTime(2025, 6, 15),
            <String, List<EffectiveDay>>{
              'm1': <EffectiveDay>[_working(9, 17)],
            },
          ),
          isNull,
        );
      },
    );

    test('folds the day\'s booking span in — the 22:00 walk-in widens it', () {
      final ScheduleTimelineWindow? window = SalonBookingsScreen.boardWindowFor(
        <Booking>[_booking(id: 'b-walkin', masterId: 'm1', hour: 22)],
        _day,
        <String, List<EffectiveDay>>{
          'm1': <EffectiveDay>[_working(9, 20)],
        },
      );

      expect(window?.firstMinute, 9 * 60);
      expect(window?.windowEndMinute, 23 * 60);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 5. bookingsMinuteSpan — the Kyiv conversion the union is fed from.
  // ═══════════════════════════════════════════════════════════════════════
  group('bookingsMinuteSpan', () {
    test('null for an empty day', () {
      expect(bookingsMinuteSpan(const <Booking>[], _day), isNull);
    });

    test('earliest START and latest END, in Kyiv minutes', () {
      final ({int firstStartMinute, int lastEndMinute})? span =
          bookingsMinuteSpan(<Booking>[
            _booking(id: 'b2', masterId: 'm1', hour: 14, minute: 30),
            _booking(id: 'b1', masterId: 'm1', hour: 9, minute: 15),
          ], _day);

      expect(span?.firstStartMinute, 9 * 60 + 15);
      // 14:30 + 60min.
      expect(span?.lastEndMinute, 15 * 60 + 30);
    });

    test('floors a zero-duration booking at one minute — the floor the vacuity '
        'proof depends on', () {
      final ({int firstStartMinute, int lastEndMinute})? span =
          bookingsMinuteSpan(<Booking>[
            _booking(
              id: 'b-zero',
              masterId: 'm1',
              hour: 12,
              durationMinutes: 0,
            ),
          ], _day);

      expect(span?.firstStartMinute, 12 * 60);
      expect(span?.lastEndMinute, 12 * 60 + 1);
    });
  });
}
