// Phase 16.2 — Service-type data layer: domain model for a second-level
// service-type picker option.
//
// One selectable service type within a chosen platform category, sourced from
// `GET /api/v1/service-catalog/service-types?categoryName=...` (the slug-contract
// `PlatformServiceTypeResponse`). The picker (Phase 16.4) renders [nameUk] as
// the option label and uses it to pre-fill the service-name field; [slug] is the
// stable wire identifier persisted on the service.
//
// Pure Dart, no Flutter imports.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'service_type_option.freezed.dart';

/// A single platform service type available for selection under a category in
/// the service create/edit form.
///
/// - [id]: the service-type UUID (primary key on the platform_service_types row).
/// - [slug]: the stable uppercase wire slug (e.g. `CLASSIC_LASHES`). Persisted
///   on the service and used for cross-system lookup.
/// - [nameUk]: the Ukrainian display label shown in the picker and used to
///   pre-fill the service-name field.
/// - [categoryName]: the parent platform-category slug this type belongs to
///   (e.g. `EYELASH`).
@freezed
abstract class ServiceTypeOption with _$ServiceTypeOption {
  const factory ServiceTypeOption({
    /// Service-type UUID (primary key).
    required String id,

    /// Stable uppercase wire slug persisted on the service.
    required String slug,

    /// Ukrainian display label — picker label and name pre-fill source.
    required String nameUk,

    /// Parent platform-category slug this type belongs to.
    required String categoryName,
  }) = _ServiceTypeOption;
}
