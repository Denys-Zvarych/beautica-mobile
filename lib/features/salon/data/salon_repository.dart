// TODO(phase-3.2): replace hand-written payloads with generated SalonApi DTOs.
//
// Phase 2.19 — SalonRepository (hand-written Dio).
//
// Created during registration Step 3 for the SALON_OWNER role: immediately
// after the owner's account registers, the app POSTs the salon (name +
// locality + address) so the owner lands on a fully-provisioned salon, per
// backend Phase 10.6.
//
// Backend contract (locked):
//   POST /api/v1/salons
//     Body: { name, cityId (UUID), districtId? (UUID|null), street, buildingNo,
//             locationNote? }
//     Returns: ApiResponse<SalonResponse> — the mobile layer does not need the
//              body here, so the method resolves with void.
//
// The base URL already carries the `/api/v1` prefix (see AppConfig.baseUrl), so
// the path below is the suffix only.

import 'dart:developer';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'salon_repository.g.dart';

/// Immutable write payload for `POST /salons`.
///
/// Hand-written (no generated DTO yet). [districtId] and [locationNote] are
/// nullable optionals; [toJson] omits them when null/empty so the backend sees
/// a clean body rather than explicit nulls.
@immutable
final class SalonCreateDto {
  const SalonCreateDto({
    required this.name,
    required this.cityId,
    this.districtId,
    required this.street,
    required this.buildingNo,
    this.locationNote,
  });

  /// Salon display name (collected in Step 2 as `salonName`).
  final String name;

  /// UUID of the salon's city.
  final String cityId;

  /// UUID of the salon's district, or null when the city is a leaf.
  final String? districtId;

  /// Street line.
  final String street;

  /// Building number / identifier.
  final String buildingNo;

  /// Optional free-text note (floor, entrance, intercom, …).
  final String? locationNote;

  /// Serialises to the backend body, omitting empty optionals.
  Map<String, dynamic> toJson() {
    final trimmedNote = locationNote?.trim();
    final json = <String, dynamic>{
      'name': name.trim(),
      'cityId': cityId,
      'street': street.trim(),
      'buildingNo': buildingNo.trim(),
    };
    if (districtId != null && districtId!.isNotEmpty) {
      json['districtId'] = districtId;
    }
    if (trimmedNote != null && trimmedNote.isNotEmpty) {
      json['locationNote'] = trimmedNote;
    }
    return json;
  }
}

/// Contract for the salon write layer.
///
/// Every method either resolves successfully or throws a [Failure] subclass
/// from `core/errors/failures.dart`. Raw [DioException]s never escape.
abstract interface class SalonRepository {
  /// Creates a salon owned by the authenticated user.
  ///
  /// Wraps `POST /salons`. Throws a typed [Failure] on any transport or server
  /// error.
  Future<void> create({required SalonCreateDto dto});
}

/// HTTP implementation of [SalonRepository].
///
/// Inject via [salonRepositoryProvider] — never construct directly.
final class HttpSalonRepository implements SalonRepository {
  HttpSalonRepository(this._dio);

  final Dio _dio;

  @override
  Future<void> create({required SalonCreateDto dto}) async {
    try {
      await _dio.post<Map<String, dynamic>>('/salons', data: dto.toJson());
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'salon create failed: ${e.type} ${e.response?.statusCode}',
          name: 'salon.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  /// Maps a [DioException] to a typed [Failure]. See [HttpMasterRepository] for
  /// the identical mapping rationale.
  Failure _mapDioException(DioException e) {
    if (e.error is Failure) return e.error as Failure;
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkFailure(cause: e);
      case DioExceptionType.badResponse:
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return ServerFailure(statusCode: e.response?.statusCode, cause: e);
    }
  }
}

/// Provides the [SalonRepository] singleton backed by the authenticated Dio.
///
/// Override in tests with a mocktail mock — never construct [HttpSalonRepository]
/// directly in tests.
@Riverpod(keepAlive: true)
SalonRepository salonRepository(Ref ref) =>
    HttpSalonRepository(ref.watch(dioProvider));
