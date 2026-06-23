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

  /// Sets the free-text query.
  ///
  /// INERT backend-side in v1: the discovery search endpoints expose no
  /// free-text param yet, so the repository drops [SearchFilters.query]. The
  /// field is kept wired for forward-compatibility (the field stays present and
  /// is carried in `extra` to the results screen). A blank/whitespace value is
  /// normalised to null so an empty box never narrows anything.
  void setQuery(String? query) {
    final String? trimmed = query?.trim();
    final String? next = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    state = state.copyWith(query: next);
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

  /// Single-select toggle for the «Вид послуги» grid. Selecting a new tile
  /// replaces the prior category; tapping the already-selected tile clears it.
  void toggleServiceType(String categoryKey) {
    state = state.copyWith(
      categoryKey: state.categoryKey == categoryKey ? null : categoryKey,
    );
  }

  /// Sets the price ceiling from the single-thumb slider.
  ///
  /// A value at/above [kSearchPriceCeiling] means "будь-яка" (no upper bound) —
  /// [SearchFilters.maxPrice] is cleared. [SearchFilters.minPrice] is never set
  /// by this single-thumb control (it stays null). Pass null to clear directly.
  void setMaxPrice(double? maxPrice) {
    final double? next = (maxPrice == null || maxPrice >= kSearchPriceCeiling)
        ? null
        : maxPrice;
    state = state.copyWith(maxPrice: next);
  }

  /// Clears every filter back to an empty [SearchFilters].
  void reset() => state = const SearchFilters();
}
