// Phase 21.14 gap-closure (mobile-qa, 2026-08-29) — `resolvedLocalityProvider`
// (`lib/features/location/state/resolved_locality_provider.dart`) shipped
// with NO test of its own — `test/features/location/state/` did not exist
// before this file. Backlogged as INFO in `docs/mobile-phases/mobile-backlog
// .md` ("Add provider tests (miss-by-id, null ids, partial resolution) when
// that area is next touched"); closed here because this IS that area being
// touched — the provider is the exact mechanism both
// `salon_management_profile_screen_test.dart` and `my_salons_screen_test
// .dart`'s new gap-closure tests depend on to exercise the resolved-locality
// branch at all.
//
// Strategy: a hand-written `_FakeLocationRepository` (mirrors
// `locality_cascade_test.dart`'s own fake shape) overriding
// `locationRepositoryProvider`, driven through a fresh `ProviderContainer`
// per test. `retry: (_, _) => null` on every container — the failure-path
// test needs the underlying (keepAlive) `oblastListProvider` to surface its
// throw on the FIRST attempt, not after Riverpod's default ~38s / 10-attempt
// backoff (see `pump_app.dart`'s own doc on why the default matters and why
// tests that need an exact call count disable it).

import 'package:beautica_mobile/features/location/data/location_repository.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:beautica_mobile/features/location/domain/resolved_locality.dart';
import 'package:beautica_mobile/features/location/state/resolved_locality_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fixtures — a full oblast -> city (with districts) -> district chain, plus
// a second districtless city, so the `hasDistricts` gate has both shapes to
// resolve against.
// ---------------------------------------------------------------------------

const _oblast = Oblast(id: 'ob-1', name: 'Львівська область', katotthCode: 'A');
const _cityWithDistricts = City(
  id: 'ct-1',
  oblastId: 'ob-1',
  name: 'Львів',
  katotthCode: 'B',
  hasDistricts: true,
);
const _cityNoDistricts = City(
  id: 'ct-2',
  oblastId: 'ob-1',
  name: 'Дрогобич',
  katotthCode: 'C',
  hasDistricts: false,
);
const _district = CityDistrict(
  id: 'd-1',
  cityId: 'ct-1',
  name: 'Галицький',
  katotthCode: 'D',
);

/// Call-counting fake so short-circuit / hasDistricts-gate tests can assert
/// the network was (or was not) actually reached, not just that the RESULT
/// happened to be right.
class _CountingFakeLocationRepository implements LocationRepository {
  _CountingFakeLocationRepository({this.oblastsThrow = false});

  final bool oblastsThrow;

  int fetchOblastsCalls = 0;
  int fetchCitiesCalls = 0;
  int fetchDistrictsCalls = 0;

  @override
  Future<List<Oblast>> fetchOblasts() async {
    fetchOblastsCalls++;
    if (oblastsThrow) throw const NetworkFailureStub();
    return const <Oblast>[_oblast];
  }

  @override
  Future<List<City>> fetchCities(String oblastId) async {
    fetchCitiesCalls++;
    return const <City>[_cityWithDistricts, _cityNoDistricts];
  }

  @override
  Future<List<CityDistrict>> fetchDistricts(String cityId) async {
    fetchDistrictsCalls++;
    return const <CityDistrict>[_district];
  }
}

/// A minimal `Exception` — avoids importing the real `Failure` hierarchy just
/// to prove the provider swallows whatever the repository throws.
class NetworkFailureStub implements Exception {
  const NetworkFailureStub();
}

void main() {
  group('short-circuit — missing ids never reach the repository', () {
    test('oblastId null returns an all-null ResolvedLocality with zero '
        'repository calls', () async {
      final repo = _CountingFakeLocationRepository();
      final container = ProviderContainer(
        overrides: [locationRepositoryProvider.overrideWith((_) => repo)],
        retry: (_, _) => null,
      );
      addTearDown(container.dispose);

      final ResolvedLocality result = await container.read(
        resolvedLocalityProvider(
          oblastId: null,
          cityId: 'ct-1',
          districtId: 'd-1',
        ).future,
      );

      expect(result, const ResolvedLocality());
      expect(
        repo.fetchOblastsCalls,
        0,
        reason: 'a null oblastId must short-circuit before any network call',
      );
    });

    test('cityId null/empty returns an all-null ResolvedLocality with zero '
        'repository calls', () async {
      final repo = _CountingFakeLocationRepository();
      final container = ProviderContainer(
        overrides: [locationRepositoryProvider.overrideWith((_) => repo)],
        retry: (_, _) => null,
      );
      addTearDown(container.dispose);

      final ResolvedLocality nullCity = await container.read(
        resolvedLocalityProvider(
          oblastId: 'ob-1',
          cityId: null,
          districtId: null,
        ).future,
      );
      final ResolvedLocality blankCity = await container.read(
        resolvedLocalityProvider(
          oblastId: 'ob-1',
          cityId: '',
          districtId: null,
        ).future,
      );

      expect(nullCity, const ResolvedLocality());
      expect(blankCity, const ResolvedLocality());
      expect(repo.fetchOblastsCalls, 0);
    });
  });

  group('full resolution', () {
    test('a matching oblast/city/district triple resolves all three', () async {
      final repo = _CountingFakeLocationRepository();
      final container = ProviderContainer(
        overrides: [locationRepositoryProvider.overrideWith((_) => repo)],
        retry: (_, _) => null,
      );
      addTearDown(container.dispose);

      final ResolvedLocality result = await container.read(
        resolvedLocalityProvider(
          oblastId: 'ob-1',
          cityId: 'ct-1',
          districtId: 'd-1',
        ).future,
      );

      expect(result.oblast, _oblast);
      expect(result.city, _cityWithDistricts);
      expect(result.district, _district);
    });
  });

  group('miss-by-id', () {
    test('a cityId that matches no city in the resolved oblast leaves city '
        'AND district null, oblast still resolved', () async {
      final repo = _CountingFakeLocationRepository();
      final container = ProviderContainer(
        overrides: [locationRepositoryProvider.overrideWith((_) => repo)],
        retry: (_, _) => null,
      );
      addTearDown(container.dispose);

      final ResolvedLocality result = await container.read(
        resolvedLocalityProvider(
          oblastId: 'ob-1',
          cityId: 'no-such-city',
          districtId: 'd-1',
        ).future,
      );

      expect(result.oblast, _oblast);
      expect(result.city, isNull);
      expect(result.district, isNull);
    });

    test('an oblastId that matches nothing leaves everything null and never '
        'requests cities', () async {
      final repo = _CountingFakeLocationRepository();
      final container = ProviderContainer(
        overrides: [locationRepositoryProvider.overrideWith((_) => repo)],
        retry: (_, _) => null,
      );
      addTearDown(container.dispose);

      final ResolvedLocality result = await container.read(
        resolvedLocalityProvider(
          oblastId: 'no-such-oblast',
          cityId: 'ct-1',
          districtId: 'd-1',
        ).future,
      );

      expect(result, const ResolvedLocality());
      expect(
        repo.fetchCitiesCalls,
        0,
        reason: 'an unresolved oblast must never trigger a cities fetch',
      );
    });
  });

  group('hasDistricts gate', () {
    test('a city with hasDistricts == false never requests districts, even '
        'when districtId is set', () async {
      final repo = _CountingFakeLocationRepository();
      final container = ProviderContainer(
        overrides: [locationRepositoryProvider.overrideWith((_) => repo)],
        retry: (_, _) => null,
      );
      addTearDown(container.dispose);

      final ResolvedLocality result = await container.read(
        resolvedLocalityProvider(
          oblastId: 'ob-1',
          cityId: 'ct-2', // hasDistricts: false
          districtId: 'd-1',
        ).future,
      );

      expect(result.oblast, _oblast);
      expect(result.city, _cityNoDistricts);
      expect(result.district, isNull);
      expect(
        repo.fetchDistrictsCalls,
        0,
        reason:
            'a districtless city must never issue a districts request, '
            'regardless of a stale districtId still being present',
      );
    });

    // MUTATION-VERIFIED (mobile-qa, 2026-08-29) — temporarily removing the
    // `city.hasDistricts` conjunct from the provider's district-fetch guard
    // (`if (districtId != null && city != null && city.hasDistricts)` ->
    // `if (districtId != null && city != null)`) turns this RED
    // (`fetchDistrictsCalls` becomes 1); restoring the guard turns it back
    // GREEN with a clean `git diff`. See the QA report for the exact
    // before/after commands.
    test('districtId null never requests districts even when the city HAS '
        'districts', () async {
      final repo = _CountingFakeLocationRepository();
      final container = ProviderContainer(
        overrides: [locationRepositoryProvider.overrideWith((_) => repo)],
        retry: (_, _) => null,
      );
      addTearDown(container.dispose);

      final ResolvedLocality result = await container.read(
        resolvedLocalityProvider(
          oblastId: 'ob-1',
          cityId: 'ct-1', // hasDistricts: true
          districtId: null,
        ).future,
      );

      expect(result.city, _cityWithDistricts);
      expect(result.district, isNull);
      expect(repo.fetchDistrictsCalls, 0);
    });
  });

  group('failure handling', () {
    test('a repository throw is swallowed — resolves to an all-null '
        'ResolvedLocality, never an AsyncError', () async {
      final repo = _CountingFakeLocationRepository(oblastsThrow: true);
      final container = ProviderContainer(
        overrides: [locationRepositoryProvider.overrideWith((_) => repo)],
        retry: (_, _) => null,
      );
      addTearDown(container.dispose);

      final ResolvedLocality result = await container.read(
        resolvedLocalityProvider(
          oblastId: 'ob-1',
          cityId: 'ct-1',
          districtId: 'd-1',
        ).future,
      );

      expect(
        result,
        const ResolvedLocality(),
        reason:
            'the provider must catch the failure internally and hand back '
            'an empty-but-valid ResolvedLocality — callers never see an '
            'AsyncError for this provider by design (see its own doc)',
      );
      expect(
        container.read(
          resolvedLocalityProvider(
            oblastId: 'ob-1',
            cityId: 'ct-1',
            districtId: 'd-1',
          ),
        ),
        isA<AsyncData<ResolvedLocality>>(),
        reason:
            'the provider state itself must settle as AsyncData, not '
            'AsyncError — this is the concrete shape both hero-card and hub-'
            'card widgets rely on when they read `.value` directly',
      );
    });
  });
}
