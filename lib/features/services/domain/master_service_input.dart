// Phase 5.1 — Service input models (create + update).
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

    /// Price charged by the master in UAH. Required.
    required double price,

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
/// by [MasterServiceMapper.toUpdateBody]. Maps to
/// `PATCH /api/v1/independent-masters/me/services/{id}`.
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

    /// New price in UAH. `null` means "do not change".
    double? price,

    /// New buffer in minutes after appointment. `null` means "do not change".
    int? bufferMinutesAfter,

    /// Whether the service is active. `null` means "do not change".
    bool? isActive,
  }) = _MasterServiceUpdate;
}
