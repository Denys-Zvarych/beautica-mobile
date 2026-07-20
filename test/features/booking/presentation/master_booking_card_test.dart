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
// render tree: client name, service name, the date chip, the price tag, and
// the status badge. None of these depend on `durationMinutes` — the card
// never reads that field — which is itself the point: there is nothing left
// in this widget that COULD vary by duration.

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_display_x.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_status_badge.dart';
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
        'a 20-minute CONFIRMED booking shows client name, service, date chip, '
        'price and status badge all at once',
        (WidgetTester tester) async {
          final Booking booking = _shortBooking();

          await tester.pumpApp(
            MasterBookingCard(booking: booking, onTap: () {}),
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

          // Row 1 — client name. Asserted against `booking.clientName` (the
          // same `BookingDisplayX` getter the widget renders) rather than a
          // re-typed literal, so the fixture's Cyrillic name isn't duplicated
          // as a second, driftable source of truth.
          expect(find.text(booking.clientName!), findsOneWidget);

          // Row 2 — service name + date chip. `formatShortDateTime` is the same
          // formatter `_BookingDateChip` uses internally, so this is the exact
          // rendered string, not an approximation. Likewise `serviceName` is
          // read straight off the fixture, not re-typed.
          expect(find.text(booking.serviceName), findsOneWidget);
          expect(
            find.text(formatShortDateTime(booking.startAt)),
            findsOneWidget,
          );

          // Row 3 — price (CONFIRMED → showsPrice) + status badge.
          expect(find.text('450 ₴'), findsOneWidget);
          expect(find.byType(BookingStatusBadge), findsOneWidget);

          // Belt-and-braces: the card's real rendered height comfortably
          // clears the old 48dp clip floor — every row above genuinely
          // contributed to layout rather than being painted then cropped away.
          final double height = tester
              .getSize(find.byKey(const Key('master-booking-card-short-card')))
              .height;
          expect(height, greaterThan(120));
        },
      );

      testWidgets('an even shorter 15-minute booking still shows every row', (
        WidgetTester tester,
      ) async {
        final Booking booking = _shortBooking(
          id: 'short-15',
          durationMinutes: 15,
        );

        await tester.pumpApp(MasterBookingCard(booking: booking, onTap: () {}));
        await tester.pump();

        expect(find.text(booking.clientName!), findsOneWidget);
        expect(find.text(booking.serviceName), findsOneWidget);
        expect(find.text(formatShortDateTime(booking.startAt)), findsOneWidget);
        expect(find.text('450 ₴'), findsOneWidget);
        expect(find.byType(BookingStatusBadge), findsOneWidget);
      });
    },
  );

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
        expect(find.byType(BookingStatusBadge), findsOneWidget);
      },
    );
  });

  group('mobile-perf MEDIUM-4/LOW-5 (2026-07-20) — decoration objects are '
      'hoisted, not reallocated per press', () {
    testWidgets(
      'the card outer decoration and the price-tag decoration are the SAME '
      'object instance across a press/release cycle — a regression that '
      'reintroduces per-build BoxDecoration/Border.all allocation would '
      'still LOOK correct but fail this identity check',
      (WidgetTester tester) async {
        const Key cardKey = Key('master-booking-card-decoration-card');
        final Booking booking = _shortBooking(id: 'decoration-card');

        await tester.pumpApp(MasterBookingCard(booking: booking, onTap: () {}));
        await tester.pump();

        AnimatedContainer cardContainer() => tester.widget<AnimatedContainer>(
          find.descendant(
            of: find.byKey(cardKey),
            matching: find.byType(AnimatedContainer),
          ),
        );
        DecoratedBox priceTagBox() => tester.widget<DecoratedBox>(
          find
              .ancestor(
                of: find.text('450 ₴'),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );

        final Decoration unpressedCard1 = cardContainer().decoration!;
        final Decoration priceTag1 = priceTagBox().decoration;

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
        // The price tag never varies by press state, so it must be
        // untouched by the press-triggered rebuild.
        expect(priceTagBox().decoration, same(priceTag1));

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
        expect(priceTagBox().decoration, same(priceTag1));
      },
    );
  });

  group('guest booking (no client name)', () {
    testWidgets('falls back to the localized guest label, still full height', (
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

      await tester.pumpApp(MasterBookingCard(booking: booking, onTap: () {}));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('master-booking-card-guest-card')),
        findsOneWidget,
      );
      final double height = tester
          .getSize(find.byKey(const Key('master-booking-card-guest-card')))
          .height;
      expect(height, greaterThan(120));
    });
  });
}
