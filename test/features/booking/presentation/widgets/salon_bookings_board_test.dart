// Phase 21.12 — the salon master-column board, and the proof that adding it
// left the two single-master routes alone.
//
// Three groups, in the order the brief demands them:
//
//   1. THE DENSITY TOKEN REDUCES TO THE SHIPPED CONSTANTS. Every getter on
//      `TimelineDensity.master` is asserted against the literal the retired
//      per-file constant held, including the N-column clamp at N == 1 against
//      the exact `math.min(_kCardW, maxWidth)` expression it generalises.
//      These are the "the master scope is unchanged BY CONSTRUCTION" claims,
//      stated as assertions instead of as a comment.
//   2. THE MASTER SCOPE STILL RENDERS AS BEFORE. Pumped through the SAME
//      widget with no new argument passed, and measured: hour band, ruler
//      width, and no roster strip anywhere in the tree.
//   3. THE BOARD. One chip per master, each chip EXACTLY as wide as and
//      horizontally flush with its own column — and both of those measured on
//      screen, never read off a widget field (a `SizedBox(width:)` assertion
//      would pass on a board whose strip and grid had drifted apart).
//
// Group 3's alignment case is the one that matters: it is what the single
// shared horizontal `ScrollPosition` exists to guarantee, and it is asserted
// AFTER a real horizontal drag, since at rest two desynchronised scrollers
// would agree too.

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_column_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/timeline_density.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/timeline_hour_ruler.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

/// Kyiv 2026-06-15 — a stable, non-DST-straddling weekday.
final DateTime _day = DateTime(2026, 6, 15);

/// `hh:mm` Kyiv on [_day], as the canonical UTC instant a `Booking` carries.
/// Kyiv is UTC+3 in June, so 10:00 Kyiv is 07:00Z.
///
/// A FIXED instant is required here, and it is safe. Required: every
/// assertion in this file is a GEOMETRY measurement against a known hour
/// band (84dp at salon density, 120dp at master density), so the fixtures
/// must land on named Kyiv wall-clock hours on a day that does not straddle
/// a DST transition — a now-relative `futureBookingStart()` offset lands on
/// an arbitrary time and would make the band arithmetic un-writable. Safe:
/// nothing here reads `BookingDisplayX.isPast` or any other real-clock
/// predicate — no card action, no status copy, no countdown is asserted —
/// and the date is already in the PAST, so it cannot silently cross a
/// boundary later the way a future literal can. This is precisely the
/// "fixed instant, deterministic relative to itself" case the annotation
/// exists for.
// (The rationale is the doc comment above; the marker below must be the line
// DIRECTLY above the literal and must be a SINGLE line — a second continuation
// line becomes `prev` and the gate stops seeing the marker at all. That trap is
// named in `scripts/forbid_stale_future_date_fixture.sh`'s own header.)
// future-date-ok: fixed PAST Kyiv day; geometry-only assertions, no isPast.
final DateTime _dayUtcMidnight = DateTime.utc(2026, 6, 15);

DateTime _kyiv(int hour, int minute) =>
    _dayUtcMidnight.add(Duration(hours: hour - 3, minutes: minute));

Booking _booking({
  required String id,
  required String masterId,
  required int hour,
  int minute = 0,
  int durationMinutes = 60,
}) {
  final DateTime start = _kyiv(hour, minute);
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

MasterColumnEntry _entry(String id, String name, int count) =>
    MasterColumnEntry(
      masterId: id,
      name: name,
      type: MasterType.salonMaster,
      bookingCount: count,
      professionalTitle: 'Стиліст',
      avgRating: 4.8,
    );

/// The on-screen rect of the roster chip for [masterId].
Rect _chipRect(WidgetTester tester, String masterId) => tester.getRect(
  find.byKey(ValueKey<String>('salon-bookings-column-chip-$masterId')),
);

/// The on-screen rect of the timeline card for [bookingId].
Rect _cardRect(WidgetTester tester, String bookingId) =>
    tester.getRect(find.byKey(ValueKey<String>('timeline-card-$bookingId')));

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  group('TimelineDensity.master reduces to the shipped constants', () {
    // The whole "the master scope is unchanged by construction" argument in
    // `bookings_timeline_grid.dart`'s ADDENDUM 10 rests on these five
    // equalities. A future density tweak that breaks one of them fails HERE,
    // with the number attached, instead of shipping a silently moved
    // timeline.
    test('hourHeight == the retired _kHourH (120)', () {
      expect(TimelineDensity.master.hourHeight, 120);
      expect(
        TimelineDensity.master.hourHeight,
        BookingsTimelineGrid.kMasterHourHeight,
      );
      // And the ruler reads the SAME number — the two-file lockstep ADDENDUM
      // 10 removed. This is now structurally impossible to break, which is
      // exactly why it is worth pinning that it stayed impossible.
      expect(
        TimelineHourRuler.kMasterHourHeight,
        TimelineDensity.master.hourHeight,
      );
    });

    test('slotHeight == the retired _kSlotH (60), i.e. half the hour', () {
      expect(TimelineDensity.master.slotHeight, 60);
      expect(
        TimelineDensity.master.slotHeight,
        TimelineDensity.master.hourHeight / 2,
      );
    });

    test('rulerWidth == the retired _kRulerWidth (42)', () {
      expect(TimelineDensity.master.rulerWidth, 42);
      expect(
        TimelineHourRuler.kMasterRulerWidth,
        TimelineDensity.master.rulerWidth,
      );
    });

    test('columnWidthCeiling == the retired _kCardW (272)', () {
      expect(TimelineDensity.master.columnWidthCeiling, 272);
      expect(
        BookingsTimelineGrid.kMasterColumnWidthCeiling,
        TimelineDensity.master.columnWidthCeiling,
      );
    });

    test('columnWidth(w) IS math.min(272, w) at one column per viewport — '
        'the shipped ADDENDUM 3 clamp, term for term', () {
      // Swept across the clamp's boundary in both directions, so the test
      // cannot pass by both sides happening to saturate. 278 is the 360dp
      // Android baseline's real lane area (see `_kTimelineLeftInset`'s
      // arithmetic); 266 is what it was BEFORE that inset halved, i.e. the
      // narrow-device case the clamp exists for.
      for (final double w in <double>[0, 100, 266, 271, 272, 278, 1000]) {
        expect(
          TimelineDensity.master.columnWidth(w),
          w < 272 ? w : 272,
          reason: 'lane viewport $w',
        );
      }
    });

    test('the salon scope lands on the derived numbers, not on guesses', () {
      const TimelineDensity salon = TimelineDensity.salon;
      expect(salon.hourHeight, closeTo(84, 0.001)); // 120 * 0.7
      expect(salon.slotHeight, closeTo(42, 0.001));
      expect(salon.rulerWidth, 30); // round(42 * 0.7) = 29.4 -> 30, floored
      expect(salon.columnWidthCeiling, 190); // round(272 * 0.7)
      expect(salon.columnGutter, 6); // round(8 * 0.7)

      // The 360dp baseline, worked end to end exactly as
      // `TimelineDensity.columnWidth`'s doc states it:
      //   360 − 12 (left inset) − 12 (right inset) − 30 (ruler) − 4 (gap)
      const double laneViewport = 360 - 12 - 12 - 30 - VelvetSpacing.xs;
      expect(laneViewport, 302);
      expect(salon.columnWidth(laneViewport), 148);

      // …and on a 430dp device the columns grow TOWARD the ceiling, never
      // past it — the property the ceiling exists for.
      expect(salon.columnWidth(430 - 12 - 12 - 30 - VelvetSpacing.xs), 183);
      expect(salon.columnWidth(2000), 190);
    });

    test('the ruler label nudge is NOT scaled — typography does not scale', () {
      // Stated as an assertion because the partial design preview scales it
      // and a future port might follow that prose. Scaling it by 0.7 would
      // hang every salon-scope hour label ~2dp below its own gridline.
      expect(TimelineHourRuler.labelCenteringNudge, 7);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('the master scope is untouched (no new argument passed)', () {
    testWidgets('one hour of ruler still measures 120dp', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(
        BookingsTimelineGrid(
          bookings: <Booking>[
            _booking(id: 'b1', masterId: 'm1', hour: 10),
            _booking(id: 'b2', masterId: 'm1', hour: 12),
          ],
          day: _day,
          onBookingTap: (_) {},
        ),
        width: 360,
        height: 600,
      );
      await tester.pump();

      final Finder labels = find.descendant(
        of: find.byType(TimelineHourRuler),
        matching: find.byType(Text),
      );
      expect(labels, findsAtLeast(2));
      final double first = tester.getTopLeft(labels.at(0)).dy;
      final double second = tester.getTopLeft(labels.at(1)).dy;
      expect(second - first, closeTo(120, 0.01));
    });

    testWidgets('the ruler gutter still measures 42dp wide', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(
        BookingsTimelineGrid(
          bookings: <Booking>[_booking(id: 'b1', masterId: 'm1', hour: 10)],
          day: _day,
          onBookingTap: (_) {},
        ),
        width: 360,
        height: 600,
      );
      await tester.pump();
      expect(tester.getSize(find.byType(TimelineHourRuler)).width, 42);
    });

    testWidgets('no roster strip is built anywhere in the master tree', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(
        BookingsTimelineGrid(
          bookings: <Booking>[_booking(id: 'b1', masterId: 'm1', hour: 10)],
          day: _day,
          onBookingTap: (_) {},
        ),
        width: 360,
        height: 600,
      );
      await tester.pump();
      expect(find.byType(MasterColumnStrip), findsNothing);
      expect(find.byType(StripScrollIndicator), findsNothing);
      // …and the one card still renders through the lane `Column`, i.e. the
      // pre-existing branch, not the board's `Positioned` one.
      expect(find.byType(MasterBookingCard), findsOneWidget);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('the salon board', () {
    List<TimelineBoardColumn> columns() => <TimelineBoardColumn>[
      TimelineBoardColumn(
        header: _entry('m1', 'Оля Коваль', 2),
        bookings: <Booking>[
          _booking(id: 'a1', masterId: 'm1', hour: 10),
          _booking(id: 'a2', masterId: 'm1', hour: 12),
        ],
      ),
      TimelineBoardColumn(
        header: _entry('m2', 'Ніна Бойко', 1),
        bookings: <Booking>[_booking(id: 'b1', masterId: 'm2', hour: 11)],
      ),
      // A master with NOTHING booked. The column must still be emitted, or
      // every column to its right renumbers and un-pins its own chip.
      TimelineBoardColumn(
        header: _entry('m3', 'Іра Ткач', 0),
        bookings: const <Booking>[],
      ),
    ];

    Future<void> pumpBoard(
      WidgetTester tester, {
      double? textScaleFactor,
    }) async {
      await tester.pumpApp(
        Padding(
          // The real body inset the salon scope uses
          // (`_kBoardBodyPadding`), so the lane viewport under test is the
          // one the screen actually produces.
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: BookingsTimelineGrid(
            bookings: <Booking>[
              for (final TimelineBoardColumn c in columns()) ...c.bookings,
            ]..sort((Booking a, Booking b) => a.startAt.compareTo(b.startAt)),
            day: _day,
            onBookingTap: (_) {},
            density: TimelineDensity.salon,
            columns: columns(),
          ),
        ),
        width: 360,
        height: 600,
        textScaleFactor: textScaleFactor,
      );
      await tester.pump();
    }

    testWidgets('renders one roster chip per column, empty ones included', (
      WidgetTester tester,
    ) async {
      await pumpBoard(tester);
      expect(find.byType(MasterColumnStrip), findsOneWidget);
      for (final String id in <String>['m1', 'm2', 'm3']) {
        expect(
          find.byKey(ValueKey<String>('salon-bookings-column-chip-$id')),
          findsOneWidget,
          reason: 'chip for $id',
        );
      }
    });

    testWidgets('two master columns fit on a 360dp phone, at ~148dp each', (
      WidgetTester tester,
    ) async {
      await pumpBoard(tester);
      // MEASURED on screen, not read off `SizedBox(width:)` — a field read
      // would pass even if the chip were laid out somewhere else entirely.
      expect(_chipRect(tester, 'm1').width, closeTo(148, 0.5));
      expect(_chipRect(tester, 'm2').width, closeTo(148, 0.5));
      // The second chip's right edge is inside the 360dp viewport, which is
      // the user-visible form of "an owner sees at least two masters".
      expect(_chipRect(tester, 'm2').right, lessThanOrEqualTo(360.5));
      // The third is off-screen — that partial/absent column IS the scroll
      // affordance, and the indicator is drawn because of it.
      expect(find.byType(StripScrollIndicator), findsOneWidget);
    });

    testWidgets('a chip is flush with its own column — AFTER a real drag', (
      WidgetTester tester,
    ) async {
      await pumpBoard(tester);

      // At rest, chip 1 and the card in column 1 share a left edge.
      expect(
        _chipRect(tester, 'm1').left,
        closeTo(_cardRect(tester, 'a1').left, 0.5),
      );

      // Now drag the GRID sideways. With two synchronised controllers this is
      // where a listener/echo bug shows up; with one shared `ScrollPosition`
      // there is nothing to desynchronise. Dragging the grid (not the strip)
      // is deliberate: it proves the weld holds in the direction a listener
      // implementation would have to propagate.
      await tester.drag(
        find.byKey(const ValueKey<String>('timeline-column-stack')),
        const Offset(-120, 0),
      );
      await tester.pumpAndSettle();

      final Rect chip1 = _chipRect(tester, 'm1');
      final Rect card1 = _cardRect(tester, 'a1');
      expect(
        chip1.left,
        closeTo(card1.left, 0.5),
        reason:
            'the roster chip drifted off its column after a horizontal drag — '
            'the strip and the grid are no longer sharing one ScrollPosition',
      );
      // And it actually MOVED, so the assertion above is not vacuously
      // comparing two things that both stayed put.
      expect(chip1.left, lessThan(12));
    });

    testWidgets('an hour band is 84dp and the gutter 30dp at salon density', (
      WidgetTester tester,
    ) async {
      await pumpBoard(tester);
      expect(tester.getSize(find.byType(TimelineHourRuler)).width, 30);

      final Finder labels = find.descendant(
        of: find.byType(TimelineHourRuler),
        matching: find.byType(Text),
      );
      expect(labels, findsAtLeast(2));
      expect(
        tester.getTopLeft(labels.at(1)).dy - tester.getTopLeft(labels.at(0)).dy,
        closeTo(84, 0.01),
      );
    });

    testWidgets('the ruler stays put horizontally while the grid scrolls', (
      WidgetTester tester,
    ) async {
      await pumpBoard(tester);
      final double before = tester
          .getTopLeft(find.byType(TimelineHourRuler))
          .dx;
      await tester.drag(
        find.byKey(const ValueKey<String>('timeline-column-stack')),
        const Offset(-120, 0),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byType(TimelineHourRuler)).dx,
        closeTo(before, 0.01),
        reason: 'the hour ruler must never ride the horizontal scroller',
      );
    });

    // ═══════════════════════════════════════════════════════════════════
    // TEXT SCALE. Added by QA (Phase 21.12): every case above pumps at
    // textScaler 1.0, which is the SOLE reason two real layout bugs shipped
    // green. `test/helpers/overflow_guard.dart` is armed by `pumpApp` on
    // every pump in this file already — it simply had nothing to catch,
    // because nothing here ever grew the text.
    //
    // MEASURED BEFORE THE FIX (this exact harness):
    //   • textScaler 1.3 → "A RenderFlex overflowed by 3.0 pixels on the
    //     bottom", once per roster chip — `MasterColumnStrip`'s 64dp
    //     `SizedBox` against a three-text-line chip body.
    //   • textScaler 2.0 → the same overflow at 30 pixels, PLUS "A RenderFlex
    //     overflowed by 8.9 pixels on the right" per card —
    //     `master_booking_card.dart`'s compact client-name/time-range/dot row,
    //     whose own comment budgets it against a 203dp lane while the salon
    //     column hands it 125dp of inner width.
    //
    // The guard fails on the FIRST overflow it records, so the two are pumped
    // as separate cases rather than one: a single combined case would have
    // reported the strip and hidden the card behind it.
    group('at an accessibility text scale', () {
      for (final double scale in <double>[1.0, 1.3, 2.0]) {
        testWidgets('the whole board lays out with NO overflow at '
            'textScaler $scale', (WidgetTester tester) async {
          await pumpBoard(tester, textScaleFactor: scale);
          // The overflow guard asserts in `tearDown`. These two keep the case
          // from passing vacuously on a board that failed to build at all.
          expect(find.byType(MasterColumnStrip), findsOneWidget);
          expect(find.byType(MasterBookingCard), findsAtLeast(1));
        });
      }

      testWidgets('the roster strip GROWS with the text scale — a fixed 64dp '
          'reserve is exactly what overflowed', (WidgetTester tester) async {
        await pumpBoard(tester);
        final double atOne = tester
            .getSize(find.byType(MasterColumnStrip))
            .height;
        expect(atOne, closeTo(MasterColumnStrip.height, 0.01));

        await pumpBoard(tester, textScaleFactor: 2.0);
        final double atTwo = tester
            .getSize(find.byType(MasterColumnStrip))
            .height;

        // MEASURED on screen, not read off `MasterColumnStrip.height` — a
        // field read would pass on a strip that never grew.
        expect(
          atTwo,
          greaterThan(atOne + 20),
          reason:
              'the strip reserve must track its own text; the pre-fix 64dp '
              'constant overflowed by 30dp at this scale',
        );
        expect(atTwo, closeTo(MasterColumnStrip.height * 2, 0.01));
      });

      testWidgets('the CARDS are clamped at the documented ceiling, and the '
          'clamp is what keeps the 125dp compact row inside its column', (
        WidgetTester tester,
      ) async {
        await pumpBoard(tester, textScaleFactor: 2.0);

        // Read the scaler the card actually renders under, from INSIDE the
        // card's own element — the clamp is a `MediaQuery` the lane inserts,
        // so this is the observable, not the constant.
        final BuildContext cardContext = tester.element(
          find.byType(MasterBookingCard).first,
        );
        expect(
          MediaQuery.textScalerOf(cardContext).scale(14),
          closeTo(14 * BookingsTimelineGrid.kBoardCardMaxTextScale, 0.01),
          reason:
              'the salon board clamps its cards to '
              'BookingsTimelineGrid.kBoardCardMaxTextScale; unclamped, the '
              'compact row overflows its 125dp of inner width by 8.9dp',
        );

        // …and the MASTER scope is NOT clamped — its 272dp lane fits 2.0.
        await tester.pumpApp(
          BookingsTimelineGrid(
            bookings: <Booking>[_booking(id: 'b1', masterId: 'm1', hour: 10)],
            day: _day,
            onBookingTap: (_) {},
          ),
          width: 360,
          height: 600,
          textScaleFactor: 2.0,
        );
        await tester.pump();
        final BuildContext masterCardContext = tester.element(
          find.byType(MasterBookingCard).first,
        );
        expect(
          MediaQuery.textScalerOf(masterCardContext).scale(14),
          closeTo(28, 0.01),
          reason:
              'clamping the master scope too would be an a11y regression on a '
              'lane that genuinely fits the larger type',
        );
      });
    });

    testWidgets('an empty roster renders the no-masters state, not a grid', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(
        BookingsTimelineGrid(
          bookings: const <Booking>[],
          day: _day,
          onBookingTap: (_) {},
          density: TimelineDensity.salon,
          columns: const <TimelineBoardColumn>[],
        ),
        width: 360,
        height: 600,
      );
      await tester.pump();
      expect(
        find.byKey(const Key('salon-bookings-no-masters')),
        findsOneWidget,
      );
      expect(find.byType(TimelineHourRuler), findsNothing);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // AUDIT H2 / M1 (2026-09-16) — horizontal culling, and a scroll extent that
  // is a FLOOR rather than a frozen textScaler-1.0 estimate.
  // ═════════════════════════════════════════════════════════════════════════
  group('the board culls columns horizontally (audit H2)', () {
    /// Ten masters, each with a full working day, on the 360dp baseline where
    /// only ~2 columns fit. This is the shape the finding measured: 110 cards
    /// live, 0 culled, 77 of them laid out entirely beyond x = 360.
    ///
    /// ⚠ COLUMN 5 CARRIES ONE EXTRA BOOKING, on purpose. `_BoardStack` never
    /// culls the column attaining the deepest planned bottom (mobile-perf
    /// L-a — a culled placeholder contributes the PLANNED height while a live
    /// column contributes its REAL one, so culling the deepest column shrank
    /// the board's extent by up to 55dp above textScaler 1.0). With ten
    /// IDENTICAL columns every one of them ties for deepest, and the pin
    /// resolves ties to the FIRST index — which would make column 0
    /// permanently live and silently defeat the left-edge case below. Giving
    /// exactly one INTERIOR column the deepest bottom keeps that pin off both
    /// ends, so both edges of the band stay observable, which is what these
    /// tests are actually about.
    List<TimelineBoardColumn> wideColumns() => <TimelineBoardColumn>[
      for (int m = 0; m < 10; m++)
        TimelineBoardColumn(
          header: _entry('m$m', 'Майстер $m', m == 5 ? 5 : 4),
          bookings: <Booking>[
            for (int h = 9; h < (m == 5 ? 14 : 13); h++)
              _booking(id: 'c$m-$h', masterId: 'm$m', hour: h),
          ],
        ),
    ];

    Future<void> pumpWide(WidgetTester tester) async {
      final List<TimelineBoardColumn> cols = wideColumns();
      await tester.pumpApp(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: BookingsTimelineGrid(
            bookings: <Booking>[
              for (final TimelineBoardColumn c in cols) ...c.bookings,
            ]..sort((Booking a, Booking b) => a.startAt.compareTo(b.startAt)),
            day: _day,
            onBookingTap: (_) {},
            density: TimelineDensity.salon,
            columns: cols,
          ),
        ),
        width: 360,
        height: 600,
      );
      // TWO pumps. The lane viewport's real WIDTH is only readable from the
      // post-frame callback after the frame that laid the scroller out, so
      // frame 1 still runs with the wide-open seed band (= cull nothing).
      await tester.pump();
      await tester.pump();
    }

    testWidgets('the far columns become same-width placeholders and their '
        'cards are never built', (WidgetTester tester) async {
      await pumpWide(tester);

      expect(
        find.byKey(const ValueKey<String>('timeline-card-c0-9')),
        findsOneWidget,
        reason: 'column 0 is on screen, so it renders for real',
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-column-culled-9')),
        findsOneWidget,
        reason:
            'column 9 starts ~1386dp into a 302dp lane viewport; not even the '
            'half-viewport slack band reaches it',
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-card-c9-9')),
        findsNothing,
        reason: 'a culled column builds no cards at all — that is the point',
      );

      // The placeholder is EXACTLY as wide as a live lane, measured ON SCREEN
      // rather than read off a `SizedBox(width:)` field, so nothing to its
      // left or right can shift when a column is culled or un-culled.
      final double liveWidth = tester
          .getRect(
            find.byKey(const ValueKey<String>('timeline-column-0-lane-0')),
          )
          .width;
      final double culledWidth = tester
          .getRect(
            find.byKey(const ValueKey<String>('timeline-column-culled-9')),
          )
          .width;
      expect(culledWidth, closeTo(liveWidth, 0.01));
    });

    testWidgets('the culled set FOLLOWS the viewport — it is not a fixed '
        'suffix', (WidgetTester tester) async {
      await pumpWide(tester);
      expect(
        find.byKey(const ValueKey<String>('timeline-card-c9-9')),
        findsNothing,
      );

      // `dragFrom` at an ON-SCREEN point, not `drag(find…)`: the strip is
      // 1534dp wide here, so its CENTER — which `drag` aims at — is far
      // outside the 360dp test surface and the hit test misses. (x = 200 is
      // inside the strip's own band: 12 page inset + 30 ruler + 4 gap = 46 is
      // its left edge; y = 30 is inside its 64dp row.)
      await tester.dragFrom(const Offset(200, 30), const Offset(-4000, 0));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('timeline-card-c9-9')),
        findsOneWidget,
        reason: 'the last master is on screen now, so their cards must build',
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-column-culled-0')),
        findsOneWidget,
        reason:
            'and the first column — now far to the LEFT — is culled in its '
            'turn. The horizontal band has BOTH edges, unlike the vertical '
            'one, because a column placeholder WIDTH is computed rather than '
            'estimated (see _visibleColumnBand).',
      );
    });
  });

  group('the board scroll extent is a FLOOR, not a frozen estimate (M1)', () {
    /// Eight back-to-back 15-minute bookings in ONE column. Deliberate: a
    /// 15-minute band at salon density is 21dp, below
    /// `MasterBookingCard.microLayoutNaturalHeight`, so each card's REAL
    /// height is content-driven — which is exactly the case a tight
    /// `SizedBox(height: plannedStackHeight)` clipped and could never grow
    /// out of.
    List<TimelineBoardColumn> denseColumn() => <TimelineBoardColumn>[
      TimelineBoardColumn(
        header: _entry('m1', 'Оля Коваль', 8),
        bookings: <Booking>[
          for (int i = 0; i < 8; i++)
            _booking(
              id: 'd$i',
              masterId: 'm1',
              hour: 10 + (i * 15) ~/ 60,
              minute: (i * 15) % 60,
              durationMinutes: 15,
            ),
        ],
      ),
    ];

    Future<double> extentAt(WidgetTester tester, double scale) async {
      final List<TimelineBoardColumn> cols = denseColumn();
      await tester.pumpApp(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: BookingsTimelineGrid(
            bookings: <Booking>[
              for (final TimelineBoardColumn c in cols) ...c.bookings,
            ],
            day: _day,
            onBookingTap: (_) {},
            density: TimelineDensity.salon,
            columns: cols,
          ),
        ),
        width: 360,
        height: 600,
        textScaleFactor: scale,
      );
      await tester.pump();
      await tester.pump();
      // The SCROLLED BOX itself, measured on screen. NOT
      // `maxScrollExtent + viewportDimension`: the roster strip above the
      // vertical scroller grows with the text scale too, so that expression
      // reports the VIEWPORT whenever the content is shorter than it — which
      // is precisely the case a clipped board produces, and would have made
      // this assertion read backwards.
      return tester
          .getRect(find.byKey(const ValueKey<String>('timeline-column-stack')))
          .height;
    }

    testWidgets('the extent GROWS with the text scale instead of staying '
        'frozen at the textScaler-1.0 planned geometry', (
      WidgetTester tester,
    ) async {
      final double at1 = await extentAt(tester, 1.0);
      final double at13 = await extentAt(tester, 1.3);
      expect(
        at13,
        greaterThan(at1),
        reason:
            'the board used to hand its Stack a TIGHT height, so the extent '
            'was pinned to the planned (scale-1.0) geometry and inflated '
            'cards were silently cropped by the scroller Clip.hardEdge. '
            'A ConstrainedBox(minHeight:) — the master branch own shape — '
            'makes it a FLOOR. Measured: $at1 -> $at13',
      );
    });
  });
}
