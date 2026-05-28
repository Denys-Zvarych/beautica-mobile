// Phase 2.19 — Unit tests for [HttpMasterRepository.updateLocality].
// Phase 4.1 — Added unit tests for [HttpMasterRepository.getMyProfile].
//
// Strategy:
//   updateLocality — mock [Dio] with mocktail; verify PATCH call shape + errors.
//   getMyProfile   — mock [MasterControllerApi] with mocktail; verify domain
//                    mapping and error propagation.
//
// Pure Dart: no ProviderScope, no widget tree.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

class _MockMasterControllerApi extends Mock implements MasterControllerApi {}

const _patchPath = '/independent-masters/me';
const _getMasterPath = '/masters/master-1';

Response<Map<String, dynamic>> _okEnvelope() => Response<Map<String, dynamic>>(
  requestOptions: RequestOptions(path: _patchPath),
  statusCode: 200,
  data: const {'success': true, 'data': <String, dynamic>{}, 'message': 'ok'},
);

void main() {
  late _MockDio dio;
  late _MockMasterControllerApi masterApi;
  late HttpMasterRepository repository;

  setUp(() {
    dio = _MockDio();
    masterApi = _MockMasterControllerApi();
    repository = HttpMasterRepository(dio, masterApi);
  });

  group('updateLocality — request body', () {
    test('PATCHes /independent-masters/me with the full body', () async {
      when(
        () => dio.patch<Map<String, dynamic>>(
          _patchPath,
          data: any(named: 'data'),
        ),
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
          _patchPath,
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
        () => dio.patch<Map<String, dynamic>>(
          _patchPath,
          data: any(named: 'data'),
        ),
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
                  _patchPath,
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
        () => dio.patch<Map<String, dynamic>>(
          _patchPath,
          data: any(named: 'data'),
        ),
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
                  _patchPath,
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;

      expect(captured.containsKey('districtId'), isFalse);
      expect(captured.containsKey('locationNote'), isFalse);
    });

    test('trims street, buildingNo, and locationNote values', () async {
      when(
        () => dio.patch<Map<String, dynamic>>(
          _patchPath,
          data: any(named: 'data'),
        ),
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
                  _patchPath,
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
        () => dio.patch<Map<String, dynamic>>(
          _patchPath,
          data: any(named: 'data'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _patchPath),
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: _patchPath),
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
        () => dio.patch<Map<String, dynamic>>(
          _patchPath,
          data: any(named: 'data'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _patchPath),
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
        () => dio.patch<Map<String, dynamic>>(
          _patchPath,
          data: any(named: 'data'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _patchPath),
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

  group('getMyProfile', () {
    /// Builds a minimal [MasterDetailResponse] DTO for happy-path assertions.
    MasterDetailResponse buildDto({
      String masterId = 'master-1',
      String firstName = 'Оля',
      String lastName = 'Коваль',
      double avgRating = 4.5,
      int reviewCount = 10,
      MasterDetailResponseMasterTypeEnum masterType =
          MasterDetailResponseMasterTypeEnum.INDEPENDENT_MASTER,
    }) =>
        (MasterDetailResponseBuilder()
              ..masterId = masterId
              ..firstName = firstName
              ..lastName = lastName
              ..avgRating = avgRating
              ..reviewCount = reviewCount
              ..masterType = masterType)
            .build();

    Response<ApiResponseMasterDetailResponse> apiResponse(
      MasterDetailResponse dto,
    ) {
      final envelope = ApiResponseMasterDetailResponse(
        (b) => b
          ..data.replace(dto)
          ..success = true,
      );
      return Response<ApiResponseMasterDetailResponse>(
        data: envelope,
        requestOptions: RequestOptions(path: _getMasterPath),
        statusCode: 200,
      );
    }

    test('success: maps MasterDetailResponse to Master', () async {
      final dto = buildDto();
      when(
        () => masterApi.getMasterDetail(masterId: 'master-1'),
      ).thenAnswer((_) async => apiResponse(dto));

      final master = await repository.getMyProfile('master-1');

      expect(master.id, 'master-1');
      expect(master.firstName, 'Оля');
      expect(master.lastName, 'Коваль');
      expect(master.avgRating, 4.5);
      expect(master.reviewCount, 10);
      expect(master.type, MasterType.independentMaster);
      expect(master.salonId, isNull);
    });

    test('success: salonOwner type is mapped correctly', () async {
      final dto = buildDto(
        masterId: 'master-2',
        masterType: MasterDetailResponseMasterTypeEnum.SALON_OWNER,
      );
      when(() => masterApi.getMasterDetail(masterId: 'master-2')).thenAnswer(
        (_) async => Response<ApiResponseMasterDetailResponse>(
          data: ApiResponseMasterDetailResponse(
            (b) => b
              ..data.replace(dto)
              ..success = true,
          ),
          requestOptions: RequestOptions(path: '/masters/master-2'),
          statusCode: 200,
        ),
      );

      final master = await repository.getMyProfile('master-2');

      expect(master.type, MasterType.salonOwner);
    });

    test('DioException connectionError → NetworkFailure', () async {
      when(() => masterApi.getMasterDetail(masterId: 'master-1')).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _getMasterPath),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        repository.getMyProfile('master-1'),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('DioException badResponse 404 → ServerFailure(404)', () async {
      when(() => masterApi.getMasterDetail(masterId: 'master-1')).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _getMasterPath),
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: _getMasterPath),
            statusCode: 404,
          ),
        ),
      );

      await expectLater(
        repository.getMyProfile('master-1'),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 404),
        ),
      );
    });

    test('pre-mapped Failure on e.error is re-thrown unchanged', () async {
      const mapped = UnauthorizedFailure();
      when(() => masterApi.getMasterDetail(masterId: 'master-1')).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _getMasterPath),
          type: DioExceptionType.badResponse,
          error: mapped,
        ),
      );

      await expectLater(
        repository.getMyProfile('master-1'),
        throwsA(same(mapped)),
      );
    });
  });
}
