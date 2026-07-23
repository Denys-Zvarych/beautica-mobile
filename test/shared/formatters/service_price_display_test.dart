// Tests for ServicePriceDisplay — the service-card price label builder.
//
// FIXED  → server-formatted priceDisplay passes through ("750 ₴").
// RANGE  → reformatted client-side to a hyphenated band ("200 - 600 ₴"),
//          NOT the server's "від … до …" phrasing.

import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/shared/formatters/booking_price_labels.dart';
import 'package:beautica_mobile/shared/formatters/service_price_display.dart';
import 'package:flutter_test/flutter_test.dart';

MasterService _service({
  required ServicePriceType priceType,
  required double priceMin,
  double? priceMax,
  String priceDisplay = '',
}) => MasterService(
  id: 'id',
  serviceDefId: 'def',
  name: 'Test',
  durationMinutes: 30,
  priceType: priceType,
  priceMin: priceMin,
  priceMax: priceMax,
  priceDisplay: priceDisplay,
);

void main() {
  group('ServicePriceDisplay.format', () {
    test('FIXED → passes through the server priceDisplay string', () {
      final s = _service(
        priceType: ServicePriceType.fixed,
        priceMin: 750,
        priceDisplay: '750 ₴',
      );
      expect(ServicePriceDisplay.format(s), '750 ₴');
    });

    test('RANGE → hyphenated band, NOT "від … до …"', () {
      final s = _service(
        priceType: ServicePriceType.range,
        priceMin: 200,
        priceMax: 600,
        // Server would send the "від … до …" form; we ignore it for RANGE.
        priceDisplay: 'від 200 до 600 ${ServicePriceDisplay.suffix}',
      );
      expect(
        ServicePriceDisplay.format(s),
        '200 - 600 ${ServicePriceDisplay.suffix}',
      );
    });

    test('RANGE → whole-hryvnia formatting (no decimals)', () {
      final s = _service(
        priceType: ServicePriceType.range,
        priceMin: 150,
        priceMax: 1200,
        priceDisplay: 'від 150 до 1200 ${ServicePriceDisplay.suffix}',
      );
      expect(
        ServicePriceDisplay.format(s),
        '150 - 1200 ${ServicePriceDisplay.suffix}',
      );
    });

    test('FIXED with empty priceDisplay → falls back to '
        '"<priceMin> <ServicePriceDisplay.suffix>"', () {
      final s = _service(priceType: ServicePriceType.fixed, priceMin: 500);
      expect(
        ServicePriceDisplay.format(s),
        '500 ${ServicePriceDisplay.suffix}',
      );
    });

    test('RANGE with null priceMax → falls back to FIXED behaviour', () {
      final s = _service(
        priceType: ServicePriceType.range,
        priceMin: 300,
        priceDisplay: '300 ₴',
      );
      expect(ServicePriceDisplay.format(s), '300 ₴');
    });
  });

  // ── unrenderable CLIENT-BUILT figures ────────────────────────────────────
  //
  // `_amount` was a bare `toStringAsFixed(0)`, so an Infinity / -0.0 / >=1e21
  // `priceMin`/`priceMax` off the wire rendered as «Infinity ₴» / «-0 ₴» /
  // «1e+21 ₴». That is a real egress, not a UI blemish:
  // `booking_success_screen.dart` hands `ServicePriceDisplay.format(...)`
  // straight to `buildCalendarDescription`, which `add_2_calendar` writes into
  // a device calendar event — the string leaves the app. Same predicate and
  // the same absent-not-stringified semantics as `formatBookingPrice`.
  //
  // The server's own `priceDisplay` passthrough is deliberately NOT covered
  // here: it is a server-controlled string on a description that already
  // carries server-controlled service/master/address text, so it crosses no
  // new trust boundary (rated INFO, explicitly out of scope).
  group('ServicePriceDisplay.format — unrenderable numeric inputs', () {
    const List<double> bad = <double>[
      double.infinity,
      double.negativeInfinity,
      double.nan,
      -500,
      -0.0,
      1e21,
    ];

    test('an unrenderable RANGE ceiling falls back to the FIXED path instead '
        'of banding «200 - Infinity ₴»', () {
      for (final double max in bad) {
        final MasterService s = _service(
          priceType: ServicePriceType.range,
          priceMin: 200,
          priceMax: max,
        );
        expect(
          ServicePriceDisplay.format(s),
          '200 ${ServicePriceDisplay.suffix}',
          reason: 'priceMax $max',
        );
      }
    });

    test('an unrenderable floor with no server string yields the neutral '
        'label and NO currency suffix', () {
      for (final double min in bad) {
        final String label = ServicePriceDisplay.format(
          _service(priceType: ServicePriceType.fixed, priceMin: min),
        );
        expect(label, priceUnavailableLabel, reason: 'priceMin $min');
        expect(
          label.contains(ServicePriceDisplay.suffix),
          isFalse,
          reason: 'priceMin $min must not assert a hryvnia amount',
        );
      }
    });

    test('no client-built output ever contains Infinity, NaN, exponent '
        'notation or a leading minus', () {
      for (final double min in bad) {
        for (final double? max in <double?>[null, 900, double.infinity, -0.0]) {
          final String label = ServicePriceDisplay.format(
            _service(
              priceType: ServicePriceType.range,
              priceMin: min,
              priceMax: max,
            ),
          );
          final String why = 'min $min / max $max';
          expect(label, isNot(contains('Infinity')), reason: why);
          expect(label, isNot(contains('NaN')), reason: why);
          expect(label, isNot(contains('e+')), reason: why);
          expect(label, isNot(contains('-')), reason: why);
        }
      }
    });

    test('POSITIVE zero and every well-formed figure are untouched', () {
      expect(
        ServicePriceDisplay.format(
          _service(priceType: ServicePriceType.fixed, priceMin: 0),
        ),
        '0 ${ServicePriceDisplay.suffix}',
      );
      expect(
        ServicePriceDisplay.format(
          _service(
            priceType: ServicePriceType.range,
            priceMin: 200,
            priceMax: 600,
          ),
        ),
        '200 - 600 ${ServicePriceDisplay.suffix}',
      );
    });
  });
}
