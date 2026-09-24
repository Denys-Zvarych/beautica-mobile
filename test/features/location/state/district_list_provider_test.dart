// Perf LOW-B — `districtListProvider` pins only a SUCCESS.
//
// A failed district lookup used to stay pinned for the session (the family
// was `keepAlive: true`), so re-picking the same settlement replayed the error
// and hid the «Район» row. A failure must now dispose once nothing listens,
// so the next read fetches again; a success must stay memoised.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/location/data/location_repository.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:beautica_mobile/features/location/domain/settlement.dart';
import 'package:beautica_mobile/features/location/state/location_providers.dart';
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _district = CityDistrict(
  id: 'd1',
  cityId: 'c1',
  name: 'Шевченківський',
  katotthCode: 'UA80-000-0001',
);

class _FlakyDistrictsRepository implements LocationRepository {
  _FlakyDistrictsRepository({required this.failures});

  /// How many leading [fetchDistricts] calls throw before one succeeds.
  int failures;
  int calls = 0;

  @override
  Future<List<CityDistrict>> fetchDistricts(String cityId) async {
    calls++;
    if (failures > 0) {
      failures--;
      throw const NetworkFailure();
    }
    return const <CityDistrict>[_district];
  }

  @override
  Future<List<Oblast>> fetchOblasts() => throw UnimplementedError();

  @override
  Future<List<City>> fetchCities(String oblastId) => throw UnimplementedError();

  @override
  Future<List<Settlement>> searchSettlements(
    String query, {
    CancelToken? cancelToken,
  }) => throw UnimplementedError();
}

ProviderContainer _container(LocationRepository repo) {
  final container = ProviderContainer(
    overrides: [locationRepositoryProvider.overrideWithValue(repo)],
    // Observe exactly the fetches the provider issues.
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('a FAILED lookup is not pinned: once disposed, a re-read fetches '
      'again and recovers', () async {
    final repo = _FlakyDistrictsRepository(failures: 1);
    final container = _container(repo);

    await expectLater(
      container.read(districtListProvider('c1').future),
      throwsA(isA<NetworkFailure>()),
    );
    // Let the unlistened, now-unpinned element dispose.
    await container.pump();

    final List<CityDistrict> districts = await container.read(
      districtListProvider('c1').future,
    );
    expect(repo.calls, 2);
    expect(districts, const <CityDistrict>[_district]);
  });

  test('a SUCCESSFUL lookup stays memoised with no listener — the old '
      'keepAlive behaviour every consumer relies on', () async {
    final repo = _FlakyDistrictsRepository(failures: 0);
    final container = _container(repo);

    await container.read(districtListProvider('c1').future);
    await container.pump();
    await container.read(districtListProvider('c1').future);

    expect(repo.calls, 1);
  });
}
