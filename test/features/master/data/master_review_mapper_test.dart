// Phase 4.5 — Unit tests for [MasterReviewMapper] (pure Dart, no widget tree).
//
// Two translation contracts are pinned here:
//   • summaryFromDto: the `{rating, count}` bucket list is folded into a fixed
//     highest-first `List<int>` of length 5 (index 0 = 5★ … index 4 = 1★),
//     regardless of wire order, with any missing / out-of-range bucket → 0.
//   • reviewsFromDtoList: entries with a null OR empty `id` are DROPPED (a single
//     broken review must never blank the whole "Мої відгуки" list), field
//     nulls fall back to safe defaults, and surviving order is preserved.
//
// Generated built_value DTOs are constructed via their builders so the test
// exercises the SAME types the real decode path produces.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/features/master/data/master_review_mapper.dart';
import 'package:beautica_mobile/features/master/domain/master_review.dart';
import 'package:built_collection/built_collection.dart';
import 'package:flutter_test/flutter_test.dart';

RatingBucket _bucket(int? rating, int? count) => RatingBucket(
  (b) => b
    ..rating = rating
    ..count = count,
);

MasterReviewSummaryResponse _summary({
  num? avgRating,
  int? reviewCount,
  List<RatingBucket>? buckets,
}) => MasterReviewSummaryResponse((b) {
  b
    ..avgRating = avgRating
    ..reviewCount = reviewCount;
  if (buckets != null) {
    b.ratingDistribution = ListBuilder<RatingBucket>(buckets);
  }
});

ReviewResponse _review({
  String? id,
  String? clientDisplayName,
  int? rating,
  String? comment,
  DateTime? createdAt,
}) => ReviewResponse(
  (b) => b
    ..id = id
    ..clientDisplayName = clientDisplayName
    ..rating = rating
    ..comment = comment
    ..createdAt = createdAt,
);

void main() {
  group('MasterReviewMapper.summaryFromDto', () {
    test('folds buckets to fixed [5★…1★] order regardless of wire order', () {
      // Deliberately scrambled wire order.
      final dto = _summary(
        avgRating: 4.2,
        reviewCount: 15,
        buckets: <RatingBucket>[
          _bucket(1, 1),
          _bucket(4, 4),
          _bucket(2, 2),
          _bucket(5, 5),
          _bucket(3, 3),
        ],
      );

      final MasterReviewSummary result = MasterReviewMapper.summaryFromDto(dto);

      // index 0 = 5★ … index 4 = 1★, independent of the scrambled input order.
      expect(result.distribution, <int>[5, 4, 3, 2, 1]);
      expect(result.avgRating, 4.2);
      expect(result.reviewCount, 15);
    });

    test('defaults missing buckets to 0 and always yields length 5', () {
      // Only 5★ and 3★ present; 4★/2★/1★ must fill in as 0.
      final dto = _summary(
        avgRating: 4.8,
        reviewCount: 12,
        buckets: <RatingBucket>[_bucket(5, 10), _bucket(3, 2)],
      );

      final MasterReviewSummary result = MasterReviewMapper.summaryFromDto(dto);

      expect(result.distribution, hasLength(5));
      expect(result.distribution, <int>[10, 0, 2, 0, 0]);
    });

    test('ignores out-of-range and null rating buckets (defensive)', () {
      final dto = _summary(
        avgRating: 5,
        reviewCount: 3,
        buckets: <RatingBucket>[
          _bucket(0, 99), // below range — ignored
          _bucket(6, 99), // above range — ignored
          _bucket(null, 99), // null rating — ignored
          _bucket(5, 3), // valid
        ],
      );

      final MasterReviewSummary result = MasterReviewMapper.summaryFromDto(dto);

      expect(result.distribution, <int>[3, 0, 0, 0, 0]);
    });

    test('null ratingDistribution yields all-zero distribution', () {
      final dto = _summary(avgRating: null, reviewCount: null);

      final MasterReviewSummary result = MasterReviewMapper.summaryFromDto(dto);

      expect(result.distribution, <int>[0, 0, 0, 0, 0]);
      // null avgRating stays null (renders «—»); null reviewCount → 0.
      expect(result.avgRating, isNull);
      expect(result.reviewCount, 0);
    });

    test('null bucket count defaults to 0', () {
      final dto = _summary(
        avgRating: 4,
        reviewCount: 1,
        buckets: <RatingBucket>[_bucket(4, null)],
      );

      final MasterReviewSummary result = MasterReviewMapper.summaryFromDto(dto);

      expect(result.distribution, <int>[0, 0, 0, 0, 0]);
    });
  });

  group('MasterReviewMapper.reviewsFromDtoList', () {
    test('maps a well-formed review to the domain item', () {
      final DateTime created = DateTime.utc(2026, 6, 10, 10);
      final List<MasterReviewItem> out =
          MasterReviewMapper.reviewsFromDtoList(<ReviewResponse>[
            _review(
              id: 'r-1',
              clientDisplayName: 'Олена К.',
              rating: 5,
              comment: 'Чудовий сервіс!',
              createdAt: created,
            ),
          ]);

      expect(out, hasLength(1));
      expect(out.single.id, 'r-1');
      expect(out.single.clientDisplayName, 'Олена К.');
      expect(out.single.rating, 5);
      expect(out.single.comment, 'Чудовий сервіс!');
      expect(out.single.createdAt, created);
    });

    test('drops entries with a null id', () {
      final List<MasterReviewItem> out =
          MasterReviewMapper.reviewsFromDtoList(<ReviewResponse>[
            _review(
              id: null,
              rating: 5,
              comment: 'nope',
              createdAt: DateTime.utc(2026),
            ),
            _review(
              id: 'r-keep',
              rating: 4,
              comment: 'yes',
              createdAt: DateTime.utc(2026),
            ),
          ]);

      expect(out, hasLength(1));
      expect(out.single.id, 'r-keep');
    });

    test('drops entries with an empty id', () {
      final List<MasterReviewItem> out =
          MasterReviewMapper.reviewsFromDtoList(<ReviewResponse>[
            _review(
              id: '',
              rating: 5,
              comment: 'nope',
              createdAt: DateTime.utc(2026),
            ),
            _review(
              id: 'r-keep',
              rating: 4,
              comment: 'yes',
              createdAt: DateTime.utc(2026),
            ),
          ]);

      expect(out, hasLength(1));
      expect(out.single.id, 'r-keep');
    });

    test(
      'defaults null fields to safe values (empty name/comment, rating 0)',
      () {
        final List<MasterReviewItem> out =
            MasterReviewMapper.reviewsFromDtoList(<ReviewResponse>[
              _review(id: 'r-1'),
            ]);

        final MasterReviewItem item = out.single;
        expect(item.clientDisplayName, '');
        expect(item.rating, 0);
        expect(item.comment, '');
        // A null createdAt falls back to a non-null timestamp (mapper uses now()).
        expect(item.createdAt, isNotNull);
      },
    );

    test('preserves the wire order of surviving entries', () {
      final List<MasterReviewItem> out = MasterReviewMapper.reviewsFromDtoList(
        <ReviewResponse>[
          _review(id: 'a', createdAt: DateTime.utc(2026, 1, 1)),
          _review(id: '', createdAt: DateTime.utc(2026, 1, 2)), // dropped
          _review(id: 'b', createdAt: DateTime.utc(2026, 1, 3)),
          _review(id: 'c', createdAt: DateTime.utc(2026, 1, 4)),
        ],
      );

      expect(out.map((MasterReviewItem e) => e.id), <String>['a', 'b', 'c']);
    });

    test('empty input yields empty output', () {
      expect(
        MasterReviewMapper.reviewsFromDtoList(const <ReviewResponse>[]),
        isEmpty,
      );
    });
  });
}
