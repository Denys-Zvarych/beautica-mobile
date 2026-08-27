// Regression guard for the 2026-08 move of the slot time OUT of
// `BookingCard._body`'s top-right `Align` and INTO `_DateStub`, stacked as a
// third line under the day number and month/weekday caption.
//
// Nothing pinned the time's POSITION before this move — every existing
// overflow / font-size test finds it by `ValueKey('time-<id>')` alone, which
// survives a widget moving anywhere in the tree. That is exactly why the body
// could lose its `Align(centerRight, Text(time))` and gain the stub's third
// line without a single test failing on geometry (`booking_surfaces_overflow
// _test.dart` only had to swap its RIGHT-EDGE reference from the old
// `time-<id>` to the new `_bodyRightEdge()` helper — see that file's 2026-08
// diff). This file exists so a future edit that puts the time back in the
// body's top-right corner (or floats it above the date instead of below) is
// caught here, not by a designer eyeballing a screenshot.
//
// `_DateStub` is a private class (not exported), so every assertion below is
// GEOMETRY against keyed finders, per the file's own convention
// (`_bodyRightEdge()` in the overflow suite does the same thing for the same
// reason) — never a `find.byType(_DateStub)` lookup.
//
// The day-number and month/weekday `Text`s carry their own stable
// `ValueKey`s (`stub-day-$id` / `stub-month-$id`, mirroring the pre-existing
// `time-$id` key) — see `_DateStub.build()` — so these finders never need to
// recompute the rendered string via `formatStubDayLine` (M2).

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const String _cardId = 'stub-pos';
// The stub's caption geometry is deliberately exercised at its worst case:
// November renders the genitive «листопада», one of only three months (with
// березня/вересня) whose caption wraps the stub to two lines (see
// _DateStub.width in booking_card.dart) — pinning the month keeps that
// two-line case deterministic across every run, rather than depending on
// which month `DateTime.now()` happens to land in when the suite runs.
// future-date-ok: pinned to a two-line-wrapping month so the stub's worst-case internal line-stacking geometry (asserted above) stays deterministic instead of depending on which month DateTime.now() lands in.
final DateTime _start = DateTime.utc(2026, 11, 28, 15);

/// A confirmed, non-dead, non-struck booking — the baseline card for the
/// geometry assertions, carrying a salon + title so the identity block is at
/// its tallest (worst case for the stub's internal line stacking — see
/// `booking_card_date_stub_vertical_centering_test.dart` for the SEPARATE
/// concern of the stub's position relative to the card, which the deleted
/// `_stubTopOffset` constant used to control).
Booking _booking({BookingStatus status = BookingStatus.confirmed}) {
  return Booking(
    id: _cardId,
    masterId: 'master-$_cardId',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterAvatarUrl: null, // initials disc → no Image.network in the test
    masterType: 'SALON_MASTER',
    salonName: 'Lviv Nails Studio',
    serviceId: 'service-$_cardId',
    serviceName: 'Манікюр з покриттям',
    categoryName: 'NAIL_SERVICE',
    cityLabel: 'Львів',
    districtLabel: 'Залізничний район',
    street: 'вулиця Тестова',
    buildingNo: '15А',
    durationMinutes: 90,
    price: 650,
    startAt: _start,
    endAt: _start.add(const Duration(minutes: 90)),
    status: status,
    canReview: false,
    masterProfessionalTitle: 'Майстриня манікюру',
  );
}

Finder _timeFinder() => find.byKey(const ValueKey<String>('time-$_cardId'));
Finder _dayNumberFinder() =>
    find.byKey(const ValueKey<String>('stub-day-$_cardId'));
Finder _monthLineFinder() =>
    find.byKey(const ValueKey<String>('stub-month-$_cardId'));
Finder _masterNameFinder() =>
    find.byKey(const ValueKey<String>('master-name-$_cardId'));

Future<void> _pumpCard(WidgetTester tester, {BookingStatus? status}) async {
  await tester.pumpApp(
    Scaffold(
      body: BookingCard(
        booking: _booking(status: status ?? BookingStatus.confirmed),
        onOpenDetails: () {},
      ),
    ),
    width: 360,
  );
  await tester.pump();
}

void main() {
  group('BookingCard — slot time position in the date stub (2026-08 move)', () {
    testWidgets('1. the time renders left of the body, not inside it', (
      tester,
    ) async {
      await _pumpCard(tester);

      // The identity row (master name) is the body's FIRST line since this
      // move (see the library doc). If the time ever moved back into the
      // body — top-right `Align` or anywhere else in that Column — its rect
      // would overlap or sit to the RIGHT of the identity text, because the
      // body only starts after the stub + its gutter. Sitting strictly to
      // the left of the body's own first line is exactly the property that
      // breaks the instant the time leaves the stub.
      final double timeRight = tester.getTopRight(_timeFinder()).dx;
      final double bodyLeft = tester.getTopLeft(_masterNameFinder()).dx;

      expect(
        timeRight,
        lessThan(bodyLeft),
        reason:
            'the time (ValueKey time-$_cardId) must sit entirely left of '
            "the body's first line (master name) — inside the date stub's "
            'column, not the body. If this fails the time has drifted back '
            "into _body(), reversing the 2026-08 move.",
      );
    });

    testWidgets(
      '2. the time sits below the day number and the month/weekday line',
      (tester) async {
        await _pumpCard(tester);

        final double dayNumberBottom = tester
            .getBottomLeft(_dayNumberFinder())
            .dy;
        final double monthLineBottom = tester
            .getBottomLeft(_monthLineFinder())
            .dy;
        final double timeTop = tester.getTopLeft(_timeFinder()).dy;

        expect(
          timeTop,
          greaterThan(dayNumberBottom),
          reason: 'the time must render BELOW the day number, not above it',
        );
        expect(
          timeTop,
          greaterThan(monthLineBottom),
          reason:
              'the time must render BELOW the month/weekday caption line — '
              'it is the THIRD stacked line in the stub, not the second',
        );
      },
    );

    testWidgets(
      "3. the time's horizontal centre aligns with the day number's centre",
      (tester) async {
        await _pumpCard(tester);

        final double dayNumberCentre = tester.getCenter(_dayNumberFinder()).dx;
        final double timeCentre = tester.getCenter(_timeFinder()).dx;

        expect(
          timeCentre,
          closeTo(dayNumberCentre, 0.5),
          reason:
              'the time shares the centred stub column with the day number '
              '(CrossAxisAlignment.center on the _DateStub Column) — a '
              'centre this far off means the time is no longer laid out '
              'inside that column',
        );
      },
    );

    testWidgets(
      '4a. a no-show booking strikes the time through, in its new home',
      (tester) async {
        await _pumpCard(tester, status: BookingStatus.notCompleted);

        final Text time = tester.widget<Text>(_timeFinder());
        expect(
          time.style?.decoration,
          TextDecoration.lineThrough,
          reason:
              'the no-show strike-through moved WITH the time into the date '
              'stub — _isNoShow must still reach the relocated Text',
        );
      },
    );

    testWidgets(
      '4b. a confirmed (non-dead, non-struck) time carries no strike and the '
      'lit accent colour',
      (tester) async {
        await _pumpCard(tester);

        final Text time = tester.widget<Text>(_timeFinder());
        expect(time.style?.decoration, TextDecoration.none);
        expect(time.style?.color, BrandColors.accentDeep);
      },
    );

    testWidgets(
      '4c. a cancelled (dead) booking mutes the time colour, in its new home',
      (tester) async {
        await _pumpCard(tester, status: BookingStatus.cancelled);

        final Text time = tester.widget<Text>(_timeFinder());
        expect(
          time.style?.color,
          BrandColors.muted,
          reason:
              'the dead-card mute (dimmed → BrandColors.muted) moved WITH '
              'the time into the date stub — _isDead must still reach the '
              'relocated Text',
        );
      },
    );
  });
}
