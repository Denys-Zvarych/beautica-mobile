// mobile-qa (2026-09-01) — unit tests for [salonMasterOwnProfileProvider]
// (`salon_master_own_profile_notifier.dart`).
//
// This loader shipped with ZERO direct tests (build-verifier MEDIUM, raised
// twice) — every claim below was previously verifiable only by reading the
// source. Three behaviours are pinned:
//
//   1. OVERLAP — the services read (keyed on Master.id) and the salon read
//      (keyed on Master.salonId) are started TOGETHER, before either is
//      awaited, mirroring `owner_own_profile_notifier_test.dart`'s own
//      Completer-gate technique: the services call is parked on a Completer,
//      and the assertion window is "the salon call has ALREADY happened while
//      services is still pending". A regression that serializes the two reads
//      (`await servicesFuture;` before building `salonFuture`) makes this test
//      fail — see the mutation note on the test itself.
//
//   2. ERROR FOLD — each read folds its OWN failure to an absent result
//      (`[]` / `null`) via `.then(onError: ...)` at creation time, so a
//      failure on one read must NOT take down the other, nor the whole
//      provider.
//
//   3. NULL-SALON SKIP — `master.salonId == null` must issue NO salon network
//      call at all (not "call with a null id").
//
// Every repository failure below is thrown from an ASYNC body
// (`thenAnswer((_) async => throw ...)`), never `thenThrow` — a Dio-backed
// repository always fails asynchronously, and a synchronous throw would
// propagate straight out of the notifier's `await` chain instead of being
// folded by `.then(onError:)`, asserting a shape real users never hit.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/master/application/salon_master_own_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';

class _MockServiceRepository extends Mock implements ServiceRepository {}

class _MockSalonRepository extends Mock implements SalonRepository {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const Master _masterWithSalon = Master(
  id: 'master-row-9',
  firstName: 'Ірина',
  lastName: 'Бондар',
  reviewCount: 0,
  type: MasterType.salonMaster,
  salonId: 'salon-1',
);

const Master _masterNoSalon = Master(
  id: 'master-row-10',
  firstName: 'Ірина',
  lastName: 'Бондар',
  reviewCount: 0,
  type: MasterType.salonMaster,
);

const List<MasterService> _services = <MasterService>[
  MasterService(
    id: 's-1',
    serviceDefId: 'd-1',
    name: 'Стрижка',
    durationMinutes: 45,
    priceMin: 400,
    priceDisplay: '400 ₴',
    category: 'HAIR',
  ),
];

const Salon _salon = Salon(id: 'salon-1', name: 'Beautica Studio');

/// `/masters/me` that resolves IMMEDIATELY with [master] — every test here
/// needs the master leg settled so the assertions land on the services/salon
/// fan-out, never on the master read itself.
class _SettledMasterProfile extends MasterProfile {
  _SettledMasterProfile(this.master);
  final Master master;

  @override
  Future<Master> build() async => master;
}

void main() {
  setUpAll(() {
    registerFallbackValue('');
  });

  ProviderContainer makeContainer({
    required Master master,
    required ServiceRepository serviceRepo,
    SalonRepository? salonRepo,
  }) {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        // This notifier only awaits masterProfileProvider.future — the edge it
        // would otherwise close (masterProfile -> authProvider) is exercised
        // for real by `master_profile_notifier_test.dart` and
        // `provider_cycle_guard_test.dart` (mirrors
        // `owner_own_profile_notifier_test.dart`'s identical stub).
        // cycle-stub-ok: leaf data dep of the notifier under test (see above).
        masterProfileProvider.overrideWith(() => _SettledMasterProfile(master)),
        publicServiceRepositoryProvider.overrideWithValue(serviceRepo),
        if (salonRepo != null)
          salonRepositoryProvider.overrideWithValue(salonRepo),
        // DIRECT override — approvedCategoriesProvider bypasses
        // serviceRepositoryProvider entirely (the established footgun, see
        // `owner_own_profile_notifier_test.dart`). Warmed unconditionally by
        // this loader; stubbed here so the warm-start never hits a real Dio
        // call.
        approvedCategoriesProvider.overrideWith(
          (Ref ref) async => const <ServiceCategoryOption>[],
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Keeps [salonMasterOwnProfileProvider] SUBSCRIBED for the life of the
  /// test — it is `autoDispose`, so a bare `.future` read would tear the
  /// element down the instant the read resolves.
  Future<SalonMasterOwnProfileData> readProfile(ProviderContainer container) {
    final sub = container.listen(salonMasterOwnProfileProvider, (_, _) {});
    addTearDown(sub.close);
    return container.read(salonMasterOwnProfileProvider.future);
  }

  group('overlap — services and salon reads start together', () {
    test('the salon read is ALREADY issued while the services read is still '
        'pending — the two are not serialized', () async {
      final List<String> log = <String>[];

      final servicesGate = Completer<List<MasterService>>();
      final serviceRepo = _MockServiceRepository();
      when(() => serviceRepo.getMasterServices(any())).thenAnswer((_) {
        log.add('services');
        return servicesGate.future;
      });

      final salonRepo = _MockSalonRepository();
      when(() => salonRepo.getSalonById(any())).thenAnswer((_) async {
        log.add('salon');
        return _salon;
      });

      final container = makeContainer(
        master: _masterWithSalon,
        serviceRepo: serviceRepo,
        salonRepo: salonRepo,
      );

      final Future<SalonMasterOwnProfileData> pending = readProfile(container);
      // Let the loader body run up to its first suspension point. `services`
      // is still parked on `servicesGate` for the whole of this window.
      await pumpEventQueue();

      expect(
        servicesGate.isCompleted,
        isFalse,
        reason:
            'sanity: the window this test asserts inside must still be open '
            '— otherwise "already started" proves nothing.',
      );
      expect(
        log,
        containsAll(<String>['services', 'salon']),
        reason:
            'GET /salons/{id} must be started BEFORE GET /masters/{id}/'
            'services resolves. MUTATION CHECK: inserting an `await` on '
            'servicesFuture before building salonFuture (i.e. serializing the '
            'two reads) makes `log` contain only "services" at this point — '
            'this assertion goes red under that mutation.',
      );

      servicesGate.complete(_services);
      final SalonMasterOwnProfileData data = await pending;
      expect(data.$1, _masterWithSalon);
      expect(data.$2, _services);
      expect(data.$3, _salon);
    });
  });

  group('error fold — each read degrades independently', () {
    test('a failed services read degrades to an EMPTY list; the salon read '
        'is unaffected and the provider does not error', () async {
      final serviceRepo = _MockServiceRepository();
      when(
        () => serviceRepo.getMasterServices(any()),
      ).thenAnswer((_) async => throw const ServerFailure());

      final salonRepo = _MockSalonRepository();
      when(() => salonRepo.getSalonById(any())).thenAnswer((_) async => _salon);

      final container = makeContainer(
        master: _masterWithSalon,
        serviceRepo: serviceRepo,
        salonRepo: salonRepo,
      );

      final SalonMasterOwnProfileData data = await readProfile(container);

      expect(data.$2, isEmpty);
      expect(
        data.$3,
        _salon,
        reason:
            'the salon read must resolve normally — one leg failing must '
            'not drag the other down',
      );
    });

    test('a failed salon read degrades to NULL; the services read is '
        'unaffected and the provider does not error', () async {
      final serviceRepo = _MockServiceRepository();
      when(
        () => serviceRepo.getMasterServices(any()),
      ).thenAnswer((_) async => _services);

      final salonRepo = _MockSalonRepository();
      when(
        () => salonRepo.getSalonById(any()),
      ).thenAnswer((_) async => throw const NotFoundFailure());

      final container = makeContainer(
        master: _masterWithSalon,
        serviceRepo: serviceRepo,
        salonRepo: salonRepo,
      );

      final SalonMasterOwnProfileData data = await readProfile(container);

      expect(data.$2, _services);
      expect(
        data.$3,
        isNull,
        reason:
            'a failed salon read must degrade to null, not error the '
            'whole profile',
      );
    });
  });

  group('null salonId — the salon call is skipped entirely', () {
    test('master.salonId == null issues ZERO salon-repository calls', () async {
      final serviceRepo = _MockServiceRepository();
      when(
        () => serviceRepo.getMasterServices(any()),
      ).thenAnswer((_) async => _services);

      final salonRepo = _MockSalonRepository();
      // Deliberately NOT stubbed with `when(...)` for getSalonById — a call
      // that reached it would throw a MissingStubError, failing the test
      // loudly rather than silently returning a null/default Salon.

      final container = makeContainer(
        master: _masterNoSalon,
        serviceRepo: serviceRepo,
        salonRepo: salonRepo,
      );

      final SalonMasterOwnProfileData data = await readProfile(container);

      expect(data.$1, _masterNoSalon);
      expect(data.$2, _services);
      expect(data.$3, isNull);
      verifyNever(() => salonRepo.getSalonById(any()));
    });
  });
}
