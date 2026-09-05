// Phase 21.5 QA gap-closure (mobile-qa) — unit tests for
// [salonStaffMemberProfileProvider] (`salon_staff_member_notifier.dart`).
//
// Before this file: `grep -rln "SalonStaffMemberNotifier"` returned ZERO
// hits — the provider that resolves ONE roster entry (master or admin) by
// [memberId] out of the already-cached [salonManagementProfileProvider], and
// that decides whether to additionally fetch the master's active services,
// had no coverage at all.
//
// Pins:
//   1. Resolution by [memberId] — the roster entry actually returned matches
//      the requested id, not just "the first one" (fixture carries TWO
//      entries so a bug that always returns index 0 would be caught).
//   2. A MASTER entry additionally fetches `getMasterServices(masterId)` —
//      the RIGHT masterId, not the roster's userId (they deliberately
//      differ in the fixture below to make that distinction provable).
//   3. An ADMIN entry does NOT call `getMasterServices` at all — verified via
//      `verifyNever`, not just "services came back empty" (which could also
//      be produced by a broken call that happens to return nothing).
//   4. An unresolvable memberId throws [NotFoundFailure] — fails closed
//      rather than rendering blank.
//
// Isolation: [salonManagementProfileProvider] is overridden with a
// synchronously-resolving stub (mirrors
// `salon_management_profile_screen_test.dart`'s own
// `_AttemptCountingSalonManagementProfile` pattern) so no real
// `salonRepositoryProvider`/Dio/auth I/O happens; [publicServiceRepositoryProvider]
// is a mocktail mock. Retry disabled (`retry: (_, _) => null`) on every
// container, mirroring `public_master_profile_notifier_test.dart`'s own
// rationale — deterministic AsyncError settling, no Riverpod auto-retry
// re-running a failing/throwing build mid-assertion.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_staff_member_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockServiceRepository extends Mock implements ServiceRepository {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const String _kSalonId = 'salon-1';
const String _kMasterUserId = 'user-master-1';

/// Deliberately DIFFERENT from [_kMasterUserId] — proves the notifier fetches
/// services keyed on `member.masterId` (the Master row id), not the roster's
/// `userId` (the User row id), which a copy-paste bug could easily conflate.
const String _kMasterRowId = 'master-row-77';
const String _kAdminUserId = 'user-admin-1';

const _stubSalon = Salon(id: _kSalonId, name: 'Салон «Тест»');

const _masterMember = SalonStaffMember(
  userId: _kMasterUserId,
  masterId: _kMasterRowId,
  role: SalonStaffRole.master,
  firstName: 'Олена',
  lastName: 'Ковальчук',
);

const _adminMember = SalonStaffMember(
  userId: _kAdminUserId,
  role: SalonStaffRole.admin,
  firstName: 'Ірина',
  lastName: 'Ковальська',
);

const _staff = <SalonStaffMember>[_masterMember, _adminMember];

const _services = <MasterService>[
  MasterService(
    id: 'svc-1',
    serviceDefId: 'def-1',
    name: 'Манікюр з покриттям',
    durationMinutes: 90,
    priceMin: 500,
    priceDisplay: '500 ₴',
    category: 'NAILS',
  ),
];

/// [SalonManagementProfile] stub whose `build()` returns [_staff] against
/// [_kSalonId] immediately — sidesteps the real `authProvider`/
/// `salonRepositoryProvider` machinery entirely (this provider under test
/// never watches either directly; it only watches
/// `salonManagementProfileProvider(...).future`).
class _StubSalonManagementProfile extends SalonManagementProfile {
  @override
  Future<SalonManagementProfileData> build(String salonId) async =>
      (_stubSalon, _staff);
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

ProviderContainer _makeContainer({ServiceRepository? serviceRepo}) {
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      salonManagementProfileProvider(
        _kSalonId,
      ).overrideWith(_StubSalonManagementProfile.new),
      if (serviceRepo != null)
        publicServiceRepositoryProvider.overrideWithValue(serviceRepo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('salonStaffMemberProfile — resolution by memberId', () {
    test('resolves the roster entry matching memberId, ignoring the other '
        'entry in the roster', () async {
      final serviceRepo = _MockServiceRepository();
      when(
        () => serviceRepo.getMasterServices(any()),
      ).thenAnswer((_) async => const <MasterService>[]);
      final container = _makeContainer(serviceRepo: serviceRepo);

      final SalonStaffMemberProfileData adminResult = await container.read(
        salonStaffMemberProfileProvider(_kSalonId, _kAdminUserId).future,
      );
      expect(adminResult.$1, _adminMember);
      expect(adminResult.$1.userId, _kAdminUserId);

      final SalonStaffMemberProfileData masterResult = await container.read(
        salonStaffMemberProfileProvider(_kSalonId, _kMasterUserId).future,
      );
      expect(masterResult.$1, _masterMember);
      expect(masterResult.$1.userId, _kMasterUserId);
    });

    test('an unresolvable memberId throws NotFoundFailure — fails closed, '
        'never a blank render', () async {
      final container = _makeContainer();

      await expectLater(
        container.read(
          salonStaffMemberProfileProvider(_kSalonId, 'ghost-id').future,
        ),
        throwsA(isA<NotFoundFailure>()),
      );
    });
  });

  group('salonStaffMemberProfile — services fetch is role-gated', () {
    test(
      'a MASTER entry fetches active services via getMasterServices(masterId) '
      '— the Master-row id, not the roster userId',
      () async {
        final serviceRepo = _MockServiceRepository();
        when(
          () => serviceRepo.getMasterServices(_kMasterRowId),
        ).thenAnswer((_) async => _services);
        final container = _makeContainer(serviceRepo: serviceRepo);

        final SalonStaffMemberProfileData result = await container.read(
          salonStaffMemberProfileProvider(_kSalonId, _kMasterUserId).future,
        );

        expect(result.$1, _masterMember);
        expect(result.$2, _services);
        verify(() => serviceRepo.getMasterServices(_kMasterRowId)).called(1);
      },
    );

    test('an ADMIN entry does NOT call getMasterServices at all, and its '
        'services list is empty', () async {
      final serviceRepo = _MockServiceRepository();
      final container = _makeContainer(serviceRepo: serviceRepo);

      final SalonStaffMemberProfileData result = await container.read(
        salonStaffMemberProfileProvider(_kSalonId, _kAdminUserId).future,
      );

      expect(result.$1, _adminMember);
      expect(result.$2, isEmpty);
      verifyNever(() => serviceRepo.getMasterServices(any()));
    });
  });
}
