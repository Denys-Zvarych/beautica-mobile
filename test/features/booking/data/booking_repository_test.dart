// Phase 14.0 — Unit tests for [HttpBookingRepository].
//
// Strategy:
//   createBooking / getBookingById / cancelBooking / rescheduleBooking — mock
//   [BookingControllerApi] with mocktail; verify domain mapping + error
//   propagation.
//   getMyBookings — mock [Dio] directly and feed the SERIALIZED envelope (via
//   `standardSerializers`), exercising the real raw-GET parse path — mirrors
//   `discovery/data/search_repository_test.dart` (see the WIRE-FORMAT NOTE in
//   `booking_repository.dart` for why this bypasses the generated
//   `listMyBookings`/`Pageable` path).
//
// Pure Dart: no ProviderScope, no widget tree.

import 'package:beautica_api/beautica_api.dart' hide CreateBookingRequest;
import 'package:beautica_api/beautica_api.dart'
    as wire
    show CreateBookingRequest;
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/create_booking_request.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

class _MockBookingControllerApi extends Mock implements BookingControllerApi {}

const _createPath = '/api/v1/bookings';
const _getPath = '/api/v1/bookings/booking-1';
const _cancelPath = '/api/v1/bookings/booking-1/cancel';
const _reschedulePath = '/api/v1/bookings/booking-1/reschedule';
const _myBookingsPath = '/api/v1/bookings/me';

/// Builds a minimal enriched [BookingDetailResponse] DTO for happy-path
/// assertions.
BookingDetailResponse _buildDetailDto({
  String id = 'booking-1',
  String masterId = 'master-1',
  String masterServiceId = 'service-1',
  String masterFirstName = 'Оля',
  String masterLastName = 'Коваль',
  String serviceName = 'Манікюр',
  BookingDetailResponseStatusEnum status =
      BookingDetailResponseStatusEnum.CONFIRMED,
  DateTime? startsAt,
  DateTime? endsAt,
  num priceAtBooking = 500,
  int durationMinutesAtBooking = 60,
  bool canReview = false,
  String? salonName,
  BookingDetailResponseMasterTypeEnum masterType =
      BookingDetailResponseMasterTypeEnum.INDEPENDENT_MASTER,
}) =>
    (BookingDetailResponseBuilder()
          ..id = id
          ..masterId = masterId
          ..masterServiceId = masterServiceId
          ..masterFirstName = masterFirstName
          ..masterLastName = masterLastName
          ..serviceName = serviceName
          ..status = status
          ..startsAt = startsAt ?? DateTime.utc(2026, 7, 10, 10)
          ..endsAt = endsAt ?? DateTime.utc(2026, 7, 10, 11)
          ..priceAtBooking = priceAtBooking
          ..durationMinutesAtBooking = durationMinutesAtBooking
          ..canReview = canReview
          ..salonName = salonName
          ..masterType = masterType)
        .build();

Response<ApiResponseBookingDetailResponse> _detailResponse(
  BookingDetailResponse dto, {
  String path = _getPath,
}) => Response<ApiResponseBookingDetailResponse>(
  data: ApiResponseBookingDetailResponse(
    (b) => b
      ..data.replace(dto)
      ..success = true,
  ),
  requestOptions: RequestOptions(path: path),
  statusCode: 200,
);

/// The exact wire form the real Dio JSON transformer hands the repository for
/// `GET /bookings/me`: the JSON-collection serialization of the typed
/// envelope, produced through the SAME `standardSerializers` the repository's
/// `_deserialize` uses to re-hydrate it — a deserialization fault would
/// surface here exactly as in production.
Map<String, dynamic> _serializeMyBookingsEnvelope(
  List<BookingDetailResponse> items, {
  int page = 0,
  int totalPages = 1,
  int? totalElements,
}) {
  final body = ApiResponsePageResponseBookingDetailResponse(
    (b) => b
      ..success = true
      ..data.replace(
        PageResponseBookingDetailResponse(
          (p) => p
            ..success = true
            ..data = ListBuilder<BookingDetailResponse>(items)
            ..page = page
            ..size = items.length
            ..totalPages = totalPages
            ..totalElements = totalElements ?? items.length,
        ),
      ),
  );
  return standardSerializers.serialize(
        body,
        specifiedType: const FullType(
          ApiResponsePageResponseBookingDetailResponse,
        ),
      )!
      as Map<String, dynamic>;
}

DioException _dioBadResponse(int statusCode, String path) => DioException(
  requestOptions: RequestOptions(path: path),
  type: DioExceptionType.badResponse,
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: path),
    statusCode: statusCode,
  ),
);

/// Like [_dioBadResponse] but carries an arbitrary raw JSON [body] on
/// `response.data` — mirrors the shape `_extractClientBookingConflict` reads
/// by hand (mobile-qa gap-fix: backend commit f95d8fd).
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

/// Builds the `data` envelope backend commit f95d8fd sends on a 409
/// `CLIENT_BOOKING_CONFLICT`. Every field is overridable (including to
/// `null`/a wrong type) so malformed-envelope fallback tests can target one
/// field at a time without duplicating the whole map shape.
Map<String, dynamic> _clientBookingConflictBody({
  Object? code = 'CLIENT_BOOKING_CONFLICT',
  Object? conflictingBookingId = 'conflict-booking-1',
  Object? serviceName = 'Манікюр класичний',
  Object? masterName = 'Олена Коваль',
  Object? startsAt = '2026-07-15T14:00:00+03:00',
  Object? endsAt = '2026-07-15T15:30:00+03:00',
}) => <String, dynamic>{
  'success': false,
  'data': <String, dynamic>{
    'code': code,
    'conflictingBookingId': conflictingBookingId,
    'serviceName': serviceName,
    'masterName': masterName,
    'startsAt': startsAt,
    'endsAt': endsAt,
  },
  'message': 'Client already has an overlapping booking',
};

/// The `data` envelope backend commit 952e441 sends on a 409
/// `BOOKING_ALREADY_ELAPSED` (both the cancel and reschedule write paths). The
/// repository hand-decodes `data.code` (not in the generated client — see the
/// `_isBookingAlreadyElapsed` doc), so a plain map is the faithful fixture.
Map<String, dynamic> _bookingAlreadyElapsedBody() => <String, dynamic>{
  'success': false,
  'data': <String, dynamic>{'code': 'BOOKING_ALREADY_ELAPSED'},
  'message': 'Booking window already elapsed',
};

DioException _dioConnectionError(String path) => DioException(
  requestOptions: RequestOptions(path: path),
  type: DioExceptionType.connectionError,
);

void main() {
  late _MockDio dio;
  late _MockBookingControllerApi bookingApi;
  late HttpBookingRepository repository;

  setUpAll(() {
    // Register fallback values required by mocktail for built_value request
    // types — mocktail needs a concrete instance to use as a fallback
    // whenever any(named: ...) / captureAny(named: ...) is used with a
    // non-primitive type.
    registerFallbackValue(RequestOptions(path: '/fallback'));
    registerFallbackValue(
      wire.CreateBookingRequest(
        (b) => b
          ..masterId = 'fallback-master'
          ..masterServiceId = 'fallback-service'
          ..startsAt = DateTime.utc(2026, 1, 1),
      ),
    );
    registerFallbackValue(
      CancelBookingRequest(
        (b) => b.cancellationReason =
            CancelBookingRequestCancellationReasonEnum.CLIENT_CANCELLED,
      ),
    );
    registerFallbackValue(
      RescheduleBookingRequest(
        (b) => b..newStartsAt = DateTime.utc(2026, 1, 1),
      ),
    );
  });

  setUp(() {
    dio = _MockDio();
    bookingApi = _MockBookingControllerApi();
    repository = HttpBookingRepository(dio, bookingApi);
  });

  group('createBooking', () {
    final req = CreateBookingRequest(
      masterId: 'master-1',
      serviceId: 'service-1',
      startAt: DateTime.utc(2026, 7, 10, 10),
      idempotencyKey: 'key-1',
      clientComment: 'Please call before arriving',
    );

    test(
      'success: creates then fetches the enriched detail via getBookingById',
      () async {
        final leanDto = (BookingResponseBuilder()..id = 'booking-1').build();
        when(
          () => bookingApi.createBooking(
            createBookingRequest: any(named: 'createBookingRequest'),
            idempotencyKey: any(named: 'idempotencyKey'),
          ),
        ).thenAnswer(
          (_) async => Response<ApiResponseBookingResponse>(
            data: ApiResponseBookingResponse(
              (b) => b
                ..data.replace(leanDto)
                ..success = true,
            ),
            requestOptions: RequestOptions(path: _createPath),
            statusCode: 201,
          ),
        );
        when(
          () => bookingApi.getBooking(bookingId: 'booking-1'),
        ).thenAnswer((_) async => _detailResponse(_buildDetailDto()));

        final booking = await repository.createBooking(req);

        expect(booking.id, 'booking-1');
        expect(booking.masterFirstName, 'Оля');
        expect(booking.masterLastName, 'Коваль');
        expect(booking.status, BookingStatus.confirmed);
        expect(booking.canReview, isFalse);

        final captured = verify(
          () => bookingApi.createBooking(
            createBookingRequest: captureAny(named: 'createBookingRequest'),
            idempotencyKey: captureAny(named: 'idempotencyKey'),
          ),
        ).captured;
        final capturedBody = captured[0] as wire.CreateBookingRequest;
        expect(capturedBody.masterId, 'master-1');
        expect(capturedBody.masterServiceId, 'service-1');
        expect(capturedBody.clientComment, 'Please call before arriving');
        expect(capturedBody.idempotencyKey, 'key-1');
        expect(
          captured[1],
          'key-1',
          reason:
              'idempotencyKey must ALSO be forwarded as the Idempotency-Key '
              'header param — see _toWireCreateRequest doc comment',
        );

        verify(() => bookingApi.getBooking(bookingId: 'booking-1')).called(1);
      },
    );

    test('409 → ConflictFailure', () async {
      when(
        () => bookingApi.createBooking(
          createBookingRequest: any(named: 'createBookingRequest'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenThrow(_dioBadResponse(409, _createPath));

      await expectLater(
        repository.createBooking(req),
        throwsA(isA<ConflictFailure>()),
      );

      // The follow-up detail fetch must never run on a failed create.
      verifyNever(
        () => bookingApi.getBooking(bookingId: any(named: 'bookingId')),
      );
    });

    test('connectionError → NetworkFailure', () async {
      when(
        () => bookingApi.createBooking(
          createBookingRequest: any(named: 'createBookingRequest'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenThrow(_dioConnectionError(_createPath));

      await expectLater(
        repository.createBooking(req),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('response with null id → ServerFailure(null)', () async {
      final leanDto = BookingResponseBuilder().build(); // id left unset
      when(
        () => bookingApi.createBooking(
          createBookingRequest: any(named: 'createBookingRequest'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer(
        (_) async => Response<ApiResponseBookingResponse>(
          data: ApiResponseBookingResponse(
            (b) => b
              ..data.replace(leanDto)
              ..success = true,
          ),
          requestOptions: RequestOptions(path: _createPath),
          statusCode: 201,
        ),
      );

      await expectLater(
        repository.createBooking(req),
        throwsA(
          isA<ServerFailure>().having(
            (f) => f.statusCode,
            'statusCode',
            isNull,
          ),
        ),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // mobile-qa gap-fix (KNOWN COVERAGE GAP 1) — `_extractClientBookingConflict`
  // had NO test at all before this. Exercised through the PUBLIC
  // `createBooking` entrypoint (the private method has no direct seam) so the
  // full `_mapBookingWriteException` → `_extractClientBookingConflict` chain
  // is proven exactly as production hits it. Covers: the happy-path decode,
  // 429 → BookingRateLimitedFailure, and every malformed-body fallback path —
  // each of which must degrade to the generic ConflictFailure and MUST NOT
  // throw a raw (non-Failure) exception, since an uncaught parse error here
  // would be a DoS of the booking-write flow.
  // ---------------------------------------------------------------------------
  group('createBooking — CLIENT_BOOKING_CONFLICT / 429 / malformed-409 mapping '
      '(mobile-qa gap-fix)', () {
    final req = CreateBookingRequest(
      masterId: 'master-1',
      serviceId: 'service-1',
      startAt: DateTime.utc(2026, 7, 10, 10),
      idempotencyKey: 'key-1',
    );

    void stub409(dynamic body) {
      when(
        () => bookingApi.createBooking(
          createBookingRequest: any(named: 'createBookingRequest'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenThrow(_dioBadResponseWithBody(409, _createPath, body));
    }

    test(
      '409 with a well-formed CLIENT_BOOKING_CONFLICT body → '
      'ClientBookingConflictFailure with every field decoded correctly',
      () async {
        stub409(_clientBookingConflictBody());

        await expectLater(
          repository.createBooking(req),
          throwsA(
            isA<ClientBookingConflictFailure>()
                .having(
                  (f) => f.conflictingBookingId,
                  'conflictingBookingId',
                  'conflict-booking-1',
                )
                .having(
                  (f) => f.serviceName,
                  'serviceName',
                  'Манікюр класичний',
                )
                .having((f) => f.masterName, 'masterName', 'Олена Коваль')
                .having(
                  (f) => f.startsAt,
                  'startsAt',
                  DateTime.parse('2026-07-15T14:00:00+03:00').toUtc(),
                )
                .having(
                  (f) => f.endsAt,
                  'endsAt',
                  DateTime.parse('2026-07-15T15:30:00+03:00').toUtc(),
                ),
          ),
        );
      },
    );

    test('429 → BookingRateLimitedFailure', () async {
      when(
        () => bookingApi.createBooking(
          createBookingRequest: any(named: 'createBookingRequest'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenThrow(_dioBadResponse(429, _createPath));

      await expectLater(
        repository.createBooking(req),
        throwsA(isA<BookingRateLimitedFailure>()),
      );
    });

    test('409 with data: null falls back to generic ConflictFailure, does '
        'not throw a raw exception', () async {
      stub409(<String, dynamic>{'success': false, 'data': null});

      await expectLater(
        repository.createBooking(req),
        throwsA(isA<ConflictFailure>()),
      );
    });

    test('409 with a non-Map data (wrong shape entirely) falls back to '
        'generic ConflictFailure', () async {
      stub409(<String, dynamic>{
        'success': false,
        'data': 'unexpected-string-payload',
      });

      await expectLater(
        repository.createBooking(req),
        throwsA(isA<ConflictFailure>()),
      );
    });

    test('409 with an unrecognized data.code falls back to generic '
        'ConflictFailure (a plain slot-taken/lock-timeout 409)', () async {
      stub409(_clientBookingConflictBody(code: 'SOME_OTHER_CODE'));

      await expectLater(
        repository.createBooking(req),
        throwsA(isA<ConflictFailure>()),
      );
    });

    for (final String field in <String>[
      'conflictingBookingId',
      'serviceName',
      'masterName',
      'startsAt',
      'endsAt',
    ]) {
      test('409 with a missing/null "$field" falls back to generic '
          'ConflictFailure instead of throwing', () async {
        final Map<String, dynamic> body = _clientBookingConflictBody();
        (body['data'] as Map<String, dynamic>)[field] = null;
        stub409(body);

        await expectLater(
          repository.createBooking(req),
          throwsA(isA<ConflictFailure>()),
        );
      });
    }

    test('409 with a wrong-typed conflictingBookingId (int, not String) '
        'falls back to generic ConflictFailure — the bad cast must be '
        'caught, never escape as a raw TypeError', () async {
      stub409(_clientBookingConflictBody(conflictingBookingId: 12345));

      await expectLater(
        repository.createBooking(req),
        throwsA(isA<ConflictFailure>()),
      );
    });

    test('409 with an unparseable startsAt falls back to generic '
        'ConflictFailure — the DateTime.parse FormatException must be '
        'caught, never escape raw', () async {
      stub409(_clientBookingConflictBody(startsAt: 'not-a-real-date'));

      await expectLater(
        repository.createBooking(req),
        throwsA(isA<ConflictFailure>()),
      );
    });

    test('409 with an unparseable endsAt falls back to generic '
        'ConflictFailure', () async {
      stub409(_clientBookingConflictBody(endsAt: 'also-not-a-date'));

      await expectLater(
        repository.createBooking(req),
        throwsA(isA<ConflictFailure>()),
      );
    });
  });

  group('getBookingById', () {
    test('success: maps every enriched field', () async {
      final dto = _buildDetailDto(
        salonName: 'Salon Beauty',
        status: BookingDetailResponseStatusEnum.COMPLETED,
        canReview: true,
        masterType: BookingDetailResponseMasterTypeEnum.SALON_MASTER,
      );
      when(
        () => bookingApi.getBooking(bookingId: 'booking-1'),
      ).thenAnswer((_) async => _detailResponse(dto));

      final booking = await repository.getBookingById('booking-1');

      expect(booking.id, 'booking-1');
      expect(booking.masterId, 'master-1');
      expect(booking.serviceId, 'service-1');
      expect(booking.serviceName, 'Манікюр');
      expect(booking.salonName, 'Salon Beauty');
      expect(booking.masterType, 'SALON_MASTER');
      expect(booking.status, BookingStatus.completed);
      expect(booking.canReview, isTrue);
      expect(booking.durationMinutes, 60);
      expect(booking.price, 500.0);
      expect(booking.startAt, DateTime.utc(2026, 7, 10, 10));
      expect(booking.endAt, DateTime.utc(2026, 7, 10, 11));
    });

    test('404 → NotFoundFailure', () async {
      // The [ErrorMapperInterceptor] (which runs on the real Dio instance,
      // not in this mocktail unit test) is what actually maps a 404 status
      // to NotFoundFailure and attaches it as `DioException.error` — mirrors
      // the identical precedent in `master_repository_test.dart`
      // ('DioException badResponse 404 → ServerFailure(404)', where a raw
      // 404 with no `.error` set falls through to the generic
      // `_mapDioException` mapping instead). Here we simulate the
      // interceptor already having run and assert the repository re-throws
      // the pre-mapped [NotFoundFailure] UNCHANGED (`e.error is Failure`
      // branch), which is what actually happens end-to-end in production.
      const mapped = NotFoundFailure();
      when(() => bookingApi.getBooking(bookingId: 'booking-1')).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _getPath),
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: _getPath),
            statusCode: 404,
          ),
          error: mapped,
        ),
      );

      await expectLater(
        repository.getBookingById('booking-1'),
        throwsA(same(mapped)),
      );
    });

    test('connectionError → NetworkFailure', () async {
      when(
        () => bookingApi.getBooking(bookingId: 'booking-1'),
      ).thenThrow(_dioConnectionError(_getPath));

      await expectLater(
        repository.getBookingById('booking-1'),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('envelope data null → ServerFailure(null)', () async {
      when(() => bookingApi.getBooking(bookingId: 'booking-1')).thenAnswer(
        (_) async => Response<ApiResponseBookingDetailResponse>(
          data: ApiResponseBookingDetailResponse((b) => b..success = true),
          requestOptions: RequestOptions(path: _getPath),
          statusCode: 200,
        ),
      );

      await expectLater(
        repository.getBookingById('booking-1'),
        throwsA(
          isA<ServerFailure>().having(
            (f) => f.statusCode,
            'statusCode',
            isNull,
          ),
        ),
      );
    });
  });

  group('cancelBooking', () {
    test(
      'success: always sends CLIENT_CANCELLED with reason as comment',
      () async {
        when(
          () => bookingApi.cancelBooking(
            bookingId: any(named: 'bookingId'),
            cancelBookingRequest: any(named: 'cancelBookingRequest'),
          ),
        ).thenAnswer(
          (_) async => Response<void>(
            requestOptions: RequestOptions(path: _cancelPath),
            statusCode: 200,
          ),
        );

        await repository.cancelBooking('booking-1', reason: 'change of plans');

        final captured = verify(
          () => bookingApi.cancelBooking(
            bookingId: captureAny(named: 'bookingId'),
            cancelBookingRequest: captureAny(named: 'cancelBookingRequest'),
          ),
        ).captured;
        expect(captured[0], 'booking-1');
        final body = captured[1] as CancelBookingRequest;
        expect(
          body.cancellationReason,
          CancelBookingRequestCancellationReasonEnum.CLIENT_CANCELLED,
        );
        expect(body.comment, 'change of plans');
      },
    );

    test('success with no reason: comment is null', () async {
      when(
        () => bookingApi.cancelBooking(
          bookingId: any(named: 'bookingId'),
          cancelBookingRequest: any(named: 'cancelBookingRequest'),
        ),
      ).thenAnswer(
        (_) async => Response<void>(
          requestOptions: RequestOptions(path: _cancelPath),
          statusCode: 200,
        ),
      );

      await repository.cancelBooking('booking-1');

      final captured =
          verify(
                () => bookingApi.cancelBooking(
                  bookingId: any(named: 'bookingId'),
                  cancelBookingRequest: captureAny(
                    named: 'cancelBookingRequest',
                  ),
                ),
              ).captured.single
              as CancelBookingRequest;
      expect(captured.comment, isNull);
    });

    test('connectionError → NetworkFailure', () async {
      when(
        () => bookingApi.cancelBooking(
          bookingId: any(named: 'bookingId'),
          cancelBookingRequest: any(named: 'cancelBookingRequest'),
        ),
      ).thenThrow(_dioConnectionError(_cancelPath));

      await expectLater(
        repository.cancelBooking('booking-1'),
        throwsA(isA<NetworkFailure>()),
      );
    });

    // mobile-qa (elapsed read-only track) — the cancel path's ONE special 409
    // is BOOKING_ALREADY_ELAPSED (backend 952e441): the visit window passed
    // server-side, so the booking can no longer be cancelled. Mapped by
    // `_mapBookingCancelException` BEFORE the generic 409 fallback.
    void stubCancel409(dynamic body) {
      when(
        () => bookingApi.cancelBooking(
          bookingId: any(named: 'bookingId'),
          cancelBookingRequest: any(named: 'cancelBookingRequest'),
        ),
      ).thenThrow(_dioBadResponseWithBody(409, _cancelPath, body));
    }

    test(
      '409 BOOKING_ALREADY_ELAPSED → BookingAlreadyElapsedFailure',
      () async {
        stubCancel409(_bookingAlreadyElapsedBody());

        await expectLater(
          repository.cancelBooking('booking-1'),
          throwsA(isA<BookingAlreadyElapsedFailure>()),
        );
      },
    );

    test(
      'a plain 409 with no body stays the previous generic ServerFailure(409) '
      '— the elapsed check must not over-catch',
      () async {
        when(
          () => bookingApi.cancelBooking(
            bookingId: any(named: 'bookingId'),
            cancelBookingRequest: any(named: 'cancelBookingRequest'),
          ),
        ).thenThrow(_dioBadResponse(409, _cancelPath));

        await expectLater(
          repository.cancelBooking('booking-1'),
          throwsA(
            isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 409),
          ),
        );
      },
    );

    test(
      'a 409 with an unrelated data.code stays generic ServerFailure(409)',
      () async {
        stubCancel409(<String, dynamic>{
          'success': false,
          'data': <String, dynamic>{'code': 'SOME_OTHER_CODE'},
        });

        await expectLater(
          repository.cancelBooking('booking-1'),
          throwsA(
            isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 409),
          ),
        );
      },
    );
  });

  group('rescheduleBooking', () {
    final newStart = DateTime.utc(2026, 7, 12, 14);

    test('success: maps the returned enriched detail', () async {
      final dto = _buildDetailDto(
        // `PENDING` was retired backend-side by track 24.x booking
        // auto-confirm — a rescheduled booking now simply stays CONFIRMED.
        status: BookingDetailResponseStatusEnum.CONFIRMED,
        startsAt: newStart,
        endsAt: newStart.add(const Duration(hours: 1)),
      );
      when(
        () => bookingApi.rescheduleBooking(
          bookingId: 'booking-1',
          rescheduleBookingRequest: any(named: 'rescheduleBookingRequest'),
        ),
      ).thenAnswer((_) async => _detailResponse(dto, path: _reschedulePath));

      final booking = await repository.rescheduleBooking('booking-1', newStart);

      expect(booking.startAt, newStart);
      expect(booking.status, BookingStatus.confirmed);

      final captured =
          verify(
                () => bookingApi.rescheduleBooking(
                  bookingId: 'booking-1',
                  rescheduleBookingRequest: captureAny(
                    named: 'rescheduleBookingRequest',
                  ),
                ),
              ).captured.single
              as RescheduleBookingRequest;
      expect(captured.newStartsAt, newStart);
    });

    test('409 → ConflictFailure', () async {
      when(
        () => bookingApi.rescheduleBooking(
          bookingId: 'booking-1',
          rescheduleBookingRequest: any(named: 'rescheduleBookingRequest'),
        ),
      ).thenThrow(_dioBadResponse(409, _reschedulePath));

      await expectLater(
        repository.rescheduleBooking('booking-1', newStart),
        throwsA(isA<ConflictFailure>()),
      );
    });

    test('connectionError → NetworkFailure', () async {
      when(
        () => bookingApi.rescheduleBooking(
          bookingId: 'booking-1',
          rescheduleBookingRequest: any(named: 'rescheduleBookingRequest'),
        ),
      ).thenThrow(_dioConnectionError(_reschedulePath));

      await expectLater(
        repository.rescheduleBooking('booking-1', newStart),
        throwsA(isA<NetworkFailure>()),
      );
    });

    // mobile-qa gap-fix — reschedule is the SECOND booking-WRITE call site
    // `_mapBookingWriteException` covers (see that method's doc comment);
    // the createBooking group above exhaustively covers the decode/fallback
    // matrix, so this just pins that the same mapping is wired for reschedule
    // too, not a second full sweep.
    test('409 with a well-formed CLIENT_BOOKING_CONFLICT body → '
        'ClientBookingConflictFailure', () async {
      when(
        () => bookingApi.rescheduleBooking(
          bookingId: 'booking-1',
          rescheduleBookingRequest: any(named: 'rescheduleBookingRequest'),
        ),
      ).thenThrow(
        _dioBadResponseWithBody(
          409,
          _reschedulePath,
          _clientBookingConflictBody(),
        ),
      );

      await expectLater(
        repository.rescheduleBooking('booking-1', newStart),
        throwsA(
          isA<ClientBookingConflictFailure>().having(
            (f) => f.conflictingBookingId,
            'conflictingBookingId',
            'conflict-booking-1',
          ),
        ),
      );
    });

    test('429 → BookingRateLimitedFailure', () async {
      when(
        () => bookingApi.rescheduleBooking(
          bookingId: 'booking-1',
          rescheduleBookingRequest: any(named: 'rescheduleBookingRequest'),
        ),
      ).thenThrow(_dioBadResponse(429, _reschedulePath));

      await expectLater(
        repository.rescheduleBooking('booking-1', newStart),
        throwsA(isA<BookingRateLimitedFailure>()),
      );
    });

    // mobile-qa (elapsed read-only track) — reschedule is the WRITE-path call
    // site of the BOOKING_ALREADY_ELAPSED 409 (backend 952e441).
    // `_mapBookingWriteException` checks the elapsed code FIRST, ahead of both
    // the CLIENT_BOOKING_CONFLICT decode and the generic ConflictFailure
    // fallback — these two tests pin that ordering.
    test('409 BOOKING_ALREADY_ELAPSED → BookingAlreadyElapsedFailure (checked '
        'before the slot-conflict fallbacks)', () async {
      when(
        () => bookingApi.rescheduleBooking(
          bookingId: 'booking-1',
          rescheduleBookingRequest: any(named: 'rescheduleBookingRequest'),
        ),
      ).thenThrow(
        _dioBadResponseWithBody(
          409,
          _reschedulePath,
          _bookingAlreadyElapsedBody(),
        ),
      );

      await expectLater(
        repository.rescheduleBooking('booking-1', newStart),
        throwsA(isA<BookingAlreadyElapsedFailure>()),
      );
    });

    test(
      'a 409 with an unrelated data.code stays the generic ConflictFailure — '
      'the elapsed branch must not over-catch the write path',
      () async {
        when(
          () => bookingApi.rescheduleBooking(
            bookingId: 'booking-1',
            rescheduleBookingRequest: any(named: 'rescheduleBookingRequest'),
          ),
        ).thenThrow(
          _dioBadResponseWithBody(409, _reschedulePath, <String, dynamic>{
            'success': false,
            'data': <String, dynamic>{'code': 'SOME_OTHER_CODE'},
          }),
        );

        await expectLater(
          repository.rescheduleBooking('booking-1', newStart),
          throwsA(isA<ConflictFailure>()),
        );
      },
    );
  });

  group('getMyBookings', () {
    test('success: maps the paged envelope to PageResponse<Booking>', () async {
      final dto = _buildDetailDto();
      final envelope = _serializeMyBookingsEnvelope(
        [dto],
        page: 0,
        totalPages: 2,
        totalElements: 21,
      );
      when(
        () => dio.get<Map<String, dynamic>>(
          _myBookingsPath,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          data: envelope,
          requestOptions: RequestOptions(path: _myBookingsPath),
          statusCode: 200,
        ),
      );

      final page = await repository.getMyBookings(
        status: BookingStatus.pending,
        page: 0,
      );

      expect(page.items, hasLength(1));
      expect(page.items.single.id, 'booking-1');
      expect(page.page, 0);
      expect(page.totalPages, 2);
      expect(page.totalElements, 21);
      expect(page.hasMore, isTrue);

      final captured =
          verify(
                () => dio.get<Map<String, dynamic>>(
                  _myBookingsPath,
                  queryParameters: captureAny(named: 'queryParameters'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['page'], 0);
      expect(captured['size'], kBookingsPageSize);
      expect(captured['status'], 'PENDING');
    });

    test('status null omits the status query param', () async {
      final envelope = _serializeMyBookingsEnvelope(const []);
      when(
        () => dio.get<Map<String, dynamic>>(
          _myBookingsPath,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          data: envelope,
          requestOptions: RequestOptions(path: _myBookingsPath),
          statusCode: 200,
        ),
      );

      final page = await repository.getMyBookings(status: null, page: 0);
      expect(page.items, isEmpty);

      final captured =
          verify(
                () => dio.get<Map<String, dynamic>>(
                  _myBookingsPath,
                  queryParameters: captureAny(named: 'queryParameters'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured.containsKey('status'), isFalse);
    });

    test('network error → NetworkFailure', () async {
      when(
        () => dio.get<Map<String, dynamic>>(
          _myBookingsPath,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenThrow(_dioConnectionError(_myBookingsPath));

      await expectLater(
        repository.getMyBookings(status: null, page: 0),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('malformed body (unrecognized enum wire value) → UnknownFailure, '
        'not a raw exception', () async {
      // Simulates a future/unrecognized `status` wire value reaching the
      // client — e.g. a backend enum addition the mobile hasn't caught up
      // to yet. `standardSerializers.deserialize` throws its own
      // (non-DioException, non-Failure) error in this case
      // (`BookingDetailResponseStatusEnum.valueOf` → `ArgumentError`), which
      // must be caught by `_deserialize` and re-surfaced as [UnknownFailure]
      // rather than escaping as a raw, unmapped exception.
      final envelope = _serializeMyBookingsEnvelope([_buildDetailDto()]);
      final pageMap = envelope['data'] as Map<String, dynamic>;
      final items = pageMap['data'] as List<dynamic>;
      final firstItem = Map<String, dynamic>.from(
        items.first as Map<String, dynamic>,
      );
      firstItem['status'] = 'FUTURE_STATUS_NOT_YET_KNOWN';
      pageMap['data'] = <dynamic>[firstItem];

      when(
        () => dio.get<Map<String, dynamic>>(
          _myBookingsPath,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          data: envelope,
          requestOptions: RequestOptions(path: _myBookingsPath),
          statusCode: 200,
        ),
      );

      await expectLater(
        repository.getMyBookings(status: null, page: 0),
        throwsA(isA<UnknownFailure>()),
      );
    });

    test('pre-mapped Failure on e.error is re-thrown unchanged', () async {
      const mapped = UnauthorizedFailure();
      when(
        () => dio.get<Map<String, dynamic>>(
          _myBookingsPath,
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _myBookingsPath),
          type: DioExceptionType.badResponse,
          error: mapped,
        ),
      );

      await expectLater(
        repository.getMyBookings(status: null, page: 0),
        throwsA(same(mapped)),
      );
    });
  });
}
