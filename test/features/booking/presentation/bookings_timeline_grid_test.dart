// Phase 7.10 — BookingsTimelineGrid + TimelineHourRuler.
//
// R1 REGRESSION (mandatory) — see the file header of
// `bookings_timeline_grid.dart`. The design's scalar-hour extent formula goes
// NEGATIVE whenever the last booking's Kyiv end hour-of-day is numerically
// smaller than the first booking's Kyiv start hour-of-day — reachable on a
// SINGLE day (a 23:30 booking with a 60-minute duration ends 00:30 the next
// day). The fix computes the extent in minutes-since-the-selected-day's-Kyiv-
// midnight instead, so a post-midnight end yields > 1440 rather than
// wrapping to a small number.
//
// KYIV-CORRECTNESS — every position must read through `toBeauticaTime`, never
// `.toLocal()` or a raw `.hour` off `Booking.startAt` (canonical UTC). The
// witness case below is a DATE-CROSSING instant (22:00 UTC = 01:00 Kyiv the
// NEXT day), mirroring `slot_time_tz_regression_test.dart`'s technique: the
// expected position is derived from the KNOWN Kyiv wall-clock, so a
// UTC-naive implementation (reading `.hour` off the raw UTC `startAt`) would
// compute a materially different — and wrong — `top` offset.

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/timeline_hour_ruler.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

Booking _booking({
  required String id,
  required DateTime startAtUtc,
  required int durationMinutes,
  String? clientFirstName = 'Марія',
  String? clientLastName = 'Іванюк',
}) => Booking(
  id: id,
  masterId: 'master-1',
  masterFirstName: 'Оля',
  masterLastName: 'Коваль',
  masterType: 'INDEPENDENT_MASTER',
  clientFirstName: clientFirstName,
  clientLastName: clientLastName,
  serviceId: 'service-1',
  serviceName: 'Манікюр',
  durationMinutes: durationMinutes,
  price: 500,
  startAt: startAtUtc,
  endAt: startAtUtc.add(Duration(minutes: durationMinutes)),
  status: BookingStatus.confirmed,
  canReview: false,
);

/// Finds the [Positioned] ancestor of the [MasterBookingCard] keyed
/// `timeline-card-<id>` — the geometry a test actually needs to assert on.
Positioned _positionedOf(WidgetTester tester, String bookingId) {
  return tester.widget<Positioned>(
    find.ancestor(
      of: find.byKey(ValueKey<String>('timeline-card-$bookingId')),
      matching: find.byType(Positioned),
    ),
  );
}

void main() {
  setUpAll(initBeauticaTimeZones);

  group('R1 regression — negative grid height', () {
    // The exact case from the phase doc: a 23:30 Kyiv booking with a
    // 60-minute duration (ends 00:30 the NEXT Kyiv day) alongside a 09:00
    // Kyiv booking, both on the SAME selected day. 2026-07-20 is Kyiv summer
    // time (UTC+3): 09:00 Kyiv == 06:00 UTC; 23:30 Kyiv == 20:30 UTC.
    final DateTime day = DateTime(2026, 7, 20);
    final Booking morning = _booking(
      id: 'r1-morning',
      startAtUtc: DateTime.utc(2026, 7, 20, 6),
      durationMinutes: 60,
    );
    final Booking lateNight = _booking(
      id: 'r1-late',
      startAtUtc: DateTime.utc(2026, 7, 20, 20, 30),
      durationMinutes: 60,
    );

    testWidgets('renders without throwing and the grid extent is positive', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(
        BookingsTimelineGrid(
          bookings: <Booking>[morning, lateNight],
          day: day,
          onBookingTap: (_) {},
        ),
      );
      await tester.pump();

      // The mere absence of a thrown exception during pump IS the R1
      // assertion. Proven by mutation: substituting the design's verbatim
      // scalar-hour formula (`(latestEnd.hour - firstHour) + latestEnd
      // .minute / 60.0`) for this exact shape throws
      // "BoxConstraints has a negative minimum height" while building a
      // SizedBox fed by that negative computed height — see the dev-session
      // record for the captured before/after transcript.
      expect(tester.takeException(), isNull);

      final double gridHeight = tester
          .widget<SizedBox>(
            find.ancestor(
              of: find.byKey(const ValueKey<String>('timeline-lane-stack')),
              matching: find.byType(SizedBox),
            ),
          )
          .height!;
      expect(gridHeight, greaterThan(0));

      // Both cards must actually be present (not silently dropped).
      expect(
        find.byKey(const ValueKey<String>('timeline-card-r1-morning')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-card-r1-late')),
        findsOneWidget,
      );
    });
  });

  group('ruler hour labels past midnight', () {
    testWidgets('an hour offset of 24 reads "00:00", never "24:00"', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(
        const Center(child: TimelineHourRuler(firstHour: 23, lastHour: 25)),
      );

      expect(find.text('23:00'), findsOneWidget);
      expect(find.text('00:00'), findsOneWidget);
      expect(find.text('01:00'), findsOneWidget);
      expect(find.text('24:00'), findsNothing);
      expect(find.text('25:00'), findsNothing);
    });
  });

  group('card position reads through toBeauticaTime (Kyiv wall-clock)', () {
    // WHY THE RULER LABEL, NOT JUST THE CARD's `top`
    // -----------------------------------------------
    // A single booking's `top` is trivially 0 regardless of which timezone
    // the extent is computed in (it anchors its own extent), so it cannot
    // distinguish a Kyiv-correct implementation from a UTC-naive one — both
    // would print `top: 0`. The RULER'S rendered hour label, however, is an
    // ABSOLUTE wall-clock reading and genuinely differs: 2026-07-17T22:00Z is
    // 2026-07-18T01:00 in Kyiv (UTC+3) — a DIFFERENT calendar day than the
    // raw UTC field (the same witness shape
    // `slot_time_tz_regression_test.dart` uses). A Kyiv-correct
    // implementation, asked for the 18th's timeline, renders "01:00"/"02:00".
    // A UTC-naive implementation (measuring the raw UTC instant against the
    // 18th's UTC midnight) computes a NEGATIVE minutes-since-day-start and
    // renders "22:00"/"23:00" instead — proven by mutation below.
    testWidgets(
      'the ruler shows the KYIV hour ("01:00"), not the raw UTC hour ("22:00")',
      (WidgetTester tester) async {
        final DateTime day = DateTime(2026, 7, 18);
        final DateTime crossing = DateTime.utc(
          2026,
          7,
          17,
          22,
        ); // 01:00 Kyiv, 18th
        final Booking b = _booking(
          id: 'crossing',
          startAtUtc: crossing,
          durationMinutes: 60,
        );

        await tester.pumpApp(
          BookingsTimelineGrid(
            bookings: <Booking>[b],
            day: day,
            onBookingTap: (_) {},
          ),
        );
        await tester.pump();

        expect(find.text('01:00'), findsOneWidget);
        expect(find.text('02:00'), findsOneWidget);
        expect(find.text('22:00'), findsNothing);
        expect(find.text('23:00'), findsNothing);

        // Sanity: with no other booking narrowing the extent, the single
        // card anchors its own extent, so `top` is 0 regardless of zone —
        // asserted here for completeness, NOT as the zone-correctness proof.
        expect(_positionedOf(tester, 'crossing').top, 0);
      },
    );
  });

  group('minimum tap target', () {
    testWidgets('a 15-minute booking still meets the 48dp floor', (
      WidgetTester tester,
    ) async {
      final DateTime day = DateTime(2026, 7, 20);
      final Booking short = _booking(
        id: 'short',
        startAtUtc: DateTime.utc(2026, 7, 20, 6), // 09:00 Kyiv
        durationMinutes: 15,
      );

      await tester.pumpApp(
        BookingsTimelineGrid(
          bookings: <Booking>[short],
          day: day,
          onBookingTap: (_) {},
        ),
      );
      await tester.pump();

      final Positioned positioned = _positionedOf(tester, 'short');
      expect(positioned.height, isNotNull);
      expect(positioned.height!, greaterThanOrEqualTo(48));
    });
  });

  group('overlapping bookings render in distinct lanes', () {
    testWidgets('two overlapping bookings get different left offsets', (
      WidgetTester tester,
    ) async {
      final DateTime day = DateTime(2026, 7, 20);
      final Booking a = _booking(
        id: 'lane-a',
        startAtUtc: DateTime.utc(2026, 7, 20, 6), // 09:00 Kyiv
        durationMinutes: 60,
      );
      final Booking b = _booking(
        id: 'lane-b',
        startAtUtc: DateTime.utc(2026, 7, 20, 6, 30), // 09:30 Kyiv, overlaps a
        durationMinutes: 60,
      );

      await tester.pumpApp(
        BookingsTimelineGrid(
          bookings: <Booking>[a, b],
          day: day,
          onBookingTap: (_) {},
        ),
      );
      await tester.pump();

      final Positioned posA = _positionedOf(tester, 'lane-a');
      final Positioned posB = _positionedOf(tester, 'lane-b');
      expect(posA.left, isNot(posB.left));
    });
  });

  group('onBookingTap', () {
    testWidgets('fires with the tapped booking', (WidgetTester tester) async {
      final DateTime day = DateTime(2026, 7, 20);
      final Booking a = _booking(
        id: 'tap-a',
        startAtUtc: DateTime.utc(2026, 7, 20, 6),
        durationMinutes: 60,
      );
      final Booking b = _booking(
        id: 'tap-b',
        startAtUtc: DateTime.utc(2026, 7, 20, 8),
        durationMinutes: 60,
      );
      Booking? tapped;

      await tester.pumpApp(
        BookingsTimelineGrid(
          bookings: <Booking>[a, b],
          day: day,
          onBookingTap: (Booking booking) => tapped = booking,
        ),
      );
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey<String>('timeline-card-tap-b')),
      );
      await tester.pump();

      expect(tapped, isNotNull);
      expect(tapped!.id, 'tap-b');
    });
  });

  group('guest/LINK bookings render without crashing', () {
    testWidgets('a null-client booking renders', (WidgetTester tester) async {
      final DateTime day = DateTime(2026, 7, 20);
      final Booking guest = _booking(
        id: 'guest',
        startAtUtc: DateTime.utc(2026, 7, 20, 6),
        durationMinutes: 60,
        clientFirstName: null,
        clientLastName: null,
      );

      await tester.pumpApp(
        BookingsTimelineGrid(
          bookings: <Booking>[guest],
          day: day,
          onBookingTap: (_) {},
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey<String>('timeline-card-guest')),
        findsOneWidget,
      );
    });
  });
}
