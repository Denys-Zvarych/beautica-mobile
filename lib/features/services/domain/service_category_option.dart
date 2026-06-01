// Service-category request feature — domain model for an approved category.
//
// One entry in the dynamic category picker, sourced from
// `GET /api/v1/service-categories/approved`. The picker renders [displayName]
// (Ukrainian) as the chip label while sending [name] (the uppercase wire slug,
// e.g. "MANICURE") to the backend as the selected service category.
//
// Pure Dart, no Flutter imports.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'service_category_option.freezed.dart';

/// A single approved service category available for selection in the
/// service create/edit form.
///
/// - [name]: the uppercase wire slug stored on the service (e.g. `MANICURE`,
///   `NAIL_ART`). This is the value sent to the backend.
/// - [displayName]: the human-readable Ukrainian label shown in the picker
///   (e.g. `Манікюр`).
@freezed
abstract class ServiceCategoryOption with _$ServiceCategoryOption {
  const factory ServiceCategoryOption({
    /// Uppercase wire slug — the value persisted on the service.
    required String name,

    /// Ukrainian display label rendered on the picker chip.
    required String displayName,
  }) = _ServiceCategoryOption;
}
