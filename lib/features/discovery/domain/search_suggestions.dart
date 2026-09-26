// Phase 352 D4 — the LOCAL (device-side) suggestion matcher.
//
// Used ONLY for the national instant-row layer (D2: "no place chosen" gives
// synchronous rows from `approvedCategoriesProvider` on every keystroke,
// replaced by the server's answer once it lands) and as the fallback on a
// network error / 429 while national. It ranks CATEGORY labels only — the
// device does not hold the service-type catalogue, so SERVICE rows only ever
// come from the backend (`search_suggestion_repository.dart`).
//
// Mirrors the backend `SearchSuggestionService` fold/match/rank/cap rules
// (Phase 331 D4) EXACTLY, so the two never disagree about what a term
// matches:
//   - fold with [foldSearchLabel] (case + Latin diacritic + apostrophe +
//     whitespace insensitive, the same fold the backend's
//     `NormalizedSearchQuery.foldApostrophes` + `toLowerCase(Locale.ROOT)`
//     achieve server-side);
//   - 1–2 folded characters → word-start match only (the label, or any
//     whitespace/hyphen-separated word in it, starts with the term);
//   - 3+ folded characters → substring match (word-start still counts, as a
//     stronger rank);
//   - rank: label-start → word-start → substring, ties keep catalogue order;
//   - capped at [max] AFTER ranking (never before — a fixture with more
//     matches than the cap must still return the top [max], not the first
//     [max] found).
//
// Pure Dart: no Flutter imports in this file.

import '../../../shared/util/search_fold.dart';
import '../../services/domain/service_category_option.dart';
import 'search_suggestion.dart';

/// The suggestion list's row cap — mirrors `limit=6` sent to the backend
/// (Phase 352 D4; the backend's own cap is 8).
const int kSearchSuggestionMax = 6;

/// Splits a folded label into words on whitespace or a hyphen, for the
/// word-start match tier.
final RegExp _wordSplit = RegExp(r'[\s\-]+');

/// Local rank of [foldedLabel] against [foldedTerm]. `null` means no match at
/// all under the given [requireWordStart] tier.
_MatchRank? _rankOf(
  String foldedLabel,
  String foldedTerm, {
  required bool requireWordStart,
}) {
  if (foldedLabel.startsWith(foldedTerm)) return _MatchRank.labelStart;
  for (final String word in foldedLabel.split(_wordSplit)) {
    if (word.startsWith(foldedTerm)) return _MatchRank.wordStart;
  }
  if (!requireWordStart && foldedLabel.contains(foldedTerm)) {
    return _MatchRank.substring;
  }
  return null;
}

enum _MatchRank { labelStart, wordStart, substring }

/// Ranks [categories] against [typed] and returns up to [max] CATEGORY
/// suggestions, in D4 rank order (catalogue order preserved on a tie).
///
/// Returns an empty list for a blank [typed] (0 chars → no list, D4/D7).
///
/// [foldedLabels], when passed, MUST be parallel to [categories] (same
/// length, `foldedLabels[i] == foldSearchLabel(categories[i].displayName)`)
/// and is used instead of re-folding each label here — the caller
/// (`SearchSuggestions._resolve`, mobile-perf LOW cycle-1 fix) already folds
/// every category label once per build for its own exact-match check, so this
/// is the ONE shared place either need the fold, not two. Omitted (the
/// default), this function folds [categories] itself exactly as before —
/// existing callers are unaffected.
List<SearchSuggestion> matchSearchSuggestions(
  String typed,
  List<ServiceCategoryOption> categories, {
  int max = kSearchSuggestionMax,
  List<String>? foldedLabels,
}) {
  final String folded = foldSearchLabel(typed);
  if (folded.isEmpty) return const <SearchSuggestion>[];
  final bool requireWordStart = folded.length < 3;
  assert(
    foldedLabels == null || foldedLabels.length == categories.length,
    'foldedLabels must be parallel to categories',
  );

  final List<ServiceCategoryOption> labelStart = <ServiceCategoryOption>[];
  final List<ServiceCategoryOption> wordStart = <ServiceCategoryOption>[];
  final List<ServiceCategoryOption> substring = <ServiceCategoryOption>[];
  for (int i = 0; i < categories.length; i++) {
    final ServiceCategoryOption category = categories[i];
    final String foldedLabel =
        foldedLabels?[i] ?? foldSearchLabel(category.displayName);
    final _MatchRank? rank = _rankOf(
      foldedLabel,
      folded,
      requireWordStart: requireWordStart,
    );
    switch (rank) {
      case _MatchRank.labelStart:
        labelStart.add(category);
      case _MatchRank.wordStart:
        wordStart.add(category);
      case _MatchRank.substring:
        substring.add(category);
      case null:
        break;
    }
  }

  final List<ServiceCategoryOption> ranked = <ServiceCategoryOption>[
    ...labelStart,
    ...wordStart,
    ...substring,
  ];
  return <SearchSuggestion>[
    for (final ServiceCategoryOption c in ranked.take(max))
      SearchSuggestion(
        type: SearchSuggestionType.category,
        label: c.displayName,
        categoryKey: c.name,
      ),
  ];
}
