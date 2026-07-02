// Phase 13.6 — Salon public reviews domain models.
//
// Backing the "Відгуки" tab: an aggregate [SalonReviewSummary] (rating +
// distribution) and the individual [SalonReviewItem]s, both loaded from the
// salon's public reviews endpoints. The read-only, client-facing view of the
// two-sided rating model — there is deliberately no "leave review" affordance
// on this screen (a separate, post-booking flow in a future phase).
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'salon_review.freezed.dart';

/// How the salon's reviews list is ordered. Maps 1:1 to the
/// `GET /salons/{salonId}/reviews?sort=` query param wire values.
enum SalonReviewSort {
  newest('NEWEST'),
  oldest('OLDEST'),
  highest('HIGHEST'),
  lowest('LOWEST');

  const SalonReviewSort(this.wireValue);

  /// The backend's wire value for this ordering.
  final String wireValue;
}

/// The salon's aggregate rating — headline score + a 5★→1★ distribution.
@freezed
abstract class SalonReviewSummary with _$SalonReviewSummary {
  const factory SalonReviewSummary({
    /// Null when [reviewCount] is 0 — no reviews yet.
    double? avgRating,
    @Default(0) int reviewCount,

    /// Star-bucket counts, highest first: index 0 = 5★ … index 4 = 1★.
    /// Always length 5 (zero-filled server-side for buckets with no reviews).
    @Default(<int>[0, 0, 0, 0, 0]) List<int> distribution,
  }) = _SalonReviewSummary;
}

/// One client review of a salon (masked reviewer name, read-only).
@freezed
abstract class SalonReviewItem with _$SalonReviewItem {
  const factory SalonReviewItem({
    required String id,
    required String masterId,
    required String masterName,

    /// Already masked by the backend (e.g. "Олена К.") — render as-is.
    required String clientDisplayName,
    String? serviceName,
    required int rating,
    required String comment,
    required DateTime createdAt,
  }) = _SalonReviewItem;
}
