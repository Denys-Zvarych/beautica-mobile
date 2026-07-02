// Phase 13.6 — Salon public service-catalogue domain models.
//
// Backing the "Послуги" tab's read-only category accordion. Loaded from
// `GET /salons/{salonId}/services`, which is already grouped + ordered
// server-side (approved platform-category order, then name) — the domain
// layer just carries that shape through; no client-side re-grouping.
//
// [SalonCatalogService.priceDisplay] and [SalonCatalogService.durationLabel]
// are ALWAYS rendered as-is (server-formatted / formatted once at map time via
// [DurationMinutes]) — never recomputed client-side.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'salon_service_catalog.freezed.dart';

/// One service in a salon's public catalogue.
@freezed
abstract class SalonCatalogService with _$SalonCatalogService {
  const factory SalonCatalogService({
    required String id,
    required String name,

    /// Pre-formatted short duration label, e.g. "1 год 30 хв" — computed once
    /// at map time via `DurationMinutes.format`.
    required String durationLabel,

    /// Server-formatted display price — single ("500 грн") or an en-dash range
    /// ("200–600 грн"). Always render as-is.
    required String priceDisplay,
    String? photoUrl,
    String? category,
  }) = _SalonCatalogService;
}

/// A titled group of services under one category (e.g. «Манікюр»).
@freezed
abstract class SalonServiceCategoryEntry with _$SalonServiceCategoryEntry {
  const factory SalonServiceCategoryEntry({
    required String category,

    /// Human-readable category title for display (e.g. «Апаратна
    /// косметологія» for the `HARDWARE_COSMETOLOGY` slug). The backend always
    /// sends a non-blank value (falling back to the raw slug server-side when
    /// no display name is configured) — the mapper defensively falls back to
    /// [category] only if the generated field is somehow null.
    required String displayName,
    required int count,
    required List<SalonCatalogService> services,
  }) = _SalonServiceCategoryEntry;
}
