// Phase 5.1 — MasterService domain model.
//
// Immutable value object representing a beauty service offered by a master.
// Uses `freezed` for value equality, copyWith, and pattern matching.
//
// Mapping notes:
//   - [id] corresponds to the `MasterServiceResponse.id` (the master-service
//     assignment UUID, not the underlying service-definition UUID).
//   - [price] is a `double` in the domain; the backend's `MasterServiceResponse`
//     delivers it as `num` via the `effectivePrice` field. The mapper calls
//     `.toDouble()` once at the data-layer boundary so this entity never
//     contains raw `num`.
//   - [durationMinutes] maps from `effectiveDurationMinutes` (or
//     `serviceDefinition.baseDurationMinutes` as a fallback).
//
// Pure Dart: no Flutter imports in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'master_service.freezed.dart';

/// A service offered by a Beautica master.
///
/// Represents the effective (possibly overridden) price and duration for a
/// service as configured by the individual master, derived from the backend's
/// `MasterServiceResponse` envelope.
@freezed
abstract class MasterService with _$MasterService {
  const factory MasterService({
    /// Backend-assigned UUID for this master-service assignment record.
    required String id,

    /// Display name of the service.
    required String name,

    /// Optional description entered by the master or service catalog.
    String? description,

    /// Optional service category string (e.g. "MANICURE", "HAIRCUT").
    String? category,

    /// Effective duration of this service in minutes.
    required int durationMinutes,

    /// Effective price charged by this master in UAH (whole units, no kopecks).
    required double price,

    /// Optional buffer in minutes after the appointment before the next booking.
    @Default(0) int bufferMinutesAfter,

    /// Whether this service is currently active and bookable.
    @Default(true) bool isActive,
  }) = _MasterService;
}
