// Phase 346 — `settlementQueryIsSearchable`, the client-side mirror of the
// server's `NormalizedSearchQuery.hasIndexServableRun`.
//
// WHY THIS IS PINNED SEPARATELY from the widget test that exercises it. This
// predicate is the only thing standing between a keystroke and an
// unauthenticated sequential scan of 25 698 rows, and it is a MIRROR: it is
// correct only for as long as it agrees with a Java method in another repo. A
// widget test proves "the hint showed"; these cases pin the exact shapes the
// server's own doc records as having defeated three weaker spellings of the
// same rule, so a future "simplify it to a length check" rewrite fails here
// with the reason attached rather than silently re-opening the hole.
//
// Pure Dart — no widget tree, no Riverpod.

import 'package:beautica_mobile/features/location/data/location_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a term the index can serve', () {
    test('three Cyrillic letters', () {
      expect(settlementQueryIsSearchable('льв'), isTrue);
    });

    test('three Latin letters', () {
      expect(settlementQueryIsSearchable('lviv'), isTrue);
    });

    test('digits count — an alphanumeric RUN is not letters-only', () {
      expect(settlementQueryIsSearchable('123'), isTrue);
    });

    test('a long term with a qualifying run anywhere in it', () {
      expect(settlementQueryIsSearchable('•• льв ••'), isTrue);
    });

    test('an apostrophe splits a run, so each side must carry its own', () {
      // «Кам’янка» — the run before the apostrophe is already three.
      expect(settlementQueryIsSearchable('кам’янка'), isTrue);
    });
  });

  group('a term the index CANNOT serve', () {
    test('one and two characters', () {
      expect(settlementQueryIsSearchable('л'), isFalse);
      expect(settlementQueryIsSearchable('ль'), isFalse);
    });

    test(
      'whitespace is trimmed BEFORE measuring — «  ль  » is two, not six',
      () {
        expect(settlementQueryIsSearchable('  ль  '), isFalse);
      },
    );

    test('a 50-character bullet string satisfies a LENGTH floor and is still '
        'unservable', () {
      // The server measured this shape at 119 ms with
      // `Rows Removed by Filter: 25697` — pg_trgm tokenises on alphanumeric
      // runs, so `show_trgm('•••') = {}` and both index tiers degrade into the
      // sequential scan the floor exists to prevent.
      expect(settlementQueryIsSearchable('•' * 50), isFalse);
    });

    test(
      '«ка » repeated defeats a whole-term trigram check but not the RUN',
      () {
        // Three distinct keys, 10 070 rechecks, 47 ms on the server.
        expect(settlementQueryIsSearchable('ка ' * 17), isFalse);
      },
    );

    test('«•к» repeated defeats a 3-character TOKEN floor but not the RUN', () {
      // Two distinct keys, 3 022 rechecks, 22 ms on the server. Repeating a
      // sub-trigram fragment adds NO distinct key, which is why the RUN is the
      // only form padding cannot defeat.
      expect(settlementQueryIsSearchable('•к' * 25), isFalse);
    });

    test('two letters either side of a separator is not a run of three', () {
      expect(settlementQueryIsSearchable('ль-ві'), isFalse);
    });
  });

  test('a BLANK term is searchable — it is the pre-typing major list, not an '
      'error', () {
    // The caller sends no `query` parameter at all for this case, and the
    // server answers with the ~50 `is_major` settlements (phase-346 D6).
    // Treating it as below-minimum would render the "type three characters"
    // hint on a sheet that has just opened and never been typed into.
    expect(settlementQueryIsSearchable(''), isTrue);
    expect(settlementQueryIsSearchable('   '), isTrue);
  });

  test('the maximum mirrors the server @Size(max = 50)', () {
    // A longer term is a hard 400, not a wider search — which an autocomplete
    // would otherwise re-issue on every subsequent keystroke.
    expect(kSettlementQueryMaxLength, 50);
  });
}
