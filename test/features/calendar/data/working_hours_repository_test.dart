// Phase 6.2 — Unit tests for [HttpWorkingHoursRepository].
//
// The repository was migrated off the deprecated single-call working-hours
// upsert onto the backend weekly-schedule API (getWeeklySchedules +
// create/updateWeeklySchedule). These tests pin the migrated behaviour:
//
//   list()
//     - calls getWeeklySchedules ONCE and maps the picked schedule to a dense,
//       gap-filled, ordered 7-entry week (this IS a network read now).
//
//   replaceAll()
//     - NO existing schedule        → createWeeklySchedule, validFrom = today
//                                     (Kyiv), validTo open-ended; result mapped.
//     - existing covering schedule  → updateWeeklySchedule(scheduleId), the
//                                     existing validFrom is PRESERVED (not
//                                     re-stamped to today); result mapped.
//
//   _pickSchedule selection
//     - a schedule covering today wins over a non-covering past schedule.
//     - the latest OPEN-ENDED schedule wins when none covers today.
//
//   guards / error mapping (retargeted to the new methods)
//     - empty masterId → UnauthorizedFailure, no API call.
//     - 400 (pre-mapped on e.error) → ValidationFailure.
//     - connectionError → NetworkFailure.
//     - 500 → ServerFailure(500).
//
// Strategy: mock [MasterControllerApi] with mocktail; construct
// [HttpWorkingHoursRepository] directly with a fixed masterId. Pure Dart: no
// ProviderScope, no widget tree.

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
const _basePath = '/api/v1/masters/$_masterId/weekly-schedules';

/// Today as a date-only [DateTime], mirroring the repo's `_todayKyiv()`. Used to
/// build schedules whose window deterministically covers "today" at test time.
DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

Date _date(DateTime d) => Date(d.year, d.month, d.day);

/// Builds a [WorkIntervalDto].
WorkIntervalDto _interval(String start, String end) => WorkIntervalDto(
  (b) => b
    ..startTime = start
    ..endTime = end,
);

/// Builds a [WeeklyScheduleResponse] for use as the persisted / fetched
/// schedule. [days] lists the active ISO days carried by the schedule.
WeeklyScheduleResponse _schedule({
  required String id,
  required DateTime validFrom,
  DateTime? validTo,
  List<int> activeDays = const [1, 2, 3],
}) => WeeklyScheduleResponse((b) {
  b
    ..id = id
    ..validFrom = _date(validFrom);
  if (validTo != null) b.validTo = _date(validTo);
  b.days = ListBuilder<WeeklyScheduleDayResponse>([
    for (final d in activeDays)
      WeeklyScheduleDayResponse(
        (db) => db
          ..dayOfWeek = d
          ..intervals = ListBuilder<WorkIntervalDto>([
            _interval('09:00:00', '18:00:00'),
          ]),
      ),
  ]);
});

/// Wraps a list of schedules in the getWeeklySchedules envelope.
Response<ApiResponseListWeeklyScheduleResponse> _listEnvelope(
  List<WeeklyScheduleResponse> schedules,
) {
  final envelope = ApiResponseListWeeklyScheduleResponse(
    (b) => b
      ..data.replace(schedules)
      ..success = true,
  );
  return Response<ApiResponseListWeeklyScheduleResponse>(
    data: envelope,
    requestOptions: RequestOptions(path: _basePath),
    statusCode: 200,
  );
}

/// Wraps a saved schedule in the create / update envelope.
Response<ApiResponseWeeklyScheduleResponse> _savedEnvelope(
  WeeklyScheduleResponse schedule,
) {
  final envelope = ApiResponseWeeklyScheduleResponse(
    (b) => b
      ..data.replace(schedule)
      ..success = true,
  );
  return Response<ApiResponseWeeklyScheduleResponse>(
    data: envelope,
    requestOptions: RequestOptions(path: _basePath),
    statusCode: 200,
  );
}

/// A DioException carrying a fetch failure for the read leg of replaceAll.
DioException _dio({
  required DioExceptionType type,
  int? statusCode,
  Object? error,
}) => DioException(
  requestOptions: RequestOptions(path: _basePath),
  type: type,
  response: statusCode == null
      ? null
      : Response<dynamic>(
          requestOptions: RequestOptions(path: _basePath),
          statusCode: statusCode,
        ),
  error: error,
);

WorkingHours _domainDay(int day, {bool active = true}) => WorkingHours(
  dayOfWeek: day,
  startTime: '09:00:00',
  endTime: '18:00:00',
  isActive: active,
);

void main() {
  late _MockMasterControllerApi masterApi;
  late HttpWorkingHoursRepository repository;

  setUpAll(() {
    registerFallbackValue(
      WeeklyScheduleRequest((b) => b..validFrom = Date(2026, 1, 1)),
    );
  });

  setUp(() {
    masterApi = _MockMasterControllerApi();
    repository = HttpWorkingHoursRepository(
      masterApi: masterApi,
      masterId: _masterId,
    );
  });

  group('list — reads schedules over the network', () {
    test('calls getWeeklySchedules once and maps the picked schedule to a '
        'dense 7-entry week', () async {
      // One open-ended schedule covering today with Mon–Wed active.
      when(() => masterApi.getWeeklySchedules(masterId: _masterId)).thenAnswer(
        (_) async => _listEnvelope([
          _schedule(
            id: 'sched-1',
            validFrom: _today().subtract(const Duration(days: 30)),
            activeDays: const [1, 2, 3],
          ),
        ]),
      );

      final week = await repository.list();

      verify(() => masterApi.getWeeklySchedules(masterId: _masterId)).called(1);
      expect(week, hasLength(7));
      expect(week.map((w) => w.dayOfWeek), [1, 2, 3, 4, 5, 6, 7]);
      // Mon–Wed carried as active; the rest gap-filled inactive.
      expect(week.take(3).every((w) => w.isActive), isTrue);
      expect(week.skip(3).every((w) => !w.isActive), isTrue);
    });

    test('no schedules → 7 inactive default days', () async {
      when(
        () => masterApi.getWeeklySchedules(masterId: _masterId),
      ).thenAnswer((_) async => _listEnvelope(const []));

      final week = await repository.list();

      expect(week, hasLength(7));
      expect(week.every((w) => !w.isActive), isTrue);
    });
  });

  group('_pickSchedule — selection', () {
    test(
      'a schedule covering today wins over a non-covering past one',
      () async {
        const coveringId = 'covering';
        // A past, already-expired schedule (validTo before today) …
        final expired = _schedule(
          id: 'expired',
          validFrom: _today().subtract(const Duration(days: 60)),
          validTo: _today().subtract(const Duration(days: 30)),
          activeDays: const [6, 7],
        );
        // … and the schedule whose window covers today (open-ended).
        final covering = _schedule(
          id: coveringId,
          validFrom: _today().subtract(const Duration(days: 10)),
          activeDays: const [1, 2, 3],
        );
        when(
          () => masterApi.getWeeklySchedules(masterId: _masterId),
        ).thenAnswer((_) async => _listEnvelope([expired, covering]));

        final week = await repository.list();

        // The covering schedule (Mon–Wed) was picked, NOT the expired (Sat–Sun).
        expect(week.take(3).every((w) => w.isActive), isTrue);
        expect(week[5].isActive, isFalse);
        expect(week[6].isActive, isFalse);
      },
    );

    test('the latest open-ended schedule wins when none covers today', () async {
      // Two FUTURE open-ended schedules (validFrom after today → neither covers
      // today); the one with the later validFrom must be picked.
      final earlierFuture = _schedule(
        id: 'future-early',
        validFrom: _today().add(const Duration(days: 10)),
        activeDays: const [1],
      );
      final laterFuture = _schedule(
        id: 'future-late',
        validFrom: _today().add(const Duration(days: 40)),
        activeDays: const [4, 5],
      );
      when(
        () => masterApi.getWeeklySchedules(masterId: _masterId),
      ).thenAnswer((_) async => _listEnvelope([earlierFuture, laterFuture]));

      final week = await repository.list();

      // laterFuture (Thu–Fri) was picked, not earlierFuture (Mon only).
      expect(
        week[0].isActive,
        isFalse,
        reason: 'Mon belongs to the earlier one',
      );
      expect(week[3].isActive, isTrue);
      expect(week[4].isActive, isTrue);
    });
  });

  group('replaceAll — create (no existing schedule)', () {
    test('createWeeklySchedule called with validFrom = today (Kyiv), '
        'open-ended; result mapped', () async {
      when(
        () => masterApi.getWeeklySchedules(masterId: _masterId),
      ).thenAnswer((_) async => _listEnvelope(const []));
      when(
        () => masterApi.createWeeklySchedule(
          masterId: any(named: 'masterId'),
          weeklyScheduleRequest: any(named: 'weeklyScheduleRequest'),
        ),
      ).thenAnswer(
        (_) async => _savedEnvelope(
          _schedule(
            id: 'new-sched',
            validFrom: _today(),
            activeDays: const [1, 2, 3, 4, 5],
          ),
        ),
      );

      final outgoing = [
        for (var d = 1; d <= 7; d++) _domainDay(d, active: d <= 5),
      ];
      final saved = await repository.replaceAll(outgoing);

      // No update on the create path.
      verifyNever(
        () => masterApi.updateWeeklySchedule(
          masterId: any(named: 'masterId'),
          scheduleId: any(named: 'scheduleId'),
          weeklyScheduleRequest: any(named: 'weeklyScheduleRequest'),
        ),
      );

      final captured =
          verify(
                () => masterApi.createWeeklySchedule(
                  masterId: _masterId,
                  weeklyScheduleRequest: captureAny(
                    named: 'weeklyScheduleRequest',
                  ),
                ),
              ).captured.single
              as WeeklyScheduleRequest;

      expect(
        captured.validFrom,
        _date(_today()),
        reason: 'a new schedule is stamped with today (Kyiv)',
      );
      expect(captured.validTo, isNull, reason: 'open-ended');
      // Only the five active days are emitted.
      expect(captured.days, hasLength(5));
      expect(captured.days!.map((d) => d.dayOfWeek), [1, 2, 3, 4, 5]);

      // The saved response is gap-filled back to a 7-entry week.
      expect(saved, hasLength(7));
      expect(saved.take(5).every((w) => w.isActive), isTrue);
      expect(saved.skip(5).every((w) => !w.isActive), isTrue);
    });
  });

  group('replaceAll — update (existing covering schedule)', () {
    test('updateWeeklySchedule(scheduleId) called; existing validFrom '
        'PRESERVED, not re-stamped to today; result mapped', () async {
      final existingValidFrom = _today().subtract(const Duration(days: 90));
      when(() => masterApi.getWeeklySchedules(masterId: _masterId)).thenAnswer(
        (_) async => _listEnvelope([
          _schedule(
            id: 'existing-sched',
            validFrom: existingValidFrom,
            activeDays: const [1],
          ),
        ]),
      );
      when(
        () => masterApi.updateWeeklySchedule(
          masterId: any(named: 'masterId'),
          scheduleId: any(named: 'scheduleId'),
          weeklyScheduleRequest: any(named: 'weeklyScheduleRequest'),
        ),
      ).thenAnswer(
        (_) async => _savedEnvelope(
          _schedule(
            id: 'existing-sched',
            validFrom: existingValidFrom,
            activeDays: const [1, 2],
          ),
        ),
      );

      final saved = await repository.replaceAll([
        _domainDay(1),
        _domainDay(2),
        for (var d = 3; d <= 7; d++) _domainDay(d, active: false),
      ]);

      // No create on the update path.
      verifyNever(
        () => masterApi.createWeeklySchedule(
          masterId: any(named: 'masterId'),
          weeklyScheduleRequest: any(named: 'weeklyScheduleRequest'),
        ),
      );

      final captured =
          verify(
                () => masterApi.updateWeeklySchedule(
                  masterId: _masterId,
                  scheduleId: 'existing-sched',
                  weeklyScheduleRequest: captureAny(
                    named: 'weeklyScheduleRequest',
                  ),
                ),
              ).captured.single
              as WeeklyScheduleRequest;

      expect(
        captured.validFrom,
        _date(existingValidFrom),
        reason:
            'the existing validFrom must be preserved — re-stamping it to '
            'today would be rejected by the backend @FutureOrPresent guard',
      );
      expect(captured.validFrom, isNot(_date(_today())));

      expect(saved, hasLength(7));
      expect(saved[0].isActive, isTrue);
      expect(saved[1].isActive, isTrue);
    });
  });

  group('replaceAll — error mapping', () {
    test('400 pre-mapped to ValidationFailure is surfaced', () async {
      const mapped = ValidationFailure(
        fieldErrors: {
          'days[0].intervals[0].endTime': 'must be after startTime',
        },
      );
      when(() => masterApi.getWeeklySchedules(masterId: _masterId)).thenAnswer(
        (_) async =>
            _listEnvelope([_schedule(id: 'existing', validFrom: _today())]),
      );
      when(
        () => masterApi.updateWeeklySchedule(
          masterId: any(named: 'masterId'),
          scheduleId: any(named: 'scheduleId'),
          weeklyScheduleRequest: any(named: 'weeklyScheduleRequest'),
        ),
      ).thenThrow(
        _dio(
          type: DioExceptionType.badResponse,
          statusCode: 400,
          error: mapped,
        ),
      );

      await expectLater(
        repository.replaceAll([_domainDay(1)]),
        throwsA(same(mapped)),
      );
    });

    test('connectionError → NetworkFailure', () async {
      when(() => masterApi.getWeeklySchedules(masterId: _masterId)).thenAnswer(
        (_) async =>
            _listEnvelope([_schedule(id: 'existing', validFrom: _today())]),
      );
      when(
        () => masterApi.updateWeeklySchedule(
          masterId: any(named: 'masterId'),
          scheduleId: any(named: 'scheduleId'),
          weeklyScheduleRequest: any(named: 'weeklyScheduleRequest'),
        ),
      ).thenThrow(_dio(type: DioExceptionType.connectionError));

      await expectLater(
        repository.replaceAll([_domainDay(1)]),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test(
      'badResponse 500 (no pre-mapped error) → ServerFailure(500)',
      () async {
        when(
          () => masterApi.getWeeklySchedules(masterId: _masterId),
        ).thenAnswer(
          (_) async =>
              _listEnvelope([_schedule(id: 'existing', validFrom: _today())]),
        );
        when(
          () => masterApi.updateWeeklySchedule(
            masterId: any(named: 'masterId'),
            scheduleId: any(named: 'scheduleId'),
            weeklyScheduleRequest: any(named: 'weeklyScheduleRequest'),
          ),
        ).thenThrow(_dio(type: DioExceptionType.badResponse, statusCode: 500));

        await expectLater(
          repository.replaceAll([_domainDay(1)]),
          throwsA(
            isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 500),
          ),
        );
      },
    );

    test(
      'a read-leg failure (getWeeklySchedules throws) is mapped too',
      () async {
        when(
          () => masterApi.getWeeklySchedules(masterId: _masterId),
        ).thenThrow(_dio(type: DioExceptionType.connectionError));

        await expectLater(
          repository.replaceAll([_domainDay(1)]),
          throwsA(isA<NetworkFailure>()),
        );
      },
    );
  });

  group('list — error mapping', () {
    test('connectionError → NetworkFailure', () async {
      when(
        () => masterApi.getWeeklySchedules(masterId: _masterId),
      ).thenThrow(_dio(type: DioExceptionType.connectionError));

      await expectLater(repository.list(), throwsA(isA<NetworkFailure>()));
    });

    test('badResponse 500 → ServerFailure(500)', () async {
      when(
        () => masterApi.getWeeklySchedules(masterId: _masterId),
      ).thenThrow(_dio(type: DioExceptionType.badResponse, statusCode: 500));

      await expectLater(
        repository.list(),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 500),
        ),
      );
    });
  });

  group('auth guard', () {
    test(
      'empty masterId → UnauthorizedFailure on replaceAll, no API call',
      () async {
        final unauthRepo = HttpWorkingHoursRepository(
          masterApi: masterApi,
          masterId: '',
        );

        await expectLater(
          unauthRepo.replaceAll([_domainDay(1)]),
          throwsA(isA<UnauthorizedFailure>()),
        );

        verifyNever(
          () => masterApi.getWeeklySchedules(masterId: any(named: 'masterId')),
        );
        verifyNever(
          () => masterApi.createWeeklySchedule(
            masterId: any(named: 'masterId'),
            weeklyScheduleRequest: any(named: 'weeklyScheduleRequest'),
          ),
        );
      },
    );

    test('empty masterId → UnauthorizedFailure on list, no API call', () async {
      final unauthRepo = HttpWorkingHoursRepository(
        masterApi: masterApi,
        masterId: '',
      );

      await expectLater(unauthRepo.list(), throwsA(isA<UnauthorizedFailure>()));

      verifyNever(
        () => masterApi.getWeeklySchedules(masterId: any(named: 'masterId')),
      );
    });
  });
}
