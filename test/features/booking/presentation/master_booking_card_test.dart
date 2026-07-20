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
}
