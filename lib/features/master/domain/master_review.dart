// Phase 4.5 — Independent-master received-reviews domain models.
//
// Backing the master's own "Мої відгуки" screen: an aggregate
// [MasterReviewSummary] (rating + distribution) and the individual
// [MasterReviewItem]s, both loaded from the master reviews endpoints
// (`GET /masters/{masterId}/reviews/summary` + `.../reviews?sort=`). The masked,
// read-only view of the two-sided rating model — the master sees the reviews
// clients left about them; there is no "leave review" affordance here.
//
// Mirrors `features/salon/domain/salon_review.dart` (the shipped salon
// equivalent) but drops the salon/master/service context fields the backend
// master item does not carry (a master's reviews are always about "me").
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'master_review.freezed.dart';

/// How the master's reviews list is ordered. Maps 1:1 to the
/// `GET /masters/{masterId}/reviews?sort=` query param wire values (the same
/// four values the salon route accepts — deliberately a separate enum so the
/// two features stay decoupled, per the phase brief).
enum MasterReviewSort {
  newest('NEWEST'),
  oldest('OLDEST'),
  highest('HIGHEST'),
  lowest('LOWEST');

  const MasterReviewSort(this.wireValue);

  /// The backend's wire value for this ordering.
  final String wireValue;
}

/// The master's aggregate rating — headline score + a 5★→1★ distribution.
@freezed
abstract class MasterReviewSummary with _$MasterReviewSummary {
  const factory MasterReviewSummary({
    /// Null when [reviewCount] is 0 — no reviews yet.
    double? avgRating,
    @Default(0) int reviewCount,

    /// Star-bucket counts, highest first: index 0 = 5★ … index 4 = 1★.
    /// Always length 5 (zero-filled for buckets with no reviews).
    @Default(<int>[0, 0, 0, 0, 0]) List<int> distribution,
  }) = _MasterReviewSummary;
}

/// One client review of the master (masked reviewer name, read-only). The
/// backend master item carries no `masterName`/`serviceName` — the reviews are
/// implicitly about the authenticated master.
@freezed
abstract class MasterReviewItem with _$MasterReviewItem {
  const factory MasterReviewItem({
    required String id,

    /// Already masked by the backend (e.g. "Олена К.") — render as-is.
    required String clientDisplayName,
    required int rating,
    required String comment,
    required DateTime createdAt,
  }) = _MasterReviewItem;
}
