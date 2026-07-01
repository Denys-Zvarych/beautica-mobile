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
import 'package:beautica_mobile/features/master/domain/master_update.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

class _MockMasterControllerApi extends Mock implements MasterControllerApi {}

const _patchPath = '/api/v1/independent-masters/me';
const _profilePatchPath = '/api/v1/independent-masters/me/profile';
const _getMasterPath = '/masters/master-1';

Response<Map<String, dynamic>> _okEnvelope() => Response<Map<String, dynamic>>(
  requestOptions: RequestOptions(path: _patchPath),
  statusCode: 200,
  data: const {'success': true, 'data': <String, dynamic>{}, 'message': 'ok'},
);

Response<Map<String, dynamic>> _okProfileEnvelope() =>
    Response<Map<String, dynamic>>(
      requestOptions: RequestOptions(path: _profilePatchPath),
      statusCode: 200,
      data: const {
        'success': true,
        'data': <String, dynamic>{},
        'message': 'ok',
      },
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
        () => masterApi.getMyProfile(),
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

    test(
      'Phase 6.2: working hours are NO LONGER bundled on the profile — '
      'Master.workingHours is always empty (read via weekly-schedule API)',
      () async {
        // Post-migration the deprecated bundled working-hours DTO is no longer
        // mapped: the calendar feature reads the week over the network via
        // getWeeklySchedules. The mapper must therefore leave Master.workingHours
        // empty regardless of the profile envelope, so no deprecated DTO crosses
        // the mapping boundary.
        final dto = buildDto();
        when(
          () => masterApi.getMyProfile(),
        ).thenAnswer((_) async => apiResponse(dto));

        final master = await repository.getMyProfile('master-1');

        expect(
          master.workingHours,
          isEmpty,
          reason:
              'working hours are read separately via the weekly-schedule API; '
              'the profile mapper must not populate them',
        );
      },
    );

    test('success: salonOwner type is mapped correctly', () async {
      final dto = buildDto(
        masterId: 'master-2',
        masterType: MasterDetailResponseMasterTypeEnum.SALON_OWNER,
      );
      when(() => masterApi.getMyProfile()).thenAnswer(
        (_) async => Response<ApiResponseMasterDetailResponse>(
          data: ApiResponseMasterDetailResponse(
            (b) => b
              ..data.replace(dto)
              ..success = true,
          ),
          requestOptions: RequestOptions(path: '/masters/me'),
          statusCode: 200,
        ),
      );

      final master = await repository.getMyProfile('master-2');

      expect(master.type, MasterType.salonOwner);
    });

    test('success: salonMaster type is mapped correctly', () async {
      // The SALON_MASTER wire enum maps to MasterType.salonMaster — the
      // remaining branch in MasterMapper._masterTypeFromDto (the independentMaster
      // and salonOwner branches are already covered above).
      final dto = buildDto(
        masterId: 'master-3',
        masterType: MasterDetailResponseMasterTypeEnum.SALON_MASTER,
      );
      when(
        () => masterApi.getMyProfile(),
      ).thenAnswer((_) async => apiResponse(dto));

      final master = await repository.getMyProfile('master-3');

      expect(master.type, MasterType.salonMaster);
    });

    test('mapper throws ServerFailure(null) when DTO masterId is null', () async {
      // A null masterId signals a broken backend contract. MasterMapper.fromDto
      // throws const ServerFailure(statusCode: null); the repository's
      // `on Failure { rethrow }` arm must let it pass through unchanged (not be
      // re-wrapped as a generic ServerFailure with a cause).
      final dto =
          (MasterDetailResponseBuilder()
                // masterId intentionally left unset → null in the built DTO.
                ..firstName = 'Оля'
                ..lastName = 'Коваль'
                ..avgRating = 4.5
                ..reviewCount = 10
                ..masterType =
                    MasterDetailResponseMasterTypeEnum.INDEPENDENT_MASTER)
              .build();
      when(
        () => masterApi.getMyProfile(),
      ).thenAnswer((_) async => apiResponse(dto));

      await expectLater(
        repository.getMyProfile('master-1'),
        throwsA(
          isA<ServerFailure>()
              .having((f) => f.statusCode, 'statusCode', isNull)
              .having((f) => f.cause, 'cause', isNull),
        ),
      );
    });

    test(
      'getMyProfile throws ServerFailure(null) when envelope data is null',
      () async {
        // The API envelope deserialized but carried no `data` payload
        // (res.data?.data == null). The repository must surface this as
        // ServerFailure(statusCode: null) BEFORE reaching the mapper.
        when(() => masterApi.getMyProfile()).thenAnswer(
          (_) async => Response<ApiResponseMasterDetailResponse>(
            data: ApiResponseMasterDetailResponse((b) => b..success = true),
            requestOptions: RequestOptions(path: _getMasterPath),
            statusCode: 200,
          ),
        );

        await expectLater(
          repository.getMyProfile('master-1'),
          throwsA(
            isA<ServerFailure>()
                .having((f) => f.statusCode, 'statusCode', isNull)
                .having((f) => f.cause, 'cause', isNull),
          ),
        );
      },
    );

    test(
      'street, buildingNo and locationNote round-trip from DTO to Master',
      () async {
        final dto =
            (MasterDetailResponseBuilder()
                  ..masterId = 'master-1'
                  ..firstName = 'Оля'
                  ..lastName = 'Коваль'
                  ..avgRating = 4.5
                  ..reviewCount = 10
                  ..masterType =
                      MasterDetailResponseMasterTypeEnum.INDEPENDENT_MASTER
                  ..street = 'вул. Хрещатик'
                  ..buildingNo = '12А'
                  ..locationNote = 'кв. 3, 2 поверх')
                .build();

        when(
          () => masterApi.getMyProfile(),
        ).thenAnswer((_) async => apiResponse(dto));

        final master = await repository.getMyProfile('master-1');

        expect(master.street, 'вул. Хрещатик');
        expect(master.buildingNo, '12А');
        expect(master.locationNote, 'кв. 3, 2 поверх');
      },
    );

    test('DioException connectionError → NetworkFailure', () async {
      when(() => masterApi.getMyProfile()).thenThrow(
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
      when(() => masterApi.getMyProfile()).thenThrow(
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
      when(() => masterApi.getMyProfile()).thenThrow(
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

    test('phoneNumber forwarded to Master when set in DTO', () async {
      final dto =
          (MasterDetailResponseBuilder()
                ..masterId = 'master-1'
                ..firstName = 'Оля'
                ..lastName = 'Коваль'
                ..avgRating = 4.5
                ..reviewCount = 10
                ..masterType =
                    MasterDetailResponseMasterTypeEnum.INDEPENDENT_MASTER
                ..phoneNumber = '+380501111111')
              .build();

      when(
        () => masterApi.getMyProfile(),
      ).thenAnswer((_) async => apiResponse(dto));

      final master = await repository.getMyProfile('master-1');

      expect(
        master.phoneNumber,
        '+380501111111',
        reason: 'phoneNumber from DTO must be forwarded to the Master entity',
      );
    });

    test('phoneNumber is null on Master when DTO has no phoneNumber', () async {
      // buildDto() does not set phoneNumber — it remains null in the DTO.
      final dto = buildDto();

      when(
        () => masterApi.getMyProfile(),
      ).thenAnswer((_) async => apiResponse(dto));

      final master = await repository.getMyProfile('master-1');

      expect(
        master.phoneNumber,
        isNull,
        reason:
            'phoneNumber must be null on Master when the DTO omits phoneNumber',
      );
    });

    test('instagram forwarded to Master when set in DTO', () async {
      final dto =
          (MasterDetailResponseBuilder()
                ..masterId = 'master-1'
                ..firstName = 'Оля'
                ..lastName = 'Коваль'
                ..avgRating = 4.5
                ..reviewCount = 10
                ..masterType =
                    MasterDetailResponseMasterTypeEnum.INDEPENDENT_MASTER
                ..instagram = '@test_handle')
              .build();

      when(
        () => masterApi.getMyProfile(),
      ).thenAnswer((_) async => apiResponse(dto));

      final master = await repository.getMyProfile('master-1');

      expect(
        master.instagram,
        '@test_handle',
        reason: 'instagram from DTO must be forwarded to the Master entity',
      );
    });

    test('instagram is null on Master when DTO has no instagram', () async {
      // buildDto() does not set instagram — it remains null in the DTO.
      final dto = buildDto();

      when(
        () => masterApi.getMyProfile(),
      ).thenAnswer((_) async => apiResponse(dto));

      final master = await repository.getMyProfile('master-1');

      expect(
        master.instagram,
        isNull,
        reason: 'instagram must be null on Master when the DTO omits instagram',
      );
    });
  });

  group('updateMyProfile', () {
    // ── A — correct endpoint ────────────────────────────────────────────────

    test('PATCHes /independent-masters/me/profile (not /me)', () async {
      when(
        () => dio.patch<Map<String, dynamic>>(
          _profilePatchPath,
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => _okProfileEnvelope());

      await repository.updateMyProfile(
        const MasterUpdate(
          firstName: 'Аня',
          lastName: 'Коваль',
          bio: '',
          contactPhone: '',
          instagram: '',
        ),
      );

      verify(
        () => dio.patch<Map<String, dynamic>>(
          _profilePatchPath,
          data: any(named: 'data'),
        ),
      ).called(1);

      verifyNever(
        () => dio.patch<Map<String, dynamic>>(
          _patchPath,
          data: any(named: 'data'),
        ),
      );
    });

    // ── B — phoneNumber field name (not contactPhone) ───────────────────────

    test('sends phoneNumber (not contactPhone) in request body', () async {
      when(
        () => dio.patch<Map<String, dynamic>>(
          _profilePatchPath,
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => _okProfileEnvelope());

      await repository.updateMyProfile(
        const MasterUpdate(
          firstName: 'Аня',
          lastName: 'Коваль',
          bio: '',
          contactPhone: '+380501111111',
          instagram: '',
        ),
      );

      final captured =
          verify(
                () => dio.patch<Map<String, dynamic>>(
                  _profilePatchPath,
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;

      expect(
        captured.containsKey('phoneNumber'),
        isTrue,
        reason: 'request body must use the backend field name "phoneNumber"',
      );
      expect(
        captured.containsKey('contactPhone'),
        isFalse,
        reason:
            'contactPhone is the Dart param name — must not leak into the body',
      );
      expect(
        captured['phoneNumber'],
        '+380501111111',
        reason: 'phoneNumber value must match the supplied contactPhone',
      );
    });

    // ── C — blank contactPhone is omitted ───────────────────────────────────

    test('omits phoneNumber when contactPhone is blank', () async {
      when(
        () => dio.patch<Map<String, dynamic>>(
          _profilePatchPath,
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => _okProfileEnvelope());

      await repository.updateMyProfile(
        const MasterUpdate(
          firstName: 'Аня',
          lastName: 'Коваль',
          bio: '',
          contactPhone: '   ',
          instagram: '',
        ),
      );

      final captured =
          verify(
                () => dio.patch<Map<String, dynamic>>(
                  _profilePatchPath,
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;

      expect(
        captured.containsKey('phoneNumber'),
        isFalse,
        reason:
            'whitespace-only contactPhone must be omitted from the request body',
      );
    });

    // ── E — instagram value included in body when set ──────────────────────

    test('instagram value included in body when set', () async {
      when(
        () => dio.patch<Map<String, dynamic>>(
          _profilePatchPath,
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => _okProfileEnvelope());

      await repository.updateMyProfile(
        const MasterUpdate(
          firstName: 'Аня',
          lastName: 'Коваль',
          bio: '',
          contactPhone: '',
          instagram: '@beauty_ua',
        ),
      );

      final captured =
          verify(
                () => dio.patch<Map<String, dynamic>>(
                  _profilePatchPath,
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;

      expect(
        captured['instagram'],
        '@beauty_ua',
        reason: 'instagram value must be forwarded to the request body',
      );
    });

    // ── F — cleared bio / instagram are sent as '' (NOT omitted) ────────────
    //
    // Backend contract: bio / instagram are persisted whenever the key is
    // non-null, so an empty string clears them. Omitting the key (the old bug)
    // left the stale server value intact. The repo must therefore ALWAYS
    // include both keys, with '' when the user cleared the field.

    test('includes bio and instagram as empty strings when cleared', () async {
      when(
        () => dio.patch<Map<String, dynamic>>(
          _profilePatchPath,
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => _okProfileEnvelope());

      await repository.updateMyProfile(
        const MasterUpdate(
          firstName: 'Аня',
          lastName: 'Коваль',
          bio: '',
          contactPhone: '',
          instagram: '',
        ),
      );

      final captured =
          verify(
                () => dio.patch<Map<String, dynamic>>(
                  _profilePatchPath,
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;

      expect(
        captured.containsKey('bio'),
        isTrue,
        reason:
            'bio key must always be present so a clear persists server-side',
      );
      expect(
        captured['bio'],
        '',
        reason: 'cleared bio must be sent as an empty string, not omitted',
      );
      expect(
        captured.containsKey('instagram'),
        isTrue,
        reason:
            'instagram key must always be present so a clear persists server-side',
      );
      expect(
        captured['instagram'],
        '',
        reason:
            'cleared instagram must be sent as an empty string, not omitted',
      );
    });

    // ── F2 — whitespace-only bio / instagram are trimmed to '' and sent ──────

    test('trims whitespace-only bio / instagram to empty string', () async {
      when(
        () => dio.patch<Map<String, dynamic>>(
          _profilePatchPath,
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => _okProfileEnvelope());

      await repository.updateMyProfile(
        const MasterUpdate(
          firstName: 'Аня',
          lastName: 'Коваль',
          bio: '   ',
          contactPhone: '',
          instagram: '   ',
        ),
      );

      final captured =
          verify(
                () => dio.patch<Map<String, dynamic>>(
                  _profilePatchPath,
                  data: captureAny(named: 'data'),
                ),
              ).captured.single
              as Map<String, dynamic>;

      expect(captured['bio'], '');
      expect(captured['instagram'], '');
    });

    // ── D — connectionError → NetworkFailure ────────────────────────────────

    test('throws NetworkFailure on connectionError', () async {
      when(
        () => dio.patch<Map<String, dynamic>>(
          _profilePatchPath,
          data: any(named: 'data'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _profilePatchPath),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        repository.updateMyProfile(
          const MasterUpdate(
            firstName: 'Аня',
            lastName: 'Коваль',
            bio: '',
            contactPhone: '',
            instagram: '',
          ),
        ),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Totality + bounded one-shot retry (flaky-errUnknown profile-save fix).
  //
  // The screen's `catch (e, st)` → errUnknown arm was reached because a raw
  // TypeError thrown by RefreshInterceptor escaped the repo's old
  // `on DioException`-only catch. `_runIdempotentPatch` now has a TOTAL catch
  // (Failure rethrow → DioException map → final catch → ServerFailure) plus a
  // bounded ONE-SHOT retry for transient UnauthorizedFailure / NetworkFailure.
  // ──────────────────────────────────────────────────────────────────────────

  const profileUpdate = MasterUpdate(
    firstName: 'Аня',
    lastName: 'Коваль',
    bio: '',
    contactPhone: '',
    instagram: '',
  );

  group('updateMyProfile — totality + bounded retry', () {
    test(
      'non-DioException, non-Failure throw (TypeError) is wrapped as ServerFailure',
      () async {
        // Simulates a raw runtime error bubbling from the Dio/interceptor layer
        // (the exact escape path of the original flaky errUnknown bug).
        when(
          () => dio.patch<Map<String, dynamic>>(
            _profilePatchPath,
            data: any(named: 'data'),
          ),
        ).thenThrow(TypeError());

        await expectLater(
          repository.updateMyProfile(profileUpdate),
          throwsA(
            isA<ServerFailure>().having(
              (f) => f.cause,
              'cause',
              isA<TypeError>(),
            ),
          ),
        );

        // A non-retryable raw error must NOT be retried.
        verify(
          () => dio.patch<Map<String, dynamic>>(
            _profilePatchPath,
            data: any(named: 'data'),
          ),
        ).called(1);
      },
    );

    test(
      'transient UnauthorizedFailure on attempt 1 → succeeds on retry (called twice)',
      () async {
        var calls = 0;
        when(
          () => dio.patch<Map<String, dynamic>>(
            _profilePatchPath,
            data: any(named: 'data'),
          ),
        ).thenAnswer((_) async {
          calls++;
          if (calls == 1) {
            // A Failure already produced upstream (e.g. by RefreshInterceptor).
            throw const UnauthorizedFailure(cause: 'transient 401');
          }
          return _okProfileEnvelope();
        });

        await repository.updateMyProfile(profileUpdate);

        verify(
          () => dio.patch<Map<String, dynamic>>(
            _profilePatchPath,
            data: any(named: 'data'),
          ),
        ).called(2);
      },
    );

    test(
      'transient NetworkFailure on attempt 1 → succeeds on retry (called twice)',
      () async {
        var calls = 0;
        when(
          () => dio.patch<Map<String, dynamic>>(
            _profilePatchPath,
            data: any(named: 'data'),
          ),
        ).thenAnswer((_) async {
          calls++;
          if (calls == 1) {
            throw DioException(
              requestOptions: RequestOptions(path: _profilePatchPath),
              type: DioExceptionType.connectionError,
            );
          }
          return _okProfileEnvelope();
        });

        await repository.updateMyProfile(profileUpdate);

        verify(
          () => dio.patch<Map<String, dynamic>>(
            _profilePatchPath,
            data: any(named: 'data'),
          ),
        ).called(2);
      },
    );

    test(
      'persistent UnauthorizedFailure → rethrown after exactly two attempts',
      () async {
        when(
          () => dio.patch<Map<String, dynamic>>(
            _profilePatchPath,
            data: any(named: 'data'),
          ),
        ).thenThrow(const UnauthorizedFailure(cause: 'expired'));

        await expectLater(
          repository.updateMyProfile(profileUpdate),
          throwsA(isA<UnauthorizedFailure>()),
        );

        // Retry is bounded — a genuine auth expiry surfaces, never masked,
        // after the single retry. Exactly two attempts, no more.
        verify(
          () => dio.patch<Map<String, dynamic>>(
            _profilePatchPath,
            data: any(named: 'data'),
          ),
        ).called(2);
      },
    );

    test(
      'non-retryable Failure (ValidationFailure) → rethrown on first attempt, not retried',
      () async {
        when(
          () => dio.patch<Map<String, dynamic>>(
            _profilePatchPath,
            data: any(named: 'data'),
          ),
        ).thenThrow(
          const ValidationFailure(fieldErrors: {'instagram': 'invalid'}),
        );

        await expectLater(
          repository.updateMyProfile(profileUpdate),
          throwsA(isA<ValidationFailure>()),
        );

        verify(
          () => dio.patch<Map<String, dynamic>>(
            _profilePatchPath,
            data: any(named: 'data'),
          ),
        ).called(1);
      },
    );

    test(
      'non-retryable DioException (404 → ServerFailure) → not retried',
      () async {
        when(
          () => dio.patch<Map<String, dynamic>>(
            _profilePatchPath,
            data: any(named: 'data'),
          ),
        ).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: _profilePatchPath),
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: _profilePatchPath),
              statusCode: 404,
            ),
          ),
        );

        await expectLater(
          repository.updateMyProfile(profileUpdate),
          throwsA(
            isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 404),
          ),
        );

        verify(
          () => dio.patch<Map<String, dynamic>>(
            _profilePatchPath,
            data: any(named: 'data'),
          ),
        ).called(1);
      },
    );
  });

  group('updateLocality — totality + bounded retry', () {
    test(
      'transient UnauthorizedFailure on attempt 1 → succeeds on retry (called twice)',
      () async {
        var calls = 0;
        when(
          () => dio.patch<Map<String, dynamic>>(
            _patchPath,
            data: any(named: 'data'),
          ),
        ).thenAnswer((_) async {
          calls++;
          if (calls == 1) {
            throw const UnauthorizedFailure(cause: 'transient 401');
          }
          return _okEnvelope();
        });

        await repository.updateLocality(
          cityId: 'city-1',
          street: 'St.',
          buildingNo: '8',
        );

        verify(
          () => dio.patch<Map<String, dynamic>>(
            _patchPath,
            data: any(named: 'data'),
          ),
        ).called(2);
      },
    );

    test(
      'non-Failure, non-DioException throw (TypeError) → ServerFailure, not retried',
      () async {
        when(
          () => dio.patch<Map<String, dynamic>>(
            _patchPath,
            data: any(named: 'data'),
          ),
        ).thenThrow(TypeError());

        await expectLater(
          repository.updateLocality(
            cityId: 'city-1',
            street: 'St.',
            buildingNo: '8',
          ),
          throwsA(isA<ServerFailure>()),
        );

        verify(
          () => dio.patch<Map<String, dynamic>>(
            _patchPath,
            data: any(named: 'data'),
          ),
        ).called(1);
      },
    );
  });
}
