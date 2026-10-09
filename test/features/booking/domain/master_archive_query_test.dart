// Phase 382 (24.1e) — MasterArchiveQuery's owner-as-master scope flag. It
// keys `masterArchiveProvider`'s family, so the owner's own archive must
// never share a cache entry with the default `/bookings/me` scope.

import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/master_archive_query.dart';

void main() {
  group('MasterArchiveQuery.asOwnerMaster (phase 382)', () {
    test('defaults to false; the default key equals the pre-382 value', () {
      final MasterArchiveQuery q = MasterArchiveQuery.of();
      expect(q.asOwnerMaster, isFalse);
      expect(
        q,
        const MasterArchiveQuery.raw(
          statuses: <BookingStatus>[],
          serviceIds: <String>[],
          salonId: null,
        ),
      );
    });

    test('asOwnerMaster: true is a DISTINCT key from the default', () {
      final MasterArchiveQuery own = MasterArchiveQuery.of(asOwnerMaster: true);
      expect(own.asOwnerMaster, isTrue);
      expect(own, isNot(MasterArchiveQuery.of()));
      expect(own.hashCode, isNot(MasterArchiveQuery.of().hashCode));
      expect(own, MasterArchiveQuery.of(asOwnerMaster: true));
    });

    test('the flag is a scope, not a filter — hasFilters ignores it', () {
      expect(MasterArchiveQuery.of(asOwnerMaster: true).hasFilters, isFalse);
    });

    test('rejects asOwnerMaster combined with a salon scope', () {
      expect(
        () => MasterArchiveQuery.of(salonId: 'salon-1', asOwnerMaster: true),
        throwsArgumentError,
      );
    });
  });
}
