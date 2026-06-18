// Phase 13.2 — MasterSearchItem domain model.
//
// Immutable value object representing a single INDEPENDENT_MASTER returned by
// the discovery search (`GET /api/v1/search/masters`). Mapped from the
// generated `MasterSearchResult` DTO by [MasterSearchMapper.fromDto] — the DTO
// type never escapes the data layer.
//
// Scope note: `/search/masters` is INDEPENDENT_MASTER-only (enforced
// backend-side in backend Phase 19.7). This model carries no role field and the
// repository does NO client-side role filtering.
//
// Pure Dart: no Flutter imports in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'master_search_item.freezed.dart';

/// A single master result in the discovery search list.
///
/// All optional metadata fields ([avgRating], [reviewCount], [cityLabel],
/// [districtLabel], [minEffectivePrice]) are nullable — the backend omits them
/// when absent (e.g. a master with no reviews has a null [avgRating], a master
/// with no published services has a null [minEffectivePrice]). Rendering of the
/// "від {price}" prefix and the rating/location lines is 13.3's job; this model
/// only carries the raw values.
@freezed
abstract class MasterSearchItem with _$MasterSearchItem {
  const factory MasterSearchItem({
    /// Backend-assigned UUID of the master (the Master-row id, used by 13.5 to
    /// open the public profile). Always present — the mapper rejects a result
    /// with a null/empty id (broken backend contract).
    required String masterId,

    /// Master's first name. Defaults to an empty string when the backend omits
    /// it rather than carrying a null — keeps name-rendering branch-free.
    required String firstName,

    /// Master's last name. Defaults to an empty string when the backend omits
    /// it.
    required String lastName,

    /// Avatar image URL, or null when the master has no avatar.
    required String? avatarUrl,

    /// Average review rating (e.g. `4.8`), or null when the master has no
    /// reviews yet.
    required double? avgRating,

    /// Number of reviews backing [avgRating], or null when unavailable.
    required int? reviewCount,

    /// Localised city label (e.g. "Київ"), or null when unavailable.
    required String? cityLabel,

    /// Localised district label (e.g. "Печерський район"), or null when the
    /// master's city has no district granularity / it is unavailable.
    required String? districtLabel,

    /// The minimum effective price across the master's published services,
    /// rendered as "від {price}" by 13.3. Null when the master has no priced
    /// services to anchor a "from" value.
    required double? minEffectivePrice,
  }) = _MasterSearchItem;
}
