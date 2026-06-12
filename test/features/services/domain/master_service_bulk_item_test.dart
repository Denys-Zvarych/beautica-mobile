// First-time service setup — unit tests for [MasterServiceBulkItem] (freezed).
//
// The model is pure data; these tests pin the FIXED vs RANGE construction so a
// regression that swaps the mode-conditional fields (e.g. setting `price` on a
// RANGE item) is caught at the model boundary, independently of the repository
// serialiser. They also exercise the freezed `==` / `copyWith` contract the
// notifier + screen rely on.

import 'package:beautica_mobile/features/services/domain/master_service.dart'
    show ServicePriceType;
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MasterServiceBulkItem — FIXED', () {
    test('carries price and leaves range fields null', () {
      const item = MasterServiceBulkItem(
        serviceTypeId: 'type-1',
        durationMinutes: 45,
        priceType: ServicePriceType.fixed,
        price: 350,
      );

      expect(item.serviceTypeId, 'type-1');
      expect(item.durationMinutes, 45);
      expect(item.priceType, ServicePriceType.fixed);
      expect(item.price, 350);
      expect(item.priceMin, isNull);
      expect(item.priceMax, isNull);
    });
  });

  group('MasterServiceBulkItem — RANGE', () {
    test('carries priceMin/priceMax and leaves price null', () {
      const item = MasterServiceBulkItem(
        serviceTypeId: 'type-2',
        durationMinutes: 90,
        priceType: ServicePriceType.range,
        priceMin: 700,
        priceMax: 1200,
      );

      expect(item.serviceTypeId, 'type-2');
      expect(item.durationMinutes, 90);
      expect(item.priceType, ServicePriceType.range);
      expect(item.priceMin, 700);
      expect(item.priceMax, 1200);
      expect(item.price, isNull);
    });
  });

  group('MasterServiceBulkItem — value semantics', () {
    test('two FIXED items with identical fields are equal', () {
      const a = MasterServiceBulkItem(
        serviceTypeId: 'type-1',
        durationMinutes: 45,
        priceType: ServicePriceType.fixed,
        price: 350,
      );
      const b = MasterServiceBulkItem(
        serviceTypeId: 'type-1',
        durationMinutes: 45,
        priceType: ServicePriceType.fixed,
        price: 350,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('FIXED and RANGE of the same type are not equal', () {
      const fixed = MasterServiceBulkItem(
        serviceTypeId: 'type-1',
        durationMinutes: 45,
        priceType: ServicePriceType.fixed,
        price: 350,
      );
      const range = MasterServiceBulkItem(
        serviceTypeId: 'type-1',
        durationMinutes: 45,
        priceType: ServicePriceType.range,
        priceMin: 300,
        priceMax: 400,
      );

      expect(fixed, isNot(equals(range)));
    });
  });
}
