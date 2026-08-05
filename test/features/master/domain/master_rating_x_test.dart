// QA (Phase 240 rating-visibility) — unit suite for [MasterRatingX].
//
// WHY THIS FILE EXISTS
// --------------------
// `Master.avgRating` went `double` → `double?` in this change, and
// `master_mapper.dart:57` stopped laundering a null wire value into `0`. The
// SINGLE thing standing between that nullable field and every rating surface
// in the app is `MasterRatingX.displayRating`, which folds THREE distinct
// "this master has no rating to show" shapes onto one null:
//
//   1. `avgRating == null`      — the Phase 240 wire contract.
//   2. `avgRating <= 0`         — the pre-240 storage artefact (masters.avg_rating
//                                 is NOT NULL DEFAULT 0.00), still reachable from
//                                 a stale backend or an older cached response.
//   3. `reviewCount <= 0`       — no reviews can produce an average.
//
// Shapes 2 and 3 are the ones with teeth: the user-facing bug this whole
// change answers was ratings being invisible/wrong, and a regression that
// drops either guard prints a damning «0.0» on a brand-new master — silently,
// because it is a plausible-looking number rather than a crash.
//
// The FOURTH case is the one a "cleanup" would break: a legitimately LOW
// rating (1.0, the floor of the 1.00–5.00 scale) must survive the fold. A
// guard written as `avg < 1` or `avg <= 1` instead of `avg <= 0` looks
// equivalent on the happy path and erases every one-star master.
//
// Pure Dart — no widget tree, no ProviderScope. The RENDER half of this
// contract (that a folded null actually prints «—») is pinned separately in
// `test/features/booking/presentation/widgets/master_strip_rating_test.dart`.

import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:flutter_test/flutter_test.dart';

Master _master({required double? avgRating, required int reviewCount}) =>
    Master(
      id: 'm1',
      firstName: 'Оксана',
      lastName: 'Коваль',
      avgRating: avgRating,
      reviewCount: reviewCount,
      type: MasterType.independentMaster,
    );

void main() {
  group('MasterRatingX.displayRating — the three "unrated" shapes fold to '
      'null', () {
    test('a null avgRating (the Phase 240 wire contract) is null', () {
      expect(_master(avgRating: null, reviewCount: 0).displayRating, isNull);
    });

    test('a null avgRating with a NON-zero count is still null — the count '
        'cannot manufacture an average out of nothing', () {
      expect(_master(avgRating: null, reviewCount: 12).displayRating, isNull);
    });

    test('a stale 0.0 avgRating (the pre-240 storage artefact) is null, NOT '
        'a rating of zero', () {
      expect(_master(avgRating: 0, reviewCount: 0).displayRating, isNull);
    });

    test('a stale 0.0 avgRating is null EVEN WITH a non-zero review count — '
        'the count guard alone would have let «0.0» through', () {
      expect(_master(avgRating: 0, reviewCount: 7).displayRating, isNull);
    });

    test('a known-zero reviewCount is null even when avgRating carries a '
        'number — no reviews, no average', () {
      expect(_master(avgRating: 4.8, reviewCount: 0).displayRating, isNull);
    });

    test('a negative avgRating is null — defensive, a rating is never < 0', () {
      expect(_master(avgRating: -1, reviewCount: 3).displayRating, isNull);
    });
  });

  group('MasterRatingX.displayRating — a genuine rating survives', () {
    test('the SCALE FLOOR (1.0) survives — a guard written `avg < 1` instead '
        'of `avg <= 0` would silently erase every one-star master', () {
      expect(_master(avgRating: 1, reviewCount: 1).displayRating, 1.0);
    });

    test('a fractional low rating (1.4) survives untouched', () {
      expect(_master(avgRating: 1.4, reviewCount: 5).displayRating, 1.4);
    });

    test('a high rating passes through byte-identical — the getter is a '
        'FILTER, never a transform', () {
      expect(_master(avgRating: 4.87, reviewCount: 42).displayRating, 4.87);
    });

    test('the scale ceiling (5.0) survives', () {
      expect(_master(avgRating: 5, reviewCount: 9).displayRating, 5.0);
    });
  });
}
