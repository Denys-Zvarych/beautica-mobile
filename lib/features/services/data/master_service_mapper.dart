// Phase 5.1 — MasterServiceMapper: data-layer translation between generated
// DTOs and the domain [MasterService] entity.
// Phase 5.6 — Flexible pricing: replaced single `price` field with a four-field
//             pricing block. Mapper reads priceType/priceMin/priceMax/priceDisplay
//             from both MasterServiceResponse and ServiceDefinitionResponse.
//             toCreateRequest and toUpdateRequest emit mode-conditional price fields.
//
// Translation boundary notes:
//   - [MasterServiceResponse] wraps a [ServiceDefinitionResponse] nested as
//     `serviceDefinition`. The mapper reads fields from both levels:
//       * id           ← MasterServiceResponse.id (assignment UUID)
//       * name         ← serviceDefinition.name
//       * description  ← serviceDefinition.description
//       * category     ← serviceDefinition.category (String wire name)
//       * durationMinutes ← effectiveDurationMinutes ?? serviceDefinition.baseDurationMinutes
//       * priceType    ← MasterServiceResponse.priceType ?? serviceDefinition.priceType
//       * priceMin     ← MasterServiceResponse.priceMin ?? serviceDefinition.priceMin (num → double)
//       * priceMax     ← MasterServiceResponse.priceMax ?? serviceDefinition.priceMax (num → double)
//       * priceDisplay ← MasterServiceResponse.priceDisplay ?? serviceDefinition.priceDisplay ?? ''
//       * bufferMinutesAfter ← serviceDefinition.bufferMinutesAfter ?? 0
//       * isActive     ← MasterServiceResponse.isActive ?? true
//
//   - Price fields are delivered as Dart `num` (not kopeck amounts). The mapper
//     converts to `double` via `.toDouble()`. No divide-by-100 is needed.
//
//   - [toCreateRequest] converts [MasterServiceCreate] → the generated
//     [CreateServiceDefinitionRequest] using the built_value builder pattern.
//     FIXED mode: sets priceType + price. RANGE mode: sets priceType + priceMin + priceMax.
//
//   - [toUpdateRequest] converts [MasterServiceUpdate] → the generated
//     [UpdateServiceDefinitionRequest] for PATCH /api/v1/services/{serviceDefId}.
//     Only non-null fields are set so the backend treats absent keys as "no change".
//     If the price block is present, all relevant price fields are sent.
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

// ---------------------------------------------------------------------------
// Internal helpers — enum mapping between wire EnumClass values and domain.
// ---------------------------------------------------------------------------

/// Maps the generated [MasterServiceResponsePriceTypeEnum] to the domain
/// [ServicePriceType]. Falls back to [ServicePriceType.fixed] for any
/// unrecognised or null value to avoid breaking the list/detail UI.
ServicePriceType _domainPriceTypeFromMsrEnum(
  MasterServiceResponsePriceTypeEnum? raw,
) {
  if (raw == MasterServiceResponsePriceTypeEnum.RANGE) {
    return ServicePriceType.range;
  }
  return ServicePriceType.fixed;
}

/// Maps the generated [ServiceDefinitionResponsePriceTypeEnum] to the domain
/// [ServicePriceType]. Same safe-default convention as [_domainPriceTypeFromMsrEnum].
ServicePriceType _domainPriceTypeFromSdrEnum(
  ServiceDefinitionResponsePriceTypeEnum? raw,
) {
  if (raw == ServiceDefinitionResponsePriceTypeEnum.RANGE) {
    return ServicePriceType.range;
  }
  return ServicePriceType.fixed;
}

/// Maps the domain [ServicePriceType] to the generated
/// [CreateServiceDefinitionRequestPriceTypeEnum].
CreateServiceDefinitionRequestPriceTypeEnum _createPriceTypeEnum(
  ServicePriceType t,
) {
  switch (t) {
    case ServicePriceType.range:
      return CreateServiceDefinitionRequestPriceTypeEnum.RANGE;
    case ServicePriceType.fixed:
      return CreateServiceDefinitionRequestPriceTypeEnum.FIXED;
  }
}

/// Maps the domain [ServicePriceType] to the generated
/// [UpdateServiceDefinitionRequestPriceTypeEnum].
UpdateServiceDefinitionRequestPriceTypeEnum _updatePriceTypeEnum(
  ServicePriceType t,
) {
  switch (t) {
    case ServicePriceType.range:
      return UpdateServiceDefinitionRequestPriceTypeEnum.RANGE;
    case ServicePriceType.fixed:
      return UpdateServiceDefinitionRequestPriceTypeEnum.FIXED;
  }
}

/// Translates generated API types from `beautica_api` into domain entities
/// and vice-versa for the service feature.
///
/// Pure translation class — no network calls, no state. Call only from
/// [HttpServiceRepository].
abstract final class MasterServiceMapper {
  /// Maps a [MasterServiceResponse] DTO to the domain [MasterService] model.
  ///
  /// Pricing fields are read from the top-level MSR envelope (priceType,
  /// priceMin, priceMax, priceDisplay) which the backend V67+ populates
  /// directly. A null priceType falls back to FIXED (safe default so
  /// pre-V67 data or a partially-deployed backend never breaks the UI).
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

    // Duration: master override takes priority; fall back to the base definition.
    final duration =
        dto.effectiveDurationMinutes ?? def?.baseDurationMinutes ?? 0;

    // Pricing: read from the top-level MSR envelope first (V67+). These fields
    // are surfaced from the nested ServiceDefinitionResponse by the backend
    // mapper. Fall back chain:
    //   dto.priceMin (V67+ top-level)
    //   → def.priceMin (ServiceDefinitionResponse, also V67+)
    //   → dto.effectivePrice (legacy floor, still present on MSR)
    //   → 0 (absolute last resort — service with no price data)
    //
    // Pricing mode: A null priceType on the MSR falls back to the nested
    // ServiceDefinitionResponse's priceType, then to FIXED as a safe default.
    final priceType = _domainPriceTypeFromMsrEnum(
      dto.priceType ??
          (def?.priceType == ServiceDefinitionResponsePriceTypeEnum.RANGE
              ? MasterServiceResponsePriceTypeEnum.RANGE
              : null),
    );
    final priceMin = (dto.priceMin ?? def?.priceMin ?? dto.effectivePrice ?? 0)
        .toDouble();
    final priceMax = (dto.priceMax ?? def?.priceMax)?.toDouble();
    final priceDisplay = dto.priceDisplay ?? def?.priceDisplay ?? '';

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

    // Service type (Phase 16.3). The backend surfaces these on the top-level
    // MSR envelope; fall back to the nested ServiceDefinitionResponse so the
    // selection round-trips regardless of which level the backend populated.
    final serviceTypeId = dto.serviceTypeId ?? def?.serviceTypeId;
    final serviceTypeNameUk = dto.serviceTypeNameUk ?? def?.serviceTypeNameUk;

    return MasterService(
      id: id,
      serviceDefId: serviceDefId,
      name: def?.name ?? '',
      description: def?.description,
      category: def?.category,
      serviceTypeId: serviceTypeId,
      serviceTypeNameUk: serviceTypeNameUk,
      durationMinutes: duration,
      priceType: priceType,
      priceMin: priceMin,
      priceMax: priceMax,
      priceDisplay: priceDisplay,
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

    final priceType = _domainPriceTypeFromSdrEnum(dto.priceType);
    // ServiceDefinitionResponse carries priceMin (base_price floor) as of V67.
    // basePrice field was removed in the flexible-pricing migration.
    final priceMin = (dto.priceMin ?? 0).toDouble();
    final priceMax = dto.priceMax?.toDouble();
    final priceDisplay = dto.priceDisplay ?? '';

    return MasterService(
      id: assignmentId,
      serviceDefId: serviceDefId,
      name: dto.name ?? '',
      description: dto.description,
      category: dto.category,
      // Service type round-trips from the definition response (Phase 16.3).
      serviceTypeId: dto.serviceTypeId,
      serviceTypeNameUk: dto.serviceTypeNameUk,
      durationMinutes: dto.baseDurationMinutes ?? 0,
      priceType: priceType,
      priceMin: priceMin,
      priceMax: priceMax,
      priceDisplay: priceDisplay,
      bufferMinutesAfter: dto.bufferMinutesAfter ?? 0,
      isActive: dto.isActive ?? true,
    );
  }

  /// Converts [MasterServiceCreate] to the generated
  /// [CreateServiceDefinitionRequest] builder type.
  ///
  /// Required fields ([name], [baseDurationMinutes], [priceType], and the
  /// mode-conditional price field(s)) are always present. Optional fields
  /// are omitted when null.
  ///
  /// FIXED mode: sets priceType + price. priceMin/priceMax must be null.
  /// RANGE mode: sets priceType + priceMin + priceMax. price must be null.
  ///
  /// Throws [ArgumentError] for invalid field values before the request
  /// reaches the network layer (security MEDIUM-1):
  ///   - [durationMinutes] < 1
  ///   - FIXED: [price] null or <= 0
  ///   - RANGE: [priceMin] null or <= 0; [priceMax] null or <= [priceMin]
  ///   - [bufferMinutesAfter] < 0 (when provided)
  ///   - [category] null or empty (required by backend @NotBlank)
  static CreateServiceDefinitionRequest toCreateRequest(
    MasterServiceCreate input,
  ) {
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
    // category is REQUIRED by the backend (`@NotBlank` on
    // CreateServiceDefinitionRequest.category). Fail fast at the data boundary.
    final category = input.category;
    if (category == null || category.isEmpty) {
      throw ArgumentError.value(category, 'category', 'category is required');
    }

    // Validate mode-conditional price fields.
    switch (input.priceType) {
      case ServicePriceType.fixed:
        final price = input.price;
        if (price == null || price <= 0) {
          throw ArgumentError.value(
            price,
            'price',
            'FIXED mode requires price > 0',
          );
        }
      case ServicePriceType.range:
        final min = input.priceMin;
        final max = input.priceMax;
        if (min == null || min <= 0) {
          throw ArgumentError.value(
            min,
            'priceMin',
            'RANGE mode requires priceMin > 0',
          );
        }
        if (max == null || max <= min) {
          throw ArgumentError.value(
            max,
            'priceMax',
            'RANGE mode requires priceMax > priceMin',
          );
        }
    }

    return CreateServiceDefinitionRequest((b) {
      b
        ..name = input.name
        ..baseDurationMinutes = input.durationMinutes
        ..priceType = _createPriceTypeEnum(input.priceType)
        ..category = category;

      if (input.description != null) b.description = input.description;
      if (buffer != null) b.bufferMinutesAfter = buffer;

      // Optional service type (Phase 16.3). Assign only when the master picked
      // one — the generated serializer omits null builder fields, so the wire
      // body carries `serviceTypeId` only when a type is selected. The backend
      // cross-validates it against `category`; a mismatch returns a
      // ValidationFailure keyed on `serviceTypeId`.
      if (input.serviceTypeId != null) b.serviceTypeId = input.serviceTypeId;

      // Set the mode-conditional price fields. The generated serializer omits
      // null builder fields from the wire body so the backend receives only the
      // appropriate subset.
      switch (input.priceType) {
        case ServicePriceType.fixed:
          b.price = input.price;
        case ServicePriceType.range:
          b.priceMin = input.priceMin;
          b.priceMax = input.priceMax;
      }
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
  /// Pricing PATCH rule (mirrors the backend): if ALL four price fields
  /// ([priceType], [price], [priceMin], [priceMax]) are null on [patch], the
  /// price block is omitted entirely and the existing pricing is preserved.
  /// When [priceType] is non-null, the full mode payload is sent.
  ///
  /// Throws [ArgumentError] for invalid field values — before the request
  /// reaches the network layer (security MEDIUM-1):
  ///   - [durationMinutes] present and < 1
  ///   - [bufferMinutesAfter] present and < 0
  ///   - FIXED update: [price] null or <= 0
  ///   - RANGE update: [priceMin] null or <= 0; [priceMax] null or <= [priceMin]
  static UpdateServiceDefinitionRequest toUpdateRequest(
    MasterServiceUpdate patch,
  ) {
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

    // Validate price block when present.
    final patchPriceType = patch.priceType;
    if (patchPriceType != null) {
      switch (patchPriceType) {
        case ServicePriceType.fixed:
          final price = patch.price;
          if (price == null || price <= 0) {
            throw ArgumentError.value(
              price,
              'price',
              'FIXED mode requires price > 0',
            );
          }
        case ServicePriceType.range:
          final min = patch.priceMin;
          final max = patch.priceMax;
          if (min == null || min <= 0) {
            throw ArgumentError.value(
              min,
              'priceMin',
              'RANGE mode requires priceMin > 0',
            );
          }
          if (max == null || max <= min) {
            throw ArgumentError.value(
              max,
              'priceMax',
              'RANGE mode requires priceMax > priceMin',
            );
          }
      }
    }

    return UpdateServiceDefinitionRequest((b) {
      // Blank-name default (backend-aligned): a non-null name — including an
      // empty string the master cleared — is sent through. The backend defaults
      // a blank/null name to the selected service type's nameUk, so the client
      // no longer substitutes a fallback name itself. A `null` name still means
      // "do not change" (key omitted from the PATCH body).
      if (patch.name != null) b.name = patch.name;
      if (patch.description != null) b.description = patch.description;
      if (patch.category != null) b.category = patch.category;
      // Service type (Phase 16.x). Assign only when the patch carries a value —
      // the generated serializer omits a null builder field, so a `null`
      // serviceTypeId leaves the current type unchanged on the wire.
      if (patch.serviceTypeId != null) b.serviceTypeId = patch.serviceTypeId;
      if (duration != null) b.baseDurationMinutes = duration;
      if (buffer != null) b.bufferMinutesAfter = buffer;

      // Set the price block only when priceType is present.
      if (patchPriceType != null) {
        b.priceType = _updatePriceTypeEnum(patchPriceType);
        switch (patchPriceType) {
          case ServicePriceType.fixed:
            b.price = patch.price;
          case ServicePriceType.range:
            b.priceMin = patch.priceMin;
            b.priceMax = patch.priceMax;
        }
      }
    });
  }
}
