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

import '../../services/domain/master_service.dart' show ServicePriceType;

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

    /// Stable slug of the underlying platform service type, or null when none
    /// was selected. Maps from `ServiceDefinitionResponse.serviceTypeSlug` — the
    /// SAME slug space as the discovery search filter
    /// (`SearchFilters.serviceTypeSlugs` / `CategoryServiceOption.key`), so the
    /// salon booking flow can exact-match a search pre-selection against it.
    String? serviceTypeSlug,

    /// Typed duration in minutes — the raw value [durationLabel] is formatted
    /// from. Added (Phase 14.12) so the salon booking flow's multi-service
    /// selection can sum an accurate total duration/price instead of
    /// re-parsing the display strings (the anti-pattern Phase 14.1's
    /// `BookingSummaryBar` explicitly moved away from — see that file's
    /// header). Null only for a legacy/never-refreshed cache entry that
    /// predates this field; the read-only "Послуги" tab never needed it and
    /// still renders [durationLabel]/[priceDisplay] as-is.
    int? durationMinutes,

    /// Typed pricing mode mirroring [ServiceDefinitionResponse.priceType].
    /// See [durationMinutes] for why this was added.
    ServicePriceType? priceType,

    /// Typed price floor (FIXED price, or RANGE minimum) in UAH.
    double? priceMin,

    /// Typed RANGE ceiling in UAH; null for FIXED mode or legacy data.
    double? priceMax,
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
