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

import '../domain/master_search_item.dart';
import '../domain/salon_search_item.dart';

/// Pre-joins a (auth-gated) street + building number into one
/// «street, buildingNo» address line, or returns `null` when the street is
/// absent/blank. Pure-Dart so the data layer can compute it at map time without
/// importing `presentation/`; mirrors `formatAddress` in the result-card
/// helpers EXACTLY (street with no building → just the street; building with no
/// street → null). Only the street portion is precomputed here — the
/// city/district locality fallback stays in the card's `build()`.
String? _formatAddressLine(String? street, String? buildingNo) {
  final String? s = (street != null && street.trim().isNotEmpty)
      ? street.trim()
      : null;
  if (s == null) return null;
  final String? b = (buildingNo != null && buildingNo.trim().isNotEmpty)
      ? buildingNo.trim()
      : null;
  return b == null ? s : '$s, $b';
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
      // Pre-join the street address ONCE here (mirrors servicesLine) so the
      // scrolling result list never re-runs the street join per card build().
      // Street portion only — the locality fallback stays in the card.
      addressLine: _formatAddressLine(dto.street, dto.buildingNo),
      serviceNames: serviceNames,
      // Pre-join the preview line ONCE here so the scrolling result list never
      // re-runs join() per card build() (LOW perf fix). Null when empty → the
      // card omits the line (no placeholder).
      servicesLine: serviceNames.isEmpty
          ? null
          : serviceNames.join(kServiceNamesSeparator),
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
      // Pre-join the street address ONCE here (mirrors the master mapper) so the
      // scrolling result list never re-runs the street join per card build().
      // Street portion only — the locality fallback stays in the card.
      addressLine: _formatAddressLine(dto.street, dto.buildingNo),
      serviceNames: serviceNames,
      // Pre-join the preview line ONCE here (mirrors the master mapper) so the
      // scrolling result list never re-runs join() per card build(). Null when
      // empty → the card omits the line (no placeholder).
      servicesLine: serviceNames.isEmpty
          ? null
          : serviceNames.join(kServiceNamesSeparator),
    );
  }
}
