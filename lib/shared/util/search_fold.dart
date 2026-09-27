// Phase 352 D4/D8 — the ONE case-, (Ukrainian/Latin) diacritic-, apostrophe-
// and whitespace-insensitive fold used for label matching across the app.
//
// Promoted out of `SearchableSelectField`'s private
// `_SearchableSelectSheetState._fold` (dropped the leading underscore, moved
// to a top-level function in a PURE-DART shared file — not left inside the
// Flutter-importing widget file — so the discovery domain layer, which must
// never import `package:flutter/*`, can share it too) and extended
// ADDITIVELY with apostrophe folding (every variant a keyboard can emit,
// collapsed to a plain `'`) and whitespace-run collapsing. Neither addition
// changes anything for `SearchableSelectField`'s own callers: category and
// service-type labels contain no apostrophes and no interior whitespace
// runs, so [foldSearchLabel] folds them exactly as the old `_fold` did.
//
// The «Пошук» suggestion matcher (`search_suggestions.dart`) and its
// debounced provider's cache key (`search_suggestions_provider.dart`) both
// need the apostrophe/whitespace rules — matching the backend's
// `SearchSuggestionService` folding (Phase 331 D4) exactly — so they share
// this ONE fold rather than a second copy.
//
// Pure Dart: no Flutter imports in this file.

/// Folds [input] for matching: trims, collapses interior whitespace runs to a
/// single space, folds every apostrophe variant onto a plain `'`, lower-cases,
/// and strips common Latin combining accents (so e.g. "ї" is left as-is —
/// Cyrillic is compared as-is, already lower-cased — and accented Latin such
/// as é → e is reachable from plain ASCII).
String foldSearchLabel(String input) {
  final String collapsed = input.trim().replaceAll(_searchWhitespace, ' ');
  final String lower = collapsed
      .replaceAll(_searchApostrophes, "'")
      .toLowerCase();
  final StringBuffer sb = StringBuffer();
  for (final int rune in lower.runes) {
    sb.writeCharCode(_foldSearchRune(rune));
  }
  return sb.toString();
}

/// Unicode-aware whitespace run, collapsed to a single space.
final RegExp _searchWhitespace = RegExp(r'\s+', unicode: true);

/// Every apostrophe variant a keyboard can emit, folded onto a plain `'`.
final RegExp _searchApostrophes = RegExp("['ʼ‘’´]");

int _foldSearchRune(int rune) {
  // Strip combining diacritical marks (U+0300–U+036F) → fold to a space so a
  // decomposed accented label still matches a plain-ASCII query.
  if (rune >= 0x0300 && rune <= 0x036F) {
    return 0x0020;
  }
  return _searchBaseLatin[rune] ?? rune;
}

// A small fold table for the accented Latin characters that realistically
// appear in Ukrainian/transliterated category labels. Cyrillic is compared
// as-is (already lowercased), which is the correct UA behaviour.
const Map<int, int> _searchBaseLatin = <int, int>{
  0x00E9: 0x0065, // é → e
  0x00E8: 0x0065, // è → e
  0x00EA: 0x0065, // ê → e
  0x00EB: 0x0065, // ë → e
  0x00E1: 0x0061, // á → a
  0x00E0: 0x0061, // à → a
  0x00E2: 0x0061, // â → a
  0x00E4: 0x0061, // ä → a
  0x00ED: 0x0069, // í → i
  0x00EC: 0x0069, // ì → i
  0x00EF: 0x0069, // ï → i
  0x00F3: 0x006F, // ó → o
  0x00F4: 0x006F, // ô → o
  0x00F6: 0x006F, // ö → o
  0x00FA: 0x0075, // ú → u
  0x00FC: 0x0075, // ü → u
  0x00E7: 0x0063, // ç → c
  0x00F1: 0x006E, // ñ → n
};
