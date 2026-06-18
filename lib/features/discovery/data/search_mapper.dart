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
    );
  }
}
