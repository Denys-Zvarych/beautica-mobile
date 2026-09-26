// Phase 352 D2 — the ONE mapping of a chosen locality onto the backend's flat
// `location.cityId` / `location.districtId` query keys.
//
// `HttpSearchRepository._addLocation` (`search_repository.dart`) already does
// this for `/search/masters` and `/search/salons`; `search_suggestion_repository
// .dart` needs the EXACT same mapping — same key names, same "blank id = no
// filter" semantics — for `/search/suggestions`, whose `location.*` params are
// the identical reused backend `LocationFilter` (331 D6). Extracted here so
// both repositories build the location slice of their query maps from one
// function instead of two copies drifting apart. `search_repository.dart`'s
// `_addLocation` now delegates to this; its own request-building behaviour and
// tests are unchanged.
//
// Pure Dart: no Flutter imports in this file.

/// Adds `location.cityId` / `location.districtId` to [query] when [cityId] /
/// [districtId] are non-null and non-blank. Blank/null ids are omitted
/// entirely, matching the backend's "no id = no filter" convention.
void addSearchLocationQuery(
  Map<String, dynamic> query, {
  required String? cityId,
  required String? districtId,
}) {
  if (cityId != null && cityId.isNotEmpty) {
    query['location.cityId'] = cityId;
  }
  if (districtId != null && districtId.isNotEmpty) {
    query['location.districtId'] = districtId;
  }
}
