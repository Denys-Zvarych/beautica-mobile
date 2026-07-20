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

/// The REAL rendered geometry of the [MasterBookingCard] keyed
/// `timeline-card-<id>` — since the R3 fix (HIGH-1 same-lane-overlap
/// regression), cards are laid out inside a per-lane `Column`, not
/// `Positioned` siblings of a shared `Stack`, so tests read actual screen
/// geometry (`tester.getRect`/`getTopLeft`) rather than a `Positioned`
/// widget's declared `top`/`left`/`height` properties.
Rect _cardRect(WidgetTester tester, String bookingId) =>
    tester.getRect(find.byKey(ValueKey<String>('timeline-card-$bookingId')));

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

      // R3 (HIGH-1 fix) note: the grid no longer has an explicit `height:`
      // (see `bookings_timeline_grid.dart`'s "R3" header section) — its
      // REAL rendered size is what must be positive, read via the actual
      // `timeline-lane-stack` `RenderBox`, not a declared `SizedBox.height`.
      final double gridHeight = tester
          .getSize(find.byKey(const ValueKey<String>('timeline-lane-stack')))
          .height;
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
        // card anchors its own extent, so it renders flush with the grid's
        // own top edge regardless of zone — asserted here for completeness,
        // NOT as the zone-correctness proof (see the comment above).
        final double gridTop = tester
            .getTopLeft(
              find.byKey(const ValueKey<String>('timeline-lane-stack')),
            )
            .dy;
        expect(_cardRect(tester, 'crossing').top, gridTop);
      },
    );
  });

  group('short bookings render their full card, not a clipped sliver', () {
    // R2 regression — the report this test exists to pin: a duration-scaled
    // Positioned `height:` (floored at 48dp) used to make `MasterBookingCard`
    // clip its own natural ~150dp content down to that box via an
    // OverflowBox + ClipRect pair, i.e. "I can see only half of the card"
    // for anything shorter than ~50 minutes. The fix positions the card by
    // `top`/`left`/`width` ONLY — no `height:` — so it always renders at its
    // full natural size regardless of duration.
    testWidgets(
      'a 15-minute booking is positioned with no forced height, and its '
      'rendered card is far taller than the old 48dp floor',
      (WidgetTester tester) async {
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

        // No `Positioned` ancestor at all any more (R3 fix) — cards flow
        // inside a per-lane `Column`, so there is no forced-height mechanism
        // left to reintroduce. A find here would mean the old absolute-
        // positioning approach (and its clipping risk) came back.
        expect(
          find.ancestor(
            of: find.byKey(const ValueKey<String>('timeline-card-short')),
            matching: find.byType(Positioned),
          ),
          findsNothing,
        );

        // The card's ACTUAL rendered height comfortably clears the old 48dp
        // floor — proof the full card (avatar row, divider, service row,
        // price/status row) is on screen, not a truncated sliver of it.
        final double renderedHeight = tester
            .getSize(find.byKey(const ValueKey<String>('timeline-card-short')))
            .height;
        expect(renderedHeight, greaterThan(120));
      },
    );
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

      final Rect rectA = _cardRect(tester, 'lane-a');
      final Rect rectB = _cardRect(tester, 'lane-b');
      expect(rectA.left, isNot(rectB.left));
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

  group('R3 regression — same-lane back-to-back cards never overlap', () {
    // HIGH-1 (mobile-dev/mobile-qa audit of the R2 un-clipping fix): once a
    // card renders its full ~150-190dp regardless of duration, two
    // back-to-back same-lane bookings — 09:00-09:30 then 09:30-10:00, the
    // ordinary case for a working master — used to paint on top of each
    // other, with the LATER one winning every tap in the overlapping region.
    // The fix (this file's "R3" section) lays same-lane cards out as a flex
    // `Column`, which cannot let card N+1 start above card N's real bottom
    // edge. 2026-07-20 is Kyiv summer time (UTC+3): 09:00 Kyiv == 06:00 UTC,
    // 09:30 Kyiv == 06:30 UTC.
    final DateTime day = DateTime(2026, 7, 20);
    final Booking early = _booking(
      id: 'r3-early',
      startAtUtc: DateTime.utc(2026, 7, 20, 6), // 09:00 Kyiv
      durationMinutes: 30,
    );
    final Booking late = _booking(
      id: 'r3-late',
      startAtUtc: DateTime.utc(2026, 7, 20, 6, 30), // 09:30 Kyiv
      durationMinutes: 30,
    );

    testWidgets('the two cards\' rendered Rects do not intersect', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(
        BookingsTimelineGrid(
          bookings: <Booking>[early, late],
          day: day,
          onBookingTap: (_) {},
        ),
      );
      await tester.pump();

      final Rect earlyRect = _cardRect(tester, 'r3-early');
      final Rect lateRect = _cardRect(tester, 'r3-late');
      expect(
        earlyRect.overlaps(lateRect),
        isFalse,
        reason:
            'r3-early $earlyRect and r3-late $lateRect must not intersect — '
            'a master tapping the earlier card must never land on the '
            'later booking (or vice-versa).',
      );
      // The later card must render entirely below the earlier one — proves
      // the non-intersection isn't a horizontal-lane coincidence.
      expect(lateRect.top, greaterThanOrEqualTo(earlyRect.bottom));
    });

    testWidgets(
      'a tap inside the EARLIER card\'s rendered region opens the earlier '
      'booking, not the later one',
      (WidgetTester tester) async {
        Booking? tapped;
        await tester.pumpApp(
          BookingsTimelineGrid(
            bookings: <Booking>[early, late],
            day: day,
            onBookingTap: (Booking booking) => tapped = booking,
          ),
        );
        await tester.pump();

        // Before the R3 fix this exact point could have been inside BOTH
        // cards' hit-test regions (the later one painted on top and won).
        final Offset earlyCenter = _cardRect(tester, 'r3-early').center;
        await tester.tapAt(earlyCenter);
        await tester.pump();

        expect(tapped, isNotNull);
        expect(tapped!.id, 'r3-early');
      },
    );

    testWidgets(
      'the last card of the day is fully within the rendered grid extent',
      (WidgetTester tester) async {
        // A third, LATE booking in the same lane with a big idle gap before
        // it, so the grid's real extent is driven by wall-clock time for
        // most of the day and only compressed near the two back-to-back
        // cards — the mixed case a pure hour-math buffer could still get
        // wrong. 18:00 Kyiv == 15:00 UTC.
        final Booking lastOfDay = _booking(
          id: 'r3-last',
          startAtUtc: DateTime.utc(2026, 7, 20, 15),
          durationMinutes: 15,
        );

        await tester.pumpApp(
          BookingsTimelineGrid(
            bookings: <Booking>[early, late, lastOfDay],
            day: day,
            onBookingTap: (_) {},
          ),
        );
        await tester.pump();

        final Rect gridRect = tester.getRect(
          find.byKey(const ValueKey<String>('timeline-lane-stack')),
        );
        final Rect lastRect = _cardRect(tester, 'r3-last');

        // A tiny epsilon absorbs float rounding — the last card's bottom
        // must never render PAST the grid's own resolved bottom edge.
        expect(lastRect.bottom, lessThanOrEqualTo(gridRect.bottom + 0.5));
      },
    );
  });
}
