// Phase 352 — one suggestion row shown under the «Пошук» search field while
// typing.
//
// Mirrors the backend `SearchSuggestionResponse` (Phase 331 D1/D2) — a
// CATEGORY (the whole approved platform category, resolved via free text) or
// a SERVICE (a single admin-curated `ServiceType`, resolved via the rail
// category + service-type slug filter). Mapped from the generated
// `SearchSuggestionResponse` DTO by `search_suggestion_repository.dart`; the
// UI never sees the DTO.
//
// Pure Dart: no Flutter imports in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'search_suggestion.freezed.dart';

/// What a [SearchSuggestion] resolves to on tap (Phase 352 D5).
enum SearchSuggestionType {
  /// The whole approved platform category — tapping applies the label as
  /// free text (`SearchFilters.query`), which the backend resolves to the
  /// full category server-side.
  category,

  /// One admin-curated service type inside [SearchSuggestion.categoryKey] —
  /// tapping filters by the exact category + service-type slug, with the
  /// search box left empty (Open Q1, locked).
  service,
}

/// A single CATEGORY or SERVICE suggestion.
///
/// - [label]: the display string, shown both in the row and (CATEGORY only)
///   written into the search field on tap.
/// - [categoryKey]: the rail's `ServiceCategoryOption.name` — for a CATEGORY
///   row, its own key; for a SERVICE row, the key of the category it belongs
///   to (so tapping it can select the rail category too).
/// - [serviceTypeSlug]: the service-type slug to filter by — `null` for
///   CATEGORY, always set for SERVICE.
@freezed
abstract class SearchSuggestion with _$SearchSuggestion {
  const factory SearchSuggestion({
    required SearchSuggestionType type,
    required String label,
    required String categoryKey,
    String? serviceTypeSlug,
  }) = _SearchSuggestion;
}
