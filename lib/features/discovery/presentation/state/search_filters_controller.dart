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

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../auth/presentation/auth_notifier.dart';
import '../../domain/search_filters.dart';

part 'search_filters_controller.g.dart';

/// Price ceiling at/above which the «до N грн» readout collapses to "будь-яка"
/// (any) and [SearchFilters.maxPrice] is cleared (no upper bound sent).
const double kSearchPriceCeiling = 5000;

/// The single-thumb price slider's discrete step count (0 → 5000 in 100-грн
/// increments). Matches the approved preview's `divisions: 50`.
const int kSearchPriceDivisions = 50;

/// Human-readable display labels for the current [SearchFilters] selection.
///
/// Kept OUT of [SearchFilters] (the wire model holds ids/slugs only). Both
/// fields are null when nothing is selected, so the row chrome falls back to its
/// placeholder.
@immutable
class SearchFilterLabels {
  const SearchFilterLabels({this.cityName, this.categoryName});

  /// Display name of the selected city (e.g. «Львів»), or null.
  final String? cityName;

  /// Display name of the selected service category (e.g. «Манікюр»), or null.
  final String? categoryName;

  SearchFilterLabels copyWith({
    String? Function()? cityName,
    String? Function()? categoryName,
  }) {
    return SearchFilterLabels(
      cityName: cityName != null ? cityName() : this.cityName,
      categoryName: categoryName != null ? categoryName() : this.categoryName,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchFilterLabels &&
          other.cityName == cityName &&
          other.categoryName == categoryName;

  @override
  int get hashCode => Object.hash(cityName, categoryName);
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

  /// Sets (or clears, when [name] is null) the selected-city display label.
  void setCityName(String? name) =>
      state = state.copyWith(cityName: () => name);

  /// Sets (or clears, when [name] is null) the selected-category display label.
  void setCategoryName(String? name) =>
      state = state.copyWith(categoryName: () => name);

  /// Clears both labels (paired with [SearchFiltersController.reset]).
  void reset() => state = const SearchFilterLabels();
}

/// The Пошук screen's filter state — IS a [SearchFilters]. The screen watches
/// this and the CTA forwards `state` to the results screen.
@Riverpod(keepAlive: true)
class SearchFiltersController extends _$SearchFiltersController {
  @override
  SearchFilters build() {
    // Reset to an empty filter set whenever the session changes (logout →
    // login) — the same self-clearing pattern every keepAlive per-user provider
    // uses. Without this, one user's last search would leak to the next login.
    ref.watch(authProvider);
    return const SearchFilters();
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

  /// Selects a city (and optional district). Pass `cityId: null` to clear the
  /// city scope — that also clears any district, since a district is only
  /// meaningful alongside its city.
  void selectCity({required String? cityId, String? districtId}) {
    state = state.copyWith(
      cityId: cityId,
      districtId: cityId == null ? null : districtId,
    );
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
/// CONTRACT NOTE (outstanding): [SearchFilters] (the wire-facing request model)
/// carries NO service-key field yet, so these selections are NOT sent to the
/// discovery backend — the search endpoints expose no per-service filter. The
/// set is kept here, forward-wired, exactly like [SearchFiltersController]'s
/// `query` (INERT in v1). Persisting it on the request is a future contract
/// addition (a `serviceKeys`/`serviceTypeKeys` query param) owned by
/// `backend-dev`.
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
