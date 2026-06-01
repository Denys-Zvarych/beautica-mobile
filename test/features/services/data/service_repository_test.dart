// Phase 5.1 — Unit tests for [HttpServiceRepository].
//
// Strategy:
//   All tests mock [ServiceControllerApi] and/or [Dio] with mocktail.
//   [HttpServiceRepository] is constructed directly so there is no Riverpod
//   overhead — pure Dart unit tests.
//
// Coverage:
//   1.  listMyServices() — empty list
//   2.  listMyServices() — populated list; mapper applied (name, price, duration)
//   3.  create()         — happy path; correct request fields forwarded
//   4.  create()         — price: -1 → ArgumentError (local validation; no network call)
//   5.  deactivate()     — correct API method called; idempotent (2× → no throw)
//   6.  update()         — happy path; PATCH issued, domain object returned (no second GET)
//   7.  empty masterId   — listMyServices() throws UnauthorizedFailure without network call

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────

class _MockServiceControllerApi extends Mock implements ServiceControllerApi {}

class _MockCategoryRequestControllerApi extends Mock
    implements CategoryRequestControllerApi {}

class _MockDio extends Mock implements Dio {}

// ── Helpers ─────────────────────────────────────────────────────────────────

const _masterId = 'master-abc';
const _serviceId = 'svc-001';
const _listPath = '/api/v1/masters/$_masterId/services';

/// Builds a [ServiceDefinitionResponse] with sensible defaults.
ServiceDefinitionResponse _buildDef({
  String id = 'def-001',
  String name = 'Манікюр',
  String? description,
  int baseDurationMinutes = 60,
  num basePrice = 500,
  int? bufferMinutesAfter,
  bool isActive = true,
}) =>
    (ServiceDefinitionResponseBuilder()
          ..id = id
          ..name = name
          ..description = description
          ..baseDurationMinutes = baseDurationMinutes
          ..basePrice = basePrice
          ..bufferMinutesAfter = bufferMinutesAfter
          ..isActive = isActive)
        .build();

/// Builds a [MasterServiceResponse] with sensible defaults.
MasterServiceResponse _buildMasterServiceDto({
  String id = _serviceId,
  String masterId = _masterId,
  ServiceDefinitionResponse? serviceDefinition,
  num? effectivePrice,
  int? effectiveDurationMinutes,
  bool isActive = true,
}) {
  final def = serviceDefinition ?? _buildDef();
  return (MasterServiceResponseBuilder()
        ..id = id
        ..masterId = masterId
        ..serviceDefinition.replace(def)
        ..effectivePrice = effectivePrice
        ..effectiveDurationMinutes = effectiveDurationMinutes
        ..isActive = isActive)
      .build();
}

/// Wraps a list of [MasterServiceResponse] DTOs in the API envelope.
Response<ApiResponseListMasterServiceResponse> _listResponse(
  List<MasterServiceResponse> items,
) {
  final envelope = ApiResponseListMasterServiceResponse(
    (b) => b
      ..data = ListBuilder<MasterServiceResponse>(items)
      ..success = true,
  );
  return Response<ApiResponseListMasterServiceResponse>(
    data: envelope,
    requestOptions: RequestOptions(path: _listPath),
    statusCode: 200,
  );
}

/// Wraps a single [MasterServiceResponse] DTO in the API envelope.
Response<ApiResponseMasterServiceResponse> _singleResponse(
  MasterServiceResponse dto,
) {
  final envelope = ApiResponseMasterServiceResponse(
    (b) => b
      ..data.replace(dto)
      ..success = true,
  );
  return Response<ApiResponseMasterServiceResponse>(
    data: envelope,
    requestOptions: RequestOptions(
      path: '/api/v1/independent-masters/me/services',
    ),
    statusCode: 201,
  );
}

// ── Test suite ───────────────────────────────────────────────────────────────

void main() {
  late _MockServiceControllerApi serviceApi;
  late _MockCategoryRequestControllerApi categoryApi;
  late _MockDio dio;
  late HttpServiceRepository repository;

  setUp(() {
    serviceApi = _MockServiceControllerApi();
    categoryApi = _MockCategoryRequestControllerApi();
    dio = _MockDio();
    repository = HttpServiceRepository(
      serviceApi: serviceApi,
      categoryApi: categoryApi,
      dio: dio,
      masterId: _masterId,
    );
    // Register fallback values required by mocktail for named-typed matchers.
    registerFallbackValue(
      CreateServiceDefinitionRequest(
        (b) => b
          ..name = 'fallback'
          ..baseDurationMinutes = 30
          ..basePrice = 100
          ..category = 'FALLBACK',
      ),
    );
    registerFallbackValue(
      CreateCategoryRequestRequest(
        (b) => b
          ..name = 'FALLBACK'
          ..displayName = 'fallback',
      ),
    );
  });

  // ── 1. listMyServices — empty list ──────────────────────────────────────────

  group('listMyServices', () {
    test(
      'returns empty list when the backend returns an empty array',
      () async {
        when(
          () => serviceApi.getMasterServices(masterId: _masterId),
        ).thenAnswer((_) async => _listResponse([]));

        final result = await repository.listMyServices();

        expect(result, isEmpty);
      },
    );

    // ── 2. listMyServices — populated list, mapper applied ───────────────────

    test('returns mapped domain objects for a populated list', () async {
      final dto1 = _buildMasterServiceDto(
        id: 'svc-001',
        serviceDefinition: _buildDef(
          name: 'Манікюр',
          baseDurationMinutes: 60,
          basePrice: 500,
        ),
        isActive: true,
      );
      final dto2 = _buildMasterServiceDto(
        id: 'svc-002',
        serviceDefinition: _buildDef(
          id: 'def-002',
          name: 'Педикюр',
          baseDurationMinutes: 90,
          basePrice: 700,
        ),
        // effectivePrice overrides basePrice for dto2
        effectivePrice: 650,
        isActive: true,
      );

      when(
        () => serviceApi.getMasterServices(masterId: _masterId),
      ).thenAnswer((_) async => _listResponse([dto1, dto2]));

      final result = await repository.listMyServices();

      expect(result.length, 2);

      // First item — base price/duration used (no overrides)
      final first = result.first;
      expect(first.id, 'svc-001');
      expect(first.name, 'Манікюр');
      expect(first.durationMinutes, 60);
      expect(first.price, 500.0);
      expect(first.isActive, isTrue);

      // Second item — effectivePrice override applies
      final second = result[1];
      expect(second.id, 'svc-002');
      expect(second.name, 'Педикюр');
      expect(second.durationMinutes, 90);
      expect(
        second.price,
        650.0,
        reason: 'effectivePrice override must take precedence over basePrice',
      );
      expect(second.isActive, isTrue);
    });

    test('maps NetworkFailure on connectionError', () async {
      when(() => serviceApi.getMasterServices(masterId: _masterId)).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _listPath),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        repository.listMyServices(),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });

  // ── 3. create — happy path ─────────────────────────────────────────────────

  group('create', () {
    test('calls addIndependentMasterService with correct fields', () async {
      final dto = _buildMasterServiceDto(
        id: 'svc-new',
        serviceDefinition: _buildDef(
          name: 'Брови',
          baseDurationMinutes: 45,
          basePrice: 350,
        ),
      );

      when(
        () => serviceApi.addIndependentMasterService(
          createServiceDefinitionRequest: any(
            named: 'createServiceDefinitionRequest',
          ),
        ),
      ).thenAnswer((_) async => _singleResponse(dto));

      const input = MasterServiceCreate(
        name: 'Брови',
        durationMinutes: 45,
        price: 350.0,
        description: 'Оформлення брів',
        category: 'BROWS',
      );

      final result = await repository.create(input);

      expect(result.id, 'svc-new');
      expect(result.name, 'Брови');
      expect(result.price, 350.0);

      // Verify the generated request carried the correct fields.
      final captured =
          verify(
                () => serviceApi.addIndependentMasterService(
                  createServiceDefinitionRequest: captureAny(
                    named: 'createServiceDefinitionRequest',
                  ),
                ),
              ).captured.single
              as CreateServiceDefinitionRequest;

      expect(captured.name, 'Брови');
      expect(captured.baseDurationMinutes, 45);
      expect(captured.basePrice, 350.0);
      expect(captured.description, 'Оформлення брів');
      // category is now required and forwarded as a plain wire String.
      expect(captured.category, 'BROWS');
    });

    // ── 4. create — invalid input → ArgumentError (local; no network call) ───

    test(
      'throws ArgumentError for negative price before any network call',
      () async {
        // No mock set up for serviceApi — if the network call were made the
        // test would fail with a "no stub found" error from mocktail, which
        // proves the validation fires locally.
        await expectLater(
          repository.create(
            const MasterServiceCreate(
              name: 'Invalid',
              durationMinutes: 30,
              price: -1,
            ),
          ),
          throwsA(isA<ArgumentError>()),
        );

        // Confirm no API call was made.
        verifyNever(
          () => serviceApi.addIndependentMasterService(
            createServiceDefinitionRequest: any(
              named: 'createServiceDefinitionRequest',
            ),
          ),
        );
      },
    );

    test(
      'throws ArgumentError for zero durationMinutes before any network call',
      () async {
        await expectLater(
          repository.create(
            const MasterServiceCreate(
              name: 'Invalid',
              durationMinutes: 0,
              price: 100,
            ),
          ),
          throwsA(isA<ArgumentError>()),
        );

        verifyNever(
          () => serviceApi.addIndependentMasterService(
            createServiceDefinitionRequest: any(
              named: 'createServiceDefinitionRequest',
            ),
          ),
        );
      },
    );

    test('re-throws pre-mapped Failure unchanged', () async {
      const mapped = NetworkFailure();
      when(
        () => serviceApi.addIndependentMasterService(
          createServiceDefinitionRequest: any(
            named: 'createServiceDefinitionRequest',
          ),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(
            path: '/api/v1/independent-masters/me/services',
          ),
          type: DioExceptionType.unknown,
          error: mapped,
        ),
      );

      await expectLater(
        repository.create(
          const MasterServiceCreate(
            name: 'Test',
            durationMinutes: 30,
            price: 100,
            category: 'MANICURE',
          ),
        ),
        throwsA(same(mapped)),
      );
    });
  });

  // ── 5. deactivate — correct method called; idempotent ──────────────────────

  group('deactivate', () {
    test(
      'calls deactivateServiceDefinition with the correct serviceDefId',
      () async {
        when(
          () =>
              serviceApi.deactivateServiceDefinition(serviceDefId: _serviceId),
        ).thenAnswer(
          (_) async => Response<void>(
            requestOptions: RequestOptions(
              path: '/api/v1/services/$_serviceId',
            ),
            statusCode: 200,
          ),
        );

        await repository.deactivate(_serviceId);

        verify(
          () =>
              serviceApi.deactivateServiceDefinition(serviceDefId: _serviceId),
        ).called(1);
      },
    );

    test(
      'calling deactivate twice does not throw (idempotent server 200)',
      () async {
        when(
          () =>
              serviceApi.deactivateServiceDefinition(serviceDefId: _serviceId),
        ).thenAnswer(
          (_) async => Response<void>(
            requestOptions: RequestOptions(
              path: '/api/v1/services/$_serviceId',
            ),
            statusCode: 200,
          ),
        );

        await repository.deactivate(_serviceId);
        await repository.deactivate(_serviceId); // must not throw

        verify(
          () =>
              serviceApi.deactivateServiceDefinition(serviceDefId: _serviceId),
        ).called(2);
      },
    );

    test('throws NetworkFailure when connectionError', () async {
      when(
        () => serviceApi.deactivateServiceDefinition(serviceDefId: _serviceId),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/v1/services/$_serviceId'),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        repository.deactivate(_serviceId),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });

  // ── 6. update — happy path; no second GET ──────────────────────────────────

  group('update', () {
    test(
      'issues PATCH and returns domain object without a second GET (fix P1-1)',
      () async {
        // Build the DTO that the PATCH response returns in its `data` field.
        final updatedDto = _buildMasterServiceDto(
          id: _serviceId,
          serviceDefinition: _buildDef(
            name: 'Манікюр Оновлений',
            baseDurationMinutes: 75,
            basePrice: 600,
          ),
          isActive: true,
        );

        // The PATCH response envelope — `data` holds the serialised DTO as a
        // plain Map (StandardJsonPlugin). We can't serialise via built_value in
        // tests trivially, so we build the map manually mirroring the wire shape
        // the repository expects from `res.data?['data']`.
        final patchResponseData = <String, dynamic>{
          'id': updatedDto.id,
          'masterId': updatedDto.masterId,
          'isActive': updatedDto.isActive,
          'effectivePrice': 600,
          'effectiveDurationMinutes': 75,
          'serviceDefinition': <String, dynamic>{
            'id': 'def-001',
            'name': 'Манікюр Оновлений',
            'baseDurationMinutes': 75,
            'basePrice': 600,
            'isActive': true,
          },
        };

        when(
          () => dio.patch<Map<String, dynamic>>(
            '/api/v1/independent-masters/me/services/$_serviceId',
            data: any(named: 'data'),
          ),
        ).thenAnswer(
          (_) async => Response<Map<String, dynamic>>(
            data: {'success': true, 'data': patchResponseData},
            requestOptions: RequestOptions(
              path: '/api/v1/independent-masters/me/services/$_serviceId',
            ),
            statusCode: 200,
          ),
        );

        const patch = MasterServiceUpdate(
          name: 'Манікюр Оновлений',
          durationMinutes: 75,
          price: 600.0,
        );

        final result = await repository.update(_serviceId, patch);

        expect(result.id, _serviceId);
        expect(result.name, 'Манікюр Оновлений');
        expect(result.durationMinutes, 75);
        expect(result.price, 600.0);

        // The list endpoint must NOT have been called (no second round-trip).
        verifyNever(
          () => serviceApi.getMasterServices(masterId: any(named: 'masterId')),
        );
      },
    );

    test(
      'throws ArgumentError for negative price in update before network call',
      () async {
        await expectLater(
          repository.update(
            _serviceId,
            const MasterServiceUpdate(price: -50.0),
          ),
          throwsA(isA<ArgumentError>()),
        );

        verifyNever(
          () =>
              dio.patch<Map<String, dynamic>>(any(), data: any(named: 'data')),
        );
      },
    );
  });

  // ── 7. empty masterId — UnauthorizedFailure without network call ───────────

  group('empty masterId guard', () {
    late HttpServiceRepository unauthRepo;

    setUp(() {
      unauthRepo = HttpServiceRepository(
        serviceApi: serviceApi,
        categoryApi: categoryApi,
        dio: dio,
        masterId: '',
      );
    });

    test(
      'listMyServices throws UnauthorizedFailure without making a network call',
      () async {
        await expectLater(
          unauthRepo.listMyServices(),
          throwsA(isA<UnauthorizedFailure>()),
        );

        verifyNever(
          () => serviceApi.getMasterServices(masterId: any(named: 'masterId')),
        );
      },
    );

    test(
      'create throws UnauthorizedFailure without making a network call',
      () async {
        await expectLater(
          unauthRepo.create(
            const MasterServiceCreate(
              name: 'Test',
              durationMinutes: 30,
              price: 100,
            ),
          ),
          throwsA(isA<UnauthorizedFailure>()),
        );

        verifyNever(
          () => serviceApi.addIndependentMasterService(
            createServiceDefinitionRequest: any(
              named: 'createServiceDefinitionRequest',
            ),
          ),
        );
      },
    );

    test(
      'deactivate throws UnauthorizedFailure without making a network call',
      () async {
        await expectLater(
          unauthRepo.deactivate(_serviceId),
          throwsA(isA<UnauthorizedFailure>()),
        );

        verifyNever(
          () => serviceApi.deactivateServiceDefinition(
            serviceDefId: any(named: 'serviceDefId'),
          ),
        );
      },
    );
  });

  // ── 8. fetchApprovedCategories ──────────────────────────────────────────────

  group('fetchApprovedCategories', () {
    Response<ApiResponseListApprovedCategoryResponse> approvedResponse(
      List<ApprovedCategoryResponse> items,
    ) {
      final envelope = ApiResponseListApprovedCategoryResponse(
        (b) => b
          ..data = ListBuilder<ApprovedCategoryResponse>(items)
          ..success = true,
      );
      return Response<ApiResponseListApprovedCategoryResponse>(
        data: envelope,
        requestOptions: RequestOptions(
          path: '/api/v1/service-categories/approved',
        ),
        statusCode: 200,
      );
    }

    ApprovedCategoryResponse approvedDto(String name, String displayName) =>
        (ApprovedCategoryResponseBuilder()
              ..name = name
              ..displayName = displayName)
            .build();

    test('maps approved categories preserving name + displayName', () async {
      when(() => categoryApi.listApproved()).thenAnswer(
        (_) async => approvedResponse(<ApprovedCategoryResponse>[
          approvedDto('MANICURE', 'Манікюр'),
          approvedDto('NAIL_ART', 'Нейл-арт'),
        ]),
      );

      final result = await repository.fetchApprovedCategories();

      expect(result.map((o) => o.name).toList(), <String>[
        'MANICURE',
        'NAIL_ART',
      ]);
      expect(result.first.displayName, 'Манікюр');
    });

    test('returns empty list when envelope data is null', () async {
      final envelope = ApiResponseListApprovedCategoryResponse(
        (b) => b..success = true,
      );
      when(() => categoryApi.listApproved()).thenAnswer(
        (_) async => Response<ApiResponseListApprovedCategoryResponse>(
          data: envelope,
          requestOptions: RequestOptions(
            path: '/api/v1/service-categories/approved',
          ),
          statusCode: 200,
        ),
      );

      expect(await repository.fetchApprovedCategories(), isEmpty);
    });

    test('maps DioException to a Failure', () async {
      when(() => categoryApi.listApproved()).thenThrow(
        DioException(
          requestOptions: RequestOptions(
            path: '/api/v1/service-categories/approved',
          ),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        repository.fetchApprovedCategories(),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });

  // ── 9. requestCategory ──────────────────────────────────────────────────────

  group('requestCategory', () {
    Response<ApiResponseCategoryRequestResponse> createdResponse() {
      final dto =
          (CategoryRequestResponseBuilder()
                ..name = 'NAIL_ART'
                ..displayName = 'Нейл-арт'
                ..status = 'PENDING')
              .build();
      final envelope = ApiResponseCategoryRequestResponse(
        (b) => b
          ..data.replace(dto)
          ..success = true,
      );
      return Response<ApiResponseCategoryRequestResponse>(
        data: envelope,
        requestOptions: RequestOptions(
          path: '/api/v1/service-categories/requests',
        ),
        statusCode: 201,
      );
    }

    DioException dioWithStatus(int status) => DioException(
      requestOptions: RequestOptions(
        path: '/api/v1/service-categories/requests',
      ),
      response: Response<dynamic>(
        requestOptions: RequestOptions(
          path: '/api/v1/service-categories/requests',
        ),
        statusCode: status,
      ),
      type: DioExceptionType.badResponse,
    );

    test('success forwards the correct name + displayName once', () async {
      when(
        () => categoryApi.submitRequest(
          createCategoryRequestRequest: any(
            named: 'createCategoryRequestRequest',
          ),
        ),
      ).thenAnswer((_) async => createdResponse());

      await repository.requestCategory(
        name: 'NAIL_ART',
        displayName: 'Нейл-арт',
      );

      final captured =
          verify(
                () => categoryApi.submitRequest(
                  createCategoryRequestRequest: captureAny(
                    named: 'createCategoryRequestRequest',
                  ),
                ),
              ).captured.single
              as CreateCategoryRequestRequest;
      expect(captured.name, 'NAIL_ART');
      expect(captured.displayName, 'Нейл-арт');
    });

    test('409 → CategoryAlreadyExistsFailure', () async {
      when(
        () => categoryApi.submitRequest(
          createCategoryRequestRequest: any(
            named: 'createCategoryRequestRequest',
          ),
        ),
      ).thenThrow(dioWithStatus(409));

      await expectLater(
        repository.requestCategory(name: 'NAIL_ART', displayName: 'Нейл-арт'),
        throwsA(isA<CategoryAlreadyExistsFailure>()),
      );
    });

    test('429 → CategoryRequestThrottledFailure', () async {
      when(
        () => categoryApi.submitRequest(
          createCategoryRequestRequest: any(
            named: 'createCategoryRequestRequest',
          ),
        ),
      ).thenThrow(dioWithStatus(429));

      await expectLater(
        repository.requestCategory(name: 'NAIL_ART', displayName: 'Нейл-арт'),
        throwsA(isA<CategoryRequestThrottledFailure>()),
      );
    });

    test('other status → generic Failure (ServerFailure)', () async {
      when(
        () => categoryApi.submitRequest(
          createCategoryRequestRequest: any(
            named: 'createCategoryRequestRequest',
          ),
        ),
      ).thenThrow(dioWithStatus(500));

      await expectLater(
        repository.requestCategory(name: 'NAIL_ART', displayName: 'Нейл-арт'),
        throwsA(isA<ServerFailure>()),
      );
    });
  });
}
