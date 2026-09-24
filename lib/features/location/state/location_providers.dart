// Phase 2.18 — Locality reference-data providers.
//
// Future providers wrapping [LocationRepository]. Only [oblastList] and
// [cityList] are `keepAlive: true` (memoized for the app lifetime; the backend
// already Spring-caches these too). [districtList] and [settlementSearch] are
// autoDispose and pin themselves with an explicit keep-alive link that is kept
// ONLY on success — a failed fetch disposes once unlistened and the next read
// refetches (for [settlementSearch], only the blank key is pinned at all). See
// each provider's own doc. Call `ref.invalidate(...)` explicitly to force a
// refetch (e.g. the sheet's Retry button).

import 'package:dio/dio.dart' show CancelToken;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/location_repository.dart';
import '../domain/city.dart';
import '../domain/city_district.dart';
import '../domain/oblast.dart';
import '../domain/settlement.dart';

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
/// Family-keyed by settlement id; the key space is bounded by how many
/// settlements one user picks in one session.
///
/// ONLY A SUCCESS IS PINNED (perf LOW-B — the same rule as
/// [settlementSearch]'s blank key). Declared autoDispose and pinned with an
/// explicit keep-alive link that is CLOSED if the fetch throws: a pinned
/// failure would otherwise replay for the whole session, hiding the «Район»
/// row every time the same settlement is re-picked. Once nothing listens, a
/// failed key disposes and the next read refetches. A successful lookup
/// stays pinned exactly as the old `keepAlive: true` family did, so every
/// consumer (`districtsOf`, `resolvedLocalityProvider`, the home hub,
/// discovery) sees the same memoisation as before.
@riverpod
Future<List<CityDistrict>> districtList(Ref ref, String cityId) async {
  final pin = ref.keepAlive();
  try {
    return await ref.watch(locationRepositoryProvider).fetchDistricts(cityId);
  } on Object {
    pin.close();
    rethrow;
  }
}

/// Phase 346 — ranked settlement matches for one debounced autocomplete query.
///
/// Family-keyed by the APPLIED (already debounced) query, so the family key
/// changes at most once per debounce window and never once per keystroke. The
/// sheet is the only consumer and it watches exactly one key at a time.
///
/// autoDispose by default and DELIBERATELY so: the key space is every prefix a
/// user can type, and a `keepAlive` family over it would grow without bound for
/// the whole app lifetime. The ONE exception is the blank key — the pre-typing
/// major-settlement list (phase-346 D6) — which is a single fixed key over
/// Flyway-seed data that cannot change at runtime and is re-read every time the
/// sheet opens. It is pinned with an explicit [Ref.keepAlive] rather than by
/// annotating the whole family, so the unbounded typed keys keep disposing.
///
/// A below-minimum query never reaches here: the field renders the "type at
/// least three characters" hint instead of watching this provider, so no
/// request is issued for a 1-2 character term. See
/// [settlementQueryIsSearchable].
///
/// CANCELLATION (perf L1). Each family member owns a [CancelToken] and cancels
/// it from `ref.onDispose`, so a query superseded by the next debounced one
/// aborts its in-flight GET instead of running it to completion on an
/// IP-throttled endpoint. The cancellation error lands on the disposed
/// element, whose result Riverpod discards — it never surfaces as an error
/// state. (The pinned blank key only disposes on an explicit invalidate, where
/// the rebuild owns a fresh token.)
///
/// ONLY A SUCCESS IS PINNED (security L3). The blank key's keep-alive link is
/// taken up front — so a warm-up `ref.read` with no listener does not dispose
/// it (and cancel its request) mid-flight — but CLOSED if the fetch fails.
/// Pinning a 429 or a network error would replay that stale error on every
/// sheet open for the rest of the session, restarting a full cooldown from an
/// old Retry-After each time. Once the sheet stops listening, a failed blank
/// key disposes and the next open refetches.
@riverpod
Future<List<Settlement>> settlementSearch(Ref ref, String query) async {
  final pin = query.isEmpty ? ref.keepAlive() : null;
  final CancelToken cancelToken = CancelToken();
  ref.onDispose(cancelToken.cancel);
  try {
    return await ref
        .watch(locationRepositoryProvider)
        .searchSettlements(query, cancelToken: cancelToken);
  } on Object {
    pin?.close();
    rethrow;
  }
}
