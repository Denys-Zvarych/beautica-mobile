// Phase 13.x (Variant A redesign) — second-level service option.
//
// One bookable SERVICE inside a [ServiceCategoryOption] — the second level of
// the category → service hierarchy the «Рейка + послуги» (Variant A) search
// redesign introduces. The client picks a category in the rail, then its
// services appear as selectable chips in the drawer below.
//
// In the preview app this was `BeautyService(key, label)` mock data inside
// `catalog.dart`. There is NO backend endpoint exposing per-category services
// yet, so the live provider that feeds these is a clearly-marked placeholder
// (see `category_service_providers.dart`). When the backend ships a
// services-within-category endpoint, swap that provider's body — this model is
// the stable shape the UI keys off.
//
// Pure Dart: no Flutter imports in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'category_service_option.freezed.dart';

/// A single bookable service within a category (second-level selection).
///
/// - [key]: stable identifier the selection set keys off (NOT the label).
/// - [displayName]: human-readable Ukrainian label rendered on the chip.
@freezed
abstract class CategoryServiceOption with _$CategoryServiceOption {
  const factory CategoryServiceOption({
    /// Stable identifier — selection keys off this, never the label.
    required String key,

    /// Ukrainian display label rendered on the service chip.
    required String displayName,
  }) = _CategoryServiceOption;
}
