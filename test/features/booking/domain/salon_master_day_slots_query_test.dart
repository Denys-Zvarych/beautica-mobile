// MO-2 — Unit tests for [SalonMasterDaySlotsQuery], the family key backing
// `salonMasterDaySlotsProvider`.
//
// MO-2 widened the single `serviceId` (the master's PRIMARY assignment id) to
// an ordered `List<String> serviceIds`. Today the salon flow still passes the
// single primary assignment as a one-element list; the multi-service summed
// block is wired in MO-3/MO-4. This pins the family-cache properties: DEEP,
// ORDER-SENSITIVE value equality; a one-element list keys the SAME member as
// pre-MO-2 (single-service cache behaviour unchanged); and time-of-day is
// truncated at construction.
//
// Pure Dart: no ProviderScope, no widget tree.

import 'package:beautica_mobile/features/booking/domain/salon_master_day_slots_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const masterId = 'master-1';
  final DateTime jul14 = DateTime(2026, 7, 14);

  group('SalonMasterDaySlotsQuery — serviceIds value equality', () {
    test('N=1 identity: two one-element ["x"] queries are equal with equal '
        'hashCode — same family member as the pre-MO-2 single-service key', () {
      final a = SalonMasterDaySlotsQuery(
        masterId: masterId,
        serviceIds: <String>['assign-1'],
        date: jul14,
      );
      final b = SalonMasterDaySlotsQuery(
        masterId: masterId,
        serviceIds: <String>['assign-1'],
        date: jul14,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test(
      'order is significant: [a,b] and [b,a] are DISTINCT family members',
      () {
        final ab = SalonMasterDaySlotsQuery(
          masterId: masterId,
          serviceIds: <String>['assign-a', 'assign-b'],
          date: jul14,
        );
        final ba = SalonMasterDaySlotsQuery(
          masterId: masterId,
          serviceIds: <String>['assign-b', 'assign-a'],
          date: jul14,
        );

        expect(ab == ba, isFalse);
        expect(ab.hashCode == ba.hashCode, isFalse);
      },
    );

    test('different assignment ids → not equal', () {
      final a = SalonMasterDaySlotsQuery(
        masterId: masterId,
        serviceIds: <String>['assign-1'],
        date: jul14,
      );
      final b = SalonMasterDaySlotsQuery(
        masterId: masterId,
        serviceIds: <String>['assign-2'],
        date: jul14,
      );

      expect(a == b, isFalse);
    });
  });

  group('SalonMasterDaySlotsQuery — construction-time normalisation', () {
    test('truncates time-of-day so two same-date selections stay ==-equal', () {
      final withTime = SalonMasterDaySlotsQuery(
        masterId: masterId,
        serviceIds: <String>['assign-1'],
        date: DateTime(2026, 7, 14, 13),
      );
      final dateOnly = SalonMasterDaySlotsQuery(
        masterId: masterId,
        serviceIds: <String>['assign-1'],
        date: DateTime(2026, 7, 14),
      );

      expect(withTime.date, DateTime(2026, 7, 14));
      expect(withTime, dateOnly);
      expect(withTime.hashCode, dateOnly.hashCode);
    });

    test('different masterId or date → distinct family members', () {
      final base = SalonMasterDaySlotsQuery(
        masterId: masterId,
        serviceIds: <String>['assign-1'],
        date: jul14,
      );
      final otherMaster = SalonMasterDaySlotsQuery(
        masterId: 'master-2',
        serviceIds: <String>['assign-1'],
        date: jul14,
      );
      final otherDate = SalonMasterDaySlotsQuery(
        masterId: masterId,
        serviceIds: <String>['assign-1'],
        date: DateTime(2026, 7, 15),
      );

      expect(base == otherMaster, isFalse);
      expect(base == otherDate, isFalse);
    });
  });
}
