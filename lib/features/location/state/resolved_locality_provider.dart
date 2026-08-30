// Phase 21.14 — [resolvedLocality]: the promoted by-id locality-cascade scan.
//
// REUSE-FIRST — before this file, the identical three-stage
// `oblastId -> cities -> districts` linear scan (find the [Oblast] matching
// an id, then its [City], then its [CityDistrict]) was hand-copied privately
// in `SalonAddressEditScreen._prePopulateLocality` AND
// `LocationEditScreen._prePopulateLocality` (master feature) — a second/
// third near-identical private copy is exactly what the REUSE-FIRST rule
// exists to prevent (see `ARCHITECTURE-mobile.md`). This provider is that
// scan promoted to one shared place. `SalonAddressEditScreen` is rewired
// onto it (this phase); `LocationEditScreen` carries the same duplicate
// pattern and is a candidate for the same rewire, deliberately left
// untouched here — out of this phase's scope.
//
// Two call shapes, one implementation:
//   - a ONE-SHOT resolve, `ref.read(resolvedLocalityProvider(...).future)`,
//     used by an edit screen to seed mutable local cascade state
//     (`SalonAddressEditScreen`);
//   - a REACTIVE watch, `ref.watch(resolvedLocalityProvider(...))`, used by
//     a read-only card to render display names as they become available
//     (`_ManagementHeroCard` in `salon_management_profile_screen.dart`).
// Both share this ONE provider — the underlying `oblastList`/`cityList`/
// `districtList` providers it reads via `ref.watch(...future)` are
// `keepAlive: true` and memoized for the app lifetime, so re-resolving the
// same triple from a fresh (default `autoDispose`) family instance never
// re-hits the network — it just re-scans already-cached lists.
//
// Error handling mirrors the ORIGINAL private implementations exactly:
// failures are caught and logged (debug builds only), never rethrown — a
// caller always gets a [ResolvedLocality], never an [AsyncError], so neither
// call site needs its own try/catch. Partial results survive a failure that
// happens after an earlier stage already resolved (e.g. district lookup
// throws after oblast+city already matched) — the matched-so-far variables
// are declared outside the try block and returned regardless.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/city.dart';
import '../domain/city_district.dart';
import '../domain/oblast.dart';
import '../domain/resolved_locality.dart';
import 'location_providers.dart';

part 'resolved_locality_provider.g.dart';

/// Resolves the [Oblast]/[City]/[CityDistrict] display objects for
/// [oblastId]/[cityId]/[districtId] (all raw taxonomy UUIDs, e.g.
/// `Salon.oblastId`/`.cityId`/`.districtId`).
///
/// Returns a [ResolvedLocality] with every field `null` immediately —
/// no network read at all — when [oblastId] or [cityId] is absent (mirrors
/// the source screens' own "nothing to resolve" short-circuit). Otherwise
/// resolves oblast -> city -> district in sequence, only requesting
/// districts when the matched [City.hasDistricts] and [districtId] is set.
@riverpod
Future<ResolvedLocality> resolvedLocality(
  Ref ref, {
  required String? oblastId,
  required String? cityId,
  required String? districtId,
}) async {
  // RESUME §4 step D (mobile half, 2026-08-30) — the null checks stay: this
  // provider is shared with callers whose ids are genuinely nullable at the
  // type level (`Master.oblastId`/`.cityId` — CLIENT/master locality is
  // optional by locked product decision). `oblastId.isEmpty` is new: since
  // [Salon.cityId]/[Salon.oblastId] flipped `String? -> String` with a
  // `@Default('')` (never `null`) for fixtures that don't set them, a blank
  // (not null) pair must trip the SAME short-circuit `null` used to, or a
  // salon fixture with no real locality would spuriously await
  // `oblastListProvider` and scan for an id that matches nothing.
  if (oblastId == null ||
      oblastId.isEmpty ||
      cityId == null ||
      cityId.isEmpty) {
    return const ResolvedLocality();
  }

  Oblast? matchedOblast;
  City? matchedCity;
  CityDistrict? matchedDistrict;

  try {
    final List<Oblast> oblasts = await ref.watch(oblastListProvider.future);
    for (final Oblast o in oblasts) {
      if (o.id == oblastId) {
        matchedOblast = o;
        break;
      }
    }

    final Oblast? oblast = matchedOblast;
    if (oblast != null) {
      final List<City> cities = await ref.watch(
        cityListProvider(oblast.id).future,
      );
      for (final City c in cities) {
        if (c.id == cityId) {
          matchedCity = c;
          break;
        }
      }
    }

    final City? city = matchedCity;
    if (districtId != null && city != null && city.hasDistricts) {
      final List<CityDistrict> districts = await ref.watch(
        districtListProvider(city.id).future,
      );
      for (final CityDistrict d in districts) {
        if (d.id == districtId) {
          matchedDistrict = d;
          break;
        }
      }
    }
  } on Object catch (e, st) {
    if (kDebugMode) {
      log(
        'Locality resolution failed — some/all fields will stay unresolved',
        name: 'feature.location.resolve',
        level: 800,
        error: e,
        stackTrace: st,
      );
    }
  }

  return ResolvedLocality(
    oblast: matchedOblast,
    city: matchedCity,
    district: matchedDistrict,
  );
}
