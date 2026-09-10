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
import 'package:beautica_mobile/features/services/domain/service_target.dart';
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
    'priceDisplay': priceMax == null ? '$priceMin ₴' : '$priceMin–$priceMax ₴',
    'serviceDefinition': <String, dynamic>{
      'id': defId,
      'name': name,
      'category': 'MANICURE',
      'baseDurationMinutes': 60,
      'priceType': priceType,
      'priceMin': priceMin,
      'priceMax': priceMax,
      'priceDisplay': priceMax == null
          ? '$priceMin ₴'
          : '$priceMin–$priceMax ₴',
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
        'priceDisplay': '650 ₴',
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

const _salonId = 'salon-abc';
const _salonMasterId = 'master-xyz';
const _salonMutatePath =
    '/api/v1/salons/$_salonId/masters/$_salonMasterId/services/$_serviceDefId';

/// Same harness as [_wire], but the repository carries a [SalonMasterTarget]
/// — phase 316's unassign branch. [lastRequestData] exposes the body of the
/// LAST request that matched [_salonMutatePath] (captured via a lightweight
/// interceptor, independent of the mock adapter's lenient default body
/// matching) so a test can assert "no request body was sent" precisely.
({
  Dio dio,
  DioAdapter adapter,
  HttpServiceRepository repo,
  Object? Function() lastRequestData,
})
_wireSalon() {
  final dio = Dio(
    BaseOptions(
      baseUrl: _baseUrl,
      headers: const <String, dynamic>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ),
  );
  Object? capturedData;
  var captured = false;
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.path == _salonMutatePath) {
          captured = true;
          capturedData = options.data;
        }
        handler.next(options);
      },
    ),
  );
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
    masterId: '',
    target: const SalonMasterTarget(
      salonId: _salonId,
      masterId: _salonMasterId,
    ),
    sessionUserId: 'user-row-uuid',
  );
  return (
    dio: dio,
    adapter: adapter,
    repo: repo,
    lastRequestData: () {
      expect(
        captured,
        isTrue,
        reason:
            'no request ever matched $_salonMutatePath — the test '
            'fixture is wrong, not the assertion',
      );
      return capturedData;
    },
  );
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

    // Was `POSITIVE: 200 with null data array → empty list (not a throw)`.
    // Inverted deliberately (security audit, null-envelope conflation): a 200
    // whose envelope carries no `data` array is a MALFORMED success, and
    // mapping it onto `const []` made it indistinguishable from a master with
    // genuinely zero services — the UI rendered the "no services" em-dash for
    // a response that never delivered a payload. It now throws so the caller's
    // error branch runs (and `ServicesStatTile` shows its distinct '?' glyph).
    test('NEGATIVE: 200 with null data array → ServerFailure '
        '(malformed success is never an empty catalogue)', () async {
      final h = _wire();
      h.adapter.onGet(
        _listPath,
        (s) => s.reply(200, <String, dynamic>{
          'success': true,
          'message': 'ok',
          'data': null,
        }),
      );

      await expectLater(h.repo.listMyServices(), throwsA(isA<ServerFailure>()));
    });

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
  // getMasterServices
  //
  // The PUBLIC sibling of listMyServices (GET /masters/{masterId}/services,
  // keyed on the path param rather than the JWT principal). It carried NO
  // transport-tier coverage at all until the null-data envelope stopped
  // mapping to `const []` and started throwing — the same inversion
  // listMyServices got, on the code path where it matters MORE, not less: a
  // silently-empty public profile shows a CLIENT a services-less master built
  // from a response that never delivered a payload.
  //
  // TIER: contract, not integration. What changed is a repository-internal
  // envelope→Failure decision on an existing route; it adds no screen, route,
  // navigation step or form submit. The CONSUMER side of the throw is already
  // pinned one tier up — `public_master_profile_notifier_test.dart`'s
  // "a failing services read propagates the typed ServerFailure" asserts the
  // provider unwraps it from `ParallelWaitError` so the screen's error branch
  // renders server-specific copy. What no tier covered is that a 200 whose
  // envelope has `data: null` PRODUCES that Failure in the first place, and
  // that is a wire-shape question: it needs the real ErrorMapperInterceptor,
  // the real generated client and the real deserializer over a faked socket,
  // which is precisely this file. An E2E would exercise the same one-line
  // branch through a whole app boot, run emulator-only (excluded from the CI
  // gate), and assert it indirectly through rendered copy — strictly slower
  // and weaker coverage of the thing that actually changed.
  // =========================================================================
  group('getMasterServices — full transport contract', () {
    const String publicPath = '/api/v1/masters/$_masterId/services';

    test(
      'POSITIVE: 200 list envelope parses into MasterService list',
      () async {
        final h = _wire();
        h.adapter.onGet(publicPath, (s) => s.reply(200, _listEnvelope()));

        final list = await h.repo.getMasterServices(_masterId);

        expect(list, hasLength(1));
        expect(list.first.id, _assignmentId);
        expect(list.first.serviceDefId, _serviceDefId);
        expect(list.first.name, 'Манікюр');
        expect(list.first.priceMin, 500.0);
        expect(list.first.priceType, ServicePriceType.fixed);
      },
    );

    test('POSITIVE: 200 with an EMPTY data array → empty list (a master who '
        'genuinely offers nothing is NOT an error)', () async {
      final h = _wire();
      h.adapter.onGet(
        publicPath,
        (s) => s.reply(200, <String, dynamic>{
          'success': true,
          'message': 'ok',
          'data': <Map<String, dynamic>>[],
        }),
      );

      expect(await h.repo.getMasterServices(_masterId), isEmpty);
    });

    // The inversion itself. Deliberately paired with the empty-array case
    // directly above: together they pin that `[]` and `null` are now DIFFERENT
    // outcomes. A regression that restored `?? const []` would keep the
    // empty-array test green and only this one would go red, which is the
    // whole point — the old behaviour made the two indistinguishable.
    test('NEGATIVE: 200 with null data array → ServerFailure '
        '(malformed success is never an empty catalogue)', () async {
      final h = _wire();
      h.adapter.onGet(
        publicPath,
        (s) => s.reply(200, <String, dynamic>{
          'success': true,
          'message': 'ok',
          'data': null,
        }),
      );

      await expectLater(
        h.repo.getMasterServices(_masterId),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('NEGATIVE: 404 (unknown masterId) → NotFoundFailure', () async {
      final h = _wire();
      h.adapter.onGet(
        publicPath,
        (s) => s.reply(404, {'message': 'no master'}),
      );

      await expectLater(
        h.repo.getMasterServices(_masterId),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test('NEGATIVE: 500 → ServerFailure(statusCode: 500)', () async {
      final h = _wire();
      h.adapter.onGet(publicPath, (s) => s.reply(500, {'message': 'boom'}));

      await expectLater(
        h.repo.getMasterServices(_masterId),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('NEGATIVE: connection timeout → NetworkFailure', () async {
      final h = _wire();
      h.adapter.onGet(
        publicPath,
        (s) => s.throws(
          408,
          DioException.connectionTimeout(
            timeout: const Duration(seconds: 1),
            requestOptions: RequestOptions(path: publicPath),
          ),
        ),
      );

      await expectLater(
        h.repo.getMasterServices(_masterId),
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
  // deactivate — salon-target (unassign) full transport contract (phase 316)
  // =========================================================================
  //
  // Same REAL interceptor + REAL Dio + REAL HttpServiceRepository harness as
  // [_wire] above, but the repository carries a [SalonMasterTarget]
  // (`_wireSalon`). Pins the two properties `service_repository_test.dart`'s
  // mocked-Dio unit tests cannot: (1) the REAL [ErrorMapperInterceptor]
  // agrees with `_mapUnassignException`'s status-code checks rather than
  // racing them, and (2) the salon branch sends NO request body — the
  // generated client's DELETE calls never do either, but this branch is
  // hand-built raw `_dio.delete`, so nothing enforces that at compile time.

  group('deactivate — salon-target full transport contract (phase 316)', () {
    test('POSITIVE: 204 void → completes; the path carries the DEFINITION id '
        '($_serviceDefId), never the assignment id ($_assignmentId — the two '
        'differ in this fixture on purpose)', () async {
      final h = _wireSalon();
      h.adapter.onDelete(_salonMutatePath, (s) => s.reply(204, null));

      await expectLater(h.repo.deactivate(_serviceDefId), completes);
    });

    test('POSITIVE: the unassign DELETE sends NO request body', () async {
      final h = _wireSalon();
      h.adapter.onDelete(_salonMutatePath, (s) => s.reply(204, null));

      await h.repo.deactivate(_serviceDefId);

      expect(
        h.lastRequestData(),
        isNull,
        reason:
            'phase 316 D1 — the unassign DELETE carries no body, mirroring '
            'the null-target branch and the generated client\'s DELETE',
      );
    });

    test('NEGATIVE: 409 (future CONFIRMED bookings) → '
        'ServiceUnassignBlockedFailure — nothing written', () async {
      final h = _wireSalon();
      h.adapter.onDelete(
        _salonMutatePath,
        (s) => s.reply(409, {
          'message':
              'Master has 2 future confirmed booking(s) for this service',
        }),
      );

      await expectLater(
        h.repo.deactivate(_serviceDefId),
        throwsA(isA<ServiceUnassignBlockedFailure>()),
      );
    });

    test('NEGATIVE: 404 (no active assignment for this pair) → '
        'NotFoundFailure', () async {
      final h = _wireSalon();
      h.adapter.onDelete(
        _salonMutatePath,
        (s) => s.reply(404, {'message': 'not found'}),
      );

      await expectLater(
        h.repo.deactivate(_serviceDefId),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test('NEGATIVE: 403 → falls through with NO special handling (D2 — the '
        'route guard makes this unreachable in practice); never mistaken for '
        'ServiceUnassignBlockedFailure or NotFoundFailure', () async {
      final h = _wireSalon();
      h.adapter.onDelete(
        _salonMutatePath,
        (s) => s.reply(403, {'message': 'forbidden'}),
      );

      await expectLater(
        h.repo.deactivate(_serviceDefId),
        throwsA(
          allOf(
            isNot(isA<ServiceUnassignBlockedFailure>()),
            isNot(isA<NotFoundFailure>()),
          ),
        ),
      );
    });

    test('NEGATIVE: 429 → ServiceRateLimitedFailure', () async {
      final h = _wireSalon();
      h.adapter.onDelete(
        _salonMutatePath,
        (s) => s.reply(
          429,
          {'message': 'rate limited'},
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
            'retry-after': ['30'],
          },
        ),
      );

      await expectLater(
        h.repo.deactivate(_serviceDefId),
        throwsA(
          isA<ServiceRateLimitedFailure>().having(
            (f) => f.retryAfterSeconds,
            'retryAfterSeconds',
            30,
          ),
        ),
      );
    });

    test('NEGATIVE: connection error → NetworkFailure', () async {
      final h = _wireSalon();
      h.adapter.onDelete(
        _salonMutatePath,
        (s) => s.throws(
          0,
          DioException.connectionError(
            requestOptions: RequestOptions(path: _salonMutatePath),
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
  // raw-path segment safety — POST-NORMALIZATION, on a REAL Dio
  // (mobile-security S1/S2/S3, phase-316 audit-fix cycle 1)
  // =========================================================================
  //
  // WHY THIS GROUP LIVES HERE AND NOT IN THE MOCKED-DIO UNIT TESTS
  // -------------------------------------------------------------
  // The unit tests capture the path STRING handed to a mocked `Dio.delete` /
  // `.get` / `.post`. Dio does not send that string. It sends
  // `RequestOptions.uri`, which is `Uri.parse(baseUrl + path).normalizePath()`
  // (`dio-5.9.2/lib/src/options.dart:642`) — and `normalizePath` REMOVES
  // dot-segments (RFC 3986 §5.2.4). So a corpus asserted against the
  // pre-normalization string is structurally incapable of catching the one
  // input that matters:
  //
  //   masterId = '..', serviceDefId = '..'
  //     string  : /api/v1/salons/salon-abc/masters/../services/..
  //     ON THE WIRE: /api/v1/salons/salon-abc/    ← the salon itself
  //
  // `Uri.encodeComponent` does NOT escape `.`, so encoding alone never closed
  // this. `HttpServiceRepository._pathSegment` therefore REJECTS dot-segments
  // instead of sanitising them, and these rows assert the wire URI a real Dio
  // computes — never the argument string.
  group('raw salon paths — post-normalization URI shape (real Dio)', () {
    // Values that MUST survive as exactly one path segment. `a/../../b` is the
    // deliberate near-miss: it CONTAINS dot-segments, but its separators
    // encode to %2F so `normalizePath` (which splits on literal `/` only)
    // cannot see them. It must pass, proving the guard rejects dot-SEGMENTS
    // rather than any string containing dots.
    const encodable = <String>[
      'a/b',
      '../evil',
      'x?y=1',
      'z#frag',
      '%2Falready-encoded',
      'a/../../b',
    ];

    // The S1 corpus gap: both survive `Uri.encodeComponent` VERBATIM and are
    // then eaten by `normalizePath`. These are the rows the old corpus was
    // missing — `'../evil'` above encodes to `..%2Fevil`, which reads as
    // coverage but is a different case entirely.
    const dotSegments = <String>['..', '.'];

    // `''` is also unusable as a segment (it collapses two separators into
    // one) but is caught one layer EARLIER, by `_assertAuthenticated`, for
    // salonId/masterId. Kept separate so each row pins the guard that
    // actually fires rather than a lowest-common-denominator matcher.
    const rejected = <String>[...dotSegments, ''];

    /// A REAL [Dio] whose first interceptor records `options.uri` — the
    /// post-normalization URI Dio would actually put on the socket — and then
    /// short-circuits with a canned success, so no adapter or socket is
    /// needed. Returns the repository plus the recorded URIs.
    ({HttpServiceRepository repo, List<Uri> uris}) probe({
      String salonId = _salonId,
      String masterId = _salonMasterId,
    }) {
      final dio = Dio(BaseOptions(baseUrl: _baseUrl));
      final uris = <Uri>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            uris.add(options.uri);
            handler.resolve(
              Response<Object?>(
                requestOptions: options,
                statusCode: 200,
                data: <String, Object?>{'success': true, 'data': <Object?>[]},
              ),
            );
          },
        ),
      );
      return (
        repo: HttpServiceRepository(
          serviceApi: ServiceControllerApi(dio, standardSerializers),
          categoryApi: CategoryRequestControllerApi(dio, standardSerializers),
          catalogApi: ServiceCatalogControllerApi(dio, standardSerializers),
          dio: dio,
          masterId: '',
          target: SalonMasterTarget(salonId: salonId, masterId: masterId),
          sessionUserId: 'user-row-uuid',
        ),
        uris: uris,
      );
    }

    // ── DELETE (unassign) — the S1 site ────────────────────────────────────

    for (final injected in encodable) {
      test('unassign DELETE: masterId "$injected" lands as ONE segment on the '
          'wire, post-normalizePath', () async {
        final h = probe(masterId: injected);

        await h.repo.deactivate(_serviceDefId);

        expect(
          h.uris.single.pathSegments,
          <String>[
            'api',
            'v1',
            'salons',
            _salonId,
            'masters',
            injected,
            'services',
            _serviceDefId,
          ],
          reason:
              'pathSegments DECODES, so the injected value is compared '
              'raw — what matters is that it is ONE element, not that it '
              'looks encoded',
        );
      });
    }

    for (final injected in dotSegments) {
      test(
        'unassign DELETE: masterId "$injected" is REJECTED as UnknownFailure '
        'and NO request is issued',
        () async {
          final h = probe(masterId: injected);

          await expectLater(
            h.repo.deactivate(_serviceDefId),
            throwsA(isA<UnknownFailure>()),
          );
          expect(
            h.uris,
            isEmpty,
            reason:
                'rejection must happen BEFORE the request — a request that '
                'flies and is then thrown away has already hit the backend',
          );
        },
      );

      test('unassign DELETE: serviceDefId "$injected" is REJECTED as '
          'UnknownFailure and NO request is issued — it is CALLER-SUPPLIED and '
          'has NO _assertAuthenticated guard behind it, so _pathSegment is the '
          'only thing standing between it and the wire', () async {
        final h = probe();

        await expectLater(
          h.repo.deactivate(injected),
          throwsA(isA<UnknownFailure>()),
        );
        expect(h.uris, isEmpty);
      });
    }

    test('unassign DELETE: an empty masterId is rejected by the EARLIER '
        '_assertAuthenticated guard (UnauthorizedFailure), still with no '
        'request', () async {
      final h = probe(masterId: '');

      await expectLater(
        h.repo.deactivate(_serviceDefId),
        throwsA(isA<UnauthorizedFailure>()),
      );
      expect(h.uris, isEmpty);
    });

    test('unassign DELETE: an empty serviceDefId has no earlier guard, so '
        '_pathSegment is the one that rejects it', () async {
      final h = probe();

      await expectLater(h.repo.deactivate(''), throwsA(isA<UnknownFailure>()));
      expect(h.uris, isEmpty);
    });

    test('unassign DELETE: the S1 exploit — masterId AND serviceDefId both '
        '".." — never degenerates to /api/v1/salons/{id}', () async {
      final h = probe(masterId: '..');

      await expectLater(
        h.repo.deactivate('..'),
        throwsA(isA<UnknownFailure>()),
      );
      expect(
        h.uris,
        isEmpty,
        reason:
            'unguarded, Dio would have sent DELETE /api/v1/salons/$_salonId/ '
            '— one trailing slash from SalonController.java:208, which '
            'deletes the entire salon',
      );
    });

    // ── GET (list) and POST (bulk) — the S3 sibling sites ──────────────────
    //
    // Same helper, same corpus: the fix is ONE `_pathSegment` encoder shared
    // by all three raw paths, so all three are pinned the same way. A fix
    // applied only to the DELETE would leave these RED.

    for (final injected in rejected) {
      test(
        'list GET: salonId ${injected.isEmpty ? '<empty>' : '"$injected"'} is '
        'REJECTED and NO request is issued',
        () async {
          // A `''` salonId is caught one layer earlier by
          // `_assertAuthenticated` (UnauthorizedFailure), which is also a
          // rejection before any request — assert on the shared invariant
          // (nothing flew) rather than pinning which guard won.
          final h = probe(salonId: injected);

          await expectLater(h.repo.listMyServices(), throwsA(isA<Failure>()));
          expect(h.uris, isEmpty);
        },
      );

      test(
        'bulkCreate POST: masterId ${injected.isEmpty ? '<empty>' : '"$injected"'} '
        'is REJECTED and NO request is issued',
        () async {
          final h = probe(masterId: injected);

          await expectLater(
            h.repo.bulkCreate(const <MasterServiceBulkItem>[
              MasterServiceBulkItem(
                serviceTypeId: 'type-fixed',
                durationMinutes: 60,
                priceType: ServicePriceType.fixed,
                price: 500,
              ),
            ]),
            throwsA(isA<Failure>()),
          );
          expect(h.uris, isEmpty);
        },
      );
    }

    test('list GET: a masterId that merely CONTAINS dot-segments '
        '("a/../../b") still flies, as ONE segment', () async {
      final h = probe(masterId: 'a/../../b');

      await h.repo.listMyServices();

      expect(h.uris.single.pathSegments, <String>[
        'api',
        'v1',
        'salons',
        _salonId,
        'masters',
        'a/../../b',
        'services',
      ]);
    });

    test('bulkCreate POST: a salonId that merely CONTAINS dot-segments '
        '("a/../../b") still flies, as ONE segment', () async {
      final h = probe(salonId: 'a/../../b');

      await h.repo.bulkCreate(const <MasterServiceBulkItem>[
        MasterServiceBulkItem(
          serviceTypeId: 'type-fixed',
          durationMinutes: 60,
          priceType: ServicePriceType.fixed,
          price: 500,
        ),
      ]);

      expect(h.uris.single.pathSegments, <String>[
        'api',
        'v1',
        'salons',
        'a/../../b',
        'masters',
        _salonMasterId,
        'services',
        'bulk',
      ]);
    });

    // ── The null-target branch is untouched ────────────────────────────────

    // ── The null-target branch is BYTE-IDENTICAL (phase 316 D1) ────────────
    //
    // `_pathSegment` guards the THREE hand-built raw paths only. The
    // null-target `deactivate` goes through the generated
    // `ServiceControllerApi`, is untouched by this change, and stays so.
    //
    // ⚠️ ADJACENT, PRE-EXISTING, OUT OF SCOPE — reported, not fixed here.
    // Measured while writing this group: the generated client does NOT
    // percent-encode its path params either, so `deactivate('..')` on a null
    // target puts `DELETE /api/v1/` on the wire (verified: pathSegments comes
    // back as ['api','v1','']). That is harmless — no endpoint matches, and
    // `..` cannot reach a delete-something-bigger route the way the salon
    // path's `/salons/{id}/` prefix could — but it is the SAME root cause on
    // every generated call in `lib/api/`, which is generated code this phase
    // is forbidden to edit. Deliberately NOT pinned as expected behaviour: a
    // test asserting `/api/v1/` is correct would cement the bug.
    test('null target: a well-formed serviceDefId still produces the '
        'unchanged DELETE /api/v1/services/{id}', () async {
      final dio = Dio(BaseOptions(baseUrl: _baseUrl));
      final uris = <Uri>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            uris.add(options.uri);
            handler.resolve(
              Response<Object?>(
                requestOptions: options,
                statusCode: 200,
                data: _okVoid,
              ),
            );
          },
        ),
      );
      final repo = HttpServiceRepository(
        serviceApi: ServiceControllerApi(dio, standardSerializers),
        categoryApi: CategoryRequestControllerApi(dio, standardSerializers),
        catalogApi: ServiceCatalogControllerApi(dio, standardSerializers),
        dio: dio,
        masterId: _masterId,
        sessionUserId: 'user-row-uuid',
      );

      await repo.deactivate(_serviceDefId);

      expect(
        uris.single.pathSegments,
        <String>['api', 'v1', 'services', _serviceDefId],
        reason:
            'phase 316 D1 — the null-target branch is byte-identical and '
            'never routes through _pathSegment',
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

    // The deliberate EXCEPTION to the guard, and the reason it is asserted
    // rather than assumed: getMasterServices hits the PUBLIC endpoint keyed on
    // its own masterId PATH PARAM, so it must keep working when the OWNER id
    // is empty — the CLIENT-safe provider passes '' (see
    // `service_repository.dart`'s comment on the missing `_assertAuthenticated`
    // call). Adding the guard "for consistency" would break every client-side
    // public master profile, and nothing before this test would have caught it.
    test('getMasterServices with empty masterId still reaches the socket '
        '(PUBLIC endpoint — path param, not the JWT principal)', () async {
      final dio = Dio(BaseOptions(baseUrl: _baseUrl));
      dio.interceptors.add(ErrorMapperInterceptor());
      final adapter = DioAdapter(dio: dio);
      final repo = HttpServiceRepository(
        serviceApi: ServiceControllerApi(dio, standardSerializers),
        categoryApi: CategoryRequestControllerApi(dio, standardSerializers),
        catalogApi: ServiceCatalogControllerApi(dio, standardSerializers),
        dio: dio,
        masterId: '',
      );
      adapter.onGet(
        '/api/v1/masters/$_masterId/services',
        (s) => s.reply(200, _listEnvelope()),
      );

      final list = await repo.getMasterServices(_masterId);

      expect(list, hasLength(1));
      expect(list.first.id, _assignmentId);
    });
  });
}
