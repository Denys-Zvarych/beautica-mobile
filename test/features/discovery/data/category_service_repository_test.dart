// Phase 13.x (Variant A «Рейка + послуги») — unit tests for
// [HttpCategoryServiceRepository] + its PlatformServiceTypeResponse → Category
// ServiceOption mapping.
//
// Strategy (mirrors search_repository_test.dart): mock the generated
// [ServiceCatalogControllerApi] with mocktail and construct
// [HttpCategoryServiceRepository] directly (pure Dart units, no Riverpod).
//
// Coverage:
//   1. happy path — list mapped to CategoryServiceOption (key=slug,
//      displayName=nameUk), backend order preserved
//   2. malformed-row drop — rows with empty/blank slug OR nameUk are dropped
//   3. null `.data` (ApiResponse.data == null) → empty list (no crash)
//   4. empty `.data` list → empty list
//   5. DioError mapping — connection/timeout → NetworkFailure; 400/422 →
//      ValidationFailure; 404 → NotFoundFailure; 5xx + cancel/badCert/unknown
//      → ServerFailure
//   6. an interceptor-attached Failure is rethrown verbatim (preferred over
//      type/status mapping)

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/discovery/data/category_service_repository.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────

class _MockServiceCatalogControllerApi extends Mock
    implements ServiceCatalogControllerApi {}

// ── Helpers ──────────────────────────────────────────────────────────────────

const _path = '/api/v1/service-types';

PlatformServiceTypeResponse _typeDto({
  String? id = 'type-1',
  String? slug = 'CLASSIC_MANICURE',
  String? nameUk = 'Класичний манікюр',
  String? categoryName = 'NAILS',
}) =>
    (PlatformServiceTypeResponseBuilder()
          ..id = id
          ..slug = slug
          ..nameUk = nameUk
          ..categoryName = categoryName)
        .build();

/// Builds a 200 [Response] carrying [items] (or a null `.data` list when
/// [items] is null) in the ApiResponseListPlatformServiceTypeResponse envelope.
Response<ApiResponseListPlatformServiceTypeResponse> _okResponse(
  List<PlatformServiceTypeResponse>? items,
) {
  final body = ApiResponseListPlatformServiceTypeResponse((b) {
    b.success = true;
    if (items != null) {
      b.data = ListBuilder<PlatformServiceTypeResponse>(items);
    }
  });
  return Response<ApiResponseListPlatformServiceTypeResponse>(
    data: body,
    requestOptions: RequestOptions(path: _path),
    statusCode: 200,
  );
}

DioException _dioBadResponse(int statusCode) => DioException(
  requestOptions: RequestOptions(path: _path),
  response: Response<Object?>(
    requestOptions: RequestOptions(path: _path),
    statusCode: statusCode,
  ),
  type: DioExceptionType.badResponse,
);

DioException _dioType(DioExceptionType type, {Object? error}) => DioException(
  requestOptions: RequestOptions(path: _path),
  type: type,
  error: error,
);

// ── Test suite ───────────────────────────────────────────────────────────────

void main() {
  late _MockServiceCatalogControllerApi api;
  late HttpCategoryServiceRepository repository;

  setUp(() {
    api = _MockServiceCatalogControllerApi();
    repository = HttpCategoryServiceRepository(api);
  });

  void stubReturn(List<PlatformServiceTypeResponse>? items) {
    when(
      () => api.getServiceTypesByPlatformCategory(
        categoryName: any(named: 'categoryName'),
      ),
    ).thenAnswer((_) async => _okResponse(items));
  }

  void stubThrow(Object error) {
    when(
      () => api.getServiceTypesByPlatformCategory(
        categoryName: any(named: 'categoryName'),
      ),
    ).thenThrow(error);
  }

  group('fetchServices — mapping', () {
    test('maps each PlatformServiceTypeResponse to a CategoryServiceOption '
        '(key=slug, displayName=nameUk), preserving backend order', () async {
      stubReturn(<PlatformServiceTypeResponse>[
        _typeDto(slug: 'CLASSIC_MANICURE', nameUk: 'Класичний манікюр'),
        _typeDto(slug: 'GEL_MANICURE', nameUk: 'Гель-лак'),
      ]);

      final result = await repository.fetchServices('NAILS');

      expect(result, hasLength(2));
      expect(result[0].key, 'CLASSIC_MANICURE');
      expect(result[0].displayName, 'Класичний манікюр');
      expect(result[1].key, 'GEL_MANICURE');
      expect(result[1].displayName, 'Гель-лак');
    });

    test('forwards the category slug to the API', () async {
      stubReturn(<PlatformServiceTypeResponse>[_typeDto()]);

      await repository.fetchServices('HAIR');

      verify(
        () => api.getServiceTypesByPlatformCategory(categoryName: 'HAIR'),
      ).called(1);
    });

    test('drops rows with a blank slug or blank nameUk (defensive)', () async {
      stubReturn(<PlatformServiceTypeResponse>[
        _typeDto(slug: 'OK', nameUk: 'Гарна назва'),
        _typeDto(slug: '', nameUk: 'Має slug?'), // empty slug → dropped
        _typeDto(slug: 'NO_LABEL', nameUk: ''), // empty label → dropped
        _typeDto(slug: null, nameUk: 'Null slug'), // null slug → dropped
        _typeDto(slug: 'NO_NAME', nameUk: null), // null label → dropped
      ]);

      final result = await repository.fetchServices('NAILS');

      expect(result, hasLength(1));
      expect(result.single.key, 'OK');
      expect(result.single.displayName, 'Гарна назва');
    });

    test('returns an empty list when the envelope `.data` is null '
        '(no crash)', () async {
      stubReturn(null);

      final result = await repository.fetchServices('NAILS');

      expect(result, isEmpty);
    });

    test('returns an empty list when the backend list is empty', () async {
      stubReturn(const <PlatformServiceTypeResponse>[]);

      final result = await repository.fetchServices('NAILS');

      expect(result, isEmpty);
    });
  });

  group('fetchServices — DioException mapping', () {
    test('connection error → NetworkFailure', () async {
      stubThrow(_dioType(DioExceptionType.connectionError));
      expect(
        () => repository.fetchServices('NAILS'),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('connection timeout → NetworkFailure', () async {
      stubThrow(_dioType(DioExceptionType.connectionTimeout));
      expect(
        () => repository.fetchServices('NAILS'),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('receive timeout → NetworkFailure', () async {
      stubThrow(_dioType(DioExceptionType.receiveTimeout));
      expect(
        () => repository.fetchServices('NAILS'),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('send timeout → NetworkFailure', () async {
      stubThrow(_dioType(DioExceptionType.sendTimeout));
      expect(
        () => repository.fetchServices('NAILS'),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('400 → ValidationFailure', () async {
      stubThrow(_dioBadResponse(400));
      expect(
        () => repository.fetchServices('NAILS'),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('422 → ValidationFailure', () async {
      stubThrow(_dioBadResponse(422));
      expect(
        () => repository.fetchServices('NAILS'),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('404 → NotFoundFailure', () async {
      stubThrow(_dioBadResponse(404));
      expect(
        () => repository.fetchServices('NAILS'),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test('500 → ServerFailure (carrying the status code)', () async {
      stubThrow(_dioBadResponse(500));
      await expectLater(
        repository.fetchServices('NAILS'),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('cancel → ServerFailure', () async {
      stubThrow(_dioType(DioExceptionType.cancel));
      expect(
        () => repository.fetchServices('NAILS'),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('badCertificate → ServerFailure', () async {
      stubThrow(_dioType(DioExceptionType.badCertificate));
      expect(
        () => repository.fetchServices('NAILS'),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('unknown → ServerFailure', () async {
      stubThrow(_dioType(DioExceptionType.unknown));
      expect(
        () => repository.fetchServices('NAILS'),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('an interceptor-attached Failure is rethrown verbatim (preferred '
        'over status/type mapping)', () async {
      // A 400 (would normally map to ValidationFailure) but carrying a
      // pre-mapped NetworkFailure on `.error` must surface as that Failure.
      stubThrow(
        DioException(
          requestOptions: RequestOptions(path: _path),
          response: Response<Object?>(
            requestOptions: RequestOptions(path: _path),
            statusCode: 400,
          ),
          type: DioExceptionType.badResponse,
          error: const NetworkFailure(),
        ),
      );

      expect(
        () => repository.fetchServices('NAILS'),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });
}
