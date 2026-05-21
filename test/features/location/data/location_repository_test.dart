// Phase 2.18 — Unit tests for [HttpLocationRepository].
//
// Strategy: mock the [Dio] instance with mocktail and drive the three fetch
// methods. Verifies:
//   1. fetchOblasts maps the envelope's data list → List<Oblast>.
//   2. fetchCities maps including the `hasDistricts` flag (true + false).
//   3. fetchDistricts maps → List<CityDistrict> on the right path.
//   4. A bad-response DioException surfaces as ServerFailure (with status).
//   5. A connectionError DioException surfaces as NetworkFailure.
//   6. A pre-mapped Failure attached as e.error is re-thrown unchanged.
//   7. A malformed envelope (no data list) surfaces as UnknownFailure.
//
// Pure Dart: no ProviderScope, no widget tree.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/location/data/location_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

/// Wraps a backend payload list in the standard `{success, data, message}`
/// envelope and returns it as a Dio [Response].
Response<Map<String, dynamic>> _envelope(
  String path,
  List<Map<String, dynamic>> data,
) {
  return Response<Map<String, dynamic>>(
    requestOptions: RequestOptions(path: path),
    statusCode: 200,
    data: {'success': true, 'data': data, 'message': 'ok'},
  );
}

void main() {
  late _MockDio dio;
  late HttpLocationRepository repository;

  setUp(() {
    dio = _MockDio();
    repository = HttpLocationRepository(dio);
  });

  group('fetchOblasts', () {
    test('maps the envelope data list to List<Oblast>', () async {
      when(
        () => dio.get<Map<String, dynamic>>('/locations/oblasts'),
      ).thenAnswer(
        (_) async => _envelope('/locations/oblasts', [
          {
            'id': 'oblast-uuid-1',
            'katotthCode': 'UA46',
            'nameUk': 'Львівська',
            'nameEn': 'Lvivska',
          },
          {
            'id': 'oblast-uuid-2',
            'katotthCode': 'UA32',
            'nameUk': 'Київська',
            'nameEn': 'Kyivska',
          },
        ]),
      );

      final result = await repository.fetchOblasts();

      expect(result, hasLength(2));
      expect(result.first.id, 'oblast-uuid-1');
      expect(result.first.name, 'Львівська'); // nameUk surfaced as `name`
      expect(result.first.katotthCode, 'UA46');
    });
  });

  group('fetchCities', () {
    test(
      'maps cities including the hasDistricts flag (true + false)',
      () async {
        const oblastId = 'oblast-uuid-1';
        when(
          () => dio.get<Map<String, dynamic>>(
            '/locations/oblasts/$oblastId/cities',
          ),
        ).thenAnswer(
          (_) async => _envelope('/locations/oblasts/$oblastId/cities', [
            {
              'id': 'city-uuid-1',
              'oblastId': oblastId,
              'katotthCode': 'UA4610',
              'nameUk': 'Львів',
              'nameEn': 'Lviv',
              'hasDistricts': true,
            },
            {
              'id': 'city-uuid-2',
              'oblastId': oblastId,
              'katotthCode': 'UA4620',
              'nameUk': 'Дрогобич',
              'nameEn': 'Drohobych',
              'hasDistricts': false,
            },
          ]),
        );

        final result = await repository.fetchCities(oblastId);

        expect(result, hasLength(2));
        expect(result[0].name, 'Львів');
        expect(result[0].hasDistricts, isTrue);
        expect(result[1].name, 'Дрогобич');
        expect(result[1].hasDistricts, isFalse);
        expect(result[0].oblastId, oblastId);
      },
    );
  });

  group('fetchDistricts', () {
    test('maps the districts list on the city path', () async {
      const cityId = 'city-uuid-1';
      when(
        () => dio.get<Map<String, dynamic>>(
          '/locations/cities/$cityId/districts',
        ),
      ).thenAnswer(
        (_) async => _envelope('/locations/cities/$cityId/districts', [
          {
            'id': 'district-uuid-1',
            'cityId': cityId,
            'katotthCode': 'UA4610136',
            'nameUk': 'Галицький',
            'nameEn': 'Halytskyi',
          },
        ]),
      );

      final result = await repository.fetchDistricts(cityId);

      expect(result, hasLength(1));
      expect(result.single.name, 'Галицький');
      expect(result.single.cityId, cityId);
    });
  });

  group('error mapping', () {
    test(
      'bad-response DioException → ServerFailure with status code',
      () async {
        when(
          () => dio.get<Map<String, dynamic>>('/locations/oblasts'),
        ).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: '/locations/oblasts'),
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: '/locations/oblasts'),
              statusCode: 500,
            ),
          ),
        );

        await expectLater(
          repository.fetchOblasts(),
          throwsA(
            isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 500),
          ),
        );
      },
    );

    test('connectionError DioException → NetworkFailure', () async {
      when(() => dio.get<Map<String, dynamic>>('/locations/oblasts')).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/locations/oblasts'),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        repository.fetchOblasts(),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('pre-mapped Failure on e.error is re-thrown unchanged', () async {
      const mapped = NotFoundFailure();
      when(() => dio.get<Map<String, dynamic>>('/locations/oblasts')).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/locations/oblasts'),
          type: DioExceptionType.badResponse,
          error: mapped,
        ),
      );

      await expectLater(repository.fetchOblasts(), throwsA(same(mapped)));
    });

    test('malformed envelope (no data list) → UnknownFailure', () async {
      when(
        () => dio.get<Map<String, dynamic>>('/locations/oblasts'),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/locations/oblasts'),
          statusCode: 200,
          data: const {'success': true, 'data': null, 'message': 'ok'},
        ),
      );

      await expectLater(
        repository.fetchOblasts(),
        throwsA(isA<UnknownFailure>()),
      );
    });
  });
}
