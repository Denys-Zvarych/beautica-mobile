// Phase 16.2 — Unit tests for the [serviceTypes] autoDispose family.
//
// The family is keyed by the platform-category slug and delegates straight to
// [ServiceRepository.fetchServiceTypes]. These tests override
// [serviceRepositoryProvider] with a mocktail mock so no transport runs, then
// assert the family resolves to the repository's list per key.
//
// Coverage:
//   1. family keyed by categoryName resolves to the repository's list.
//   2. a category with no types resolves to an empty list (not an error).
//   3. two keys are independent (each forwards its own categoryName).

import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────

class _MockServiceRepository extends Mock implements ServiceRepository {}

// ── Helpers ─────────────────────────────────────────────────────────────────

const _eyelashTypes = <ServiceTypeOption>[
  ServiceTypeOption(
    id: 'type-1',
    slug: 'CLASSIC_LASHES',
    nameUk: 'Класика',
    categoryName: 'EYELASH',
  ),
  ServiceTypeOption(
    id: 'type-2',
    slug: 'VOLUME_LASHES',
    nameUk: 'Об’ємне',
    categoryName: 'EYELASH',
  ),
];

ProviderContainer _container(ServiceRepository repo) {
  final container = ProviderContainer(
    overrides: [serviceRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  late _MockServiceRepository repo;

  setUp(() {
    repo = _MockServiceRepository();
  });

  test('resolves to the repository list for the keyed category', () async {
    when(
      () => repo.fetchServiceTypes('EYELASH'),
    ).thenAnswer((_) async => _eyelashTypes);

    final container = _container(repo);

    final result = await container.read(serviceTypesProvider('EYELASH').future);

    expect(result, _eyelashTypes);
    expect(result.map((o) => o.slug).toList(), <String>[
      'CLASSIC_LASHES',
      'VOLUME_LASHES',
    ]);
    verify(() => repo.fetchServiceTypes('EYELASH')).called(1);
  });

  test('resolves to an empty list for a category with no types', () async {
    when(
      () => repo.fetchServiceTypes('UNKNOWN'),
    ).thenAnswer((_) async => const <ServiceTypeOption>[]);

    final container = _container(repo);

    final result = await container.read(serviceTypesProvider('UNKNOWN').future);

    expect(result, isEmpty);
  });

  test('keys are independent — each forwards its own categoryName', () async {
    when(
      () => repo.fetchServiceTypes('EYELASH'),
    ).thenAnswer((_) async => _eyelashTypes);
    when(
      () => repo.fetchServiceTypes('HAIR'),
    ).thenAnswer((_) async => const <ServiceTypeOption>[]);

    final container = _container(repo);

    final eyelash =
        await container.read(serviceTypesProvider('EYELASH').future);
    final hair = await container.read(serviceTypesProvider('HAIR').future);

    expect(eyelash, _eyelashTypes);
    expect(hair, isEmpty);
    verify(() => repo.fetchServiceTypes('EYELASH')).called(1);
    verify(() => repo.fetchServiceTypes('HAIR')).called(1);
  });
}
