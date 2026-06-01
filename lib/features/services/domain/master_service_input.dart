// Phase 5.1 — Service input models (create + update).
// Phase 5.6 — Flexible pricing: replaced single `price` field with a four-field
//             pricing block. Both create and update carry [priceType] plus the
//             mode-conditional price fields. The mapper sends only the fields
//             appropriate for the selected mode.
//
// Two separate `@freezed` classes covering the two mutation directions:
//   - [MasterServiceCreate] — POST body for creating a new service. Required
//     fields mirror [CreateServiceDefinitionRequest] required fields.
//   - [MasterServiceUpdate] — PATCH body for updating an existing service.
//     All fields are optional (PATCH semantics). The mapper only includes
//     non-null fields in the wire body.
//
// Pure Dart: no Flutter imports.

import 'package:freezed_annotation/freezed_annotation.dart';

import 'master_service.dart';

part 'master_service_input.freezed.dart';

/// Input model for creating a new service under the authenticated master.
///
/// Maps to `POST /api/v1/independent-masters/me/services` via
/// [MasterServiceMapper.toCreateRequest].
@freezed
abstract class MasterServiceCreate with _$MasterServiceCreate {
  const factory MasterServiceCreate({
    /// Display name of the service. Required.
    required String name,

    /// Duration of the service in minutes. Required.
    required int durationMinutes,

    /// Pricing mode — FIXED or RANGE. Required.
    required ServicePriceType priceType,

    /// FIXED-mode amount. Required when [priceType] == FIXED; must be null for RANGE.
    ///
    /// The mapper sends this as the `price` field on the wire request.
    double? price,

    /// RANGE floor. Required when [priceType] == RANGE; null for FIXED.
    double? priceMin,

    /// RANGE ceiling. Required when [priceType] == RANGE; null for FIXED.
    /// Must be strictly greater than [priceMin].
    double? priceMax,

    /// Optional description shown to clients.
    String? description,

    /// Optional service category string (e.g. "MANICURE", "HAIRCUT").
    String? category,

    /// Optional buffer in minutes after the appointment.
    int? bufferMinutesAfter,
  }) = _MasterServiceCreate;
}

/// Input model for updating an existing service (PATCH semantics).
///
/// All fields are optional. Only non-null fields are sent in the PATCH body
/// by [MasterServiceMapper.toUpdateRequest]. Maps to
/// `PATCH /api/v1/services/{serviceDefId}`.
///
/// Pricing PATCH rule (mirrors the backend): if ALL four price fields
/// ([priceType], [price], [priceMin], [priceMax]) are null, the price block
/// is treated as absent and the existing pricing is preserved. If ANY price
/// field is non-null, [priceType] must be present and the full mode payload
/// must satisfy the FIXED or RANGE invariants.
@freezed
abstract class MasterServiceUpdate with _$MasterServiceUpdate {
  const factory MasterServiceUpdate({
    /// New display name. `null` means "do not change".
    String? name,

    /// New description. `null` means "do not change".
    String? description,

    /// New category string. `null` means "do not change".
    String? category,

    /// New duration in minutes. `null` means "do not change".
    int? durationMinutes,

    /// New pricing mode. Required when any price field is present.
    ServicePriceType? priceType,

    /// FIXED-mode new amount. Required when [priceType] == FIXED.
    double? price,

    /// RANGE new floor. Required when [priceType] == RANGE.
    double? priceMin,

    /// RANGE new ceiling. Required when [priceType] == RANGE.
    double? priceMax,

    /// New buffer in minutes after appointment. `null` means "do not change".
    int? bufferMinutesAfter,

    /// Whether the service is active. `null` means "do not change".
    bool? isActive,
  }) = _MasterServiceUpdate;
}
