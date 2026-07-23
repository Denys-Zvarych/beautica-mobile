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
  const double hourHeight = 168; // `BookingsTimelineGrid._kHourH` (ADDENDUM 7)
  final double proportional = durationMinutes / 60.0 * hourHeight;
  // Floored at the card's legibility minimum, DECOUPLED from the 30-minute
  // gridline slot (ADDENDUM 7) — mirrors production `_cardMinHeightFor`.
  const double floor = MasterBookingCard.estimatedNaturalHeight;
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
      // straddle the compact/full switch (ADDENDUM 7 raised the scale to
      // 168dp/hour and moved the switch to 117dp == duration ~41.8min):
      //
      //   10  — 28dp proportional, floored at the 56dp legibility minimum;
      //         compact, floor == natural == 56
      //   30  — floor 84 (30/60*168), clears the compact natural (56), still
      //         compact (84 < 117)
      //   45  — floor 126 (45/60*168) >= 117, so it takes the FULL layout now;
      //         natural 117 < 126, so the floor wins, occupied == 126
      //   59  — floor 165.2, full layout, floor well above the 117 natural
      //   60  — floor 168, full layout; lands exactly on its end-time line
      //   61  — floor 170.8, full layout
      //   63  — floor 176.4, full layout
      //   90  — floor 252, comfortably content-independent
      //   120 — floor 336, the long tail
      //
      // At this scale every real floor is >= its layout's natural height, so
      // occupiedHeightFor coincides with the floor (no overshoot) — see the
      // sub-56 unit case below for the branch that still genuinely diverges.
      for (final int durationMinutes in <int>[
        10,
        30,
        45,
        59,
        60,
        61,
        63,
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
      // height, not echo its input. At the ADDENDUM 7 scale every real
      // duration's floor already exceeds its natural (so the sweep above is
      // all echoes), so the non-echo branch is proven with an artificial
      // sub-legibility floor: a card asked for 40dp (below the 56dp compact
      // natural) must still render at 56dp — content wins over the floor, the
      // core class-doc contract — and occupiedHeightFor must PREDICT 56, not
      // echo 40 back. This is what keeps the culling placeholder honest if a
      // future scale ever hands a floor below a layout's natural again.
      testWidgets(
        'occupiedHeightFor reads the natural, not the floor: a sub-56 floor '
        'still predicts (and renders) the 56dp compact natural',
        (WidgetTester tester) async {
          const double floor = 40; // deliberately below estimatedNaturalHeight
          expect(
            floor,
            lessThan(MasterBookingCard.estimatedNaturalHeight),
            reason:
                'fixture guard: this floor must sit below the compact natural '
                'or the branch under test is not exercised',
          );

          final double rendered = await _renderedHeight(
            tester,
            durationMinutes: 30,
            floor: floor,
            laneWidth: 272,
          );
          expect(
            rendered,
            closeTo(MasterBookingCard.estimatedNaturalHeight, 0.5),
            reason:
                'the card must grow past a sub-natural floor to its own 56dp '
                'content (no clipping) — if it renders at 40dp the class-doc '
                'floor-not-ceiling contract is broken.',
          );
          expect(
            MasterBookingCard.occupiedHeightFor(floor),
            closeTo(rendered, 0.5),
            reason:
                'occupiedHeightFor echoed the 40dp floor instead of predicting '
                'the 56dp natural — the culling placeholder would under-'
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
          // A 45-minute booking, NOT 60: at ADDENDUM 7's 168dp scale a
          // 60-minute floor (168dp) already exceeds even the 1.3 full-layout
          // natural (132dp), so scaling would not push the box past the floor
          // and the prediction would coincidentally hold. A 45-minute floor
          // (126dp) sits BETWEEN the 1.0 natural (117) and the 1.3 natural
          // (132), so at 1.3 the content grows past the floor and the
          // textScaler-1.0 prediction is genuinely wrong — the property this
          // test exists to pin.
          final double floor = _floorFor(45);
          final double rendered = await _renderedHeight(
            tester,
            durationMinutes: 45,
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
