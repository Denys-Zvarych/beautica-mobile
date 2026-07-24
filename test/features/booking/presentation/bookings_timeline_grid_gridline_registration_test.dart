// Phase 7.10 — GRIDLINE REGISTRATION: the parametric ground-truth guard for
// `BookingsTimelineGrid`.
//
// ============================================================================
// WHY THIS FILE EXISTS SEPARATELY FROM `bookings_timeline_grid_test.dart`
// ============================================================================
// The card/gridline alignment bug has now shipped TWICE:
//
//   1. `4a4de1f` claimed to fix it and added "structural guard" tests. Those
//      guards were written against fixtures that could not express the defect
//      — a SINGLE booking (no run, so nothing to accumulate), or a booking
//      with real idle time before it (which re-anchors the running position
//      and erases the residual). One of them went further and ASSERTED the
//      8dp per-card offset as correct, calling it "the cosmetic minimum gap,
//      no collision-nudge drift".
//   2. The 8dp `_kMinInterCardGap` floor survived that pass and was still
//      adding itself once per card to an ABSOLUTE running position, so a
//      12:00–14:00 booking rendered as ~12:10–14:10 — an OFFSET, not a
//      stretch, growing with each consecutive booking in the day.
//
// So the property under test here is deliberately the one no single-card,
// single-duration or idle-gapped fixture can satisfy by accident:
//
//   FOR EVERY CARD IN A BACK-TO-BACK RUN OF MIXED DURATIONS — not just the
//   first, and not just relative to its neighbour — the card's rendered TOP
//   lands on the ruler position of its `startAt` and its rendered BOTTOM on
//   the ruler position of its `endAt`.
//
// ============================================================================
// THE GROUND TRUTH IS THE RENDERED RULER, NEVER `_kHourH`
// ============================================================================
// [_expectedY] converts a wall-clock instant to a screen Y by INTERPOLATING
// BETWEEN THE RENDERED GRIDLINE RECTS ([_gridlineLadderAscending]) — it never
// multiplies a duration by a dp-per-hour constant. That is the whole point of
// this file and the reason it is not a copy of the sibling file's `kHourH`
// arithmetic:
//
//   * A test that recomputes expected positions as `minutes / 60 * 120` is
//     SELF-REFERENTIAL. It restates the same constant the widget uses, so it
//     can only ever catch a change to that constant — never a change to how
//     the constant is APPLIED, which is exactly what both shipped bugs were
//     (an additive floor in one coordinate space, an origin anchored to
//     `firstMinute` instead of the floored `firstHour` in the other).
//   * Reading the ladder instead means a future scale pass — 120 → 96, or a
//     responsive dp-per-hour — needs NO edit here and still cannot silently
//     break alignment. If the ruler moves, the expectations move with it; if
//     the CARDS stop tracking the ruler, this file goes red.
//
// The ladder is the half-hour gridline `ColoredBox` set the grid actually
// paints (hour lines at full-opacity `BrandColors.faint`, half-hour lines at
// the same hue on alpha 0.4), sorted by rendered top, so rung `i` is
// `firstHour * 60 + i * 30` minutes. Times that land on a rung are asserted
// against that rung's REAL rect with zero arithmetic; off-rung times (10:45,
// 13:40) interpolate between the two rendered rungs that bracket them.
//
// Per the project rule, a regenerated golden is self-referential and is NOT
// acceptance for a layout fix — these are structural pixel assertions against
// rendered geometry instead.

import 'dart:math' as math;

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/timeline_hour_ruler.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';

/// The KYIV calendar day every fixture is anchored to — derived from the real
/// clock, never an absolute future literal (see the sibling file's header for
/// the ratchet this observes).
final DateTime _day = dateOnly(toBeauticaTime(futureBookingStart()));

/// The UTC instant for `hour:minute` KYIV wall-clock on [_day]. Built through
/// [tz.TZDateTime] rather than a hard-coded `+3`, because Kyiv is UTC+3 in
/// summer and UTC+2 in winter and [_day] moves with the calendar.
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

Rect _cardRect(WidgetTester tester, String bookingId) =>
    tester.getRect(find.byKey(ValueKey<String>('timeline-card-$bookingId')));

/// Whether [element] sits inside a [MasterBookingCard] — the card's own
/// hairline divider is a `BrandColors.faint` `ColoredBox` too, so a gridline
/// search has to exclude it or the ladder gains phantom rungs.
bool _hasCardAncestor(Element element) {
  bool found = false;
  element.visitAncestorElements((Element ancestor) {
    if (ancestor.widget is MasterBookingCard) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// EVERY rendered gridline — hour lines (full-opacity [BrandColors.faint]) AND
/// half-hour lines (the same hue at alpha 0.4) — sorted ascending by rendered
/// top, so rung `i` is exactly `firstHour * 60 + i * 30` minutes.
///
/// Both colours are collected on purpose: the half-hour rungs double the
/// ladder's resolution, which means a 30-minute booking's start and end are
/// each pinned to a REAL rendered rect rather than to an interpolation.
List<Rect> _gridlineLadderAscending(WidgetTester tester) {
  final Color halfHour = BrandColors.faint.withValues(alpha: 0.4);
  final Iterable<Element> elements = find
      .byWidgetPredicate(
        (Widget w) =>
            w is ColoredBox &&
            (w.color == BrandColors.faint || w.color == halfHour),
      )
      .evaluate();
  return elements.where((Element e) => !_hasCardAncestor(e)).map((Element e) {
    final RenderBox box = e.renderObject! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }).toList()..sort((Rect a, Rect b) => a.top.compareTo(b.top));
}

/// The screen Y the ruler puts [instantUtc] at, derived ENTIRELY from
/// [ladder]'s rendered rects — no `_kHourH`, no dp-per-minute constant.
///
/// [firstHour] is the ladder's own origin (`hours since [_day]'s Kyiv
/// midnight` of rung 0). An instant landing exactly on a rung returns that
/// rung's real `top` (the fractional term is 0); an off-rung instant is
/// linearly interpolated between the two rendered rungs bracketing it, which
/// is the definition of a uniform ruler and is still measured, not assumed.
double _expectedY({
  required List<Rect> ladder,
  required int firstHour,
  required DateTime instantUtc,
}) {
  final tz.TZDateTime midnight = tz.TZDateTime(
    beauticaZone,
    _day.year,
    _day.month,
    _day.day,
  );
  final int minutesSinceMidnight = toBeauticaTime(
    instantUtc,
  ).difference(midnight).inMinutes;
  final double rung = (minutesSinceMidnight - firstHour * 60) / 30.0;

  // Clamp the lower index so the last rung extrapolates off the final PAIR of
  // real rungs instead of running off the end of the list.
  final int lo = math.max(0, math.min(rung.floor(), ladder.length - 2));
  final double loY = ladder[lo].top;
  final double hiY = ladder[lo + 1].top;
  return loY + (rung - lo) * (hiY - loY);
}

/// One fixture row: a booking plus the wall-clock instants its card's top and
/// bottom edges must land on.
typedef _Run = ({String id, int startHour, int startMinute, int durationMin});

/// Builds the bookings for [run] in ascending order.
List<Booking> _bookingsFor(List<_Run> run) => <Booking>[
  for (final _Run r in run)
    _booking(
      id: r.id,
      startAtUtc: _kyivAtUtc(r.startHour, r.startMinute),
      durationMinutes: r.durationMin,
    ),
];

void main() {
  group('GRIDLINE REGISTRATION — every card in a back-to-back run', () {
    /// The shared assertion body: pump [run], then for EVERY booking in it
    /// assert both edges against the rendered ladder.
    ///
    /// "Every", not "the last" and not "the first", is load-bearing. The
    /// retired `_kMinInterCardGap` produced a residual that GREW with the
    /// index, so a check on card 0 alone passes on the broken build and a
    /// check on the last card alone cannot say whether the error is a
    /// one-off constant or an accumulator. Asserting the whole run pins the
    /// shape of the error as well as its magnitude.
    Future<void> expectRunLandsOnItsGridlines(
      WidgetTester tester, {
      required List<_Run> run,
      required int firstHour,
    }) async {
      final List<Booking> bookings = _bookingsFor(run);
      await tester.pumpApp(
        BookingsTimelineGrid(
          bookings: bookings,
          day: _day,
          onBookingTap: (_) {},
        ),
      );
      await tester.pump();

      final List<Rect> ladder = _gridlineLadderAscending(tester);
      expect(
        ladder.length,
        greaterThanOrEqualTo(2),
        reason:
            'the ruler must paint at least two gridlines for the ladder to '
            'establish a scale from rendered geometry',
      );

      // PRECONDITION: every card in the run must be a REAL card, not a culled
      // placeholder. The grid culls cards planned past `offset + 1.5V`
      // (ADDENDUM 9) and swaps in a `timeline-card-culled-<id>` box, so a
      // fixture that grew — or a future `_kHourH` rise, or a further window
      // tightening — could push the run's tail past the edge. `_cardRect`
      // would then throw a bare "no element" from deep inside the loop, which
      // reads like a broken finder and invites someone to "fix" it by
      // scrolling; that would leave this file asserting registration only for
      // whichever prefix of the run survived. Stated up front, the failure
      // names its own cause.
      for (final Booking b in bookings) {
        expect(
          find.byKey(ValueKey<String>('timeline-card-culled-${b.id}')),
          findsNothing,
          reason:
              'booking ${b.id} rendered as a CULLED PLACEHOLDER, so the '
              'registration assertions below would not be measuring a real '
              'card. The fixture must sit entirely within the culling window '
              '(`scrollOffset + 1.5 viewports`) at rest — shorten the run, or '
              're-check whether the window or the dp-per-hour scale moved.',
        );
      }

      for (final Booking b in bookings) {
        final Rect card = _cardRect(tester, b.id);
        final double expectedTop = _expectedY(
          ladder: ladder,
          firstHour: firstHour,
          instantUtc: b.startAt,
        );
        final double expectedBottom = _expectedY(
          ladder: ladder,
          firstHour: firstHour,
          instantUtc: b.endAt,
        );

        expect(
          card.top,
          closeTo(expectedTop, 1.0),
          reason:
              'booking ${b.id} (${b.durationMinutes}min) renders its card top '
              'at ${card.top} but its startAt sits at $expectedTop on the '
              'RENDERED ruler — a delta that grows with position in the run is '
              'an additive per-card gap being applied against an absolute '
              'ruler (the `_kMinInterCardGap` bug, shipped twice).',
        );
        expect(
          card.bottom,
          closeTo(expectedBottom, 1.0),
          reason:
              'booking ${b.id} (${b.durationMinutes}min) renders its card '
              'bottom at ${card.bottom} but its endAt sits at $expectedBottom '
              'on the RENDERED ruler — the «12:00–14:00 reads as 12:10–14:10» '
              'symptom.',
        );
      }
    }

    testWidgets(
      'MIXED DURATIONS, WHOLE-HOUR START: six back-to-back bookings '
      '(60/30/15/45/60/30) each land BOTH edges on their own ruler position',
      (WidgetTester tester) async {
        // Mixed durations on purpose. A uniform 60-minute run only exercises
        // the FULL layout, whose occupied height equals its band exactly — the
        // easiest case. Interleaving 30 (compact), 15 (micro) and 45 (compact)
        // walks all three of `occupiedHeightFor`'s branches inside a single
        // run, so a density pass that breaks any one branch's band/box
        // agreement shows up as a misregistration of every card BELOW it,
        // not merely as a wrong height on the card itself.
        //
        // 09:00 → 13:00, with no idle time anywhere: idle time re-anchors the
        // running position and would mask an accumulator (that is precisely
        // how the `4a4de1f` guards missed this).
        await expectRunLandsOnItsGridlines(
          tester,
          firstHour: 9,
          run: const <_Run>[
            (id: 'mix-0', startHour: 9, startMinute: 0, durationMin: 60),
            (id: 'mix-1', startHour: 10, startMinute: 0, durationMin: 30),
            (id: 'mix-2', startHour: 10, startMinute: 30, durationMin: 15),
            (id: 'mix-3', startHour: 10, startMinute: 45, durationMin: 45),
            (id: 'mix-4', startHour: 11, startMinute: 30, durationMin: 60),
            (id: 'mix-5', startHour: 12, startMinute: 30, durationMin: 30),
          ],
        );
      },
    );

    testWidgets(
      'MIXED DURATIONS, OFF-HOUR START (13:40): the same property holds when '
      'the day\'s first booking does not start on a whole hour',
      (WidgetTester tester) async {
        // Masters routinely open at :15/:30/:40, and the card layer's origin
        // is the FLOORED hour (`firstHour * 60`) while the first booking's
        // own start is not. An implementation that anchors cards to
        // `firstMinute` instead slides the whole card layer up by
        // `(firstMinute mod 60)` minutes — every card, uniformly, so the
        // whole-hour run above cannot see it (its `firstMinute mod 60` is 0)
        // and neither can any relative card-to-card check.
        //
        // 13:40 → 16:15, back to back throughout.
        await expectRunLandsOnItsGridlines(
          tester,
          firstHour: 13,
          run: const <_Run>[
            (id: 'off-0', startHour: 13, startMinute: 40, durationMin: 20),
            (id: 'off-1', startHour: 14, startMinute: 0, durationMin: 60),
            (id: 'off-2', startHour: 15, startMinute: 0, durationMin: 30),
            (id: 'off-3', startHour: 15, startMinute: 30, durationMin: 45),
          ],
        );
      },
    );

    testWidgets(
      'FIXTURE GUARD: the mixed run really is back-to-back and really does '
      'span three densities — a fixture that drifted into idle gaps or a '
      'single density would pass the assertions above vacuously',
      (WidgetTester tester) async {
        // The `4a4de1f` guards failed exactly here: the assertions were fine,
        // the FIXTURES could not express the defect. Pinning the fixture's own
        // preconditions is what stops this file from rotting the same way.
        const List<_Run> run = <_Run>[
          (id: 'mix-0', startHour: 9, startMinute: 0, durationMin: 60),
          (id: 'mix-1', startHour: 10, startMinute: 0, durationMin: 30),
          (id: 'mix-2', startHour: 10, startMinute: 30, durationMin: 15),
          (id: 'mix-3', startHour: 10, startMinute: 45, durationMin: 45),
          (id: 'mix-4', startHour: 11, startMinute: 30, durationMin: 60),
          (id: 'mix-5', startHour: 12, startMinute: 30, durationMin: 30),
        ];
        final List<Booking> bookings = _bookingsFor(run);

        for (int i = 1; i < bookings.length; i++) {
          expect(
            bookings[i].startAt,
            bookings[i - 1].endAt,
            reason:
                'booking $i must start exactly when booking ${i - 1} ends — '
                'any idle time re-anchors the running position and would let '
                'an accumulating offset pass unnoticed',
          );
        }

        // All three `MasterBookingCard` densities must be represented, read
        // through the very predictor the grid's own `_cardMinHeightFor` feeds
        // rather than by quoting duration thresholds.
        final Set<String> densities = <String>{};
        for (final Booking b in bookings) {
          final double floor = math.max(
            b.durationMinutes / 60.0 * 120,
            MasterBookingCard.microLayoutNaturalHeight,
          );
          if (floor >= MasterBookingCard.fullLayoutMinHeight) {
            densities.add('full');
          } else if (floor < MasterBookingCard.microLayoutMaxHeight) {
            densities.add('micro');
          } else {
            densities.add('compact');
          }
        }
        expect(
          densities,
          <String>{'full', 'compact', 'micro'},
          reason:
              'the run must cross all three densities, or it only proves '
              'registration for whichever layout it happens to select',
        );
      },
    );
  });

  group('NO DEAD SPACE below the last hour', () {
    testWidgets(
      'the timeline\'s total rendered height is the ruled span plus the last '
      'label plus one bottom margin — never a spare trailing hour',
      (WidgetTester tester) async {
        // `TimelineHourRuler` used to size itself `(totalHours + 1) * _kHourH`
        // — one FULL empty hour below the last label, on every day. Because
        // the ruler and the lane stack share a `Row`, that dead hour usually
        // DOMINATED the row's height and the whole timeline scrolled past its
        // own content.
        await tester.pumpApp(
          BookingsTimelineGrid(
            bookings: _bookingsFor(const <_Run>[
              (id: 'dead-0', startHour: 9, startMinute: 0, durationMin: 60),
              (id: 'dead-1', startHour: 10, startMinute: 0, durationMin: 30),
              (id: 'dead-2', startHour: 10, startMinute: 30, durationMin: 15),
              (id: 'dead-3', startHour: 10, startMinute: 45, durationMin: 45),
            ]),
            day: _day,
            onBookingTap: (_) {},
          ),
        );
        await tester.pump();

        final List<Rect> ladder = _gridlineLadderAscending(tester);
        final double ruledSpan = ladder.last.top - ladder.first.top;
        // One rendered hour band, measured off two adjacent HALF-hour rungs —
        // again, never `_kHourH`.
        final double hourBand = (ladder[1].top - ladder[0].top) * 2;
        expect(hourBand, greaterThan(0));

        // The whole timeline's laid-out height: the `Row` that holds the ruler
        // and the lane area. Located as the ruler's nearest `Row` ancestor so
        // it can never resolve to a `Row` inside a card.
        final double contentHeight = tester
            .getRect(
              find
                  .ancestor(
                    of: find.byType(TimelineHourRuler),
                    matching: find.byType(Row),
                  )
                  .first,
            )
            .height;

        // The SCALE-FREE property — this is the one that survives any future
        // dp-per-hour change: whatever sits below the last gridline must be
        // page furniture (a label plus a margin), never another whole hour.
        expect(
          contentHeight - ruledSpan,
          lessThan(hourBand),
          reason:
              'the timeline is ${contentHeight - ruledSpan}dp taller than its '
              'ruled span, i.e. at least one full ${hourBand}dp hour of dead '
              'scroll below the last hour line. `TimelineHourRuler` is sizing '
              'itself past its own last label again.',
        );

        // And the exact composition, so a REGRESSION that adds half an hour
        // (which would still pass the bound above) is caught too. The label
        // term is MEASURED off the rendered bottom-most label rather than
        // predicted from font metrics — the same reason the production code
        // measures it with a `TextPainter`.
        // Located as "the ruler's bottom-most label", never by its string: the
        // day's last hour is a function of the fixture's extent, and a
        // hard-coded «13:00» would silently stop measuring anything the moment
        // a duration in the fixture changed.
        final List<Rect> labelRects =
            find
                .descendant(
                  of: find.byType(TimelineHourRuler),
                  matching: find.byType(Text),
                )
                .evaluate()
                .map((Element e) {
                  final RenderBox box = e.renderObject! as RenderBox;
                  return box.localToGlobal(Offset.zero) & box.size;
                })
                .toList()
              ..sort((Rect a, Rect b) => a.top.compareTo(b.top));
        expect(labelRects, isNotEmpty);
        final double lastLabelHeight = labelRects.last.height;
        expect(
          contentHeight - ruledSpan - lastLabelHeight,
          closeTo(VelvetSpacing.lg, 1.0),
          reason:
              'below the last gridline the timeline should hold exactly the '
              'last hour label plus one VelvetSpacing.lg bottom margin.',
        );
      },
    );
  });
}
