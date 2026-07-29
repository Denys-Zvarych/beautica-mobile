// ADDENDUM 5 (2026-07-22) — the culling placeholder's size invariant, at its
// SOURCE.
//
// `bookings_timeline_grid.dart` replaces an off-screen `MasterBookingCard`
// with a bare `SizedBox` of the same size. That substitution is only a layout
// no-op if the grid can predict the card's rendered box WITHOUT building it —
// and the previous pass's prediction (the duration-derived FLOOR alone) was
// 5dp short for every booking >= 60 minutes, because the card switches to its
// taller full layout at exactly that floor. Cards below a culled one then
// slid off their own hour lines as the day scrolled.
//
// `bookings_timeline_grid_test.dart`'s "ADDENDUM 4 — viewport culling" group
// pins the CONSEQUENCE (placeholder box == real box; no card moves within the
// timeline content when the view scrolls). This file pins the PREDICTION
// itself: for every floor `BookingsTimelineGrid._cardMinHeightFor` can
// produce, `MasterBookingCard.occupiedHeightFor(floor)` must equal the height
// the real card renders at when handed that same floor.
//
// WHY BOTH, AND WHY THIS ONE IS THE LOAD-BEARING HALF: the grid-level tests
// exercise the two durations their fixtures happen to use. A density pass
// that moves EITHER layout's natural height — a type-scale change, an extra
// row, a padding tweak — breaks the prediction for durations those fixtures
// never cover, and would ship the reflow with the grid suite still green.
// The sweep below covers every floor shape the grid can emit: both sides of
// the `fullLayoutMinHeight` boundary, the boundary itself, floors that clear
// the natural height, and floors that do not.
//
// TEXT SCALE 1.0 ONLY, DELIBERATELY. `occupiedHeightFor`'s naturals are
// scale-1.0 measurements. The grid USED to gate culling on
// `textScalerOf(context).scale(1) <= 1.0` for exactly that reason; ADDENDUM 6
// removed the gate by culling only BELOW the visible window, where an
// imperfect prediction displaces nothing that is on screen. The last case
// here still asserts the prediction is WRONG above 1.0 — that fact did not
// change, and it is the reason culling must stay below-window-only. A future
// "the prediction looks fine at 1.3, so we can cull above the window again"
// edit fails here first.
//
// The sweep's tolerance is 0.01dp, not a lax 0.5: the quantity is exact, and
// a systematic sub-pixel error would accumulate one card at a time until it
// reproduced the very reflow this file exists to prevent.

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

/// The same pinned Kyiv wall-clock fixture `master_booking_card_test.dart`
/// uses — every height here is content-independent, but a now-relative anchor
/// would still be a needless source of run-to-run variance (the rendered
/// «09:00–10:00» range is 1-2 glyphs wider or narrower depending on the hour
/// it lands on, and the compact layout's row 1 is width-sensitive).
Booking _booking({required int durationMinutes}) {
  // This file measures HEIGHTS only, and `MasterBookingCard` renders nothing
  // off `BookingDisplayX.isPast` (the status indicator maps from
  // `booking.status` alone, `showsPrice` is a pure status predicate), so
  // expiry cannot change any outcome here — the fixture is inert with respect
  // to "now" by construction, not by luck.
  // future-date-ok: pinned Kyiv wall-clock fixture, see the block above.
  final DateTime startAt = DateTime.utc(2026, 7, 20, 6); // 09:00 Kyiv
  return Booking(
    id: 'layout-height',
    masterId: 'master-1',
    masterFirstName: 'Оля',
    masterLastName: 'Коваль',
    masterType: 'INDEPENDENT_MASTER',
    clientFirstName: 'Марія',
    clientLastName: 'Іванюк',
    serviceId: 'service-1',
    // The worst realistic content: a long service name plus a frozen RANGE
    // band. If the card's height were content-sensitive at all, this is the
    // fixture that would expose it — and the whole prediction would be
    // unsound, not merely mis-tuned.
    serviceName: 'Комплексний догляд за волоссям з ботоксом та укладкою',
    durationMinutes: durationMinutes,
    price: 12500,
    priceMax: 25000,
    startAt: startAt,
    endAt: startAt.add(Duration(minutes: durationMinutes)),
    status: BookingStatus.confirmed,
    canReview: false,
  );
}

/// `BookingsTimelineGrid._cardMinHeightFor`, restated — the floor the grid
/// hands the card. Duplicated rather than exported: the grid's copy is a
/// private implementation detail, and a test that silently followed a change
/// to it would stop pinning the pairing this file exists for.
double _floorFor(int durationMinutes) {
  const double hourHeight = 120; // `BookingsTimelineGrid._kHourH` (ADDENDUM 8)
  final double proportional = durationMinutes / 60.0 * hourHeight;
  // Floored at the MICRO layout's natural height, DECOUPLED from the
  // 30-minute gridline slot — mirrors production `_cardMinHeightFor`.
  const double floor = MasterBookingCard.microLayoutNaturalHeight;
  return proportional > floor ? proportional : floor;
}

/// The card's REAL rendered box height at [floor].
///
/// `Center` + a fixed-width `SizedBox` reproduce the constraints
/// `_LaneColumn` imposes in production: tight width (the lane's card width),
/// LOOSE height (a `Column` child sizes to its own content). Without the
/// `Center`, `pumpApp` would hand the card the full 800x600 surface as a
/// tight constraint and every measurement would read 600.
Future<double> _renderedHeight(
  WidgetTester tester, {
  required int durationMinutes,
  required double floor,
  required double laneWidth,
  double textScale = 1.0,
}) async {
  await tester.pumpApp(
    Center(
      child: SizedBox(
        width: laneWidth,
        child: MasterBookingCard(
          booking: _booking(durationMinutes: durationMinutes),
          onTap: () {},
          minHeight: floor,
        ),
      ),
    ),
    textScaleFactor: textScale,
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
  return tester.getSize(find.byType(MasterBookingCard)).height;
}

void main() {
  group(
    'MasterBookingCard.occupiedHeightFor predicts the rendered box exactly',
    () {
      // Every duration the timeline can realistically hand a card, chosen to
      // straddle BOTH switches. At ADDENDUM 8's 120dp/hour the micro/compact
      // boundary is 56dp (duration 28min) and the compact/full boundary is
      // 118dp (duration 59.0min — 117/58.5 until the card's ROW-1 GLYPH pass
      // grew the full body by 1dp):
      //
      //   5   — 10dp proportional, floored at the 28dp micro natural; MICRO,
      //         and the one row where the floor is BELOW the natural, so
      //         occupiedHeightFor genuinely raises it
      //   10  — 20dp proportional, floored at 28; MICRO, same non-echo branch
      //   13  — 26dp proportional, floored at 28; the LONGEST duration the
      //         floor still raises, one minute under the break-even
      //   14  — 28dp proportional == the 28dp floor EXACTLY: the break-even
      //         itself, where `_floorFor`'s `max` is degenerate and
      //         occupiedHeightFor's prediction has to be right for both
      //         reasons at once. Added when the ONE-TIME-STYLE pass
      //         (2026-07-24) moved the break-even from 14.5 to 14.0 — at the
      //         outgoing 29dp natural this row was a floored one, so it is
      //         precisely the row that changed branch and was not covered.
      //   15  — floor 30 (15/60*120), just clears the micro natural; MICRO
      //   28  — floor 56, exactly the micro/compact boundary; COMPACT (the
      //         bound is exclusive), floor == natural == 56
      //   30  — floor 60, COMPACT (60 < 118)
      //   45  — floor 90, COMPACT — this flipped back from full when the
      //         scale came down from 168; see `_kFullLayoutMinHeight`'s doc
      //   58  — floor 116, one step BELOW the full switch; COMPACT with the
      //         floor well above the 56 natural
      //   59  — floor 118, EXACTLY the switch since the ROW-1 GLYPH pass;
      //         FULL, floor == the 118 natural at zero clearance (it used to
      //         sit one step above a 117 natural)
      //   60  — floor 120, FULL; lands exactly on its end-time line
      //   90  — floor 180, comfortably content-independent
      //   120 — floor 240, the long tail
      for (final int durationMinutes in <int>[
        5,
        10,
        13,
        14,
        15,
        28,
        30,
        45,
        58,
        59,
        60,
        90,
        120,
      ]) {
        testWidgets('$durationMinutes-minute booking', (
          WidgetTester tester,
        ) async {
          final double floor = _floorFor(durationMinutes);
          final double predicted = MasterBookingCard.occupiedHeightFor(floor);
          final double rendered = await _renderedHeight(
            tester,
            durationMinutes: durationMinutes,
            floor: floor,
            laneWidth: 272,
          );

          expect(
            predicted,
            closeTo(rendered, 0.01),
            reason:
                'a $durationMinutes-minute booking gets a ${floor}dp floor; '
                'occupiedHeightFor predicted ${predicted}dp but the real card '
                'renders at ${rendered}dp. BookingsTimelineGrid sizes its '
                'culling placeholder from that prediction, so every card '
                'below a culled one would shift by the difference and slide '
                'off its hour gridline. See that file\'s ADDENDUM 5.',
          );
        });
      }

      // occupiedHeightFor must GENUINELY read the selected layout's natural
      // height, not echo its input. The 5- and 10-minute rows of the sweep
      // above already exercise that branch in production terms (their floors
      // sit below the 28dp micro natural), which is itself the ADDENDUM 8
      // correction: at the retired 168dp scale EVERY real floor exceeded its
      // natural, the function was a mathematical no-op, and the only proof it
      // was not came from an artificial fixture. The artificial case is kept
      // as the WIDE version of the same property — a floor far below every
      // layout — so the branch stays pinned even if a future scale lifts the
      // real durations back above their naturals.
      testWidgets(
        'occupiedHeightFor reads the natural, not the floor: a 12dp floor '
        'still predicts (and renders) the 28dp micro natural',
        (WidgetTester tester) async {
          const double floor = 12; // far below microLayoutNaturalHeight
          expect(
            floor,
            lessThan(MasterBookingCard.microLayoutNaturalHeight),
            reason:
                'fixture guard: this floor must sit below the SHORTEST layout '
                'natural or the branch under test is not exercised',
          );

          final double rendered = await _renderedHeight(
            tester,
            durationMinutes: 30,
            floor: floor,
            laneWidth: 272,
          );
          expect(
            rendered,
            closeTo(MasterBookingCard.microLayoutNaturalHeight, 0.5),
            reason:
                'the card must grow past a sub-natural floor to its own 28dp '
                'content (no clipping) — if it renders at 12dp the class-doc '
                'floor-not-ceiling contract is broken.',
          );
          expect(
            MasterBookingCard.occupiedHeightFor(floor),
            closeTo(rendered, 0.5),
            reason:
                'occupiedHeightFor echoed the 12dp floor instead of predicting '
                'the 28dp natural — the culling placeholder would under-'
                'reserve and every card below would slide off its gridline.',
          );
        },
      );

      // The prediction has no lane-width term. If a future layout change made
      // a row wrap instead of ellipsise, height WOULD depend on width and the
      // whole approach would be unsound — this is what would catch it.
      for (final double laneWidth in <double>[226, 266, 272]) {
        testWidgets(
          'the prediction holds at ${laneWidth}dp of lane — height is '
          'independent of lane width',
          (WidgetTester tester) async {
            final double floor = _floorFor(60);
            final double rendered = await _renderedHeight(
              tester,
              durationMinutes: 60,
              floor: floor,
              laneWidth: laneWidth,
            );
            expect(
              MasterBookingCard.occupiedHeightFor(floor),
              closeTo(rendered, 0.01),
              reason:
                  'at ${laneWidth}dp of lane the card measured ${rendered}dp. '
                  'If this varies with width, a row is WRAPPING rather than '
                  'ellipsising and occupiedHeightFor cannot be a pure '
                  'function of the floor at all.',
            );
          },
        );
      }

      testWidgets(
        'above textScaler 1.0 the prediction is deliberately WRONG — which is '
        'why BookingsTimelineGrid only ever culls BELOW the visible window',
        (WidgetTester tester) async {
          // A 60-minute booking, and the duration matters. The floor has to
          // sit BETWEEN the selected layout's 1.0 natural and its 1.3 natural,
          // or the content cannot grow past the floor at 1.3 and the
          // prediction holds by coincidence instead of being wrong. At
          // ADDENDUM 8's 120dp scale that window is the FULL layout's
          // 118 (@1.0) → 132 (@1.3), and a 60-minute floor is 120dp — inside
          // it. (This used to be 45 minutes for the same reason at the 168dp
          // scale, where a 45-minute floor was 126dp; at 120 a 45-minute floor
          // is 90dp and selects the compact layout, whose 1.3 natural is only
          // 65dp — the test would have silently stopped testing anything.)
          final double floor = _floorFor(60);
          final double rendered = await _renderedHeight(
            tester,
            durationMinutes: 60,
            floor: floor,
            laneWidth: 272,
            textScale: 1.3,
          );

          expect(
            rendered,
            greaterThan(MasterBookingCard.occupiedHeightFor(floor) + 1),
            reason:
                'at textScaler 1.3 the card measured ${rendered}dp against a '
                'prediction of ${MasterBookingCard.occupiedHeightFor(floor)}dp. '
                'If these ever agree, re-derive the naturals before letting '
                'the grid cull ABOVE the visible window again — do NOT make '
                'that change on this test alone.',
          );
        },
      );
    },
  );
}
