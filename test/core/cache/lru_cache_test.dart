// Phase 352 D3 — LruCache<K, V>: the generic core promoted out of
// SettlementSearchCache. Mirrors that class's own LRU test group so the
// promotion is proven behaviour-identical, plus record-key equality (the
// suggestion cache's key type).

import 'package:beautica_mobile/core/cache/lru_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LruCache eviction / recency', () {
    test('evicts the eldest entry once capacity is exceeded', () {
      final cache = LruCache<String, int>(3)
        ..put('a', 1)
        ..put('b', 2)
        ..put('c', 3);
      expect(cache.length, 3);

      cache.put('d', 4);
      expect(cache.length, 3);
      expect(cache.get('a'), isNull, reason: 'the eldest was evicted');
      expect(cache.get('b'), isNotNull);
      expect(cache.get('c'), isNotNull);
      expect(cache.get('d'), isNotNull);
    });

    test('get bumps recency, protecting the entry from the next eviction', () {
      final cache = LruCache<String, int>(2)
        ..put('a', 1)
        ..put('b', 2);
      expect(cache.get('a'), 1); // 'a' is now the most recent.
      cache.put('c', 3); // evicts 'b', the now-eldest.
      expect(cache.get('b'), isNull);
      expect(cache.get('a'), 1);
      expect(cache.get('c'), 3);
    });

    test('a miss returns null and does not affect recency', () {
      final cache = LruCache<String, int>(2)..put('a', 1);
      expect(cache.get('zzz'), isNull);
      expect(cache.length, 1);
    });

    test('put overwrites an existing key without growing length', () {
      final cache = LruCache<String, int>(2)
        ..put('a', 1)
        ..put('a', 11);
      expect(cache.length, 1);
      expect(cache.get('a'), 11);
    });

    test('peek reads without bumping recency', () {
      final cache = LruCache<String, int>(2)
        ..put('a', 1)
        ..put('b', 2);
      expect(cache.peek('a'), 1); // read, but must NOT bump recency
      cache.put('c', 3); // evicts the still-eldest 'a'
      expect(cache.get('a'), isNull);
      expect(cache.get('b'), 2);
      expect(cache.get('c'), 3);
    });

    test('clear drops every entry', () {
      final cache = LruCache<String, int>(4)
        ..put('a', 1)
        ..put('b', 2)
        ..clear();
      expect(cache.length, 0);
      expect(cache.get('a'), isNull);
    });
  });

  group('record keys (SuggestionCacheKey shape)', () {
    test('two keys with equal fields hit the same entry', () {
      final cache = LruCache<(String, String?, String?), int>(4);
      cache.put(('нар', 'city-1', null), 42);
      expect(cache.get(('нар', 'city-1', null)), 42);
    });

    test('a differing field is a different entry (place-scoped key)', () {
      final cache = LruCache<(String, String?, String?), int>(4);
      cache.put(('нар', 'city-1', null), 1);
      cache.put(('нар', 'city-2', null), 2);
      expect(cache.get(('нар', 'city-1', null)), 1);
      expect(cache.get(('нар', 'city-2', null)), 2);
      expect(cache.get(('нар', null, null)), isNull);
    });
  });
}
