// Phase 480 — the generic KeepAliveLru<K> promoted out of
// `bookings_day_notifier.dart`. The day-side contract (DayKeepAliveLru,
// isWatched reference count, clear on logout) stays pinned by
// `bookings_day_notifier_test.dart`, unchanged.

import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/features/booking/application/bookings_day_notifier.dart';
import 'package:beautica_mobile/features/booking/application/keep_alive_lru.dart';

class _Link implements KeepAliveLink {
  bool closed = false;

  @override
  void close() => closed = true;
}

void main() {
  test('a capacity-3 LRU evicts (and closes) the least-recently-touched key '
      'on the 4th distinct key', () {
    final KeepAliveLru<String> lru = KeepAliveLru<String>(capacity: 3);
    final Map<String, _Link> links = <String, _Link>{
      for (final String k in <String>['a', 'b', 'c', 'd']) k: _Link(),
    };

    lru.touch('a', links['a']!);
    lru.touch('b', links['b']!);
    lru.touch('c', links['c']!);
    // Re-touching `a` makes `b` the least recently used.
    final _Link aAgain = _Link();
    lru.touch('a', aAgain);
    expect(links['a']!.closed, isTrue, reason: 'replaced link is closed');

    lru.touch('d', links['d']!);

    expect(lru.liveQueries, <String>['c', 'a', 'd']);
    expect(lru.contains('b'), isFalse);
    expect(links['b']!.closed, isTrue);
    expect(aAgain.closed, isFalse);
    expect(links['c']!.closed, isFalse);
    expect(links['d']!.closed, isFalse);
  });

  test('isWatched is a reference count', () {
    final KeepAliveLru<int> lru = KeepAliveLru<int>(capacity: 3);
    lru.markWatched(1);
    lru.markWatched(1);
    lru.markUnwatched(1);
    expect(lru.isWatched(1), isTrue);
    lru.markUnwatched(1);
    expect(lru.isWatched(1), isFalse);
    lru.markUnwatched(1); // unmatched — no-op, never negative
    expect(lru.isWatched(1), isFalse);
  });

  test('clear closes every link and forgets keys and watch counts', () {
    final KeepAliveLru<int> lru = KeepAliveLru<int>(capacity: 3);
    final _Link l1 = _Link();
    final _Link l2 = _Link();
    lru
      ..touch(1, l1)
      ..touch(2, l2)
      ..markWatched(1);

    lru.clear();

    expect(l1.closed && l2.closed, isTrue);
    expect(lru.liveQueries, isEmpty);
    expect(lru.isWatched(1), isFalse);
  });

  test('DayKeepAliveLru is the generic LRU at capacity 3', () {
    final DayKeepAliveLru lru = DayKeepAliveLru();
    expect(lru, isA<KeepAliveLru<Object?>>());
    expect(lru.capacity, 3);
  });

  group('forget', () {
    test('with a non-identical link is a no-op', () {
      final KeepAliveLru<String> lru = KeepAliveLru<String>(capacity: 3);
      final _Link current = _Link();
      lru.touch('a', current);

      lru.forget('a', _Link());

      expect(lru.contains('a'), isTrue);
      expect(current.closed, isFalse);
    });

    test('drops the entry without closing the link', () {
      final KeepAliveLru<String> lru = KeepAliveLru<String>(capacity: 3);
      final _Link link = _Link();
      lru.touch('a', link);

      lru.forget('a', link);

      expect(lru.contains('a'), isFalse);
      expect(link.closed, isFalse);
    });

    test('an entry forgotten on dispose is not closed by a later touch', () {
      final KeepAliveLru<String> lru = KeepAliveLru<String>(capacity: 3);
      final _Link dead = _Link();
      lru.touch('a', dead);
      lru.forget('a', dead);

      final _Link fresh = _Link();
      lru.touch('a', fresh);

      expect(dead.closed, isFalse);
      expect(fresh.closed, isFalse);
      expect(lru.liveQueries, <String>['a']);
    });

    test('after clear is a no-op and does not throw', () {
      final KeepAliveLru<String> lru = KeepAliveLru<String>(capacity: 3);
      final _Link link = _Link();
      lru.touch('a', link);
      lru.clear();

      expect(() => lru.forget('a', link), returnsNormally);

      expect(lru.contains('a'), isFalse);
      expect(lru.liveQueries, isEmpty);
    });
  });
}
