// Track 7.x Wave B — the CLIENT's own aggregate two-sided rating.
//
// Backing «Мій рейтинг» (`MyRatingScreen`): the client's own AGGREGATE score,
// assigned by masters/salons after COMPLETED bookings via `POST
// /client-reviews`. Mirrors `MasterReviewSummary` in shape (`GET
// /users/me/rating` now also zero-fills a `ratingDistribution`, same as the
// master/salon summary endpoints) so the shared `RatingSummaryCard` renders
// this screen's rating breakdown identically to the master's «Мої відгуки» —
// PRODUCT RULE (locked) still holds: the client NEVER sees individual
// comments, only the aggregate number + the per-star bucket counts.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'client_rating.freezed.dart';

/// The authenticated client's own aggregate rating.
@freezed
abstract class ClientRating with _$ClientRating {
  const factory ClientRating({
    /// Null when [reviewCount] is 0 — no reviews yet. Render the empty state,
    /// never a ★0.
    double? avgRating,
    @Default(0) int reviewCount,

    /// Star-bucket counts, highest first: index 0 = 5★ … index 4 = 1★.
    /// Always length 5 (zero-filled for buckets with no reviews). Mirrors
    /// `MasterReviewSummary.distribution` exactly so `RatingSummaryCard`
    /// takes either unchanged.
    @Default(<int>[0, 0, 0, 0, 0]) List<int> distribution,
  }) = _ClientRating;
}
