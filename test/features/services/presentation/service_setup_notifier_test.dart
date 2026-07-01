// First-time service setup — unit tests for [ServiceSetup] AsyncNotifier.
//
// The notifier owns ONLY the bulk-save side effect: it forwards assembled
// [MasterServiceBulkItem]s to [ServiceRepository.bulkCreate], moves through
// AsyncLoading → AsyncData (success) / AsyncError (failure), and returns the
// created list on success or null on failure so the screen can branch without
// re-reading the error.
//
// Strategy:
//   Pure Dart — ProviderContainer + mocktail mock for ServiceRepository.
//   No widget tree. Fresh container per test, disposed via addTearDown.
//
// Coverage:
//   1. success — returns created list, state ends AsyncData, no throw.
//   2. failure — typed Failure surfaces in AsyncError; submit returns null;
//      the raw Failure never escapes as a thrown exception.
//   3. 409     — MasterAlreadyHasServicesFailure lands in state.error (the
//      branch the screen keys on to route to the list instead of retrying).
//   4. empty   — empty items short-circuits to AsyncData([]) without a repo call.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/presentation/service_setup_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────

class _MockServiceRepository extends Mock implements ServiceRepository {}

// ── Stub data ────────────────────────────────────────────────────────────────

const _item = MasterServiceBulkItem(
  serviceTypeId: 'type-1',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  price: 500,
);

const _created = <MasterService>[
  MasterService(
    id: 'svc-001',
    serviceDefId: 'def-001',
    name: 'Манікюр',
    durationMinutes: 60,
    priceMin: 500,
    priceDisplay: '500 грн',
  ),
];

ProviderContainer _makeContainer(_MockServiceRepository repo) {
  final container = ProviderContainer(
    // cycle-stub-ok: the service-setup notifier under test watches serviceRepositoryProvider as its DIRECT leaf data dep — stubbing the repo overrides the leaf, not a cycle-closing edge. No auth/logout cascade is exercised here.
    overrides: [serviceRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late _MockServiceRepository repo;

  setUp(() {
    repo = _MockServiceRepository();
    registerFallbackValue(const <MasterServiceBulkItem>[]);
  });

  test('submit success — returns created list and ends in AsyncData', () async {
    when(() => repo.bulkCreate(any())).thenAnswer((_) async => _created);
    final container = _makeContainer(repo);

    // Settle the idle initial build.
    await container.read(serviceSetupProvider.future);

    final result = await container.read(serviceSetupProvider.notifier).submit(
      <MasterServiceBulkItem>[_item],
    );

    expect(result, _created);
    final state = container.read(serviceSetupProvider);
    expect(state.hasValue, isTrue);
    expect(state.hasError, isFalse);
    verify(() => repo.bulkCreate(any())).called(1);
  });

  test('submit failure — surfaces typed Failure in AsyncError, returns null '
      'without throwing', () async {
    const failure = ValidationFailure(fieldErrors: <String, String>{});
    when(() => repo.bulkCreate(any())).thenThrow(failure);
    final container = _makeContainer(repo);
    await container.read(serviceSetupProvider.future);

    final result = await container.read(serviceSetupProvider.notifier).submit(
      <MasterServiceBulkItem>[_item],
    );

    expect(result, isNull);
    final state = container.read(serviceSetupProvider);
    expect(state.hasError, isTrue);
    expect(state.error, same(failure));
  });

  test(
    'submit 409 — MasterAlreadyHasServicesFailure lands in state.error',
    () async {
      const failure = MasterAlreadyHasServicesFailure();
      when(() => repo.bulkCreate(any())).thenThrow(failure);
      final container = _makeContainer(repo);
      await container.read(serviceSetupProvider.future);

      final result = await container.read(serviceSetupProvider.notifier).submit(
        <MasterServiceBulkItem>[_item],
      );

      expect(result, isNull);
      expect(
        container.read(serviceSetupProvider).error,
        isA<MasterAlreadyHasServicesFailure>(),
      );
    },
  );

  test(
    'submit with empty items short-circuits to AsyncData([]) — no repo call',
    () async {
      final container = _makeContainer(repo);
      await container.read(serviceSetupProvider.future);

      final result = await container
          .read(serviceSetupProvider.notifier)
          .submit(const <MasterServiceBulkItem>[]);

      expect(result, isEmpty);
      expect(container.read(serviceSetupProvider).hasValue, isTrue);
      verifyNever(() => repo.bulkCreate(any()));
    },
  );
}
