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

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_display_x.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/timeline_hour_ruler.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
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
      final DateTime day = DateTime(2026, 7, 20);
      // A single 60-minute booking starting exactly on the hour (09:00 Kyiv,
      // 06:00 UTC) makes the ruler's extent deterministic: firstHour = 9,
      // lastHour = 10, i.e. exactly two labels — "09:00" (i == 0, the one
      // that used to clip) and the accent "10:00" (i == 1, a later label
      // whose registration must stay untouched by the fix).
      final Booking onTheHour = _booking(
        id: 'r4-on-hour',
        startAtUtc: DateTime.utc(2026, 7, 20, 6),
        durationMinutes: 60,
      );

      // Mirrors `TimelineHourRuler._kHourH` / `BookingsTimelineGrid._kHourH`
      // (both files assert, in their own doc comments, that the two MUST
      // match) — not re-exported, so pinned here as a plain literal the way
      // this file already pins other cross-file geometry invariants (e.g. the
      // 48dp clip floor in the R2 group above). Raised from 72 to 112 by the
      // proportional-duration-height pass (2026-07-20, see
      // `bookings_timeline_grid.dart`'s "ADDENDUM 2").
      const double hourHeight = 112;

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
        // the ruler. This booking is 60 minutes (a 112dp floor), so the
        // card renders the ADAPTIVE FULL layout (2026-07-20 design-parity
        // pass) and prints the full date+time (`formatShortDateTime`), not
        // the compact grid's bare `formatSlotTime` — see
        // `master_booking_card.dart`'s "Adaptive full/compact layout"
        // header section.
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('timeline-card-crossing')),
            matching: find.text(formatShortDateTime(crossing)),
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
    // The `greaterThan(...)` floor below tracks `MasterBookingCard`'s real
    // natural height, which the compact-timeline pass (2026-07-20) shrank
    // from ~150dp to ~52-56dp (`MasterBookingCard.estimatedNaturalHeight`) —
    // it is NOT the old 48dp clip floor re-applied; it just has to stay
    // comfortably below the card's new real size so a regression that
    // reintroduces clipping (rendering back down near/at 48dp) still trips
    // it.
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
        // clip floor — proof the full card (both content rows) is on
        // screen, not a truncated sliver of it.
        final double renderedHeight = tester
            .getSize(find.byKey(const ValueKey<String>('timeline-card-short')))
            .height;
        expect(renderedHeight, greaterThan(48));
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

  group('proportional-duration-height pass (2026-07-20)', () {
    // Mirrors the private `BookingsTimelineGrid._kSlotH` / `_kHourH` (not
    // re-exported — same convention the R4 group above already uses for
    // `hourHeight`). `_kSlotH` (30-minute slot) is `_kHourH / 2` by
    // construction; see that file's "ADDENDUM 2" for the derivation of both
    // numbers from `MasterBookingCard`'s measured ~54dp natural height.
    const double kSlotH = 56;
    const double kHourH = 112;

    final DateTime day = DateTime(2026, 7, 20);

    testWidgets('a 30-minute booking renders at exactly one slot (56dp)', (
      WidgetTester tester,
    ) async {
      final Booking b = _booking(
        id: 'dur-30',
        startAtUtc: DateTime.utc(2026, 7, 20, 6), // 09:00 Kyiv
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
      'a 60-minute booking renders at AT LEAST two slots (112dp) — the '
      'floor still tracks duration proportionally, though the adaptive '
      'FULL layout\'s own natural content is slightly taller than the '
      'bare floor at this exact threshold',
      (WidgetTester tester) async {
        final Booking b = _booking(
          id: 'dur-60',
          startAtUtc: DateTime.utc(2026, 7, 20, 6),
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

        // NOT `closeTo(kHourH, 0.5)` any more (pre-adaptive-layout-pass
        // behaviour): a 60-minute booking's floor (112dp) is exactly this
        // group's `_kFullLayoutMinHeight` threshold
        // (`master_booking_card.dart`), so the card now renders the
        // ADAPTIVE FULL layout (client name / divider / service+date /
        // price+status) instead of the old compact two-row grid — and that
        // fuller layout's own natural content (~117dp measured, padding +
        // four stacked rows) is a few dp TALLER than the pure
        // duration-derived floor. [minHeight] is a floor, never a ceiling
        // (see `master_booking_card.dart`'s class doc), so the box grows to
        // fit it — exactly the documented, no-clipping behaviour, not a
        // regression. The 90-minute sibling test below still lands on an
        // EXACT floor match, because ITS floor (168dp) is already taller
        // than the full layout's natural content, so the floor — not the
        // content — wins there.
        expect(height, greaterThanOrEqualTo(kHourH));
        // A generous ceiling so a genuine future regression (e.g. the full
        // layout ballooning past its intended ~117dp) still trips this
        // test rather than being silently absorbed by a `greaterThan`-only
        // check.
        expect(height, lessThan(140));
      },
    );

    testWidgets(
      'a 90-minute booking renders at exactly three slots (168dp) — three '
      'times the 30-minute card\'s height, proving the height tracks '
      'duration proportionally rather than rounding up to a fixed unit',
      (WidgetTester tester) async {
        final Booking b = _booking(
          id: 'dur-90',
          startAtUtc: DateTime.utc(2026, 7, 20, 6),
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
      'a 45-minute booking renders at 1.5 slots (84dp) — not rounded up to '
      'a whole slot',
      (WidgetTester tester) async {
        final Booking b = _booking(
          id: 'dur-45',
          startAtUtc: DateTime.utc(2026, 7, 20, 6),
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

    testWidgets('a booking shorter than 30 minutes still renders every row, '
        'un-clipped, at the one-slot floor (56dp) rather than a '
        'duration-scaled sliver', (WidgetTester tester) async {
      final Booking b = _booking(
        id: 'dur-10',
        startAtUtc: DateTime.utc(2026, 7, 20, 6),
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

      // Floored at one slot, NOT a duration-scaled ~19dp sliver
      // (10/60*112) — that would be shorter than the card's own natural
      // content and would need clipping to render at all.
      expect(_cardRect(tester, 'dur-10').height, closeTo(kSlotH, 0.5));

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
      expect(find.text(b.clientName!), findsOneWidget);
    });

    testWidgets(
      'back-to-back bookings of DIFFERENT durations (60min then 90min) '
      'tile with only the cosmetic minimum gap, no collision-nudge drift, '
      'and never intersect',
      (WidgetTester tester) async {
        final Booking first = _booking(
          id: 'tile-60',
          startAtUtc: DateTime.utc(2026, 7, 20, 6), // 09:00 Kyiv
          durationMinutes: 60,
        );
        final Booking second = _booking(
          id: 'tile-90',
          startAtUtc: DateTime.utc(2026, 7, 20, 7), // 10:00 Kyiv, back-to-back
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

        // The tiling itself: since the first card's real height now equals
        // its full 60-minute wall-clock footprint, the second card's
        // wall-clock-derived `desiredTop` lands EXACTLY at (or past) the
        // first card's real bottom, so `_LaneColumn`'s collision-nudge
        // degenerates to its cosmetic-minimum-gap floor rather than pushing
        // the card further down to avoid a genuine collision — proving the
        // "happy consequence" the proportional-height pass exists for.
        const double kMinInterCardGap = 8; // VelvetSpacing.sm
        expect(
          secondRect.top - firstRect.bottom,
          closeTo(kMinInterCardGap, 0.5),
        );
      },
    );
  });
}
