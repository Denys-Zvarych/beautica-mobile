// Phase 13.2 — Discovery search filters + paged result envelope.
//
// [SearchFilters] is the pure-Dart filter set the UI builds and the repository
// translates into the generated `MasterSearchRequest` / `SalonSearchRequest`
// query params. [SearchPage] is a generic immutable page envelope returned by
// the repository (the data layer maps the wrapped `PageResponse…` DTO into it).
//
// Generic-freezed note: a generic `@freezed class SearchPage<T>` is brittle with
// the current freezed/build_runner toolchain (the generated mixin trips on the
// type parameter). [SearchPage] is therefore a HAND-WRITTEN immutable generic
// class with explicit `==`/`hashCode`/`copyWith`, per the phase doc's stated
// fallback. [SearchFilters] (non-generic) stays on freezed.
//
// Pure Dart: no Flutter imports in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'search_filters.freezed.dart';

/// Allow-listed sort orderings for the discovery endpoints.
///
/// Maps 1:1 onto the backend `SearchSort` enum
/// (`com.beautica.search.dto.SearchSort`). The [wireValue] is the exact enum
/// constant name the `?sort=` query param binds to — caller text never reaches
/// an `ORDER BY` server-side (the enum binding is the injection control).
///
/// Salon side: the backend honours [priceAsc]/[priceDesc] as a price-band
/// ordering but falls back to name order for [ratingDesc]/[reviewsDesc] (salons
/// have no per-row rating/review column to sort on cheaply). The client sends
/// the same enum regardless; the fallback is the backend's concern.
enum SearchSort {
  /// Highest average rating first. The default ordering.
  ratingDesc('RATING_DESC'),

  /// Cheapest effective price first.
  priceAsc('PRICE_ASC'),

  /// Most expensive effective price first.
  priceDesc('PRICE_DESC'),

  /// Most-reviewed first.
  reviewsDesc('REVIEWS_DESC');

  const SearchSort(this.wireValue);

  /// The backend enum constant name this option binds to on the wire.
  final String wireValue;
}

/// The discovery filter set built by the search UI.
///
/// All fields are nullable — a null field means "no constraint" and is omitted
/// from the request the repository sends.
@freezed
abstract class SearchFilters with _$SearchFilters {
  const factory SearchFilters({
    /// Free-text name / service query. Trimmed + forwarded to the backend `q`
    /// param by the repository (empty/blank → omitted). The backend normalises a
    /// `q` shorter than 3 characters to null (location-scoped results) — the
    /// client sends it verbatim.
    String? query,

    /// Platform category key/slug to filter by (e.g. "HAIR"), or null for all.
    String? categoryKey,

    /// City id to scope results to, or null for all cities.
    String? cityId,

    /// District id to scope results to, or null for all districts. Only
    /// meaningful alongside [cityId].
    String? districtId,

    /// Minimum average rating filter, or null for no rating floor.
    double? minRating,

    /// Minimum price filter, or null for no lower bound.
    double? minPrice,

    /// Maximum price filter, or null for no upper bound.
    double? maxPrice,

    /// Result ordering. Defaults to [SearchSort.ratingDesc] (the backend
    /// default), so it is always forwarded — never null.
    @Default(SearchSort.ratingDesc) SearchSort sort,
  }) = _SearchFilters;
}

/// An immutable, generic page of search results.
///
/// Hand-written (not freezed) because the current toolchain does not reliably
/// generate a freezed mixin for a generic data class. Carries the items plus the
/// paging metadata the infinite-scroll controller (13.3) needs to decide
/// whether more pages remain.
@immutable
class SearchPage<T> {
  const SearchPage({
    required this.items,
    required this.page,
    required this.totalPages,
    required this.totalElements,
  });

  /// The results on this page. Empty for a no-match query (still a valid page).
  final List<T> items;

  /// Zero-based index of this page.
  final int page;

  /// Total number of pages available for the query.
  final int totalPages;

  /// Total number of matching elements across all pages.
  final int totalElements;

  /// Whether a subsequent page exists (`page < totalPages - 1`).
  bool get hasMore => page < totalPages - 1;

  SearchPage<T> copyWith({
    List<T>? items,
    int? page,
    int? totalPages,
    int? totalElements,
  }) {
    return SearchPage<T>(
      items: items ?? this.items,
      page: page ?? this.page,
      totalPages: totalPages ?? this.totalPages,
      totalElements: totalElements ?? this.totalElements,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SearchPage<T> &&
        _listEquals(other.items, items) &&
        other.page == page &&
        other.totalPages == totalPages &&
        other.totalElements == totalElements;
  }

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(items), page, totalPages, totalElements);

  @override
  String toString() =>
      'SearchPage<$T>(items: ${items.length}, page: $page, '
      'totalPages: $totalPages, totalElements: $totalElements)';
}

/// Order-sensitive element-wise list equality used by [SearchPage].
bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
