// Phase 13.6 — Salon domain model (public, client-facing).
//
// Immutable value object representing a salon as returned by the PUBLIC
// `GET /salons/{salonId}` endpoint. Uses `freezed` for value equality,
// copyWith, and pattern matching.
//
// [avgRating] is `null` when [reviewCount] is 0 (no reviews yet) — render a
// muted "—" placeholder rather than "0.0" (mirrors the [Master] domain
// convention).
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'salon.freezed.dart';

/// A Beautica salon — the canonical domain entity returned by the public
/// salon-read path (`GET /salons/{salonId}`).
@freezed
abstract class Salon with _$Salon {
  const factory Salon({
    required String id,
    required String name,
    String? description,
    String? city,
    String? region,
    String? address,
    String? instagramUrl,
    String? avatarUrl,

    /// Owner-uploadable cover photo. Null renders the gradient placeholder.
    String? coverImageUrl,

    /// Null when [reviewCount] is 0 — no reviews yet.
    double? avgRating,
    @Default(0) int reviewCount,
  }) = _Salon;
}
