// Phase 267 — unit tests for [SalonServiceBooking] (D1/D2).
//
// Pure Dart: no ProviderScope, no widget tree.
//
// D2 fixture note: [_serviceDefId] and [_masterServiceId] below are
// deliberately VISIBLY DISTINCT literal strings (a salon-catalogue-shaped id
// vs a per-master-assignment-shaped id), not two random UUIDs that merely
// happen to differ. A fixture where both ids collide would make
// `should_carryTheAssignmentIdNotTheDefinitionId_when_buildingTheCreateRequest`
// vacuous — see the phase doc's mutation-check note.

import 'package:beautica_mobile/features/booking/domain/create_booking_request.dart';
import 'package:beautica_mobile/features/booking/domain/salon_service_booking.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:flutter_test/flutter_test.dart';

const String _serviceDefId = 'svcdef-nails-001';
const String _masterServiceId = 'msvc-anna-nails-001';

const SalonCatalogService _catalogService = SalonCatalogService(
  id: _serviceDefId,
  name: 'Манікюр класичний',
  durationLabel: '1 год',
  priceDisplay: '500 ₴',
);

const SalonMasterSummary _master = SalonMasterSummary(
  masterId: 'master-anna-1',
  firstName: 'Анна',
  lastName: 'Коваль',
  type: MasterType.salonMaster,
);

SalonServiceBooking _unassigned() => const SalonServiceBooking(
  service: _catalogService,
  serviceDefId: _serviceDefId,
);

SalonServiceBooking _assignedAndScheduled({
  DateTime? startAt,
  int? durationMinutes,
}) => SalonServiceBooking(
  service: _catalogService,
  serviceDefId: _serviceDefId,
  masterId: _master.masterId,
  masterServiceId: _masterServiceId,
  master: _master,
  startAt: startAt ?? DateTime.utc(2020, 7, 10, 11),
  durationMinutes: durationMinutes ?? 60,
  idempotencyKey: 'idem-key-1',
);

void main() {
  group('endAt', () {
    test('should_computeEndAtFromStartAtPlusDuration_when_bothAreSet', () {
      final booking = _assignedAndScheduled(
        startAt: DateTime.utc(2020, 7, 10, 11),
        durationMinutes: 90,
      );

      expect(booking.endAt, DateTime.utc(2020, 7, 10, 12, 30));
    });

    test('is null when startAt is unset', () {
      final booking = _unassigned().copyWith(durationMinutes: 60);

      expect(booking.endAt, isNull);
    });

    test('is null when durationMinutes is unset', () {
      final booking = _unassigned().copyWith(
        startAt: DateTime.utc(2020, 7, 10, 11),
      );

      expect(booking.endAt, isNull);
    });
  });

  group('toCreateBookingRequest', () {
    test(
      'should_carryTheAssignmentIdNotTheDefinitionId_when_buildingTheCreateRequest',
      () {
        final booking = _assignedAndScheduled();

        final CreateBookingRequest request = booking.toCreateBookingRequest();

        expect(
          request.serviceId,
          _masterServiceId,
          reason:
              'the wire needs the per-master ASSIGNMENT id — D2. Sending '
              'serviceDefId 404s server-side ("Master service not found").',
        );
        expect(request.serviceId, isNot(_serviceDefId));
        expect(request.masterId, _master.masterId);
        expect(request.idempotencyKey, 'idem-key-1');
      },
    );

    test('carries clientComment through when given', () {
      final booking = _assignedAndScheduled();

      final CreateBookingRequest request = booking.toCreateBookingRequest(
        clientComment: 'Please arrive on time',
      );

      expect(request.clientComment, 'Please arrive on time');
    });

    test('throws StateError when the entry is not yet assigned', () {
      final booking = _unassigned();

      expect(booking.toCreateBookingRequest, throwsStateError);
    });

    test('throws StateError when the entry is not yet scheduled', () {
      final booking = _unassigned().copyWith(
        masterId: _master.masterId,
        masterServiceId: _masterServiceId,
        master: _master,
        idempotencyKey: 'idem-key-1',
      );

      expect(booking.toCreateBookingRequest, throwsStateError);
    });
  });
}
