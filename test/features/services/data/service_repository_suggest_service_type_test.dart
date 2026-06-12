// Phase 16.6 — Unit tests for [HttpServiceRepository.suggestServiceType].
//
// Strategy mirrors service_repository_service_types_test.dart: mocks
// [ServiceCatalogControllerApi] with mocktail and constructs
// [HttpServiceRepository] directly (pure Dart, no Riverpod). The repository
// forwards a [SuggestServiceTypeRequest] to `POST /service-types/suggest` and
// maps the Dio failure surface onto typed [Failure]s.
//
// The single most important guard (M4 — strict argument matching) is the WIRE
// SHAPE: the request `categoryName` MUST be the System-B SLUG the caller passes
// (e.g. 'EYELASH'), NEVER a categoryId UUID. A regression that sent the UUID
// would silently 4xx on the backend and is exactly what these capture-and-assert
// tests lock down.
//
// Coverage:
//   WIRE-1. forwards name + categoryName SLUG + description on the request body.
//   WIRE-2. null description → request.description omitted (null on the wire).
//   WIRE-3. empty / whitespace description → request.description null (omitted).
//   MAP-400. 400 → ValidationFailure.
//   MAP-422. 422 → ValidationFailure.
//   MAP-400-FIELDS. interceptor-attached ValidationFailure (fieldErrors) is
//                   preferred so inline name messages survive.
//   MAP-429. 429 → CategoryRequestThrottledFailure (throttle copy reused).
//   MAP-5xx. 500 → ServerFailure (generic server error).
//   MAP-NET. connection / timeout errors → NetworkFailure.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────

class _MockServiceControllerApi extends Mock implements ServiceControllerApi {}

class _MockCategoryRequestControllerApi extends Mock
    implements CategoryRequestControllerApi {}

class _MockServiceCatalogControllerApi extends Mock
    implements ServiceCatalogControllerApi {}

class _FakeSuggestServiceTypeRequest extends Fake
    implements SuggestServiceTypeRequest {}

// ── Helpers ─────────────────────────────────────────────────────────────────

const _masterId = 'master-abc';
const _categorySlug = 'EYELASH';
const _path = '/api/v1/service-types/suggest';

/// A 200 envelope response — the success path for suggestServiceType.
Response<ApiResponseVoid> _ok() => Response<ApiResponseVoid>(
  data: ApiResponseVoid((b) => b..success = true),
  requestOptions: RequestOptions(path: _path),
  statusCode: 200,
);

DioException _dio(DioExceptionType type, {int? status, Object? attached}) =>
    DioException(
      requestOptions: RequestOptions(path: _path),
      type: type,
      error: attached,
      response: status == null
          ? null
          : Response<dynamic>(
              requestOptions: RequestOptions(path: _path),
              statusCode: status,
            ),
    );

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeSuggestServiceTypeRequest());
  });

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

  /// Captures the [SuggestServiceTypeRequest] handed to the generated API after
  /// the repository ran, so the wire shape can be asserted (M4).
  SuggestServiceTypeRequest capturedRequest() =>
      verify(
            () => catalogApi.suggestServiceType(
              suggestServiceTypeRequest: captureAny(
                named: 'suggestServiceTypeRequest',
              ),
            ),
          ).captured.single
          as SuggestServiceTypeRequest;

  group('suggestServiceType — wire shape (M4: slug, never a UUID)', () {
    test(
      'forwards name + categoryName SLUG + description on the body',
      () async {
        when(
          () => catalogApi.suggestServiceType(
            suggestServiceTypeRequest: any(named: 'suggestServiceTypeRequest'),
          ),
        ).thenAnswer((_) async => _ok());

        await repository.suggestServiceType(
          categoryName: _categorySlug,
          name: 'Ламінування вій',
          description: 'Опис для перевірки',
        );

        final req = capturedRequest();
        expect(req.name, 'Ламінування вій');
        // The category context is the System-B SLUG, NOT a categoryId UUID.
        expect(req.categoryName, _categorySlug);
        expect(
          req.categoryName,
          isNot(matches(RegExp(r'^[0-9a-fA-F-]{36}$'))),
          reason: 'categoryName must be a slug, never a UUID',
        );
        expect(req.description, 'Опис для перевірки');
      },
    );

    test('null description → request.description is null (omitted)', () async {
      when(
        () => catalogApi.suggestServiceType(
          suggestServiceTypeRequest: any(named: 'suggestServiceTypeRequest'),
        ),
      ).thenAnswer((_) async => _ok());

      await repository.suggestServiceType(
        categoryName: _categorySlug,
        name: 'Ламінування вій',
        description: null,
      );

      expect(capturedRequest().description, isNull);
    });

    test(
      'empty / whitespace description → request.description is null (omitted)',
      () async {
        when(
          () => catalogApi.suggestServiceType(
            suggestServiceTypeRequest: any(named: 'suggestServiceTypeRequest'),
          ),
        ).thenAnswer((_) async => _ok());

        await repository.suggestServiceType(
          categoryName: _categorySlug,
          name: 'Ламінування вій',
          description: '   ',
        );

        expect(
          capturedRequest().description,
          isNull,
          reason: 'a blank description must not be sent as an empty string',
        );
      },
    );
  });

  group('suggestServiceType — failure mapping → typed Failures', () {
    test('400 → ValidationFailure', () async {
      when(
        () => catalogApi.suggestServiceType(
          suggestServiceTypeRequest: any(named: 'suggestServiceTypeRequest'),
        ),
      ).thenThrow(_dio(DioExceptionType.badResponse, status: 400));

      await expectLater(
        repository.suggestServiceType(categoryName: _categorySlug, name: 'Bad'),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('422 → ValidationFailure', () async {
      when(
        () => catalogApi.suggestServiceType(
          suggestServiceTypeRequest: any(named: 'suggestServiceTypeRequest'),
        ),
      ).thenThrow(_dio(DioExceptionType.badResponse, status: 422));

      await expectLater(
        repository.suggestServiceType(categoryName: _categorySlug, name: 'Bad'),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test(
      'an interceptor-attached ValidationFailure(fieldErrors) is preferred so '
      'inline name messages survive',
      () async {
        const attached = ValidationFailure(
          fieldErrors: <String, String>{'name': 'Назва вже існує'},
        );
        when(
          () => catalogApi.suggestServiceType(
            suggestServiceTypeRequest: any(named: 'suggestServiceTypeRequest'),
          ),
        ).thenThrow(
          _dio(DioExceptionType.badResponse, status: 400, attached: attached),
        );

        await expectLater(
          repository.suggestServiceType(
            categoryName: _categorySlug,
            name: 'Dup',
          ),
          throwsA(
            isA<ValidationFailure>().having(
              (f) => f.fieldErrors['name'],
              'fieldErrors[name]',
              'Назва вже існує',
            ),
          ),
        );
      },
    );

    test(
      '429 → CategoryRequestThrottledFailure (throttle copy reused)',
      () async {
        when(
          () => catalogApi.suggestServiceType(
            suggestServiceTypeRequest: any(named: 'suggestServiceTypeRequest'),
          ),
        ).thenThrow(_dio(DioExceptionType.badResponse, status: 429));

        await expectLater(
          repository.suggestServiceType(
            categoryName: _categorySlug,
            name: 'Throttled',
          ),
          throwsA(isA<CategoryRequestThrottledFailure>()),
        );
      },
    );

    test('500 → ServerFailure', () async {
      when(
        () => catalogApi.suggestServiceType(
          suggestServiceTypeRequest: any(named: 'suggestServiceTypeRequest'),
        ),
      ).thenThrow(_dio(DioExceptionType.badResponse, status: 500));

      await expectLater(
        repository.suggestServiceType(
          categoryName: _categorySlug,
          name: 'Boom',
        ),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('connectionError → NetworkFailure', () async {
      when(
        () => catalogApi.suggestServiceType(
          suggestServiceTypeRequest: any(named: 'suggestServiceTypeRequest'),
        ),
      ).thenThrow(_dio(DioExceptionType.connectionError));

      await expectLater(
        repository.suggestServiceType(
          categoryName: _categorySlug,
          name: 'Offline',
        ),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('receiveTimeout → NetworkFailure', () async {
      when(
        () => catalogApi.suggestServiceType(
          suggestServiceTypeRequest: any(named: 'suggestServiceTypeRequest'),
        ),
      ).thenThrow(_dio(DioExceptionType.receiveTimeout));

      await expectLater(
        repository.suggestServiceType(
          categoryName: _categorySlug,
          name: 'Slow',
        ),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });
}
