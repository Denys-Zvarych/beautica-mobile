// Phase 13.2 — SalonSearchItem domain model.
//
// Immutable value object representing a single salon returned by the discovery
// search (`GET /api/v1/search/salons`). Mapped from the generated
// `SalonSearchResult` DTO by [SalonSearchMapper.fromDto] — the DTO type never
// escapes the data layer.
//
// avgRating note: the regenerated `SalonSearchResult` DTO exposes ONLY
// salonId / name / cityLabel / districtLabel / avatarUrl / priceMin / priceMax
// — it does NOT carry an avgRating field. [avgRating] is kept here (nullable)
// for forward-compatibility and parity with [MasterSearchItem], but the mapper
// always maps it as `null` (the backend does not send it). Do NOT invent a
// value for it.
//
// Pure Dart: no Flutter imports in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'salon_search_item.freezed.dart';

/// A single salon result in the discovery search list.
///
/// [priceMin]/[priceMax] are both nullable: when equal the caller renders one
/// value; when both null no price is shown. (Rendering is 13.3's job — this
/// model only carries them.)
@freezed
abstract class SalonSearchItem with _$SalonSearchItem {
  const factory SalonSearchItem({
    /// Backend-assigned UUID of the salon (used by 13.6 to open the public
    /// salon profile). Always present — the mapper rejects a result with a
    /// null/empty id (broken backend contract).
    required String salonId,

    /// Salon display name. Defaults to an empty string when the backend omits
    /// it.
    required String name,

    /// Avatar / logo image URL, or null when the salon has no avatar.
    required String? avatarUrl,

    /// Average review rating, or null. The current `SalonSearchResult` DTO does
    /// NOT expose this field, so the mapper always sets it to null. Retained for
    /// forward-compatibility; do not assume the backend populates it.
    required double? avgRating,

    /// Localised city label (e.g. "Київ"), or null when unavailable.
    required String? cityLabel,

    /// Localised district label, or null when unavailable.
    required String? districtLabel,

    /// Lower bound of the salon's service price range, or null when the salon
    /// has no priced services. Equal to [priceMax] ⇒ a single price; both null
    /// ⇒ no price shown.
    required double? priceMin,

    /// Upper bound of the salon's service price range, or null when the salon
    /// has no priced services / no range ceiling.
    required double? priceMax,
  }) = _SalonSearchItem;
}
