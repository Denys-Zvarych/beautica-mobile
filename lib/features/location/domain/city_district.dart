// Phase 2.18 — CityDistrict domain model.
//
// Thin freezed wrapper around the backend `CityDistrictResponse` shape.
// Hand-written for now; Phase 3.2 will swap in a generated DTO.
//
// Backend `CityDistrictResponse` (camelCase JSON):
//   { id (UUID), cityId (UUID), katotthCode, nameUk, nameEn }
//
// IDs are UUIDs → modeled as [String].
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'city_district.freezed.dart';

/// An urban district within a city — the third (optional) level of the
/// locality cascade. Only present for cities where `City.hasDistricts == true`.
@freezed
abstract class CityDistrict with _$CityDistrict {
  const factory CityDistrict({
    /// Backend-assigned UUID (string form).
    required String id,

    /// UUID of the parent city this district belongs to.
    required String cityId,

    /// Localized display name (Ukrainian — `nameUk` from the backend).
    required String name,

    /// KATOTTH administrative code. Stored for downstream submission.
    required String katotthCode,
  }) = _CityDistrict;

  /// Maps a raw backend `CityDistrictResponse` map to the domain model.
  ///
  /// Named `fromResponse` (not `fromJson`) so freezed does not wire
  /// json_serializable glue — `name` is sourced from `nameUk`.
  static CityDistrict fromResponse(Map<String, dynamic> json) => CityDistrict(
    id: json['id'] as String,
    cityId: json['cityId'] as String,
    name: json['nameUk'] as String,
    katotthCode: json['katotthCode'] as String,
  );
}
