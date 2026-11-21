// The free-text search bounds shared by the discovery filters and every other
// host of `SearchQueryField` (the «Клієнти» tab passes its own 2 / 50).
//
// MOVED from `features/discovery/domain/search_filters.dart` so
// `shared/widgets/search_query_field.dart` no longer imports a feature. That
// file re-exports this one, so every existing discovery import keeps working;
// values and behaviour are unchanged.

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

/// Whether [raw] is a non-empty term that is still too short for the backend to
/// honour — i.e. the [SearchQueryOutcome.belowMinimum] predicate, evaluated
/// without touching any state.
///
/// Single-sourced here beside [kSearchMinQueryLength] so the controller, the
/// search field's error chrome and the «Показати майстрів» CTA gate can never
/// drift apart on where the threshold sits. Trimmed before measuring, exactly as
/// `SearchFiltersController._normalizeQuery` does, so «  ма  » is 2 characters
/// and not 6.
///
/// [min] (additive, M509) overrides the threshold for hosts with a different
/// backend bound (the «Клієнти» `q` is 2–50); the default is discovery's.
bool isBelowSearchMinimum(String? raw, {int min = kSearchMinQueryLength}) {
  final int length = (raw ?? '').trim().length;
  return length > 0 && length < min;
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
