// Phase 7.10 timeline audit (R2 regression) — direct CARD-level pin.
//
// `bookings_timeline_grid_test.dart`'s "short bookings render their full
// card, not a clipped sliver" group already proves the fix in the TIMELINE's
// context: nothing upstream of `MasterBookingCard` computes or passes a
// forced height any more. This file proves the OTHER half — that
// `MasterBookingCard` itself has no internal mechanism left that COULD clip
// its own content, regardless of what a duration-derived box used to do to
// it. See `master_booking_card.dart`'s class doc for the retired
// `OverflowBox` + `ClipRect` pair this pins against reintroducing: an earlier
// version wrapped the card in that pair whenever an externally-forced
// `height:` came in smaller than the card's natural size (as it always did
// for anything shorter than ~50 minutes) — laying the card out at its full
// natural height and then visually CROPPING the paint (and the hit-test
// region) down to the forced box. That was the exact mechanism behind the
// real-device report: "I can see only half of the card, and another card is
// cut off".
//
// `MasterBookingCard` no longer accepts a `width`/`height` constructor param
// at all (only `booking` + `onTap`), so there is no longer any external knob
// that could reintroduce the old clip — this file pumps the card completely
// unconstrained (no `SizedBox`/`ConstrainedBox` wrapper) and asserts every
// content row a SHORT (20-minute) booking carries actually reaches the
// render tree.
//
// COMPACT-TIMELINE PASS (2026-07-20): the card dropped its avatar row and
// moved to a two-line grid (time/service/price, then client/status) targeting
// ~52-56dp so it fits inside a 45-60 minute timeline slot — see
// `master_booking_card.dart`'s class doc for the full rationale (the "cards
// going outside the time lines" report was really about `_LaneColumn`'s
// collision-nudge compensating for a card that could never fit its own true
// hour line). The text-content assertions below were updated for the new
// grid and the height assertions now pin the card comfortably UNDER a
// 45-minute slot's worth of ruler space instead of proving it clears the old
// ~150dp avatar-row floor.
//
// TIME IS A RANGE, AND CARRIES NO DATE (2026-07-21)
// -------------------------------------------------
// BOTH layouts now print `start–end` via `formatSlotTimeRange(startAt,
// endAt)` — the compact grid's leading label and the full layout's
// `schedule_outlined` caption alike — and NEITHER prints a date any more (the
// full layout's old "12 лип, 14:30" caption is gone; «Мої записи» is
// day-scoped and the day rail already names the day). Two things are asserted
// throughout, both of which a naive "the range renders" check would miss:
//
//   * NO DATE anywhere on the card — checked against the fixture's own
//     `kMonthsUkShort` token rather than a Cyrillic literal, so it survives
//     both the i18n-finder gate and a change of fixture date.
//   * The range comes from `endAt`, NOT from `startAt + durationMinutes`. The
//     "endAt is the source of truth" case below deliberately hands the
//     fixture an `endAt` that disagrees with its `durationMinutes`, which is
//     the only shape that can tell the two derivations apart.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_display_x.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

Booking _shortBooking({
  String id = 'short-card',
  int durationMinutes = 20,
  BookingStatus status = BookingStatus.confirmed,
}) {
  // WHY A PINNED INSTANT AND NOT `futureBookingStart()` (stale-future-date
  // gate, 2026-07-21)
  // -----------------------------------------------------------------------
  // Every assertion in this file that touches time is a WALL-CLOCK STRING
  // assertion derived from this instant: the «09:00–09:20» range the card
  // prints, its measured dp width in the narrow-lane sweeps below (a
  // now-relative anchor makes the label 1-2 glyphs wider or narrower
  // depending on the hour it lands on, which silently moves every measured
  // overflow floor), and the `kMonthsUkShort` no-date probe in
  // `_expectNoDateOnCard`. Expiry cannot change any outcome either:
  // `MasterBookingCard` renders nothing off `BookingDisplayX.isPast` — the
  // status badge maps from `booking.status` alone and `showsPrice` is a pure
  // status predicate — so this fixture is inert with respect to "now" by
  // construction, not by luck.
  // future-date-ok: pinned Kyiv wall-clock fixture — see the block above.
  final DateTime startAt = DateTime.utc(2026, 7, 20, 6); // 09:00 Kyiv
  return Booking(
    id: id,
    masterId: 'master-1',
    masterFirstName: 'Оля',
    masterLastName: 'Коваль',
    masterType: 'INDEPENDENT_MASTER',
    clientFirstName: 'Марія',
    clientLastName: 'Іванюк',
    serviceId: 'service-1',
    serviceName: 'Стрижка жіноча',
    durationMinutes: durationMinutes,
    price: 450,
    startAt: startAt,
    endAt: startAt.add(Duration(minutes: durationMinutes)),
    status: status,
    canReview: false,
  );
}

void main() {
  group(
    'R2 regression — a short booking renders every row, none truncated',
    () {
      testWidgets(
        'a 20-minute CONFIRMED booking shows the start time, service, '
        'client name, price and status badge all at once',
        (WidgetTester tester) async {
          final Booking booking = _shortBooking();

          // `Center` matters here, not just cosmetics: `pumpApp` places the
          // card directly as `MaterialApp.home`, which receives TIGHT
          // constraints equal to the full test surface (800×600) — without a
          // loosening ancestor, `tester.getSize` would report 600 (the
          // screen height the Column is forced to fill), not the card's real
          // content-driven height. `Center` passes LOOSE constraints to its
          // child, so the card sizes to its own content as it does inside
          // `BookingsTimelineGrid`'s `SingleChildScrollView` in production.
          await tester.pumpApp(
            Center(
              child: MasterBookingCard(booking: booking, onTap: () {}),
            ),
          );
          await tester.pump();

          // No leftover mechanism that could crop the card's paint/hit-test to
          // a smaller box — the exact shape of the retired bug.
          expect(
            find.ancestor(
              of: find.byKey(const Key('master-booking-card-short-card')),
              matching: find.byType(OverflowBox),
            ),
            findsNothing,
          );
          expect(
            find.ancestor(
              of: find.byKey(const Key('master-booking-card-short-card')),
              matching: find.byType(ClipRect),
            ),
            findsNothing,
          );

          // Row 1 — start–end range + service name. `formatSlotTimeRange` is
          // the same shared formatter the card uses internally.
          expect(
            find.text(formatSlotTimeRange(booking.startAt, booking.endAt)),
            findsOneWidget,
          );
          expect(find.text(booking.serviceName), findsOneWidget);

          // The bare start time alone must NOT be what renders — that is
          // exactly the pre-range behaviour this replaced.
          expect(find.text(formatSlotTime(booking.startAt)), findsNothing);
          _expectNoDateOnCard(booking);

          // Row 2 — client name. Asserted against `booking.clientName` (the
          // same `BookingDisplayX` getter the widget renders) rather than a
          // re-typed literal, so the fixture's Cyrillic name isn't duplicated
          // as a second, driftable source of truth.
          expect(find.text(booking.clientName!), findsOneWidget);

          // Row 1's price (CONFIRMED → showsPrice) + row 2's status badge.
          expect(find.text('450 ₴'), findsOneWidget);
          expect(find.byType(TimelineStatusBadge), findsOneWidget);

          // Belt-and-braces: the card's real rendered height stays well
          // clear of the old 48dp clip floor — every row above genuinely
          // contributed to layout rather than being painted then cropped
          // away — while also staying comfortably under a 30-minute timeline
          // slot (56dp — `bookings_timeline_grid.dart`'s `_kSlotH`, chosen
          // specifically to clear this card's real ~54dp height; see that
          // file's "ADDENDUM 2"). No `minHeight` is passed here — this pumps
          // the card's own NATURAL size, unaffected by the timeline's
          // duration-floor mechanism.
          final double height = tester
              .getSize(find.byKey(const Key('master-booking-card-short-card')))
              .height;
          expect(height, greaterThan(48));
          expect(height, lessThan(64));
        },
      );

      testWidgets('an even shorter 15-minute booking still shows every row', (
        WidgetTester tester,
      ) async {
        final Booking booking = _shortBooking(
          id: 'short-15',
          durationMinutes: 15,
        );

        // `Center` matters here for the same reason as the sibling test
        // above (see its comment): without it, `pumpApp`'s
        // `MaterialApp.home` hands the card TIGHT constraints equal to the
        // full test surface, and — since the adaptive-layout pass — a
        // `minHeight` that large would trip the >=112dp full-layout switch
        // and render the full body instead of the compact grid this test is
        // about. (Both bodies now print the SAME range string, so the switch
        // is no longer observable through the time label alone — the
        // divider key is what tells them apart.)
        await tester.pumpApp(
          Center(
            child: MasterBookingCard(booking: booking, onTap: () {}),
          ),
        );
        await tester.pump();

        expect(
          find.text(formatSlotTimeRange(booking.startAt, booking.endAt)),
          findsOneWidget,
        );
        expect(find.text(booking.serviceName), findsOneWidget);
        expect(find.text(booking.clientName!), findsOneWidget);
        expect(find.text('450 ₴'), findsOneWidget);
        expect(find.byType(TimelineStatusBadge), findsOneWidget);
      });
    },
  );

  group('compact card height — the ~52dp timeline budget', () {
    // Pins the card's real measured height under a hard ceiling so a future
    // row addition (or a reverted density fix) can't silently reinflate it
    // back toward the pre-compact-pass ~150dp — which is exactly what made
    // `_LaneColumn`'s collision-nudge push cards away from their true hour
    // line in the first place (see `master_booking_card.dart`'s class doc).
    testWidgets('the card renders at roughly the design\'s ~52dp target, never '
        'anywhere near the old ~150dp avatar-row height', (
      WidgetTester tester,
    ) async {
      final Booking booking = _shortBooking(id: 'height-budget');

      // `Center` loosens the tight full-screen constraints `MaterialApp.home`
      // would otherwise impose — see the R2 group's first test for the full
      // explanation. Without it `getSize` reports the 800×600 test surface's
      // height, not the card's real content-driven height.
      await tester.pumpApp(
        Center(
          child: MasterBookingCard(booking: booking, onTap: () {}),
        ),
      );
      await tester.pump();

      final double height = tester
          .getSize(find.byKey(const Key('master-booking-card-height-budget')))
          .height;

      expect(
        height,
        lessThanOrEqualTo(60),
        reason:
            'MasterBookingCard rendered at ${height}dp — over the ~60dp '
            'timeline budget. The 30-minute slot (`_kSlotH`, '
            'bookings_timeline_grid.dart) is 56dp specifically because it '
            'was measured to clear this card\'s real height with only a '
            'couple dp of headroom (see that file\'s "ADDENDUM 2") — a card '
            'this tall would no longer fit even the proportional-height '
            'floor without help from _LaneColumn\'s collision-nudge, '
            'reintroducing the drift this pass fixed.',
      );
      expect(height, greaterThan(40));
    });

    testWidgets(
      'MasterBookingCard.estimatedNaturalHeight is a same-order-of-magnitude '
      'estimate of the real rendered height',
      (WidgetTester tester) async {
        final Booking booking = _shortBooking(id: 'height-estimate');

        // See the R2 group's first test for why `Center` is required to
        // measure the card's real content-driven height under this harness.
        await tester.pumpApp(
          Center(
            child: MasterBookingCard(booking: booking, onTap: () {}),
          ),
        );
        await tester.pump();

        final double height = tester
            .getSize(
              find.byKey(const Key('master-booking-card-height-estimate')),
            )
            .height;

        // Not a tight pin — `estimatedNaturalHeight` only has to be a
        // reasonable planning number for `_LaneColumn`'s spacer maths (see
        // that constant's doc); this just proves it hasn't drifted back
        // toward the old ~150dp figure.
        expect(MasterBookingCard.estimatedNaturalHeight, lessThan(80));
        expect(
          (MasterBookingCard.estimatedNaturalHeight - height).abs(),
          lessThan(30),
        );
      },
    );
  });

  group('tap', () {
    testWidgets('onTap fires once per tap', (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpApp(
        MasterBookingCard(booking: _shortBooking(), onTap: () => taps++),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('master-booking-card-short-card')));
      await tester.pump();

      expect(taps, 1);
    });
  });

  group('cancelled booking hides the price', () {
    testWidgets(
      'a CANCELLED booking renders no price tag but still shows the status '
      'badge',
      (WidgetTester tester) async {
        final Booking booking = _shortBooking(
          id: 'cancelled-card',
          status: BookingStatus.cancelled,
        );

        await tester.pumpApp(MasterBookingCard(booking: booking, onTap: () {}));
        await tester.pump();

        expect(find.text('450 ₴'), findsNothing);
        expect(find.byType(TimelineStatusBadge), findsOneWidget);
      },
    );

    // THE FULL LAYOUT'S `else` ARM (2026-07-21 re-audit) — row 3's no-price
    // branch is the ONE arm the narrow-lane fix rewrote that nothing pinned.
    //
    // The fix turned row 3 from `_PriceTag` + `Spacer` + badge into
    // `Expanded(Align(centerLeft, _PriceTag))` + badge, and the `else` arm
    // kept a bare `Spacer()` so the badge stays hard right when there is no
    // price. That arm cannot OVERFLOW (a `Spacer` and a badge always fit), so
    // `pumpApp`'s guard is blind to it — and a "simplification" that dropped
    // the `Spacer` (leaving the badge to fall to the LEFT edge, under the
    // service name, where the price used to be) would look plausible in a
    // diff, break the layout on every cancelled/declined/missed card, and
    // pass every other test in this file. Hence a positional assertion, not
    // just a presence one.
    testWidgets(
      'a CANCELLED booking in the FULL layout keeps its status badge hard '
      'right — the no-price arm must not lose its Spacer',
      (WidgetTester tester) async {
        final Booking booking = _shortBooking(
          id: 'cancelled-full-card',
          durationMinutes: 60,
          status: BookingStatus.cancelled,
        );

        await tester.pumpApp(
          Center(
            child: SizedBox(
              width: 226,
              child: MasterBookingCard(
                booking: booking,
                onTap: () {},
                minHeight: 112,
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(
          find.byKey(
            const Key('master-booking-card-divider-cancelled-full-card'),
          ),
          findsOneWidget,
          reason: 'precondition: this must be the FULL layout',
        );
        expect(find.text('450 ₴'), findsNothing);

        // `_fullPadding` is `EdgeInsets.all(VelvetSpacing.md)` (16), plus the
        // card's 1dp border — so a right-aligned badge sits ~17dp in from the
        // card's own right edge. A badge that lost its `Spacer` would start
        // at the LEFT padding instead, tens of dp away.
        final Rect card = tester.getRect(
          find.byKey(const Key('master-booking-card-cancelled-full-card')),
        );
        final Rect badge = tester.getRect(find.byType(TimelineStatusBadge));
        expect(
          card.right - badge.right,
          lessThan(VelvetSpacing.md + 2),
          reason:
              'the badge right edge sat ${card.right - badge.right}dp in from '
              'the card edge — row 3 has lost the Spacer that keeps it right-'
              'aligned when there is no price to occupy the Expanded',
        );
        expect(
          badge.left - card.left,
          greaterThan(VelvetSpacing.md + 2),
          reason:
              'the badge is hugging the LEFT padding, i.e. it collapsed into '
              'the slot the price would have used',
        );
      },
    );
  });

  group('mobile-perf MEDIUM-4/LOW-5 (2026-07-20) — decoration objects are '
      'hoisted, not reallocated per press', () {
    testWidgets(
      'the card outer decoration is the SAME object instance across a '
      'press/release cycle — a regression that reintroduces per-build '
      'BoxDecoration/Border.all allocation would still LOOK correct but '
      'fail this identity check',
      (WidgetTester tester) async {
        const Key cardKey = Key('master-booking-card-decoration-card');
        final Booking booking = _shortBooking(id: 'decoration-card');

        await tester.pumpApp(MasterBookingCard(booking: booking, onTap: () {}));
        await tester.pump();

        // `.first`, not a bare (implicitly `.single`) match: the price tag's
        // AND the status badge's `NeumorphicInset` each build their own
        // `AnimatedContainer` internally, so the card now contains three.
        // Pre-order descendant traversal visits the CARD's own outer
        // `AnimatedContainer` — the one this identity check is about —
        // before either nested one, so `.first` is unambiguous.
        AnimatedContainer cardContainer() => tester.widget<AnimatedContainer>(
          find
              .descendant(
                of: find.byKey(cardKey),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );

        final Decoration unpressedCard1 = cardContainer().decoration!;

        final TestGesture gesture = await tester.startGesture(
          tester.getCenter(find.byKey(cardKey)),
        );
        await tester.pump();

        // Pressed and unpressed are deliberately two DIFFERENT static
        // instances (`_decorationPressed`/`_decorationUnpressed`) — this
        // asserts the SWITCH still happens, not that the decoration is
        // frozen forever.
        final Decoration pressedCard = cardContainer().decoration!;
        expect(pressedCard, isNot(same(unpressedCard1)));

        await gesture.up();
        await tester.pump();

        final Decoration unpressedCard2 = cardContainer().decoration!;
        expect(
          unpressedCard2,
          same(unpressedCard1),
          reason:
              'releasing back to the unpressed state must reuse the exact '
              'same hoisted BoxDecoration object, not allocate a fresh '
              '(value-equal but distinct) one',
        );
      },
    );

    // Design-parity finding #9: the price tag is a `NeumorphicInset` recessed
    // well (transcribed from the approved design's own `PriceTag`), not a
    // hoisted-`BoxDecoration` bordered pill — so it has no stable decoration-
    // object identity to pin (`NeumorphicInset` builds a fresh `BoxDecoration`
    // per rebuild, same as every other call site of that shared widget across
    // the app). This structural check replaces the retired identity
    // assertions above: the price tag renders through `NeumorphicInset`, on
    // every press/release frame, without exception.
    testWidgets(
      'the price tag renders as a NeumorphicInset well, before and after a '
      'press',
      (WidgetTester tester) async {
        const Key cardKey = Key('master-booking-card-neumorphic-price');
        final Booking booking = _shortBooking(id: 'neumorphic-price');

        await tester.pumpApp(MasterBookingCard(booking: booking, onTap: () {}));
        await tester.pump();

        Finder priceInset() => find.ancestor(
          of: find.text('450 ₴'),
          matching: find.byType(NeumorphicInset),
        );

        expect(priceInset(), findsOneWidget);

        final TestGesture gesture = await tester.startGesture(
          tester.getCenter(find.byKey(cardKey)),
        );
        await tester.pump();
        expect(priceInset(), findsOneWidget);

        await gesture.up();
        await tester.pump();
        expect(priceInset(), findsOneWidget);
      },
    );
  });

  group('guest booking (no client name)', () {
    testWidgets('falls back to the localized guest label, still compact', (
      WidgetTester tester,
    ) async {
      // The same pinned Kyiv wall-clock instant `_shortBooking` uses — see its
      // doc for why this file's fixtures are inert with respect to "now".
      // Hand-built here only because this case needs a null client name, which
      // the shared factory does not expose.
      // future-date-ok: pinned Kyiv wall-clock fixture.
      final DateTime startAt = DateTime.utc(2026, 7, 20, 6);
      final Booking booking = Booking(
        id: 'guest-card',
        masterId: 'master-1',
        masterFirstName: 'Оля',
        masterLastName: 'Коваль',
        masterType: 'INDEPENDENT_MASTER',
        clientFirstName: null,
        clientLastName: null,
        serviceId: 'service-1',
        serviceName: 'Стрижка жіноча',
        durationMinutes: 20,
        price: 450,
        startAt: startAt,
        endAt: startAt.add(const Duration(minutes: 20)),
        status: BookingStatus.confirmed,
        canReview: false,
      );

      // See the R2 group's first test for why `Center` is required to
      // measure the card's real content-driven height under this harness.
      await tester.pumpApp(
        Center(
          child: MasterBookingCard(booking: booking, onTap: () {}),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('master-booking-card-guest-card')),
        findsOneWidget,
      );
      final double height = tester
          .getSize(find.byKey(const Key('master-booking-card-guest-card')))
          .height;
      expect(height, greaterThan(40));
      expect(height, lessThan(64));
    });
  });

  group(
    'adaptive full/compact layout (2026-07-20 design-parity pass) — the '
    'switch reads the resolved minHeight constraint, not durationMinutes',
    () {
      testWidgets(
        'a >=112dp card (a 60-minute booking\'s floor) renders the FULL '
        'layout: client name, a divider, the service name BELOW the '
        'divider, the start–end time range (NO date), price and status — all '
        'present, none clipped',
        (WidgetTester tester) async {
          final Booking booking = _shortBooking(
            id: 'full-card',
            durationMinutes: 60,
          );

          await tester.pumpApp(
            Center(
              child: MasterBookingCard(
                booking: booking,
                onTap: () {},
                minHeight: 112,
              ),
            ),
          );
          await tester.pump();

          expect(tester.takeException(), isNull);

          expect(find.text(booking.clientName!), findsOneWidget);
          expect(
            find.byKey(const Key('master-booking-card-divider-full-card')),
            findsOneWidget,
          );
          expect(find.text(booking.serviceName), findsOneWidget);
          // The full layout's `schedule_outlined` caption is the SAME
          // start–end range the compact grid prints — exactly once, and
          // date-free.
          expect(
            find.text(formatSlotTimeRange(booking.startAt, booking.endAt)),
            findsOneWidget,
          );
          expect(find.byIcon(Icons.schedule_outlined), findsOneWidget);
          _expectNoDateOnCard(booking);
          // The bare start time alone must NOT be printed anywhere.
          expect(find.text(formatSlotTime(booking.startAt)), findsNothing);
          expect(find.text('450 ₴'), findsOneWidget);
          expect(find.byType(TimelineStatusBadge), findsOneWidget);

          // Structural proof the service row sits BELOW the divider (the
          // design's canonical shape), not on the client-identity row: the
          // divider's top must sit strictly between the client name's top
          // and the service row's top.
          final double clientNameY = tester
              .getTopLeft(find.text(booking.clientName!))
              .dy;
          final double dividerY = tester
              .getTopLeft(
                find.byKey(const Key('master-booking-card-divider-full-card')),
              )
              .dy;
          final double serviceY = tester
              .getTopLeft(find.text(booking.serviceName))
              .dy;
          expect(
            clientNameY,
            lessThan(dividerY),
            reason: 'the client name must render above the divider',
          );
          expect(
            dividerY,
            lessThan(serviceY),
            reason: 'the service name must render below the divider',
          );
        },
      );

      testWidgets(
        'a 56dp card (the 30-minute floor) stays on the compact grid — no '
        'divider, no date — and still renders every field un-clipped',
        (WidgetTester tester) async {
          final Booking booking = _shortBooking(
            id: 'compact-floor-card',
            durationMinutes: 30,
          );

          await tester.pumpApp(
            Center(
              child: MasterBookingCard(
                booking: booking,
                onTap: () {},
                minHeight: 56,
              ),
            ),
          );
          await tester.pump();

          expect(tester.takeException(), isNull);

          // The compact-only shape: no divider, and — like the full layout —
          // no date.
          expect(
            find.byKey(
              const Key('master-booking-card-divider-compact-floor-card'),
            ),
            findsNothing,
          );
          _expectNoDateOnCard(booking);

          // Every field the compact grid DOES show is still there.
          expect(
            find.text(formatSlotTimeRange(booking.startAt, booking.endAt)),
            findsOneWidget,
          );
          expect(find.text(booking.serviceName), findsOneWidget);
          expect(find.text(booking.clientName!), findsOneWidget);
          expect(find.text('450 ₴'), findsOneWidget);
          expect(find.byType(TimelineStatusBadge), findsOneWidget);

          final double height = tester
              .getSize(
                find.byKey(const Key('master-booking-card-compact-floor-card')),
              )
              .height;
          expect(height, closeTo(56, 0.5));
        },
      );

      testWidgets(
        'MUTATION CHECK — forcing the compact layout at every height makes '
        'the full-layout divider assertion fail; the real code must NOT '
        'exhibit this failure',
        (WidgetTester tester) async {
          // This test intentionally re-runs the FIRST test's own divider
          // assertion against a card whose `minHeight` is comfortably past
          // the >=112dp threshold, as a standing structural guard: it is
          // the automated half of the manual mutation check documented in
          // the phase report (temporarily hardcoding `_useFullLayout` to
          // always return `false` in `master_booking_card.dart` and
          // re-running this file turns
          // THIS test red — the divider key never renders — while every
          // other test in this file stays green, isolating the switch as
          // the thing under test).
          final Booking booking = _shortBooking(
            id: 'mutation-guard-card',
            durationMinutes: 90,
          );

          await tester.pumpApp(
            Center(
              child: MasterBookingCard(
                booking: booking,
                onTap: () {},
                minHeight: 168,
              ),
            ),
          );
          await tester.pump();

          expect(
            find.byKey(
              const Key('master-booking-card-divider-mutation-guard-card'),
            ),
            findsOneWidget,
            reason:
                'a 168dp (90-minute) card must select the FULL layout — if '
                'this fails, the height-vs-threshold switch in '
                'MasterBookingCard.build has regressed to always picking '
                'the compact body.',
          );
        },
      );
    },
  );

  // The 2026-07-21 pass: both layouts print `start–end`, neither prints a
  // date. The per-layout content assertions live in the groups above; this
  // group pins the two properties those assertions cannot express — where the
  // end instant COMES FROM, and that the widened label cannot overflow the
  // narrowest lane the timeline ever renders.
  group('start–end time range', () {
    // THE MUTATION THIS CATCHES: `formatTimeRange(startAt, durationMinutes)`
    // substituted for `formatSlotTimeRange(startAt, endAt)`. Against a normal
    // fixture the two agree exactly, so every other test in this file would
    // stay green through that swap. Here `endAt` is deliberately 45 minutes
    // after the start while `durationMinutes` still says 20 — only a card
    // reading the real persisted `endAt` prints 09:45.
    for (final ({String label, double? minHeight}) layout
        in <({String label, double? minHeight})>[
          (label: 'compact', minHeight: null),
          (label: 'full', minHeight: 112),
        ]) {
      testWidgets('the ${layout.label} layout reads the persisted endAt, never '
          'startAt + durationMinutes', (WidgetTester tester) async {
        final Booking base = _shortBooking(id: 'endat-${layout.label}');
        final Booking booking = base.copyWith(
          endAt: base.startAt.add(const Duration(minutes: 45)),
        );
        expect(
          booking.durationMinutes,
          20,
          reason:
              'the fixture must keep a durationMinutes that DISAGREES with '
              'endAt, or this proves nothing',
        );

        await tester.pumpApp(
          Center(
            child: MasterBookingCard(
              booking: booking,
              onTap: () {},
              minHeight: layout.minHeight,
            ),
          ),
        );
        await tester.pump();

        // 09:00 Kyiv + 45 minutes. Asserted through the formatter (not a
        // literal) so the expectation stays anchored to the fixture, then
        // cross-checked against the duration-derived string it must NOT be.
        expect(
          find.text(formatSlotTimeRange(booking.startAt, booking.endAt)),
          findsOneWidget,
        );
        expect(
          find.text(formatTimeRange(booking.startAt, booking.durationMinutes)),
          findsNothing,
          reason:
              're-deriving the end from durationMinutes is exactly the '
              'second source of truth this formatter choice avoids',
        );
      });
    }

    // OVERFLOW BUDGET — the range roughly DOUBLES row 1's leading label
    // (measured through `VelvetText.masterCardTime`: «09:00» is 30.45dp,
    // «09:00–09:20» is 66.65dp at textScaler 1.0, and 39.55 -> 86.58 at 1.3),
    // so this is the real risk of the change.
    //
    // THE NARROWEST LANE IS 226dp, NOT 266 — a 320dp device, not a 360dp one
    // ---------------------------------------------------------------------
    // `bookings_timeline_grid.dart`'s "ADDENDUM 3" clamps the 272dp card to
    // `constraints.maxWidth`, and the lane area is `deviceWidth − 94` (24 + 24
    // screen padding, 42 ruler, 4 gap). An earlier version of this group
    // asserted 266dp — `360 − 94` — was "the narrowest lane the production
    // grid ever renders". It is not: this app treats 320dp as a supported
    // width throughout (`test/golden/master_profile_golden_test.dart` and
    // `auth_register_golden_test.dart` both sweep {320, 360, 414};
    // `service_setup_screen_test.dart` sweeps {320, 360, 412};
    // `pricing_toggle_overflow_test.dart` exists solely for 320dp;
    // `login_screen.dart` and `passport_preview_card.dart` both carry 320dp
    // layout notes), and minSdk 26 keeps 320dp Android 8 hardware in the
    // supported fleet. `320 − 94 = 226`, so 226dp is the real floor and the
    // clamp genuinely produces it.
    //
    // That mattered concretely: the retired flat `greaterThan(80)` assertion
    // measured 79.88dp at 226dp — it would have failed by 0.12dp on the
    // narrowest device it claimed to protect. Each lane now carries its own
    // measured floor instead of one number that only fits the widest case.
    //
    // SWEPT ACROSS textScaler, and that sweep is load-bearing: 1.3 is the
    // app's own MediaQuery ceiling (`main.dart`), and the range's extra width
    // scales WITH the text while the lane does not — so the narrowest lane at
    // the largest scale is the corner the widened label actually threatens.
    // `pumpApp` installs the overflow guard, so a RenderFlex overflow fails
    // these on its own.
    for (final ({String label, double width, double at10, double at13}) lane
        in <({String label, double width, double at10, double at13})>[
          (
            label: 'the narrowest clamped 226dp lane (a 320dp device)',
            width: 226,
            at10: 70,
            at13: 42,
          ),
          (
            label: 'the 266dp lane (a 360dp device)',
            width: 266,
            at10: 108,
            at13: 80,
          ),
          (
            label: 'the unclamped production 272dp lane',
            width: 272,
            at10: 113,
            at13: 86,
          ),
        ]) {
      for (final double scale in <double>[1.0, 1.3]) {
        testWidgets('the range + a long service name stay inside ${lane.label} '
            '(textScaler $scale)', (WidgetTester tester) async {
          final Booking booking = _shortBooking(id: 'narrow-lane').copyWith(
            serviceName:
                'Комплексний догляд за волоссям з ботоксом та укладкою',
          );

          await tester.pumpApp(
            Center(
              child: SizedBox(
                width: lane.width,
                child: MasterBookingCard(booking: booking, onTap: () {}),
              ),
            ),
            textScaleFactor: scale,
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(
            find.text(formatSlotTimeRange(booking.startAt, booking.endAt)),
            findsOneWidget,
          );

          // The `Expanded` service name absorbs the width the wider time
          // label took, so what matters is that it still gets a USABLE
          // share rather than being squeezed to an ellipsis-only sliver.
          // Floors are the real measured width minus ~10dp of slack:
          // 226dp -> 79.88 / 51.12, 266dp -> 119.88 / 91.12,
          // 272dp -> 125.88 / 97.12 at scale 1.0 / 1.3.
          final double expectedFloor = scale == 1.0 ? lane.at10 : lane.at13;
          final double serviceWidth = tester
              .renderObject<RenderBox>(find.text(booking.serviceName))
              .size
              .width;
          expect(
            serviceWidth,
            greaterThan(expectedFloor),
            reason:
                'the service name rendered at ${serviceWidth}dp in a '
                '${lane.width}dp lane at textScaler $scale — the widened '
                'start–end label has eaten the row. Shrink the range, not '
                'the service name.',
          );
        });
      }
    }

    // The FULL layout's own narrow-lane budget. Its time caption sits in row 2
    // beside an `Expanded` service name, so it cannot overflow that row on its
    // own — but it is also the row the change actually touched, and the change
    // made it NARROWER, not wider: the retired «20 лип, 09:00» caption
    // measures 70.88dp in `VelvetText.masterCardDateFull` against the range's
    // 63.76dp (92.13 vs 82.86 at textScaler 1.3). This pins that gain so a
    // future edit cannot quietly hand it back.
    for (final double scale in <double>[1.0, 1.3]) {
      testWidgets(
        'the FULL layout keeps a usable service column in the narrowest '
        '226dp lane (textScaler $scale)',
        (WidgetTester tester) async {
          final Booking booking =
              _shortBooking(
                id: 'narrow-lane-full',
                durationMinutes: 60,
              ).copyWith(
                serviceName:
                    'Комплексний догляд за волоссям з ботоксом та укладкою',
              );

          await tester.pumpApp(
            Center(
              child: SizedBox(
                width: 226,
                child: MasterBookingCard(
                  booking: booking,
                  onTap: () {},
                  minHeight: 112,
                ),
              ),
            ),
            textScaleFactor: scale,
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(
            find.byKey(
              const Key('master-booking-card-divider-narrow-lane-full'),
            ),
            findsOneWidget,
            reason: 'precondition: this must be the FULL layout',
          );
          expect(
            find.text(formatSlotTimeRange(booking.startAt, booking.endAt)),
            findsOneWidget,
          );
          _expectNoDateOnCard(booking);

          // Measured 80.24dp at 1.0 and 61.14dp at 1.3; floors carry ~10dp of
          // slack.
          final double serviceWidth = tester
              .renderObject<RenderBox>(find.text(booking.serviceName))
              .size
              .width;
          expect(serviceWidth, greaterThan(scale == 1.0 ? 70 : 50));
        },
      );
    }
  });

  group('border visibility (2026-07-20 design-parity pass)', () {
    testWidgets(
      'the card border uses the bumped 0.38-alpha / 1.5dp stroke, not the '
      'old 0.18-alpha / 1dp one — catches a silent revert',
      (WidgetTester tester) async {
        const Key cardKey = Key('master-booking-card-border-card');
        final Booking booking = _shortBooking(id: 'border-card');

        await tester.pumpApp(
          Center(
            child: MasterBookingCard(booking: booking, onTap: () {}),
          ),
        );
        await tester.pump();

        final AnimatedContainer cardContainer = tester
            .widget<AnimatedContainer>(
              find
                  .descendant(
                    of: find.byKey(cardKey),
                    matching: find.byType(AnimatedContainer),
                  )
                  .first,
            );
        final BoxDecoration decoration =
            cardContainer.decoration! as BoxDecoration;
        final Border border = decoration.border! as Border;

        expect(
          border.top.width,
          1.5,
          reason: 'border width must be the bumped 1.5dp, not the old 1dp',
        );
        expect(
          border.top.color,
          BrandColors.accent.withValues(alpha: 0.38),
          reason:
              'border alpha must be the bumped 0.38, not the old 0.18 — a '
              'silent revert here would make the "much more visible" '
              'border ask regress unnoticed.',
        );
      },
    );
  });

  // A booking made against a service the master had left as a genuine RANGE
  // carries BOTH `price` (floor) and `priceMax` (ceiling), frozen server-side
  // at booking time. The pill must render the band — the shipped bug was that
  // it showed the floor alone — and, because it is a NON-flex child beside an
  // `Expanded` service name, the wider two-number string must not be able to
  // trip a RenderFlex overflow on a narrow timeline lane.
  group('frozen RANGE price band', () {
    testWidgets('the compact layout renders «300–500 ₴», not the floor alone', (
      WidgetTester tester,
    ) async {
      final Booking booking = _shortBooking().copyWith(
        price: 300,
        priceMax: 500,
      );

      await tester.pumpApp(
        Center(
          child: MasterBookingCard(booking: booking, onTap: () {}),
        ),
      );
      await tester.pump();

      expect(find.text('300–500 ₴'), findsOneWidget);
      expect(
        find.text('300 ₴'),
        findsNothing,
        reason: 'the floor alone is exactly the bug this fixes',
      );
    });

    testWidgets('the full layout (>=112dp) renders the band too', (
      WidgetTester tester,
    ) async {
      final Booking booking = _shortBooking(
        durationMinutes: 60,
      ).copyWith(price: 300, priceMax: 500);

      await tester.pumpApp(
        Center(
          child: MasterBookingCard(
            booking: booking,
            onTap: () {},
            minHeight: 112,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('300–500 ₴'), findsOneWidget);
    });

    testWidgets('a null priceMax still renders the SINGLE price — null is not '
        'a missing value', (WidgetTester tester) async {
      final Booking booking = _shortBooking();
      expect(booking.priceMax, isNull);

      await tester.pumpApp(
        Center(
          child: MasterBookingCard(booking: booking, onTap: () {}),
        ),
      );
      await tester.pump();

      expect(find.text('450 ₴'), findsOneWidget);
    });

    // The price pill is a NON-flex child beside an `Expanded` service name, so
    // a wider two-number band eats into the name's share rather than the other
    // way round — but if the pill's own intrinsic width ever exceeded what the
    // row had left, the `Expanded` would be squeezed to zero and the Row would
    // overflow. `_PriceTag` caps its text at 96dp and scales down, which keeps
    // the worst band this card can be asked to draw inside the lane's budget.
    //
    // THE TWO WIDTHS ARE BOTH REAL — 272 is `BookingsTimelineGrid._kCardW`,
    // and since "ADDENDUM 3" (that file) it is a CEILING rather than a fixed
    // width: the grid clamps it to `constraints.maxWidth`, so a 360dp device
    // renders 266 (`360 − 94`).
    //
    // 266 IS NOT THE FLOOR. An earlier version of this very comment claimed
    // "266 is therefore the narrowest lane production ever builds this card
    // at". It is not — `320 − 94 = 226` is, because 320dp is a supported
    // width (`test/golden/helpers/golden_pump.dart`'s `kGoldenWidths` is
    // {320, 360, 414}, and `android/app/build.gradle.kts`'s `minSdk = 26`
    // keeps 320dp hardware in the fleet). That restatement is what hid the
    // 226dp overflow this file now sweeps for: the arithmetic in
    // `bookings_timeline_grid.dart` was always right, only the "narrowest
    // device" gloss on top of it was wrong, and it was copied into three
    // places before anyone re-derived it. This pair of lanes is therefore the
    // WIDE end of the coverage; the floor is covered by "THE 226dp NARROW-LANE
    // SWEEP" below and by the "start–end time range" group's own per-lane,
    // per-scale sweep. Do not reintroduce a "narrowest lane" claim here.
    //
    // WHY "a hypothetical 200dp lane" WAS RETIRED FROM THIS SLOT (and why QA
    // signed that off, 2026-07-21 re-audit — do not re-litigate)
    // -------------------------------------------------------------------
    // This slot previously held a 200dp entry. It was RETIRED, not weakened,
    // when the card's time label became a start–end range: the range roughly
    // doubles row 1's leading label, and the row's non-flex children (range
    // ~68dp + gaps 10dp + the capped price pill 112dp ≈ 190dp) no longer fit
    // 200dp's ~177dp of inner width, so the pathological-band case below
    // overflowed by 12dp there.
    //
    // 200dp is UNREACHABLE: the lane is `min(272, deviceWidth − 94)`, so
    // reaching 200 would need a 294dp device, well under the 320dp floor
    // cited above. It is 26dp under the real 226dp floor (the retired comment
    // said "66dp under", which was 266 − 200 — the same stale-266 error).
    // Asserting an unreachable width in place of the reachable one is what
    // let the real floor go untested, so replacing it with 266 AND adding the
    // 226 sweep is a strict net gain in coverage, not a retreat.
    //
    // Nothing about the CAP mechanism is lost either: the cap is on the
    // pill's TEXT (96dp) and is independent of lane width, so the over-cap
    // group below still engages `FittedBox(scaleDown)` at 266dp exactly as it
    // did at 200dp — as that group's own natural-vs-fitted assertions prove.
    for (final ({String label, double width}) lane
        in <({String label, double width})>[
          (label: 'the production 272dp lane', width: 272),
          (label: 'the narrowest clamped 266dp lane', width: 266),
        ]) {
      testWidgets(
        'the longest band + a long service name stay inside ${lane.label}',
        (WidgetTester tester) async {
          final Booking booking = _shortBooking().copyWith(
            serviceName:
                'Комплексний догляд за волоссям з ботоксом та укладкою',
            price: 12500,
            priceMax: 25000,
          );

          await tester.pumpApp(
            Center(
              child: SizedBox(
                width: lane.width,
                child: MasterBookingCard(booking: booking, onTap: () {}),
              ),
            ),
          );
          await tester.pump();

          // `pumpApp` installs the shared overflow guard, so a RenderFlex
          // overflow here fails the test on its own; this pins the absence of
          // any other thrown layout error too.
          expect(tester.takeException(), isNull);
          expect(find.text('12500–25000 ₴'), findsOneWidget);

          // This band FITS — it does not exercise the cap. 83.8dp of text
          // against a 96dp cap means `FittedBox` resolves to scale 1.0 and
          // the `ConstrainedBox` never binds, so on its own this case proves
          // only "the realistic worst band needs no scaling". The cap
          // MECHANISM is exercised by the group below; pinned here so the two
          // cases can never silently collapse into one.
          expect(
            _priceTextWidth(tester),
            lessThan(_kPriceCapWidth),
            reason:
                'the realistic worst band must stay UNDER the cap — if this '
                'ever fails the cap has been lowered into real data, and the '
                'over-cap group below is no longer testing anything extra',
          );
          expect(_fittedPriceWidth(tester), _priceTextWidth(tester));
        },
      );
    }

    // FINDING-3 REGRESSION — the group above measures 83.8dp against a 96dp
    // cap, so it never actually engages `_PriceTag`'s `ConstrainedBox` +
    // `FittedBox(scaleDown)`. These cases push a deliberately pathological
    // band past the cap and assert the scale-down REALLY fires, in both the
    // production 272dp lane and the narrower hypothetical one.
    for (final ({String label, double width}) lane
        in <({String label, double width})>[
          (label: 'the production 272dp lane', width: 272),
          (label: 'the narrowest clamped 266dp lane', width: 266),
        ]) {
      testWidgets('an OVER-cap band actually engages the width cap in '
          '${lane.label}', (WidgetTester tester) async {
        final Booking booking = _shortBooking().copyWith(
          serviceName: 'Комплексний догляд за волоссям з ботоксом та укладкою',
          price: 1234567,
          priceMax: 8901234,
        );

        await tester.pumpApp(
          Center(
            child: SizedBox(
              width: lane.width,
              child: MasterBookingCard(booking: booking, onTap: () {}),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);

        // The text's own render box keeps its NATURAL size — `FittedBox`
        // scales via a transform, it does not re-lay-out its child — so
        // comparing the two boxes is a direct read of whether the scale
        // engaged. Observed: natural 110.97dp vs fitted 96.0dp (scale ~0.865).
        final double natural = _priceTextWidth(tester);
        final double fitted = _fittedPriceWidth(tester);
        expect(
          natural,
          greaterThan(_kPriceCapWidth),
          reason: 'the fixture must out-measure the cap or this proves nothing',
        );
        expect(
          fitted,
          _kPriceCapWidth,
          reason: 'the ConstrainedBox must clamp the band at exactly the cap',
        );
        expect(fitted, lessThan(natural), reason: 'scaleDown must have fired');

        // The pill's own box clamps at cap + its horizontal padding, and the
        // band is still whole — scaled, never ellipsised or clipped.
        expect(_priceTagWidth(tester), _kPriceCapWidth + VelvetSpacing.sm * 2);
        expect(find.text('1234567–8901234 ₴'), findsOneWidget);
      });
    }

    // THE 226dp NARROW-LANE SWEEP (2026-07-21 audit fix) — the corner both
    // layouts actually overflowed in
    // ------------------------------------------------------------------
    // The two lane sweeps above stop at 266dp and run at textScaler 1.0 only,
    // which is why the real failure hid: at the true floor (226dp — a 320dp
    // device, see the "start–end time range" group's own note on why 226 and
    // not 266) BOTH layouts overflowed once a frozen band was present.
    // Measured before the fix, all with «12500–25000 ₴»:
    //
    //   * compact row 1 — clean at 1.0/1.15, 5.6px over at 1.3. The range
    //     label is 47.0dp wider than the bare start time it replaced at 1.3
    //     (36.2dp at 1.0), against ~41dp of slack the old label had left.
    //   * full row 3 — 6.6px over at 1.0 (with a cap-binding band), 16px at
    //     1.15, 26px at 1.3. Strictly worse, and NOT caused by the range at
    //     all: two non-flex children (`_PriceTag`, `TimelineStatusBadge`)
    //     either side of a `Spacer` simply cannot fit 191dp of inner width.
    //
    // Both are now structurally impossible — compact caps the pill at the
    // row's real width minus a documented reserve, full hands it the row's
    // whole remainder via `Expanded` + `Align`. `pumpApp` installs the
    // overflow guard, so the sweep fails on its own if either regresses; the
    // width assertions then pin WHICH mechanism absorbed the pressure, so a
    // future "fix" that buys the room by shrinking the service name or the
    // type scale instead cannot pass quietly.
    //
    // 1.15 is in the sweep deliberately: it is where the full layout's
    // overflow first became scale-driven rather than band-driven, and it is
    // the only scale at which the two bands below behave identically (both
    // exceed the pill's own 96dp text cap once scaled).
    for (final double scale in <double>[1.0, 1.15, 1.3]) {
      for (final ({String label, double price, double priceMax}) band
          in <({String label, double price, double priceMax})>[
            (label: 'the realistic worst band', price: 12500, priceMax: 25000),
            (
              label: 'a pathological 7-digit band',
              price: 1234567,
              priceMax: 8901234,
            ),
          ]) {
        for (final ({String label, double? minHeight, int duration}) layout
            in <({String label, double? minHeight, int duration})>[
              (label: 'compact', minHeight: null, duration: 20),
              (label: 'full', minHeight: 112, duration: 60),
            ]) {
          testWidgets(
            '${band.label} fits the ${layout.label} layout in the narrowest '
            '226dp lane (textScaler $scale)',
            (WidgetTester tester) async {
              final Booking booking =
                  _shortBooking(
                    id: 'narrow-band-${layout.label}',
                    durationMinutes: layout.duration,
                  ).copyWith(
                    serviceName:
                        'Комплексний догляд за волоссям з ботоксом та укладкою',
                    price: band.price,
                    priceMax: band.priceMax,
                  );

              await tester.pumpApp(
                Center(
                  child: SizedBox(
                    width: 226,
                    child: MasterBookingCard(
                      booking: booking,
                      onTap: () {},
                      minHeight: layout.minHeight,
                    ),
                  ),
                ),
                textScaleFactor: scale,
              );
              await tester.pump();

              expect(tester.takeException(), isNull);

              // The band is still WHOLE — `scaleDown` shrinks, it never
              // ellipsises, so absorbing the pressure must not have cost a
              // digit.
              expect(find.text(booking.priceLabel), findsOneWidget);
              // …and the range is still a range, still date-free.
              expect(
                find.text(formatSlotTimeRange(booking.startAt, booking.endAt)),
                findsOneWidget,
              );
              _expectNoDateOnCard(booking);

              // NON-VACUITY — the pill really is bounded below its own
              // 112dp ceiling (96 cap + 2×8 padding) here, i.e. the new
              // constraint is doing the work rather than the case having
              // been comfortable all along. The one exception is the full
              // layout at 1.0, where the badge is narrow enough that the
              // row's remainder still clears 112.
              final double pill = _priceTagWidth(tester);
              const double ceiling = _kPriceCapWidth + VelvetSpacing.sm * 2;
              if (layout.label == 'compact' || scale > 1.0) {
                expect(
                  pill,
                  lessThan(ceiling),
                  reason:
                      'the pill measured ${pill}dp — at 226dp/$scale it must '
                      'be held under its own ${ceiling}dp ceiling by the '
                      'row, or the row is back to the unbounded non-flex '
                      'contract that overflowed',
                );
              }

              // The service name is what must NOT have paid for the fit
              // beyond the ellipsis it was always allowed to take. Floors
              // are PER SCALE, not one flat number: the same standard the
              // "start–end time range" group sets out above ("each lane now
              // carries its own measured floor instead of one number that
              // only fits the widest case") applies along the textScaler
              // axis too. A flat floor low enough to pass at 1.3 leaves
              // ~25dp of undetected slack at 1.0, so a future edit could
              // hand the pill 20dp more of the row and only the 1.3 case
              // would notice — which is one mutation away from no coverage
              // at all. See [_narrowServiceFloors] for the measurements.
              final ({double compact, double full})? floors =
                  _narrowServiceFloors(scale);
              expect(
                floors,
                isNotNull,
                reason:
                    'no measured service-name floor recorded for textScaler '
                    '$scale — add one to _narrowServiceFloors rather than '
                    'letting the sweep run unpinned',
              );
              final double serviceWidth = tester
                  .renderObject<RenderBox>(find.text(booking.serviceName))
                  .size
                  .width;
              expect(
                serviceWidth,
                greaterThan(
                  layout.label == 'full' ? floors!.full : floors!.compact,
                ),
                reason:
                    'the service name rendered at ${serviceWidth}dp in the '
                    '${layout.label} layout at textScaler $scale — the '
                    'overflow must be absorbed by the price pill scaling '
                    'down, not by squeezing the name out of the card',
              );
            },
          );
        }
      }
    }

    // FINDING-5 REGRESSION — `BoxFit.scaleDown` scales UNIFORMLY, so before
    // `_PriceTag` grew its zero-width height anchor an over-cap band shrank
    // the pill's HEIGHT too (measured: text 15.0dp -> 13.0dp, pill 21 -> 19),
    // quietly dragging the compact card under
    // `MasterBookingCard.estimatedNaturalHeight`. The anchor holds the pill at
    // its natural line height whatever the horizontal scale.
    //
    // SWEPT ACROSS textScaler, and that sweep is the point (perf P2). At the
    // default 1.0 a `SizedBox(height: 15)` would satisfy this test exactly as
    // well as the `Text` anchor does — 15.0 IS the line height there — so a
    // 1.0-only case cannot tell a scale-aware anchor from a frozen constant
    // and silently blesses the swap. Above 1.0 the two diverge: the `Text`
    // re-derives its height from the inherited scaler, the box cannot see it.
    // 1.3 is the app's own MediaQuery ceiling (`main.dart`), i.e. a scale real
    // users reach, not a synthetic one.
    for (final double scale in <double>[1.0, 1.3]) {
      testWidgets('an OVER-cap band does not shrink the price pill vertically '
          '(textScaler $scale)', (WidgetTester tester) async {
        Future<({double pill, double card})> measure(
          double price,
          double priceMax,
        ) async {
          await tester.pumpApp(
            Center(
              child: SizedBox(
                width: 272,
                child: MasterBookingCard(
                  booking: _shortBooking().copyWith(
                    price: price,
                    priceMax: priceMax,
                  ),
                  onTap: () {},
                ),
              ),
            ),
            textScaleFactor: scale,
          );
          await tester.pump();
          return (
            pill: tester
                .renderObject<RenderBox>(find.byType(NeumorphicInset).first)
                .size
                .height,
            card: tester
                .renderObject<RenderBox>(find.byType(MasterBookingCard))
                .size
                .height,
          );
        }

        final ({double pill, double card}) inCap = await measure(12500, 25000);
        final ({double pill, double card}) overCap = await measure(
          1234567,
          8901234,
        );

        expect(
          overCap.pill,
          inCap.pill,
          reason:
              'the height anchor must keep the pill at its natural line height '
              'even when the width cap scales the band down',
        );
        expect(overCap.card, inCap.card);
        expect(
          overCap.card,
          greaterThanOrEqualTo(MasterBookingCard.estimatedNaturalHeight - 2),
          reason:
              'a scaled band must not drag the card under its documented '
              'natural height',
        );
      });
    }
  });
}

/// Asserts NO date component renders anywhere on the card — the 2026-07-21
/// day-scoped-timeline decision (see `master_booking_card.dart`'s "The time is
/// a RANGE" header section).
///
/// Probes the fixture's own Kyiv short-month token (`лип` for a July booking)
/// via [kMonthsUkShort] rather than a hard-coded Cyrillic literal: that keeps
/// it clear of the `forbid_cyrillic_finder.sh` gate AND re-derives itself if
/// the fixture's date ever moves. The month is the strongest single probe —
/// the retired «12 лип, 14:30» caption was the ONLY place a date reached this
/// card, and its month token cannot collide with a service name, a client
/// name, a status label or a «₴» price.
///
/// Reads the month through [toBeauticaTime] for the same reason the card
/// does: a booking in the last two hours of a UTC day is already the NEXT
/// Kyiv day, so the raw UTC month is not always the rendered one.
void _expectNoDateOnCard(Booking booking) {
  final String month =
      kMonthsUkShort[toBeauticaTime(booking.startAt).month - 1];
  expect(
    find.textContaining(month),
    findsNothing,
    reason:
        'a date component ("$month") reached the card — «Мої записи» is '
        'day-scoped and the day rail above the timeline already names the '
        'day, so the card must print the time range alone.',
  );
}

/// Measured service-name widths in the 226dp lane WITH a frozen band, per
/// textScaler, minus slack — the floors the "226dp narrow-lane sweep" pins.
///
/// Observed (identical for both bands, because at 226dp the price pill is
/// bound by the row rather than by its own text in every one of these cases):
///
/// | textScaler | compact  | full     |
/// |------------|----------|----------|
/// | 1.0        | 35.35dp  | 80.24dp  |
/// | 1.15       | 25.38dp  | 70.73dp  |
/// | 1.3        | 15.42dp  | 61.14dp  |
///
/// The compact column is small by DESIGN, not by accident:
/// `MasterBookingCard._kCompactPriceReserve` budgets only ~15dp of the row to
/// the service name at the 1.3 ceiling, deliberately spending the rest on the
/// time range and a legible price band. These floors therefore pin "the name
/// keeps the sliver the reserve promised it", not "the name is comfortable" —
/// the reserve's own doc comment is the place to argue the split.
///
/// Slack is ~5dp on the compact row (where the whole budget is ~15-35dp) and
/// ~10dp on the full row, so each entry fails on a real shift without
/// tripping on sub-pixel font-metric drift. The compact floors are what make
/// a shrunk reserve detectable at EVERY scale instead of only at 1.3.
///
/// A lookup FUNCTION rather than a `Map<double, …>` on purpose: Dart bans
/// `double` keys in a const map, and an epsilon comparison is the honest way
/// to match a scale anyway. Returns null for an unmeasured scale so the sweep
/// fails loudly rather than running unpinned.
({double compact, double full})? _narrowServiceFloors(double scale) {
  const double eps = 0.001;
  if ((scale - 1.0).abs() < eps) return (compact: 30, full: 70);
  if ((scale - 1.15).abs() < eps) return (compact: 20, full: 60);
  if ((scale - 1.3).abs() < eps) return (compact: 10, full: 50);
  return null;
}

/// `_PriceTag._maxTextWidth` — private to the widget, restated here so these
/// tests read as an independent check rather than an echo of the source.
const double _kPriceCapWidth = VelvetSpacing.xxl * 2; // 96

Finder get _priceFittedBox => find.descendant(
  of: find.byType(MasterBookingCard),
  matching: find.byType(FittedBox),
);

/// The price band's NATURAL width — `FittedBox` scales by transform, so its
/// child's render box still reports the unscaled size.
double _priceTextWidth(WidgetTester tester) => tester
    .renderObject<RenderBox>(
      find.descendant(of: _priceFittedBox, matching: find.byType(Text)),
    )
    .size
    .width;

/// The width the `ConstrainedBox` actually resolved for the band.
double _fittedPriceWidth(WidgetTester tester) =>
    tester.renderObject<RenderBox>(_priceFittedBox).size.width;

/// The whole price pill's outer width, cap + horizontal padding.
double _priceTagWidth(WidgetTester tester) => tester
    .renderObject<RenderBox>(find.byType(NeumorphicInset).first)
    .size
    .width;
