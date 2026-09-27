// Phase 347 — SettlementSearchCache: the LRU behind the instant autocomplete,
// and the query normalisation that keys it.

import 'package:beautica_mobile/features/location/data/settlement_search_cache.dart';
import 'package:beautica_mobile/features/location/domain/settlement.dart';
import 'package:flutter_test/flutter_test.dart';

Settlement _s(String id, String name) =>
    Settlement(id: id, name: name, oblastName: 'Львівська');

final Settlement _lviv = _s('lviv', 'Львів');
final Settlement _lvivVillage = _s('lviv-v', 'Львів');
final Settlement _lvivske = _s('lvivske', 'Львівське');
// Contains «льві» but does not START with it — the case that tells a prefix
// narrowing apart from a `contains` one.
final Settlement _zalviv = _s('zalviv', 'Зальвівка');
final Settlement _kyiv = _s('kyiv', 'Київ');

void main() {
  group('LRU', () {
    test('evicts the eldest entry on the 65th put', () {
      final cache = SettlementSearchCache();
      for (int i = 0; i < kSettlementSearchCacheSize; i++) {
        cache.put('q$i', <Settlement>[_lviv]);
      }
      expect(cache.length, 64);
      expect(cache.get('q0'), isNotNull, reason: 'still inside the bound');

      // q0 was just bumped, so q1 is now the eldest.
      cache.put('q64', <Settlement>[_kyiv]);
      expect(cache.length, 64);
      expect(cache.get('q1'), isNull, reason: 'the eldest was evicted');
      expect(cache.get('q0'), isNotNull, reason: 'get bumped its recency');
      expect(cache.get('q64'), isNotNull);
    });

    test('get bumps recency; a miss returns null', () {
      final cache = SettlementSearchCache(capacity: 2)
        ..put('a', <Settlement>[_lviv])
        ..put('b', <Settlement>[_kyiv]);
      expect(cache.get('a'), isNotNull); // a is now the most recent
      cache.put('c', <Settlement>[_lviv]);
      expect(cache.get('b'), isNull);
      expect(cache.get('a'), isNotNull);
      expect(cache.get('zzz'), isNull);
    });

    test('a hit returns the stored instance itself', () {
      final List<Settlement> rows = <Settlement>[_lviv];
      final cache = SettlementSearchCache()..put('льв', rows);
      expect(identical(cache.get('льв'), rows), isTrue);
    });
  });

  group('provisionalFor', () {
    test(
      'narrows the cached ancestor to NAME-prefix rows, in server order',
      () {
        final cache = SettlementSearchCache()
          ..put('льв', <Settlement>[_lvivske, _zalviv, _lviv, _lvivVillage]);

        expect(cache.provisionalFor('льві'), <Settlement>[
          _lvivske,
          _lviv,
          _lvivVillage,
        ]);
      },
    );

    test('the longest cached ancestor wins over the blank majors list', () {
      final cache = SettlementSearchCache()
        ..put('', <Settlement>[_lviv, _kyiv])
        ..put('льв', <Settlement>[_lviv, _lvivVillage]);

      expect(cache.provisionalFor('льві'), <Settlement>[_lviv, _lvivVillage]);
    });

    test('the blank majors list serves a 1-2 character term', () {
      final cache = SettlementSearchCache()
        ..put('', <Settlement>[_lviv, _kyiv]);
      expect(cache.provisionalFor('ки'), <Settlement>[_kyiv]);
    });

    test('an exact hit returns the server rows unfiltered', () {
      final cache = SettlementSearchCache()
        ..put('льв', <Settlement>[_lviv, _zalviv]);
      expect(cache.provisionalFor('льв'), <Settlement>[_lviv, _zalviv]);
    });

    test('null when no ancestor is cached, or none of its rows match', () {
      final cache = SettlementSearchCache();
      expect(cache.provisionalFor('льв'), isNull);
      cache.put('', <Settlement>[_kyiv]);
      expect(cache.provisionalFor('льв'), isNull);
    });

    test(
      'matches a name whose stored apostrophe differs from the typed one',
      () {
        final Settlement kamianka = _s('kam', 'Кам’янка');
        final cache = SettlementSearchCache()..put('', <Settlement>[kamianka]);
        expect(
          cache.provisionalFor(normalizeSettlementQuery("Кам'ян")),
          <Settlement>[kamianka],
        );
      },
    );
  });

  group('normalizeSettlementQuery', () {
    test('lower-cases, trims and collapses whitespace (NBSP included)', () {
      expect(
        normalizeSettlementQuery('  Івано \u00A0 Франківськ '),
        'івано франківськ',
      );
      expect(normalizeSettlementQuery('   '), '');
    });

    test('folds every keyboard apostrophe onto the stored U+2019', () {
      for (final String a in <String>["'", 'ʼ', '‘', '´', '’']) {
        expect(normalizeSettlementQuery('Кам$aянка'), 'кам’янка');
      }
    });
  });
}
