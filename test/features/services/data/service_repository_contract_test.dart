// Contract-drift regression net (2026-06-02) — service management surface.
//
// WHY THIS FILE EXISTS
// --------------------
// The recent "profile-save → nothing persists" bug shipped GREEN because every
// service-feature test mocked either the generated API or the repository, so the
// REAL request→response→Failure contract was never exercised end-to-end. A
// backend response shape the app mishandles (a 4xx/5xx whose body the repository
// maps to the WRONG Failure, or a success envelope it fails to parse) slips
// straight through that blind spot into a silent or wrong UI.
//
// This file closes that gap for the service CRUD surface. It wires:
//   • a REAL Dio with the SAME interceptor that production installs —
//     [ErrorMapperInterceptor] — so the status→Failure mapping that the
//     repository depends on (`e.error is Failure`) runs for real;
//   • the REAL generated [ServiceControllerApi] + [standardSerializers];
//   • the REAL [HttpServiceRepository].
// Only the HTTP socket is faked via http_mock_adapter's [DioAdapter].
//
// POSITIVE paths assert the success envelope parses into the right domain model.
// NEGATIVE paths assert every realistic server failure (400 with errors map,
// 400 with EMPTY errors map, 401, 403, 404, 409, 422, 500, network timeout,
// malformed JSON) maps to the CORRECT typed Failure — never a raw DioException,
// never the wrong subtype, never a silent swallow.
//
// Runs headless in CI:  flutter test test/features/services/data/service_repository_contract_test.dart
// Placed under test/ (not integration_test/) so it executes on every push —
// integration_test/ is emulator-only and excluded from the CI gate.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/error_mapper_interceptor.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

// The production dioProvider baseUrl carries NO /api/v1 prefix; the generated
// client prepends the full /api/v1/ segment. Mirror that here so assembled
// paths match production exactly.
const _baseUrl = 'http://localhost:8080';
const _masterId = 'master-1';
const _serviceDefId = 'def-7';
const _assignmentId = 'svc-7';

// Phase 16.9: listMyServices() hits the authenticated owner endpoint (master
// derived from the JWT principal, drafts included) — no masterId path param.
const _listPath = '/api/v1/independent-masters/me/services';
const _createPath = '/api/v1/independent-masters/me/services';
const _mutatePath = '/api/v1/services/$_serviceDefId';

// ---------------------------------------------------------------------------
// Success envelopes (as the Spring backend serializes them)
// ---------------------------------------------------------------------------

/// A realistic MasterServiceResponse nested envelope, FIXED pricing.
Map<String, dynamic> _masterServiceEnvelope({
  String id = _assignmentId,
  String defId = _serviceDefId,
  String name = 'Манікюр',
  String priceType = 'FIXED',
  num priceMin = 500,
  num? priceMax,
}) => <String, dynamic>{
  'success': true,
  'message': 'ok',
  'data': <String, dynamic>{
    'id': id,
    'masterId': _masterId,
    'effectiveDurationMinutes': 60,
    'isActive': true,
    'priceType': priceType,
    'priceMin': priceMin,
    'priceMax': priceMax,
    'priceDisplay': priceMax == null
        ? '$priceMin грн'
        : '$priceMin–$priceMax грн',
    'serviceDefinition': <String, dynamic>{
      'id': defId,
      'name': name,
      'category': 'MANICURE',
      'baseDurationMinutes': 60,
      'priceType': priceType,
      'priceMin': priceMin,
      'priceMax': priceMax,
      'priceDisplay': priceMax == null
          ? '$priceMin грн'
          : '$priceMin–$priceMax грн',
      'isActive': true,
    },
  },
};

/// A list envelope wrapping one MasterServiceResponse.
Map<String, dynamic> _listEnvelope() => <String, dynamic>{
  'success': true,
  'message': 'ok',
  'data': <Map<String, dynamic>>[
    (_masterServiceEnvelope()['data'] as Map<String, dynamic>),
  ],
};

/// The ServiceDefinitionResponse envelope returned by PATCH /services/{id}.
Map<String, dynamic> _serviceDefEnvelope({String name = 'Манікюр PRO'}) =>
    <String, dynamic>{
      'success': true,
      'message': 'ok',
      'data': <String, dynamic>{
        'id': _serviceDefId,
        'name': name,
        'category': 'MANICURE',
        'baseDurationMinutes': 90,
        'priceType': 'FIXED',
        'priceMin': 650,
        'priceDisplay': '650 грн',
        'isActive': true,
      },
    };

const Map<String, dynamic> _okVoid = <String, dynamic>{
  'success': true,
  'data': null,
  'message': 'ok',
};

// ---------------------------------------------------------------------------
// Harness — real interceptor + real API + real repository over a faked socket
// ---------------------------------------------------------------------------

({Dio dio, DioAdapter adapter, HttpServiceRepository repo}) _wire() {
  final dio = Dio(
    BaseOptions(
      baseUrl: _baseUrl,
      headers: const <String, dynamic>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ),
  );
  // The REAL production status→Failure mapper. This is the load-bearing piece:
  // HttpServiceRepository._mapDioException trusts that ErrorMapperInterceptor
  // has already attached a typed Failure as e.error. Installing the real
  // interceptor exercises that exact contract.
  dio.interceptors.add(ErrorMapperInterceptor());
  final adapter = DioAdapter(dio: dio);
  final api = ServiceControllerApi(dio, standardSerializers);
  final categoryApi = CategoryRequestControllerApi(dio, standardSerializers);
  final catalogApi = ServiceCatalogControllerApi(dio, standardSerializers);
  final repo = HttpServiceRepository(
    serviceApi: api,
    categoryApi: categoryApi,
    catalogApi: catalogApi,
    dio: dio,
    masterId: _masterId,
  );
  return (dio: dio, adapter: adapter, repo: repo);
}

const _validCreate = MasterServiceCreate(
  name: 'Манікюр',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  price: 500,
  category: 'MANICURE',
  // Service type is mandatory on create (backend @NotNull); a valid create
  // fixture must carry one or the mapper fail-fasts before the network call.
  serviceTypeId: 'stype-1',
);

const _validUpdate = MasterServiceUpdate(
  name: 'Манікюр PRO',
  durationMinutes: 90,
  priceType: ServicePriceType.fixed,
  price: 650,
  category: 'MANICURE',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  // listMyServices
  // =========================================================================
  group('listMyServices — full transport contract', () {
    test(
      'POSITIVE: 200 list envelope parses into MasterService list',
      () async {
        final h = _wire();
        h.adapter.onGet(_listPath, (s) => s.reply(200, _listEnvelope()));

        final list = await h.repo.listMyServices();

        expect(list, hasLength(1));
        expect(list.first.id, _assignmentId);
        expect(list.first.serviceDefId, _serviceDefId);
        expect(list.first.name, 'Манікюр');
        expect(list.first.priceMin, 500.0);
        expect(list.first.priceType, ServicePriceType.fixed);
      },
    );

    test(
      'POSITIVE: 200 with null data array → empty list (not a throw)',
      () async {
        final h = _wire();
        h.adapter.onGet(
          _listPath,
          (s) => s.reply(200, <String, dynamic>{
            'success': true,
            'message': 'ok',
            'data': null,
          }),
        );

        expect(await h.repo.listMyServices(), isEmpty);
      },
    );

    test(
      'NEGATIVE: 401 → UnauthorizedFailure (never raw DioException)',
      () async {
        final h = _wire();
        h.adapter.onGet(_listPath, (s) => s.reply(401, {'message': 'unauth'}));

        await expectLater(
          h.repo.listMyServices(),
          throwsA(isA<UnauthorizedFailure>()),
        );
      },
    );

    test('NEGATIVE: 500 → ServerFailure(statusCode: 500)', () async {
      final h = _wire();
      h.adapter.onGet(_listPath, (s) => s.reply(500, {'message': 'boom'}));

      await expectLater(
        h.repo.listMyServices(),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('NEGATIVE: connection timeout → NetworkFailure', () async {
      final h = _wire();
      h.adapter.onGet(
        _listPath,
        (s) => s.throws(
          408,
          DioException.connectionTimeout(
            timeout: const Duration(seconds: 1),
            requestOptions: RequestOptions(path: _listPath),
          ),
        ),
      );

      await expectLater(
        h.repo.listMyServices(),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });

  // =========================================================================
  // create
  // =========================================================================
  group('create — full transport contract', () {
    test(
      'POSITIVE: 200 envelope parses into the created MasterService',
      () async {
        final h = _wire();
        h.adapter.onPost(
          _createPath,
          (s) => s.reply(200, _masterServiceEnvelope(name: 'Педикюр')),
          data: Matchers.any,
        );

        final created = await h.repo.create(_validCreate);

        expect(created.id, _assignmentId);
        expect(created.serviceDefId, _serviceDefId);
        expect(created.name, 'Педикюр');
      },
    );

    test('POSITIVE: RANGE create envelope parses priceMin/priceMax', () async {
      final h = _wire();
      h.adapter.onPost(
        _createPath,
        (s) => s.reply(
          200,
          _masterServiceEnvelope(
            priceType: 'RANGE',
            priceMin: 400,
            priceMax: 700,
          ),
        ),
        data: Matchers.any,
      );

      final created = await h.repo.create(
        const MasterServiceCreate(
          name: 'Стрижка',
          durationMinutes: 60,
          priceType: ServicePriceType.range,
          priceMin: 400,
          priceMax: 700,
          category: 'HAIRCUT',
          serviceTypeId: 'stype-1',
        ),
      );

      expect(created.priceType, ServicePriceType.range);
      expect(created.priceMin, 400.0);
      expect(created.priceMax, 700.0);
    });

    test('NEGATIVE: 400 with field-errors map → ValidationFailure carrying '
        'fieldErrors', () async {
      final h = _wire();
      h.adapter.onPost(
        _createPath,
        (s) => s.reply(400, {
          'success': false,
          'errors': {'name': 'must not be blank'},
        }),
        data: Matchers.any,
      );

      await expectLater(
        h.repo.create(_validCreate),
        throwsA(
          isA<ValidationFailure>().having(
            (f) => f.fieldErrors['name'],
            'fieldErrors[name]',
            'must not be blank',
          ),
        ),
      );
    });

    test('NEGATIVE: 400 with EMPTY errors map → ValidationFailure with empty '
        'fieldErrors (the silent-dead-state guard)', () async {
      final h = _wire();
      h.adapter.onPost(
        _createPath,
        (s) => s.reply(400, {'success': false, 'message': 'Bad request'}),
        data: Matchers.any,
      );

      await expectLater(
        h.repo.create(_validCreate),
        throwsA(
          isA<ValidationFailure>().having(
            (f) => f.fieldErrors,
            'fieldErrors',
            isEmpty,
          ),
        ),
      );
    });

    test('NEGATIVE: 422 (Spring @Validated) → ValidationFailure', () async {
      final h = _wire();
      h.adapter.onPost(
        _createPath,
        (s) => s.reply(422, {
          'success': false,
          'errors': {'price': 'must be positive'},
        }),
        data: Matchers.any,
      );

      await expectLater(
        h.repo.create(_validCreate),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test(
      'NEGATIVE: 403 → UnknownFailure (interceptor maps unmapped 403)',
      () async {
        // ErrorMapperInterceptor maps an unmodelled 403 to UnknownFailure; the
        // repository re-throws e.error verbatim. This pins the observable
        // contract so a refactor that changes it is caught.
        final h = _wire();
        h.adapter.onPost(
          _createPath,
          (s) => s.reply(403, {'message': 'forbidden'}),
          data: Matchers.any,
        );

        await expectLater(
          h.repo.create(_validCreate),
          throwsA(isA<UnknownFailure>()),
        );
      },
    );

    test('NEGATIVE: 500 → ServerFailure(500)', () async {
      final h = _wire();
      h.adapter.onPost(
        _createPath,
        (s) => s.reply(500, {'message': 'boom'}),
        data: Matchers.any,
      );

      await expectLater(
        h.repo.create(_validCreate),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('NEGATIVE: 200 success status but null data payload → ServerFailure '
        '(malformed/unexpected success shape, not a silent null)', () async {
      final h = _wire();
      h.adapter.onPost(
        _createPath,
        (s) => s.reply(200, {'success': true, 'message': 'ok', 'data': null}),
        data: Matchers.any,
      );

      await expectLater(
        h.repo.create(_validCreate),
        throwsA(isA<ServerFailure>()),
      );
    });
  });

  // =========================================================================
  // update
  // =========================================================================
  group('update — full transport contract', () {
    test(
      'POSITIVE: 200 ServiceDefinitionResponse parses, assignmentId threaded',
      () async {
        final h = _wire();
        h.adapter.onPatch(
          _mutatePath,
          (s) => s.reply(200, _serviceDefEnvelope(name: 'Манікюр PRO')),
          data: Matchers.any,
        );

        final updated = await h.repo.update(
          _serviceDefId,
          _validUpdate,
          assignmentId: _assignmentId,
        );

        expect(
          updated.id,
          _assignmentId,
          reason: 'assignment id threaded through',
        );
        expect(updated.serviceDefId, _serviceDefId);
        expect(updated.name, 'Манікюр PRO');
        expect(updated.durationMinutes, 90);
      },
    );

    test('NEGATIVE: 404 (wrong serviceDefId) → NotFoundFailure', () async {
      final h = _wire();
      h.adapter.onPatch(
        _mutatePath,
        (s) => s.reply(404, {'message': 'not found'}),
        data: Matchers.any,
      );

      await expectLater(
        h.repo.update(_serviceDefId, _validUpdate, assignmentId: _assignmentId),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test('NEGATIVE: 400 field errors → ValidationFailure', () async {
      final h = _wire();
      h.adapter.onPatch(
        _mutatePath,
        (s) => s.reply(400, {
          'success': false,
          'errors': {'durationMinutes': 'too large'},
        }),
        data: Matchers.any,
      );

      await expectLater(
        h.repo.update(_serviceDefId, _validUpdate, assignmentId: _assignmentId),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('NEGATIVE: 401 → UnauthorizedFailure', () async {
      final h = _wire();
      h.adapter.onPatch(
        _mutatePath,
        (s) => s.reply(401, {'message': 'unauth'}),
        data: Matchers.any,
      );

      await expectLater(
        h.repo.update(_serviceDefId, _validUpdate, assignmentId: _assignmentId),
        throwsA(isA<UnauthorizedFailure>()),
      );
    });

    test('NEGATIVE: 500 → ServerFailure(500)', () async {
      final h = _wire();
      h.adapter.onPatch(
        _mutatePath,
        (s) => s.reply(500, {'message': 'boom'}),
        data: Matchers.any,
      );

      await expectLater(
        h.repo.update(_serviceDefId, _validUpdate, assignmentId: _assignmentId),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 500),
        ),
      );
    });
  });

  // =========================================================================
  // deactivate (delete)
  // =========================================================================
  group('deactivate — full transport contract', () {
    test('POSITIVE: 200 void → completes', () async {
      final h = _wire();
      h.adapter.onDelete(_mutatePath, (s) => s.reply(200, _okVoid));

      await expectLater(h.repo.deactivate(_serviceDefId), completes);
    });

    test('NEGATIVE: 404 → NotFoundFailure', () async {
      final h = _wire();
      h.adapter.onDelete(
        _mutatePath,
        (s) => s.reply(404, {'message': 'not found'}),
      );

      await expectLater(
        h.repo.deactivate(_serviceDefId),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test(
      'NEGATIVE: 409 conflict (e.g. future bookings) → ServerFailure(409)',
      () async {
        final h = _wire();
        h.adapter.onDelete(
          _mutatePath,
          (s) => s.reply(409, {'message': 'has future bookings'}),
        );

        await expectLater(
          h.repo.deactivate(_serviceDefId),
          throwsA(
            isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 409),
          ),
        );
      },
    );

    test('NEGATIVE: 401 → UnauthorizedFailure', () async {
      final h = _wire();
      h.adapter.onDelete(_mutatePath, (s) => s.reply(401, {'message': 'x'}));

      await expectLater(
        h.repo.deactivate(_serviceDefId),
        throwsA(isA<UnauthorizedFailure>()),
      );
    });

    test('NEGATIVE: connection error → NetworkFailure', () async {
      final h = _wire();
      h.adapter.onDelete(
        _mutatePath,
        (s) => s.throws(
          0,
          DioException.connectionError(
            requestOptions: RequestOptions(path: _mutatePath),
            reason: 'socket closed',
          ),
        ),
      );

      await expectLater(
        h.repo.deactivate(_serviceDefId),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });

  // =========================================================================
  // empty-masterId fast-fail (auth guard) — never lets a malformed URL fly
  // =========================================================================
  group('auth guard — empty masterId', () {
    HttpServiceRepository repoWithEmptyMaster() {
      final dio = Dio(BaseOptions(baseUrl: _baseUrl));
      dio.interceptors.add(ErrorMapperInterceptor());
      final api = ServiceControllerApi(dio, standardSerializers);
      final categoryApi = CategoryRequestControllerApi(
        dio,
        standardSerializers,
      );
      final catalogApi = ServiceCatalogControllerApi(dio, standardSerializers);
      return HttpServiceRepository(
        serviceApi: api,
        categoryApi: categoryApi,
        catalogApi: catalogApi,
        dio: dio,
        masterId: '',
      );
    }

    test(
      'listMyServices with empty masterId → UnauthorizedFailure (no socket)',
      () async {
        await expectLater(
          repoWithEmptyMaster().listMyServices(),
          throwsA(isA<UnauthorizedFailure>()),
        );
      },
    );

    test(
      'create with empty masterId → UnauthorizedFailure (no socket)',
      () async {
        await expectLater(
          repoWithEmptyMaster().create(_validCreate),
          throwsA(isA<UnauthorizedFailure>()),
        );
      },
    );
  });
}
