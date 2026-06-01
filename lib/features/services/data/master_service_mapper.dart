// Phase 5.1 — MasterServiceMapper: data-layer translation between generated
// DTOs and the domain [MasterService] entity.
//
// Translation boundary notes:
//   - [MasterServiceResponse] wraps a [ServiceDefinitionResponse] nested as
//     `serviceDefinition`. The mapper reads fields from both levels:
//       * id           ← MasterServiceResponse.id (assignment UUID)
//       * name         ← serviceDefinition.name
//       * description  ← serviceDefinition.description
//       * category     ← serviceDefinition.category (String wire name)
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
//   - [toUpdateRequest] converts [MasterServiceUpdate] → the generated
//     [UpdateServiceDefinitionRequest] for PATCH /api/v1/services/{serviceDefId}.
//     Only non-null fields are set so the backend treats absent keys as
//     "no change". (Domain durationMinutes/price → wire baseDurationMinutes/basePrice.)
//   - [fromServiceDefinitionDto] maps the [ServiceDefinitionResponse] returned by
//     that update endpoint back to [MasterService] (carrying the assignment id
//     through, since the response omits it).
//
// Error contract: a null [MasterServiceResponse.id] throws [ServerFailure]
// (broken backend contract). All other nulls are substituted with safe
// defaults or passed through as null.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';

import '../domain/master_service.dart';
import '../domain/master_service_input.dart';
import '../domain/service_category_option.dart';

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

    // The backend's update/deactivate endpoints key on the service-definition
    // id (`/api/v1/services/{serviceDefId}`), NOT the assignment id. Capture it
    // from the nested serviceDefinition so the repository can route mutations
    // correctly. A null/empty value means the backend omitted it — log so the
    // broken contract surfaces, but do not throw (list/read still works).
    final serviceDefId = def?.id ?? '';
    if (serviceDefId.isEmpty) {
      log(
        'MasterServiceResponse.serviceDefinition.id is null — update/delete '
        'will fail for assignment id=$id',
        name: 'feature.services.mapper',
        level: 1000,
      );
    }

    return MasterService(
      id: id,
      serviceDefId: serviceDefId,
      name: def?.name ?? '',
      description: def?.description,
      category: def?.category,
      durationMinutes: duration,
      price: price,
      bufferMinutesAfter: def?.bufferMinutesAfter ?? 0,
      isActive: dto.isActive ?? true,
    );
  }

  /// Maps a [ServiceDefinitionResponse] DTO (returned by the update endpoint
  /// `PATCH /api/v1/services/{serviceDefId}`) to the domain [MasterService].
  ///
  /// Unlike [fromDto], this response carries no master-level override fields
  /// (`effectivePrice` / `effectiveDurationMinutes`); for an INDEPENDENT_MASTER
  /// the definition's base values *are* the effective values, so we read them
  /// directly.
  ///
  /// The response does not include the master-service *assignment* id, so the
  /// caller passes the existing [assignmentId] through to keep the returned
  /// [MasterService.id] stable for cache lookup and routing.
  ///
  /// Throws [ServerFailure] (statusCode `null`) when [dto.id] is absent
  /// (broken backend contract — the serviceDefId is required downstream).
  static MasterService fromServiceDefinitionDto(
    ServiceDefinitionResponse dto, {
    required String assignmentId,
  }) {
    final serviceDefId = dto.id;
    if (serviceDefId == null || serviceDefId.isEmpty) {
      log(
        'ServiceDefinitionResponse.id is null — broken backend contract',
        name: 'feature.services.mapper',
        level: 1000,
      );
      throw const ServerFailure(statusCode: null);
    }

    return MasterService(
      id: assignmentId,
      serviceDefId: serviceDefId,
      name: dto.name ?? '',
      description: dto.description,
      category: dto.category,
      durationMinutes: dto.baseDurationMinutes ?? 0,
      price: (dto.basePrice ?? 0).toDouble(),
      bufferMinutesAfter: dto.bufferMinutesAfter ?? 0,
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
    // category is now REQUIRED by the backend (`@NotBlank` on
    // CreateServiceDefinitionRequest.category) and the generated request types
    // it as a non-nullable String. Fail fast at the data boundary if the form
    // somehow submits without a category selected — the create form enforces
    // selection before reaching here.
    final category = input.category;
    if (category == null || category.isEmpty) {
      throw ArgumentError.value(category, 'category', 'category is required');
    }

    return CreateServiceDefinitionRequest((b) {
      b
        ..name = input.name
        ..baseDurationMinutes = input.durationMinutes
        // price is double in the domain; basePrice is num in the generated
        // type — direct assignment is safe (double is a num).
        ..basePrice = input.price
        // category is a plain String on the generated request (backend changed
        // the field from a strict enum → String to support self-service
        // approved categories). Pass the wire name through directly.
        ..category = category;

      if (input.description != null) b.description = input.description;
      if (buffer != null) b.bufferMinutesAfter = buffer;
    });
  }

  /// Maps an [ApprovedCategoryResponse] DTO to the domain
  /// [ServiceCategoryOption] used by the category picker.
  ///
  /// Both [name] and [displayName] are nullable on the generated DTO. A
  /// category with a null/empty [name] is unusable as a selectable value, so
  /// it is dropped by [fromApprovedCategoryList] rather than mapped here.
  /// [displayName] falls back to [name] when absent so the chip always has a
  /// readable label.
  static ServiceCategoryOption fromApprovedCategory(
    ApprovedCategoryResponse dto,
  ) {
    final name = dto.name ?? '';
    return ServiceCategoryOption(
      name: name,
      displayName: (dto.displayName?.isNotEmpty ?? false)
          ? dto.displayName!
          : name,
    );
  }

  /// Maps a list of [ApprovedCategoryResponse] DTOs to domain options,
  /// dropping any entry whose wire [name] is null or empty (unselectable).
  static List<ServiceCategoryOption> fromApprovedCategoryList(
    Iterable<ApprovedCategoryResponse> dtos,
  ) => dtos
      .map(fromApprovedCategory)
      .where((o) => o.name.isNotEmpty)
      .toList(growable: false);

  /// Converts [MasterServiceUpdate] to the generated
  /// [UpdateServiceDefinitionRequest] for `PATCH /api/v1/services/{serviceDefId}`.
  ///
  /// Only non-null fields from [patch] are set on the builder so the backend
  /// treats absent keys as "no change" (PATCH semantics). The generated
  /// serializer omits null builder fields from the wire body.
  ///
  /// Field-name boundary: the domain uses [MasterServiceUpdate.durationMinutes]
  /// / [MasterServiceUpdate.price]; the backend request expects
  /// `baseDurationMinutes` / `basePrice`. The mapping happens here. Note the
  /// request has no `isActive` field — deactivation goes through the dedicated
  /// `DELETE /api/v1/services/{serviceDefId}` endpoint, not this PATCH.
  ///
  /// Throws [ArgumentError] for invalid field values — before the request
  /// reaches the network layer (security MEDIUM-1):
  ///   - [price] present and < 0
  ///   - [durationMinutes] present and < 1
  ///   - [bufferMinutesAfter] present and < 0
  static UpdateServiceDefinitionRequest toUpdateRequest(
    MasterServiceUpdate patch,
  ) {
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

    return UpdateServiceDefinitionRequest((b) {
      if (patch.name != null) b.name = patch.name;
      if (patch.description != null) b.description = patch.description;
      if (patch.category != null) b.category = patch.category;
      if (duration != null) b.baseDurationMinutes = duration;
      if (price != null) b.basePrice = price;
      if (buffer != null) b.bufferMinutesAfter = buffer;
    });
  }
}
