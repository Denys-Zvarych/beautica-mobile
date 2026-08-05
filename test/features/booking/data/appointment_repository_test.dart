// MO-1 — Unit tests for [HttpAppointmentRepository].
//
// Strategy: mock [AppointmentControllerApi] with mocktail; verify domain
// mapping, the idempotency-key channel (header + body), the cancel-note
// trimming, and the error mapping transcribed from `HttpBookingRepository`
// (409 CLIENT_BOOKING_CONFLICT / BOOKING_ALREADY_ELAPSED / plain 409, 429).
// Mirrors `booking_repository_test.dart`.
//
// Pure Dart: no ProviderScope, no widget tree.
//
// WHY EVERY INSTANT HERE IS A FIXED PAST LITERAL
// ----------------------------------------------
// Nothing on this path reads the wall clock — the repository maps DTOs and
// serialises the create body, and `startsAt` is asserted as an EXACT
// input⇄output pair (the domain `startAt` handed to `createAppointment` must
// reappear verbatim on the captured wire body). A `futureBookingStart()`
// anchor would make that pair non-deterministic for no gain. A literal in a
// past year can never become "upcoming", so it is not the time bomb
// `scripts/forbid_stale_future_date_fixture.sh` guards against and the gate
// exempts it automatically.

import 'package:beautica_api/beautica_api.dart' hide CreateAppointmentRequest;
import 'package:beautica_api/beautica_api.dart'
    as wire
    show CreateAppointmentRequest;
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/booking/data/appointment_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/create_appointment_request.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAppointmentControllerApi extends Mock
    implements AppointmentControllerApi {}

const _createPath = '/api/v1/appointments';
const _getPath = '/api/v1/appointments/appt-1';
const _itemReschedulePath =
    '/api/v1/appointments/appt-1/services/b-1/reschedule';
const _cancelPath = '/api/v1/appointments/appt-1/cancel';

AppointmentItemResponse _buildItem({
  String bookingId = 'b-1',
  String masterServiceId = 's-1',
  String serviceName = 'Манікюр',
}) =>
    (AppointmentItemResponseBuilder()
          ..bookingId = bookingId
          ..masterServiceId = masterServiceId
          ..serviceName = serviceName
          ..startsAt = DateTime.utc(2020, 7, 10, 10)
          ..endsAt = DateTime.utc(2020, 7, 10, 11)
          ..durationMinutesAtBooking = 60
          ..priceAtBooking = 500)
        .build();

AppointmentDetailResponse _buildDetail({String id = 'appt-1'}) =>
    (AppointmentDetailResponseBuilder()
          ..id = id
          ..status = AppointmentDetailResponseStatusEnum.CONFIRMED
          ..masterId = 'master-1'
          ..masterFirstName = 'Оля'
          ..masterLastName = 'Коваль'
          ..masterType =
              AppointmentDetailResponseMasterTypeEnum.INDEPENDENT_MASTER
          ..startsAt = DateTime.utc(2020, 7, 10, 10)
          ..endsAt = DateTime.utc(2020, 7, 10, 11)
          ..totalDurationMinutes = 60
          ..totalPrice = 500
          ..items = ListBuilder<AppointmentItemResponse>(
            <AppointmentItemResponse>[_buildItem()],
          ))
        .build();

Response<ApiResponseAppointmentDetailResponse> _detailResponse(
  AppointmentDetailResponse dto, {
  String path = _createPath,
}) => Response<ApiResponseAppointmentDetailResponse>(
  data: ApiResponseAppointmentDetailResponse(
    (b) => b
      ..data.replace(dto)
      ..success = true,
  ),
  requestOptions: RequestOptions(path: path),
  statusCode: 200,
);

DioException _dioBadResponse(int statusCode, String path) => DioException(
  requestOptions: RequestOptions(path: path),
  type: DioExceptionType.badResponse,
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: path),
    statusCode: statusCode,
  ),
);

DioException _dioBadResponseWithBody(
  int statusCode,
  String path,
  dynamic body,
) => DioException(
  requestOptions: RequestOptions(path: path),
  type: DioExceptionType.badResponse,
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: path),
    statusCode: statusCode,
    data: body,
  ),
);

DioException _dioConnectionError(String path) => DioException(
  requestOptions: RequestOptions(path: path),
  type: DioExceptionType.connectionError,
);

DioException _dioBadCertificate(String path) => DioException(
  requestOptions: RequestOptions(path: path),
  type: DioExceptionType.badCertificate,
);

Map<String, dynamic> _clientBookingConflictBody() => <String, dynamic>{
  'success': false,
  'data': <String, dynamic>{
    'code': 'CLIENT_BOOKING_CONFLICT',
    'conflictingBookingId': 'conflict-1',
    'serviceName': 'Манікюр',
    'masterName': 'Олена Коваль',
    'startsAt': '2026-07-15T14:00:00+03:00',
    'endsAt': '2026-07-15T15:30:00+03:00',
  },
  'message': 'Client already has an overlapping booking',
};

Map<String, dynamic> _bookingAlreadyElapsedBody() => <String, dynamic>{
  'success': false,
  'data': <String, dynamic>{'code': 'BOOKING_ALREADY_ELAPSED'},
  'message': 'elapsed',
};

void main() {
  late _MockAppointmentControllerApi appointmentApi;
  late HttpAppointmentRepository repository;

  setUpAll(() {
    registerFallbackValue(
      wire.CreateAppointmentRequest(
        (b) => b
          ..masterId = 'fallback-master'
          ..masterServiceIds = ListBuilder<String>(<String>['fallback-service'])
          ..startsAt = DateTime.utc(2020, 1, 1),
      ),
    );
    registerFallbackValue(AppointmentCancelRequest((b) => b));
    registerFallbackValue(
      AppointmentItemRescheduleRequest(
        (b) => b..newStartsAt = DateTime.utc(2020, 1, 1),
      ),
    );
  });

  setUp(() {
    appointmentApi = _MockAppointmentControllerApi();
    repository = HttpAppointmentRepository(appointmentApi);
  });

  group('createAppointment', () {
    final req = CreateAppointmentRequest(
      masterId: 'master-1',
      masterServiceIds: const <String>['s-1', 's-2'],
      startAt: DateTime.utc(2020, 7, 10, 10),
      idempotencyKey: 'key-1',
      clientComment: 'Please call before arriving',
    );

    test(
      'success: maps the returned detail directly (no second fetch)',
      () async {
        when(
          () => appointmentApi.createAppointment(
            createAppointmentRequest: any(named: 'createAppointmentRequest'),
            idempotencyKey: any(named: 'idempotencyKey'),
          ),
        ).thenAnswer((_) async => _detailResponse(_buildDetail()));

        final appt = await repository.createAppointment(req);

        expect(appt.id, 'appt-1');
        expect(appt.status, BookingStatus.confirmed);
        expect(appt.items, hasLength(1));
        // No getAppointment follow-up — the create response is already enriched.
        verifyNever(
          () => appointmentApi.getAppointment(
            appointmentId: any(named: 'appointmentId'),
          ),
        );
      },
    );

    test('forwards the ordered masterServiceIds + idempotency key on BOTH '
        'the body and the header param', () async {
      when(
        () => appointmentApi.createAppointment(
          createAppointmentRequest: any(named: 'createAppointmentRequest'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer((_) async => _detailResponse(_buildDetail()));

      await repository.createAppointment(req);

      final captured = verify(
        () => appointmentApi.createAppointment(
          createAppointmentRequest: captureAny(
            named: 'createAppointmentRequest',
          ),
          idempotencyKey: captureAny(named: 'idempotencyKey'),
        ),
      ).captured;
      final body = captured[0] as wire.CreateAppointmentRequest;
      expect(body.masterId, 'master-1');
      expect(body.masterServiceIds.toList(), <String>['s-1', 's-2']);
      expect(body.startsAt, DateTime.utc(2020, 7, 10, 10));
      expect(body.idempotencyKey, 'key-1');
      expect(body.clientComment, 'Please call before arriving');
      expect(captured[1], 'key-1');
    });

    test('null data on 200 → ServerFailure(null)', () async {
      when(
        () => appointmentApi.createAppointment(
          createAppointmentRequest: any(named: 'createAppointmentRequest'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer(
        (_) async => Response<ApiResponseAppointmentDetailResponse>(
          data: ApiResponseAppointmentDetailResponse((b) => b..success = true),
          requestOptions: RequestOptions(path: _createPath),
          statusCode: 200,
        ),
      );

      await expectLater(
        repository.createAppointment(req),
        throwsA(
          isA<ServerFailure>().having(
            (f) => f.statusCode,
            'statusCode',
            isNull,
          ),
        ),
      );
    });

    test(
      '409 CLIENT_BOOKING_CONFLICT → ClientBookingConflictFailure',
      () async {
        when(
          () => appointmentApi.createAppointment(
            createAppointmentRequest: any(named: 'createAppointmentRequest'),
            idempotencyKey: any(named: 'idempotencyKey'),
          ),
        ).thenThrow(
          _dioBadResponseWithBody(
            409,
            _createPath,
            _clientBookingConflictBody(),
          ),
        );

        await expectLater(
          repository.createAppointment(req),
          throwsA(
            isA<ClientBookingConflictFailure>()
                .having((f) => f.conflictingBookingId, 'id', 'conflict-1')
                .having((f) => f.serviceName, 'service', 'Манікюр'),
          ),
        );
      },
    );

    test(
      '409 BOOKING_ALREADY_ELAPSED → BookingAlreadyElapsedFailure',
      () async {
        when(
          () => appointmentApi.createAppointment(
            createAppointmentRequest: any(named: 'createAppointmentRequest'),
            idempotencyKey: any(named: 'idempotencyKey'),
          ),
        ).thenThrow(
          _dioBadResponseWithBody(
            409,
            _createPath,
            _bookingAlreadyElapsedBody(),
          ),
        );

        await expectLater(
          repository.createAppointment(req),
          throwsA(isA<BookingAlreadyElapsedFailure>()),
        );
      },
    );

    test('409 DUPLICATE_SERVICE → DuplicateServiceFailure (MO-3)', () async {
      when(
        () => appointmentApi.createAppointment(
          createAppointmentRequest: any(named: 'createAppointmentRequest'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenThrow(
        _dioBadResponseWithBody(409, _createPath, <String, dynamic>{
          'success': false,
          'data': <String, dynamic>{'code': 'DUPLICATE_SERVICE'},
          'message': 'duplicate service',
        }),
      );

      await expectLater(
        repository.createAppointment(req),
        throwsA(isA<DuplicateServiceFailure>()),
      );
    });

    test('plain 409 (empty body) → ConflictFailure', () async {
      when(
        () => appointmentApi.createAppointment(
          createAppointmentRequest: any(named: 'createAppointmentRequest'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenThrow(_dioBadResponse(409, _createPath));

      await expectLater(
        repository.createAppointment(req),
        throwsA(isA<ConflictFailure>()),
      );
    });

    test('429 → BookingRateLimitedFailure', () async {
      when(
        () => appointmentApi.createAppointment(
          createAppointmentRequest: any(named: 'createAppointmentRequest'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenThrow(_dioBadResponse(429, _createPath));

      await expectLater(
        repository.createAppointment(req),
        throwsA(isA<BookingRateLimitedFailure>()),
      );
    });

    test('connection error → NetworkFailure', () async {
      when(
        () => appointmentApi.createAppointment(
          createAppointmentRequest: any(named: 'createAppointmentRequest'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenThrow(_dioConnectionError(_createPath));

      await expectLater(
        repository.createAppointment(req),
        throwsA(isA<NetworkFailure>()),
      );
    });

    // MITM signal must NOT be swallowed: a TLS/certificate failure surfaces as
    // ServerFailure (fails closed) — the security-visible arm transcribed from
    // HttpBookingRepository._mapDioException. Pins that a badCertificate never
    // collapses to a NetworkFailure (which would read as a transient retry).
    test('badCertificate → ServerFailure (MITM not swallowed)', () async {
      when(
        () => appointmentApi.createAppointment(
          createAppointmentRequest: any(named: 'createAppointmentRequest'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenThrow(_dioBadCertificate(_createPath));

      await expectLater(
        repository.createAppointment(req),
        throwsA(
          isA<ServerFailure>().having(
            (f) => f,
            'not a NetworkFailure',
            isNot(isA<NetworkFailure>()),
          ),
        ),
      );
    });

    // A 409 whose body claims CLIENT_BOOKING_CONFLICT but is missing the
    // required envelope fields must NOT crash the hand-decoder — it falls back
    // to the generic ConflictFailure (the client picked a stale slot).
    test('409 with malformed CLIENT_BOOKING_CONFLICT body → ConflictFailure '
        '(no crash)', () async {
      final malformed = <String, dynamic>{
        'success': false,
        'data': <String, dynamic>{
          'code': 'CLIENT_BOOKING_CONFLICT',
          // conflictingBookingId / serviceName / masterName / startsAt /
          // endsAt all absent → _extractClientBookingConflict returns null.
          'serviceName': 'Манікюр',
        },
      };
      when(
        () => appointmentApi.createAppointment(
          createAppointmentRequest: any(named: 'createAppointmentRequest'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenThrow(_dioBadResponseWithBody(409, _createPath, malformed));

      await expectLater(
        repository.createAppointment(req),
        throwsA(
          isA<ConflictFailure>().having(
            (f) => f,
            'not the typed conflict',
            isNot(isA<ClientBookingConflictFailure>()),
          ),
        ),
      );
    });

    // A 409 whose body is not even a JSON object (e.g. an HTML error page /
    // bare string) must degrade to ConflictFailure, never throw a cast error.
    test('409 with a non-map body → ConflictFailure (no crash)', () async {
      when(
        () => appointmentApi.createAppointment(
          createAppointmentRequest: any(named: 'createAppointmentRequest'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenThrow(
        _dioBadResponseWithBody(409, _createPath, '<html>Conflict</html>'),
      );

      await expectLater(
        repository.createAppointment(req),
        throwsA(isA<ConflictFailure>()),
      );
    });

    // A [Failure] already attached to DioException.error (e.g. by an
    // interceptor) is re-thrown unchanged — mirrors slot/booking repo tests.
    test('pre-mapped Failure on e.error is re-thrown unchanged', () async {
      const mapped = UnauthorizedFailure();
      when(
        () => appointmentApi.createAppointment(
          createAppointmentRequest: any(named: 'createAppointmentRequest'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _createPath),
          type: DioExceptionType.badResponse,
          error: mapped,
        ),
      );

      await expectLater(
        repository.createAppointment(req),
        throwsA(same(mapped)),
      );
    });
  });

  group('rescheduleAppointmentItem', () {
    final newStart = DateTime.utc(2020, 8, 1, 9);

    test(
      'success: forwards newStartsAt and maps the returned detail',
      () async {
        when(
          () => appointmentApi.rescheduleAppointmentItem(
            appointmentId: 'appt-1',
            bookingId: 'b-1',
            appointmentItemRescheduleRequest: any(
              named: 'appointmentItemRescheduleRequest',
            ),
          ),
        ).thenAnswer(
          (_) async =>
              _detailResponse(_buildDetail(), path: _itemReschedulePath),
        );

        final appt = await repository.rescheduleAppointmentItem(
          'appt-1',
          'b-1',
          newStart,
        );

        expect(appt.id, 'appt-1');
        expect(appt.status, BookingStatus.confirmed);

        final captured = verify(
          () => appointmentApi.rescheduleAppointmentItem(
            appointmentId: 'appt-1',
            bookingId: 'b-1',
            appointmentItemRescheduleRequest: captureAny(
              named: 'appointmentItemRescheduleRequest',
            ),
          ),
        ).captured;
        final body = captured.single as AppointmentItemRescheduleRequest;
        expect(body.newStartsAt, newStart);
      },
    );

    test('null data on 200 → ServerFailure(null)', () async {
      when(
        () => appointmentApi.rescheduleAppointmentItem(
          appointmentId: 'appt-1',
          bookingId: 'b-1',
          appointmentItemRescheduleRequest: any(
            named: 'appointmentItemRescheduleRequest',
          ),
        ),
      ).thenAnswer(
        (_) async => Response<ApiResponseAppointmentDetailResponse>(
          data: ApiResponseAppointmentDetailResponse((b) => b..success = true),
          requestOptions: RequestOptions(path: _itemReschedulePath),
          statusCode: 200,
        ),
      );

      await expectLater(
        repository.rescheduleAppointmentItem('appt-1', 'b-1', newStart),
        throwsA(
          isA<ServerFailure>().having(
            (f) => f.statusCode,
            'statusCode',
            isNull,
          ),
        ),
      );
    });

    test(
      '409 BOOKING_ALREADY_ELAPSED → BookingAlreadyElapsedFailure',
      () async {
        when(
          () => appointmentApi.rescheduleAppointmentItem(
            appointmentId: 'appt-1',
            bookingId: 'b-1',
            appointmentItemRescheduleRequest: any(
              named: 'appointmentItemRescheduleRequest',
            ),
          ),
        ).thenThrow(
          _dioBadResponseWithBody(
            409,
            _itemReschedulePath,
            _bookingAlreadyElapsedBody(),
          ),
        );

        await expectLater(
          repository.rescheduleAppointmentItem('appt-1', 'b-1', newStart),
          throwsA(isA<BookingAlreadyElapsedFailure>()),
        );
      },
    );

    // The backend cannot distinguish, on the wire, a sibling-overlap /
    // "master busy" conflict from the "changed concurrently — please retry"
    // guard — both are plain `BusinessException(CONFLICT, …)` and serialize
    // to the SAME bare `data: null` 409 (see
    // `AppointmentTransitionService.rescheduleAppointmentItem`'s Javadoc).
    // Both therefore surface the SAME "time is no longer available"
    // ConflictFailure the single-booking reschedule endpoint uses, never a
    // bespoke type.
    test('plain 409 (empty body) → ConflictFailure', () async {
      when(
        () => appointmentApi.rescheduleAppointmentItem(
          appointmentId: 'appt-1',
          bookingId: 'b-1',
          appointmentItemRescheduleRequest: any(
            named: 'appointmentItemRescheduleRequest',
          ),
        ),
      ).thenThrow(_dioBadResponse(409, _itemReschedulePath));

      await expectLater(
        repository.rescheduleAppointmentItem('appt-1', 'b-1', newStart),
        throwsA(isA<ConflictFailure>()),
      );
    });

    // 409 CLIENT_BOOKING_CONFLICT → ClientBookingConflictFailure — mirrors the
    // `createAppointment` test above. The OpenAPI spec documents this
    // endpoint's 409 explicitly as covering `CLIENT_BOOKING_CONFLICT`, and the
    // backend's `AppointmentTransitionService.rescheduleAppointmentItem` calls
    // `assertNoClientConflictExcludingBooking`, which throws the SAME coded
    // `ClientBookingConflictException` the create path does whenever moving
    // this item would overlap the owning client's own OTHER booking.
    // (Previously this test pinned the OPPOSITE behaviour — plain
    // ConflictFailure — on the false premise that this endpoint's 409 is
    // always a bare `data: null` body; that premise did not survive contact
    // with the OpenAPI spec or the backend source, so the mapping was
    // reverted to extract the coded envelope, and this test now pins the
    // correct, richer shape.)
    test(
      '409 CLIENT_BOOKING_CONFLICT → ClientBookingConflictFailure',
      () async {
        when(
          () => appointmentApi.rescheduleAppointmentItem(
            appointmentId: 'appt-1',
            bookingId: 'b-1',
            appointmentItemRescheduleRequest: any(
              named: 'appointmentItemRescheduleRequest',
            ),
          ),
        ).thenThrow(
          _dioBadResponseWithBody(
            409,
            _itemReschedulePath,
            _clientBookingConflictBody(),
          ),
        );

        await expectLater(
          repository.rescheduleAppointmentItem('appt-1', 'b-1', newStart),
          throwsA(
            isA<ClientBookingConflictFailure>()
                .having((f) => f.conflictingBookingId, 'id', 'conflict-1')
                .having((f) => f.serviceName, 'service', 'Манікюр'),
          ),
        );
      },
    );

    // mobile-qa fix (F6) — the 404 case (`bookingId` is not a child of
    // `appointmentId`) was only exercised incidentally, sharing the 400
    // test's `e.error is Failure` branch with no test of its own naming that
    // status code. Named explicitly so a future change to this branch's
    // status-code handling can't silently drop 404 coverage.
    test('404 (bookingId not a child of appointmentId): pre-mapped '
        'NotFoundFailure on e.error is re-thrown unchanged', () async {
      const mapped = NotFoundFailure();
      when(
        () => appointmentApi.rescheduleAppointmentItem(
          appointmentId: 'appt-1',
          bookingId: 'b-1',
          appointmentItemRescheduleRequest: any(
            named: 'appointmentItemRescheduleRequest',
          ),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _itemReschedulePath),
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: _itemReschedulePath),
            statusCode: 404,
          ),
          error: mapped,
        ),
      );

      await expectLater(
        repository.rescheduleAppointmentItem('appt-1', 'b-1', newStart),
        throwsA(same(mapped)),
      );
    });

    // The backend's 15-minute–180-day window guard rejects with a plain 400 —
    // no dedicated Failure type here; it defers to whatever the shared
    // ErrorMapperInterceptor already attached (a ValidationFailure carrying the
    // server's window message), simulated here via `e.error`.
    test('400 window violation: pre-mapped ValidationFailure on e.error is '
        're-thrown unchanged', () async {
      const mapped = ValidationFailure(
        fieldErrors: <String, String>{},
        serverMessage: 'window violation',
      );
      when(
        () => appointmentApi.rescheduleAppointmentItem(
          appointmentId: 'appt-1',
          bookingId: 'b-1',
          appointmentItemRescheduleRequest: any(
            named: 'appointmentItemRescheduleRequest',
          ),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _itemReschedulePath),
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: _itemReschedulePath),
            statusCode: 400,
          ),
          error: mapped,
        ),
      );

      await expectLater(
        repository.rescheduleAppointmentItem('appt-1', 'b-1', newStart),
        throwsA(same(mapped)),
      );
    });

    test('connection error → NetworkFailure', () async {
      when(
        () => appointmentApi.rescheduleAppointmentItem(
          appointmentId: 'appt-1',
          bookingId: 'b-1',
          appointmentItemRescheduleRequest: any(
            named: 'appointmentItemRescheduleRequest',
          ),
        ),
      ).thenThrow(_dioConnectionError(_itemReschedulePath));

      await expectLater(
        repository.rescheduleAppointmentItem('appt-1', 'b-1', newStart),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });

  group('getAppointment', () {
    test('success maps the detail', () async {
      when(
        () => appointmentApi.getAppointment(appointmentId: 'appt-1'),
      ).thenAnswer(
        (_) async => _detailResponse(_buildDetail(), path: _getPath),
      );

      final appt = await repository.getAppointment('appt-1');
      expect(appt.id, 'appt-1');
      expect(appt.items.single.serviceName, 'Манікюр');
    });

    test('null data → ServerFailure(null)', () async {
      when(
        () => appointmentApi.getAppointment(appointmentId: 'appt-1'),
      ).thenAnswer(
        (_) async => Response<ApiResponseAppointmentDetailResponse>(
          data: ApiResponseAppointmentDetailResponse((b) => b..success = true),
          requestOptions: RequestOptions(path: _getPath),
          statusCode: 200,
        ),
      );

      await expectLater(
        repository.getAppointment('appt-1'),
        throwsA(isA<ServerFailure>()),
      );
    });

    // Pins the ACTUAL behaviour: a 404 maps through the shared
    // _mapDioException to ServerFailure(statusCode: 404) — NOT a dedicated
    // NotFoundFailure (the interface docstring's "throws NotFoundFailure"
    // wording is aspirational and mirrors the same loose wording on
    // HttpBookingRepository.getBookingById; the impl carries the status code
    // instead). If MO-2/MO-3 ever wants a typed NotFoundFailure for a
    // deleted/foreign visit, the branch must be ADDED here first — this test
    // is the tripwire that will flag that change.
    test('404 → ServerFailure carrying the 404 status', () async {
      when(
        () => appointmentApi.getAppointment(appointmentId: 'appt-1'),
      ).thenThrow(_dioBadResponse(404, _getPath));

      await expectLater(
        repository.getAppointment('appt-1'),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 404),
        ),
      );
    });
  });

  group('cancelAppointment', () {
    test('forwards a trimmed note as clientCancellationNote', () async {
      when(
        () => appointmentApi.cancelAppointment(
          appointmentId: any(named: 'appointmentId'),
          appointmentCancelRequest: any(named: 'appointmentCancelRequest'),
        ),
      ).thenAnswer(
        (_) async => Response<void>(
          requestOptions: RequestOptions(path: _cancelPath),
          statusCode: 200,
        ),
      );

      await repository.cancelAppointment('appt-1', note: '  changed my mind  ');

      final captured = verify(
        () => appointmentApi.cancelAppointment(
          appointmentId: 'appt-1',
          appointmentCancelRequest: captureAny(
            named: 'appointmentCancelRequest',
          ),
        ),
      ).captured;
      final body = captured.single as AppointmentCancelRequest;
      expect(body.clientCancellationNote, 'changed my mind');
    });

    test('blank note is sent as null', () async {
      when(
        () => appointmentApi.cancelAppointment(
          appointmentId: any(named: 'appointmentId'),
          appointmentCancelRequest: any(named: 'appointmentCancelRequest'),
        ),
      ).thenAnswer(
        (_) async => Response<void>(
          requestOptions: RequestOptions(path: _cancelPath),
          statusCode: 200,
        ),
      );

      await repository.cancelAppointment('appt-1', note: '   ');

      final captured = verify(
        () => appointmentApi.cancelAppointment(
          appointmentId: 'appt-1',
          appointmentCancelRequest: captureAny(
            named: 'appointmentCancelRequest',
          ),
        ),
      ).captured;
      expect(
        (captured.single as AppointmentCancelRequest).clientCancellationNote,
        isNull,
      );
    });

    test(
      '409 BOOKING_ALREADY_ELAPSED → BookingAlreadyElapsedFailure',
      () async {
        when(
          () => appointmentApi.cancelAppointment(
            appointmentId: any(named: 'appointmentId'),
            appointmentCancelRequest: any(named: 'appointmentCancelRequest'),
          ),
        ).thenThrow(
          _dioBadResponseWithBody(
            409,
            _cancelPath,
            _bookingAlreadyElapsedBody(),
          ),
        );

        await expectLater(
          repository.cancelAppointment('appt-1'),
          throwsA(isA<BookingAlreadyElapsedFailure>()),
        );
      },
    );
  });
}
