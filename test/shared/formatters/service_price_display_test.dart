// Tests for ServicePriceDisplay — the service-card price label builder.
//
// FIXED  → server-formatted priceDisplay passes through ("750 ₴").
// RANGE  → reformatted client-side to a hyphenated band ("200 - 600 ₴"),
//          NOT the server's "від … до …" phrasing.

import 'package:beautica_mobile/features/services/domain/master_service.dart';
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
}
