// Phase 2.19 — Unit tests for [HttpSalonRepository] + [SalonCreateDto].
//
// Strategy: mock the [Dio] instance with mocktail and drive `create`.
// Verifies:
//   1. create POSTs /salons with the full body when all fields are present.
//   2. SalonCreateDto.toJson omits null/empty optionals (districtId, note).
//   3. A bad-response DioException surfaces as ServerFailure (with status).
//   4. A connectionError DioException surfaces as NetworkFailure.
//   5. A pre-mapped Failure attached as e.error is re-thrown unchanged.
//
// Pure Dart: no ProviderScope, no widget tree.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

Response<Map<String, dynamic>> _okEnvelope() => Response<Map<String, dynamic>>(
  requestOptions: RequestOptions(path: '/salons'),
  statusCode: 201,
  data: const {'success': true, 'data': <String, dynamic>{}, 'message': 'ok'},
);

void main() {
  late _MockDio dio;
  late HttpSalonRepository repository;

  setUp(() {
    dio = _MockDio();
    repository = HttpSalonRepository(dio);
  });

  group('SalonCreateDto.toJson', () {
    test('includes all fields when present', () {
      const dto = SalonCreateDto(
        name: 'Salon Lumière',
        cityId: 'city-1',
        districtId: 'district-1',
        street: 'вул. Хрещатик',
        buildingNo: '12А',
        locationNote: '3 поверх',
      );

      expect(dto.toJson(), {
        'name': 'Salon Lumière',
        'cityId': 'city-1',
        'street': 'вул. Хрещатик',
        'buildingNo': '12А',
        'districtId': 'district-1',
        'locationNote': '3 поверх',
      });
    });

    test('omits null/empty districtId and note', () {
      const dto = SalonCreateDto(
        name: 'Salon',
        cityId: 'city-1',
        districtId: null,
        street: 'St.',
        buildingNo: '8',
        locationNote: '   ', // whitespace-only → omitted
      );

      final json = dto.toJson();
      expect(json.containsKey('districtId'), isFalse);
      expect(json.containsKey('locationNote'), isFalse);
      expect(json['name'], 'Salon');
      expect(json['cityId'], 'city-1');
    });
  });

  group('create', () {
    test('POSTs /salons with the DTO body', () async {
      const dto = SalonCreateDto(
        name: 'Salon',
        cityId: 'city-1',
        districtId: 'district-1',
        street: 'St.',
        buildingNo: '8',
      );
      when(
        () => dio.post<Map<String, dynamic>>('/salons', data: dto.toJson()),
      ).thenAnswer((_) async => _okEnvelope());

      await repository.create(dto: dto);

      verify(
        () => dio.post<Map<String, dynamic>>('/salons', data: dto.toJson()),
      ).called(1);
    });

    test('bad-response DioException → ServerFailure with status', () async {
      const dto = SalonCreateDto(
        name: 'Salon',
        cityId: 'city-1',
        street: 'St.',
        buildingNo: '8',
      );
      when(
        () =>
            dio.post<Map<String, dynamic>>('/salons', data: any(named: 'data')),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/salons'),
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: '/salons'),
            statusCode: 422,
          ),
        ),
      );

      await expectLater(
        repository.create(dto: dto),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 422),
        ),
      );
    });

    test('connectionError DioException → NetworkFailure', () async {
      const dto = SalonCreateDto(
        name: 'Salon',
        cityId: 'city-1',
        street: 'St.',
        buildingNo: '8',
      );
      when(
        () =>
            dio.post<Map<String, dynamic>>('/salons', data: any(named: 'data')),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/salons'),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        repository.create(dto: dto),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('pre-mapped Failure on e.error is re-thrown unchanged', () async {
      const dto = SalonCreateDto(
        name: 'Salon',
        cityId: 'city-1',
        street: 'St.',
        buildingNo: '8',
      );
      const mapped = ValidationFailure(fieldErrors: {'name': 'taken'});
      when(
        () =>
            dio.post<Map<String, dynamic>>('/salons', data: any(named: 'data')),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/salons'),
          type: DioExceptionType.badResponse,
          error: mapped,
        ),
      );

      await expectLater(repository.create(dto: dto), throwsA(same(mapped)));
    });
  });
}
