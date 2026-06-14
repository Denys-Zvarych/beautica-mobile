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
//   4. REGRESSION (stale-cache): after the family's only listener drops and the
//      autoDispose entry tears down, re-reading the same key issues a SECOND
//      fetch — so a service type approved out-of-band appears on picker re-entry.
//      This FAILS against the old keepAlive/Timer body (call count would be 1).
//   5. REGRESSION (explicit invalidate): an explicit `ref.invalidate` of the
//      family forces a refetch and surfaces the newly-approved type.

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

/// The newly-approved type that an admin added out-of-band under the SAME
/// existing `EYELASH` category — must appear on the next (post-teardown) fetch.
const _newlyApprovedType = ServiceTypeOption(
  id: 'type-3',
  slug: 'MEGA_VOLUME_LASHES',
  nameUk: 'Мега-об’ємне',
  categoryName: 'EYELASH',
);

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

    final eyelash = await container.read(
      serviceTypesProvider('EYELASH').future,
    );
    final hair = await container.read(serviceTypesProvider('HAIR').future);

    expect(eyelash, _eyelashTypes);
    expect(hair, isEmpty);
    verify(() => repo.fetchServiceTypes('EYELASH')).called(1);
    verify(() => repo.fetchServiceTypes('HAIR')).called(1);
  });

  // ── 4. REGRESSION — autoDispose re-fetch surfaces an out-of-band approval ───
  //
  // This is the stale-cache bug guard. The picker previously pinned each
  // category's fetched list via `ref.keepAlive()` + a 3-minute `Timer`, so a
  // service type an admin approved under an EXISTING category never appeared in
  // the "Тип послуги" dropdown until the timer lapsed or the app cold-restarted.
  //
  // The fix made the family a plain autoDispose fetch: once its last listener
  // drops, the entry tears down, and the next read issues a fresh fetch. This
  // test models exactly that — read once (repo returns list A), drop the
  // subscription so the autoDispose family disposes, then read again with the
  // repo now returning list A + the newly-approved type.
  //
  // Pre-fix expectation: the second read would be served from the kept-alive
  //   cache → `fetchServiceTypes` called ONCE → `verify(...).called(2)` FAILS
  //   and the newly-approved option would be ABSENT. That is what makes this a
  //   true regression test for THIS bug.
  // Post-fix expectation: the family re-fetches → called TWICE → the second
  //   result contains MEGA_VOLUME_LASHES.
  test(
    'REGRESSION: re-fetches after listener drops so an out-of-band approval '
    'appears on picker re-entry (called twice, new option present)',
    () async {
      // First fetch returns the original two types; the second fetch (after the
      // autoDispose teardown) returns the original two PLUS the new approval.
      final responses = <List<ServiceTypeOption>>[
        _eyelashTypes,
        <ServiceTypeOption>[..._eyelashTypes, _newlyApprovedType],
      ];
      var call = 0;
      when(() => repo.fetchServiceTypes('EYELASH')).thenAnswer((_) async {
        return responses[call++];
      });

      final container = _container(repo);

      // First picker entry — keep a live subscription so the provider builds.
      final firstSub = container.listen(
        serviceTypesProvider('EYELASH'),
        (_, _) {},
      );
      final firstResult = await container.read(
        serviceTypesProvider('EYELASH').future,
      );
      expect(firstResult, _eyelashTypes);
      expect(
        firstResult.map((o) => o.slug),
        isNot(contains('MEGA_VOLUME_LASHES')),
        reason: 'the new type is not approved yet at first entry',
      );

      // Picker closes → its only listener drops. The autoDispose family tears
      // the entry down (no keepAlive pins it alive anymore). `pump` lets the
      // scheduled disposal microtask run.
      firstSub.close();
      await container.pump();

      // Second picker entry (admin approved MEGA_VOLUME_LASHES meanwhile) — the
      // family must build afresh and issue a second fetch.
      final secondResult = await container.read(
        serviceTypesProvider('EYELASH').future,
      );

      expect(
        secondResult.map((o) => o.slug).toList(),
        <String>['CLASSIC_LASHES', 'VOLUME_LASHES', 'MEGA_VOLUME_LASHES'],
        reason:
            'the out-of-band approval must surface on re-entry — the old '
            'keepAlive/Timer body would have returned the stale 2-item list',
      );
      verify(() => repo.fetchServiceTypes('EYELASH')).called(2);
    },
  );

  // ── 5. REGRESSION — explicit invalidate forces a refetch ────────────────────
  //
  // The services-list screen invalidates the WHOLE `serviceTypes` family on its
  // refresh surfaces (entry / pop-back / pull-to-refresh). This variant pins
  // that an explicit `ref.invalidate` re-issues the fetch and surfaces the
  // newly-approved type even while a listener stays attached.
  test(
    'REGRESSION: explicit invalidate refetches and surfaces the new option',
    () async {
      final responses = <List<ServiceTypeOption>>[
        _eyelashTypes,
        <ServiceTypeOption>[..._eyelashTypes, _newlyApprovedType],
      ];
      var call = 0;
      when(() => repo.fetchServiceTypes('EYELASH')).thenAnswer((_) async {
        return responses[call++];
      });

      final container = _container(repo);

      final before = await container.read(
        serviceTypesProvider('EYELASH').future,
      );
      expect(before, _eyelashTypes);

      // Screen refresh surface: invalidate the whole family (no arg).
      container.invalidate(serviceTypesProvider);

      final after = await container.read(
        serviceTypesProvider('EYELASH').future,
      );

      expect(
        after.map((o) => o.slug),
        contains('MEGA_VOLUME_LASHES'),
        reason: 'invalidation must surface the newly-approved type',
      );
      verify(() => repo.fetchServiceTypes('EYELASH')).called(2);
    },
  );
}
