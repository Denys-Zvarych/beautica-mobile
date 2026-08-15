// mobile-qa — 2026-08-15 booking-card font-size pass, THE MOVED BOUNDARY.
//
// `MasterBookingCard.fullLayoutMinHeight` fell from 118dp to 115dp when the
// font-size pass shrank the FULL body's three rows (client-name / service+
// time / price+badge) by 3dp combined — see `master_booking_card.dart`'s
// `fullLayoutNaturalHeight` doc. At `BookingsTimelineGrid`'s current
// 120dp/hour scale (`_kHourH`), that moves the exact FULL/COMPACT break-even
// duration from 59.0 minutes to 57.5 minutes: a 58-minute booking (floor
// `58/60×120=116dp`) now clears the threshold and selects FULL; a 57-minute
// one (floor `57/60×120=114dp`) does not.
//
// NOTHING pins this from the CALLER's side. `master_booking_card_test.dart`
// pins the card's own switch directly via literal `minHeight` values (114 /
// 115), and `bookings_timeline_grid_test.dart` pins the (separately-moved)
// MICRO/COMPACT break-even at 13.5 minutes — but no test anywhere pumps a
// real 58- or 57-minute BOOKING through the real `BookingsTimelineGrid` (the
// widget that actually computes a booking's proportional floor from its
// `durationMinutes` and hands it to the card) and checks which layout comes
// out. That is a real, end-to-end gap: a regression in the GRID's own
// `_cardMinHeightFor` scale (as opposed to the CARD's own threshold, which
// is separately pinned) could silently move which real durations render
// FULL vs COMPACT with nothing here to catch it.
//
// THE EXISTING "59-minute" TRIPWIRE IS STALE, NOT REMOVED, AND WORTH
// FLAGGING HERE
// -----------------------------------------------------------------------
// `master_booking_card_test.dart`'s "the FULL body's 118dp natural, measured
// from the inside" group still asserts a 59-minute booking sits at "EXACTLY
// zero clearance" against the switch. That was true when the threshold was
// 118 (`59/60×120 = 118` exactly). At the new 115dp threshold a 59-minute
// booking's 118dp floor clears it with 3dp to spare, not zero — the group's
// own numeric assertion still passes (it reads
// `MasterBookingCard.fullLayoutMinHeight` symbolically, not a hardcoded
// 118), but its STATED invariant ("any further growth of that body fails
// here") is no longer true: the body can now grow by up to 3dp before this
// tripwire fires, not 0dp. The REAL zero-slack edge moved to 58 minutes
// (1dp clearance — no whole-minute duration sits at exactly zero any more,
// since the new threshold, 115, is not a multiple of `120/60`). See the QA
// report for the full finding; this file supplies the missing coverage at
// the CORRECT current edge rather than editing that large, narrative-heavy
// group in place.

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';

/// Mirrors `bookings_timeline_grid_test.dart`'s own anchor — a real, now-
/// relative Kyiv day rather than an elapsing hard-coded literal.
final DateTime _day = dateOnly(toBeauticaTime(futureBookingStart()));

DateTime _kyivAtUtc(int hour, [int minute = 0]) => tz.TZDateTime(
  beauticaZone,
  _day.year,
  _day.month,
  _day.day,
  hour,
  minute,
).toUtc();

Booking _booking({required String id, required int durationMinutes}) => Booking(
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
  startAt: _kyivAtUtc(9),
  endAt: _kyivAtUtc(9).add(Duration(minutes: durationMinutes)),
  status: BookingStatus.confirmed,
  canReview: false,
);

void main() {
  group(
    'THE CALLER SIDE — a real duration pumped through BookingsTimelineGrid, '
    'not a hand-picked minHeight',
    () {
      testWidgets(
        'a 58-minute booking (120dp/hour floor 116dp) selects the FULL body '
        'through the real grid',
        (WidgetTester tester) async {
          final Booking booking = _booking(id: 'edge-58', durationMinutes: 58);

          await tester.pumpApp(
            BookingsTimelineGrid(
              bookings: <Booking>[booking],
              day: _day,
              onBookingTap: (_) {},
            ),
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const Key('master-booking-card-divider-edge-58')),
            findsOneWidget,
            reason:
                'a 58-minute booking\'s real, grid-derived floor (116dp) must '
                'clear MasterBookingCard.fullLayoutMinHeight (115dp) and '
                'select the FULL body — through the GRID\'s own '
                '_cardMinHeightFor, not a literal minHeight',
          );
          expect(
            find.byKey(
              const Key('master-booking-card-compact-divider-edge-58'),
            ),
            findsNothing,
          );
        },
      );

      testWidgets(
        'a 57-minute booking (120dp/hour floor 114dp) stays on the COMPACT '
        'grid through the real grid — one minute below the new edge',
        (WidgetTester tester) async {
          final Booking booking = _booking(id: 'edge-57', durationMinutes: 57);

          await tester.pumpApp(
            BookingsTimelineGrid(
              bookings: <Booking>[booking],
              day: _day,
              onBookingTap: (_) {},
            ),
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(
            find.byKey(
              const Key('master-booking-card-compact-divider-edge-57'),
            ),
            findsOneWidget,
            reason:
                'a 57-minute booking\'s real, grid-derived floor (114dp) must '
                'stay below MasterBookingCard.fullLayoutMinHeight (115dp) and '
                'render the COMPACT grid',
          );
          expect(
            find.byKey(const Key('master-booking-card-divider-edge-57')),
            findsNothing,
          );
        },
      );
    },
  );

  group(
    'THE CARD SIDE, restated at the CORRECT current edge (58, not the stale '
    '59) — the zero-to-near-zero-clearance tripwire',
    () {
      testWidgets(
        'a 58-minute booking\'s 116dp floor clears the 115dp threshold by '
        'EXACTLY 1dp — the tightest whole-minute duration that still selects '
        'FULL; any further growth of the full body\'s natural fails this',
        (WidgetTester tester) async {
          const double floor58 =
              58 / 60.0 * 120; // BookingsTimelineGrid._kHourH

          expect(
            floor58 - MasterBookingCard.fullLayoutMinHeight,
            closeTo(1, 0.01),
            reason:
                'fixture guard: the 58-minute floor must sit exactly 1dp past '
                'the current threshold, or this case is not measuring the '
                'edge it claims to',
          );

          await tester.pumpApp(
            Center(
              child: SizedBox(
                width: 226,
                child: MasterBookingCard(
                  booking: _booking(id: 'card-edge-58', durationMinutes: 58),
                  onTap: () {},
                  minHeight: floor58,
                ),
              ),
            ),
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const Key('master-booking-card-divider-card-edge-58')),
            findsOneWidget,
            reason:
                'a 58-minute booking must still select the FULL body — if '
                'the full body\'s natural grows even 1dp further, a '
                '58-minute booking silently demotes to the compact grid',
          );
        },
      );

      testWidgets(
        'a 57-minute booking\'s 114dp floor sits 1dp SHORT of the threshold '
        'and stays COMPACT',
        (WidgetTester tester) async {
          const double floor57 = 57 / 60.0 * 120;

          expect(
            MasterBookingCard.fullLayoutMinHeight - floor57,
            closeTo(1, 0.01),
          );

          await tester.pumpApp(
            Center(
              child: SizedBox(
                width: 226,
                child: MasterBookingCard(
                  booking: _booking(id: 'card-edge-57', durationMinutes: 57),
                  onTap: () {},
                  minHeight: floor57,
                ),
              ),
            ),
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(
            find.byKey(
              const Key('master-booking-card-compact-divider-card-edge-57'),
            ),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('master-booking-card-divider-card-edge-57')),
            findsNothing,
          );
        },
      );
    },
  );

  group(
    'mobile-perf INFO (2026-08-15) — the 58-minute card\'s scale behaviour, '
    'pinned rather than left as handoff prose',
    () {
      // The dev handoff measured this card at 116.0dp @1.0, 120.0dp @1.15 and
      // 126.0dp @1.3 with `tester.takeException()` null throughout, but the
      // throwaway test that produced those numbers was deleted — they existed
      // only as prose. This re-derives them from a real render. Growth past
      // the 116dp band above textScaler 1.0 is ACCEPTED, documented behaviour
      // for this widget (`minHeight` is a floor, never a ceiling — see
      // `MasterBookingCard.minHeight`'s own doc), so this pins the actual
      // measured height rather than asserting it stays under a band ceiling.
      const double floor58 = 58 / 60.0 * 120; // BookingsTimelineGrid._kHourH

      testWidgets(
        'textScaler 1.15 — no exception, height pinned to the measured value',
        (WidgetTester tester) async {
          await tester.pumpApp(
            Center(
              child: SizedBox(
                width: 226,
                child: MasterBookingCard(
                  booking: _booking(
                    id: 'card-edge-58-scale',
                    durationMinutes: 58,
                  ),
                  onTap: () {},
                  minHeight: floor58,
                ),
              ),
            ),
            textScaleFactor: 1.15,
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
          final double height = tester
              .getSize(
                find.byKey(const Key('master-booking-card-card-edge-58-scale')),
              )
              .height;
          // Measured directly (`tester.getSize`) — matches the deleted
          // throwaway test's claimed 120.0dp exactly. This card's 116dp
          // proportional floor is a `minHeight` FLOOR, not a ceiling, so
          // growing 4dp past it at 1.15x is accepted, expected behaviour —
          // not something to clamp against.
          expect(
            height,
            120.0,
            reason:
                'the 58-minute FULL card grew to ${height}dp at textScaler '
                '1.15 — pinning the real measured overhang past the 116dp '
                'floor, not a band ceiling.',
          );
        },
      );

      testWidgets(
        'textScaler 1.3 — no exception, height pinned to the measured value',
        (WidgetTester tester) async {
          await tester.pumpApp(
            Center(
              child: SizedBox(
                width: 226,
                child: MasterBookingCard(
                  booking: _booking(
                    id: 'card-edge-58-scale',
                    durationMinutes: 58,
                  ),
                  onTap: () {},
                  minHeight: floor58,
                ),
              ),
            ),
            textScaleFactor: 1.3,
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
          final double height = tester
              .getSize(
                find.byKey(const Key('master-booking-card-card-edge-58-scale')),
              )
              .height;
          // Measured directly (`tester.getSize`) — matches the deleted
          // throwaway test's claimed 126.0dp exactly. Same accepted-overhang
          // reasoning as the 1.15 case above.
          expect(
            height,
            126.0,
            reason:
                'the 58-minute FULL card grew to ${height}dp at textScaler '
                '1.3 — pinning the real measured overhang past the 116dp '
                'floor, not a band ceiling.',
          );
        },
      );
    },
  );
}
