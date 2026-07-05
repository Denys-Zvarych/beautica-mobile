// Phase 14.0 — Unit tests for [HttpSlotRepository].
//
// Mocks [MasterControllerApi] with mocktail; verifies domain mapping (incl.
// the DEVIATION that [BookingSlot.available] is always `true` — see
// `booking_mapper.dart` / `domain/booking_slot.dart`) and error propagation.
//
// Pure Dart: no ProviderScope, no widget tree.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/booking/data/slot_repository.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockMasterControllerApi extends Mock implements MasterControllerApi {}

const _slotsPath = '/api/v1/masters/master-1/slots';

void main() {
  late _MockMasterControllerApi masterApi;
  late HttpSlotRepository repository;

  setUpAll(() {
    registerFallbackValue(Date(2026, 1, 1));
  });

  setUp(() {
    masterApi = _MockMasterControllerApi();
    repository = HttpSlotRepository(masterApi);
  });

  group('getMasterSlots', () {
    test('success: maps slots and forces available = true', () async {
      final slot1 =
          (AvailableSlotResponseBuilder()
                ..startsAt = DateTime.utc(2026, 7, 10, 10)
                ..endsAt = DateTime.utc(2026, 7, 10, 11))
              .build();
      final slot2 =
          (AvailableSlotResponseBuilder()
                ..startsAt = DateTime.utc(2026, 7, 10, 11)
                ..endsAt = DateTime.utc(2026, 7, 10, 12))
              .build();
      final slotsDto =
          (AvailableSlotsResponseBuilder()
                ..date = Date(2026, 7, 10)
                ..slots = ListBuilder<AvailableSlotResponse>([slot1, slot2]))
              .build();

      when(
        () => masterApi.getAvailableSlots(
          masterId: 'master-1',
          serviceId: 'service-1',
          date: any(named: 'date'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => Response<ApiResponseAvailableSlotsResponse>(
          data: ApiResponseAvailableSlotsResponse(
            (b) => b
              ..data.replace(slotsDto)
              ..success = true,
          ),
          requestOptions: RequestOptions(path: _slotsPath),
          statusCode: 200,
        ),
      );

      final slots = await repository.getMasterSlots(
        masterId: 'master-1',
        serviceId: 'service-1',
        date: DateTime(2026, 7, 10, 15, 30), // time-of-day must be discarded
      );

      expect(slots, hasLength(2));
      expect(slots.every((s) => s.available), isTrue);
      expect(slots[0].startAt, DateTime.utc(2026, 7, 10, 10));
      expect(slots[0].endAt, DateTime.utc(2026, 7, 10, 11));
      expect(slots[1].startAt, DateTime.utc(2026, 7, 10, 11));

      final capturedDate =
          verify(
                () => masterApi.getAvailableSlots(
                  masterId: 'master-1',
                  serviceId: 'service-1',
                  date: captureAny(named: 'date'),
                  cancelToken: any(named: 'cancelToken'),
                ),
              ).captured.single
              as Date;
      expect(capturedDate.year, 2026);
      expect(capturedDate.month, 7);
      expect(capturedDate.day, 10);
    });

    test('no availability that day → empty list (not an error)', () async {
      final slotsDto =
          (AvailableSlotsResponseBuilder()
                ..date = Date(2026, 7, 11)
                ..slots = ListBuilder<AvailableSlotResponse>(const []))
              .build();
      when(
        () => masterApi.getAvailableSlots(
          masterId: 'master-1',
          serviceId: 'service-1',
          date: any(named: 'date'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => Response<ApiResponseAvailableSlotsResponse>(
          data: ApiResponseAvailableSlotsResponse(
            (b) => b
              ..data.replace(slotsDto)
              ..success = true,
          ),
          requestOptions: RequestOptions(path: _slotsPath),
          statusCode: 200,
        ),
      );

      final slots = await repository.getMasterSlots(
        masterId: 'master-1',
        serviceId: 'service-1',
        date: DateTime(2026, 7, 11),
      );

      expect(slots, isEmpty);
    });

    test('malformed slot (missing startsAt) is dropped, not thrown', () async {
      final badSlot =
          (AvailableSlotResponseBuilder()
                ..endsAt = DateTime.utc(2026, 7, 10, 11))
              .build(); // startsAt intentionally left unset
      final goodSlot =
          (AvailableSlotResponseBuilder()
                ..startsAt = DateTime.utc(2026, 7, 10, 12)
                ..endsAt = DateTime.utc(2026, 7, 10, 13))
              .build();
      final slotsDto =
          (AvailableSlotsResponseBuilder()
                ..date = Date(2026, 7, 10)
                ..slots = ListBuilder<AvailableSlotResponse>([
                  badSlot,
                  goodSlot,
                ]))
              .build();
      when(
        () => masterApi.getAvailableSlots(
          masterId: 'master-1',
          serviceId: 'service-1',
          date: any(named: 'date'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => Response<ApiResponseAvailableSlotsResponse>(
          data: ApiResponseAvailableSlotsResponse(
            (b) => b
              ..data.replace(slotsDto)
              ..success = true,
          ),
          requestOptions: RequestOptions(path: _slotsPath),
          statusCode: 200,
        ),
      );

      final slots = await repository.getMasterSlots(
        masterId: 'master-1',
        serviceId: 'service-1',
        date: DateTime(2026, 7, 10),
      );

      expect(slots, hasLength(1));
      expect(slots.single.startAt, DateTime.utc(2026, 7, 10, 12));
    });

    test('connectionError → NetworkFailure', () async {
      when(
        () => masterApi.getAvailableSlots(
          masterId: 'master-1',
          serviceId: 'service-1',
          date: any(named: 'date'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _slotsPath),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        repository.getMasterSlots(
          masterId: 'master-1',
          serviceId: 'service-1',
          date: DateTime(2026, 7, 10),
        ),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('bad-response DioException → ServerFailure with status', () async {
      when(
        () => masterApi.getAvailableSlots(
          masterId: 'master-1',
          serviceId: 'service-1',
          date: any(named: 'date'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _slotsPath),
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: _slotsPath),
            statusCode: 422,
          ),
        ),
      );

      await expectLater(
        repository.getMasterSlots(
          masterId: 'master-1',
          serviceId: 'service-1',
          date: DateTime(2026, 7, 10),
        ),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 422),
        ),
      );
    });

    test('pre-mapped Failure on e.error is re-thrown unchanged', () async {
      const mapped = UnauthorizedFailure();
      when(
        () => masterApi.getAvailableSlots(
          masterId: 'master-1',
          serviceId: 'service-1',
          date: any(named: 'date'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _slotsPath),
          type: DioExceptionType.badResponse,
          error: mapped,
        ),
      );

      await expectLater(
        repository.getMasterSlots(
          masterId: 'master-1',
          serviceId: 'service-1',
          date: DateTime(2026, 7, 10),
        ),
        throwsA(same(mapped)),
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Phase 14.14 — [HttpSlotRepository.getWorkingDays].
  // ───────────────────────────────────────────────────────────────────────────
  group('getWorkingDays', () {
    const workingDaysPath = '/api/v1/masters/master-1/working-days';

    test('success: maps date + working, discarding time-of-day on the '
        'request params', () async {
      final day1 =
          (MasterWorkingDayResponseBuilder()
                ..date = Date(2026, 7, 1)
                ..working = true)
              .build();
      final day2 =
          (MasterWorkingDayResponseBuilder()
                ..date = Date(2026, 7, 2)
                ..working = false)
              .build();

      when(
        () => masterApi.getWorkingDays(
          masterId: 'master-1',
          from: any(named: 'from'),
          to: any(named: 'to'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => Response<ApiResponseListMasterWorkingDayResponse>(
          data: ApiResponseListMasterWorkingDayResponse(
            (b) => b
              ..data = ListBuilder<MasterWorkingDayResponse>([day1, day2])
              ..success = true,
          ),
          requestOptions: RequestOptions(path: workingDaysPath),
          statusCode: 200,
        ),
      );

      final days = await repository.getWorkingDays(
        masterId: 'master-1',
        from: DateTime(2026, 7, 1, 12, 30), // time-of-day must be discarded
        to: DateTime(2026, 7, 31, 23),
      );

      expect(days, hasLength(2));
      expect(days[0].date, DateTime(2026, 7, 1));
      expect(days[0].working, isTrue);
      expect(days[1].date, DateTime(2026, 7, 2));
      expect(days[1].working, isFalse);

      final captured = verify(
        () => masterApi.getWorkingDays(
          masterId: 'master-1',
          from: captureAny(named: 'from'),
          to: captureAny(named: 'to'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).captured;
      final capturedFrom = captured[0] as Date;
      final capturedTo = captured[1] as Date;
      expect(capturedFrom.year, 2026);
      expect(capturedFrom.month, 7);
      expect(capturedFrom.day, 1);
      expect(capturedTo.day, 31);
    });

    test('no data returned → empty list (not an error)', () async {
      when(
        () => masterApi.getWorkingDays(
          masterId: 'master-1',
          from: any(named: 'from'),
          to: any(named: 'to'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => Response<ApiResponseListMasterWorkingDayResponse>(
          data: ApiResponseListMasterWorkingDayResponse(
            (b) => b
              ..data = ListBuilder<MasterWorkingDayResponse>([])
              ..success = true,
          ),
          requestOptions: RequestOptions(path: workingDaysPath),
          statusCode: 200,
        ),
      );

      final days = await repository.getWorkingDays(
        masterId: 'master-1',
        from: DateTime(2026, 7, 1),
        to: DateTime(2026, 7, 31),
      );

      expect(days, isEmpty);
    });

    test('malformed entry (missing working) is dropped, not thrown', () async {
      final badDay =
          (MasterWorkingDayResponseBuilder()..date = Date(2026, 7, 5))
              .build(); // working intentionally left unset
      final goodDay =
          (MasterWorkingDayResponseBuilder()
                ..date = Date(2026, 7, 6)
                ..working = true)
              .build();

      when(
        () => masterApi.getWorkingDays(
          masterId: 'master-1',
          from: any(named: 'from'),
          to: any(named: 'to'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => Response<ApiResponseListMasterWorkingDayResponse>(
          data: ApiResponseListMasterWorkingDayResponse(
            (b) => b
              ..data = ListBuilder<MasterWorkingDayResponse>([badDay, goodDay])
              ..success = true,
          ),
          requestOptions: RequestOptions(path: workingDaysPath),
          statusCode: 200,
        ),
      );

      final days = await repository.getWorkingDays(
        masterId: 'master-1',
        from: DateTime(2026, 7, 1),
        to: DateTime(2026, 7, 31),
      );

      expect(days, hasLength(1));
      expect(days.single.date, DateTime(2026, 7, 6));
    });

    test('connectionError → NetworkFailure', () async {
      when(
        () => masterApi.getWorkingDays(
          masterId: 'master-1',
          from: any(named: 'from'),
          to: any(named: 'to'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: workingDaysPath),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        repository.getWorkingDays(
          masterId: 'master-1',
          from: DateTime(2026, 7, 1),
          to: DateTime(2026, 7, 31),
        ),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('bad-response DioException → ServerFailure with status', () async {
      when(
        () => masterApi.getWorkingDays(
          masterId: 'master-1',
          from: any(named: 'from'),
          to: any(named: 'to'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: workingDaysPath),
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: workingDaysPath),
            statusCode: 422,
          ),
        ),
      );

      await expectLater(
        repository.getWorkingDays(
          masterId: 'master-1',
          from: DateTime(2026, 7, 1),
          to: DateTime(2026, 7, 31),
        ),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 422),
        ),
      );
    });

    test('pre-mapped Failure on e.error is re-thrown unchanged', () async {
      const mapped = UnauthorizedFailure();
      when(
        () => masterApi.getWorkingDays(
          masterId: 'master-1',
          from: any(named: 'from'),
          to: any(named: 'to'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: workingDaysPath),
          type: DioExceptionType.badResponse,
          error: mapped,
        ),
      );

      await expectLater(
        repository.getWorkingDays(
          masterId: 'master-1',
          from: DateTime(2026, 7, 1),
          to: DateTime(2026, 7, 31),
        ),
        throwsA(same(mapped)),
      );
    });
  });
}
