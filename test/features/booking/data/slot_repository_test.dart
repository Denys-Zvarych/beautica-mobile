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
}
