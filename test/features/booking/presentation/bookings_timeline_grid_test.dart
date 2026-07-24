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

// NO ABSOLUTE FUTURE LITERALS (2026-07-22, ratchet turn) — every instant in
// this file used to be a hand-rolled `DateTime.utc(2026, 7, 20, …)`, which is
// exactly why the file sat in `scripts/.stale_future_date_allow`. Those
// literals have since elapsed. [_day] and [_kyivAtUtc] replace them with a
// now-relative Kyiv anchor, and the file is DELISTED. [_kyivAtUtc] takes a
// KYIV wall-clock hour and returns the UTC instant, so nothing here hand-codes
// a `+3` summer offset that would be wrong for half the year once the anchor
// day started moving.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_display_x.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/timeline_hour_ruler.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';

/// The KYIV calendar day every fixture below is anchored to — date-only,
/// derived from the real clock rather than a literal (see the file header).
///
/// Lazily initialised, which is safe here: `test/flutter_test_config.dart`
/// calls `initBeauticaTimeZones()` before this file's `main()` (and therefore
/// before any `group(...)` body) runs, so [beauticaZone] is always resolved by
/// the time this is first read.
final DateTime _day = dateOnly(toBeauticaTime(futureBookingStart()));

/// The UTC instant for `hour:minute` KYIV wall-clock on [_day].
///
/// Built through [tz.TZDateTime] rather than by subtracting a hard-coded
/// offset: Kyiv is UTC+3 in summer and UTC+2 in winter, and [_day] moves with
/// the calendar, so any hand-written offset would be wrong for roughly half the
/// year. Returns a UTC instant because `Booking.startAt` is canonical UTC.
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

/// Whether [element] has a [MasterBookingCard] ancestor — used by the R4
/// group's gridline finder to exclude the card's own same-coloured
/// (`BrandColors.faint`) divider hairline (adaptive full/compact layout
/// pass, 2026-07-20) from a ruler-only `ColoredBox` search.
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

/// EVERY rendered gridline the grid paints — hour lines (full-opacity
/// [BrandColors.faint]) AND half-hour lines (the same hue at alpha 0.4) —
/// sorted ascending by rendered top, so rung `i` is exactly
/// `firstHour * 60 + i * 30` minutes.
///
/// Cards' own same-coloured hairline dividers are excluded via
/// [_hasCardAncestor], or the ladder gains phantom rungs.
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

/// The dp the RULER actually renders one 30-minute rung at — measured off two
/// adjacent gridline rects, never re-derived from `_kHourH`.
///
/// This is the antidote to the self-referential assertion that let the
/// card/gridline misalignment ship twice: a test that recomputes an expected
/// height as `minutes / 60 * 120` restates the widget's own constant and can
/// only catch a change to that constant — never a change to how it is APPLIED.
/// See `bookings_timeline_grid_gridline_registration_test.dart`'s header, the
/// parametric ground-truth guard this mirrors.
double _renderedRungBand(WidgetTester tester) {
  final List<Rect> ladder = _gridlineLadderAscending(tester);
  expect(
    ladder.length,
    greaterThanOrEqualTo(2),
    reason:
        'the ruler must paint at least two gridlines for a scale to be '
        'measurable from rendered geometry',
  );
  final double band = ladder[1].top - ladder[0].top;
  expect(
    band,
    greaterThan(0),
    reason: 'gridline rungs must be strictly ascending',
  );
  return band;
}

/// The dp the ruler renders one WALL-CLOCK HOUR at — two rendered 30-minute
/// rungs. Same rationale as [_renderedRungBand].
double _renderedHourBand(WidgetTester tester) => _renderedRungBand(tester) * 2;

void main() {
  setUpAll(initBeauticaTimeZones);

  group('R1 regression — negative grid height', () {
    // The exact case from the phase doc: a 23:30 Kyiv booking with a
    // 60-minute duration (ends 00:30 the NEXT Kyiv day) alongside a 09:00
    // Kyiv booking, both on the SAME selected day. Both instants are built
    // FROM the Kyiv wall-clock by [_kyivAtUtc], so the UTC offset (+2 winter /
    // +3 summer) never has to be hand-computed — and does not have to be
    // re-checked when [_day] moves.
    final DateTime day = _day;
    final Booking morning = _booking(
      id: 'r1-morning',
      startAtUtc: _kyivAtUtc(9),
      durationMinutes: 60,
    );
    final Booking lateNight = _booking(
      id: 'r1-late',
      startAtUtc: _kyivAtUtc(23, 30),
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

      // Both cards must actually be present (not silently dropped). The
      // morning one is on screen at rest.
      expect(
        find.byKey(const ValueKey<String>('timeline-card-r1-morning')),
        findsOneWidget,
      );

      // The 23:30 card sits ~1624dp down a 600dp-tall test viewport, and the
      // grid CULLS cards more than a viewport outside the visible band
      // (`bookings_timeline_grid.dart`'s "ADDENDUM 4"). So it is scrolled to,
      // exactly as a real master would — which STRENGTHENS this assertion
      // rather than relaxing it: the late card now has to survive both the R1
      // extent maths AND a real scroll to be found, instead of merely
      // existing in an eagerly-materialised off-screen subtree.
      await tester.drag(
        find.byType(BookingsTimelineGrid),
        const Offset(0, -1600),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('timeline-card-r1-late')),
        findsOneWidget,
      );
    });
  });

  group(
    'R4 regression — first hour label must not clip at the viewport top',
    () {
      // The bug this pins: `TimelineHourRuler` used to lay its labels out at
      // `top: i * _kHourH - _kLabelCenteringNudge` so the text visually
      // centred on its hour line. For `i == 0` that produced `top: -7` — 7dp
      // ABOVE the ruler's own origin. `TimelineHourRuler`'s own `Stack` uses
      // `clipBehavior: Clip.none`, so it never clipped that itself, but this
      // whole widget is the CONTENT of `bookings_timeline_grid.dart`'s outer
      // vertical `SingleChildScrollView` (default `Clip.hardEdge`), and at
      // rest (scroll offset 0, Android's clamping physics giving no
      // overscroll) that permanently cropped the top of the very first hour
      // label — a real-device report, not a cosmetic nit.
      //
      // The fix moved the nudge to the OTHER stack instead (see
      // `TimelineHourRuler.labelCenteringNudge`'s doc and the `Padding` in
      // `bookings_timeline_grid.dart`): ruler labels now sit at
      // `top: i * _kHourH` (never negative, `i == 0` included), and the
      // gridline/card `Stack` is shifted down by the same constant so the
      // 7dp label↔line visual relationship is preserved for every hour.
      //
      // This test pumps the REAL `BookingsTimelineGrid` (not
      // `TimelineHourRuler` in isolation, unlike the "past midnight" group
      // above) so the outer `SingleChildScrollView` that actually did the
      // clipping is present in the tree — a bare `Center` (as the isolated
      // ruler tests use) has no clip boundary at all and cannot reproduce
      // this class of bug.
      final DateTime day = _day;
      // A single 60-minute booking starting exactly on the hour (09:00 Kyiv,
      // 06:00 UTC) makes the ruler's extent deterministic: firstHour = 9,
      // lastHour = 10, i.e. exactly two labels — "09:00" (i == 0, the one
      // that used to clip) and the accent "10:00" (i == 1, a later label
      // whose registration must stay untouched by the fix).
      final Booking onTheHour = _booking(
        id: 'r4-on-hour',
        startAtUtc: _kyivAtUtc(9),
        durationMinutes: 60,
      );

      // Mirrors `TimelineHourRuler._kHourH` / `BookingsTimelineGrid._kHourH`
      // (both files assert, in their own doc comments, that the two MUST
      // match) — not re-exported, so pinned here as a plain literal the way
      // this file already pins other cross-file geometry invariants (e.g. the
      // 48dp clip floor in the R2 group above). Raised 72 -> 112 by the
      // proportional-duration-height pass (2026-07-20), 112 -> 168 by the
      // vertical-scale pass, then 168 -> 120 by ADDENDUM 8 (2026-07-24) once
      // the MICRO card layout removed the 56dp floor that forced the scale up.
      const double hourHeight = 120;

      Finder rulerLabel(String text) => find.descendant(
        of: find.byType(TimelineHourRuler),
        matching: find.text(text),
      );

      /// The gridlines are the `ColoredBox(color: BrandColors.faint)` leaves
      /// inside the `timeline-lane-stack` `Stack` — no `Key` of their own
      /// (there's no need for one outside this test). That `ColoredBox`
      /// color combination is no longer unique to the ruler within the
      /// pumped tree, though: the adaptive full/compact layout pass
      /// (2026-07-20, `master_booking_card.dart`) added a same-coloured
      /// hairline divider inside the card's FULL layout (a
      /// `Container(color: BrandColors.faint)`, which — like any
      /// `Container` with a plain `color` — builds its own `ColoredBox`
      /// internally), and this test's single 60-minute booking now renders
      /// that layout. `_hasCardAncestor` filters those out so this stays a
      /// ruler-only gridline count. Sorted ascending by rendered top so
      /// index 0 is always the FIRST (topmost) gridline regardless of
      /// `Stack` child order.
      List<Rect> gridlineRectsAscending(WidgetTester tester) {
        final Iterable<Element> elements = find
            .byWidgetPredicate(
              (Widget w) => w is ColoredBox && w.color == BrandColors.faint,
            )
            .evaluate();
        final List<Rect> rects =
            elements.where((Element e) => !_hasCardAncestor(e)).map((
              Element e,
            ) {
              final RenderBox box = e.renderObject! as RenderBox;
              return box.localToGlobal(Offset.zero) & box.size;
            }).toList()..sort((Rect a, Rect b) => a.top.compareTo(b.top));
        return rects;
      }

      testWidgets(
        'the first-hour label never renders above the viewport origin, and '
        'every label stays registered 7dp above its own gridline',
        (WidgetTester tester) async {
          await tester.pumpApp(
            BookingsTimelineGrid(
              bookings: <Booking>[onTheHour],
              day: day,
              onBookingTap: (_) {},
            ),
          );
          await tester.pump();

          final Rect firstLabelRect = tester.getRect(rulerLabel('09:00'));
          final Rect secondLabelRect = tester.getRect(rulerLabel('10:00'));
          final List<Rect> gridlines = gridlineRectsAscending(tester);
          expect(
            gridlines.length,
            2,
            reason: 'expected exactly one gridline per hour (09:00, 10:00)',
          );
          final Rect firstGridlineRect = gridlines[0];
          final Rect secondGridlineRect = gridlines[1];

          // THE CLIPPING ASSERTION — this is what goes red on the bug. At
          // scroll offset 0 (the pumped, unscrolled state), the outer
          // `SingleChildScrollView`'s viewport top IS the window's origin
          // (`pumpApp` places this widget directly as `MaterialApp.home`, no
          // intervening chrome), so any rendered `top < 0` here is content
          // that a `Clip.hardEdge` ancestor would crop.
          expect(
            firstLabelRect.top,
            greaterThanOrEqualTo(0),
            reason:
                'the first hour label rendered above the scrollable '
                'viewport\'s origin and would be clipped by the outer '
                'SingleChildScrollView at rest',
          );

          // REGISTRATION — the first label must still sit exactly
          // `labelCenteringNudge` above its own gridline …
          expect(
            firstGridlineRect.top - firstLabelRect.top,
            closeTo(TimelineHourRuler.labelCenteringNudge, 0.01),
          );
          // … and so must a LATER label (i == 1, never touched by the `i ==
          // 0` clipping bug) — proving a fix that shoves the whole ruler (or
          // the whole grid) around by some ad-hoc amount, rather than
          // preserving this per-hour relationship, cannot pass either.
          expect(
            secondGridlineRect.top - secondLabelRect.top,
            closeTo(TimelineHourRuler.labelCenteringNudge, 0.01),
          );

          // SPACING — the vertical distance from one hour to the next must
          // stay exactly `hourHeight` for both labels and gridlines, so a
          // fix that compresses/stretches spacing instead of redistributing
          // a constant leading amount cannot pass either.
          expect(
            secondLabelRect.top - firstLabelRect.top,
            closeTo(hourHeight, 0.01),
          );
          expect(
            secondGridlineRect.top - firstGridlineRect.top,
            closeTo(hourHeight, 0.01),
          );
        },
      );
    },
  );

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
    // ABSOLUTE wall-clock reading and genuinely differs: 01:00 Kyiv on [_day]
    // is 22:00 (or 23:00 in winter) UTC on the PRECEDING calendar day — a
    // different day than the raw UTC field names (the same witness shape
    // `slot_time_tz_regression_test.dart` uses). A Kyiv-correct
    // implementation, asked for [_day]'s timeline, renders "01:00"/"02:00".
    // A UTC-naive implementation (measuring the raw UTC instant against
    // [_day]'s UTC midnight) computes a NEGATIVE minutes-since-day-start and
    // renders "22:00"/"23:00" instead — proven by mutation below.
    testWidgets(
      'the ruler shows the KYIV hour ("01:00"), not the raw UTC hour ("22:00")',
      (WidgetTester tester) async {
        final DateTime day = _day;
        // 01:00 KYIV on [_day] — whose UTC instant lands on the PREVIOUS
        // calendar day (22:00 in summer, 23:00 in winter). That date crossing
        // is the whole witness: a UTC-naive implementation reads a different
        // day entirely. See [_kyivAtUtc].
        final DateTime crossing = _kyivAtUtc(1);
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

        // Scoped to the ruler, not a bare `find.text('01:00')`: the card
        // itself also reads through the Kyiv wall-clock (see below), so an
        // unscoped lookup would be ambiguous about which witness matched.
        final Finder rulerLabels = find.descendant(
          of: find.byType(TimelineHourRuler),
          matching: find.text('01:00'),
        );
        expect(rulerLabels, findsOneWidget);
        expect(find.text('02:00'), findsOneWidget);
        expect(find.text('22:00'), findsNothing);
        expect(find.text('23:00'), findsNothing);

        // The card's OWN start-time label is the second, independent
        // Kyiv-correctness witness (the card's `_minutesSinceDayStart`-
        // driven position derives the same value the ruler does) — proves
        // `MasterBookingCard` also reads through `toBeauticaTime`, not just
        // the ruler. Since the 2026-07-21 pass BOTH the card's layouts print
        // the same date-free start–end range (`formatSlotTimeRange`), so this
        // no longer depends on which layout the 60-minute (120dp floor)
        // booking selects — see `master_booking_card.dart`'s "The time is a
        // RANGE" header section. The range is the STRONGER witness of the two
        // it replaced: it proves BOTH instants convert, not just the start.
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('timeline-card-crossing')),
            matching: find.text(formatSlotTimeRange(b.startAt, b.endAt)),
          ),
          findsOneWidget,
        );

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
    // clip its own natural content down to that box via an OverflowBox +
    // ClipRect pair, i.e. "I can see only half of the card" for anything
    // shorter than ~50 minutes. The fix positions the card by `top`/`left`/
    // `width` ONLY — no `height:` — so it always renders at its full natural
    // size regardless of duration.
    //
    // THE FLOOR THIS ASSERTS IS THE CARD'S OWN NATURAL HEIGHT, NOT A LITERAL.
    // It used to be `greaterThan(48)` — the old clip floor, kept as a number
    // the compact card's ~56dp real height comfortably cleared. ADDENDUM 8
    // invalidated that: a 15-minute booking is now a 30dp box in the MICRO
    // layout, so `> 48` failed even though nothing is clipped. The property
    // being guarded was never "the card is tall"; it is "the card is never
    // SHORTER than the layout it selected needs", which is exactly
    // `MasterBookingCard.occupiedHeightFor(floor)`. Written against that, the
    // guard survives any future density or scale pass — and still fails
    // immediately if an `OverflowBox`/`ClipRect` crop comes back, because a
    // cropped card renders shorter than its own natural height by definition.
    testWidgets(
      'a 15-minute booking is positioned with no forced height, and renders '
      'at no less than its selected layout\'s full natural height',
      (WidgetTester tester) async {
        final DateTime day = _day;
        final Booking short = _booking(
          id: 'short',
          startAtUtc: _kyivAtUtc(9),
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

        // The card's ACTUAL rendered height is at least its own natural
        // content height — proof the whole card is on screen, not a truncated
        // sliver of it. A 15-minute booking's floor at 120dp/hour is 30dp,
        // which selects the MICRO layout (natural 28dp), so the box renders at
        // 30 and nothing is cropped.
        final double renderedHeight = tester
            .getSize(find.byKey(const ValueKey<String>('timeline-card-short')))
            .height;
        expect(
          renderedHeight,
          greaterThanOrEqualTo(
            MasterBookingCard.microLayoutNaturalHeight - 0.5,
          ),
          reason:
              'a $renderedHeight dp card is shorter than the micro layout\'s '
              'own ${MasterBookingCard.microLayoutNaturalHeight}dp natural '
              'content — something is cropping it (the retired R2 '
              'OverflowBox+ClipRect pair, or an exact `height:`).',
        );
        // And the content really is laid out, not merely allocated: a crop
        // would still leave the box measurable.
        expect(find.text(short.serviceName), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('overlapping bookings render in distinct lanes', () {
    testWidgets('two overlapping bookings get different left offsets', (
      WidgetTester tester,
    ) async {
      final DateTime day = _day;
      final Booking a = _booking(
        id: 'lane-a',
        startAtUtc: _kyivAtUtc(9),
        durationMinutes: 60,
      );
      final Booking b = _booking(
        id: 'lane-b',
        startAtUtc: _kyivAtUtc(9, 30), // overlaps a
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
      final DateTime day = _day;
      final Booking a = _booking(
        id: 'tap-a',
        startAtUtc: _kyivAtUtc(9),
        durationMinutes: 60,
      );
      final Booking b = _booking(
        id: 'tap-b',
        startAtUtc: _kyivAtUtc(11),
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
      final DateTime day = _day;
      final Booking guest = _booking(
        id: 'guest',
        startAtUtc: _kyivAtUtc(9),
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
    // edge. Both instants come from [_kyivAtUtc] — 09:00 and 09:30 KYIV.
    final DateTime day = _day;
    final Booking early = _booking(
      id: 'r3-early',
      startAtUtc: _kyivAtUtc(9),
      durationMinutes: 30,
    );
    final Booking late = _booking(
      id: 'r3-late',
      startAtUtc: _kyivAtUtc(9, 30),
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
          startAtUtc: _kyivAtUtc(18),
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

        // At ADDENDUM 8's 120dp/hour the 18:00 card sits ~1080dp down, still
        // below the initial cull window, so it starts as a placeholder. Scroll to the very bottom to materialise the real card
        // before measuring it — the grid-extent property under test is
        // independent of culling (the placeholder reserves the exact box).
        final ScrollableState scrollable = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byType(BookingsTimelineGrid),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
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

  group('proportional-duration-height pass (2026-07-20)', () {
    // Mirrors the private `BookingsTimelineGrid._kSlotH` / `_kHourH` (not
    // re-exported — same convention the R4 group above already uses for
    // `hourHeight`). `_kSlotH` (30-minute GRIDLINE slot) is `_kHourH / 2` by
    // construction.
    //
    // THESE TWO LITERALS ARE NOT THE PRIMARY GUARD, AND THE TWO ASSERTIONS
    // THAT COULD ONLY EVER BE SATISFIED BY THEM NO LONGER USE THEM.
    //
    // A test that recomputes an expected position from the same constant the
    // widget uses is SELF-REFERENTIAL — it can catch a change to the constant
    // but never a change to how the constant is APPLIED, which is what BOTH
    // shipped misalignment bugs were. So the two cases in this group whose
    // subject is card-vs-ruler REGISTRATION now derive their expectations from
    // the rendered gridline ladder (`_renderedHourBand`):
    //
    //   * "INVARIANT: every booking >= 15 minutes lands its card bottom
    //     exactly on its end-time line" — the widest case, seven durations.
    //   * "NO ACCUMULATED DRIFT" — the direct regression for the twice-shipped
    //     `_kMinInterCardGap` accumulator.
    //
    // The remaining literals are DELIBERATE and are kept:
    //
    //   * The per-duration height cases below (30/45/60/90/15 min) are ABSOLUTE
    //     pins on the chosen vertical scale. `kSlotH`/`kHourH` are mirrored
    //     literals here, NOT imports of the widget's private constants, so a
    //     unilateral change to `_kHourH` turns them red — which is the point.
    //     They document the scale; the two measured cases above and
    //     `bookings_timeline_grid_gridline_registration_test.dart` prove the
    //     application.
    //   * "LOCKSTEP" in the gridline group below compares the RENDERED ruler
    //     band to the RENDERED gridline band, so a one-sided edit to either
    //     `_kHourH` fails there whatever these say.
    //
    // See that file's header for why the vertical scale came back DOWN to 120
    // (the micro card layout removed the 56dp legibility floor that was forcing
    // it up to 168) and why the card floor is
    // `MasterBookingCard.microLayoutNaturalHeight`, decoupled from the slot,
    // so short bookings land their card bottom on the end line.
    const double kSlotH = 60;
    const double kHourH = 120;

    final DateTime day = _day;

    testWidgets('a 30-minute booking renders at exactly one slot (60dp)', (
      WidgetTester tester,
    ) async {
      final Booking b = _booking(
        id: 'dur-30',
        startAtUtc: _kyivAtUtc(9),
        durationMinutes: 30,
      );
      await tester.pumpApp(
        BookingsTimelineGrid(
          bookings: <Booking>[b],
          day: day,
          onBookingTap: (_) {},
        ),
      );
      await tester.pump();

      expect(_cardRect(tester, 'dur-30').height, closeTo(kSlotH, 0.5));
    });

    testWidgets(
      'a 60-minute booking renders at EXACTLY two slots (120dp) — its card '
      'bottom lands precisely on its end-time line',
      (WidgetTester tester) async {
        final Booking b = _booking(
          id: 'dur-60',
          startAtUtc: _kyivAtUtc(9),
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

        final double height = _cardRect(tester, 'dur-60').height;

        // ADDENDUM 8: a 60-minute booking's proportional height is
        // `60/60 * 120 = 120dp`, which clears the adaptive FULL layout's own
        // 117dp natural content by 3dp — so the duration-derived height still
        // wins outright and the card lands EXACTLY on its end-time line
        // (kSlotH * 2 = 120). 60 minutes is the break-even for the full
        // layout at this scale: that 3dp of headroom is exactly why `_kHourH`
        // must not drop below 120 without moving `fullLayoutMinHeight` too.
        expect(height, closeTo(kSlotH * 2, 0.5));
      },
    );

    testWidgets(
      'a 90-minute booking renders at exactly three slots (180dp) — three '
      'times the 30-minute card\'s height, proving the height tracks '
      'duration proportionally rather than rounding up to a fixed unit',
      (WidgetTester tester) async {
        final Booking b = _booking(
          id: 'dur-90',
          startAtUtc: _kyivAtUtc(9),
          durationMinutes: 90,
        );
        await tester.pumpApp(
          BookingsTimelineGrid(
            bookings: <Booking>[b],
            day: day,
            onBookingTap: (_) {},
          ),
        );
        await tester.pump();

        final double height = _cardRect(tester, 'dur-90').height;
        expect(height, closeTo(kSlotH * 3, 0.5));
      },
    );

    testWidgets(
      'a 45-minute booking renders at 1.5 slots (90dp) — not rounded up to '
      'a whole slot',
      (WidgetTester tester) async {
        final Booking b = _booking(
          id: 'dur-45',
          startAtUtc: _kyivAtUtc(9),
          durationMinutes: 45,
        );
        await tester.pumpApp(
          BookingsTimelineGrid(
            bookings: <Booking>[b],
            day: day,
            onBookingTap: (_) {},
          ),
        );
        await tester.pump();

        expect(_cardRect(tester, 'dur-45').height, closeTo(kSlotH * 1.5, 0.5));
      },
    );

    testWidgets('a booking shorter than the break-even still renders, '
        'un-clipped, at the MICRO layout\'s 28dp legibility floor rather than '
        'a duration-scaled sliver', (WidgetTester tester) async {
      final Booking b = _booking(
        id: 'dur-10',
        startAtUtc: _kyivAtUtc(9),
        durationMinutes: 10,
      );
      await tester.pumpApp(
        BookingsTimelineGrid(
          bookings: <Booking>[b],
          day: day,
          onBookingTap: (_) {},
        ),
      );
      await tester.pump();

      // ADDENDUM 8: sub-break-even bookings floor at the MICRO layout's
      // natural height (`MasterBookingCard.microLayoutNaturalHeight`, 28dp),
      // NOT a duration-scaled 20dp sliver (10/60*120) which no layout can
      // render, NOT the old 56dp compact natural (the micro row is what let
      // the floor come down), and NOT the 60dp gridline slot (the floor is
      // decoupled from the slot). This is the documented residual overrun
      // below the 14.0-minute break-even — irreducible because a card cannot
      // render below its own natural height and services can be 1 minute long.
      expect(
        _cardRect(tester, 'dur-10').height,
        closeTo(MasterBookingCard.microLayoutNaturalHeight, 0.5),
      );

      // No clipping/forced-height mechanism directly on the card — mirrors
      // the "short bookings render their full card" group above (which
      // checks `Positioned`; `OverflowBox` is the OTHER half of the R2
      // bug's retired pair). Deliberately NOT asserting `ClipRect`
      // findsNothing here: unlike `master_booking_card_test.dart`'s
      // isolated-card R2 pin, this test pumps the full
      // `BookingsTimelineGrid`, whose own vertical+horizontal
      // `SingleChildScrollView`s legitimately contribute `ClipRect`
      // ancestors (default `Clip.hardEdge` scroll-viewport clipping) that
      // have nothing to do with the retired per-card OverflowBox+ClipRect
      // crop.
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey<String>('timeline-card-dur-10')),
          matching: find.byType(OverflowBox),
        ),
        findsNothing,
      );
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey<String>('timeline-card-dur-10')),
          matching: find.byType(Positioned),
        ),
        findsNothing,
      );
      expect(find.text(b.serviceName), findsOneWidget);
      // The CLIENT NAME is deliberately absent from the VISUAL: a 28dp box
      // selects `MasterBookingCard`'s MICRO layout, which renders
      // service · time · dot only. It is still announced, because
      // `masterBookingCardSemantics` («{client}, {service}») has ALWAYS carried
      // it for all three layouts — the micro pass did not "move the client
      // into Semantics" and did not touch that line; the only thing the micro
      // branch relocated is the PRICE, to `Semantics(value:)`. (Both are
      // asserted by `master_booking_card_test.dart`.) Asserting the name on
      // screen here would be asserting the pre-ADDENDUM-8 shape.
      expect(find.text(b.clientName!), findsNothing);
    });

    testWidgets(
      'a 15-minute booking renders at EXACTLY 30dp — the shortest slot any '
      'real service catalogue uses, comfortably above the 14.0-minute '
      'break-even, so the proportional height clears the micro floor and the '
      'card bottom lands on its end-time line',
      (WidgetTester tester) async {
        final Booking b = _booking(
          id: 'dur-20',
          startAtUtc: _kyivAtUtc(9),
          durationMinutes: 15,
        );
        await tester.pumpApp(
          BookingsTimelineGrid(
            bookings: <Booking>[b],
            day: day,
            onBookingTap: (_) {},
          ),
        );
        await tester.pump();

        // 15/60 * 120 = 30, clear of `microLayoutNaturalHeight` (28) — the
        // proportional height wins over the floor, so the card bottom lands
        // precisely on its end-time line with no residual. (The exact
        // break-even is 14.0 minutes, and 14 — not 15 — is the shortest whole
        // minute at or past it since the micro natural came down to 28; that
        // boundary has its OWN case directly below. 15 is kept because it is
        // the shortest slot any real service catalogue uses.)
        expect(
          _cardRect(tester, 'dur-20').height,
          closeTo(kHourH * 15 / 60, 0.5),
        );
      },
    );

    // THE BREAK-EVEN ITSELF, at the duration it actually falls on.
    // ---------------------------------------------------------------------
    // The break-even is `microLayoutNaturalHeight / kHourH * 60` — it MOVED
    // from 14.5 to 14.0 minutes when the ONE-TIME-STYLE pass (2026-07-24)
    // took the micro natural from 29dp to 28dp. The cases above and below
    // this one sweep 15 and up (proportional wins) and 10 and down (the floor
    // wins); NEITHER touches the boundary the pass created, so until this
    // case existed the whole geometric consequence of the type change was
    // pinned only one dp away from where it actually bites.
    //
    // 14 is the discriminating minute, and it discriminates in BOTH
    // directions:
    //   * at the current 28dp natural, 14/60 × 120 = 28.0 == the floor, so a
    //     14-minute booking is the SHORTEST duration that lands exactly on
    //     its own end-time line with zero residual overrun;
    //   * at the outgoing 29dp natural it was BELOW the break-even, floored
    //     to 29, and overran its line by 1dp.
    // So this case fails if the natural ever drifts back up — including via
    // the `height: 1.2` that `VelvetText.masterCardTime` deliberately leaves
    // out of the typography-equality group, which is a layout knob whose
    // only guard is geometry like this.
    testWidgets(
      'the NEW break-even is 14.0 minutes: a 14-minute booking lands its card '
      'bottom EXACTLY on its end-time line (zero residual), while a '
      '13-minute one is the longest booking the micro floor still inflates',
      (WidgetTester tester) async {
        final Booking atBreakEven = _booking(
          id: 'dur-14',
          startAtUtc: _kyivAtUtc(8),
          durationMinutes: 14,
        );
        final Booking belowBreakEven = _booking(
          id: 'dur-13',
          startAtUtc: _kyivAtUtc(9),
          durationMinutes: 13,
        );
        await tester.pumpApp(
          BookingsTimelineGrid(
            bookings: <Booking>[atBreakEven, belowBreakEven],
            day: day,
            onBookingTap: (_) {},
          ),
        );
        await tester.pump();

        // Ground truth off the RENDERED ladder, like the sweep below — the
        // point is the RELATIONSHIP «14 minutes == its own wall-clock band»,
        // not a restatement of `kHourH`.
        final double hourBand = _renderedHourBand(tester);

        // Tolerance is deliberately tighter than 1dp: the entire content of
        // this assertion is that the card does NOT sit one dp above its band
        // the way it did at the 29dp natural.
        expect(
          _cardRect(tester, 'dur-14').height,
          closeTo(hourBand * 14 / 60, 0.5),
          reason:
              'a 14-minute booking must land exactly on its end-time line. '
              'If it renders taller, the MICRO natural has drifted back above '
              '28dp and the break-even is no longer 14.0 — re-measure '
              'MasterBookingCard.microLayoutNaturalHeight and update every '
              'doc that quotes the break-even.',
        );
        // Stated as the floor rather than as a number, so the pairing (not
        // the literal 28) is what is pinned.
        expect(
          _cardRect(tester, 'dur-14').height,
          closeTo(MasterBookingCard.microLayoutNaturalHeight, 0.5),
          reason:
              'at the break-even the proportional band and the micro floor '
              'COINCIDE — that is what makes 14.0 the break-even',
        );

        // One minute below, the floor genuinely binds again: the card is
        // taller than its own band and shorter than the next one.
        final double thirteenHeight = _cardRect(tester, 'dur-13').height;
        expect(
          thirteenHeight,
          closeTo(MasterBookingCard.microLayoutNaturalHeight, 0.5),
          reason:
              'below the break-even the card floors at the MICRO natural, '
              'un-clipped — it can never render at its 26dp band',
        );
        expect(
          thirteenHeight,
          greaterThan(hourBand * 13 / 60),
          reason:
              'the residual overrun below the break-even is real and must '
              'stay visible to this test — if it vanished, the floor stopped '
              'binding and short cards would render as clipped slivers',
        );
      },
    );

    testWidgets(
      'INVARIANT: every booking >= 15 minutes lands its card bottom exactly '
      'on its end-time line — its height is duration/60 of ONE RENDERED HOUR '
      'BAND, so no floor or full-layout inflation pushes any legible duration '
      'past its line, at whatever dp-per-hour the ruler is actually drawn at',
      (WidgetTester tester) async {
        // 15 is now included: ADDENDUM 8 dropped the break-even from 20
        // minutes to 14.0, so a quarter-hour slot is exact rather than
        // inflated. 20/25 stay in the sweep — they are compact-layout
        // durations at this scale and the floor must not touch them either.
        const List<int> durations = <int>[15, 20, 25, 30, 45, 60, 90];
        // Staggered by 30min from 08:00 so every card stays in the top,
        // never-culled band. Height is independent of vertical position and
        // of any spacer, so overlap between longer cards is harmless to this
        // assertion.
        final List<Booking> bookings = <Booking>[
          for (int i = 0; i < durations.length; i++)
            _booking(
              id: 'dur-${durations[i]}',
              startAtUtc: _kyivAtUtc(8, i * 30),
              durationMinutes: durations[i],
            ),
        ];
        await tester.pumpApp(
          BookingsTimelineGrid(
            bookings: bookings,
            day: day,
            onBookingTap: (_) {},
          ),
        );
        await tester.pump();

        // GROUND TRUTH, NOT `kHourH`. The expected height is read off the
        // RENDERED gridline ladder, so this sweep pins the relationship
        // «card height == its own wall-clock band» rather than restating the
        // widget's own constant back at it (see `_renderedHourBand`). A future
        // scale pass needs no edit here and still cannot silently break it.
        final double hourBand = _renderedHourBand(tester);
        for (final int mins in durations) {
          expect(
            _cardRect(tester, 'dur-$mins').height,
            closeTo(hourBand * mins / 60, 1.0),
            reason:
                'a $mins-min card must be $mins/60 of the RENDERED hour band '
                '(${hourBand}dp), i.e. ${hourBand * mins / 60}dp',
          );
        }

        // And the rendered band really is the ADDENDUM 8 scale — pinned once,
        // deliberately, so a scale change is a conscious edit rather than a
        // silent one. (Paired with, not substituted for, the measured
        // assertions above: this line alone could not see a MISAPPLIED scale.)
        expect(hourBand, closeTo(kHourH, 0.5));
      },
    );

    testWidgets(
      'back-to-back bookings of DIFFERENT durations (60min then 90min) tile '
      'EXACTLY — the second card starts where the first ends, zero gap, so no '
      'drift can accumulate — and never intersect',
      (WidgetTester tester) async {
        final Booking first = _booking(
          id: 'tile-60',
          startAtUtc: _kyivAtUtc(9),
          durationMinutes: 60,
        );
        final Booking second = _booking(
          id: 'tile-90',
          startAtUtc: _kyivAtUtc(10), // back-to-back
          durationMinutes: 90,
        );

        await tester.pumpApp(
          BookingsTimelineGrid(
            bookings: <Booking>[first, second],
            day: day,
            onBookingTap: (_) {},
          ),
        );
        await tester.pump();

        final Rect firstRect = _cardRect(tester, 'tile-60');
        final Rect secondRect = _cardRect(tester, 'tile-90');

        expect(firstRect.overlaps(secondRect), isFalse);
        expect(secondRect.top, greaterThanOrEqualTo(firstRect.bottom));

        // THIS ASSERTION WAS INVERTED BY ADDENDUM 8. As shipped it read
        // `closeTo(8, 0.5)` and called the 8dp "the cosmetic minimum gap, no
        // collision-nudge drift". That 8dp WAS the drift: `_kMinInterCardGap`
        // floored a spacer measured from the previous card's bottom, so every
        // back-to-back pair pushed the later card 8dp below its own gridline
        // and the error compounded down the day (six consecutive hour-long
        // bookings ended 40dp — 20 minutes at this scale — late). The test
        // asserted the bug.
        //
        // The correct property is ZERO: the second card's top must sit on the
        // first card's bottom, which (since the first card's height equals its
        // wall-clock footprint) is its own start gridline. Separation is drawn
        // by the two adjacent card borders, not bought with ruler space.
        expect(
          secondRect.top - firstRect.bottom,
          closeTo(0, 0.5),
          reason:
              'a non-zero gap here is added to an ABSOLUTE running position '
              'that never re-registers against the ruler, so it compounds '
              'once per booking. See bookings_timeline_grid.dart ADDENDUM 8.',
        );
      },
    );

    testWidgets(
      'NO ACCUMULATED DRIFT: in a run of six back-to-back hour-long bookings, '
      'card N\'s top lands on its OWN start gridline for every N — the '
      'regression test for the reported «12:00–14:00 looks like 12:10–14:10»',
      (WidgetTester tester) async {
        // Six consecutive 60-minute bookings from 09:00. Under the retired
        // 8dp gap floor these drifted 0/8/16/24/32/40dp; the last card read a
        // full 20 minutes late at this scale. One card is not enough to catch
        // that — the defect is per-STEP, so the fixture has to be a run.
        const int count = 6;
        final List<Booking> bookings = <Booking>[
          for (int i = 0; i < count; i++)
            _booking(
              id: 'run-$i',
              startAtUtc: _kyivAtUtc(9 + i),
              durationMinutes: 60,
            ),
        ];

        await tester.pumpApp(
          BookingsTimelineGrid(
            bookings: bookings,
            day: day,
            onBookingTap: (_) {},
          ),
        );
        await tester.pump();

        // Measured against the FIRST card's own top, and stepped by the hour
        // band the RULER really rendered (`_renderedHourBand`) rather than by
        // `kHourH`. That distinction is the whole point of this test: the
        // retired `_kMinInterCardGap` never touched the constant, it changed
        // how the constant was APPLIED, so an expectation recomputed from the
        // constant is structurally blind to it. Reading the gridlines makes
        // the ruler the ground truth, exactly as
        // `bookings_timeline_grid_gridline_registration_test.dart` does.
        final double hourBand = _renderedHourBand(tester);
        final double origin = _cardRect(tester, 'run-0').top;
        for (int i = 0; i < count; i++) {
          final Rect card = _cardRect(tester, 'run-$i');
          expect(
            card.top - origin,
            closeTo(i * hourBand, 0.5),
            reason:
                'card $i sits ${card.top - origin}dp below the first card but '
                'its booking starts exactly $i hour(s) later, i.e. '
                '${i * hourBand}dp of RENDERED ruler. A residual that GROWS '
                'with i is the additive inter-card gap coming back.',
          );
        }
      },
    );
  });

  group('ADDENDUM 7 — a card\'s BOTTOM edge lands on its end-time gridline', () {
    // The user's complaint was a card that CROSSES its own end-time line
    // («ending at 14:00 rendered its card bottom down to ~14:10»). The
    // proportional-height tests above pin the card's HEIGHT
    // (`duration/60 * 120`), which is necessary but NOT sufficient: a card of
    // the exact right height can still cross its line if it is positioned
    // wrong. The strongest guard is to tie the card's rendered BOTTOM Y to the
    // rendered Y of the `Positioned` gridline for its `endAt`, so the card
    // provably cannot end anywhere but on its own line. Added by mobile-qa
    // (2026-07-24) — the proportional-height suite as shipped never asserted
    // this coincidence.

    /// The HOUR gridlines only — half-hour lines use `_halfHourLineColor`
    /// (`BrandColors.faint` at alpha 0.4), so filtering on the full-opacity
    /// `BrandColors.faint` `ColoredBox` yields exactly the on-the-hour lines.
    /// `_hasCardAncestor` excludes the card's own same-coloured hairline
    /// divider (see the R4 group). Sorted ascending by rendered top.
    List<Rect> hourGridlinesAscending(WidgetTester tester) {
      final Iterable<Element> elements = find
          .byWidgetPredicate(
            (Widget w) => w is ColoredBox && w.color == BrandColors.faint,
          )
          .evaluate();
      return elements.where((Element e) => !_hasCardAncestor(e)).map((
        Element e,
      ) {
        final RenderBox box = e.renderObject! as RenderBox;
        return box.localToGlobal(Offset.zero) & box.size;
      }).toList()..sort((Rect a, Rect b) => a.top.compareTo(b.top));
    }

    testWidgets(
      'a time-anchored 20-minute booking (11:40–12:00, after an hour-aligned '
      'first booking with an idle gap) lands its card bottom EXACTLY on the '
      '12:00 gridline — height alone cannot prove this, position must too',
      (WidgetTester tester) async {
        // The FIRST booking is hour-aligned (09:00) so the whole card layer is
        // correctly registered against the ruler; the SECOND has a real idle
        // gap before it. The idle gap is no longer load-bearing — ADDENDUM 8
        // removed the additive `_kMinInterCardGap` floor, so a BACK-TO-BACK
        // pair would land on its line too (the run test in the group above
        // pins exactly that). It is kept because the original fixture's
        // property — an off-hour start reaching its true wall-clock position —
        // is what this case is for. Its end (12:00) is an on-the-hour
        // gridline.
        final Booking first = _booking(
          id: 'anchor-first',
          startAtUtc: _kyivAtUtc(9),
          durationMinutes: 20,
        );
        final Booking probe = _booking(
          id: 'anchor-probe',
          startAtUtc: _kyivAtUtc(11, 40),
          durationMinutes: 20,
        );

        await tester.pumpApp(
          BookingsTimelineGrid(
            bookings: <Booking>[first, probe],
            day: _day,
            onBookingTap: (_) {},
          ),
        );
        await tester.pump();

        final List<Rect> hourLines = hourGridlinesAscending(tester);
        // firstHour 9 → lastHour 12: gridlines 09:00, 10:00, 11:00, 12:00.
        expect(
          hourLines.length,
          4,
          reason: 'expected hour gridlines at 09:00, 10:00, 11:00, 12:00',
        );
        final Rect endGridline = hourLines.last; // 12:00
        final Rect probeCard = _cardRect(tester, 'anchor-probe');

        expect(
          probeCard.bottom,
          closeTo(endGridline.top, 1.0),
          reason:
              'the 11:40–12:00 card bottom (${probeCard.bottom}) must land on '
              'the 12:00 gridline (${endGridline.top}) — a card that ends '
              'anywhere but on its own line is the exact overrun the user '
              'reported',
        );
      },
    );

    testWidgets(
      'a single OFF-HOUR-anchored booking (13:40–14:00) lands its card bottom '
      'on the 14:00 gridline — regression for the day\'s first booking not '
      'starting on a whole hour',
      (WidgetTester tester) async {
        // The literal witness from the user's example. This is the case the
        // proportional-height suite never exercised: EVERY fixture there
        // starts the day on a whole hour (or half hour), so the card layer
        // happens to register with the ruler. A real master's first
        // appointment is routinely at :15/:30/:40 — and then the card layer is
        // anchored to `firstMinute` while the ruler/gridlines are anchored to
        // the floored `firstHour`, shifting every card up by
        // `(firstMinute mod 60)` minutes. See mobile-qa finding [HIGH].
        final Booking b = _booking(
          id: 'offhour',
          startAtUtc: _kyivAtUtc(13, 40),
          durationMinutes: 20,
        );

        await tester.pumpApp(
          BookingsTimelineGrid(
            bookings: <Booking>[b],
            day: _day,
            onBookingTap: (_) {},
          ),
        );
        await tester.pump();

        final List<Rect> hourLines = hourGridlinesAscending(tester);
        // firstHour 13 → lastHour 15: gridlines 13:00, 14:00, 15:00. The
        // booking ends at 14:00, the SECOND hour line.
        expect(hourLines.length, greaterThanOrEqualTo(2));
        final Rect endGridline = hourLines[1]; // 14:00
        final Rect card = _cardRect(tester, 'offhour');

        expect(
          card.bottom,
          closeTo(endGridline.top, 1.0),
          reason:
              'the 13:40–14:00 card bottom (${card.bottom}) must land on the '
              '14:00 gridline (${endGridline.top}). If these differ by '
              '(firstMinute mod 60)/60 * 120 dp, the card layer is anchored to '
              'firstMinute while the ruler is anchored to the floored '
              'firstHour — every card is drawn too high and no card lands on '
              'its end line. Fix: anchor cards to firstHour*60, not '
              'firstMinute (BookingsTimelineGrid._recomputeLayoutModel).',
        );
      },
    );

    testWidgets(
      'LOCKSTEP: the ruler\'s rendered hour-band height equals the grid\'s '
      'gridline hour-band height — the two _kHourH constants cannot desync',
      (WidgetTester tester) async {
        // The debugger flagged ruler/grid _kHourH desync as the failure mode
        // if the two private constants ever diverge. This compares the two
        // RENDERED bands to EACH OTHER (not to a literal), so a coordinated
        // rename or a one-sided edit both trip it.
        final Booking b = _booking(
          id: 'lockstep',
          startAtUtc: _kyivAtUtc(9),
          durationMinutes: 120, // spans 09:00–11:00 → three hour lines
        );

        await tester.pumpApp(
          BookingsTimelineGrid(
            bookings: <Booking>[b],
            day: _day,
            onBookingTap: (_) {},
          ),
        );
        await tester.pump();

        Rect rulerLabel(String t) => tester.getRect(
          find.descendant(
            of: find.byType(TimelineHourRuler),
            matching: find.text(t),
          ),
        );
        final double rulerBand =
            rulerLabel('10:00').top - rulerLabel('09:00').top;

        final List<Rect> hourLines = hourGridlinesAscending(tester);
        expect(hourLines.length, greaterThanOrEqualTo(2));
        final double gridBand = hourLines[1].top - hourLines[0].top;

        expect(
          gridBand,
          closeTo(rulerBand, 0.01),
          reason:
              'the ruler laid one hour out at ${rulerBand}dp but the grid '
              'gridlines at ${gridBand}dp — TimelineHourRuler._kHourH and '
              'BookingsTimelineGrid._kHourH have desynced; the ruler labels '
              'and the lane hairlines no longer line up',
        );
        // And both really are the 120dp ADDENDUM 8 value.
        expect(rulerBand, closeTo(120, 0.5));
      },
    );
  });

  group('ADDENDUM 3 regression — narrow-device card width clamp', () {
    // Real-device report: on a 360dp-wide Android phone (the common
    // baseline) the leading timeline card clipped 6dp off its right edge
    // and the day was silently forced into horizontal scroll — no
    // RenderFlex overflow to catch it, because the outer
    // `SingleChildScrollView` just absorbs the extra width instead of
    // throwing. `installOverflowGuard()` (wired into `pumpApp`) and the
    // existing 375dp `master_bookings_screen_test.dart` viewport test both
    // stay green through this bug for the exact same reason — neither
    // asserts a card's actual rendered WIDTH. See
    // `bookings_timeline_grid.dart`'s "ADDENDUM 3".
    //
    // ARITHMETIC (mirrors the real screen, `bookings_discovery_view.dart`,
    // which wraps `BookingsTimelineGrid` in
    // `EdgeInsets.fromLTRB(VelvetSpacing.lg, 0, VelvetSpacing.lg,
    // VelvetSpacing.xxl)`) — this harness reproduces that horizontal
    // padding rather than pumping the raw grid at 360dp directly, because
    // the padding is part of what starves the lane area down to 266dp;
    // skipping it would understate the bug by 48dp:
    //   360 (device)  − 24 − 24 (VelvetSpacing.lg screen padding, L/R)
    //     = 312 (width available to BookingsTimelineGrid.build's own Row)
    //   312 − 42 (TimelineHourRuler._kRulerWidth)
    //       − 4  (VelvetSpacing.xs ruler↔grid gap)
    //     = 266 (the lane area's real LayoutBuilder constraints.maxWidth)
    const double kDeviceWidth = 360;
    const double kAvailableCardArea = 266; // 360 - 94, see file header
    const double kFixedCardW = 272; // BookingsTimelineGrid._kCardW

    final DateTime day = _day;

    Widget screenShapedGrid(List<Booking> bookings) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
      child: BookingsTimelineGrid(
        bookings: bookings,
        day: day,
        onBookingTap: (_) {},
      ),
    );

    testWidgets(
      'single-lane 360dp device: the leading card never renders wider '
      'than the available lane area (was a fixed 272dp, clipped 6dp past '
      'the real 266dp)',
      (WidgetTester tester) async {
        final Booking solo = _booking(
          id: 'narrow-solo',
          startAtUtc: _kyivAtUtc(9),
          durationMinutes: 60,
        );

        await tester.pumpApp(
          screenShapedGrid(<Booking>[solo]),
          width: kDeviceWidth,
        );
        await tester.pump();

        final Rect cardRect = _cardRect(tester, 'narrow-solo');

        // THE ASSERTION THAT FAILS ON THE OLD FIXED-WIDTH CODE: pre-fix,
        // `cardWidth` was the raw `_kCardW` constant (272) regardless of
        // `constraints.maxWidth`, so `cardRect.width` would render ~272
        // here — 6dp WIDER than the 266dp actually available. This bound
        // goes red against the un-clamped code (272 > 266.5).
        expect(
          cardRect.width,
          lessThanOrEqualTo(kAvailableCardArea + 0.5),
          reason:
              'the card rendered wider than the lane area actually has '
              'room for — this is the narrow-device clip regression',
        );
        // Positive pin, not just an upper bound: the clamp must use ALL
        // the room it has (never shrink further than necessary), and it
        // must NOT still be the raw fixed constant.
        expect(cardRect.width, closeTo(kAvailableCardArea, 0.5));
        expect(cardRect.width, isNot(closeTo(kFixedCardW, 0.5)));

        // The real symptom, restated in device coordinates: the card's
        // right edge must land inside the device viewport, not past it.
        expect(cardRect.right, lessThanOrEqualTo(kDeviceWidth));
      },
    );

    testWidgets(
      'multi-lane 360dp device (2 overlapping bookings): both lanes clamp '
      'to the same available width — uniform, not just lane 0 — and the '
      'grid still scrolls horizontally to reach lane 2',
      (WidgetTester tester) async {
        final Booking laneA = _booking(
          id: 'narrow-lane-a',
          startAtUtc: _kyivAtUtc(9),
          durationMinutes: 60,
        );
        final Booking laneB = _booking(
          id: 'narrow-lane-b',
          startAtUtc: _kyivAtUtc(9, 30), // overlaps laneA
          durationMinutes: 60,
        );

        await tester.pumpApp(
          screenShapedGrid(<Booking>[laneA, laneB]),
          width: kDeviceWidth,
        );
        await tester.pump();

        final Rect rectA = _cardRect(tester, 'narrow-lane-a');
        final Rect rectB = _cardRect(tester, 'narrow-lane-b');

        // Uniform clamp — pins the file header's "THE CLAMP IS
        // UNCONDITIONAL" decision: EVERY lane clamps to the same
        // effectiveCardW, not only lane 0. A future "only clamp when
        // lanesCount <= 1" regression would leave rectA at 266 but
        // rectB back at 272, tripping this.
        expect(rectA.width, closeTo(kAvailableCardArea, 0.5));
        expect(rectB.width, closeTo(kAvailableCardArea, 0.5));
        expect(rectA.width, closeTo(rectB.width, 0.01));

        // The LEADING lane (lane 0, visible without any horizontal
        // scroll) must never clip past the device viewport, exactly as
        // the single-lane case above.
        expect(rectA.left, lessThan(rectB.left));
        expect(rectA.right, lessThanOrEqualTo(kDeviceWidth));

        // Pin the OTHER half of the deliberate decision: multi-lane days
        // are still expected to need horizontal scroll to reach lane 2+.
        // Two 266dp lanes plus the inter-lane gap need MORE room than a
        // single lane area has, so the grid's real content width must
        // exceed what's available — a future "fix" that also shrinks
        // lane 2+ to avoid scrolling (e.g. dividing the available width
        // across all lanes instead of clamping each to the same
        // ceiling) would collapse this apart and must not silently pass.
        final double gridContentWidth = tester
            .getSize(find.byKey(const ValueKey<String>('timeline-lane-stack')))
            .width;
        expect(gridContentWidth, greaterThan(kAvailableCardArea));
      },
    );

    testWidgets(
      'wide viewport (default test surface): the card still renders at '
      'the full 272dp ceiling — the clamp never shrinks a card that '
      'already fits',
      (WidgetTester tester) async {
        final Booking wide = _booking(
          id: 'wide-solo',
          startAtUtc: _kyivAtUtc(9),
          durationMinutes: 60,
        );

        await tester.pumpApp(
          BookingsTimelineGrid(
            bookings: <Booking>[wide],
            day: day,
            onBookingTap: (_) {},
          ),
        );
        await tester.pump();

        expect(_cardRect(tester, 'wide-solo').width, closeTo(kFixedCardW, 0.5));
      },
    );
  });

  // ===========================================================================
  // ADDENDUM 4 — VIEWPORT CULLING (mobile-qa, 2026-07-22)
  // ===========================================================================
  //
  // The culling pass landed with NO test of its own, and its two load-bearing
  // claims are both silent-failure shaped:
  //
  //   1. SIZE FIDELITY. A culled card is replaced by a bare
  //      `SizedBox(width: cardWidth, height: cardMinHeight)`. If that box is
  //      not the EXACT box the real card would have occupied, every card BELOW
  //      it shifts — including visible ones — and the day's layout silently
  //      reflows as you scroll. Nothing throws.
  //   2. THE SLACK/HYSTERESIS ARITHMETIC. The window ends at `offset + 1.5V`
  //      and is only re-anchored once the offset has drifted `V / 4`
  //      (ADDENDUM 9 — it was `+2V` / `V / 2` until the vertical scale came
  //      down to 120dp/hour and the same pixel window started covering 1.4x
  //      more of the DAY). The guaranteed margin is the difference,
  //      `0.25V`. If either number is shaved further, a card that is genuinely
  //      ON SCREEN gets replaced by a blank box — the master's booking just is
  //      not there. Again, nothing throws; the widget tree is structurally
  //      identical either way.
  //
  // AMENDED BY ADDENDUM 6 (mobile-perf MEDIUM, 2026-07-22). Claim 1 above is
  // no longer load-bearing and the text-scale gate it forced is GONE. Culling
  // now happens only BELOW the visible window, never above it, at EVERY text
  // scale — so an imperfect placeholder can only displace content that is
  // itself off-screen and further down, and the invariant asserted here is
  // now:
  //
  //   No card at or above the visible band is ever replaced by a
  //   placeholder, at any text scale. Every card's offset within the timeline
  //   content is therefore independent of the scroll offset for the whole
  //   range that has ever been rendered.
  //
  // The two tests below that used to pin "the placeholder is size-exact" and
  // "no card moves" still pin exactly that at scale 1.0 (`occupiedHeightFor`
  // is kept and is still exact there — see ADDENDUM 6's "kept, deliberately"
  // paragraph). What CHANGED is the last test in this group: it used to
  // assert culling switches ITSELF OFF above 1.0, which was the defect
  // ADDENDUM 6 fixed — that behaviour left ~1.15/1.3 users on the original
  // ~200-layer grid for their whole session. It now asserts the opposite:
  // culling engages at 1.3 too, and still never touches anything at or above
  // the visible band.
  group('ADDENDUM 4 — viewport culling', () {
    // The default `flutter_test` surface. `_windowViewport` is seeded from
    // `MediaQuery.sizeOf(context).height` before the scroll controller has
    // metrics, so this IS the viewport the initial window is sized from.
    const double kViewportH = 600;

    Finder culledPlaceholder(String id) =>
        find.byKey(ValueKey<String>('timeline-card-culled-$id'));

    Finder realCard(String id) =>
        find.byKey(ValueKey<String>('timeline-card-$id'));

    /// The grid's OWN vertical scroll position — driven directly rather than
    /// through `tester.drag`, whose fling momentum would make the resulting
    /// offset (and therefore which window is anchored) non-deterministic.
    ScrollableState verticalScrollable(WidgetTester tester) =>
        tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byType(BookingsTimelineGrid),
                matching: find.byType(Scrollable),
              )
              .first,
        );

    Future<void> scrollTo(WidgetTester tester, double offset) async {
      final ScrollableState scrollable = verticalScrollable(tester);
      scrollable.position.jumpTo(
        offset.clamp(0.0, scrollable.position.maxScrollExtent),
      );
      await tester.pump();
    }

    testWidgets(
      'a card more than a full viewport below the visible band renders as a '
      'placeholder, and materialises once scrolled to',
      (WidgetTester tester) async {
        // 09:00 and 21:00 Kyiv: 12 wall-clock hours apart, i.e. 1440dp of
        // ruler at 120dp/hour (ADDENDUM 8). The initial window's bottom edge
        // is `0 + 1.5 × 600 − 7 = 893` (ADDENDUM 9), so the late card starts
        // well below it. The dedicated boundary test below pins the window's
        // edge tightly; this one only needs it to be somewhere above 1440.
        final Booking early = _booking(
          id: 'cull-early',
          startAtUtc: _kyivAtUtc(9),
          durationMinutes: 60,
        );
        final Booking late = _booking(
          id: 'cull-late',
          startAtUtc: _kyivAtUtc(21),
          durationMinutes: 60,
        );

        await tester.pumpApp(
          BookingsTimelineGrid(
            bookings: <Booking>[early, late],
            day: _day,
            onBookingTap: (_) {},
          ),
        );
        await tester.pump();

        // The on-screen card is real; the far-off one is not built at all.
        expect(realCard('cull-early'), findsOneWidget);
        expect(
          realCard('cull-late'),
          findsNothing,
          reason:
              'the far-off card was fully materialised — culling did not '
              'engage, which is the whole ~200-layer cost ADDENDUM 4 exists '
              'to remove',
        );
        expect(culledPlaceholder('cull-late'), findsOneWidget);

        final Size placeholderSize = tester.getSize(
          culledPlaceholder('cull-late'),
        );

        // Scroll the late card into the band.
        await scrollTo(tester, double.infinity);
        await tester.pumpAndSettle();

        expect(
          realCard('cull-late'),
          findsOneWidget,
          reason:
              'the card never materialised after scrolling to it — the '
              'culling window is not tracking the scroll offset',
        );
        expect(culledPlaceholder('cull-late'), findsNothing);

        // The width half of size fidelity — the height half is its own test
        // below (it is currently RED; see that test's header).
        final Size realSize = tester.getSize(realCard('cull-late'));
        expect(
          placeholderSize.width,
          closeTo(realSize.width, 0.5),
          reason:
              'a lane whose cards were all replaced by height-only boxes '
              'would collapse to zero width and drag every lane to its '
              'right sideways',
        );
      },
    );

    // ─────────────────────────────────────────────────────────────────────
    // ADDENDUM 9 — THE WINDOW'S SIZE ITSELF, PINNED IN BOTH DIRECTIONS.
    //
    // The test above only proves culling engages SOMEWHERE below the viewport;
    // it passes for a `2V` window, a `1.5V` window and a `10V` window alike.
    // That is how the window silently stopped doing its job: it is a PIXEL
    // quantity, ADDENDUM 8 cut `_kHourH` 168 -> 120, and the same 2V of pixels
    // quietly started covering 1.4x more of the DAY — first-paint culling on an
    // ordinary 09:00–19:00 shift fell from ~35% of the day to ~10% with no test
    // going red.
    //
    // So this case pins the edge from BOTH sides at once:
    //   * TOO NARROW is caught by the `<= windowBottom` half (a card inside the
    //     window must be real — shave the slack and an on-screen card becomes a
    //     blank box).
    //   * TOO WIDE is caught by the `> windowBottom` half plus the fixture
    //     guard, which requires at least one probe in the `(1.5V, 2V]` strip —
    //     exactly the band that regressing to ADDENDUM 4's window would
    //     re-materialise.
    //
    // The boundary is derived from the RENDERED viewport and the RENDERED hour
    // band, never from a hard-coded dp, so a future scale pass moves the
    // expectation with it instead of falsifying this file.
    // ─────────────────────────────────────────────────────────────────────
    testWidgets(
      'the culling band ends at scrollOffset + 1.5 viewports: every card '
      'inside it is real and every card past it is a placeholder — including '
      'the strip that ADDENDUM 4\'s wider 2V window would have materialised',
      (WidgetTester tester) async {
        // A long day, so probes land on both sides of the edge AND inside the
        // 1.5V–2V discriminating strip. 09:00–21:00 at 120dp/hour is 1440dp of
        // ruler against a 600dp viewport: the edge sits at 893dp (card 8 of 13
        // is the first past it) and the strip 893–1193 holds cards 8 and 9.
        final List<Booking> day = <Booking>[
          for (int i = 0; i < 13; i++)
            _booking(
              id: 'window-$i',
              startAtUtc: _kyivAtUtc(9 + i),
              durationMinutes: 60,
            ),
        ];

        await tester.pumpApp(
          BookingsTimelineGrid(bookings: day, day: _day, onBookingTap: (_) {}),
        );
        await tester.pump();

        final double viewport = verticalScrollable(
          tester,
        ).position.viewportDimension;
        expect(
          viewport,
          greaterThan(0),
          reason: 'fixture guard: the grid must have a real viewport',
        );

        // The band's bottom edge in the lane `Column`s' own coordinates, which
        // is exactly the space `timeline-lane-stack` establishes (the
        // `labelCenteringNudge` padding sits OUTSIDE that `Stack`, so it is
        // already netted out of every offset measured against it).
        const double kSlack = 0.5;
        final double windowBottom =
            (1 + kSlack) * viewport - TimelineHourRuler.labelCenteringNudge;
        final double oldWindowBottom =
            2.0 * viewport - TimelineHourRuler.labelCenteringNudge;

        double contentOffsetOf(String id) {
          final double gridTop = tester
              .getTopLeft(
                find.byKey(const ValueKey<String>('timeline-lane-stack')),
              )
              .dy;
          final Finder real = realCard(id);
          final Finder target = real.evaluate().isNotEmpty
              ? real
              : culledPlaceholder(id);
          return tester.getTopLeft(target).dy - gridTop;
        }

        int inDiscriminatingStrip = 0;
        for (int i = 0; i < day.length; i++) {
          final String id = 'window-$i';
          final double top = contentOffsetOf(id);
          final bool isCulled = culledPlaceholder(id).evaluate().isNotEmpty;

          if (top > windowBottom && top <= oldWindowBottom) {
            inDiscriminatingStrip++;
          }

          if (top <= windowBottom) {
            expect(
              isCulled,
              isFalse,
              reason:
                  '$id is planned at ${top}dp, INSIDE the culling band '
                  '(0 … ${windowBottom}dp), but was replaced by a '
                  'placeholder. The slack has been shaved below '
                  '$kSlack viewports and the guaranteed on-screen margin '
                  '(slack − the V/4 re-anchor drift) has gone negative — a '
                  'real booking now renders as a blank box.',
            );
          } else {
            expect(
              isCulled,
              isTrue,
              reason:
                  '$id is planned at ${top}dp, PAST the culling band\'s '
                  '${windowBottom}dp edge, but was fully materialised. The '
                  'window is wider than ${1 + kSlack} viewports — if it has '
                  'gone back to 2V, note that the window is a PIXEL quantity '
                  'and `_kHourH` is 120, so 2V now buys ~9.1 hours of the day '
                  'and culling barely engages on a normal working day (the '
                  'ADDENDUM 9 finding).',
            );
          }
        }

        expect(
          inDiscriminatingStrip,
          greaterThanOrEqualTo(1),
          reason:
              'fixture guard: no probe lands between the 1.5V edge and the '
              'old 2V edge, so the assertions above could not tell the two '
              'windows apart and a regression to ADDENDUM 4\'s window would '
              'pass',
        );
      },
    );

    // ─────────────────────────────────────────────────────────────────────
    // ⚠ HISTORICAL — THESE TWO TESTS WERE WRITTEN RED AND ARE NOW GREEN.
    // ADDENDUM 5 fixed the defect described below (`occupiedHeightFor`);
    // ADDENDUM 6 then made it non-load-bearing by culling below the window
    // only. Keep the diagnosis for the next density pass: it is still what
    // goes wrong if `occupiedHeightFor` stops predicting the rendered box.
    //
    // They pin ADDENDUM 4's own stated contract, which the implementation of
    // the day did not meet for the single most common booking length. The
    // addendum argued size fidelity like this:
    //
    //   "a placeholder only preserves layout if the real card would have
    //    rendered at exactly `cardMinHeight`. That holds because
    //    [_cardMinHeightFor]'s floor (one 56dp slot) already exceeds the
    //    card's measured natural height (54dp)"
    //
    // That reasoning is about `MasterBookingCard`'s COMPACT layout only. The
    // card switches to its ADAPTIVE FULL layout once
    // `minHeight >= fullLayoutNaturalHeight` (117dp, `_kFullLayoutMinHeight`),
    // and the full layout's own natural content also measures 117dp.
    //
    // HISTORICAL MOTIVATION (scale 112, pre-ADDENDUM 7): a 60-minute booking's
    // floor was 112dp but its real card rendered at 117dp (full layout), so a
    // naive `minHeight` placeholder was 5dp SHORT, and because `_LaneColumn`
    // is a flex `Column`, every card below a culled one moved UP by 5dp per
    // culled card — sliding cards OUT OF REGISTRATION with the never-culled
    // `Positioned` gridlines, the one relationship this widget exists to
    // maintain (see the file header's "THE RULER IS THE KYIV WALL-CLOCK").
    // That is exactly why the placeholder must reserve `occupiedHeightFor`
    // (which accounts for the layout switch), not the bare `minHeight`.
    //
    // AT THE CURRENT 120dp SCALE (ADDENDUM 8) that specific 5dp gap still
    // does not arise — a 60-minute floor is 120dp >= 117dp, so
    // `occupiedHeightFor` and `minHeight` coincide there — but
    // `occupiedHeightFor` is NO LONGER a no-op the way it was at 168: the
    // grid's card floor is now `microLayoutNaturalHeight` (28dp), so every
    // booking under the 14.0-minute break-even has a floor BELOW its layout's
    // natural and the `max` genuinely binds. It is also the general,
    // scale-independent predictor for any future scale.
    //
    // How it was resolved: ADDENDUM 5 took the first branch — the
    // placeholder reserves `MasterBookingCard.occupiedHeightFor(floor)`, the
    // box the card really occupies, pinned to the pixel by
    // `widgets/master_booking_card_layout_height_test.dart`. ADDENDUM 6 then
    // removed the textScaler gate the second branch would have needed, by
    // never culling above the visible band at all. Do NOT relax these
    // assertions.
    // ─────────────────────────────────────────────────────────────────────

    testWidgets(
      'a culled card\'s placeholder is the EXACT box the real card occupies '
      '(height)',
      (WidgetTester tester) async {
        final Booking early = _booking(
          id: 'exact-early',
          startAtUtc: _kyivAtUtc(9),
          durationMinutes: 60,
        );
        final Booking late = _booking(
          id: 'exact-late',
          startAtUtc: _kyivAtUtc(21),
          durationMinutes: 60,
        );

        await tester.pumpApp(
          BookingsTimelineGrid(
            bookings: <Booking>[early, late],
            day: _day,
            onBookingTap: (_) {},
          ),
        );
        await tester.pump();

        final double placeholderH = tester
            .getSize(culledPlaceholder('exact-late'))
            .height;

        await scrollTo(tester, double.infinity);
        await tester.pumpAndSettle();

        final double realH = tester.getSize(realCard('exact-late')).height;
        expect(
          placeholderH,
          closeTo(realH, 0.5),
          reason:
              'the placeholder reserved ${placeholderH}dp for a card that '
              'really renders at ${realH}dp. Every card below a culled one '
              'shifts by the difference.',
        );
      },
    );

    testWidgets(
      'a card\'s offset WITHIN the timeline content does not depend on the '
      'scroll offset',
      (WidgetTester tester) async {
        // Twelve back-to-back hour-long bookings: a plausible full working
        // day, and the exact duration whose floor and natural height differ.
        final List<Booking> day = <Booking>[
          for (int i = 0; i < 12; i++)
            _booking(
              id: 'reflow-$i',
              startAtUtc: _kyivAtUtc(9 + i),
              durationMinutes: 60,
            ),
        ];

        await tester.pumpApp(
          BookingsTimelineGrid(bookings: day, day: _day, onBookingTap: (_) {}),
        );
        await tester.pump();

        /// A card's top edge measured against the timeline content's own
        /// origin — i.e. where it sits in the DAY, independent of how far
        /// the view is scrolled. Reads the placeholder when the card is
        /// culled, which is the whole point: the placeholder claims to
        /// occupy the same place.
        double contentOffsetOf(String id) {
          final double gridTop = tester
              .getTopLeft(
                find.byKey(const ValueKey<String>('timeline-lane-stack')),
              )
              .dy;
          final Finder real = realCard(id);
          final Finder target = real.evaluate().isNotEmpty
              ? real
              : culledPlaceholder(id);
          return tester.getTopLeft(target).dy - gridTop;
        }

        final Map<String, double> atRest = <String, double>{
          for (int i = 0; i < day.length; i++)
            'reflow-$i': contentOffsetOf('reflow-$i'),
        };

        // Fixture guard: at rest the day's TAIL must actually be substituted,
        // or there is nothing to observe and the test is vacuous. (This used
        // to guard on the HEAD being culled after scrolling to the bottom —
        // ADDENDUM 6 deliberately made that impossible: nothing at or above
        // the visible band is ever culled. The substitution being observed is
        // the same one either way, just measured from the other end.)
        expect(
          culledPlaceholder('reflow-${day.length - 1}'),
          findsOneWidget,
          reason:
              'nothing was culled at the tail of the day at rest — the '
              'assertions below would pass for the wrong reason',
        );

        await scrollTo(tester, double.infinity);
        await tester.pumpAndSettle();

        // ADDENDUM 6's invariant, directly: the head of the day is STILL a
        // real card after scrolling a full day away from it. Culling below
        // the window only is what makes "no visible card can move" true by
        // construction rather than by a measurement table.
        expect(
          realCard('reflow-0'),
          findsOneWidget,
          reason:
              'the head of the day was culled after scrolling to the bottom '
              '— culling has been re-enabled ABOVE the visible band, which '
              'makes placeholder height fidelity load-bearing again at every '
              'text scale (see ADDENDUM 6)',
        );

        for (int i = 0; i < day.length; i++) {
          final String id = 'reflow-$i';
          expect(
            contentOffsetOf(id),
            closeTo(atRest[id]!, 0.5),
            reason:
                '$id moved from ${atRest[id]}dp to ${contentOffsetOf(id)}dp '
                'within the timeline content purely because the view was '
                'scrolled. The hour gridlines did NOT move (they are '
                'Positioned and never culled), so the cards have slid out '
                'of registration with their own hour lines.',
          );
        }
      },
    );

    testWidgets(
      'the slack + hysteresis keep every ON-SCREEN card real: no placeholder '
      'ever intersects the viewport, at any scroll offset',
      (WidgetTester tester) async {
        // A full working day — 12 hourly bookings, ~1456dp of grid against a
        // 600dp viewport, so most of the day is off-screen at any offset and
        // the window is genuinely doing work.
        final List<Booking> bookings = <Booking>[
          for (int i = 0; i < 12; i++)
            _booking(
              id: 'slack-$i',
              startAtUtc: _kyivAtUtc(9 + i),
              durationMinutes: 60,
            ),
        ];

        await tester.pumpApp(
          BookingsTimelineGrid(
            bookings: bookings,
            day: _day,
            onBookingTap: (_) {},
          ),
        );
        await tester.pump();

        void expectNoVisiblePlaceholder(double offset) {
          final Rect viewport = tester.getRect(
            find.byType(BookingsTimelineGrid),
          );
          for (int i = 0; i < bookings.length; i++) {
            final Finder placeholder = culledPlaceholder('slack-$i');
            if (placeholder.evaluate().isEmpty) continue;
            expect(
              tester.getRect(placeholder).overlaps(viewport),
              isFalse,
              reason:
                  'at scroll offset $offset, booking slack-$i was culled '
                  'while still inside the viewport — the window\'s slack '
                  '(half a viewport below the visible band) or its '
                  'quarter-viewport re-anchor threshold has been shaved, and '
                  'a real card is now a blank box on screen',
            );
          }
        }

        // Step in increments SMALLER than the re-anchor threshold
        // (ADDENDUM 9's `viewport / 4` = 150dp; it was `viewport / 2` = 300dp
        // before the window was tightened, so this step had to come down with
        // it), so most steps deliberately do NOT re-anchor the window — which
        // is exactly when the slack has to carry the load on its own. A step
        // at or above the threshold would re-anchor on EVERY iteration and the
        // hysteresis half of this test would go untested.
        const double kStep = 100;
        expect(
          kStep,
          lessThan(kViewportH / 4),
          reason:
              'the sweep must under-step the re-anchor threshold or it only '
              'ever samples a freshly-anchored window',
        );
        final double maxExtent = verticalScrollable(
          tester,
        ).position.maxScrollExtent;
        expect(
          maxExtent,
          greaterThan(kViewportH),
          reason:
              'fixture guard: the day must be taller than the viewport or '
              'nothing is ever off-screen and this test is vacuous',
        );
        for (double offset = 0; offset <= maxExtent; offset += kStep) {
          await scrollTo(tester, offset);
          expectNoVisiblePlaceholder(offset);
        }
        await scrollTo(tester, maxExtent);
        expectNoVisiblePlaceholder(maxExtent);

        // Fixture guard — the whole test is vacuous if nothing was ever
        // culled. Back at the top, the day's tail must be placeholders.
        await scrollTo(tester, 0);
        expect(
          culledPlaceholder('slack-11'),
          findsOneWidget,
          reason:
              'nothing was culled at all, so the assertions above proved '
              'nothing',
        );
      },
    );

    // ─────────────────────────────────────────────────────────────────────
    // ADDENDUM 9 — THE SAME INVARIANT WHERE THE GRID'S VIEWPORT IS NOT THE
    // SCREEN. Every culling test above pumps the grid as the whole `home`, so
    // its scroll viewport IS the surface height and `_windowViewport`'s
    // pre-metrics seed (`MediaQuery.sizeOf(context).height`) happens to be
    // exactly right. On a REAL screen it never is: `MasterBookingsScreen` puts
    // an app bar above the grid and a `VelvetBottomNavBar` below it, so at an
    // iPhone SE-class 375x667 the grid's own viewport is a few hundred dp
    // shorter than the screen the seed reads.
    //
    // That gap is why this case exists, and it is worth its own test for two
    // reasons:
    //
    //   1. THE SEED IS AN OVER-ESTIMATE, SO THE WINDOW SHRINKS ON THE FIRST
    //      SCROLL. Before any scroll the band is sized off the SCREEN
    //      (`1.5 x 600`); after [_onScroll] runs it is sized off the real
    //      viewport (`1.5 x 320`). Cards between the two edges flip from real
    //      to placeholder mid-session. That is safe ONLY because the shrink
    //      happens far below the fold — and "far below the fold" is an
    //      assertion, not a comment, so it is made here.
    //   2. THE MARGIN IS A FRACTION OF THE VIEWPORT, so a window tightened too
    //      far fails PROPORTIONALLY — it strands a visible card as a blank box
    //      at 320dp just as it would at 600dp. Pinning the invariant at a
    //      second, materially different viewport is what stops a future
    //      tightening from being "fine on the test surface" and popping cards
    //      in on a small phone.
    //
    // `master_bookings_screen_test.dart`'s small-viewport case now scrolls to
    // `maxScrollExtent` before asserting its last card is in the tree, exactly
    // because that card is legitimately culled at rest at 375x667. This test is
    // what makes that adaptation safe: it holds the culling contract at a
    // chrome-shrunk viewport so the screen test does not have to.
    // ─────────────────────────────────────────────────────────────────────
    testWidgets(
      'when surrounding chrome shrinks the grid\'s viewport below the screen '
      'height, no placeholder is ever on screen — before OR after the '
      'pre-metrics seed is replaced by the real viewport',
      (WidgetTester tester) async {
        // Materially shorter than the 600dp surface, mirroring what an app bar
        // plus a bottom nav bar leave the grid on a 667dp-tall phone.
        const double kShrunkViewportH = 320;

        final List<Booking> bookings = <Booking>[
          for (int i = 0; i < 12; i++)
            _booking(
              id: 'chrome-$i',
              startAtUtc: _kyivAtUtc(9 + i),
              durationMinutes: 60,
            ),
        ];

        await tester.pumpApp(
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: kShrunkViewportH,
              child: BookingsTimelineGrid(
                bookings: bookings,
                day: _day,
                onBookingTap: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();

        // FIXTURE GUARD: the whole point is that the grid's viewport is NOT
        // the screen height. If a layout change ever let the grid size itself
        // to the surface again, this test would silently become a duplicate of
        // the sweep above.
        final double realViewport = verticalScrollable(
          tester,
        ).position.viewportDimension;
        expect(
          realViewport,
          closeTo(kShrunkViewportH, 1.0),
          reason:
              'fixture guard: the grid must actually be constrained to '
              '${kShrunkViewportH}dp — this test is about the case where the '
              'viewport is smaller than the screen the window seed reads',
        );
        expect(
          realViewport,
          lessThan(kViewportH * 0.75),
          reason:
              'fixture guard: the grid viewport must be MATERIALLY smaller '
              'than the ${kViewportH}dp surface, or the pre-metrics seed and '
              'the real viewport agree and the transition under test never '
              'happens',
        );

        void expectNoVisiblePlaceholder(String phase) {
          final Rect visible = tester.getRect(
            find.byType(BookingsTimelineGrid),
          );
          for (int i = 0; i < bookings.length; i++) {
            final Finder placeholder = culledPlaceholder('chrome-$i');
            if (placeholder.evaluate().isEmpty) continue;
            expect(
              tester.getRect(placeholder).overlaps(visible),
              isFalse,
              reason:
                  '$phase: chrome-$i was culled while still inside the grid\'s '
                  '${realViewport}dp viewport. The window\'s slack '
                  '(half a viewport below the visible band) or its '
                  'quarter-viewport re-anchor threshold has been shaved '
                  'until the guaranteed margin went negative, and a real '
                  'booking is now a blank box on screen — the POP-IN this '
                  'window is only allowed to avoid, not cause.',
            );
          }
        }

        // Phase 1 — the seeded window, before [_onScroll] has ever run.
        expectNoVisiblePlaceholder('at rest (screen-height seed)');

        // Phase 2 — every offset, stepping under the real viewport's own
        // re-anchor threshold (320 / 4 = 80) so the window is deliberately
        // sampled while stale, which is when the slack alone carries it.
        const double kStep = 50;
        expect(
          kStep,
          lessThan(kShrunkViewportH / 4),
          reason:
              'the sweep must under-step the re-anchor threshold or it only '
              'ever samples a freshly-anchored window',
        );
        final double maxExtent = verticalScrollable(
          tester,
        ).position.maxScrollExtent;
        expect(
          maxExtent,
          greaterThan(kShrunkViewportH),
          reason:
              'fixture guard: the day must overflow the shrunk viewport or '
              'nothing is ever off-screen and this test is vacuous',
        );
        for (double offset = 0; offset <= maxExtent; offset += kStep) {
          await scrollTo(tester, offset);
          expectNoVisiblePlaceholder('at offset $offset (real viewport)');
        }
        await scrollTo(tester, maxExtent);
        expectNoVisiblePlaceholder('at maxScrollExtent');

        // FIXTURE GUARD: vacuous unless culling actually engaged. Asserted
        // back at the top, where the day's tail is furthest below the fold.
        await scrollTo(tester, 0);
        expect(
          culledPlaceholder('chrome-11'),
          findsOneWidget,
          reason:
              'nothing was culled at the shrunk viewport at all, so the '
              'assertions above proved nothing — culling must engage MORE at a '
              'smaller viewport, not less',
        );
      },
    );

    // ─────────────────────────────────────────────────────────────────────
    // ADDENDUM 9 — THE HYSTERESIS HALF OF THE MARGIN, PINNED SHARPLY.
    //
    // The window's safety is a SUBTRACTION between two independent constants:
    // the guaranteed on-screen margin is
    // `(_kWindowSlack - _kWindowReanchorFraction) x viewport`. Every other
    // culling test above pins only the FIRST term:
    //
    //   * The "band ends at 1.5 viewports" case measures the window at rest
    //     (offset 0, freshly anchored), so it sees `_kWindowSlack` and is
    //     blind to `_kWindowReanchorFraction` entirely.
    //   * The two sweeps DO scroll, but they step at a fixed 100/50dp over a
    //     fixture whose cards sit 120dp apart — so whether a violated card
    //     happens to land in the strip between the visible bottom and the
    //     window edge is luck, not construction.
    //
    // MEASURED GAP (mobile-qa, 2026-07-24): mutating ONLY
    // `_kWindowReanchorFraction` 0.25 -> 0.6, leaving the slack at 0.5, makes
    // the guaranteed margin `-0.1 x viewport` — cards that are genuinely on
    // screen render as blank boxes part-way through every scroll — and the
    // whole file still passed green. This case is what makes that mutation
    // red. It is the "cards POP IN during scroll" regression, which is
    // user-visible in a way that a merely-too-WIDE window never is.
    //
    // TWO CONSTRUCTION CHOICES DO THE WORK, and both are guarded below rather
    // than left as comments:
    //
    //   1. A DENSE fixture — 15-minute bookings tile at exactly 30dp, a
    //      quarter of the 120dp pitch the other cases use — so the sweep's
    //      RESOLUTION is 30dp: any margin violation wider than one card is
    //      caught by construction instead of by coincidence.
    //   2. A FINE step that is NOT derived from the current threshold. The
    //      sibling sweep guards `kStep < kViewportH / 4`, which re-states
    //      today's `_kWindowReanchorFraction` as a literal — if that constant
    //      grows, the guard silently stops meaning "under-steps the
    //      threshold". Stepping at 10dp under-steps ANY threshold, so every
    //      staleness level up to whatever the real one is gets sampled,
    //      including the worst case immediately before a re-anchor.
    // ─────────────────────────────────────────────────────────────────────
    testWidgets(
      'the re-anchor hysteresis never outruns the slack: at EVERY scroll '
      'offset — including the maximum staleness just before a re-anchor — no '
      'culled card is above the fold',
      (WidgetTester tester) async {
        // 15-minute bookings tile at exactly 30dp (band 30dp vs the 28dp
        // micro floor), giving the sweep 4x the resolution of the 120dp
        // fixtures above. 09:00–21:00 is 48 cards / 1440dp — comfortably past
        // the 893dp window edge, so culling genuinely engages (a shorter day
        // fits INSIDE the window and the sweep would assert nothing; the
        // `sawCulled` guard below is what caught exactly that while this case
        // was being written).
        const int kCardCount = 48;
        final List<Booking> bookings = <Booking>[
          for (int i = 0; i < kCardCount; i++)
            _booking(
              id: 'hyst-$i',
              startAtUtc: _kyivAtUtc(9 + i ~/ 4, (i % 4) * 15),
              durationMinutes: 15,
            ),
        ];

        await tester.pumpApp(
          BookingsTimelineGrid(
            bookings: bookings,
            day: _day,
            onBookingTap: (_) {},
          ),
        );
        await tester.pump();

        // FIXTURE GUARD — the resolution claim, measured rather than assumed.
        // If a density pass changed the micro floor so 15-minute cards no
        // longer tile at 30dp, this sweep would quietly get coarser.
        final double pitch =
            tester.getRect(realCard('hyst-1')).top -
            tester.getRect(realCard('hyst-0')).top;
        expect(
          pitch,
          closeTo(30, 1.0),
          reason:
              'fixture guard: the dense run must tile at 30dp for the sweep '
              'to resolve a margin violation narrower than the 120dp fixtures '
              'used elsewhere',
        );

        /// The topmost culled card's rendered top, or null when nothing is
        /// culled. Collected in ONE tree walk (a key-prefix predicate) rather
        /// than 24 finder lookups per offset, so the fine step stays cheap.
        double? topmostCulledTop() {
          final Iterable<Element> culled = find
              .byWidgetPredicate(
                (Widget w) =>
                    w.key is ValueKey<String> &&
                    (w.key! as ValueKey<String>).value.startsWith(
                      'timeline-card-culled-',
                    ),
              )
              .evaluate();
          double? top;
          for (final Element e in culled) {
            final RenderBox box = e.renderObject! as RenderBox;
            final double t = box.localToGlobal(Offset.zero).dy;
            if (top == null || t < top) top = t;
          }
          return top;
        }

        final double fold = tester
            .getRect(find.byType(BookingsTimelineGrid))
            .bottom;
        final double maxExtent = verticalScrollable(
          tester,
        ).position.maxScrollExtent;
        expect(
          maxExtent,
          greaterThan(0),
          reason:
              'fixture guard: the day must overflow the viewport or nothing '
              'is ever culled',
        );

        // 10dp under-steps ANY plausible re-anchor threshold, so the window is
        // sampled at every staleness including its worst. Deliberately NOT
        // expressed as a fraction of the viewport — see this case's header.
        const double kFineStep = 10;
        int sawCulled = 0;
        for (double offset = 0; offset <= maxExtent; offset += kFineStep) {
          await scrollTo(tester, offset);
          final double? top = topmostCulledTop();
          if (top == null) continue;
          sawCulled++;
          expect(
            top,
            greaterThanOrEqualTo(fold - 0.5),
            reason:
                'at scroll offset $offset the topmost culled card starts at '
                '${top}dp, ABOVE the fold at ${fold}dp — it is on screen and '
                'it is a blank box. The guaranteed margin '
                '`(slack - reanchorFraction) x viewport` has gone negative: '
                'either the slack was shaved or the re-anchor threshold was '
                'raised without raising the slack with it. Cards will POP IN '
                'as the user scrolls.',
          );
        }

        expect(
          sawCulled,
          greaterThan(0),
          reason:
              'nothing was culled at ANY offset, so this sweep asserted '
              'nothing',
        );
      },
    );

    // ─────────────────────────────────────────────────────────────────────
    // ADDENDUM 6 — THIS TEST REPLACES THE TEXT-SCALE GATE (mobile-perf
    // MEDIUM). It used to assert the exact opposite: that culling switched
    // ITSELF OFF above textScaler 1.0, because the placeholder could not be
    // size-exact there. That was the defect — `main.dart` clamps only the
    // scale CEILING (1.3), so Android's ordinary "Large" setting (1.15) and
    // the clamped maximum both reach this widget intact, and every such user
    // spent their whole session on the un-culled ~200-layer grid: the HIGH
    // was simply unfixed for them.
    //
    // The gate is gone. Culling runs at every scale, but only BELOW the
    // visible band, so an imperfect placeholder can only displace content
    // that is itself off-screen and further down. DELIBERATELY RELAXED, and
    // deliberately not asserted anywhere: "the placeholder is size-exact at
    // 1.3" is not true, and no longer needs to be.
    // ─────────────────────────────────────────────────────────────────────
    testWidgets(
      'at textScaler 1.3 culling STILL engages below the window, and still '
      'never touches a card at or above the visible band',
      (WidgetTester tester) async {
        final List<Booking> day = <Booking>[
          for (int i = 0; i < 12; i++)
            _booking(
              id: 'scaled-$i',
              startAtUtc: _kyivAtUtc(9 + i),
              durationMinutes: 60,
            ),
        ];

        await tester.pumpApp(
          BookingsTimelineGrid(bookings: day, day: _day, onBookingTap: (_) {}),
          textScaleFactor: 1.3,
        );
        await tester.pump();

        // 1. The fix itself: a scaled-up locale gets culling, not the whole
        //    day materialised.
        expect(realCard('scaled-0'), findsOneWidget);
        expect(
          culledPlaceholder('scaled-11'),
          findsOneWidget,
          reason:
              'nothing was culled at textScaler 1.3 — the text-scale gate is '
              'back, and every user above 1.0 (Android\'s "Large" = 1.15, and '
              'main.dart\'s own 1.3 clamp) is on the un-culled ~200-layer '
              'grid for their whole session',
        );

        // 2. Content offsets of everything already rendered, before and after
        //    a full-day scroll. Cards at or above the window are never
        //    substituted, so none of these can move — even though the
        //    placeholder below them is NOT size-exact at 1.3.
        double contentOffsetOf(String id) {
          final double gridTop = tester
              .getTopLeft(
                find.byKey(const ValueKey<String>('timeline-lane-stack')),
              )
              .dy;
          return tester.getTopLeft(realCard(id)).dy - gridTop;
        }

        final Map<String, double> atRest = <String, double>{
          for (int i = 0; i < day.length; i++)
            if (realCard('scaled-$i').evaluate().isNotEmpty)
              'scaled-$i': contentOffsetOf('scaled-$i'),
        };
        expect(
          atRest.length,
          lessThan(day.length),
          reason:
              'fixture guard: every card was real at rest, so "nothing that '
              'was already rendered moved" proves nothing',
        );

        await scrollTo(tester, double.infinity);
        await tester.pumpAndSettle();

        expect(
          realCard('scaled-0'),
          findsOneWidget,
          reason:
              'the head of the day was culled after scrolling to the bottom '
              '— culling has been re-enabled ABOVE the visible band, and at '
              '1.3 the placeholder is NOT size-exact, so visible cards will '
              'slide off their own hour gridlines',
        );
        atRest.forEach((String id, double offset) {
          expect(
            contentOffsetOf(id),
            closeTo(offset, 0.5),
            reason:
                '$id moved from ${offset}dp to ${contentOffsetOf(id)}dp '
                'within the timeline content purely because the view was '
                'scrolled, at textScaler 1.3',
          );
        });
      },
    );
  });
}
