// Phase 13.3 — Пошук (Search) filters controller.
//
// Drives the existing pure-Dart [SearchFilters] model the discovery repository
// already understands. The Пошук screen reads this controller, mutates it as
// the user picks a city / service type / price ceiling, and the CTA forwards
// the assembled [SearchFilters] to the results screen via `context.push`
// `extra:`.
//
// keepAlive: selections must survive the `context.push` to the results screen
// and back (a fresh autoDispose provider would reset the moment the screen
// unmounts during the push). The controller `ref.watch(authProvider)`s so a
// fresh session (login after logout) rebuilds it back to `const SearchFilters()`
// — mirroring how every other keepAlive provider sheds stale per-user state on
// logout (auth_notifier.dart § "do NOT invalidate" note: watchers self-clear
// when the session flips). No manual logout eviction is needed here.
//
// Display labels (selected city name, selected category name) are NOT stored on
// [SearchFilters] — that model is the wire-facing filter set and carries only
// ids/slugs. The human-readable labels live in the sibling
// [SearchFilterLabels] provider so the row chrome can render «Львів» / «Манікюр»
// without polluting the request model.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../auth/domain/user.dart';
import '../../../auth/presentation/auth_notifier.dart';
import '../../../home/application/client_edit_profile_notifier.dart';
import '../../../location/domain/city.dart';
import '../../../location/domain/city_district.dart';
import '../../../location/domain/oblast.dart';
import '../../../location/state/location_providers.dart';
import '../../domain/search_filters.dart';

part 'search_filters_controller.g.dart';

/// Price ceiling at/above which the «до N грн» readout collapses to "будь-яка"
/// (any) and [SearchFilters.maxPrice] is cleared (no upper bound sent).
const double kSearchPriceCeiling = 20000;

/// The price slider's discrete step count (0 → 20000 in 500-грн increments).
const int kSearchPriceDivisions = 40;

/// Human-readable display labels for the current [SearchFilters] selection.
///
/// Kept OUT of [SearchFilters] (the wire model holds ids/slugs only). Both
/// fields are null when nothing is selected, so the row chrome falls back to its
/// placeholder.
@immutable
class SearchFilterLabels {
  const SearchFilterLabels({
    this.oblastName,
    this.cityName,
    this.cityHasDistricts = false,
    this.districtName,
    this.categoryName,
  });

  /// Display name of the selected oblast / region (e.g. «Львівська область»), or
  /// null.
  final String? oblastName;

  /// Display name of the selected city (e.g. «Львів»), or null.
  final String? cityName;

  /// Whether the selected city subdivides into districts (mirrors
  /// `City.hasDistricts`). Drives the District row's enabled/disabled state on
  /// the filters screen: when false (or no city is chosen) the row is disabled
  /// and the app never issues a districts request. UI-only — never sent on the
  /// wire. Defaults to false (no city → no districts).
  final bool cityHasDistricts;

  /// Display name of the selected district (e.g. «Франківський»), or null when
  /// the city has no districts or the (optional) district step was skipped.
  final String? districtName;

  /// Display name of the selected service category (e.g. «Манікюр»), or null.
  final String? categoryName;

  SearchFilterLabels copyWith({
    String? Function()? oblastName,
    String? Function()? cityName,
    bool? cityHasDistricts,
    String? Function()? districtName,
    String? Function()? categoryName,
  }) {
    return SearchFilterLabels(
      oblastName: oblastName != null ? oblastName() : this.oblastName,
      cityName: cityName != null ? cityName() : this.cityName,
      cityHasDistricts: cityHasDistricts ?? this.cityHasDistricts,
      districtName: districtName != null ? districtName() : this.districtName,
      categoryName: categoryName != null ? categoryName() : this.categoryName,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchFilterLabels &&
          other.oblastName == oblastName &&
          other.cityName == cityName &&
          other.cityHasDistricts == cityHasDistricts &&
          other.districtName == districtName &&
          other.categoryName == categoryName;

  @override
  int get hashCode => Object.hash(
    oblastName,
    cityName,
    cityHasDistricts,
    districtName,
    categoryName,
  );
}

/// Holds the display labels for the active [SearchFilters] selection.
///
/// keepAlive + auth-watched for the same reasons as [SearchFiltersController]:
/// labels survive the push to results and reset on a fresh session.
@Riverpod(keepAlive: true)
class SearchFilterLabelsController extends _$SearchFilterLabelsController {
  @override
  SearchFilterLabels build() {
    // Reset to empty labels whenever the session changes (logout → login).
    ref.watch(authProvider);
    return const SearchFilterLabels();
  }

  /// Sets (or clears, when [name] is null) the selected-oblast display label.
  void setOblastName(String? name) =>
      state = state.copyWith(oblastName: () => name);

  /// Sets (or clears, when [name] is null) the selected-city display label.
  ///
  /// Clearing the city name also resets [SearchFilterLabels.cityHasDistricts] to
  /// false (no city → no districts), so the District row falls back to disabled.
  void setCityName(String? name) => state = state.copyWith(
    cityName: () => name,
    cityHasDistricts: name == null ? false : state.cityHasDistricts,
  );

  /// Records whether the selected city subdivides into districts (drives the
  /// District row's enabled state on the filters screen).
  void setCityHasDistricts(bool hasDistricts) =>
      state = state.copyWith(cityHasDistricts: hasDistricts);

  /// Sets (or clears, when [name] is null) the selected-district display label.
  void setDistrictName(String? name) =>
      state = state.copyWith(districtName: () => name);

  /// Sets (or clears, when [name] is null) the selected-category display label.
  void setCategoryName(String? name) =>
      state = state.copyWith(categoryName: () => name);

  /// Clears all labels (paired with [SearchFiltersController.reset]).
  void reset() => state = const SearchFilterLabels();
}

/// The Пошук screen's filter state — IS a [SearchFilters]. The screen watches
/// this and the CTA forwards `state` to the results screen.
@Riverpod(keepAlive: true)
class SearchFiltersController extends _$SearchFiltersController {
  /// Set ONLY by the user-driven locality mutators ([selectOblast] /
  /// [selectCity] / [selectDistrict]) — never by [prefillFromProfileIfNeeded]
  /// itself. Once true, the profile-derived seed is permanently abandoned for
  /// the rest of the session: a genuine manual pick (including a manual
  /// *clear*) must never be silently reverted by a later profile-derived
  /// reseed.
  ///
  /// Re-armed (cleared) in [build] on a session flip, same as every other
  /// per-session guard on this notifier.
  bool _userTouchedLocality = false;

  /// Identity of the locality [prefillFromProfileIfNeeded] last auto-seeded
  /// from [clientEditProfileProvider] (all `null` when nothing has been seeded
  /// yet, or the profile currently has no saved locality).
  ///
  /// Replaces the old one-shot latch: instead of seeding at most once per
  /// session, [prefillFromProfileIfNeeded] now re-reads the profile on EVERY
  /// call (cheap — [clientEditProfileProvider] is a cached keepAlive future
  /// and only actually refetches after an edit-screen `ref.invalidate`) and
  /// compares the profile's current locality against these fields. A mismatch
  /// means the saved profile locality changed since the last seed (e.g. the
  /// user edited it on `ClientLocationEditScreen`), so the filter is
  /// re-seeded to match; an identical value is a no-op, avoiding redundant
  /// taxonomy lookups + state churn on every screen re-entry.
  String? _lastSeededOblastId;
  String? _lastSeededCityId;
  String? _lastSeededDistrictId;

  @override
  SearchFilters build() {
    // Reset to an empty filter set whenever the session changes (logout →
    // login) — the same self-clearing pattern every keepAlive per-user provider
    // uses. Without this, one user's last search would leak to the next login.
    ref.watch(authProvider);
    // Re-arm the profile-seed tracking for the (possibly new) session.
    _userTouchedLocality = false;
    _lastSeededOblastId = null;
    _lastSeededCityId = null;
    _lastSeededDistrictId = null;
    return const SearchFilters();
  }

  /// Pre-fills the locality filter (oblast → city → district) from the signed-in
  /// CLIENT's saved profile location — kept in sync with the profile across the
  /// WHOLE session, and NEVER over a manual change.
  ///
  /// Called when the Пошук screen opens (its `initState`). Designed around the
  /// keepAlive seamless-reload footgun: this controller never `ref.watch`es
  /// [clientEditProfileProvider] (a watch would re-run `build()` on every profile
  /// emission and clobber the user's edits). Instead the profile is read
  /// (off the widget lifecycle) on every call, behind two guards:
  ///   1. [_userTouchedLocality] — once the user has manually picked (or
  ///      cleared) a locality via [selectOblast]/[selectCity]/[selectDistrict],
  ///      the seed is abandoned for the rest of the session (re-checked again
  ///      AFTER each async resolve, in case the user picks while the taxonomy
  ///      is loading);
  ///   2. [_lastSeededOblastId]/[_lastSeededCityId]/[_lastSeededDistrictId] — if
  ///      the profile's current locality is identical to what was last seeded,
  ///      the call is a no-op (nothing changed).
  ///
  /// When the profile has no saved location, any previously-seeded locality is
  /// cleared to match (the user removed their saved address); when any taxonomy
  /// lookup fails, the filter is left as-is.
  ///
  /// Labels (incl. `cityHasDistricts`, resolved from the taxonomy — never
  /// hardcoded) are seeded on the sibling [searchFilterLabelsControllerProvider]
  /// so the locality chips show the saved names and the District row gates
  /// correctly. Mirrors `ClientLocationEditScreen._prePopulateLocality`.
  Future<void> prefillFromProfileIfNeeded() async {
    // A genuine user pick (or clear) always wins — never re-read the profile
    // once the user has manually driven the locality this session.
    if (_userTouchedLocality) return;

    try {
      final User user = await ref.read(clientEditProfileProvider.future);
      // The user may have picked a locality WHILE the (cached, but still
      // async) profile future was resolving — their choice wins.
      if (_userTouchedLocality) return;

      final String? oblastId = user.oblastId;
      final String? cityId = user.cityId;
      final String? districtId = user.districtId;

      // No-op: the profile's locality is identical to what we last seeded
      // (including "both empty" on the very first call).
      if (oblastId == _lastSeededOblastId &&
          cityId == _lastSeededCityId &&
          districtId == _lastSeededDistrictId) {
        return;
      }

      // No saved location (any more) → clear whatever was previously seeded,
      // matching the profile.
      if (oblastId == null || cityId == null) {
        _lastSeededOblastId = null;
        _lastSeededCityId = null;
        _lastSeededDistrictId = null;
        state = state.copyWith(oblastId: null, cityId: null, districtId: null);
        ref.read(searchFilterLabelsControllerProvider.notifier)
          ..setOblastName(null)
          ..setCityName(null)
          ..setDistrictName(null);
        return;
      }

      // Resolve the taxonomy objects so the labels + cityHasDistricts are
      // accurate (a single targeted city fetch for the saved oblast — not a scan
      // of every oblast). Mirrors _prePopulateLocality.
      final List<Oblast> oblasts = await ref.read(oblastListProvider.future);
      if (_userTouchedLocality) return;
      Oblast? matchedOblast;
      for (final Oblast o in oblasts) {
        if (o.id == oblastId) {
          matchedOblast = o;
          break;
        }
      }
      if (matchedOblast == null) return;

      final List<City> cities = await ref.read(
        cityListProvider(oblastId).future,
      );
      if (_userTouchedLocality) return;
      City? matchedCity;
      for (final City c in cities) {
        if (c.id == cityId) {
          matchedCity = c;
          break;
        }
      }
      if (matchedCity == null) return;

      CityDistrict? matchedDistrict;
      if (districtId != null && matchedCity.hasDistricts) {
        final List<CityDistrict> districts = await ref.read(
          districtListProvider(matchedCity.id).future,
        );
        if (_userTouchedLocality) return;
        for (final CityDistrict d in districts) {
          if (d.id == districtId) {
            matchedDistrict = d;
            break;
          }
        }
      }

      // Final re-check of the anti-clobber guard: if the user picked (or
      // cleared) a locality while the taxonomy was loading, their choice wins
      // — abandon the seed.
      if (_userTouchedLocality) return;

      // Record what we are about to seed ...
      _lastSeededOblastId = matchedOblast.id;
      _lastSeededCityId = matchedCity.id;
      _lastSeededDistrictId = matchedDistrict?.id;
      // ... and commit the cascade-consistent filter ids ...
      state = state.copyWith(
        oblastId: matchedOblast.id,
        cityId: matchedCity.id,
        districtId: matchedDistrict?.id,
      );
      // ... and the display labels (cityHasDistricts comes from the resolved
      // City, so the District row gates correctly).
      final City city = matchedCity;
      final CityDistrict? district = matchedDistrict;
      ref.read(searchFilterLabelsControllerProvider.notifier)
        ..setOblastName(matchedOblast.name)
        ..setCityName(city.name)
        ..setCityHasDistricts(city.hasDistricts)
        ..setDistrictName(district?.name);
    } catch (e, st) {
      // Graceful: a failed resolve leaves the locality filter as-is (nothing
      // was recorded as seeded), so the NEXT call — e.g. the next time the
      // Пошук screen opens — retries automatically instead of getting stuck.
      if (kDebugMode) {
        // Log only the error's runtime type — never the raw error object, whose
        // toString() can embed PII (e.g. a DioException carrying the /users/me
        // request/response: email, phone, saved locality). MS5/MS14 hygiene.
        log(
          'search locality prefill failed (${e.runtimeType}) — filter left empty',
          name: 'feature.discovery.search',
          level: 800,
          stackTrace: st,
        );
      }
    }
  }

  /// Sets the free-text name / service query.
  ///
  /// Forwarded to the backend `q` param by the repository. A blank/whitespace
  /// value is normalised to null so an empty box never narrows anything (and the
  /// param is omitted). The value is carried in `extra` to the results screen.
  void setQuery(String? query) {
    final String? trimmed = query?.trim();
    final String? next = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    state = state.copyWith(query: next);
  }

  /// Sets the result ordering. Re-keys the results provider on the results
  /// screen so a fresh page-0 fetch runs with the new `sort`.
  void setSort(SearchSort sort) {
    state = state.copyWith(sort: sort);
  }

  /// Selects (or clears) the oblast / region — the first cascade level.
  ///
  /// Changing or clearing the oblast invalidates everything funnelled through
  /// it: the city and the district are both cleared, since neither is meaningful
  /// outside its region. Pass `oblastId: null` to clear the whole locality.
  ///
  /// A user-driven mutator: marks [_userTouchedLocality] so
  /// [prefillFromProfileIfNeeded] never overwrites this choice again this
  /// session, even a deliberate clear.
  void selectOblast({required String? oblastId}) {
    _userTouchedLocality = true;
    state = state.copyWith(oblastId: oblastId, cityId: null, districtId: null);
  }

  /// Selects (or clears) the city — the second cascade level. Pass
  /// `cityId: null` to clear the city scope; that also clears any district,
  /// since a district is only meaningful alongside its city. The oblast is left
  /// intact (the user stays within the chosen region).
  ///
  /// A user-driven mutator: marks [_userTouchedLocality] so
  /// [prefillFromProfileIfNeeded] never overwrites this choice again this
  /// session, even a deliberate clear.
  void selectCity({required String? cityId}) {
    _userTouchedLocality = true;
    state = state.copyWith(
      cityId: cityId,
      districtId: cityId == null ? null : state.districtId,
    );
  }

  /// Selects (or clears) the district — the optional third cascade level. Pass
  /// `districtId: null` to clear / skip it.
  ///
  /// A district is only meaningful alongside a city: setting a non-null district
  /// while no city is selected is dropped (the cascade integrity invariant). The
  /// screen always picks a city first, so this guard only ever matters for a
  /// stray/out-of-order call.
  ///
  /// A user-driven mutator: marks [_userTouchedLocality] so
  /// [prefillFromProfileIfNeeded] never overwrites this choice again this
  /// session, even a deliberate clear. Marked even on the dropped/no-op path
  /// above — a stray call is still a signal the caller is UI-driven, not the
  /// seed path.
  void selectDistrict({required String? districtId}) {
    _userTouchedLocality = true;
    if (districtId != null && state.cityId == null) return;
    state = state.copyWith(districtId: districtId);
  }

  /// Single-select toggle for the category rail (Variant A) / legacy grid.
  /// Selecting a new tile replaces the prior category; tapping the
  /// already-selected tile clears it.
  void toggleServiceType(String categoryKey) {
    state = state.copyWith(
      categoryKey: state.categoryKey == categoryKey ? null : categoryKey,
    );
  }

  /// Sets the upper price bound (the MAX field / right slider thumb).
  ///
  /// A value at/above [kSearchPriceCeiling] (or null) means "будь-яка" (no upper
  /// bound) — [SearchFilters.maxPrice] is cleared. Otherwise the value is clamped
  /// to `[0, kSearchPriceCeiling]`.
  ///
  /// `min <= max` is enforced at this boundary: lowering the ceiling below the
  /// current lower bound pulls the lower bound down with it, so the UI can never
  /// emit an inverted pair the backend would reject with a 400.
  void setMaxPrice(double? maxPrice) {
    final double? nextMax =
        (maxPrice == null || maxPrice >= kSearchPriceCeiling)
        ? null
        : maxPrice.clamp(0.0, kSearchPriceCeiling);

    // Pull the lower bound down if the new ceiling drops below it (only possible
    // when a finite ceiling is set; a cleared ceiling is "no upper bound").
    double? nextMin = state.minPrice;
    if (nextMax != null && nextMin != null && nextMin > nextMax) {
      nextMin = nextMax;
    }

    state = state.copyWith(minPrice: nextMin, maxPrice: nextMax);
  }

  /// Sets the lower price bound (the MIN field / left slider thumb).
  ///
  /// A value `<= 0` (or null) means "no lower bound" — [SearchFilters.minPrice]
  /// is cleared. Otherwise the value is clamped to `[0, kSearchPriceCeiling]`.
  ///
  /// `min <= max` is enforced at this boundary: raising the floor above the
  /// current ceiling pushes the ceiling up with it, so the pair stays valid.
  void setMinPrice(double? minPrice) {
    final double? nextMin = (minPrice == null || minPrice <= 0)
        ? null
        : minPrice.clamp(0.0, kSearchPriceCeiling);

    // Push the ceiling up if the new floor rises above it. A null ceiling means
    // "no upper bound" (already >= any floor), so it needs no adjustment.
    double? nextMax = state.maxPrice;
    if (nextMin != null && nextMax != null && nextMin > nextMax) {
      nextMax = nextMin >= kSearchPriceCeiling ? null : nextMin;
    }

    state = state.copyWith(minPrice: nextMin, maxPrice: nextMax);
  }

  /// Sets both price bounds atomically from a single range-slider drag.
  ///
  /// Applies the same clear/clamp semantics as [setMinPrice] / [setMaxPrice]
  /// (min `<= 0` → cleared, max `>= kSearchPriceCeiling` → cleared) and enforces
  /// `min <= max` in one pass so a drag can never momentarily emit an inverted
  /// pair. When both resolve to finite values with `min > max`, they are
  /// coalesced to the lower of the two.
  void setPriceRange({double? min, double? max}) {
    double? nextMin = (min == null || min <= 0)
        ? null
        : min.clamp(0.0, kSearchPriceCeiling);
    double? nextMax = (max == null || max >= kSearchPriceCeiling)
        ? null
        : max.clamp(0.0, kSearchPriceCeiling);

    if (nextMin != null && nextMax != null && nextMin > nextMax) {
      // Inverted finite pair — collapse to the lower value.
      nextMin = nextMax;
    }

    state = state.copyWith(minPrice: nextMin, maxPrice: nextMax);
  }

  /// Clears every filter back to an empty [SearchFilters].
  void reset() => state = const SearchFilters();
}

/// Second-level service selection for the Variant A category → service flow.
///
/// The redesign introduces a SERVICE selection (the chips inside a category's
/// drawer) alongside the existing single category key on [SearchFilters]. This
/// is a multi-select set of service-option keys scoped to the currently chosen
/// category.
///
/// WIRE (Phase 13.11): this selection is folded into [SearchFilters.serviceTypeSlugs]
/// at "Apply" time by `SearchFiltersScreen._onShowMasters` (the base controller
/// never stores the slugs itself), and the repository emits each slug as a
/// repeated `serviceTypeSlugs` query param to `/search/masters` + `/search/salons`
/// (OR / union semantics — the provider must offer ANY selected service). The set is
/// CLEARED on a category change (see the rail's `_toggle`) so a stale
/// cross-category slug never reaches the wire.
///
/// keepAlive + auth-watched for the same reasons as [SearchFiltersController]:
/// selections survive the push to results and reset on a fresh session.
@Riverpod(keepAlive: true)
class SearchServiceSelectionController
    extends _$SearchServiceSelectionController {
  @override
  Set<String> build() {
    // Reset to an empty set whenever the session changes (logout → login) —
    // the same self-clearing pattern every keepAlive per-user provider uses.
    //
    // The category-change reset is driven imperatively (the rail/sheet call
    // [clear] when the parent category changes) rather than by watching
    // [searchFiltersControllerProvider] here: watching the whole filter set
    // would wrongly drop the service selection on an unrelated mutation (a
    // price drag, a city pick), since this generated notifier's `build()`
    // ref.watch cannot `.select` a single slice.
    ref.watch(authProvider);
    return const <String>{};
  }

  /// Toggles a service-option key within the active category. Adds it when
  /// absent, removes it when present — multi-select, mirroring the preview's
  /// `_toggleService`.
  void toggle(String serviceKey) {
    final Set<String> next = <String>{...state};
    if (!next.add(serviceKey)) next.remove(serviceKey);
    state = next;
  }

  /// Clears the selected services (paired with a category change / reset).
  void clear() => state = const <String>{};
}
