// The DENSE card's height must be a pure function of its floor: a short
// name and a long (first-name-only / ellipsized) name render the SAME box, and it equals
// `MasterBookingCard.occupiedHeightFor(floor, dense: true)` exactly. Otherwise
// the grid's culling placeholder (ADDENDUM 5 / 11) drifts and cards below it
// slide off the hour ruler.

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

// Fixture data, not UI copy.
const String _kShortFirst = 'Іра';
const String _kShortLast = 'Ко';
const String _kShortService = 'Брови';
const String _kLongFirst = 'Олександра';
const String _kLongLast = 'Шевченко-Коваленко';
const String _kLongService =
    'Комплексний догляд за волоссям з ботоксом та укладкою';

/// `TimelineDensity.salon.hourHeight` (120 * 0.7).
const double _kSalonHour = 84;

Booking _booking({
  required int durationMinutes,
  required String first,
  required String last,
  required String service,
  double? priceMax,
  BookingStatus status = BookingStatus.confirmed,
}) {
  // future-date-ok: pinned Kyiv wall-clock fixture.
  final DateTime startAt = DateTime.utc(2026, 7, 20, 6);
  return Booking(
    id: 'dense-h',
    masterId: 'master-1',
    masterFirstName: 'Оля',
    masterLastName: 'Коваль',
    masterType: 'SALON_MASTER',
    clientFirstName: first,
    clientLastName: last,
    serviceId: 'service-1',
    serviceName: service,
    durationMinutes: durationMinutes,
    price: 1250,
    priceMax: priceMax,
    startAt: startAt,
    endAt: startAt.add(Duration(minutes: durationMinutes)),
    status: status,
    canReview: false,
  );
}

double _floor(int minutes) {
  final double proportional = minutes / 60.0 * _kSalonHour;
  return proportional > MasterBookingCard.microLayoutNaturalHeight
      ? proportional
      : MasterBookingCard.microLayoutNaturalHeight;
}

Future<double> _height(
  WidgetTester tester,
  Booking booking,
  double floor,
  double lane,
) async {
  await tester.pumpApp(
    Center(
      child: SizedBox(
        width: lane,
        child: MasterBookingCard(
          booking: booking,
          onTap: () {},
          minHeight: floor,
          dense: true,
          laneWidth: lane,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle(); // AnimatedContainer tweens the floor.
  expect(tester.takeException(), isNull);
  return tester.getSize(find.byType(MasterBookingCard)).height;
}

void main() {
  for (final int minutes in <int>[45, 60, 85, 90, 120]) {
    for (final double lane in <double>[136, 148]) {
      testWidgets('$minutes min @${lane}dp: long == short == predicted', (
        WidgetTester tester,
      ) async {
        final double floor = _floor(minutes);
        final double predicted = MasterBookingCard.occupiedHeightFor(
          floor,
          dense: true,
        );
        final double shortH = await _height(
          tester,
          _booking(
            durationMinutes: minutes,
            first: _kShortFirst,
            last: _kShortLast,
            service: _kShortService,
          ),
          floor,
          lane,
        );
        final double longH = await _height(
          tester,
          _booking(
            durationMinutes: minutes,
            first: _kLongFirst,
            last: _kLongLast,
            service: _kLongService,
            priceMax: 25000,
          ),
          floor,
          lane,
        );
        expect(shortH, closeTo(predicted, 0.01), reason: 'short name');
        expect(longH, closeTo(predicted, 0.01), reason: 'long name');
        expect(longH, closeTo(shortH, 0.01));
      });
    }
  }

  testWidgets('a booking that owes nothing has the same dense height', (
    WidgetTester tester,
  ) async {
    for (final int minutes in <int>[60, 90]) {
      final double floor = _floor(minutes);
      final double predicted = MasterBookingCard.occupiedHeightFor(
        floor,
        dense: true,
      );
      final double h = await _height(
        tester,
        _booking(
          durationMinutes: minutes,
          first: _kLongFirst,
          last: _kLongLast,
          service: _kLongService,
          status: BookingStatus.cancelled,
        ),
        floor,
        136,
      );
      expect(h, closeTo(predicted, 0.01));
    }
  });
}
