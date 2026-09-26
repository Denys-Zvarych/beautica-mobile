// Phase 352 D3 — the generic least-recently-used map behind BOTH the
// «Населений пункт» autocomplete (`SettlementSearchCache`, Phase 347) and the
// «Пошук» suggestion list (`search_suggestions_provider.dart`).
//
// Promoted (not copied) from `SettlementSearchCache`'s own `LinkedHashMap` +
// recency-bump-on-`get` + evict-eldest-on-`put` core
// (`settlement_search_cache.dart`, pre-352). `SettlementSearchCache` now
// COMPOSES this class instead of holding the map itself; its public API
// (`get`/`put`/`provisionalFor`/`clear`/`length`/`capacity`) is unchanged, so
// its existing tests prove the promotion did not move the behaviour.
//
// Pure Dart: no Flutter imports.

import 'dart:collection';

/// A capacity-bounded least-recently-used map.
///
/// [get] returns the value for [K] and bumps its recency (moves it to "most
/// recently used"). [put] stores a value, evicting the LEAST recently used
/// entry once [capacity] is exceeded. [peek] reads without touching recency —
/// for a caller that needs to inspect an entry without counting that read as a
/// use (e.g. a provisional-narrowing scan over every cached entry).
class LruCache<K, V> {
  LruCache(this.capacity)
    : assert(capacity > 0, 'a zero-capacity cache would evict every put');

  /// Maximum number of entries before the eldest is evicted.
  final int capacity;

  // Insertion order == recency order: [get] and [put] re-insert at the end, so
  // the FIRST key is always the least recently used.
  final LinkedHashMap<K, V> _entries = LinkedHashMap<K, V>();

  /// Number of cached entries.
  int get length => _entries.length;

  /// Every cached entry, oldest (least recently used) first. Read-only — does
  /// not affect recency.
  Iterable<MapEntry<K, V>> get entries => _entries.entries;

  /// The value for [key], or `null` on a miss. A hit bumps recency.
  V? get(K key) {
    final V? value = _entries.remove(key);
    if (value == null) return null;
    _entries[key] = value;
    return value;
  }

  /// The value for [key] without bumping recency, or `null` on a miss.
  V? peek(K key) => _entries[key];

  /// Stores [value] under [key], evicting the eldest entry once [capacity] is
  /// exceeded.
  void put(K key, V value) {
    _entries
      ..remove(key)
      ..[key] = value;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// Drops every entry.
  void clear() => _entries.clear();
}
