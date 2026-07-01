// Phase 13.6 — Salon master-rail summary domain model.
//
// A lightweight master summary as returned by `GET /salons/{salonId}/masters`
// — the "Майстри" tab's horizontal rail. Deliberately NOT the full [Master]
// entity (that comes from `GET /masters/{masterId}` and is loaded only once
// the user taps into a specific master's public profile, Phase 13.5).
//
// Reuses [MasterType] from the master feature's domain layer (a legitimate
// cross-feature `domain/`-to-`domain/` import per the architecture's layering
// rule) instead of duplicating the enum.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../master/domain/master.dart';

part 'salon_master_summary.freezed.dart';

/// One master in a salon's public roster.
@freezed
abstract class SalonMasterSummary with _$SalonMasterSummary {
  const factory SalonMasterSummary({
    required String masterId,
    required String firstName,
    required String lastName,
    String? avatarUrl,

    /// Null when [reviewCount] is 0 — no reviews yet.
    double? avgRating,
    @Default(0) int reviewCount,
    required MasterType type,
  }) = _SalonMasterSummary;
}
