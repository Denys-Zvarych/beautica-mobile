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

    /// Legacy free-text city name — kept for backward compat, but no longer
    /// written by the backend since Phase 10.6 (taxonomy fields took over).
    /// Null for any salon created/edited after that.
    String? city,
    String? region,

    /// Legacy free-text address — same backward-compat caveat as [city].
    String? address,

    /// UUID of the taxonomy city the salon is located in (Phase 10.6+).
    /// Raw id only — Beautica's `/locations/*` city lookup is oblast-scoped
    /// and [Salon] carries no `oblastId`, so this cannot be resolved to a
    /// display name client-side; it is not rendered directly.
    String? cityId,

    /// UUID of the taxonomy city district, or `null` when the city has no
    /// districts or none was selected. Same resolution caveat as [cityId].
    String? districtId,

    /// Street name where the salon operates (Phase 10.6+ taxonomy field).
    String? street,

    /// Building number (e.g. "22").
    String? buildingNo,

    /// Apartment/floor/office note (e.g. "2 поверх, офіс 5").
    String? locationNote,
    String? instagramUrl,
    String? avatarUrl,

    /// Owner-uploadable cover photo. Null renders the gradient placeholder.
    String? coverImageUrl,

    /// Null when [reviewCount] is 0 — no reviews yet.
    double? avgRating,
    @Default(0) int reviewCount,
  }) = _Salon;
}
