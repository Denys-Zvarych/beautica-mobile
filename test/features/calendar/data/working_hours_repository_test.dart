// Phase 6.1 — Unit tests for [HttpWorkingHoursRepository] + [WorkingHoursMapper].
//
// Strategy:
//   - Mock [MasterControllerApi] with mocktail (same harness as the master repo
//     tests); construct [HttpWorkingHoursRepository] directly with a fixed
//     masterId so no ProviderScope is needed.
//   - list()       — PERF M1: reads the injected `cachedWeek` directly (the
//                    working hours already carried on the cached Master
//                    profile) and makes NO network call. The gap-filling that
//                    used to live on the read path now happens at profile-
//                    mapping time, exercised by the "PERF M1" cases in
//                    master_repository_test.dart's getMyProfile group.
//   - replaceAll() — asserts the ENTIRE week is sent via upsertWorkingHours and
//                    the saved response is mapped (and gap-filled) back.
//   - error mapping — a 400 (server-side validation) pre-mapped onto
//                     DioException.error by the ErrorMapperInterceptor surfaces
//                     as a ValidationFailure.
//
// Pure Dart: no ProviderScope, no widget tree.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/calendar/data/working_hours_repository.dart';
import 'package:beautica_mobile/features/calendar/domain/working_hours.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockMasterControllerApi extends Mock implements MasterControllerApi {}

const _masterId = 'master-1';
const _path = '/api/v1/masters/$_masterId/working-hours';

/// Builds a [WorkingHoursResponse] for the given ISO [day].
WorkingHoursResponse _whResponse(
  int day, {
  String start = '09:00:00',
  String end = '18:00:00',
  bool active = true,
}) =>
    (WorkingHoursResponseBuilder()
          ..dayOfWeek = day
          ..startTime = start
          ..endTime = end
          ..isActive = active)
        .build();

/// Wraps a saved [workingHours] list in the upsertWorkingHours envelope.
Response<ApiResponseListWorkingHoursResponse> _savedEnvelope(
  Iterable<WorkingHoursResponse> workingHours,
) {
  final envelope = ApiResponseListWorkingHoursResponse(
    (b) => b
      ..data.replace(workingHours)
      ..success = true,
  );
  return Response<ApiResponseListWorkingHoursResponse>(
    data: envelope,
    requestOptions: RequestOptions(path: _path),
    statusCode: 200,
  );
}

void main() {
  late _MockMasterControllerApi masterApi;
  late HttpWorkingHoursRepository repository;

  setUpAll(() {
    registerFallbackValue(BuiltList<WorkingHoursRequest>());
  });

  setUp(() {
    masterApi = _MockMasterControllerApi();
    repository = HttpWorkingHoursRepository(
      masterApi: masterApi,
      masterId: _masterId,
      cachedWeek: const [],
    );
  });

  group('list — reads the cached week, no network call (PERF M1)', () {
    test('returns the injected cached week verbatim', () async {
      // The dense, gap-filled week the master profile already carries — the
      // mapper produced this at profile-mapping time, so list() just returns it.
      final cached = [
        for (var day = 1; day <= 7; day++) _domainDay(day, active: day <= 5),
      ];
      final repo = HttpWorkingHoursRepository(
        masterApi: masterApi,
        masterId: _masterId,
        cachedWeek: cached,
      );

      final week = await repo.list();

      expect(week, same(cached), reason: 'returns the cached week directly');
      expect(week, hasLength(7));
      expect(week.map((w) => w.dayOfWeek), [1, 2, 3, 4, 5, 6, 7]);
      expect(week.take(5).every((w) => w.isActive), isTrue);
      expect(week[5].isActive, isFalse);
      expect(week[6].isActive, isFalse);
    });

    test('never calls getMyProfile (PERF M1 — no second round-trip)', () async {
      final repo = HttpWorkingHoursRepository(
        masterApi: masterApi,
        masterId: _masterId,
        cachedWeek: [_domainDay(1)],
      );

      await repo.list();

      verifyNever(() => masterApi.getMyProfile());
    });

    test('empty cached week (profile not resolved) → empty list', () async {
      // setUp's repository is constructed with an empty cached week.
      final week = await repository.list();

      expect(week, isEmpty);
      verifyNever(() => masterApi.getMyProfile());
    });
  });

  group('replaceAll — sends the entire week', () {
    test('PATCHes the full array via upsertWorkingHours', () async {
      final outgoing = [
        for (var day = 1; day <= 7; day++) _domainDay(day, active: day <= 5),
      ];

      when(
        () => masterApi.upsertWorkingHours(
          masterId: any(named: 'masterId'),
          workingHoursRequest: any(named: 'workingHoursRequest'),
        ),
      ).thenAnswer(
        (_) async =>
            _savedEnvelope([for (var d = 1; d <= 7; d++) _whResponse(d)]),
      );

      await repository.replaceAll(outgoing);

      final captured =
          verify(
                () => masterApi.upsertWorkingHours(
                  masterId: _masterId,
                  workingHoursRequest: captureAny(named: 'workingHoursRequest'),
                ),
              ).captured.single
              as BuiltList<WorkingHoursRequest>;

      expect(
        captured,
        hasLength(7),
        reason: 'the whole week must be sent atomically, not one day',
      );
      expect(captured.map((r) => r.dayOfWeek), [1, 2, 3, 4, 5, 6, 7]);
      // Domain isActive flags must survive the mapping.
      expect(captured.map((r) => r.isActive), [
        true,
        true,
        true,
        true,
        true,
        false,
        false,
      ]);
      // Wire times must survive the mapping.
      expect(captured.first.startTime, '09:00:00');
      expect(captured.first.endTime, '18:00:00');
    });

    test('maps the saved response back to a 7-entry week', () async {
      when(
        () => masterApi.upsertWorkingHours(
          masterId: any(named: 'masterId'),
          workingHoursRequest: any(named: 'workingHoursRequest'),
        ),
      ).thenAnswer(
        // Server echoes only the 3 active days it persisted.
        (_) async =>
            _savedEnvelope([_whResponse(1), _whResponse(2), _whResponse(3)]),
      );

      final saved = await repository.replaceAll([_domainDay(1)]);

      expect(saved, hasLength(7), reason: 'response is gap-filled to 7 too');
      expect(saved.where((w) => w.isActive), hasLength(3));
    });
  });

  group('replaceAll — error mapping', () {
    test('400 pre-mapped to ValidationFailure is surfaced', () async {
      // The ErrorMapperInterceptor maps a 400 working-hours validation envelope
      // (e.g. endTime before startTime) to a ValidationFailure and attaches it
      // to DioException.error; the repo must re-throw it unchanged.
      const mapped = ValidationFailure(
        fieldErrors: {'workingHours[0].endTime': 'must be after startTime'},
      );
      when(
        () => masterApi.upsertWorkingHours(
          masterId: any(named: 'masterId'),
          workingHoursRequest: any(named: 'workingHoursRequest'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _path),
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: _path),
            statusCode: 400,
          ),
          error: mapped,
        ),
      );

      await expectLater(
        repository.replaceAll([_domainDay(1)]),
        throwsA(same(mapped)),
      );
    });

    test('connectionError → NetworkFailure', () async {
      when(
        () => masterApi.upsertWorkingHours(
          masterId: any(named: 'masterId'),
          workingHoursRequest: any(named: 'workingHoursRequest'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _path),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        repository.replaceAll([_domainDay(1)]),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test(
      'badResponse 500 (no pre-mapped error) → ServerFailure(500)',
      () async {
        when(
          () => masterApi.upsertWorkingHours(
            masterId: any(named: 'masterId'),
            workingHoursRequest: any(named: 'workingHoursRequest'),
          ),
        ).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: _path),
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: _path),
              statusCode: 500,
            ),
          ),
        );

        await expectLater(
          repository.replaceAll([_domainDay(1)]),
          throwsA(
            isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 500),
          ),
        );
      },
    );
  });

  group('replaceAll — auth guard', () {
    test('empty masterId → UnauthorizedFailure, no API call', () async {
      final unauthRepo = HttpWorkingHoursRepository(
        masterApi: masterApi,
        masterId: '',
        cachedWeek: const [],
      );

      await expectLater(
        unauthRepo.replaceAll([_domainDay(1)]),
        throwsA(isA<UnauthorizedFailure>()),
      );

      verifyNever(
        () => masterApi.upsertWorkingHours(
          masterId: any(named: 'masterId'),
          workingHoursRequest: any(named: 'workingHoursRequest'),
        ),
      );
    });
  });
}

/// Builds a domain [WorkingHours] for the given ISO [day] with the default
/// 09:00–18:00 window.
WorkingHours _domainDay(int day, {bool active = true}) => WorkingHours(
  dayOfWeek: day,
  startTime: '09:00:00',
  endTime: '18:00:00',
  isActive: active,
);
