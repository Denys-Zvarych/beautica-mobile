// Phase 4.5 — Master review mappers: data-layer translation from generated DTOs
// to domain models.
//
// Mirrors `SalonReviewMapper` (features/salon/data/salon_mapper.dart) minus the
// salon/master context fields the master item does not carry (`serviceName` IS
// carried — backend `92280c3` — and is mapped through below). Generated DTO
// types must not cross this boundary into the domain or presentation layers.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';

import '../domain/master_review.dart';

/// Maps [MasterReviewSummaryResponse] to the domain [MasterReviewSummary], and
/// [ReviewResponse] to [MasterReviewItem].
abstract final class MasterReviewMapper {
  /// [ratingDistribution] arrives as `{rating, count}` buckets (the backend
  /// zero-fills all five). This reduces it to a fixed highest-first `List<int>`
  /// (index 0 = 5★ … index 4 = 1★) regardless of wire order, defaulting any
  /// missing bucket to 0 — identical folding to [SalonReviewMapper].
  static MasterReviewSummary summaryFromDto(MasterReviewSummaryResponse dto) {
    final List<int> distribution = List<int>.filled(5, 0);
    for (final bucket in dto.ratingDistribution ?? const <RatingBucket>[]) {
      final int? star = bucket.rating;
      if (star == null || star < 1 || star > 5) continue;
      distribution[5 - star] = bucket.count ?? 0;
    }
    return MasterReviewSummary(
      avgRating: dto.avgRating?.toDouble(),
      reviewCount: dto.reviewCount ?? 0,
      distribution: distribution,
    );
  }

  /// Entries with a null/empty `id` are dropped (logged) rather than thrown —
  /// one broken review must not blank the whole "Мої відгуки" list.
  static List<MasterReviewItem> reviewsFromDtoList(
    Iterable<ReviewResponse> dtos,
  ) {
    final List<MasterReviewItem> out = <MasterReviewItem>[];
    for (final ReviewResponse dto in dtos) {
      final String? id = dto.id;
      if (id == null || id.isEmpty) {
        log(
          'ReviewResponse.id is null — dropping master review entry',
          name: 'feature.master.review.mapper',
          level: 900,
        );
        continue;
      }
      out.add(
        MasterReviewItem(
          id: id,
          clientDisplayName: dto.clientDisplayName ?? '',
          rating: dto.rating ?? 0,
          comment: dto.comment ?? '',
          // instant-ok: last-resort fallback for a malformed/absent DTO timestamp
          createdAt: dto.createdAt ?? DateTime.now(),
          serviceName: dto.serviceName,
        ),
      );
    }
    return out;
  }
}
