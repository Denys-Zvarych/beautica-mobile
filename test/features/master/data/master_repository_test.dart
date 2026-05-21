// Phase 2.19 — Unit tests for [HttpMasterRepository.updateLocality].
//
// Mirrors test/features/salon/data/salon_repository_test.dart.
//
// Strategy: mock the [Dio] instance with mocktail and drive `updateLocality`.
// Verifies:
//   1. PATCH /independent-masters/me with the full body when all fields present.
//   2. Body-omission: null/empty/whitespace districtId + locationNote are
//      dropped (not sent as null) — backlog pattern 5.
//   3. Trimmed-value mapping: street / buildingNo / locationNote are trimmed.
//   4. A bad-response DioException surfaces as ServerFailure (with status).
//   5. A connectionError DioException surfaces as NetworkFailure.
//   6. A pre-mapped Failure attached as e.error is re-thrown unchanged.
//
// Pure Dart: no ProviderScope, no widget tree.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

const _path = '/independent-masters/me';

Response<Map<String, dynamic>> _okEnvelope() => Response<Map<String, dynamic>>(
  requestOptions: RequestOptions(path: _path),
  statusCode: 200,
  data: const {'success': true, 'data': <String, dynamic>{}, 'message': 'ok'},
);

void main() {
  late _MockDio dio;
  late HttpMasterRepository repository;

  setUp(() {
    dio = _MockDio();
    repository = HttpMasterRepository(dio);
  });

  group('updateLocality — request body', () {
    test('PATCHes /independent-masters/me with the full body', () async {
      when(
        () => dio.patch<Map<String, dynamic>>(_path, data: any(named: 'data')),
      ).thenAnswer((_) async => _okEnvelope());

      await repository.updateLocality(
        cityId: 'city-1',
        districtId: 'district-1',
        street: 'вул. Хрещатик',
        buildingNo: '12А',
        locationNote: '3 поверх',
      );

      verify(
        () => dio.patch<Map<String, dynamic>>(
          _path,
          data: {
            'cityId': 'city-1',
            'street': 'вул. Хрещатик',
            'buildingNo': '12А',
            'districtId': 'district-1',
            'locationNote': '3 поверх',
          },
        ),
      ).called(1);
    });

    test('omits null districtId and null locationNote', () async {
      when(
        () => dio.patch<Map<String, dynamic>>(_path, data: any(named: 'data')),
      ).thenAnswer((_) async => _okEnvelope());

      await repository.updateLocality(
        cityId: 'city-2',
        districtId: null,
        street: 'St.',
        buildingNo: '8',
        locationNote: null,
      );

      final captured =
          verify(
                () => dio.patch<Map<String, dynamic>>(
                  _path,
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;

      expect(captured.containsKey('districtId'), isFalse);
      expect(captured.containsKey('locationNote'), isFalse);
      expect(captured['cityId'], 'city-2');
      expect(captured['street'], 'St.');
      expect(captured['buildingNo'], '8');
    });

    test('omits empty / whitespace-only districtId and note', () async {
      when(
        () => dio.patch<Map<String, dynamic>>(_path, data: any(named: 'data')),
      ).thenAnswer((_) async => _okEnvelope());

      await repository.updateLocality(
        cityId: 'city-3',
        districtId: '',
        street: 'St.',
        buildingNo: '8',
        locationNote: '   ',
      );

      final captured =
          verify(
                () => dio.patch<Map<String, dynamic>>(
                  _path,
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;

      expect(captured.containsKey('districtId'), isFalse);
      expect(captured.containsKey('locationNote'), isFalse);
    });

    test('trims street, buildingNo, and locationNote values', () async {
      when(
        () => dio.patch<Map<String, dynamic>>(_path, data: any(named: 'data')),
      ).thenAnswer((_) async => _okEnvelope());

      await repository.updateLocality(
        cityId: 'city-4',
        districtId: 'district-4',
        street: '  вул. Тестова  ',
        buildingNo: '  5  ',
        locationNote: '  домофон  ',
      );

      final captured =
          verify(
                () => dio.patch<Map<String, dynamic>>(
                  _path,
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;

      expect(captured['street'], 'вул. Тестова');
      expect(captured['buildingNo'], '5');
      expect(captured['locationNote'], 'домофон');
    });
  });

  group('updateLocality — error mapping', () {
    test('bad-response DioException → ServerFailure with status', () async {
      when(
        () => dio.patch<Map<String, dynamic>>(_path, data: any(named: 'data')),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _path),
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: _path),
            statusCode: 422,
          ),
        ),
      );

      await expectLater(
        repository.updateLocality(
          cityId: 'city-1',
          street: 'St.',
          buildingNo: '8',
        ),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 422),
        ),
      );
    });

    test('connectionError DioException → NetworkFailure', () async {
      when(
        () => dio.patch<Map<String, dynamic>>(_path, data: any(named: 'data')),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _path),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        repository.updateLocality(
          cityId: 'city-1',
          street: 'St.',
          buildingNo: '8',
        ),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('pre-mapped Failure on e.error is re-thrown unchanged', () async {
      const mapped = ValidationFailure(fieldErrors: {'cityId': 'invalid'});
      when(
        () => dio.patch<Map<String, dynamic>>(_path, data: any(named: 'data')),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _path),
          type: DioExceptionType.badResponse,
          error: mapped,
        ),
      );

      await expectLater(
        repository.updateLocality(
          cityId: 'city-1',
          street: 'St.',
          buildingNo: '8',
        ),
        throwsA(same(mapped)),
      );
    });
  });
}
