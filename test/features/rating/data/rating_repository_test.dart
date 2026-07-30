// QA (mobile-security LOW follow-up) — Unit tests for
// [HttpRatingRepository.getMyRating], specifically the private
// `_distributionFromBuckets` fold (rating_repository.dart:86-94).
//
// WHY THIS FILE EXISTS
// --------------------
// Before this file, `_distributionFromBuckets` had ZERO direct coverage —
// `test/features/rating/presentation/my_rating_screen_test.dart` only proves
// that MyRatingScreen forwards an already-built `ClientRating.distribution`
// to `RatingSummaryCard` unchanged; it never drives a `ClientRating` through
// the repository's fold from wire `RatingBucket`s, so it can't catch a
// regression in the fold itself.
//
// `_distributionFromBuckets` is reachable ONLY through the public
// `getMyRating()` entry point (it's private), so every case below drives the
// real method with a mocked [UserControllerApi] returning a raw
// `ApiResponseUserRatingResponse` — the exact generated DTO shape the real
// decode path produces (built via its builder, never hand-rolled JSON) — and
// asserts on the resulting `ClientRating.distribution`.
//
// mobile-security flagged (LOW) that a malformed `ratingDistribution` bucket
// (out-of-range `rating`, null `count`, a duplicate `rating`, or an
// unexpectedly long list) must degrade gracefully rather than throw —
// a `RangeError` from `distribution[5 - star]` on a hostile/malformed
// payload would be a client-side DoS (every rated CLIENT would see the
// error state on every app open). These are real assertions on the
// resulting list contents, not smoke checks.
//
// Also pins the WIRE CONTRACT the code comment calls out explicitly:
// placement is by each bucket's own `rating` VALUE, never by wire position —
// so a deliberately out-of-order server response must still fold to the
// correct highest-first list. This is the test that fails if someone
// "optimises" the fold back to positional indexing.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/features/rating/data/rating_repository.dart';
import 'package:beautica_mobile/features/rating/domain/client_rating.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockUserControllerApi extends Mock implements UserControllerApi {}

RatingBucket _bucket(int? rating, int? count) => RatingBucket(
  (b) => b
    ..rating = rating
    ..count = count,
);

UserRatingResponse _dto({
  num? avgRating,
  int? reviewCount,
  List<RatingBucket>? buckets,
}) => UserRatingResponse((b) {
  b
    ..avgRating = avgRating
    ..reviewCount = reviewCount;
  if (buckets != null) {
    b.ratingDistribution = ListBuilder<RatingBucket>(buckets);
  }
});

Response<ApiResponseUserRatingResponse> _okResponse(UserRatingResponse dto) =>
    Response<ApiResponseUserRatingResponse>(
      requestOptions: RequestOptions(path: '/api/v1/users/me/rating'),
      statusCode: 200,
      data: ApiResponseUserRatingResponse(
        (b) => b
          ..success = true
          ..data.replace(dto),
      ),
    );

void main() {
  late _MockUserControllerApi userApi;
  late HttpRatingRepository repository;

  setUp(() {
    userApi = _MockUserControllerApi();
    repository = HttpRatingRepository(userApi);
  });

  void stub(UserRatingResponse dto) {
    when(() => userApi.getMyRating()).thenAnswer((_) async => _okResponse(dto));
  }

  group('HttpRatingRepository.getMyRating — distribution fold, happy path', () {
    test('folds well-formed 5..1 buckets into the matching highest-first '
        'list', () async {
      stub(
        _dto(
          avgRating: 4.2,
          reviewCount: 15,
          buckets: <RatingBucket>[
            _bucket(5, 5),
            _bucket(4, 4),
            _bucket(3, 3),
            _bucket(2, 2),
            _bucket(1, 1),
          ],
        ),
      );

      final ClientRating result = await repository.getMyRating();

      expect(result.distribution, <int>[5, 4, 3, 2, 1]);
      expect(result.avgRating, 4.2);
      expect(result.reviewCount, 15);
    });
  });

  group('HttpRatingRepository.getMyRating — ordering is a WIRE CONTRACT, not '
      'positional', () {
    test('a deliberately OUT-OF-ORDER server response still folds to the '
        'correct highest-first list (placement by VALUE, never by wire '
        'position)', () async {
      // Server sends 1★, 3★, 5★ in that literal wire order — a purely
      // positional fold (distribution[i] = buckets[i].count) would
      // scramble this into [1, _, 3, _, 5] instead of [5, _, 3, _, 1].
      stub(
        _dto(
          avgRating: 3.4,
          reviewCount: 9,
          buckets: <RatingBucket>[_bucket(1, 1), _bucket(3, 3), _bucket(5, 5)],
        ),
      );

      final ClientRating result = await repository.getMyRating();

      expect(
        result.distribution,
        <int>[5, 0, 3, 0, 1],
        reason:
            'index 0 must be the 5★ bucket\'s count (5) and index 4 the '
            '1★ bucket\'s count (1) regardless of the scrambled wire '
            'order — this fails immediately if the fold is ever '
            '"optimised" back to positional indexing',
      );
    });

    test(
      'reversed wire order (1★ first, 5★ last) still resolves correctly',
      () async {
        stub(
          _dto(
            buckets: <RatingBucket>[
              _bucket(1, 7),
              _bucket(2, 6),
              _bucket(3, 5),
              _bucket(4, 4),
              _bucket(5, 3),
            ],
          ),
        );

        final ClientRating result = await repository.getMyRating();

        expect(result.distribution, <int>[3, 4, 5, 6, 7]);
      },
    );
  });

  group('HttpRatingRepository.getMyRating — hostile-input degradation '
      '(mobile-security LOW)', () {
    test(
      'rating: 0 (below range) is skipped — slot stays 0, no throw',
      () async {
        stub(_dto(buckets: <RatingBucket>[_bucket(0, 99)]));

        final ClientRating result = await repository.getMyRating();

        expect(result.distribution, <int>[0, 0, 0, 0, 0]);
      },
    );

    test(
      'rating: 6 (above range) is skipped — slot stays 0, no throw',
      () async {
        stub(_dto(buckets: <RatingBucket>[_bucket(6, 99)]));

        final ClientRating result = await repository.getMyRating();

        expect(result.distribution, <int>[0, 0, 0, 0, 0]);
      },
    );

    test('a negative rating is skipped — slot stays 0, no throw', () async {
      stub(_dto(buckets: <RatingBucket>[_bucket(-3, 99)]));

      final ClientRating result = await repository.getMyRating();

      expect(result.distribution, <int>[0, 0, 0, 0, 0]);
    });

    test('rating: null is skipped — slot stays 0, no throw', () async {
      stub(
        _dto(
          buckets: <RatingBucket>[
            _bucket(null, 99),
            _bucket(5, 2), // a valid sibling must still resolve
          ],
        ),
      );

      final ClientRating result = await repository.getMyRating();

      expect(result.distribution, <int>[2, 0, 0, 0, 0]);
    });

    test(
      'count: null defaults the slot to 0 (not null, not a throw)',
      () async {
        stub(_dto(buckets: <RatingBucket>[_bucket(4, null)]));

        final ClientRating result = await repository.getMyRating();

        expect(result.distribution, <int>[0, 0, 0, 0, 0]);
        expect(
          result.distribution[1],
          0,
          reason:
              'a null bucket.count must default to 0, never propagate null '
              'into the fixed-length int list',
        );
      },
    );

    test(
      'two buckets with the SAME rating: last-write-wins, no crash',
      () async {
        stub(
          _dto(
            buckets: <RatingBucket>[
              _bucket(5, 10),
              _bucket(5, 3), // arrives second — must win
            ],
          ),
        );

        final ClientRating result = await repository.getMyRating();

        expect(
          result.distribution,
          <int>[3, 0, 0, 0, 0],
          reason:
              'a duplicate-rating bucket must overwrite rather than throw or '
              'sum — last write in iteration order wins',
        );
      },
    );

    test('a 7-element bucket list (more buckets than star values) still yields '
        'exactly 5 slots', () async {
      stub(
        _dto(
          buckets: <RatingBucket>[
            _bucket(5, 1),
            _bucket(4, 1),
            _bucket(3, 1),
            _bucket(2, 1),
            _bucket(1, 1),
            _bucket(0, 999), // out-of-range extra — ignored
            _bucket(9, 999), // out-of-range extra — ignored
          ],
        ),
      );

      final ClientRating result = await repository.getMyRating();

      expect(result.distribution, hasLength(5));
      expect(result.distribution, <int>[1, 1, 1, 1, 1]);
    });

    test(
      'null ratingDistribution yields an all-zero, length-5 distribution',
      () async {
        stub(_dto(avgRating: null, reviewCount: null));

        final ClientRating result = await repository.getMyRating();

        expect(result.distribution, hasLength(5));
        expect(result.distribution, <int>[0, 0, 0, 0, 0]);
        expect(result.avgRating, isNull);
        expect(result.reviewCount, 0);
      },
    );

    test('an empty (present but zero-length) ratingDistribution list yields '
        'all-zeros, length 5', () async {
      stub(_dto(buckets: const <RatingBucket>[]));

      final ClientRating result = await repository.getMyRating();

      expect(result.distribution, <int>[0, 0, 0, 0, 0]);
    });
  });
}
