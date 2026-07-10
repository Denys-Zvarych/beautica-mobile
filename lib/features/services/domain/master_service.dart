// Phase 5.1 — MasterService domain model.
// Phase 5.6 — Flexible pricing: replaced single `price` field with a four-field
//             pricing block matching the backend's FIXED / RANGE pricing model.
//
// Immutable value object representing a beauty service offered by a master.
// Uses `freezed` for value equality, copyWith, and pattern matching.
//
// Mapping notes:
//   - [id] corresponds to the `MasterServiceResponse.id` (the master-service
//     assignment UUID, not the underlying service-definition UUID).
//   - [priceType] is either "FIXED" or "RANGE" — mirrors the backend PriceType enum.
//   - [priceMin] is the canonical floor (base_price on the backend). For FIXED
//     mode this IS the price. For RANGE mode this is the minimum.
//   - [priceMax] is only set for RANGE mode; null for FIXED.
//   - [priceDisplay] is the server-formatted display string (e.g. "500 грн" or
//     "від 500 до 800 грн"). Always render from this field — never build the
//     string client-side.
//   - [durationMinutes] maps from `effectiveDurationMinutes` (or
//     `serviceDefinition.baseDurationMinutes` as a fallback).
//
// Pure Dart: no Flutter imports in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'master_service.freezed.dart';

/// Pricing mode for a service — mirrors the backend `PriceType` enum.
enum ServicePriceType {
  /// A single fixed amount. [MasterService.priceMin] holds the price;
  /// [MasterService.priceMax] is null.
  fixed,

  /// A min–max price band. [MasterService.priceMin] is the floor;
  /// [MasterService.priceMax] is the ceiling (strictly greater than [priceMin]).
  range,
}

/// A service offered by a Beautica master.
///
/// Represents the effective (possibly overridden) price and duration for a
/// service as configured by the individual master, derived from the backend's
/// `MasterServiceResponse` envelope.
@freezed
abstract class MasterService with _$MasterService {
  const factory MasterService({
    /// Backend-assigned UUID for this master-service assignment record.
    ///
    /// This is `MasterServiceResponse.id` — the *assignment* key. Used for
    /// cache lookup and routing. NOT accepted by the
    /// `PATCH/DELETE /api/v1/services/{serviceDefId}` endpoints — use
    /// [serviceDefId] for those.
    required String id,

    /// Backend-assigned UUID for the underlying *service definition*.
    ///
    /// Maps from `MasterServiceResponse.serviceDefinition.id`. This is the id
    /// the backend's `PATCH /api/v1/services/{serviceDefId}` (update) and
    /// `DELETE /api/v1/services/{serviceDefId}` (deactivate) endpoints key on.
    /// Passing the assignment [id] to those endpoints yields a 404 / generic
    /// failure — always pass [serviceDefId].
    ///
    /// Empty only when the backend omitted `serviceDefinition.id` (broken
    /// contract); the mapper logs in that case.
    required String serviceDefId,

    /// Display name of the service.
    required String name,

    /// Optional description entered by the master or service catalog.
    String? description,

    /// Optional service category string (e.g. "MANICURE", "HAIRCUT").
    String? category,

    /// Id of the chosen platform service type, or null when none was selected
    /// (Phase 16.3). Round-trips from `serviceTypeId` on the backend response so
    /// the UI can confirm and pre-select the master's chosen type.
    String? serviceTypeId,

    /// Ukrainian display name of the chosen service type, or null when none was
    /// selected (Phase 16.3). Round-trips from `serviceTypeNameUk` on the
    /// backend response so the UI can render the selection without a second
    /// lookup.
    String? serviceTypeNameUk,

    /// Stable slug of the chosen platform service type, or null when none was
    /// selected. Round-trips from `serviceTypeSlug` on the backend response.
    /// This is the SAME slug space as the discovery search filter
    /// (`SearchFilters.serviceTypeSlugs` / `CategoryServiceOption.key`), so the
    /// booking flow can exact-match a search pre-selection against it.
    String? serviceTypeSlug,

    /// Effective duration of this service in minutes.
    required int durationMinutes,

    /// Pricing mode — FIXED (single amount) or RANGE (min–max band).
    ///
    /// Defaults to [ServicePriceType.fixed] as a safe fallback when the backend
    /// omits the field (pre-V67 data or broken contract).
    @Default(ServicePriceType.fixed) ServicePriceType priceType,

    /// Canonical price floor in UAH.
    ///
    /// For FIXED mode this IS the price. For RANGE mode this is the minimum.
    /// Maps from `priceMin` on the backend response (which equals `base_price`).
    @Default(0.0) double priceMin,

    /// RANGE mode ceiling in UAH. Null for FIXED mode.
    ///
    /// Maps from `priceMax` on the backend response. Always null when
    /// [priceType] is [ServicePriceType.fixed].
    double? priceMax,

    /// Server-formatted display string for the price.
    ///
    /// Examples: `"500 грн"` (FIXED) or `"від 500 до 800 грн"` (RANGE).
    /// ALWAYS render from this field — never build a price string client-side.
    /// Falls back to the empty string when the backend omits the field.
    @Default('') String priceDisplay,

    /// Optional buffer in minutes after the appointment before the next booking.
    @Default(0) int bufferMinutesAfter,

    /// Whether this service is currently active and bookable.
    @Default(true) bool isActive,

    /// Number of future (upcoming) bookings that reference this service.
    ///
    /// Defaults to `0` because the current backend API does not yet expose this
    /// field in [MasterServiceResponse]. When the backend adds the field, the
    /// mapper will read it and this default will only apply on cache-miss.
    /// A value > 0 blocks deactivation until those bookings are resolved.
    @Default(0) int futureBookingCount,
  }) = _MasterService;
}
