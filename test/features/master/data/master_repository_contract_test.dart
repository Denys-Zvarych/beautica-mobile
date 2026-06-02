// Contract-drift regression net (2026-06-02) — master profile, NEGATIVE half.
//
// WHY THIS FILE EXISTS
// --------------------
// This is the exact surface where the "save profile → nothing persists" bug
// lived. master_repository_transport_test.dart covers the POSITIVE paths (real
// wire body, real success deserialization). It does NOT install the production
// ErrorMapperInterceptor, so it cannot prove the FAILURE contract: that a
// 4xx/5xx/network response becomes the right typed Failure the screens branch on.
//
// This file fills that half. It wires a REAL Dio carrying the production
// [ErrorMapperInterceptor], the REAL generated MasterControllerApi, and the REAL
// [HttpMasterRepository] over a faked socket — then drives every realistic server
// failure through updateMyProfile / updateLocality / getMyProfile and asserts the
// mapped Failure. A raw DioException escaping, or the wrong subtype, fails here.
//
// Runs headless in CI:
//   flutter test test/features/master/data/master_repository_contract_test.dart

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/error_mapper_interceptor.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master_update.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

const _baseUrl = 'http://localhost:8080';
const _profilePath = '/api/v1/independent-masters/me/profile';
const _localityPath = '/api/v1/independent-masters/me';
const _getMePath = '/api/v1/masters/me';

const _validUpdate = MasterUpdate(
  firstName: 'Аня',
  lastName: 'Коваль',
  bio: 'bio',
  contactPhone: '+380501234567',
  instagram: '@x',
);

({Dio dio, DioAdapter adapter, HttpMasterRepository repo}) _wire() {
  final dio = Dio(
    BaseOptions(
      baseUrl: _baseUrl,
      headers: const <String, dynamic>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ),
  );
  dio.interceptors.add(ErrorMapperInterceptor());
  final adapter = DioAdapter(dio: dio);
  final repo = HttpMasterRepository(
    dio,
    MasterControllerApi(dio, standardSerializers),
  );
  return (dio: dio, adapter: adapter, repo: repo);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  // updateMyProfile — the profile-save bug surface
  // =========================================================================
  group('updateMyProfile — failure contract', () {
    test(
      'NEGATIVE: 400 field errors → ValidationFailure carrying fieldErrors',
      () async {
        final h = _wire();
        h.adapter.onPatch(
          _profilePath,
          (s) => s.reply(400, {
            'success': false,
            'errors': {'firstName': 'must not be blank'},
          }),
          data: Matchers.any,
        );

        await expectLater(
          h.repo.updateMyProfile(_validUpdate),
          throwsA(
            isA<ValidationFailure>().having(
              (f) => f.fieldErrors['firstName'],
              'fieldErrors[firstName]',
              'must not be blank',
            ),
          ),
        );
      },
    );

    test('NEGATIVE: 400 with EMPTY errors map → ValidationFailure empty map '
        '(the durable guard against a silent dead Save)', () async {
      final h = _wire();
      h.adapter.onPatch(
        _profilePath,
        (s) => s.reply(400, {'success': false, 'message': 'Bad request'}),
        data: Matchers.any,
      );

      await expectLater(
        h.repo.updateMyProfile(_validUpdate),
        throwsA(
          isA<ValidationFailure>().having(
            (f) => f.fieldErrors,
            'fieldErrors',
            isEmpty,
          ),
        ),
      );
    });

    test('NEGATIVE: 401 → UnauthorizedFailure', () async {
      final h = _wire();
      h.adapter.onPatch(
        _profilePath,
        (s) => s.reply(401, {'message': 'unauth'}),
        data: Matchers.any,
      );

      await expectLater(
        h.repo.updateMyProfile(_validUpdate),
        throwsA(isA<UnauthorizedFailure>()),
      );
    });

    test('NEGATIVE: 404 → NotFoundFailure', () async {
      final h = _wire();
      h.adapter.onPatch(
        _profilePath,
        (s) => s.reply(404, {'message': 'not found'}),
        data: Matchers.any,
      );

      await expectLater(
        h.repo.updateMyProfile(_validUpdate),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test('NEGATIVE: 500 → ServerFailure(500)', () async {
      final h = _wire();
      h.adapter.onPatch(
        _profilePath,
        (s) => s.reply(500, {'message': 'boom'}),
        data: Matchers.any,
      );

      await expectLater(
        h.repo.updateMyProfile(_validUpdate),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('NEGATIVE: connection timeout → NetworkFailure', () async {
      final h = _wire();
      h.adapter.onPatch(
        _profilePath,
        (s) => s.throws(
          408,
          DioException.connectionTimeout(
            timeout: const Duration(seconds: 1),
            requestOptions: RequestOptions(path: _profilePath),
          ),
        ),
        data: Matchers.any,
      );

      await expectLater(
        h.repo.updateMyProfile(_validUpdate),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });

  // =========================================================================
  // updateLocality — failure contract
  // =========================================================================
  group('updateLocality — failure contract', () {
    test('NEGATIVE: 400 field errors → ValidationFailure', () async {
      final h = _wire();
      h.adapter.onPatch(
        _localityPath,
        (s) => s.reply(400, {
          'success': false,
          'errors': {'cityId': 'must not be null'},
        }),
        data: Matchers.any,
      );

      await expectLater(
        h.repo.updateLocality(cityId: 'c', street: 'St', buildingNo: '1'),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('NEGATIVE: 500 → ServerFailure(500)', () async {
      final h = _wire();
      h.adapter.onPatch(
        _localityPath,
        (s) => s.reply(500, {'message': 'boom'}),
        data: Matchers.any,
      );

      await expectLater(
        h.repo.updateLocality(cityId: 'c', street: 'St', buildingNo: '1'),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('NEGATIVE: connection error → NetworkFailure', () async {
      final h = _wire();
      h.adapter.onPatch(
        _localityPath,
        (s) => s.throws(
          0,
          DioException.connectionError(
            requestOptions: RequestOptions(path: _localityPath),
            reason: 'closed',
          ),
        ),
        data: Matchers.any,
      );

      await expectLater(
        h.repo.updateLocality(cityId: 'c', street: 'St', buildingNo: '1'),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });

  // =========================================================================
  // getMyProfile — failure contract (profile screen load path)
  // =========================================================================
  group('getMyProfile — failure contract', () {
    test('NEGATIVE: 401 → UnauthorizedFailure', () async {
      final h = _wire();
      h.adapter.onGet(_getMePath, (s) => s.reply(401, {'message': 'unauth'}));

      await expectLater(
        h.repo.getMyProfile('master-1'),
        throwsA(isA<UnauthorizedFailure>()),
      );
    });

    test('NEGATIVE: 404 → NotFoundFailure', () async {
      final h = _wire();
      h.adapter.onGet(_getMePath, (s) => s.reply(404, {'message': 'nope'}));

      await expectLater(
        h.repo.getMyProfile('master-1'),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test('NEGATIVE: 500 → ServerFailure(500)', () async {
      final h = _wire();
      h.adapter.onGet(_getMePath, (s) => s.reply(500, {'message': 'boom'}));

      await expectLater(
        h.repo.getMyProfile('master-1'),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('NEGATIVE: network timeout → NetworkFailure', () async {
      final h = _wire();
      h.adapter.onGet(
        _getMePath,
        (s) => s.throws(
          408,
          DioException.receiveTimeout(
            timeout: const Duration(seconds: 1),
            requestOptions: RequestOptions(path: _getMePath),
          ),
        ),
      );

      await expectLater(
        h.repo.getMyProfile('master-1'),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });
}
