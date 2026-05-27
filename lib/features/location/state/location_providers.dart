// Phase 2.18 — Locality reference-data providers.
//
// Three `keepAlive: true` future providers wrapping [LocationRepository]. The
// keepAlive modifier means a registration session that opens the picker many
// times only hits each `/locations/*` endpoint once — the result is memoized
// for the app lifetime (the backend already Spring-caches these too). Call
// `ref.invalidate(...)` explicitly to force a refetch (e.g. the sheet's
// Retry button).

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/location_repository.dart';
import '../domain/city.dart';
import '../domain/city_district.dart';
import '../domain/oblast.dart';

part 'location_providers.g.dart';

/// All Ukrainian oblasts (first cascade level).
@Riverpod(keepAlive: true)
Future<List<Oblast>> oblastList(Ref ref) =>
    ref.watch(locationRepositoryProvider).fetchOblasts();

/// Cities for the given [oblastId] (a UUID — second cascade level).
///
/// Family-keyed by oblast id; each distinct oblast caches independently.
@Riverpod(keepAlive: true)
Future<List<City>> cityList(Ref ref, String oblastId) =>
    ref.watch(locationRepositoryProvider).fetchCities(oblastId);

/// Districts for the given [cityId] (a UUID — third cascade level).
///
/// Only requested when `City.hasDistricts == true`. Family-keyed by city id.
@Riverpod(keepAlive: true)
Future<List<CityDistrict>> districtList(Ref ref, String cityId) =>
    ref.watch(locationRepositoryProvider).fetchDistricts(cityId);
