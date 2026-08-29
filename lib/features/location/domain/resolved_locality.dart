// Phase 21.14 — ResolvedLocality: the display-name counterpart to the raw
// `oblastId`/`cityId`/`districtId` UUID triple carried by [Salon] (and
// [Master]).
//
// Neither the backend's public salon/master read paths nor the `/locations/*`
// endpoints return a denormalised oblast/city/district NAME alongside those
// ids — only [Oblast]/[City]/[CityDistrict] objects fetched from the
// `/locations/*` cascade (`oblastListProvider` -> `cityListProvider` ->
// `districtListProvider`, all `keepAlive: true` and memoized for the app
// lifetime) carry `.name`. This record is the resolved trio, produced by
// `resolvedLocalityProvider` (`state/resolved_locality_provider.dart`) —
// each field independently nullable because resolution can partially fail
// (see that provider's doc) or the salon/master simply never set a district.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

import 'city.dart';
import 'city_district.dart';
import 'oblast.dart';

part 'resolved_locality.freezed.dart';

/// The resolved [Oblast] / [City] / [CityDistrict] display objects for a
/// given `oblastId`/`cityId`/`districtId` triple — `null` fields mean that
/// level was absent on the source entity or could not be resolved (network
/// failure, or a stale id no longer present in the reference list).
@freezed
abstract class ResolvedLocality with _$ResolvedLocality {
  const factory ResolvedLocality({
    Oblast? oblast,
    City? city,
    CityDistrict? district,
  }) = _ResolvedLocality;
}
