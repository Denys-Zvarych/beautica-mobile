// Phase 4.1 — Master domain model.
//
// Immutable value object representing a beauty master as returned by the
// `GET /masters/{masterId}` endpoint. Uses `freezed` for value equality,
// copyWith, and pattern matching.
//
// [MasterType] bridges the backend's SCREAMING_SNAKE_CASE wire values
// (from [MasterDetailResponseMasterTypeEnum]) to idiomatic Dart lowerCamelCase
// enum variants so the rest of the domain layer never depends on generated
// API types.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../calendar/domain/working_hours.dart';

part 'master.freezed.dart';

/// The role / tenure type of a master in the Beautica platform.
///
/// Mirrors [MasterDetailResponseMasterTypeEnum] from the generated API package.
/// Conversion is done once at the data-layer boundary in [MasterMapper].
enum MasterType {
  /// Master employed within a salon (invited by a [salonOwner] or admin).
  salonMaster,

  /// Solo provider with no salon affiliation.
  independentMaster,

  /// Owner of a salon who also acts as a master.
  salonOwner,
}

/// A Beautica beauty master — the canonical domain entity returned by the
/// profile-read path.
///
/// All fields are flat and nullable-where-optional; there is no nested user
/// sub-object because [MasterDetailResponse] does not carry one.
@freezed
abstract class Master with _$Master {
  const factory Master({
    /// Backend-assigned UUID for this master.
    required String id,

    /// Master's given name.
    required String firstName,

    /// Master's family name.
    required String lastName,

    /// City where the master operates (display string, not a UUID).
    String? city,

    /// UUID of the city the master is located in. Used by [LocalityCascade]
    /// to pre-populate the city picker when opening the edit screen.
    String? cityId,

    /// UUID of the oblast (region) the master is located in. Used by
    /// [LocalityCascade] to pre-populate the region picker when opening the
    /// edit screen.
    String? oblastId,

    /// UUID of the city district, or `null` when the city has no districts or
    /// the master hasn't selected one.
    String? districtId,

    /// Street name where the master works.
    String? street,

    /// Building number (e.g. "22").
    String? buildingNo,

    /// Apartment/floor/office note (e.g. "кв. 3, 2 поверх").
    String? locationNote,

    /// Short bio text entered by the master.
    String? bio,

    /// URL of the master's profile avatar.
    String? avatarUrl,

    /// Average review rating (0.0–5.0 scale).
    required double avgRating,

    /// Total number of reviews received.
    required int reviewCount,

    /// Tenure / role type for this master.
    required MasterType type,

    /// UUID of the affiliated salon; `null` for [MasterType.independentMaster].
    String? salonId,

    /// Contact phone number as entered by the master.
    String? phoneNumber,

    /// Instagram handle or URL as entered by the master.
    /// May be a bare handle (e.g. "username"), "@"-prefixed handle, or full
    /// https://instagram.com/... URL — stored verbatim from user input.
    String? instagram,

    /// The master's working week as a dense, ordered 7-entry list
    /// (Monday(1) … Sunday(7)), gap-filled by [WorkingHoursMapper.toDomainWeek]
    /// at the data-layer boundary. Carries the working hours bundled in
    /// `MasterDetailResponse.workingHours` so the calendar feature reads them
    /// from this cached profile instead of issuing a second `getMyProfile`
    /// round-trip (PERF M1). Defaults to an empty list only when constructed
    /// without a mapped profile (e.g. in tests); the mapper always materialises
    /// all 7 days.
    @Default(<WorkingHours>[]) List<WorkingHours> workingHours,
  }) = _Master;
}
