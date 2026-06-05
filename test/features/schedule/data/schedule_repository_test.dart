// Phase 15.1 — Unit tests for [HttpScheduleRepository].
//
// Strategy mirrors working_hours_repository_test.dart: mock MasterControllerApi
// with mocktail, construct the repo directly with a fixed masterId. No
// ProviderScope.
//
// Covers: the bounded-range guard (>366 days throws BEFORE any API call);
// listOverrides multi-row mapping; 400 → ValidationFailure; connectionError →
// NetworkFailure; empty masterId → UnauthorizedFailure (no call).

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockMasterControllerApi extends Mock implements MasterControllerApi {}

const _masterId = 'master-1';
const _path = '/api/v1/masters/$_masterId/effective-schedule';

Response<ApiResponseListScheduleOverrideResponse> _overridesEnvelope(
  Iterable<ScheduleOverrideResponse> rows,
) {
  final envelope = ApiResponseListScheduleOverrideResponse(
    (b) => b
      ..success = true
      ..data.replace(rows),
  );
  return Response<ApiResponseListScheduleOverrideResponse>(
    data: envelope,
    requestOptions: RequestOptions(path: _path),
    statusCode: 200,
  );
}

ScheduleOverrideResponse _dayOffRow(int year, int month, int day) =>
    ScheduleOverrideResponse(
      (b) => b
        ..date = Date(year, month, day)
        ..kind = ScheduleOverrideResponseKindEnum.DAY_OFF
        ..reason = ScheduleOverrideResponseReasonEnum.VACATION,
    );

void main() {
  late _MockMasterControllerApi masterApi;
  late HttpScheduleRepository repository;

  setUpAll(() {
    registerFallbackValue(Date(2026, 1, 1));
  });

  setUp(() {
    masterApi = _MockMasterControllerApi();
    repository = HttpScheduleRepository(
      masterApi: masterApi,
      masterId: _masterId,
    );
  });

  group('bounded-range guard — fails before any API call', () {
    // The guard asserts in debug (test) mode and throws ValidationFailure in
    // release; tests run with asserts ON, so an AssertionError fires first. The
    // contract under audit is "rejects BEFORE any API call" — accept either the
    // debug AssertionError or the release ValidationFailure, and prove no call.
    final rejectsBeforeCall = throwsA(
      anyOf(isA<AssertionError>(), isA<ValidationFailure>()),
    );

    test(
      'effectiveSchedule >366-day range rejects before any API call',
      () async {
        final from = DateTime(2026, 1, 1);
        final to = DateTime(2027, 6, 1); // ~516 days

        await expectLater(
          repository.effectiveSchedule(from, to),
          rejectsBeforeCall,
        );

        verifyNever(
          () => masterApi.getEffectiveSchedule(
            masterId: any(named: 'masterId'),
            from: any(named: 'from'),
            to: any(named: 'to'),
          ),
        );
      },
    );

    test('listOverrides >366-day range rejects before any API call', () async {
      await expectLater(
        repository.listOverrides(DateTime(2026, 1, 1), DateTime(2027, 6, 1)),
        rejectsBeforeCall,
      );

      verifyNever(
        () => masterApi.getOverrides(
          masterId: any(named: 'masterId'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      );
    });

    test(
      'inverted range (to before from) rejects before any API call',
      () async {
        await expectLater(
          repository.effectiveSchedule(
            DateTime(2026, 6, 10),
            DateTime(2026, 6, 1),
          ),
          rejectsBeforeCall,
        );

        verifyNever(
          () => masterApi.getEffectiveSchedule(
            masterId: any(named: 'masterId'),
            from: any(named: 'from'),
            to: any(named: 'to'),
          ),
        );
      },
    );
  });

  group('listOverrides — happy path', () {
    test('a multi-row range maps to N single-date overrides', () async {
      when(
        () => masterApi.getOverrides(
          masterId: any(named: 'masterId'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer(
        (_) async => _overridesEnvelope(<ScheduleOverrideResponse>[
          _dayOffRow(2026, 6, 10),
          _dayOffRow(2026, 6, 11),
          _dayOffRow(2026, 6, 12),
        ]),
      );

      final overrides = await repository.listOverrides(
        DateTime(2026, 6, 1),
        DateTime(2026, 6, 30),
      );

      expect(overrides, hasLength(3));
      expect(overrides.every((o) => o.isSingleDay), isTrue);
      expect(overrides.map((o) => o.start.day), [10, 11, 12]);
      expect(overrides.every((o) => o.kind == OverrideKind.dayOff), isTrue);
    });

    test('null data → empty list', () async {
      when(
        () => masterApi.getOverrides(
          masterId: any(named: 'masterId'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer(
        (_) async => Response<ApiResponseListScheduleOverrideResponse>(
          data: ApiResponseListScheduleOverrideResponse(
            (b) => b..success = true,
          ),
          requestOptions: RequestOptions(path: _path),
          statusCode: 200,
        ),
      );

      final overrides = await repository.listOverrides(
        DateTime(2026, 6, 1),
        DateTime(2026, 6, 30),
      );
      expect(overrides, isEmpty);
    });
  });

  group('error mapping', () {
    test('400 pre-mapped ValidationFailure is surfaced unchanged', () async {
      const mapped = ValidationFailure(
        fieldErrors: {'from': 'range too large'},
      );
      when(
        () => masterApi.getEffectiveSchedule(
          masterId: any(named: 'masterId'),
          from: any(named: 'from'),
          to: any(named: 'to'),
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
        repository.effectiveSchedule(
          DateTime(2026, 6, 1),
          DateTime(2026, 6, 30),
        ),
        throwsA(same(mapped)),
      );
    });

    test('connectionError → NetworkFailure', () async {
      when(
        () => masterApi.getEffectiveSchedule(
          masterId: any(named: 'masterId'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _path),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        repository.effectiveSchedule(
          DateTime(2026, 6, 1),
          DateTime(2026, 6, 30),
        ),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });

  group('auth guard', () {
    test('empty masterId → UnauthorizedFailure, no API call', () async {
      final unauthRepo = HttpScheduleRepository(
        masterApi: masterApi,
        masterId: '',
      );

      await expectLater(
        unauthRepo.listWeeklySchedules(),
        throwsA(isA<UnauthorizedFailure>()),
      );

      verifyNever(
        () => masterApi.getWeeklySchedules(masterId: any(named: 'masterId')),
      );
    });

    test(
      'empty masterId short-circuits effectiveSchedule before range guard',
      () async {
        final unauthRepo = HttpScheduleRepository(
          masterApi: masterApi,
          masterId: '',
        );

        await expectLater(
          unauthRepo.effectiveSchedule(
            DateTime(2026, 6, 1),
            DateTime(2026, 6, 30),
          ),
          throwsA(isA<UnauthorizedFailure>()),
        );

        verifyNever(
          () => masterApi.getEffectiveSchedule(
            masterId: any(named: 'masterId'),
            from: any(named: 'from'),
            to: any(named: 'to'),
          ),
        );
      },
    );
  });
}
