// First-time service setup — unit tests for [HttpServiceRepository.bulkCreate].
//
// Strategy:
//   bulkCreate is the ONE repository method that bypasses the generated
//   [ServiceControllerApi] and POSTs through the raw authenticated [Dio]
//   (the generated client has no bulk operation yet). So these tests mock the
//   [Dio] instance with mocktail and drive `bulkCreate` directly —
//   [HttpServiceRepository] is constructed by hand (no Riverpod), mirroring
//   service_repository_test.dart.
//
// Coverage:
//   1. happy path  — POSTs to the /api/v1-prefixed bulk path; per-item JSON is
//      correct (FIXED → `price` only, no priceMin/priceMax; RANGE →
//      priceMin/priceMax only, no `price`); response mapped to domain.
//   2. 409         → ServiceDuplicateFailure, but ONLY for the typed
//      `data.code == DUPLICATE_SERVICE` envelope. Since beautica-backend
//      c5e420f made bulk create ADDITIVE, the "master already has services"
//      server condition is gone and with it the former
//      MasterAlreadyHasServicesFailure remap — a plain, untyped 409 now falls
//      THROUGH to the generic `_mapDioException` mapping.
//   2b. 503        → BulkSetupBusyFailure (per-master advisory lock still held
//      at the backend's 3 s ceiling; transient, nothing was written).
//   3. 400 / 422   → ValidationFailure.
//   4. transport   → NetworkFailure (connectionError) / ServerFailure (5xx).
//   5. no raw DioException escapes (only typed Failure subclasses).
//   6. empty items → no network call, resolves to [].
//   7. empty masterId guard → UnauthorizedFailure without a network call.
//
// Pure Dart: no ProviderScope, no widget tree.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────

class _MockServiceControllerApi extends Mock implements ServiceControllerApi {}

class _MockCategoryRequestControllerApi extends Mock
    implements CategoryRequestControllerApi {}

class _MockServiceCatalogControllerApi extends Mock
    implements ServiceCatalogControllerApi {}

class _MockDio extends Mock implements Dio {}

// ── Helpers ─────────────────────────────────────────────────────────────────

const _masterId = 'master-abc';
const _bulkPath = '/api/v1/independent-masters/me/services/bulk';

const _fixedItem = MasterServiceBulkItem(
  serviceTypeId: 'type-fixed',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  price: 500,
);

const _rangeItem = MasterServiceBulkItem(
  serviceTypeId: 'type-range',
  durationMinutes: 90,
  priceType: ServicePriceType.range,
  priceMin: 700,
  priceMax: 1200,
);

/// A wire-shape `MasterServiceResponse` JSON map as the backend would return it
/// inside the `data` array — fed straight through `standardSerializers`, so the
/// keys must match the generated model exactly.
Map<String, Object?> _wireServiceJson({
  String id = 'svc-001',
  String name = 'Манікюр',
  int durationMinutes = 60,
  num priceMin = 500,
}) => <String, Object?>{
  'id': id,
  'masterId': _masterId,
  'serviceDefinition': <String, Object?>{
    'id': 'def-$id',
    'name': name,
    'baseDurationMinutes': durationMinutes,
    'priceType': 'FIXED',
    'priceMin': priceMin,
    'priceDisplay': '${priceMin.toInt()} ₴',
    'isActive': true,
  },
  'isActive': true,
};

/// The `ApiResponse<List<MasterServiceResponse>>` envelope the bulk POST returns.
Response<Object?> _bulkOkResponse(List<Map<String, Object?>> services) =>
    Response<Object?>(
      requestOptions: RequestOptions(path: _bulkPath),
      statusCode: 201,
      data: <String, Object?>{'success': true, 'data': services},
    );

DioException _dioWithStatus(int status) => DioException(
  requestOptions: RequestOptions(path: _bulkPath),
  type: DioExceptionType.badResponse,
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: _bulkPath),
    statusCode: status,
  ),
);

// ── Test suite ───────────────────────────────────────────────────────────────

void main() {
  late _MockServiceControllerApi serviceApi;
  late _MockCategoryRequestControllerApi categoryApi;
  late _MockServiceCatalogControllerApi catalogApi;
  late _MockDio dio;
  late HttpServiceRepository repository;

  setUp(() {
    serviceApi = _MockServiceControllerApi();
    categoryApi = _MockCategoryRequestControllerApi();
    catalogApi = _MockServiceCatalogControllerApi();
    dio = _MockDio();
    repository = HttpServiceRepository(
      serviceApi: serviceApi,
      categoryApi: categoryApi,
      catalogApi: catalogApi,
      dio: dio,
      masterId: _masterId,
    );
  });

  group('bulkCreate — happy path', () {
    test(
      'POSTs to the /api/v1-prefixed bulk path and maps the response',
      () async {
        when(
          () => dio.post<Object?>(_bulkPath, data: any(named: 'data')),
        ).thenAnswer(
          (_) async => _bulkOkResponse(<Map<String, Object?>>[
            _wireServiceJson(id: 'svc-001', name: 'Манікюр', priceMin: 500),
            _wireServiceJson(id: 'svc-002', name: 'Педикюр', priceMin: 700),
          ]),
        );

        final result = await repository.bulkCreate(<MasterServiceBulkItem>[
          _fixedItem,
          _rangeItem,
        ]);

        expect(result, hasLength(2));
        expect(result.first, isA<MasterService>());
        expect(result.first.name, 'Манікюр');
        expect(result.first.priceMin, 500.0);
        expect(result[1].name, 'Педикюр');

        // The path MUST carry the /api/v1 prefix — the generated client's
        // relative paths all begin with /api/v1 and AppConfig strips it from
        // baseUrl, so the raw path must include it to match (omitting it 404s).
        verify(
          () => dio.post<Object?>(_bulkPath, data: any(named: 'data')),
        ).called(1);
      },
    );

    test(
      'serialises FIXED items with `price` only (no priceMin/priceMax)',
      () async {
        when(
          () => dio.post<Object?>(_bulkPath, data: any(named: 'data')),
        ).thenAnswer((_) async => _bulkOkResponse(<Map<String, Object?>>[]));

        await repository.bulkCreate(<MasterServiceBulkItem>[_fixedItem]);

        final captured =
            verify(
                  () => dio.post<Object?>(
                    _bulkPath,
                    data: captureAny(named: 'data'),
                  ),
                ).captured.single
                as Map<String, Object?>;
        final items = captured['items']! as List<Object?>;
        final item = items.single! as Map<String, Object?>;

        expect(item['serviceTypeId'], 'type-fixed');
        expect(item['durationMinutes'], 60);
        expect(item['priceType'], 'FIXED');
        expect(item['price'], 500);
        // FIXED must NOT carry range fields.
        expect(item.containsKey('priceMin'), isFalse);
        expect(item.containsKey('priceMax'), isFalse);
      },
    );

    test(
      'serialises RANGE items with priceMin/priceMax only (no `price`)',
      () async {
        when(
          () => dio.post<Object?>(_bulkPath, data: any(named: 'data')),
        ).thenAnswer((_) async => _bulkOkResponse(<Map<String, Object?>>[]));

        await repository.bulkCreate(<MasterServiceBulkItem>[_rangeItem]);

        final captured =
            verify(
                  () => dio.post<Object?>(
                    _bulkPath,
                    data: captureAny(named: 'data'),
                  ),
                ).captured.single
                as Map<String, Object?>;
        final items = captured['items']! as List<Object?>;
        final item = items.single! as Map<String, Object?>;

        expect(item['serviceTypeId'], 'type-range');
        expect(item['durationMinutes'], 90);
        expect(item['priceType'], 'RANGE');
        expect(item['priceMin'], 700);
        expect(item['priceMax'], 1200);
        // RANGE must NOT carry the fixed `price` field.
        expect(item.containsKey('price'), isFalse);
      },
    );
  });

  group('bulkCreate — error mapping', () {
    test('409 (no typed code) FALLS THROUGH to the generic mapping — '
        'ServerFailure(409), not a bespoke bulk-setup failure', () async {
      // The old contract remapped ANY 409 on this endpoint to
      // MasterAlreadyHasServicesFailure ("bulk setup is only for a master with
      // no active services"). beautica-backend c5e420f made bulk create
      // ADDITIVE and deleted that server condition, so the only 409 the
      // endpoint still emits is the typed DUPLICATE_SERVICE envelope covered
      // by the next test. An UNTYPED 409 is now an UNMODELLED conflict: it
      // must surface as the honest generic server error rather than being
      // mistranslated into confident, wrong copy (and, in the screen, a forced
      // navigation away without saving).
      when(
        () => dio.post<Object?>(_bulkPath, data: any(named: 'data')),
      ).thenThrow(_dioWithStatus(409));

      final failure = await repository
          .bulkCreate(<MasterServiceBulkItem>[_fixedItem])
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect(
        failure,
        isNot(isA<ServiceDuplicateFailure>()),
        reason:
            'the duplicate remap is gated on data.code == DUPLICATE_SERVICE; '
            'a bodiless 409 must NOT claim the service is already in the menu',
      );
      expect(failure, isA<ServerFailure>());
      expect(
        (failure! as ServerFailure).statusCode,
        409,
        reason:
            'the status must be carried through verbatim — '
            'failure_retry_policy classifies ServerFailure by statusCode, and '
            '409 must stay OUT of the retryable 5xx band',
      );
    });

    test(
      '409 DUPLICATE_SERVICE → ServiceDuplicateFailure (serviceName null on bulk)',
      () async {
        // The typed 409 envelope is the ONE modelled conflict on this path (it
        // must also beat any generic ServerFailure(409) the
        // ErrorMapperInterceptor attached — see the contract test).
        // `serviceName` is null on this path; `existingServiceDefId` may be
        // present.
        when(
          () => dio.post<Object?>(_bulkPath, data: any(named: 'data')),
        ).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: _bulkPath),
            type: DioExceptionType.badResponse,
            error: const ServerFailure(statusCode: 409),
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: _bulkPath),
              statusCode: 409,
              data: <String, dynamic>{
                'success': false,
                'data': <String, dynamic>{
                  'code': 'DUPLICATE_SERVICE',
                  'serviceName': null,
                  'existingServiceDefId': 'def-existing',
                },
                'message': 'This service already exists',
              },
            ),
          ),
        );

        final failure = await repository
            .bulkCreate(<MasterServiceBulkItem>[_fixedItem])
            .then<Object?>((_) => null, onError: (Object e) => e);

        expect(failure, isA<ServiceDuplicateFailure>());
        final dup = failure! as ServiceDuplicateFailure;
        expect(dup.serviceName, isNull);
        expect(dup.existingServiceDefId, 'def-existing');
      },
    );

    test('400 → ValidationFailure', () async {
      when(
        () => dio.post<Object?>(_bulkPath, data: any(named: 'data')),
      ).thenThrow(_dioWithStatus(400));

      await expectLater(
        repository.bulkCreate(<MasterServiceBulkItem>[_fixedItem]),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('422 → ValidationFailure', () async {
      when(
        () => dio.post<Object?>(_bulkPath, data: any(named: 'data')),
      ).thenThrow(_dioWithStatus(422));

      await expectLater(
        repository.bulkCreate(<MasterServiceBulkItem>[_fixedItem]),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('connectionError → NetworkFailure', () async {
      when(
        () => dio.post<Object?>(_bulkPath, data: any(named: 'data')),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _bulkPath),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        repository.bulkCreate(<MasterServiceBulkItem>[_fixedItem]),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('503 → BulkSetupBusyFailure (advisory lock held past the 3 s '
        'ceiling), NOT a generic 5xx ServerFailure', () async {
      when(
        () => dio.post<Object?>(_bulkPath, data: any(named: 'data')),
      ).thenThrow(_dioWithStatus(503));

      final failure = await repository
          .bulkCreate(<MasterServiceBulkItem>[_fixedItem])
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect(failure, isA<BulkSetupBusyFailure>());
      expect(
        failure,
        isNot(isA<ServerFailure>()),
        reason:
            'a bare ServerFailure(503) would render the generic server-error '
            'copy instead of the "setup is busy, try again" message; the '
            'status-code remap in _mapBulkCreateException exists to prevent '
            'exactly that',
      );
    });

    // ── 429 — the throttle the new retry affordance walks users into ─────────
    //
    // The bulk route is rate-limited (10/min per master). `_mapBulkCreateException`
    // handles 409 and 503 and defers everything else, so a 429 lands in
    // `_mapDioException`'s `badResponse` default and becomes
    // `ServerFailure(statusCode: 429)` — the SAME generic "server error, try
    // again" copy a 500 produces, and classified NON-transient by
    // `isTransientFailure` (its ServerFailure arm only accepts 500–599).
    //
    // That is newly load-bearing in this change: the 503 branch now hands the
    // master an explicit «Повторити» button, so re-tapping into the limiter is
    // the behaviour the UI actively invites. When they cross it they are told
    // "server error" — advice that is both wrong (the server is fine) and
    // useless (retrying immediately fails again).
    //
    // This test pins the fix rather than the current behaviour: it asserts the
    // 429 is (a) not collapsed into the generic server error and (b) classified
    // as retryable-after-a-wait. It is RED until the mapping is added.
    test('429 → a typed, retryable rate-limit failure — NOT the generic '
        'ServerFailure the 500 path produces', () async {
      when(
        () => dio.post<Object?>(_bulkPath, data: any(named: 'data')),
      ).thenThrow(_dioWithStatus(429));

      final failure = await repository
          .bulkCreate(<MasterServiceBulkItem>[_fixedItem])
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect(failure, isA<Failure>());
      expect(
        failure,
        isNot(isA<ServerFailure>()),
        reason:
            'a throttled master must not be told "server error, try again" — '
            'that is the one piece of advice guaranteed to fail, and the new '
            '503 retry action makes hitting the 10/min bulk limit reachable',
      );
      expect(
        isTransientFailure(failure! as Failure),
        isTrue,
        reason:
            'a rate limit clears on its own, so it belongs on the transient '
            'side of the retry policy alongside the 5xx and 503 arms — '
            'ServerFailure(429) is currently classified DETERMINISTIC because '
            'that arm only accepts 500-599',
      );
    });

    test('5xx (other than 503) → ServerFailure', () async {
      when(
        () => dio.post<Object?>(_bulkPath, data: any(named: 'data')),
      ).thenThrow(_dioWithStatus(500));

      await expectLater(
        repository.bulkCreate(<MasterServiceBulkItem>[_fixedItem]),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('no raw DioException escapes — always a typed Failure', () async {
      when(
        () => dio.post<Object?>(_bulkPath, data: any(named: 'data')),
      ).thenThrow(_dioWithStatus(403));

      await expectLater(
        repository.bulkCreate(<MasterServiceBulkItem>[_fixedItem]),
        throwsA(isA<Failure>()),
      );
    });

    test('pre-mapped Failure on e.error is re-thrown unchanged', () async {
      const mapped = ValidationFailure(fieldErrors: {'items[0].price': 'bad'});
      when(
        () => dio.post<Object?>(_bulkPath, data: any(named: 'data')),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _bulkPath),
          type: DioExceptionType.badResponse,
          error: mapped,
        ),
      );

      await expectLater(
        repository.bulkCreate(<MasterServiceBulkItem>[_fixedItem]),
        throwsA(same(mapped)),
      );
    });
  });

  group('bulkCreate — short circuits', () {
    test('empty items resolves to [] without a network call', () async {
      final result = await repository.bulkCreate(
        const <MasterServiceBulkItem>[],
      );

      expect(result, isEmpty);
      verifyNever(() => dio.post<Object?>(any(), data: any(named: 'data')));
    });

    test(
      'empty masterId throws UnauthorizedFailure without a network call',
      () async {
        final unauthRepo = HttpServiceRepository(
          serviceApi: serviceApi,
          categoryApi: categoryApi,
          catalogApi: catalogApi,
          dio: dio,
          masterId: '',
        );

        await expectLater(
          unauthRepo.bulkCreate(<MasterServiceBulkItem>[_fixedItem]),
          throwsA(isA<UnauthorizedFailure>()),
        );
        verifyNever(() => dio.post<Object?>(any(), data: any(named: 'data')));
      },
    );
  });
}
