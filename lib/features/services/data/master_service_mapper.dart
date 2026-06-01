// Phase 5.1 — MasterServiceMapper: data-layer translation between generated
// DTOs and the domain [MasterService] entity.
//
// Translation boundary notes:
//   - [MasterServiceResponse] wraps a [ServiceDefinitionResponse] nested as
//     `serviceDefinition`. The mapper reads fields from both levels:
//       * id           ← MasterServiceResponse.id (assignment UUID)
//       * name         ← serviceDefinition.name
//       * description  ← serviceDefinition.description
//       * category     ← serviceDefinition.category?.name (enum wire name)
//       * durationMinutes ← effectiveDurationMinutes ?? serviceDefinition.baseDurationMinutes
//       * price        ← effectivePrice ?? serviceDefinition.basePrice (num → double)
//       * bufferMinutesAfter ← serviceDefinition.bufferMinutesAfter ?? 0
//       * isActive     ← MasterServiceResponse.isActive ?? true
//
//   - Price is delivered as Dart `num` (not an integer kopeck amount). The
//     mapper converts to `double` via `.toDouble()`. No divide-by-100 is needed.
//
//   - [toCreateRequest] converts [MasterServiceCreate] → the generated
//     [CreateServiceDefinitionRequest] using the built_value builder pattern.
//
//   - [toUpdateBody] converts [MasterServiceUpdate] → a plain [Map] for a
//     hand-written PATCH (no generated update request exists in the API client).
//     Only non-null fields are included so the backend treats absent keys as
//     "no change".
//
// Error contract: a null [MasterServiceResponse.id] throws [ServerFailure]
// (broken backend contract). All other nulls are substituted with safe
// defaults or passed through as null.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';

import '../domain/master_service.dart';
import '../domain/master_service_input.dart';

/// Translates generated API types from `beautica_api` into domain entities
/// and vice-versa for the service feature.
///
/// Pure translation class — no network calls, no state. Call only from
/// [HttpServiceRepository].
abstract final class MasterServiceMapper {
  /// Maps a [MasterServiceResponse] DTO to the domain [MasterService] model.
  ///
  /// Throws [ServerFailure] (statusCode `null`) when [dto.id] is absent,
  /// indicating a broken backend contract.
  static MasterService fromDto(MasterServiceResponse dto) {
    final id = dto.id;
    if (id == null || id.isEmpty) {
      log(
        'MasterServiceResponse.id is null — broken backend contract',
        name: 'feature.services.mapper',
        level: 1000,
      );
      throw const ServerFailure(statusCode: null);
    }

    final def = dto.serviceDefinition;

    // Effective values (master override) take priority; fall back to the base
    // service definition values if no override is set.
    final duration =
        dto.effectiveDurationMinutes ?? def?.baseDurationMinutes ?? 0;
    final price = (dto.effectivePrice ?? def?.basePrice ?? 0).toDouble();

    // futureBookingCount is not yet returned by the backend API. Log a
    // development-mode reminder so engineers are aware the field is absent.
    // This is NOT an assert — the field being absent is expected and safe.
    // TODO: read dto.futureBookingCount once backend exposes it in
    // MasterServiceResponse and remove this log.
    assert(() {
      log(
        'MasterServiceMapper.fromDto: futureBookingCount not yet populated '
        'by backend (defaults to 0). Blocked-delete variant is suppressed '
        'until the field is exposed in MasterServiceResponse.',
        name: 'feature.services.mapper',
        level: 700,
      );
      return true;
    }());

    return MasterService(
      id: id,
      name: def?.name ?? '',
      description: def?.description,
      category: def?.category?.name,
      durationMinutes: duration,
      price: price,
      bufferMinutesAfter: def?.bufferMinutesAfter ?? 0,
      isActive: dto.isActive ?? true,
    );
  }

  /// Converts [MasterServiceCreate] to the generated
  /// [CreateServiceDefinitionRequest] builder type.
  ///
  /// Required fields ([name], [baseDurationMinutes], [basePrice]) are always
  /// present. Optional fields are omitted when null.
  ///
  /// Throws [ArgumentError] for invalid field values — before the request
  /// reaches the network layer (security MEDIUM-1):
  ///   - [price] < 0
  ///   - [durationMinutes] < 1
  ///   - [bufferMinutesAfter] < 0 (when provided)
  static CreateServiceDefinitionRequest toCreateRequest(
    MasterServiceCreate input,
  ) {
    if (input.price < 0) {
      throw ArgumentError.value(input.price, 'price', 'price must be >= 0');
    }
    if (input.durationMinutes < 1) {
      throw ArgumentError.value(
        input.durationMinutes,
        'durationMinutes',
        'durationMinutes must be >= 1',
      );
    }
    final buffer = input.bufferMinutesAfter;
    if (buffer != null && buffer < 0) {
      throw ArgumentError.value(
        buffer,
        'bufferMinutesAfter',
        'bufferMinutesAfter must be >= 0',
      );
    }

    return CreateServiceDefinitionRequest((b) {
      b
        ..name = input.name
        ..baseDurationMinutes = input.durationMinutes
        // price is double in the domain; basePrice is num in the generated
        // type — direct assignment is safe (double is a num).
        ..basePrice = input.price;

      if (input.description != null) b.description = input.description;
      if (buffer != null) b.bufferMinutesAfter = buffer;
      if (input.category != null) {
        b.category = _categoryEnum(input.category!);
      }
    });
  }

  /// Maps a category wire-name string to [CreateServiceDefinitionRequestCategoryEnum].
  ///
  /// Returns [CreateServiceDefinitionRequestCategoryEnum.OTHER] for any
  /// unrecognised wire value so the call never throws at the data boundary.
  static CreateServiceDefinitionRequestCategoryEnum _categoryEnum(String wire) {
    switch (wire) {
      case 'MANICURE':
        return CreateServiceDefinitionRequestCategoryEnum.MANICURE;
      case 'PEDICURE':
        return CreateServiceDefinitionRequestCategoryEnum.PEDICURE;
      case 'EYELASH':
        return CreateServiceDefinitionRequestCategoryEnum.EYELASH;
      case 'HAIRCUT':
        return CreateServiceDefinitionRequestCategoryEnum.HAIRCUT;
      case 'MAKEUP':
        return CreateServiceDefinitionRequestCategoryEnum.MAKEUP;
      case 'BROWS':
        return CreateServiceDefinitionRequestCategoryEnum.BROWS;
      default:
        return CreateServiceDefinitionRequestCategoryEnum.OTHER;
    }
  }

  /// Converts [MasterServiceUpdate] to a plain body map for PATCH.
  ///
  /// Only non-null fields from [patch] are included in the returned map so
  /// the backend ignores absent keys (PATCH semantics). Returns an empty map
  /// when all fields are null (no-op update — callers should guard against
  /// sending a no-op if desired).
  ///
  /// Throws [ArgumentError] for invalid field values — before the request
  /// reaches the network layer (security MEDIUM-1):
  ///   - [price] present and < 0
  ///   - [durationMinutes] present and < 1
  ///   - [bufferMinutesAfter] present and < 0
  static Map<String, dynamic> toUpdateBody(MasterServiceUpdate patch) {
    final price = patch.price;
    if (price != null && price < 0) {
      throw ArgumentError.value(price, 'price', 'price must be >= 0');
    }
    final duration = patch.durationMinutes;
    if (duration != null && duration < 1) {
      throw ArgumentError.value(
        duration,
        'durationMinutes',
        'durationMinutes must be >= 1',
      );
    }
    final buffer = patch.bufferMinutesAfter;
    if (buffer != null && buffer < 0) {
      throw ArgumentError.value(
        buffer,
        'bufferMinutesAfter',
        'bufferMinutesAfter must be >= 0',
      );
    }

    final body = <String, dynamic>{};
    if (patch.name != null) body['name'] = patch.name;
    if (patch.description != null) body['description'] = patch.description;
    if (patch.category != null) body['category'] = patch.category;
    if (duration != null) body['durationMinutes'] = duration;
    if (price != null) body['price'] = price;
    if (buffer != null) body['bufferMinutesAfter'] = buffer;
    if (patch.isActive != null) body['isActive'] = patch.isActive;
    return body;
  }
}
