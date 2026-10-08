// Phase 377 (24.4) + audit-fix — serviceIdentityLockProvider: verdict from the
// roster's owner row + that master's ACTIVE services; `pending` while either
// read is loading; fail-open (`unlocked`) on error / no owner row / owner viewer.
// ownerMasterServiceDefIdsProvider (the async fetch it composes) stays: it is
// the only place the owner's catalogue is read and gives the derived provider
// its own loading/error edge.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/master/domain/master.dart'
    show MasterType;
import 'package:beautica_mobile/features/salon/application/salon_manage_capability.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/services/application/owner_performed_services_provider.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/test_container.dart';

const String _kSalon = 'salon-1';

const SalonStaffMember _owner = SalonStaffMember(
  userId: 'u-owner',
  masterId: 'm-owner',
  role: SalonStaffRole.master,
  masterType: MasterType.salonOwner,
  firstName: 'О',
  lastName: 'В',
);
const SalonStaffMember _other = SalonStaffMember(
  userId: 'u-2',
  masterId: 'm-2',
  role: SalonStaffRole.master,
  firstName: 'М',
  lastName: 'Н',
);

MasterService _svc(String defId, {bool active = true}) => MasterService(
  id: 'a-$defId',
  serviceDefId: defId,
  name: defId,
  durationMinutes: 30,
  priceType: ServicePriceType.fixed,
  priceMin: 100,
  priceDisplay: '100',
  isActive: active,
);

class _MockRepo extends Mock implements ServiceRepository {}

class _Roster extends SalonManagementProfile {
  _Roster(this._build);
  final Future<SalonManagementProfileData> Function() _build;
  @override
  Future<SalonManagementProfileData> build(String salonId) => _build();
}

SalonManagementProfileData _rosterOf(List<SalonStaffMember> staff) =>
    (const Salon(id: _kSalon, name: 'S'), staff);

void main() {
  late _MockRepo repo;

  setUp(() => repo = _MockRepo());

  ProviderContainer make(
    Future<SalonManagementProfileData> Function() roster, {
    bool viewerOwns = false,
  }) => makeTestContainer(
    overrides: <Object>[
      viewerOwnsSalonProvider(_kSalon).overrideWithValue(viewerOwns),
      salonManagementProfileProvider.overrideWith(() => _Roster(roster)),
      publicServiceRepositoryProvider.overrideWithValue(repo),
    ],
  );

  ServiceIdentityLock lockOf(ProviderContainer c, [String def = 'd1']) =>
      c.read(serviceIdentityLockProvider(_kSalon, def));

  /// Listens (keeps the autoDispose chain alive) and lets the reads settle.
  Future<void> settle(ProviderContainer c, {String def = 'd1'}) async {
    final ProviderSubscription<ServiceIdentityLock> sub = c.listen(
      serviceIdentityLockProvider(_kSalon, def),
      (_, _) {},
    );
    addTearDown(sub.close);
    for (int i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test(
    'locked when the owner row performs the def (ACTIVE services)',
    () async {
      when(
        () => repo.getMasterServices('m-owner'),
      ).thenAnswer((_) async => <MasterService>[_svc('d1'), _svc('d2')]);
      final c = make(() async => _rosterOf(<SalonStaffMember>[_other, _owner]));

      await settle(c);
      expect(lockOf(c), ServiceIdentityLock.locked);
      expect(lockOf(c, 'd2'), ServiceIdentityLock.locked);
      verify(() => repo.getMasterServices('m-owner')).called(1);
      verifyNever(() => repo.getMasterServices('m-2'));
    },
  );

  test('unlocked for a def the owner does not perform', () async {
    when(
      () => repo.getMasterServices('m-owner'),
    ).thenAnswer((_) async => <MasterService>[_svc('d2')]);
    final c = make(() async => _rosterOf(<SalonStaffMember>[_owner]));

    await settle(c);
    expect(lockOf(c), ServiceIdentityLock.unlocked);
  });

  test('an inactive assignment does not lock', () async {
    when(
      () => repo.getMasterServices('m-owner'),
    ).thenAnswer((_) async => <MasterService>[_svc('d1', active: false)]);
    final c = make(() async => _rosterOf(<SalonStaffMember>[_owner]));

    await settle(c);
    expect(lockOf(c), ServiceIdentityLock.unlocked);
  });

  test('no owner row -> unlocked, no catalogue read', () async {
    final c = make(() async => _rosterOf(<SalonStaffMember>[_other]));

    await settle(c);
    expect(lockOf(c), ServiceIdentityLock.unlocked);
    verifyNever(() => repo.getMasterServices(any()));
  });

  test('the OWNER viewer is unlocked and reads nothing', () async {
    final c = make(
      () async => _rosterOf(<SalonStaffMember>[_owner]),
      viewerOwns: true,
    );

    await settle(c);
    expect(lockOf(c), ServiceIdentityLock.unlocked);
    verifyNever(() => repo.getMasterServices(any()));
  });

  test('PENDING while the roster is loading', () async {
    final Completer<SalonManagementProfileData> gate =
        Completer<SalonManagementProfileData>();
    final c = make(() => gate.future);

    await settle(c);
    expect(lockOf(c), ServiceIdentityLock.pending);
    verifyNever(() => repo.getMasterServices(any()));
  });

  test('PENDING while the owner catalogue is loading, then resolves', () async {
    final Completer<List<MasterService>> gate =
        Completer<List<MasterService>>();
    when(
      () => repo.getMasterServices('m-owner'),
    ).thenAnswer((_) => gate.future);
    final c = make(() async => _rosterOf(<SalonStaffMember>[_owner]));

    await settle(c);
    expect(lockOf(c), ServiceIdentityLock.pending);

    gate.complete(<MasterService>[_svc('d1')]);
    await settle(c);
    expect(lockOf(c), ServiceIdentityLock.locked);
  });

  test('catalogue read FAILS -> unlocked (fail-open)', () async {
    when(
      () => repo.getMasterServices('m-owner'),
    ).thenAnswer((_) async => throw const NetworkFailure());
    final c = make(() async => _rosterOf(<SalonStaffMember>[_owner]));

    await settle(c);
    expect(lockOf(c), ServiceIdentityLock.unlocked);
    verify(() => repo.getMasterServices('m-owner')).called(greaterThan(0));
  });

  test('roster read FAILS -> unlocked (fail-open)', () async {
    final c = make(() async => throw const NetworkFailure());

    await settle(c);
    expect(lockOf(c), ServiceIdentityLock.unlocked);
    verifyNever(() => repo.getMasterServices(any()));
  });

  // Audit-fix cycle 2 — a REFRESH keeps the previous value: never pending.
  test('catalogue REFRESH (loading with a previous value) stays LOCKED, '
      'never pending', () async {
    final Completer<List<MasterService>> second =
        Completer<List<MasterService>>();
    int calls = 0;
    when(() => repo.getMasterServices('m-owner')).thenAnswer((_) {
      calls++;
      return calls == 1
          ? Future<List<MasterService>>.value(<MasterService>[_svc('d1')])
          : second.future;
    });
    final c = make(() async => _rosterOf(<SalonStaffMember>[_owner]));
    await settle(c);
    expect(lockOf(c), ServiceIdentityLock.locked);

    c.invalidate(ownerMasterServiceDefIdsProvider('m-owner'));
    await settle(c);
    expect(calls, 2, reason: 'positive: the refresh really started');
    expect(lockOf(c), ServiceIdentityLock.locked);

    second.complete(<MasterService>[_svc('d2')]);
    await settle(c);
    expect(lockOf(c), ServiceIdentityLock.unlocked);
  });

  test('roster REFRESH (loading with a previous value) stays UNLOCKED for a '
      'def the owner does not perform, never pending', () async {
    when(
      () => repo.getMasterServices('m-owner'),
    ).thenAnswer((_) async => <MasterService>[_svc('d2')]);
    final Completer<SalonManagementProfileData> second =
        Completer<SalonManagementProfileData>();
    int builds = 0;
    final c = make(() {
      builds++;
      return builds == 1
          ? Future<SalonManagementProfileData>.value(
              _rosterOf(<SalonStaffMember>[_owner]),
            )
          : second.future;
    });
    await settle(c);
    expect(lockOf(c), ServiceIdentityLock.unlocked);

    c.invalidate(salonManagementProfileProvider(_kSalon));
    await settle(c);
    expect(builds, 2, reason: 'positive: the refresh really started');
    expect(lockOf(c), ServiceIdentityLock.unlocked);
  });

  test('roster REFRESH keeps LOCKED too (previous value used)', () async {
    when(
      () => repo.getMasterServices('m-owner'),
    ).thenAnswer((_) async => <MasterService>[_svc('d1')]);
    final Completer<SalonManagementProfileData> second =
        Completer<SalonManagementProfileData>();
    int builds = 0;
    final c = make(() {
      builds++;
      return builds == 1
          ? Future<SalonManagementProfileData>.value(
              _rosterOf(<SalonStaffMember>[_owner]),
            )
          : second.future;
    });
    await settle(c);
    expect(lockOf(c), ServiceIdentityLock.locked);

    c.invalidate(salonManagementProfileProvider(_kSalon));
    await settle(c);
    expect(builds, 2);
    expect(lockOf(c), ServiceIdentityLock.locked);
  });
}
