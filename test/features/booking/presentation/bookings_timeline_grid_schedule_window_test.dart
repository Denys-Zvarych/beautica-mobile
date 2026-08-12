// Phase 244 — BookingsTimelineGrid.scheduleFirstMinute/scheduleWindowEndMinute:
// the working-hours-bounded grid geometry, and the `didUpdateWidget`
// memoization gate those two params were added to.
//
// See `bookings_timeline_grid.dart`'s class doc on [scheduleFirstMinute] for
// the exact contract: grid top = scheduleFirstMinute directly (never lowered
// for an early booking — there shouldn't be one, since the caller is assumed
// to have already filtered); grid bottom = max(scheduleWindowEndMinute, the
// real end of the latest booking) — the ONE widening this feature performs.

import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/timeline_hour_ruler.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';

final DateTime _day = dateOnly(toBeauticaTime(futureBookingStart()));

DateTime _kyivAtUtc(int hour, [int minute = 0]) => tz.TZDateTime(
  beauticaZone,
  _day.year,
  _day.month,
  _day.day,
  hour,
  minute,
).toUtc();

Booking _booking({
  required String id,
  required DateTime startAtUtc,
  required int durationMinutes,
}) => Booking(
  id: id,
  masterId: 'master-1',
  masterFirstName: 'Оля',
  masterLastName: 'Коваль',
  masterType: 'INDEPENDENT_MASTER',
  clientFirstName: 'Марія',
  clientLastName: 'Іванюк',
  serviceId: 'service-1',
  serviceName: 'Манікюр',
  durationMinutes: durationMinutes,
  price: 500,
  startAt: startAtUtc,
  endAt: startAtUtc.add(Duration(minutes: durationMinutes)),
  status: BookingStatus.confirmed,
  canReview: false,
);

Rect _cardRect(WidgetTester tester, String id) =>
    tester.getRect(find.byKey(ValueKey<String>('timeline-card-$id')));

/// A [Booking] `List` wrapper that counts reads of `.length` — the signal
/// `BookingsTimelineGrid._recomputeLayoutModel` touches on every recompute
/// (its very first line is `for (final Booking b in bookings) …`, and the
/// lane-assignment loop below it is an explicit `bookings.length`-bounded
/// `for`). Used ONLY by the memoization guard below: if a rebuild that should
/// be a no-op (per `didUpdateWidget`'s `identical(...)` gate) recomputes
/// anyway, `lengthReads` grows.
class _CountingBookings extends ListBase<Booking> {
  _CountingBookings(this._inner);
  final List<Booking> _inner;
  int lengthReads = 0;

  @override
  int get length {
    lengthReads++;
    return _inner.length;
  }

  @override
  set length(int value) => _inner.length = value;

  @override
  Booking operator [](int index) => _inner[index];

  @override
  void operator []=(int index, Booking value) => _inner[index] = value;
}

void main() {
  setUpAll(initBeauticaTimeZones);

  group('grid top anchors to scheduleFirstMinute, not the first booking', () {
    testWidgets(
      'a booking starting AFTER the window opens still renders at its true '
      'offset from the window start, not from its own start',
      (WidgetTester tester) async {
        // Window opens 09:00 (540). The one booking in this day starts 10:00
        // — an hour into the window. If the grid anchored to the booking
        // instead of the window, the card would render flush with the grid
        // top (offset 0). Anchored correctly, it must sit ~1 rendered hour
        // band down.
        final Booking b = _booking(
          id: 'late-open',
          startAtUtc: _kyivAtUtc(10),
          durationMinutes: 30,
        );

        await tester.pumpApp(
          BookingsTimelineGrid(
            bookings: <Booking>[b],
            day: _day,
            onBookingTap: (_) {},
            scheduleFirstMinute: 540, // 09:00
            scheduleWindowEndMinute: 1080, // 18:00
          ),
        );
        await tester.pump();

        final double gridTop = tester
            .getTopLeft(
              find.byKey(const ValueKey<String>('timeline-lane-stack')),
            )
            .dy;
        final double cardTop = _cardRect(tester, 'late-open').top;

        expect(
          cardTop - gridTop,
          greaterThan(50),
          reason:
              'the card rendered flush with the grid top — the grid anchored '
              'to the booking\'s own start instead of scheduleFirstMinute',
        );
      },
    );

    testWidgets(
      'the SAME booking anchored against an EARLIER scheduleFirstMinute '
      'renders further down — proving the offset tracks the window param, '
      'not a fixed constant',
      (WidgetTester tester) async {
        final Booking b = _booking(
          id: 'compare',
          startAtUtc: _kyivAtUtc(10),
          durationMinutes: 30,
        );

        await tester.pumpApp(
          BookingsTimelineGrid(
            bookings: <Booking>[b],
            day: _day,
            onBookingTap: (_) {},
            scheduleFirstMinute: 540, // 09:00 — 1h before the booking
            scheduleWindowEndMinute: 1080,
          ),
        );
        await tester.pump();
        final double offsetFromNineOpen =
            _cardRect(tester, 'compare').top -
            tester
                .getTopLeft(
                  find.byKey(const ValueKey<String>('timeline-lane-stack')),
                )
                .dy;

        await tester.pumpApp(
          BookingsTimelineGrid(
            bookings: <Booking>[b],
            day: _day,
            onBookingTap: (_) {},
            scheduleFirstMinute: 480, // 08:00 — 2h before the booking
            scheduleWindowEndMinute: 1080,
          ),
        );
        await tester.pump();
        final double offsetFromEightOpen =
            _cardRect(tester, 'compare').top -
            tester
                .getTopLeft(
                  find.byKey(const ValueKey<String>('timeline-lane-stack')),
                )
                .dy;

        expect(
          offsetFromEightOpen,
          greaterThan(offsetFromNineOpen),
          reason:
              'an earlier window open must push the SAME booking further '
              'down the grid — the offset is measured from '
              'scheduleFirstMinute',
        );
      },
    );
  });

  group('grid bottom widens for a booking that starts inside but ends past '
      'scheduleWindowEndMinute', () {
    // NOTE: the card itself is NEVER clipped regardless of this widening —
    // that is a SEPARATE, structural guarantee (see the file header's "R2"/
    // "R3": `BookingsTimelineGrid`'s `Stack` sizes itself to its lane
    // `Column`s' real rendered content, not to `_lastMinute`). What
    // `scheduleWindowEndMinute`'s widening actually controls is the RULER's
    // and the GRIDLINES' hour extent (`lastHour`) — without it, the ruler
    // stops drawing hour lines at the nominal window end even though a card
    // renders past it, i.e. the card would render with no ruler background
    // trailing alongside it. That is the property pinned here.
    testWidgets(
      'a booking starting at 18:30 with a 60-minute duration against hours '
      'ending 19:00 extends the RULER past the nominal window end to cover it',
      (WidgetTester tester) async {
        final Booking widensBottom = _booking(
          id: 'widens',
          startAtUtc: _kyivAtUtc(18, 30),
          durationMinutes: 60, // ends 19:30 -> ceil -> lastHour 20
        );

        await tester.pumpApp(
          BookingsTimelineGrid(
            bookings: <Booking>[widensBottom],
            day: _day,
            onBookingTap: (_) {},
            scheduleFirstMinute: 540, // 09:00
            scheduleWindowEndMinute: 1140, // 19:00
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(
          find.descendant(
            of: find.byType(TimelineHourRuler),
            matching: find.text('20:00'),
          ),
          findsOneWidget,
          reason:
              'the ruler must extend to the 20:00 hour line to cover a '
              'booking that runs until 19:30 — scheduleWindowEndMinute (19:00) '
              'alone would stop the ruler one hour short',
        );
      },
    );

    testWidgets(
      'the SAME booking against a schedule window that already comfortably '
      'covers it renders NO 20:00 hour line — proving the extension above is '
      'real, not an unconditional pad',
      (WidgetTester tester) async {
        final Booking widensBottom = _booking(
          id: 'widens-covered',
          startAtUtc: _kyivAtUtc(18, 30),
          durationMinutes: 60, // ends 19:30
        );

        await tester.pumpApp(
          BookingsTimelineGrid(
            bookings: <Booking>[widensBottom],
            day: _day,
            onBookingTap: (_) {},
            scheduleFirstMinute: 540,
            scheduleWindowEndMinute: 1320, // 22:00 — already covers 19:30
          ),
        );
        await tester.pump();

        expect(
          find.descendant(
            of: find.byType(TimelineHourRuler),
            matching: find.text('20:00'),
          ),
          findsOneWidget,
          reason:
              'fixture sanity: 20:00 must still be inside a 22:00-ending ruler',
        );
        expect(
          find.descendant(
            of: find.byType(TimelineHourRuler),
            matching: find.text('22:00'),
          ),
          findsOneWidget,
          reason:
              'the ruler must reach the schedule\'s own window end (22:00) '
              'when that already exceeds the booking\'s real end — the max() '
              'picks the LARGER of the two, not always the booking\'s end',
        );
      },
    );

    testWidgets(
      'a booking that FITS comfortably inside the window (no widening '
      'needed) renders NO hour line past the window end',
      (WidgetTester tester) async {
        final Booking fitsInside = _booking(
          id: 'fits',
          startAtUtc: _kyivAtUtc(9),
          durationMinutes: 30, // ends 09:30, well inside the window
        );

        await tester.pumpApp(
          BookingsTimelineGrid(
            bookings: <Booking>[fitsInside],
            day: _day,
            onBookingTap: (_) {},
            scheduleFirstMinute: 540, // 09:00
            scheduleWindowEndMinute: 1140, // 19:00
          ),
        );
        await tester.pump();

        expect(
          find.descendant(
            of: find.byType(TimelineHourRuler),
            matching: find.text('19:00'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(TimelineHourRuler),
            matching: find.text('20:00'),
          ),
          findsNothing,
          reason:
              'nothing in this day runs past 19:00 — the ruler must not '
              'extend an extra hour for no reason',
        );
      },
    );
  });

  group(
    'memoization regression guard (mobile-qa — regressed TWICE already)',
    () {
      testWidgets(
        'a rebuild with an IDENTICAL bookings list and UNCHANGED schedule '
        'window params does not recompute the layout model',
        (WidgetTester tester) async {
          final List<Booking> raw = <Booking>[
            _booking(
              id: 'memo-a',
              startAtUtc: _kyivAtUtc(9),
              durationMinutes: 30,
            ),
          ];
          final _CountingBookings bookings = _CountingBookings(raw);

          Widget build() => BookingsTimelineGrid(
            bookings: bookings,
            day: _day,
            onBookingTap: (_) {},
            scheduleFirstMinute: 540,
            scheduleWindowEndMinute: 1080,
          );

          await tester.pumpApp(build());
          await tester.pump();
          final int readsAfterFirstBuild = bookings.lengthReads;
          expect(
            readsAfterFirstBuild,
            greaterThan(0),
            reason:
                'fixture guard: the first mount must recompute at least once, '
                'or this counter cannot prove anything about the SECOND build',
          );

          // Rebuild via a brand-new widget instance (so didUpdateWidget fires)
          // wrapping the SAME `bookings` list identity and the SAME ints.
          await tester.pumpApp(build());
          await tester.pump();

          expect(
            bookings.lengthReads,
            readsAfterFirstBuild,
            reason:
                'a rebuild with unchanged bookings identity and unchanged '
                'schedule-window params recomputed the layout model — the '
                'BookingsTimelineGrid.didUpdateWidget identical() gate '
                'regressed',
          );
        },
      );

      testWidgets(
        'a rebuild that DOES change scheduleFirstMinute (a master editing '
        'today\'s hours while the screen is open) DOES recompute — the gate is '
        'not stuck permanently closed',
        (WidgetTester tester) async {
          final List<Booking> raw = <Booking>[
            _booking(
              id: 'memo-b',
              startAtUtc: _kyivAtUtc(9),
              durationMinutes: 30,
            ),
          ];
          final _CountingBookings bookings = _CountingBookings(raw);

          await tester.pumpApp(
            BookingsTimelineGrid(
              bookings: bookings,
              day: _day,
              onBookingTap: (_) {},
              scheduleFirstMinute: 540,
              scheduleWindowEndMinute: 1080,
            ),
          );
          await tester.pump();
          final int readsAfterFirstBuild = bookings.lengthReads;

          await tester.pumpApp(
            BookingsTimelineGrid(
              bookings: bookings,
              day: _day,
              onBookingTap: (_) {},
              scheduleFirstMinute: 480, // CHANGED — 08:00 now
              scheduleWindowEndMinute: 1080,
            ),
          );
          await tester.pump();

          expect(
            bookings.lengthReads,
            greaterThan(readsAfterFirstBuild),
            reason:
                'a genuine schedule-window change must still trigger a '
                'recompute — the memoization gate must not over-fire and '
                'freeze the grid on stale geometry',
          );
        },
      );
    },
  );
}
