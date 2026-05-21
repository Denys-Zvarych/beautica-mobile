// Phase 2.18 — Oblast domain model.
//
// Thin freezed wrapper around the backend `OblastResponse` shape so the UI
// layer never imports raw API DTOs. Built by hand for now; Phase 3.2 will
// regenerate a type-safe LocationApi and the repository will map from the
// generated DTO instead of a raw Map.
//
// Backend `OblastResponse` (camelCase JSON):
//   { id (UUID), katotthCode, nameUk, nameEn }
//
// IDs are UUIDs on the backend → modeled as [String] in Dart (NOT int).
// [name] surfaces `nameUk` because the v1 API serves Ukrainian only.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'oblast.freezed.dart';

/// A Ukrainian oblast (region) — the first level of the locality cascade.
@freezed
abstract class Oblast with _$Oblast {
  const factory Oblast({
    /// Backend-assigned UUID (string form). Used as the parent key when
    /// fetching the oblast's cities via `GET /locations/oblasts/{id}/cities`.
    required String id,

    /// Localized display name (Ukrainian — `nameUk` from the backend).
    required String name,

    /// KATOTTH administrative code (e.g. `UA46000000000026132`). Stored for
    /// downstream submission; not shown in the picker list.
    required String katotthCode,
  }) = _Oblast;

  /// Maps a raw backend `OblastResponse` map to the domain model.
  ///
  /// Hand-written for now (no generated DTO yet); the field reads mirror the
  /// live backend contract exactly. Named `fromResponse` (not `fromJson`) so
  /// freezed does not try to wire json_serializable glue — `name` is sourced
  /// from `nameUk`, which a generated `fromJson` could not express.
  static Oblast fromResponse(Map<String, dynamic> json) => Oblast(
    id: json['id'] as String,
    name: json['nameUk'] as String,
    katotthCode: json['katotthCode'] as String,
  );
}
