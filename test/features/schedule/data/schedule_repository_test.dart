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
import 'package:built_collection/built_collection.dart';
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

const _weeklyPath = '/api/v1/masters/$_masterId/weekly-schedules';

Response<ApiResponseListWeeklyScheduleResponse> _weeklyEnvelope(
  Iterable<WeeklyScheduleResponse> rows,
) {
  final envelope = ApiResponseListWeeklyScheduleResponse(
    (b) => b
      ..success = true
      ..data.replace(rows),
  );
  return Response<ApiResponseListWeeklyScheduleResponse>(
    data: envelope,
    requestOptions: RequestOptions(path: _weeklyPath),
    statusCode: 200,
  );
}

/// A persisted weekly template row carrying its server [id] — Mon 09:00–18:00,
/// every other day omitted (the backend may send a sparse week).
WeeklyScheduleResponse _weeklyRow({required String? id}) =>
    WeeklyScheduleResponse(
      (b) => b
        ..id = id
        ..validFrom = Date(2026, 6, 1)
        ..days = ListBuilder<WeeklyScheduleDayResponse>(
          <WeeklyScheduleDayResponse>[
            WeeklyScheduleDayResponse(
              (db) => db
                ..dayOfWeek = 1
                ..intervals = ListBuilder<WorkIntervalDto>(<WorkIntervalDto>[
                  WorkIntervalDto(
                    (i) => i
                      ..startTime = '09:00:00'
                      ..endTime = '18:00:00',
                  ),
                ]),
            ),
          ],
        ),
    );

ScheduleOverrideResponse _dayOffRow(int year, int month, int day) =>
    ScheduleOverrideResponse(
      (b) => b
        ..date = Date(year, month, day)
        ..kind = ScheduleOverrideResponseKindEnum.DAY_OFF,
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

    // Phase 15.6 — pin the guard on listOverrides for the INVERTED case too. The
    // existing >366-day test covers listOverrides' upper bound; this adds the
    // ordering half so BOTH range methods reject BOTH invariants before any call.
    test('listOverrides inverted range rejects before any API call', () async {
      await expectLater(
        repository.listOverrides(DateTime(2026, 6, 10), DateTime(2026, 6, 1)),
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

    // Phase 15.6 — the guard's ACCEPT path: a normal in-bounds window (and the
    // exact 366-day boundary, which is inclusive) must pass through to the API.
    // Without this, all three guard tests above would still pass if the guard
    // rejected EVERYTHING — this proves it admits the valid range.
    test('a normal month range passes the guard and reaches the API', () async {
      when(
        () => masterApi.getEffectiveSchedule(
          masterId: any(named: 'masterId'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer(
        (_) async => Response<ApiResponseListEffectiveDayResponse>(
          data: ApiResponseListEffectiveDayResponse((b) => b..success = true),
          requestOptions: RequestOptions(path: _path),
          statusCode: 200,
        ),
      );

      await repository.effectiveSchedule(
        DateTime(2026, 6, 1),
        DateTime(2026, 6, 30),
      );

      verify(
        () => masterApi.getEffectiveSchedule(
          masterId: any(named: 'masterId'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).called(1);
    });

    test(
      'the inclusive 366-day boundary is accepted (reaches the API)',
      () async {
        when(
          () => masterApi.getOverrides(
            masterId: any(named: 'masterId'),
            from: any(named: 'from'),
            to: any(named: 'to'),
          ),
        ).thenAnswer(
          (_) async => _overridesEnvelope(const <ScheduleOverrideResponse>[]),
        );

        final from = DateTime(2026, 1, 1);
        // Exactly kMaxScheduleRangeDays apart → span == 366 → on the inclusive bound.
        final to = from.add(const Duration(days: kMaxScheduleRangeDays));

        await repository.listOverrides(from, to);

        verify(
          () => masterApi.getOverrides(
            masterId: any(named: 'masterId'),
            from: any(named: 'from'),
            to: any(named: 'to'),
          ),
        ).called(1);
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

  // ── Regression: list path must yield self-identifying templates ───────────
  //
  // The dropped-id bug lived on THIS path. `listWeeklySchedules` maps each row
  // through `weeklyScheduleFromResponse` with no explicit `id:` override, so the
  // id has to ride in on `dto.id`. When it didn't, every loaded template had
  // `id == null` → the editor's create-vs-update diff (`existing.id`) chose
  // CREATE on the second save → a duplicate window → backend overlap rejection.
  //
  // The behavioral assertion: given a persisted row with a non-null wire id,
  // the listed `WeeklySchedule` carries that exact id (NOT null) — which is what
  // makes the editor PUT (`scheduleId: <that id>`) instead of POST.
  group('listWeeklySchedules — id propagation (dropped-id regression)', () {
    test(
      'a persisted row keeps its server id (non-null, equal to dto.id)',
      () async {
        when(
          () => masterApi.getWeeklySchedules(masterId: any(named: 'masterId')),
        ).thenAnswer(
          (_) async => _weeklyEnvelope(<WeeklyScheduleResponse>[
            _weeklyRow(id: 'sched-42'),
          ]),
        );

        final templates = await repository.listWeeklySchedules();

        expect(templates, hasLength(1));
        expect(
          templates.single.id,
          'sched-42',
          reason:
              'the reloaded list template must be self-identifying so the editor '
              'PUTs with this id rather than POSTing a duplicate window',
        );
        expect(
          templates.single.id,
          isNotNull,
          reason:
              'a null id here is the exact bug: it forces a duplicate CREATE',
        );
      },
    );

    test('null data → empty list', () async {
      when(
        () => masterApi.getWeeklySchedules(masterId: any(named: 'masterId')),
      ).thenAnswer(
        (_) async => Response<ApiResponseListWeeklyScheduleResponse>(
          data: ApiResponseListWeeklyScheduleResponse((b) => b..success = true),
          requestOptions: RequestOptions(path: _weeklyPath),
          statusCode: 200,
        ),
      );

      expect(await repository.listWeeklySchedules(), isEmpty);
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
