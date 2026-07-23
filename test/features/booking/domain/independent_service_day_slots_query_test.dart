// MO-2 — Unit tests for [IndependentServiceDaySlotsQuery], the family key
// backing `independentServiceDaySlotsProvider`.
//
// MO-2 widened the single `serviceId` to an ordered `List<String> serviceIds`.
// This pins the properties the family cache leans on: value equality over the
// list is DEEP and ORDER-SENSITIVE (freezed `DeepCollectionEquality`), a
// one-element `['x']` list keys the SAME family member as pre-MO-2 (single-
// service cache behaviour unchanged), and time-of-day is truncated at
// construction so re-selecting the same calendar day never forks the cache.
//
// Pure Dart: no ProviderScope, no widget tree.

import 'package:beautica_mobile/features/booking/domain/independent_service_day_slots_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const masterId = 'master-1';
  final DateTime jul14 = DateTime(2026, 7, 14);

  group('IndependentServiceDaySlotsQuery — serviceIds value equality', () {
    test('N=1 identity: two one-element ["x"] queries are equal with equal '
        'hashCode — same family member as the pre-MO-2 single-service key', () {
      final a = IndependentServiceDaySlotsQuery(
        masterId: masterId,
        serviceIds: <String>['svc-1'],
        date: jul14,
      );
      final b = IndependentServiceDaySlotsQuery(
        masterId: masterId,
        serviceIds: <String>['svc-1'],
        date: jul14,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('same multi-service selection in the same order is equal with equal '
        'hashCode', () {
      final a = IndependentServiceDaySlotsQuery(
        masterId: masterId,
        serviceIds: <String>['svc-a', 'svc-b'],
        date: jul14,
      );
      final b = IndependentServiceDaySlotsQuery(
        masterId: masterId,
        serviceIds: <String>['svc-a', 'svc-b'],
        date: jul14,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('order is significant: [a,b] and [b,a] are DISTINCT family members '
        '(back-to-back running order changes the summed-block layout)', () {
      final ab = IndependentServiceDaySlotsQuery(
        masterId: masterId,
        serviceIds: <String>['svc-a', 'svc-b'],
        date: jul14,
      );
      final ba = IndependentServiceDaySlotsQuery(
        masterId: masterId,
        serviceIds: <String>['svc-b', 'svc-a'],
        date: jul14,
      );

      expect(ab == ba, isFalse);
      expect(ab.hashCode == ba.hashCode, isFalse);
    });

    test('different serviceIds content → not equal', () {
      final a = IndependentServiceDaySlotsQuery(
        masterId: masterId,
        serviceIds: <String>['svc-1'],
        date: jul14,
      );
      final b = IndependentServiceDaySlotsQuery(
        masterId: masterId,
        serviceIds: <String>['svc-2'],
        date: jul14,
      );

      expect(a == b, isFalse);
    });
  });

  group(
    'IndependentServiceDaySlotsQuery — construction-time normalisation',
    () {
      test(
        'truncates time-of-day so two same-date selections stay ==-equal',
        () {
          final withTime = IndependentServiceDaySlotsQuery(
            masterId: masterId,
            serviceIds: <String>['svc-1'],
            date: DateTime(2026, 7, 14, 16, 45, 30),
          );
          final dateOnly = IndependentServiceDaySlotsQuery(
            masterId: masterId,
            serviceIds: <String>['svc-1'],
            date: DateTime(2026, 7, 14),
          );

          expect(withTime.date, DateTime(2026, 7, 14));
          expect(withTime, dateOnly);
          expect(withTime.hashCode, dateOnly.hashCode);
        },
      );

      test('different masterId or date → distinct family members', () {
        final base = IndependentServiceDaySlotsQuery(
          masterId: masterId,
          serviceIds: <String>['svc-1'],
          date: jul14,
        );
        final otherMaster = IndependentServiceDaySlotsQuery(
          masterId: 'master-2',
          serviceIds: <String>['svc-1'],
          date: jul14,
        );
        final otherDate = IndependentServiceDaySlotsQuery(
          masterId: masterId,
          serviceIds: <String>['svc-1'],
          date: DateTime(2026, 7, 15),
        );

        expect(base == otherMaster, isFalse);
        expect(base == otherDate, isFalse);
      });
    },
  );
}
