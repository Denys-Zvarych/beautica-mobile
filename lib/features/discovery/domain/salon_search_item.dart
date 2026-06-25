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

    /// Street name of the salon's address, or null. AUTH-GATED server-side: the
    /// backend omits it for anonymous callers and populates it for authenticated
    /// ones. Rendered (with [buildingNo]) as a full-address line when present,
    /// falling back to the city/district locality when null.
    required String? street,

    /// Building number of the salon's address, or null. Same auth-gating as
    /// [street]; only meaningful alongside it.
    required String? buildingNo,

    /// The [street] + [buildingNo] pre-joined into one «street, buildingNo»
    /// address line, or `null` when [street] is absent/blank (the card then
    /// falls back to the city/district locality at render). Computed ONCE by
    /// [SalonSearchMapper.fromDto] at map time — mirrors [servicesLine] so the
    /// scrolling result list never re-runs the street join per card `build()`.
    /// Only the street portion is precomputed; the locality fallback stays in
    /// the card. Kept in lockstep with [street]/[buildingNo].
    @Default(null) String? addressLine,

    /// A short (≤3) list of the salon's distinct active service names (e.g.
    /// `['Манікюр', 'Педикюр']`), surfaced as a preview line on the result card.
    /// Always non-null — an empty list (`const []`) means the salon has no
    /// active priced services and the card renders no service line.
    @Default(<String>[]) List<String> serviceNames,

    /// The [serviceNames] pre-joined into the single `' · '`-separated preview
    /// line the card renders, or `null` when [serviceNames] is empty (the card
    /// then omits the line — no placeholder). Computed ONCE by
    /// [SalonSearchMapper.fromDto] at map time so the scrolling result list never
    /// re-runs `join()` per card `build()`. Kept in lockstep with [serviceNames];
    /// mutating one without the other is a contract break.
    @Default(null) String? servicesLine,
  }) = _SalonSearchItem;
}
