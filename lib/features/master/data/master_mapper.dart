// Phase 4.1 — MasterMapper: data-layer translation from generated DTO to domain.
//
// [MasterMapper.fromDto] is the single translation boundary between
// [MasterDetailResponse] (generated API type, lives in `package:beautica_api`)
// and the domain [Master] entity. Generated DTO types must not cross this
// boundary into the domain or presentation layers.
//
// Error contract (backlog pattern — use ServerFailure for missing required
// backend fields):
//   - [MasterDetailResponse.masterId] is required; a null value indicates a
//     broken backend contract and surfaces as [ServerFailure].
//   - All other nullable fields are either passed through as `null` or
//     substituted with safe defaults (empty string, 0).

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';

import '../domain/master.dart';

/// Converts generated API types from the `beautica_api` package into the
/// domain [Master] entity.
///
/// This is a pure translation class — no network calls, no state. Inject /
/// call it only from [HttpMasterRepository].
abstract final class MasterMapper {
  /// Maps a [MasterDetailResponse] DTO to the domain [Master] model.
  ///
  /// Throws [ServerFailure] (statusCode `null`) when [dto.masterId] is
  /// absent, signalling a broken backend contract rather than a network or
  /// auth failure.
  static Master fromDto(MasterDetailResponse dto) {
    final masterId = dto.masterId;
    if (masterId == null || masterId.isEmpty) {
      log(
        'MasterDetailResponse.masterId is null — broken backend contract',
        name: 'feature.master.mapper',
        level: 1000,
      );
      throw const ServerFailure(statusCode: null);
    }

    return Master(
      id: masterId,
      firstName: dto.firstName ?? '',
      lastName: dto.lastName ?? '',
      city: dto.city,
      bio: dto.bio,
      avatarUrl: dto.avatarUrl,
      avgRating: (dto.avgRating ?? 0).toDouble(),
      reviewCount: dto.reviewCount ?? 0,
      type: dto.masterType != null
          ? _masterTypeFromDto(dto.masterType!)
          : MasterType.salonMaster,
      salonId: dto.salon?.id,
    );
  }

  /// Translates [MasterDetailResponseMasterTypeEnum] (built_value EnumClass)
  /// to the domain [MasterType] enum.
  static MasterType _masterTypeFromDto(MasterDetailResponseMasterTypeEnum e) {
    if (e == MasterDetailResponseMasterTypeEnum.INDEPENDENT_MASTER) {
      return MasterType.independentMaster;
    }
    if (e == MasterDetailResponseMasterTypeEnum.SALON_OWNER) {
      return MasterType.salonOwner;
    }
    // Covers SALON_MASTER and any future values that may be added before
    // this mapper is updated — fail-safe to salonMaster.
    return MasterType.salonMaster;
  }
}
