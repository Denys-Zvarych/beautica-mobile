// Phase 13.2 — Search DTO → domain mappers.
//
// Translation boundary for the discovery search feature. Converts the generated
// `MasterSearchResult` / `SalonSearchResult` DTOs into the domain
// [MasterSearchItem] / [SalonSearchItem] value objects. NO generated DTO type is
// allowed to escape past this layer — the repository returns only domain types.
//
// Null contract:
//   - A null/empty `masterId` / `salonId` is a broken backend contract: the
//     mapper throws [ServerFailure] rather than emitting a model with an empty
//     required id (mobile-backlog J-1/J-2/J-3 mapper pattern).
//   - `firstName` / `lastName` / `name` fall back to '' (keeps name rendering
//     branch-free).
//   - `avgRating` falls back to 0.0 when the DTO omits/nulls it (per phase doc).
//   - Price fields are delivered as `num?`; converted to `double?` via
//     `.toDouble()`. No divide-by-100 (the backend sends currency units, not
//     kopecks).
//   - `SalonSearchResult` exposes NO avgRating field, so the salon mapper always
//     sets [SalonSearchItem.avgRating] to null (see model doc).
//
// Pure translation classes — no network calls, no state. Call only from
// [HttpSearchRepository].

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:flutter/foundation.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/shared/formatters/address_lines.dart';
import 'package:beautica_mobile/shared/util/sanitize_display_text.dart';

import '../domain/master_search_item.dart';
import '../domain/salon_search_item.dart';

/// Pre-joins the (auth-gated) street, building number, and optional free-text
/// location note into one street detail line, or returns `null` when the street
/// is absent/blank. Pure-Dart so the data layer can compute it at map time
/// without importing `presentation/`. Only the street/building/note portion is
/// precomputed here — the city/district locality (which needs l10n formatting)
/// stays in the card's `build()`. Composition rules (parts skipped when
/// blank, no stray separators):
///   - street + buildingNo → «street, buildingNo» (street alone → just street;
///     a building number with no street → `null`, since the street anchors the
///     line);
///   - locationNote appended as a quiet « · note» suffix (never bracketed, and
///     dropped entirely when blank → no dangling separator).
///
/// SANITIZATION (Phase 253 audit fix — mobile-security MEDIUM)
/// ----------------------------------------------------------
/// All three inputs are provider-authored free text validated server-side by
/// `@Size` only — no character class — and the composed line renders through a
/// bare `Text` in `ResultAddressBlock` (`result_address_block.dart:144`) on
/// every search result card. A lone U+202E in a street name would reorder the
/// rendered address on a list every client scrolls, so each part goes through
/// `sanitizeDisplayText` before it is composed.
///
/// The street + buildingNo half is delegated to [buildStreetLine]
/// (`shared/formatters/address_lines.dart:92`), which already owns exactly this
/// composition AND sanitizes-then-tests internally — reused rather than
/// re-implemented, so the search cards and the master/salon profile screens can
/// never disagree about what «street, buildingNo» is. What this function
/// composes is unchanged; only its inputs are now clean.
///
/// The note is sanitized here because no composer downstream does — the same
/// reason `favorite_mapper.dart` owns its note (see that file's header).
String? _formatAddressLine(String? street, String? buildingNo, String? note) {
  final String? streetLine = buildStreetLine(street, buildingNo);
  if (streetLine == null) return null;
  // Sanitize BEFORE the emptiness test: a note made entirely of characters
  // `sanitizeDisplayText` strips is `isNotEmpty` before sanitization and empty
  // after it, so testing first would append a dangling ' · ' separator.
  final String n = note == null ? '' : sanitizeDisplayText(note).trim();
  return n.isEmpty ? streetLine : '$streetLine$kServiceNamesSeparator$n';
}

/// Translates [MasterSearchResult] DTOs into the domain [MasterSearchItem].
abstract final class MasterSearchMapper {
  static const _tag = 'feature.discovery.mapper';

  /// Maps a single [MasterSearchResult] DTO to [MasterSearchItem].
  ///
  /// Throws [ServerFailure] (statusCode `null`) when [dto.masterId] is absent —
  /// a result with no id is unusable downstream (routing to the public profile
  /// keys on it), so it is rejected rather than emitted with an empty id.
  static MasterSearchItem fromDto(MasterSearchResult dto) {
    final id = dto.masterId;
    if (id == null || id.isEmpty) {
      if (kDebugMode) {
        log(
          'MasterSearchResult.masterId is null/empty — broken backend contract',
          name: _tag,
          level: 1000,
        );
      }
      throw const ServerFailure(statusCode: null);
    }

    // Backend contract: serviceNames is always present ([] when none, ≤3
    // entries, custom-preferred). The generated builtSet is defensively
    // null-coalesced to const [] so a stale/omitting payload still yields a
    // card with no service line rather than a crash.
    final List<String> serviceNames =
        dto.serviceNames?.toList(growable: false) ?? const <String>[];

    // Matched service names (≤3) are populated by the backend ONLY when the
    // search carried a `serviceTypeSlugs` filter; otherwise the list is empty
    // and the pre-joined line stays null (the card falls back to serviceNames).
    final List<String> matchedServiceNames =
        dto.matchedServiceNames?.toList(growable: false) ?? const <String>[];

    return MasterSearchItem(
      masterId: id,
      firstName: dto.firstName ?? '',
      lastName: dto.lastName ?? '',
      avatarUrl: dto.avatarUrl,
      // Per phase doc: default a missing/null rating to 0.0 (not null).
      avgRating: dto.avgRating ?? 0.0,
      reviewCount: dto.reviewCount,
      cityLabel: dto.cityLabel,
      districtLabel: dto.districtLabel,
      minEffectivePrice: dto.minEffectivePrice?.toDouble(),
      priceMax: dto.priceMax?.toDouble(),
      street: dto.street,
      buildingNo: dto.buildingNo,
      locationNote: dto.locationNote,
      // Pre-join the street detail line ONCE here (mirrors servicesLine) so the
      // scrolling result list never re-runs the join per card build(). Street +
      // building + note only — the locality stays in the card.
      addressLine: _formatAddressLine(
        dto.street,
        dto.buildingNo,
        dto.locationNote,
      ),
      serviceNames: serviceNames,
      // Pre-join the preview line ONCE here so the scrolling result list never
      // re-runs join() per card build() (LOW perf fix). Null when empty → the
      // card omits the line (no placeholder).
      servicesLine: serviceNames.isEmpty
          ? null
          : serviceNames.join(kServiceNamesSeparator),
      // Matched-service line: same ' · ' join + null-when-empty contract as
      // servicesLine. Pre-joined ONCE here so the card never join()s per build.
      matchedServicesLine: matchedServiceNames.isEmpty
          ? null
          : matchedServiceNames.join(kServiceNamesSeparator),
    );
  }
}

/// Translates [SalonSearchResult] DTOs into the domain [SalonSearchItem].
abstract final class SalonSearchMapper {
  static const _tag = 'feature.discovery.mapper';

  /// Maps a single [SalonSearchResult] DTO to [SalonSearchItem].
  ///
  /// Throws [ServerFailure] (statusCode `null`) when [dto.salonId] is absent.
  /// [SalonSearchItem.avgRating] is always mapped to `null` — the DTO does not
  /// carry an avgRating field.
  static SalonSearchItem fromDto(SalonSearchResult dto) {
    final id = dto.salonId;
    if (id == null || id.isEmpty) {
      if (kDebugMode) {
        log(
          'SalonSearchResult.salonId is null/empty — broken backend contract',
          name: _tag,
          level: 1000,
        );
      }
      throw const ServerFailure(statusCode: null);
    }

    // Backend contract: serviceNames is always present ([] when none, ≤3
    // entries). Defensively null-coalesced so a stale/omitting payload still
    // yields a card with no service line rather than a crash.
    final List<String> serviceNames =
        dto.serviceNames?.toList(growable: false) ?? const <String>[];

    // Matched service names (≤3) are populated by the backend ONLY when the
    // search carried a `serviceTypeSlugs` filter; otherwise the list is empty
    // and the pre-joined line stays null (the card falls back to serviceNames).
    final List<String> matchedServiceNames =
        dto.matchedServiceNames?.toList(growable: false) ?? const <String>[];

    return SalonSearchItem(
      salonId: id,
      name: dto.name ?? '',
      avatarUrl: dto.avatarUrl,
      // SalonSearchResult does not expose avgRating; never invent one.
      avgRating: null,
      cityLabel: dto.cityLabel,
      districtLabel: dto.districtLabel,
      priceMin: dto.priceMin?.toDouble(),
      priceMax: dto.priceMax?.toDouble(),
      street: dto.street,
      buildingNo: dto.buildingNo,
      locationNote: dto.locationNote,
      // Pre-join the street detail line ONCE here (mirrors the master mapper) so
      // the scrolling result list never re-runs the join per card build().
      // Street + building + note only — the locality stays in the card.
      addressLine: _formatAddressLine(
        dto.street,
        dto.buildingNo,
        dto.locationNote,
      ),
      serviceNames: serviceNames,
      // Pre-join the preview line ONCE here (mirrors the master mapper) so the
      // scrolling result list never re-runs join() per card build(). Null when
      // empty → the card omits the line (no placeholder).
      servicesLine: serviceNames.isEmpty
          ? null
          : serviceNames.join(kServiceNamesSeparator),
      // Matched-service line: same ' · ' join + null-when-empty contract as
      // servicesLine. Pre-joined ONCE here so the card never join()s per build.
      matchedServicesLine: matchedServiceNames.isEmpty
          ? null
          : matchedServiceNames.join(kServiceNamesSeparator),
    );
  }
}
