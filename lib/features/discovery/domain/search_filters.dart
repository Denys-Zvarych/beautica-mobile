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

/// Shortest free-text term the backend will actually honour on `q`.
///
/// A `q` of 1–2 characters is NOT a narrowing search server-side: the backend
/// answers it with an empty page plus an envelope `message` telling the user to
/// type at least this many characters. The client therefore treats a
/// below-minimum term as a BLOCKING ERROR, not as "still being typed": it is
/// never written into [SearchFilters.query] and never reaches the wire (see
/// `SearchFiltersController.setQuery`), the previously applied query is CLEARED
/// so no stale result set survives it, and the filters screen renders a red
/// error line under the search field AND disables «Показати майстрів». That CTA
/// gate is the containment boundary: because the search box exists only on the
/// filters screen, a below-minimum term can never travel to the results screen,
/// which therefore needs no blocked state of its own.
const int kSearchMinQueryLength = 3;

/// What `SearchFiltersController.setQuery` did with a raw term.
///
/// The three cases are deliberately distinguishable at the call site, because
/// the wire invariant on [SearchFilters.query] (null, or a term the backend will
/// honour) collapses [cleared] and [belowMinimum] into the same `null` — and the
/// UI must treat them very differently: an empty box is a perfectly valid
/// filters-only search, while a 1–2 character box is an error that blocks.
enum SearchQueryOutcome {
  /// The term was blank (or null) — [SearchFilters.query] is now null and the
  /// `q` param is omitted. NOT an error: searching on the other facets alone is
  /// legitimate.
  cleared,

  /// The term normalised to 1 … [kSearchMinQueryLength] - 1 characters — below
  /// what the backend honours. [SearchFilters.query] is CLEARED (an applied
  /// query must never outlive the term that produced it), the raw term is kept
  /// on `searchQueryDraftControllerProvider`, and the UI must surface a blocking
  /// error.
  belowMinimum,

  /// The term normalised to [kSearchMinQueryLength] or more characters and is
  /// now applied on [SearchFilters.query].
  applied,
}

/// Whether [raw] is a non-empty term that is still too short for the backend to
/// honour — i.e. the [SearchQueryOutcome.belowMinimum] predicate, evaluated
/// without touching any state.
///
/// Single-sourced here beside [kSearchMinQueryLength] so the controller, the
/// search field's error chrome and the «Показати майстрів» CTA gate can never
/// drift apart on where the threshold sits. Trimmed before measuring, exactly as
/// `SearchFiltersController._normalizeQuery` does, so «  ма  » is 2 characters
/// and not 6.
bool isBelowSearchMinimum(String? raw) {
  final int length = (raw ?? '').trim().length;
  return length > 0 && length < kSearchMinQueryLength;
}

/// Longest free-text term the backend will accept on `q`.
///
/// Mirrors the backend's `@Size(max = 100)` on `MasterSearchRequest.q` /
/// `SalonSearchRequest.q`. A longer term is not a wider search — it is a hard
/// 400, and the results screen's retry button would re-issue the identical
/// doomed request forever. Trimming alone does not help, since trim only strips
/// the ENDS of a pasted string.
///
/// Counted in **UTF-16 code units**, the unit Java's `String.length()` — and so
/// `@Size` — measures. That distinction is load-bearing: the search field's
/// `maxLength` truncates by GRAPHEME CLUSTER, so emoji or combining-mark pairs
/// can sit under the widget's cap at twice this many code units. The cap is
/// therefore enforced twice (sec LOW-1 / NEW-2): `SearchQueryField` clamps as
/// the user types, for immediate feedback, and `SearchFiltersController
/// .setQuery` re-clamps in code units as the correctness backstop every caller
/// inherits.
const int kSearchMaxQueryLength = 100;

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
    /// The APPLIED free-text name / service query — trimmed, and either null
    /// ("no term") or at least [kSearchMinQueryLength] characters long. Never
    /// holds a 1–2 character term: `SearchFiltersController.setQuery` CLEARS
    /// this field for those and reports [SearchQueryOutcome.belowMinimum]
    /// instead (the backend answers a below-minimum `q` with an empty page + a
    /// "type at least 3 characters" message, so sending it is a pointless round
    /// trip — and keeping the PREVIOUS term applied would leave stale results
    /// and a stale chip on screen under a term the user has already shortened).
    /// The raw text the user is mid-way through typing lives in the field's
    /// `TextEditingController` and, cross-screen, on
    /// `searchQueryDraftControllerProvider` — never here.
    ///
    /// Forwarded to the backend `q` param by the repository (null → omitted).
    String? query,

    /// Platform category key/slug to filter by (e.g. "HAIR"), or null for all.
    String? categoryKey,

    /// Platform service-type slugs the provider must offer, or empty for "no
    /// per-service constraint". Each entry is a `CategoryServiceOption.key`
    /// (a service-type slug) the second-level drawer chips key off.
    ///
    /// **OR / union semantics** — a provider is kept when it offers ANY of the
    /// slugs in the set (backend `serviceTypeSlugs` multi-valued param, enforced
    /// server-side; the client just sends the whole set). Emitted as repeated
    /// `serviceTypeSlugs=<slug>` query params by the repository; omitted entirely
    /// when empty.
    ///
    /// Order-insensitive in the [searchResultsProvider] family key: a [Set]
    /// participates in freezed's `==`/`hashCode` via `DeepCollectionEquality`,
    /// which hashes/compares sets WITHOUT regard to insertion order — so toggling
    /// the chips in a different order never re-keys or re-fetches the results.
    /// (The repository additionally sorts the slugs before emitting them so the
    /// assembled wire URI is deterministic.) Scoped to [categoryKey]; cleared
    /// whenever the category changes so a stale cross-category slug never reaches
    /// the wire.
    @Default(<String>{}) Set<String> serviceTypeSlugs,

    /// Oblast (region) id the city was funnelled through, or null when no region
    /// has been picked. The region is a MANDATORY narrowing step in the UI that
    /// always resolves to a [cityId]; there is NO whole-region search, so the
    /// oblast id is NOT sent to the backend (no `location.oblastId` param). It is
    /// persisted only so the picker can re-open the right city list and the
    /// applied-filter chips can show the region label. Cleared whenever [cityId]
    /// is cleared (a city is only meaningful within its region).
    String? oblastId,

    /// City id to scope results to, or null for all cities. Sent flat as
    /// `location.cityId`.
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

  const SearchFilters._();

  /// Number of distinct active filter facets, used to render the «(N)» badge
  /// next to the results top-bar filter icon.
  ///
  /// Each facet contributes at most 1: region, city, district, category, the
  /// per-service selection (any number of slugs counts once), and the price
  /// band (a min and/or a max counts once). [query] and [sort] are NOT facets,
  /// so the count maxes out at 6.
  ///
  /// Why [query] stays OUT even though the results screen now hosts a live
  /// search field: the badge exists to summarise the facets that are otherwise
  /// INVISIBLE on the results screen — the ones that live behind the filter
  /// icon. The query is the one facet that is fully visible there, echoed both
  /// as the field's text and as the applied-query chip beneath it. Counting it
  /// would report the same state twice and make «(1)» ambiguous between "a
  /// hidden filter is on" and "you typed something". [sort] is excluded for the
  /// same reason (it has its own always-visible pill).
  int get activeFilterCount {
    var count = 0;
    if (oblastId != null) count++;
    if (cityId != null) count++;
    if (districtId != null) count++;
    if (categoryKey != null) count++;
    if (serviceTypeSlugs.isNotEmpty) count++;
    if (minPrice != null || maxPrice != null) count++;
    return count;
  }
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
