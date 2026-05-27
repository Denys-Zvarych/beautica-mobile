// Phase 2.18 — City domain model.
//
// Thin freezed wrapper around the backend `CityResponse` shape. Hand-written
// for now; Phase 3.2 will replace the raw-Map mapping with a generated DTO.
//
// Backend `CityResponse` (camelCase JSON):
//   { id (UUID), oblastId (UUID), katotthCode, nameUk, nameEn, hasDistricts }
//
// IDs are UUIDs → modeled as [String]. [hasDistricts] drives the District
// row's disabled-with-helper state in [LocalityCascade]: when false the app
// never issues a districts request and renders the helper line instead.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'city.freezed.dart';

/// A city within an oblast — the second level of the locality cascade.
@freezed
abstract class City with _$City {
  const factory City({
    /// Backend-assigned UUID (string form). Used as the parent key when
    /// fetching districts via `GET /locations/cities/{id}/districts`.
    required String id,

    /// UUID of the parent oblast this city belongs to.
    required String oblastId,

    /// Localized display name (Ukrainian — `nameUk` from the backend).
    required String name,

    /// KATOTTH administrative code. Stored for downstream submission.
    required String katotthCode,

    /// Whether this city subdivides into urban districts.
    ///
    /// When false, the District row is rendered disabled with the
    /// "не обов'язково" helper line and no districts request is made.
    required bool hasDistricts,
  }) = _City;

  /// Maps a raw backend `CityResponse` map to the domain model.
  ///
  /// Named `fromResponse` (not `fromJson`) so freezed does not wire
  /// json_serializable glue — `name` is sourced from `nameUk`.
  static City fromResponse(Map<String, dynamic> json) => City(
    id: json['id'] as String,
    oblastId: json['oblastId'] as String,
    name: json['nameUk'] as String,
    katotthCode: json['katotthCode'] as String,
    hasDistricts: json['hasDistricts'] as bool,
  );
}
