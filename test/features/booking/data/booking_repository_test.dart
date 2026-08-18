// Phase 14.0 — Unit tests for [HttpBookingRepository].
//
// Strategy:
//   createBooking / getBookingById / cancelBooking / rescheduleBooking — mock
//   [BookingControllerApi] with mocktail; verify domain mapping + error
//   propagation.
//   getMyBookings — mock [Dio] directly and feed the SERIALIZED envelope (via
//   `standardSerializers`), exercising the real raw-GET ROW-BY-ROW parse path
//   (`_decodeBookingsPage`, which replaced a single atomic whole-envelope
//   deserialize so one bad row can no longer blank the page) — mirrors
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
import 'package:beautica_mobile/features/booking/domain/booking_partition.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/create_booking_request.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

class _MockBookingControllerApi extends Mock implements BookingControllerApi {}

class _MockReviewControllerApi extends Mock implements ReviewControllerApi {}

const _createPath = '/api/v1/bookings';
const _getPath = '/api/v1/bookings/booking-1';
const _cancelPath = '/api/v1/bookings/booking-1/cancel';
const _reschedulePath = '/api/v1/bookings/booking-1/reschedule';
const _declinePath = '/api/v1/bookings/booking-1/decline';
const _completePath = '/api/v1/bookings/booking-1/complete';
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

  /// Left `null` by default so the builder never emits the `awaitingClosure`
  /// key on serialize (see `_$BookingDetailResponseSerializer.serialize`'s
  /// `if (object.awaitingClosure != null)` guard) — this is what makes the
  /// default fixture double as the Phase 226 stale-backend "key absent"
  /// fixture without a second builder.
  bool? awaitingClosure,
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
          ..masterType = masterType
          ..awaitingClosure = awaitingClosure)
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
  late _MockReviewControllerApi reviewApi;
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
    registerFallbackValue(
      StatusUpdateRequest(
        (b) => b.cancellationReason =
            StatusUpdateRequestCancellationReasonEnum.PROVIDER_UNAVAILABLE,
      ),
    );
  });

  setUp(() {
    dio = _MockDio();
    bookingApi = _MockBookingControllerApi();
    reviewApi = _MockReviewControllerApi();
    repository = HttpBookingRepository(dio, bookingApi, reviewApi);
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
        // POST /bookings now returns ApiResponseBookingDetailResponse (backend
        // feat/multi-service-appointments). createBooking still reads only
        // `.data?.data?.id` and does a follow-up getBookingById, so a minimal
        // detail DTO carrying just the id is all this stub needs.
        final createdDto = (BookingDetailResponseBuilder()..id = 'booking-1')
            .build();
        when(
          () => bookingApi.createBooking(
            createBookingRequest: any(named: 'createBookingRequest'),
            idempotencyKey: any(named: 'idempotencyKey'),
          ),
        ).thenAnswer(
          (_) async => Response<ApiResponseBookingDetailResponse>(
            data: ApiResponseBookingDetailResponse(
              (b) => b
                ..data.replace(createdDto)
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
      final createdDto = BookingDetailResponseBuilder().build(); // id unset
      when(
        () => bookingApi.createBooking(
          createBookingRequest: any(named: 'createBookingRequest'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer(
        (_) async => Response<ApiResponseBookingDetailResponse>(
          data: ApiResponseBookingDetailResponse(
            (b) => b
              ..data.replace(createdDto)
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

    // mobile-qa gap-fix (Phase 226 audit) — the two `awaitingClosure` tests
    // added under `getMyBookings` only pin the LIST path
    // (`_decodeBookingsPage` → raw-JSON `beauticaSerializers` round trip).
    // `getBookingById` is a SEPARATE call site — it goes through the
    // generated `BookingControllerApi.getBooking` / its own
    // `_serializers.deserialize`, then the SAME `BookingMapper.fromDto` — and
    // had no assertion on `awaitingClosure` in either direction. Both call
    // sites share the mapper, but only testing one leaves the OTHER
    // production entrypoint (the booking detail screen) unpinned: a future
    // change that special-cased one call site over the other (e.g. an
    // intermediate DTO transform before `fromDto`) would pass every existing
    // test while breaking `awaitingClosure` on «Деталі запису» specifically.
    test('maps awaitingClosure: true through the DETAIL endpoint onto '
        'Booking.awaitingClosure', () async {
      final dto = _buildDetailDto(awaitingClosure: true);
      when(
        () => bookingApi.getBooking(bookingId: 'booking-1'),
      ).thenAnswer((_) async => _detailResponse(dto));

      final booking = await repository.getBookingById('booking-1');

      expect(booking.awaitingClosure, isTrue);
    });

    test('awaitingClosure absent on the DETAIL endpoint (stale/pre-29.2 '
        'backend) decodes to false, without throwing', () async {
      // [_buildDetailDto]'s default already leaves the builder field null,
      // which is what makes the fixture double as the "key absent" case —
      // see its doc comment.
      final dto = _buildDetailDto();
      when(
        () => bookingApi.getBooking(bookingId: 'booking-1'),
      ).thenAnswer((_) async => _detailResponse(dto));

      final booking = await repository.getBookingById('booking-1');

      expect(booking.awaitingClosure, isFalse);
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

  // Track 27.x Wave A — the PROVIDER decline write path.
  group('declineBooking', () {
    test('success: always sends PROVIDER_UNAVAILABLE with comment as the '
        'optional free text', () async {
      when(
        () => bookingApi.declineBooking(
          bookingId: any(named: 'bookingId'),
          statusUpdateRequest: any(named: 'statusUpdateRequest'),
        ),
      ).thenAnswer(
        (_) async => Response<void>(
          requestOptions: RequestOptions(path: _declinePath),
          statusCode: 200,
        ),
      );

      await repository.declineBooking('booking-1', comment: 'ill, apologies');

      final captured = verify(
        () => bookingApi.declineBooking(
          bookingId: captureAny(named: 'bookingId'),
          statusUpdateRequest: captureAny(named: 'statusUpdateRequest'),
        ),
      ).captured;
      expect(captured[0], 'booking-1');
      final body = captured[1] as StatusUpdateRequest;
      expect(
        body.cancellationReason,
        StatusUpdateRequestCancellationReasonEnum.PROVIDER_UNAVAILABLE,
      );
      expect(body.comment, 'ill, apologies');
    });

    test(
      'success with no comment: comment is null (blank is trimmed too)',
      () async {
        when(
          () => bookingApi.declineBooking(
            bookingId: any(named: 'bookingId'),
            statusUpdateRequest: any(named: 'statusUpdateRequest'),
          ),
        ).thenAnswer(
          (_) async => Response<void>(
            requestOptions: RequestOptions(path: _declinePath),
            statusCode: 200,
          ),
        );

        await repository.declineBooking('booking-1', comment: '   ');

        final captured =
            verify(
                  () => bookingApi.declineBooking(
                    bookingId: any(named: 'bookingId'),
                    statusUpdateRequest: captureAny(
                      named: 'statusUpdateRequest',
                    ),
                  ),
                ).captured.single
                as StatusUpdateRequest;
        expect(captured.comment, isNull);
      },
    );

    test('connectionError → NetworkFailure', () async {
      when(
        () => bookingApi.declineBooking(
          bookingId: any(named: 'bookingId'),
          statusUpdateRequest: any(named: 'statusUpdateRequest'),
        ),
      ).thenThrow(_dioConnectionError(_declinePath));

      await expectLater(
        repository.declineBooking('booking-1'),
        throwsA(isA<NetworkFailure>()),
      );
    });

    // Unlike cancelBooking's BOOKING_ALREADY_ELAPSED, the backend's Phase
    // 27.1 BookingTemporalGuard throws a plain BusinessException with NO
    // typed data.code envelope — GlobalExceptionHandler.handleBusiness
    // genericises every CONFLICT body to {"data": null}. So EVERY 409 from
    // this endpoint maps to ProviderDeclineWindowClosedFailure, by call site
    // — see that failure's doc.
    test(
      'ANY 409 (even with no body at all) → ProviderDeclineWindowClosedFailure',
      () async {
        when(
          () => bookingApi.declineBooking(
            bookingId: any(named: 'bookingId'),
            statusUpdateRequest: any(named: 'statusUpdateRequest'),
          ),
        ).thenThrow(_dioBadResponse(409, _declinePath));

        await expectLater(
          repository.declineBooking('booking-1'),
          throwsA(isA<ProviderDeclineWindowClosedFailure>()),
        );
      },
    );

    test('a 409 carrying an UNRELATED data.code still maps to '
        'ProviderDeclineWindowClosedFailure — the mapping is by call site, not '
        'by body content', () async {
      when(
        () => bookingApi.declineBooking(
          bookingId: any(named: 'bookingId'),
          statusUpdateRequest: any(named: 'statusUpdateRequest'),
        ),
      ).thenThrow(
        _dioBadResponseWithBody(409, _declinePath, <String, dynamic>{
          'success': false,
          'data': <String, dynamic>{'code': 'SOME_OTHER_CODE'},
        }),
      );

      await expectLater(
        repository.declineBooking('booking-1'),
        throwsA(isA<ProviderDeclineWindowClosedFailure>()),
      );
    });

    test(
      'a non-409 bad response (e.g. 403) stays a generic ServerFailure',
      () async {
        when(
          () => bookingApi.declineBooking(
            bookingId: any(named: 'bookingId'),
            statusUpdateRequest: any(named: 'statusUpdateRequest'),
          ),
        ).thenThrow(_dioBadResponse(403, _declinePath));

        await expectLater(
          repository.declineBooking('booking-1'),
          throwsA(
            isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 403),
          ),
        );
      },
    );
  });

  // Track 27.x Wave A — the PROVIDER complete write path.
  group('completeBooking', () {
    test('success: no request body', () async {
      when(
        () => bookingApi.completeBooking(bookingId: any(named: 'bookingId')),
      ).thenAnswer(
        (_) async => Response<void>(
          requestOptions: RequestOptions(path: _completePath),
          statusCode: 200,
        ),
      );

      await repository.completeBooking('booking-1');

      verify(
        () => bookingApi.completeBooking(bookingId: 'booking-1'),
      ).called(1);
    });

    test('connectionError → NetworkFailure', () async {
      when(
        () => bookingApi.completeBooking(bookingId: any(named: 'bookingId')),
      ).thenThrow(_dioConnectionError(_completePath));

      await expectLater(
        repository.completeBooking('booking-1'),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('ANY 409 → ProviderCompleteNotStartedFailure — same no-typed-code '
        'reasoning as declineBooking', () async {
      when(
        () => bookingApi.completeBooking(bookingId: any(named: 'bookingId')),
      ).thenThrow(_dioBadResponse(409, _completePath));

      await expectLater(
        repository.completeBooking('booking-1'),
        throwsA(isA<ProviderCompleteNotStartedFailure>()),
      );
    });

    test(
      'a non-409 bad response (e.g. 403) stays a generic ServerFailure',
      () async {
        when(
          () => bookingApi.completeBooking(bookingId: any(named: 'bookingId')),
        ).thenThrow(_dioBadResponse(403, _completePath));

        await expectLater(
          repository.completeBooking('booking-1'),
          throwsA(
            isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 403),
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
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          data: envelope,
          requestOptions: RequestOptions(path: _myBookingsPath),
          statusCode: 200,
        ),
      );

      final page = await repository.getMyBookings(
        statuses: const <BookingStatus>{BookingStatus.confirmed},
        sort: BookingSort.newest,
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
                  cancelToken: any(named: 'cancelToken'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['page'], 0);
      expect(captured['size'], kBookingsPageSize);
      expect(captured['status'], <String>['CONFIRMED']);
      expect(captured['sort'], 'startsAt,desc');
    });

    test(
      'mobile-perf MEDIUM-3 (2026-07-20): a supplied cancelToken reaches the '
      'underlying dio.get call UNCHANGED — an abandoned rail-scrub request '
      'must actually be abortable, not silently dropped on the floor',
      () async {
        final envelope = _serializeMyBookingsEnvelope(const []);
        when(
          () => dio.get<Map<String, dynamic>>(
            _myBookingsPath,
            queryParameters: any(named: 'queryParameters'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => Response<Map<String, dynamic>>(
            data: envelope,
            requestOptions: RequestOptions(path: _myBookingsPath),
            statusCode: 200,
          ),
        );

        final CancelToken token = CancelToken();
        await repository.getMyBookings(
          statuses: const <BookingStatus>{},
          sort: BookingSort.newest,
          page: 0,
          cancelToken: token,
        );

        final captured =
            verify(
                  () => dio.get<Map<String, dynamic>>(
                    _myBookingsPath,
                    queryParameters: any(named: 'queryParameters'),
                    cancelToken: captureAny(named: 'cancelToken'),
                  ),
                ).captured.single
                as CancelToken?;
        expect(captured, same(token));
      },
    );

    test(
      'multiple statuses are sent as a repeated status list, not a single '
      'value (backend Phase 26.1 — one request per tab, server-unioned)',
      () async {
        final envelope = _serializeMyBookingsEnvelope(const []);
        when(
          () => dio.get<Map<String, dynamic>>(
            _myBookingsPath,
            queryParameters: any(named: 'queryParameters'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => Response<Map<String, dynamic>>(
            data: envelope,
            requestOptions: RequestOptions(path: _myBookingsPath),
            statusCode: 200,
          ),
        );

        await repository.getMyBookings(
          statuses: const <BookingStatus>{
            BookingStatus.completed,
            BookingStatus.notCompleted,
          },
          sort: BookingSort.newest,
          page: 0,
        );

        final captured =
            verify(
                  () => dio.get<Map<String, dynamic>>(
                    _myBookingsPath,
                    queryParameters: captureAny(named: 'queryParameters'),
                    cancelToken: any(named: 'cancelToken'),
                  ),
                ).captured.single
                as Map<String, dynamic>;
        expect((captured['status'] as List<Object?>).toSet(), <String>{
          'COMPLETED',
          'NOT_COMPLETED',
        });
      },
    );

    test(
      'BookingSort.oldest renders sort=startsAt,asc (Майбутні — soonest-first)',
      (() async {
        final envelope = _serializeMyBookingsEnvelope(const []);
        when(
          () => dio.get<Map<String, dynamic>>(
            _myBookingsPath,
            queryParameters: any(named: 'queryParameters'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => Response<Map<String, dynamic>>(
            data: envelope,
            requestOptions: RequestOptions(path: _myBookingsPath),
            statusCode: 200,
          ),
        );

        await repository.getMyBookings(
          statuses: const <BookingStatus>{BookingStatus.confirmed},
          sort: BookingSort.oldest,
          page: 0,
        );

        final captured =
            verify(
                  () => dio.get<Map<String, dynamic>>(
                    _myBookingsPath,
                    queryParameters: captureAny(named: 'queryParameters'),
                    cancelToken: any(named: 'cancelToken'),
                  ),
                ).captured.single
                as Map<String, dynamic>;
        expect(captured['sort'], 'startsAt,asc');
      }),
    );

    test('empty statuses omits the status query param', () async {
      final envelope = _serializeMyBookingsEnvelope(const []);
      when(
        () => dio.get<Map<String, dynamic>>(
          _myBookingsPath,
          queryParameters: any(named: 'queryParameters'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          data: envelope,
          requestOptions: RequestOptions(path: _myBookingsPath),
          statusCode: 200,
        ),
      );

      final page = await repository.getMyBookings(
        statuses: const <BookingStatus>{},
        sort: BookingSort.newest,
        page: 0,
      );
      expect(page.items, isEmpty);

      final captured =
          verify(
                () => dio.get<Map<String, dynamic>>(
                  _myBookingsPath,
                  queryParameters: captureAny(named: 'queryParameters'),
                  cancelToken: any(named: 'cancelToken'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured.containsKey('status'), isFalse);
      // sort is unconditional — always sent regardless of the status filter.
      expect(captured['sort'], 'startsAt,desc');
    });

    test('network error → NetworkFailure', () async {
      when(
        () => dio.get<Map<String, dynamic>>(
          _myBookingsPath,
          queryParameters: any(named: 'queryParameters'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenThrow(_dioConnectionError(_myBookingsPath));

      await expectLater(
        repository.getMyBookings(
          statuses: const <BookingStatus>{},
          sort: BookingSort.newest,
          page: 0,
        ),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('an unrecognized `status` wire value decodes to BookingStatus.unknown '
        'and the row is KEPT — it must not fail or blank the page', () async {
      // This test used to assert `throwsA(isA<UnknownFailure>())`, pinning the
      // DEFECT rather than the contract: `standardSerializers` threw
      // `ArgumentError` out of `BookingDetailResponseStatusEnum.valueOf`, the
      // whole-envelope deserialize propagated it, and «Мої записи» went EMPTY
      // — for the entire page, over ONE row. Worse, on the detail screen the
      // resulting `Failure` is neither an `Error` nor a `ProviderException`,
      // so Riverpod's `defaultRetry` retried it ~10 times over ~38s behind an
      // indefinite spinner.
      //
      // `UnknownEnumTolerancePlugin` (`core/network/`) now strips the value
      // before it reaches the enum serializer, so the documented
      // keep-and-deny contract in `booking_mapper.dart` finally applies on the
      // wire: the row survives as [BookingStatus.unknown], which renders
      // read-only and grants none of `confirmed`'s capabilities.
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
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          data: envelope,
          requestOptions: RequestOptions(path: _myBookingsPath),
          statusCode: 200,
        ),
      );

      final page = await repository.getMyBookings(
        statuses: const <BookingStatus>{},
        sort: BookingSort.newest,
        page: 0,
      );

      expect(page.items, hasLength(1));
      expect(page.items.single.id, 'booking-1');
      expect(page.items.single.status, BookingStatus.unknown);
    });

    test('ONE structurally broken row is skipped; its siblings still render '
        'and the SERVER page counters are preserved', () async {
      // The page is decoded ROW BY ROW, so a row that cannot be parsed at all
      // (here: a non-date `startsAt`) is dropped on its own instead of taking
      // the page down with it. `totalElements`/`totalPages` deliberately stay
      // the SERVER's values — they are the pager's cursor state, and
      // recomputing them from the surviving rows would convince the pager it
      // had reached the end of the list.
      final envelope = _serializeMyBookingsEnvelope(
        [_buildDetailDto(id: 'booking-1'), _buildDetailDto(id: 'booking-2')],
        totalPages: 3,
        totalElements: 42,
      );
      final pageMap = envelope['data'] as Map<String, dynamic>;
      final items = pageMap['data'] as List<dynamic>;
      final broken = Map<String, dynamic>.from(
        items.first as Map<String, dynamic>,
      );
      broken['startsAt'] = 'not-a-timestamp';
      pageMap['data'] = <dynamic>[broken, items.last];

      when(
        () => dio.get<Map<String, dynamic>>(
          _myBookingsPath,
          queryParameters: any(named: 'queryParameters'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          data: envelope,
          requestOptions: RequestOptions(path: _myBookingsPath),
          statusCode: 200,
        ),
      );

      final page = await repository.getMyBookings(
        statuses: const <BookingStatus>{},
        sort: BookingSort.newest,
        page: 0,
      );

      expect(page.items, hasLength(1));
      expect(page.items.single.id, 'booking-2');
      expect(page.totalPages, 3);
      expect(page.totalElements, 42);
    });

    // ------------------------------------------------------------------
    // Envelope shape. ROW tolerance (the two tests above) must NOT have
    // become ENVELOPE tolerance.
    //
    // The row-by-row rewrite briefly returned `PageResponse(items: [],
    // totalPages: 0, totalElements: 0)` for a malformed envelope, which the
    // «Мої записи» screen renders BYTE-IDENTICALLY to the legitimate "you
    // have no bookings yet" empty state: no error copy, no retry button, no
    // way for the user to tell a broken response from an empty account. A
    // throw is what puts the screen into its `error:` branch. It also keeps
    // this method consistent with its sibling `getBookingById`, which throws
    // on a null envelope.
    // ------------------------------------------------------------------

    /// Every envelope shape that is NOT a decodable page, each of which must
    /// throw rather than degrade to an empty page.
    final Map<String, Map<String, dynamic>?>
    malformedEnvelopes = <String, Map<String, dynamic>?>{
      'a null body (empty 200 response)': null,
      'an envelope with no data key at all': <String, dynamic>{'success': true},
      'an envelope whose data is explicitly null (the error-envelope '
          'shape)': <String, dynamic>{
        'success': false,
        'data': null,
      },
      'an envelope whose data is a scalar, not an object': <String, dynamic>{
        'success': true,
        'data': 'oops',
      },
      'an envelope whose data is a LIST (page object skipped)':
          <String, dynamic>{'success': true, 'data': <dynamic>[]},
      'a page object with no rows key': <String, dynamic>{
        'success': true,
        'data': <String, dynamic>{'page': 0, 'totalPages': 1},
      },
      'a page object whose rows are null': <String, dynamic>{
        'success': true,
        'data': <String, dynamic>{'data': null, 'totalElements': 7},
      },
      'a page object whose rows are an object, not an array': <String, dynamic>{
        'success': true,
        'data': <String, dynamic>{'data': <String, dynamic>{}},
      },
    };

    for (final MapEntry<String, Map<String, dynamic>?> shape
        in malformedEnvelopes.entries) {
      test('${shape.key} throws instead of reading as an empty page', () async {
        when(
          () => dio.get<Map<String, dynamic>>(
            _myBookingsPath,
            queryParameters: any(named: 'queryParameters'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => Response<Map<String, dynamic>>(
            data: shape.value,
            requestOptions: RequestOptions(path: _myBookingsPath),
            statusCode: 200,
          ),
        );

        await expectLater(
          repository.getMyBookings(
            statuses: const <BookingStatus>{},
            sort: BookingSort.newest,
            page: 0,
          ),
          throwsA(isA<UnknownFailure>()),
        );
      });
    }

    test('a WELL-FORMED envelope carrying zero rows is a legitimate empty '
        'page and does NOT throw — the tolerance boundary is the envelope, '
        'not "any response with no bookings"', () async {
      final envelope = _serializeMyBookingsEnvelope(
        const [],
        page: 0,
        totalPages: 0,
        totalElements: 0,
      );
      when(
        () => dio.get<Map<String, dynamic>>(
          _myBookingsPath,
          queryParameters: any(named: 'queryParameters'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          data: envelope,
          requestOptions: RequestOptions(path: _myBookingsPath),
          statusCode: 200,
        ),
      );

      final page = await repository.getMyBookings(
        statuses: const <BookingStatus>{},
        sort: BookingSort.newest,
        page: 0,
      );

      expect(page.items, isEmpty);
      expect(page.totalElements, 0);
      expect(page.hasMore, isFalse);
    });

    test('every row being individually unparseable still returns a page, not '
        'a throw — row tolerance is unchanged by the envelope guard', () async {
      final envelope = _serializeMyBookingsEnvelope(
        [_buildDetailDto(id: 'booking-1'), _buildDetailDto(id: 'booking-2')],
        totalPages: 3,
        totalElements: 42,
      );
      final pageMap = envelope['data'] as Map<String, dynamic>;
      final items = pageMap['data'] as List<dynamic>;
      pageMap['data'] = <dynamic>[
        for (final Object? row in items)
          Map<String, dynamic>.from(row as Map<String, dynamic>)
            ..['startsAt'] = 'not-a-timestamp',
      ];

      when(
        () => dio.get<Map<String, dynamic>>(
          _myBookingsPath,
          queryParameters: any(named: 'queryParameters'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          data: envelope,
          requestOptions: RequestOptions(path: _myBookingsPath),
          statusCode: 200,
        ),
      );

      final page = await repository.getMyBookings(
        statuses: const <BookingStatus>{},
        sort: BookingSort.newest,
        page: 0,
      );

      expect(page.items, isEmpty);
      // The SERVER's counters survive: the pager must not conclude it reached
      // the end just because this page happened to decode to nothing.
      expect(page.totalPages, 3);
      expect(page.totalElements, 42);
    });

    // The test ABOVE breaks rows at the DESERIALIZATION boundary
    // ('startsAt': 'not-a-timestamp'), so it exercises
    // `_decodeBookingsPage`'s OWN `on Failure { continue; }` loop. A row can
    // also deserialize perfectly and then throw one layer later, during
    // MAPPING (`BookingMapper.fromDto` throws ServerFailure when id/startsAt/
    // endsAt is absent) — a DIFFERENT skip loop, in BookingMapper.fromDtoList.
    // Nothing covered that second loop end-to-end through the repository, so
    // the documented promise "one broken row is dropped instead of blanking
    // the whole page" was unproven for mapping failures specifically.
    //
    // The broken row is deliberately in the MIDDLE: a trailing broken row
    // cannot tell `continue` apart from `break`.
    //
    // The counters are deliberately values that CANNOT be produced by
    // recomputing from the 2 survivors (totalElements 57, totalPages 3). If a
    // future refactor "helpfully" derives the counters from `items.length`,
    // this fails — and it must, because shortening totalElements would also
    // convince the pager it had reached the end and silently strand the rest
    // of the user's history.
    test('a row that DESERIALIZES but fails MAPPING is skipped mid-page — the '
        'siblings survive and the SERVER page counters are preserved, not '
        'recomputed from the survivors', () async {
      final envelope = _serializeMyBookingsEnvelope(
        [
          _buildDetailDto(id: 'booking-1'),
          _buildDetailDto(id: 'booking-2'),
          _buildDetailDto(id: 'booking-3'),
        ],
        page: 1,
        totalPages: 3,
        totalElements: 57,
      );
      final pageMap = envelope['data'] as Map<String, dynamic>;
      final items = pageMap['data'] as List<dynamic>;
      pageMap['data'] = <dynamic>[
        for (int i = 0; i < items.length; i++)
          if (i == 1)
            // Row 2: valid JSON, deserializes into a BookingDetailResponse
            // with a null `id` — so it clears the deserialization loop and
            // throws inside fromDtoList instead.
            (Map<String, dynamic>.from(items[i] as Map<String, dynamic>)
              ..remove('id'))
          else
            Map<String, dynamic>.from(items[i] as Map<String, dynamic>),
      ];

      when(
        () => dio.get<Map<String, dynamic>>(
          _myBookingsPath,
          queryParameters: any(named: 'queryParameters'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          data: envelope,
          requestOptions: RequestOptions(path: _myBookingsPath),
          statusCode: 200,
        ),
      );

      final page = await repository.getMyBookings(
        statuses: const <BookingStatus>{},
        sort: BookingSort.newest,
        page: 1,
      );

      expect(
        page.items.map((b) => b.id).toList(),
        <String>['booking-1', 'booking-3'],
        reason:
            'the unmappable middle row is dropped and BOTH siblings '
            'survive in order. [booking-1] alone would mean fromDtoList '
            'ABORTED rather than continued; an empty list would mean the '
            'whole page was blanked.',
      );
      expect(
        page.totalElements,
        57,
        reason:
            'the SERVER cursor state is authoritative — never recomputed '
            'from the 2 surviving rows',
      );
      expect(page.totalPages, 3);
      expect(page.page, 1);
      expect(
        page.hasMore,
        isTrue,
        reason: 'dropping a row must not convince the pager it reached the end',
      );
    });

    test('pre-mapped Failure on e.error is re-thrown unchanged', () async {
      const mapped = UnauthorizedFailure();
      when(
        () => dio.get<Map<String, dynamic>>(
          _myBookingsPath,
          queryParameters: any(named: 'queryParameters'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _myBookingsPath),
          type: DioExceptionType.badResponse,
          error: mapped,
        ),
      );

      await expectLater(
        repository.getMyBookings(
          statuses: const <BookingStatus>{},
          sort: BookingSort.newest,
          page: 0,
        ),
        throwsA(same(mapped)),
      );
    });

    // Phase 226 — OpenAPI regen: `awaitingClosure` (backend 29.2) and the
    // wired-but-unused `partition` param (backend 28.2/29.3, cutover in
    // Phase 227). No behaviour change: these three tests pin the mapping
    // boundary and the byte-identical back-compat contract, they do not
    // exercise any new filtering behaviour.
    test(
      'decodes awaitingClosure: true off the wire onto Booking.awaitingClosure',
      () async {
        final envelope = _serializeMyBookingsEnvelope([
          _buildDetailDto(awaitingClosure: true),
        ]);
        when(
          () => dio.get<Map<String, dynamic>>(
            _myBookingsPath,
            queryParameters: any(named: 'queryParameters'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => Response<Map<String, dynamic>>(
            data: envelope,
            requestOptions: RequestOptions(path: _myBookingsPath),
            statusCode: 200,
          ),
        );

        final page = await repository.getMyBookings(
          statuses: const <BookingStatus>{},
          sort: BookingSort.newest,
          page: 0,
        );

        expect(page.items.single.awaitingClosure, isTrue);
      },
    );

    test(
      'awaitingClosure absent from the wire (stale/pre-29.2 backend) decodes '
      'to false, without throwing',
      () async {
        final envelope = _serializeMyBookingsEnvelope([_buildDetailDto()]);
        // Belt-and-braces: [_buildDetailDto]'s default already omits the key
        // on serialize (its builder field is left null), but the key is also
        // stripped explicitly here so this test keeps pinning the "key
        // absent" contract even if that default ever changes.
        final pageMap = envelope['data'] as Map<String, dynamic>;
        final items = pageMap['data'] as List<dynamic>;
        final row = Map<String, dynamic>.from(
          items.single as Map<String, dynamic>,
        )..remove('awaitingClosure');
        pageMap['data'] = <dynamic>[row];

        when(
          () => dio.get<Map<String, dynamic>>(
            _myBookingsPath,
            queryParameters: any(named: 'queryParameters'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => Response<Map<String, dynamic>>(
            data: envelope,
            requestOptions: RequestOptions(path: _myBookingsPath),
            statusCode: 200,
          ),
        );

        final page = await repository.getMyBookings(
          statuses: const <BookingStatus>{},
          sort: BookingSort.newest,
          page: 0,
        );

        expect(page.items, hasLength(1));
        expect(page.items.single.awaitingClosure, isFalse);
      },
    );

    test('getMyBookings called WITHOUT partition emits a query map with NO '
        '`partition` key at all — not partition=null, not "" — the '
        'byte-identical back-compat proof for Phase 226 (no caller passes it '
        'yet; Phase 227 is the cutover)', () async {
      final envelope = _serializeMyBookingsEnvelope(const []);
      when(
        () => dio.get<Map<String, dynamic>>(
          _myBookingsPath,
          queryParameters: any(named: 'queryParameters'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          data: envelope,
          requestOptions: RequestOptions(path: _myBookingsPath),
          statusCode: 200,
        ),
      );

      await repository.getMyBookings(
        statuses: const <BookingStatus>{BookingStatus.confirmed},
        sort: BookingSort.newest,
        page: 0,
      );

      final captured =
          verify(
                () => dio.get<Map<String, dynamic>>(
                  _myBookingsPath,
                  queryParameters: captureAny(named: 'queryParameters'),
                  cancelToken: any(named: 'cancelToken'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured.containsKey('partition'), isFalse);
    });

    test(
      'getMyBookings forwards an explicit partition as its wireValue string',
      () async {
        final envelope = _serializeMyBookingsEnvelope(const []);
        when(
          () => dio.get<Map<String, dynamic>>(
            _myBookingsPath,
            queryParameters: any(named: 'queryParameters'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => Response<Map<String, dynamic>>(
            data: envelope,
            requestOptions: RequestOptions(path: _myBookingsPath),
            statusCode: 200,
          ),
        );

        await repository.getMyBookings(
          statuses: const <BookingStatus>{},
          sort: BookingSort.newest,
          page: 0,
          partition: BookingPartition.awaitingClosure,
        );

        final captured =
            verify(
                  () => dio.get<Map<String, dynamic>>(
                    _myBookingsPath,
                    queryParameters: captureAny(named: 'queryParameters'),
                    cancelToken: any(named: 'cancelToken'),
                  ),
                ).captured.single
                as Map<String, dynamic>;
        // Pins that the WIRE string reaches the query map — `.wireValue`,
        // never `.name` or `.toString()` (both of which would happen to
        // agree with `wireValue` for this particular member, which is why
        // this asserts the exact literal rather than
        // `BookingPartition.awaitingClosure.wireValue`).
        expect(captured['partition'], 'AWAITING_CLOSURE');
      },
    );

    // Phase 227 — THE ROLLOUT SAFETY VALVE. `MyBookingsNotifier` is now a
    // real caller of BOTH params together on every request: `partition` is
    // what a Phase-28.2-capable backend actually filters on, but `status`
    // must ALSO still be on the wire, because Spring silently DROPS an
    // unrecognised `partition` query key rather than 400ing — a client that
    // sent `partition` alone against a backend without 28.2 would therefore
    // send, in effect, no filter at all, and `GET /bookings/me` would return
    // the caller's entire unfiltered booking history. This is the test that
    // proves the repository layer does not accidentally suppress `status`
    // once `partition` is also supplied (e.g. an `if (partition != null)
    // don't send status` shortcut would defeat the whole valve while every
    // other test in this group — which each pass only ONE of the two — would
    // stay green).
    test(
      'getMyBookings sends BOTH `status` and `partition` on the SAME request '
      'when both are supplied — partition does not suppress status on the '
      'wire (the backend, not this repository, decides precedence)',
      () async {
        final envelope = _serializeMyBookingsEnvelope(const []);
        when(
          () => dio.get<Map<String, dynamic>>(
            _myBookingsPath,
            queryParameters: any(named: 'queryParameters'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer(
          (_) async => Response<Map<String, dynamic>>(
            data: envelope,
            requestOptions: RequestOptions(path: _myBookingsPath),
            statusCode: 200,
          ),
        );

        await repository.getMyBookings(
          statuses: const <BookingStatus>{BookingStatus.confirmed},
          sort: BookingSort.oldest,
          page: 0,
          partition: BookingPartition.upcoming,
        );

        final captured =
            verify(
                  () => dio.get<Map<String, dynamic>>(
                    _myBookingsPath,
                    queryParameters: captureAny(named: 'queryParameters'),
                    cancelToken: any(named: 'cancelToken'),
                  ),
                ).captured.single
                as Map<String, dynamic>;
        expect(
          captured['status'],
          <String>['CONFIRMED'],
          reason:
              'status must still be present even though partition is '
              'also supplied — this is the whole point of the safety valve',
        );
        expect(captured['partition'], 'UPCOMING');
      },
    );

    test('BookingPartition.wireValue is pinned for every member — a renamed '
        'member must not silently change the wire contract', () {
      expect(BookingPartition.upcoming.wireValue, 'UPCOMING');
      expect(BookingPartition.past.wireValue, 'PAST');
      expect(BookingPartition.cancelled.wireValue, 'CANCELLED');
      expect(BookingPartition.awaitingClosure.wireValue, 'AWAITING_CLOSURE');
    });
  });
}
