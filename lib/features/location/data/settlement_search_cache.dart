// Phase 347 — the in-memory result cache behind the «Населений пункт»
// autocomplete.
//
// Two jobs, both local and both free:
//
//   1. EXACT HITS ([get]). A query the session has already answered is served
//      again with no request: backspacing «льві» → «льв», or re-opening the
//      sheet on a term typed earlier. The settlement taxonomy is Flyway-seeded
//      reference data that cannot change while the app runs, so there is no
//      TTL; the bound is purely a size one ([kSettlementSearchCacheSize]).
//
//   2. PROVISIONAL ROWS ([provisionalFor]). While the debounced request for a
//      LONGER term is still pending, the rows of the longest cached term the
//      typed text extends — down to the blank-query major list — are narrowed
//      by NAME prefix and shown at once. Prefix-only is deliberate: it is an
//      exact subset of the server's tier 1 (`ILIKE term%`), so a provisional
//      row is always one the server would also return. The server's answer
//      still replaces them (its trigram tier adds rows no ancestor held).
//
// Pure Dart: no Flutter imports.
//
// Phase 352 D3 — the LinkedHashMap + recency/eviction core this class used to
// hold directly is PROMOTED to `core/cache/lru_cache.dart` as generic
// `LruCache<K, V>`. This class now COMPOSES it (`_lru`) and keeps every public
// member (`capacity`, `get`, `put`, `provisionalFor`, `clear`, `length`)
// byte-for-byte, so the existing autocomplete + cache tests prove the
// promotion moved no behaviour.

import '../../../core/cache/lru_cache.dart';
import '../domain/settlement.dart';

/// How many settled queries the session keeps. 64 covers every prefix of a
/// handful of names typed in one sitting at a few KB each (≤ 20 rows a query).
const int kSettlementSearchCacheSize = 64;

/// Unicode-aware whitespace run (a non-breaking space collapses like a plain
/// one), as backend `SettlementSearchService.WHITESPACE`.
final RegExp _whitespace = RegExp(r'\s+', unicode: true);

/// Every apostrophe variant a keyboard can emit — backend
/// `SettlementSearchService.APOSTROPHES`, character class copied verbatim.
final RegExp _apostrophes = RegExp("['ʼ‘´]");

/// The apostrophe `cities.name_uk` actually stores (U+2019) — backend
/// `SettlementSearchService.STORED_APOSTROPHE`.
const String _storedApostrophe = '’';

/// The cache key for [query], and the form both sides of a provisional prefix
/// match are compared in.
///
/// Mirrors backend `SettlementSearchService#normalize` exactly: trim, collapse
/// whitespace runs to one space, fold the apostrophe variants onto the STORED
/// U+2019, lower-case. Mirroring the server is what makes «Кам'янка» typed on a
/// desktop keyboard hit the same cache entry — and prefix-match the same
/// stored «Кам’янка» — as the server's own tier 1.
String normalizeSettlementQuery(String query) {
  final String trimmed = query.trim();
  if (trimmed.isEmpty) return '';
  return trimmed
      .replaceAll(_whitespace, ' ')
      .replaceAll(_apostrophes, _storedApostrophe)
      .toLowerCase();
}

/// A least-recently-used map of normalized query → the server's rows for it.
///
/// Holds SUCCESSES only — the caller never puts a failure, so a 429 or a
/// network error can never be replayed from here.
class SettlementSearchCache {
  SettlementSearchCache({this.capacity = kSettlementSearchCacheSize})
    : assert(capacity > 0, 'a zero-capacity cache would evict every put'),
      _lru = LruCache<String, _Entry>(capacity);

  /// Maximum number of entries before the eldest is evicted.
  final int capacity;

  final LruCache<String, _Entry> _lru;

  /// Number of cached queries.
  int get length => _lru.length;

  /// The rows for normalized [key], or `null` on a miss. A hit bumps recency.
  List<Settlement>? get(String key) => _lru.get(key)?.rows;

  /// Stores [rows] under normalized [key], evicting the eldest entry once
  /// [capacity] is exceeded.
  ///
  /// Stored by IDENTITY, not copied: a later hit hands back the very instance
  /// the first answer produced, so the settlement field's identity-keyed
  /// option memo stays a pointer compare across a backspace. Callers treat the
  /// list as read-only (the repository builds a fresh one per response).
  void put(String key, List<Settlement> rows) => _lru.put(key, _Entry(rows));

  /// Rows to show for normalized [typed] before the server has answered it,
  /// or `null` when the cache has nothing useful.
  ///
  /// - An EXACT hit returns the server's own rows for [typed] unfiltered —
  ///   they ARE the answer, fuzzy rows included.
  /// - Otherwise the longest cached key that [typed] extends (the blank
  ///   major list included) is narrowed to rows whose normalized NAME — never
  ///   the composed «м. Львів, Львівська обл.» label — starts with [typed],
  ///   keeping the server's order.
  /// - `null` when no ancestor is cached or none of its rows match.
  ///
  /// Read-only: does not bump recency, because nothing was actually served.
  List<Settlement>? provisionalFor(String typed) {
    final _Entry? exact = _lru.peek(typed);
    if (exact != null) return exact.rows;

    String? ancestor;
    _Entry? ancestorEntry;
    for (final MapEntry<String, _Entry> entry in _lru.entries) {
      final String key = entry.key;
      if (typed.startsWith(key) &&
          (ancestor == null || key.length > ancestor.length)) {
        ancestor = key;
        ancestorEntry = entry.value;
      }
    }
    if (ancestorEntry == null) return null;

    final List<Settlement> source = ancestorEntry.rows;
    final List<String> names = ancestorEntry.normalizedNames;
    final List<Settlement> rows = <Settlement>[
      for (int i = 0; i < source.length; i++)
        if (names[i].startsWith(typed)) source[i],
    ];
    return rows.isEmpty ? null : rows;
  }

  /// Drops every entry. Called on logout (security LOW, phase 347 audit): the
  /// cache is keepAlive, and the queries a user typed must not survive into
  /// the next account's session on the same device.
  void clear() => _lru.clear();
}

/// One cached answer plus its rows' names, normalized ONCE at [put] time
/// (perf I1) rather than on every keystroke's [provisionalFor].
final class _Entry {
  _Entry(this.rows)
    : normalizedNames = List<String>.unmodifiable(<String>[
        for (final Settlement s in rows) normalizeSettlementQuery(s.name),
      ]);

  final List<Settlement> rows;
  final List<String> normalizedNames;
}
