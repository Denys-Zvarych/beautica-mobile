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

/// The interpunct used to join the master's top service names into the card's
/// single preview line (e.g. «Манікюр · Педикюр»).
///
/// Lives in the (pure-Dart) domain layer because the join is computed at map
/// time in [MasterSearchMapper.fromDto] — the `data/` layer must not import
/// `presentation/`. The presentation layer re-exports this from
/// `result_card_text.dart` for existing call sites.
const String kServiceNamesSeparator = ' · ';

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

    /// The maximum effective price across the master's published services, or
    /// null when the master has no priced services / no range ceiling. Together
    /// with [minEffectivePrice] this drives the «від» prefix decision on the
    /// card: show a single fixed price when `priceMax == minEffectivePrice`
    /// (or null), otherwise a «від N грн» / range label.
    required double? priceMax,

    /// Street name of the master's worksite, or null. AUTH-GATED server-side:
    /// the backend omits it for anonymous callers and populates it for
    /// authenticated ones. Rendered (with [buildingNo]) as a full-address line
    /// when present, falling back to the city/district locality when null.
    required String? street,

    /// Building number of the master's worksite, or null. Same auth-gating as
    /// [street]; only meaningful alongside it.
    required String? buildingNo,

    /// The [street] + [buildingNo] pre-joined into one «street, buildingNo»
    /// address line, or `null` when [street] is absent/blank (the card then
    /// falls back to the city/district locality at render). Computed ONCE by
    /// [MasterSearchMapper.fromDto] at map time — mirrors [servicesLine] so the
    /// scrolling result list never re-runs the street join per card `build()`.
    /// Only the street portion is precomputed; the locality fallback stays in
    /// the card. Kept in lockstep with [street]/[buildingNo].
    @Default(null) String? addressLine,

    /// A short (≤3), custom-preferred list of the master's distinct active
    /// service names (e.g. `['Манікюр', 'Педикюр']`), surfaced as a preview line
    /// on the result card. Always non-null — an empty list (`const []`) means the
    /// master has no active priced services and the card renders no service line.
    /// The custom-over-default choice is already resolved backend-side.
    @Default(<String>[]) List<String> serviceNames,

    /// The [serviceNames] pre-joined into the single `' · '`-separated preview
    /// line the card renders, or `null` when [serviceNames] is empty (the card
    /// then omits the line — no placeholder). Computed ONCE by
    /// [MasterSearchMapper.fromDto] at map time so the scrolling result list
    /// never re-runs `join()` per card `build()` (perf house-rule: no
    /// per-build allocation in a list row). Kept in lockstep with
    /// [serviceNames]; mutating one without the other is a contract break.
    @Default(null) String? servicesLine,
  }) = _MasterSearchItem;
}
