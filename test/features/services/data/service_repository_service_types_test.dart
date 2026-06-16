// Phase 16.x — Unit tests for [HttpServiceRepository.fetchServiceTypes].
//
// Strategy:
//   Mocks [ServiceCatalogControllerApi] with mocktail and constructs
//   [HttpServiceRepository] directly (pure Dart, no Riverpod overhead), mirroring
//   service_repository_test.dart.
//
// Contract (post-regen): `GET /api/v1/service-types?categoryName=...` is a
// SINGLE-shape 200 response — `ApiResponseListPlatformServiceTypeResponse`.
// The ambiguous 2-branch `oneOf` (`GetServiceTypes200Response`) was DELETED
// backend-side (the legacy operation is @Hidden), so the client now returns the
// Platform envelope directly via `getServiceTypesByPlatformCategory`.
//
//   ⚠ Regression context: the OLD oneOf had two branches that BOTH matched the
//   real payload `{id,slug,nameUk,categoryName}`. The `one_of` deserializer
//   threw `UnsupportedError("more than one match found")` at runtime → the
//   picker rendered EMPTY. The old tests never caught it because they built the
//   `OneOf` value directly in Dart and never drove raw JSON through the
//   deserializer. The companion contract test
//   (api/test/contract/service_types_contract_test.dart) now drives the real
//   serializer path to lock the single-shape contract.
//
// Coverage:
//   1. Platform rows  → mapped List<ServiceTypeOption> (data binding asserted).
//   2. Empty list     → empty list.
//   3. null .data     → empty list.
//   4. forwards categoryName to the generated API.
//   5. connection / timeout errors → NetworkFailure.
//   6. 400 / 422                   → ValidationFailure.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

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

/// Wraps the Platform rows in the single-shape transport [Response].
/// Pass [items] = null to model a present envelope with a null `.data`.
Response<ApiResponseListPlatformServiceTypeResponse> _platformResponse(
  List<PlatformServiceTypeResponse>? items,
) {
  final envelope = ApiResponseListPlatformServiceTypeResponse((b) {
    b.success = true;
    if (items != null) {
      b.data = ListBuilder<PlatformServiceTypeResponse>(items);
    }
  });
  return Response<ApiResponseListPlatformServiceTypeResponse>(
    data: envelope,
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
      dio: Dio(),
      masterId: _masterId,
    );
  });

  group('fetchServiceTypes — happy path (single Platform shape)', () {
    test('maps the Platform rows to domain options', () async {
      when(
        () => catalogApi.getServiceTypesByPlatformCategory(
          categoryName: _category,
        ),
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
        () => catalogApi.getServiceTypesByPlatformCategory(
          categoryName: any(named: 'categoryName'),
        ),
      ).thenAnswer((_) async => _platformResponse(const []));

      await repository.fetchServiceTypes('HAIR');

      verify(
        () =>
            catalogApi.getServiceTypesByPlatformCategory(categoryName: 'HAIR'),
      ).called(1);
    });
  });

  group('fetchServiceTypes — graceful degradation to empty list', () {
    test('empty backend result → empty list', () async {
      when(
        () => catalogApi.getServiceTypesByPlatformCategory(
          categoryName: _category,
        ),
      ).thenAnswer((_) async => _platformResponse(const []));

      expect(await repository.fetchServiceTypes(_category), isEmpty);
    });

    test('null envelope .data → empty list', () async {
      when(
        () => catalogApi.getServiceTypesByPlatformCategory(
          categoryName: _category,
        ),
      ).thenAnswer((_) async => _platformResponse(null));

      expect(await repository.fetchServiceTypes(_category), isEmpty);
    });
  });

  group('fetchServiceTypes — transport errors → typed Failures', () {
    test('connectionError → NetworkFailure', () async {
      when(
        () => catalogApi.getServiceTypesByPlatformCategory(
          categoryName: _category,
        ),
      ).thenThrow(_dio(DioExceptionType.connectionError));

      await expectLater(
        repository.fetchServiceTypes(_category),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('receiveTimeout → NetworkFailure', () async {
      when(
        () => catalogApi.getServiceTypesByPlatformCategory(
          categoryName: _category,
        ),
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
        () => catalogApi.getServiceTypesByPlatformCategory(
          categoryName: _category,
        ),
      ).thenThrow(_dio(DioExceptionType.sendTimeout));

      await expectLater(
        repository.fetchServiceTypes(_category),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('connectionTimeout → NetworkFailure (spinner-fix guard)', () async {
      when(
        () => catalogApi.getServiceTypesByPlatformCategory(
          categoryName: _category,
        ),
      ).thenThrow(_dio(DioExceptionType.connectionTimeout));

      await expectLater(
        repository.fetchServiceTypes(_category),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('400 → ValidationFailure', () async {
      when(
        () => catalogApi.getServiceTypesByPlatformCategory(
          categoryName: _category,
        ),
      ).thenThrow(_dio(DioExceptionType.badResponse, status: 400));

      await expectLater(
        repository.fetchServiceTypes(_category),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('422 → ValidationFailure', () async {
      when(
        () => catalogApi.getServiceTypesByPlatformCategory(
          categoryName: _category,
        ),
      ).thenThrow(_dio(DioExceptionType.badResponse, status: 422));

      await expectLater(
        repository.fetchServiceTypes(_category),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });

  // ── Regression: real deserialization resolves to exactly ONE shape ──────────
  //
  // This is the test that, under the OLD ambiguous oneOf model, would have
  // failed with `UnsupportedError("more than one match found")`. We drive an
  // actual JSON envelope through the generated serializers exactly as Dio's
  // generated client does (standardSerializers.deserialize into the now-single
  // ApiResponseListPlatformServiceTypeResponse), then feed the resulting model
  // through the repository and assert a non-empty typed list — proving no throw
  // and correct binding end-to-end.
  group(
    'fetchServiceTypes — regression: single-shape JSON resolves cleanly',
    () {
      final json = <String, Object?>{
        'success': true,
        'data': <Object?>[
          <String, Object?>{
            'id': 'st-1',
            'slug': 'CLASSIC_LASHES',
            'nameUk': 'Класичне нарощування',
            'categoryName': _category,
          },
          <String, Object?>{
            'id': 'st-2',
            'slug': 'VOLUME_LASHES',
            'nameUk': 'Об’ємне нарощування',
            'categoryName': _category,
          },
        ],
        'message': null,
        'errors': null,
      };

      test('deserializes the Platform envelope without UnsupportedError', () {
        // Under the deleted 2-branch oneOf, both branches matched this payload
        // and `one_of` threw "more than one match found". The single-shape model
        // resolves it to exactly one typed envelope.
        final envelope =
            standardSerializers.deserialize(
                  json,
                  specifiedType: const FullType(
                    ApiResponseListPlatformServiceTypeResponse,
                  ),
                )
                as ApiResponseListPlatformServiceTypeResponse;

        expect(envelope.success, isTrue);
        expect(envelope.data, isNotNull);
        expect(envelope.data!.length, 2);
        expect(envelope.data!.first.slug, 'CLASSIC_LASHES');
        expect(envelope.data!.first.categoryName, _category);
      });

      test('repository maps the deserialized envelope to a non-empty '
          'List<ServiceTypeOption>', () async {
        final envelope =
            standardSerializers.deserialize(
                  json,
                  specifiedType: const FullType(
                    ApiResponseListPlatformServiceTypeResponse,
                  ),
                )
                as ApiResponseListPlatformServiceTypeResponse;

        when(
          () => catalogApi.getServiceTypesByPlatformCategory(
            categoryName: _category,
          ),
        ).thenAnswer(
          (_) async => Response<ApiResponseListPlatformServiceTypeResponse>(
            data: envelope,
            requestOptions: RequestOptions(path: _path),
            statusCode: 200,
          ),
        );

        final result = await repository.fetchServiceTypes(_category);

        expect(result.length, 2);
        expect(result.map((o) => o.slug).toList(), <String>[
          'CLASSIC_LASHES',
          'VOLUME_LASHES',
        ]);
        expect(result.first.nameUk, 'Класичне нарощування');
      });
    },
  );
}
