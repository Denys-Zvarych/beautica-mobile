// Track 7.x Wave B — the CLIENT's own aggregate two-sided rating.
//
// Backing «Мій рейтинг» (`MyRatingScreen`): the client's own AGGREGATE score,
// assigned by masters/salons after COMPLETED bookings via `POST
// /client-reviews`. Mirrors `MasterReviewSummary` in shape but carries no
// distribution — the client-rating endpoint (`GET /users/me/rating`) exposes
// only the average + count, by design (PRODUCT RULE, locked): the client
// NEVER sees individual comments or a per-star breakdown, only the number.
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
  }) = _ClientRating;
}
