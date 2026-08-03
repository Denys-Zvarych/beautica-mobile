// Regression guard for the 2026-08 UTC-day-boundary bug: `_DateStub`'s day
// number line read `start.day.toString()` off the raw UTC instant while its
// two sibling lines (`formatStubDayLine`, the slot time) already converted to
// the Europe/Kyiv wall-clock via `toBeauticaTime` first. Kyiv is always AHEAD
// of UTC (EET +2 / EEST +3), so a late-evening UTC instant is already the
// next Kyiv calendar day — near that boundary the day number printed a date
// that disagreed with the weekday/month caption beside it, and could name a
// date that does not exist on the real calendar (worked example: 18 June
// 2026 has no Friday, but the pre-fix card paired day-number "18" with the
// correct "пт" caption whenever `startAt` fell late enough in UTC).
//
// `booking_card_date_stub_time_position_test.dart`, this file's sibling,
// only ever renders `DateTime.utc(2026, 11, 28, 15)` — mid-UTC-day, so its
// suite is green whether or not this bug is present. It also asserts
// GEOMETRY only ("every assertion below is GEOMETRY against keyed finders...
// never a find.byType(_DateStub) lookup" — see that file's header), so this
// is a NEW sibling file rather than an addition there: mixing literal-string
// content assertions into a geometry-only file would blur its one job. Same
// scaffold/idiom otherwise (imports, `_booking()` builder, `_pumpCard`
// helper, keyed `Finder`s).
//
// `booking_date_labels_test.dart` pins the underlying formatters directly at
// the unit level (including this exact bug, with the same two fixtures);
// this file additionally proves the full `BookingCard` widget wires those
// formatters into the stub correctly end-to-end.

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const String _cardId = 'stub-kyiv-boundary';

Booking _booking(DateTime startAt) {
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
    categoryName: 'Манікюр',
    cityLabel: 'Львів',
    districtLabel: 'Залізничний район',
    street: 'вулиця Тестова',
    buildingNo: '15А',
    durationMinutes: 90,
    price: 650,
    startAt: startAt,
    endAt: startAt.add(const Duration(minutes: 90)),
    status: BookingStatus.confirmed,
    canReview: false,
    masterProfessionalTitle: 'Майстриня манікюру',
  );
}

Finder _dayNumberFinder() =>
    find.byKey(const ValueKey<String>('stub-day-$_cardId'));
Finder _monthLineFinder() =>
    find.byKey(const ValueKey<String>('stub-month-$_cardId'));
Finder _timeFinder() => find.byKey(const ValueKey<String>('time-$_cardId'));

Future<void> _pumpCard(WidgetTester tester, DateTime startAt) async {
  await tester.pumpApp(
    Scaffold(
      body: BookingCard(booking: _booking(startAt), onOpenDetails: () {}),
    ),
    width: 360,
  );
  await tester.pump();
}

void main() {
  group('BookingCard date stub — UTC day-boundary near midnight Kyiv', () {
    testWidgets(
      'summer/EEST: 2026-06-18T22:30Z renders as Friday the 19th, not '
      'Thursday the 18th',
      (tester) async {
        final DateTime start = DateTime.utc(2026, 6, 18, 22, 30);
        await _pumpCard(tester, start);

        final Text day = tester.widget<Text>(_dayNumberFinder());
        final Text month = tester.widget<Text>(_monthLineFinder());
        final Text time = tester.widget<Text>(_timeFinder());

        expect(
          day.data,
          '19',
          reason:
              'the day number must read the Kyiv calendar day (19th); the '
              'pre-fix bug rendered the raw UTC day (18th) instead — and 18 '
              'June 2026 is a Thursday, never a Friday, so pairing it with '
              'the correct "пт" caption below produced a date that cannot '
              'exist',
        );
        expect(month.data, 'червня, пт');
        expect(time.data, '01:30');
      },
    );

    testWidgets(
      'winter/EET: 2026-01-18T22:30Z renders as Monday the 19th, not Sunday '
      'the 18th — proves DST-awareness, not a hardcoded +3 offset',
      (tester) async {
        final DateTime start = DateTime.utc(2026, 1, 18, 22, 30);
        await _pumpCard(tester, start);

        final Text day = tester.widget<Text>(_dayNumberFinder());
        final Text month = tester.widget<Text>(_monthLineFinder());
        final Text time = tester.widget<Text>(_timeFinder());

        expect(day.data, '19');
        expect(month.data, 'січня, пн');
        expect(time.data, '00:30');
      },
    );

    testWidgets(
      'the day number and the month/weekday caption always describe the '
      'same calendar date — the invariant the bug violated',
      (tester) async {
        // Independent re-derivation, not a second copy of the literal
        // expectations above: parse the rendered day number, build a plain
        // Gregorian date from it (Dart core `DateTime(y, m, d).weekday` —
        // NOT `toBeauticaTime`, so this does not exercise the same
        // conversion the fix performs), and confirm that weekday is the one
        // actually printed in the caption below it.
        final DateTime start = DateTime.utc(2026, 6, 18, 22, 30);
        await _pumpCard(tester, start);

        final int renderedDay = int.parse(
          tester.widget<Text>(_dayNumberFinder()).data!,
        );
        final String renderedCaption = tester
            .widget<Text>(_monthLineFinder())
            .data!;
        final int trueWeekday = DateTime(2026, 6, renderedDay).weekday;
        const List<String> weekdayAbbrevByIndex = <String>[
          'пн',
          'вт',
          'ср',
          'чт',
          'пт',
          'сб',
          'нд',
        ];
        final String expectedAbbrev = weekdayAbbrevByIndex[trueWeekday - 1];

        expect(
          renderedCaption,
          endsWith(', $expectedAbbrev'),
          reason:
              'day number $renderedDay and caption "$renderedCaption" must '
              'name the same weekday; a raw-UTC day paired with a '
              'Kyiv-converted weekday is exactly the bug this test pins',
        );
      },
    );
  });
}
