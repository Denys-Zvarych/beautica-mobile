// Phase 16.2 — Unit tests for [HttpServiceRepository.fetchServiceTypes].
//
// Strategy:
//   Mocks [ServiceCatalogControllerApi] with mocktail and constructs
//   [HttpServiceRepository] directly (pure Dart, no Riverpod overhead), mirroring
//   service_repository_test.dart.
//
// The `GET /service-types?categoryName=...` response is a `oneOf` over:
//   [0] ApiResponseListPlatformServiceTypeResponse  — the live slug-contract
//       branch the categoryName path resolves to.
//   [1] ApiResponseListServiceTypeResponse          — legacy alternate; ignored.
// The repository binds to branch [0] by the unwrapped value's runtime type and
// degrades any other shape to an empty list rather than throwing.
//
// Coverage:
//   1. Platform branch with rows  → mapped List<ServiceTypeOption>.
//   2. Platform branch, empty list → empty list.
//   3. Platform branch, null .data → empty list.
//   4. Legacy branch resolved      → empty list (graceful degrade, no throw).
//      ← highest-value guard for the 16.1 oneOf contract nuance.
//   5. forwards categoryName to the generated API.
//   6. connectionError             → NetworkFailure.
//   7. 400 / 422                   → ValidationFailure.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:one_of/one_of.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────

class _MockServiceControllerApi extends Mock implements ServiceControllerApi {}

class _MockCategoryRequestControllerApi extends Mock
    implements CategoryRequestControllerApi {}

class _MockServiceCatalogControllerApi extends Mock
    implements ServiceCatalogControllerApi {}

// ── Helpers ─────────────────────────────────────────────────────────────────

const _masterId = 'master-abc';
const _category = 'EYELASH';
const _path = '/api/v1/service-types';

/// Builds a slug-contract [PlatformServiceTypeResponse].
PlatformServiceTypeResponse _platformDto({
  String id = 'type-1',
  String slug = 'CLASSIC_LASHES',
  String nameUk = 'Класичне нарощування',
  String categoryName = _category,
}) => PlatformServiceTypeResponse(
  (b) => b
    ..id = id
    ..slug = slug
    ..nameUk = nameUk
    ..categoryName = categoryName,
);

/// Wraps the Platform branch (`oneOf` typeIndex 0) in the transport [Response].
/// Pass [items] = null to model a present envelope with a null `.data`.
Response<GetServiceTypes200Response> _platformResponse(
  List<PlatformServiceTypeResponse>? items,
) {
  final envelope = ApiResponseListPlatformServiceTypeResponse((b) {
    b.success = true;
    if (items != null) {
      b.data = ListBuilder<PlatformServiceTypeResponse>(items);
    }
  });
  final body = GetServiceTypes200Response(
    (b) => b
      ..oneOf =
          OneOf2<
            ApiResponseListPlatformServiceTypeResponse,
            ApiResponseListServiceTypeResponse
          >(value: envelope, typeIndex: 0),
  );
  return Response<GetServiceTypes200Response>(
    data: body,
    requestOptions: RequestOptions(path: _path),
    statusCode: 200,
  );
}

/// Wraps the LEGACY branch (`oneOf` typeIndex 1) in the transport [Response].
/// The repository must NOT map this branch — it degrades to an empty list.
Response<GetServiceTypes200Response> _legacyResponse() {
  final legacy = ApiResponseListServiceTypeResponse(
    (b) => b
      ..success = true
      ..data = ListBuilder<ServiceTypeResponse>(<ServiceTypeResponse>[
        ServiceTypeResponse(
          (t) => t
            ..id = 'legacy-1'
            ..slug = 'LEGACY_SLUG'
            ..nameUk = 'Старе'
            ..nameEn = 'Old',
        ),
      ]),
  );
  final body = GetServiceTypes200Response(
    (b) => b
      ..oneOf =
          OneOf2<
            ApiResponseListPlatformServiceTypeResponse,
            ApiResponseListServiceTypeResponse
          >(value: legacy, typeIndex: 1),
  );
  return Response<GetServiceTypes200Response>(
    data: body,
    requestOptions: RequestOptions(path: _path),
    statusCode: 200,
  );
}

DioException _dio(DioExceptionType type, {int? status}) => DioException(
  requestOptions: RequestOptions(path: _path),
  type: type,
  response: status == null
      ? null
      : Response<dynamic>(
          requestOptions: RequestOptions(path: _path),
          statusCode: status,
        ),
);

// ── Test suite ───────────────────────────────────────────────────────────────

void main() {
  late _MockServiceControllerApi serviceApi;
  late _MockCategoryRequestControllerApi categoryApi;
  late _MockServiceCatalogControllerApi catalogApi;
  late HttpServiceRepository repository;

  setUp(() {
    serviceApi = _MockServiceControllerApi();
    categoryApi = _MockCategoryRequestControllerApi();
    catalogApi = _MockServiceCatalogControllerApi();
    repository = HttpServiceRepository(
      serviceApi: serviceApi,
      categoryApi: categoryApi,
      catalogApi: catalogApi,
      masterId: _masterId,
    );
  });

  group('fetchServiceTypes — happy path (Platform branch)', () {
    test('maps the Platform-branch rows to domain options', () async {
      when(
        () => catalogApi.getServiceTypes(categoryName: _category),
      ).thenAnswer(
        (_) async => _platformResponse(<PlatformServiceTypeResponse>[
          _platformDto(id: 'type-1', slug: 'CLASSIC_LASHES', nameUk: 'Класика'),
          _platformDto(id: 'type-2', slug: 'VOLUME_LASHES', nameUk: 'Об’ємне'),
        ]),
      );

      final result = await repository.fetchServiceTypes(_category);

      expect(result.length, 2);
      expect(result.map((o) => o.slug).toList(), <String>[
        'CLASSIC_LASHES',
        'VOLUME_LASHES',
      ]);
      expect(result.first.id, 'type-1');
      expect(result.first.nameUk, 'Класика');
      expect(result.first.categoryName, _category);
    });

    test('forwards the categoryName argument to the generated API', () async {
      when(
        () => catalogApi.getServiceTypes(
          categoryName: any(named: 'categoryName'),
        ),
      ).thenAnswer((_) async => _platformResponse(const []));

      await repository.fetchServiceTypes('HAIR');

      verify(() => catalogApi.getServiceTypes(categoryName: 'HAIR')).called(1);
    });
  });

  group('fetchServiceTypes — graceful degradation to empty list', () {
    test('empty backend result → empty list', () async {
      when(
        () => catalogApi.getServiceTypes(categoryName: _category),
      ).thenAnswer((_) async => _platformResponse(const []));

      expect(await repository.fetchServiceTypes(_category), isEmpty);
    });

    test('null envelope .data → empty list', () async {
      when(
        () => catalogApi.getServiceTypes(categoryName: _category),
      ).thenAnswer((_) async => _platformResponse(null));

      expect(await repository.fetchServiceTypes(_category), isEmpty);
    });

    test('oneOf resolves to the legacy ServiceTypeResponse branch → empty list '
        '(no throw)', () async {
      // The 16.1 contract nuance: the categoryName path should resolve to the
      // Platform branch, but if the response ever lands on the legacy branch
      // the repository must degrade to [] rather than throw an unchecked cast.
      when(
        () => catalogApi.getServiceTypes(categoryName: _category),
      ).thenAnswer((_) async => _legacyResponse());

      final result = await repository.fetchServiceTypes(_category);

      expect(result, isEmpty);
    });
  });

  group('fetchServiceTypes — transport errors → typed Failures', () {
    test('connectionError → NetworkFailure', () async {
      when(
        () => catalogApi.getServiceTypes(categoryName: _category),
      ).thenThrow(_dio(DioExceptionType.connectionError));

      await expectLater(
        repository.fetchServiceTypes(_category),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('receiveTimeout → NetworkFailure', () async {
      when(
        () => catalogApi.getServiceTypes(categoryName: _category),
      ).thenThrow(_dio(DioExceptionType.receiveTimeout));

      await expectLater(
        repository.fetchServiceTypes(_category),
        throwsA(isA<NetworkFailure>()),
      );
    });

    // Phase 16.6 spinner-fix guard: a hung backend manifests as a send- or
    // connection-timeout once dio_provider added a 15 s sendTimeout. Both MUST
    // map to a typed NetworkFailure so the picker degrades to a retryable error
    // state instead of stranding the user on an infinite spinner.
    test('sendTimeout → NetworkFailure (spinner-fix guard)', () async {
      when(
        () => catalogApi.getServiceTypes(categoryName: _category),
      ).thenThrow(_dio(DioExceptionType.sendTimeout));

      await expectLater(
        repository.fetchServiceTypes(_category),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('connectionTimeout → NetworkFailure (spinner-fix guard)', () async {
      when(
        () => catalogApi.getServiceTypes(categoryName: _category),
      ).thenThrow(_dio(DioExceptionType.connectionTimeout));

      await expectLater(
        repository.fetchServiceTypes(_category),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('400 → ValidationFailure', () async {
      when(
        () => catalogApi.getServiceTypes(categoryName: _category),
      ).thenThrow(_dio(DioExceptionType.badResponse, status: 400));

      await expectLater(
        repository.fetchServiceTypes(_category),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('422 → ValidationFailure', () async {
      when(
        () => catalogApi.getServiceTypes(categoryName: _category),
      ).thenThrow(_dio(DioExceptionType.badResponse, status: 422));

      await expectLater(
        repository.fetchServiceTypes(_category),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });
}
