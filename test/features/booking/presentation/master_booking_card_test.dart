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
// grid (bare start time via `formatSlotTime`, no more date-chip icon caption)
// and the height assertions now pin the card comfortably UNDER a 45-minute
// slot's worth of ruler space instead of proving it clears the old ~150dp
// avatar-row floor.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_display_x.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

Booking _shortBooking({
  String id = 'short-card',
  int durationMinutes = 20,
  BookingStatus status = BookingStatus.confirmed,
}) {
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

          // Row 1 — start time + service name. `formatSlotTime` is the same
          // bare "HH:mm" formatter the card uses internally.
          expect(find.text(formatSlotTime(booking.startAt)), findsOneWidget);
          expect(find.text(booking.serviceName), findsOneWidget);

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
        // and print the full date+time instead of the bare
        // `formatSlotTime` string this test asserts against.
        await tester.pumpApp(
          Center(
            child: MasterBookingCard(booking: booking, onTap: () {}),
          ),
        );
        await tester.pump();

        expect(find.text(formatSlotTime(booking.startAt)), findsOneWidget);
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
        'divider, full date+time, price and status — all present, none '
        'clipped',
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
          expect(
            find.text(formatShortDateTime(booking.startAt)),
            findsOneWidget,
          );
          // The compact row's bare time must NOT also be printed — the
          // full layout replaces it with the date+time caption above,
          // rather than showing both.
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
        'divider, no full date+time — and still renders every field '
        'un-clipped',
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

          // The compact-only shape: no divider, no full date+time caption.
          expect(
            find.byKey(
              const Key('master-booking-card-divider-compact-floor-card'),
            ),
            findsNothing,
          );
          expect(find.text(formatShortDateTime(booking.startAt)), findsNothing);

          // Every field the compact grid DOES show is still there.
          expect(find.text(formatSlotTime(booking.startAt)), findsOneWidget);
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
    // 272dp is `BookingsTimelineGrid._kCardW` — the ONE production width this
    // card is ever built at (the grid scrolls horizontally rather than
    // narrowing lanes), so this is the real budget, not a synthetic one.
    for (final ({String label, double width}) lane
        in <({String label, double width})>[
          (label: 'the production 272dp lane', width: 272),
          (label: 'a hypothetical 200dp lane', width: 200),
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
          (label: 'a hypothetical 200dp lane', width: 200),
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
