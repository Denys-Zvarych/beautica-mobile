// Track 7.x Wave B — mobile-qa GAP-FIX: unit tests for
// [HttpClientReviewRepository].
//
// WHY THIS FILE EXISTS
// ---------------------
// `leave_client_feedback_screen_test.dart` and the master_leave_client_
// feedback_flow_test.dart integration test both exercise
// [ClientReviewRepository] through its INTERFACE — a mocked implementation in
// the widget suite, a real backend double (`FakeBackend`) in the integration
// suite. Neither proves what [HttpClientReviewRepository] itself does at the
// wire-construction boundary:
//   • the blank/whitespace-only comment → null trimming (mirrors
//     `HttpBookingRepository.createReview`'s identical rule for the CLIENT→
//     MASTER direction, which likewise has no dedicated repository-level
//     unit test — this file closes the gap for the NEW Wave B path without
//     assuming the old one is exempt by precedent);
//   • the exact `CreateClientReviewRequest` body reaching
//     `ClientReviewControllerApi.create`;
//   • the 409 / 403 / 400 / 422 → typed-[Failure] status-code mapping
//     (`_mapClientReviewException`), which runs BEFORE deferring to any
//     [Failure] the [ErrorMapperInterceptor] may have attached;
//   • the transport-level fallback (`_mapDioException`) for network errors,
//     an already-mapped [Failure] on `DioException.error`, and the generic
//     [ServerFailure] catch-all.
//
// Mocks [ClientReviewControllerApi] with mocktail — mirrors
// `booking_repository_test.dart`'s `_MockReviewControllerApi` pattern
// (Repository test structure, mobile-qa non-negotiable). Pure Dart: no
// ProviderScope, no widget tree.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/booking/data/client_review_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockClientReviewControllerApi extends Mock
    implements ClientReviewControllerApi {}

const String _path = '/api/v1/client-reviews';

DioException _dioBadResponse(int statusCode) => DioException(
  requestOptions: RequestOptions(path: _path),
  type: DioExceptionType.badResponse,
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: _path),
    statusCode: statusCode,
  ),
);

Response<ApiResponseClientReviewResponse> _successResponse() =>
    Response<ApiResponseClientReviewResponse>(
      data: ApiResponseClientReviewResponse((b) => b.success = true),
      requestOptions: RequestOptions(path: _path),
      statusCode: 201,
    );

void main() {
  late _MockClientReviewControllerApi api;
  late HttpClientReviewRepository repository;

  setUpAll(() {
    // mocktail needs a concrete fallback instance whenever any(named: ...) /
    // captureAny(named: ...) is used with a non-primitive type.
    registerFallbackValue(
      CreateClientReviewRequest(
        (b) => b
          ..bookingId = 'fallback-booking'
          ..rating = 1,
      ),
    );
  });

  setUp(() {
    api = _MockClientReviewControllerApi();
    repository = HttpClientReviewRepository(api);
  });

  group('createClientReview — request body', () {
    test('sends the exact bookingId, rating and comment', () async {
      when(
        () => api.create(
          createClientReviewRequest: any(named: 'createClientReviewRequest'),
        ),
      ).thenAnswer((_) async => _successResponse());

      await repository.createClientReview(
        bookingId: 'booking-1',
        rating: 5,
        comment: 'Пунктуальна, приємна клієнтка.',
      );

      final captured = verify(
        () => api.create(
          createClientReviewRequest: captureAny(
            named: 'createClientReviewRequest',
          ),
        ),
      ).captured;
      final body = captured.single as CreateClientReviewRequest;
      expect(body.bookingId, 'booking-1');
      expect(body.rating, 5);
      expect(body.comment, 'Пунктуальна, приємна клієнтка.');
    });

    test('an empty-string comment is sent as null (never an empty string on '
        'the wire)', () async {
      when(
        () => api.create(
          createClientReviewRequest: any(named: 'createClientReviewRequest'),
        ),
      ).thenAnswer((_) async => _successResponse());

      await repository.createClientReview(
        bookingId: 'booking-1',
        rating: 4,
        comment: '',
      );

      final captured = verify(
        () => api.create(
          createClientReviewRequest: captureAny(
            named: 'createClientReviewRequest',
          ),
        ),
      ).captured;
      final body = captured.single as CreateClientReviewRequest;
      expect(body.comment, isNull);
    });

    test('a whitespace-only comment is trimmed to null', () async {
      when(
        () => api.create(
          createClientReviewRequest: any(named: 'createClientReviewRequest'),
        ),
      ).thenAnswer((_) async => _successResponse());

      await repository.createClientReview(
        bookingId: 'booking-1',
        rating: 3,
        comment: '   \n\t  ',
      );

      final captured = verify(
        () => api.create(
          createClientReviewRequest: captureAny(
            named: 'createClientReviewRequest',
          ),
        ),
      ).captured;
      final body = captured.single as CreateClientReviewRequest;
      expect(body.comment, isNull);
    });

    test('a null comment stays null', () async {
      when(
        () => api.create(
          createClientReviewRequest: any(named: 'createClientReviewRequest'),
        ),
      ).thenAnswer((_) async => _successResponse());

      await repository.createClientReview(bookingId: 'booking-1', rating: 2);

      final captured = verify(
        () => api.create(
          createClientReviewRequest: captureAny(
            named: 'createClientReviewRequest',
          ),
        ),
      ).captured;
      final body = captured.single as CreateClientReviewRequest;
      expect(body.comment, isNull);
    });

    test('leading/trailing whitespace around real text is trimmed, not just '
        'blanked', () async {
      when(
        () => api.create(
          createClientReviewRequest: any(named: 'createClientReviewRequest'),
        ),
      ).thenAnswer((_) async => _successResponse());

      await repository.createClientReview(
        bookingId: 'booking-1',
        rating: 5,
        comment: '  Дуже приємна клієнтка  ',
      );

      final captured = verify(
        () => api.create(
          createClientReviewRequest: captureAny(
            named: 'createClientReviewRequest',
          ),
        ),
      ).captured;
      final body = captured.single as CreateClientReviewRequest;
      expect(body.comment, 'Дуже приємна клієнтка');
    });
  });

  group('createClientReview — status-code mapping', () {
    test('409 → ClientReviewAlreadyExistsFailure', () async {
      when(
        () => api.create(
          createClientReviewRequest: any(named: 'createClientReviewRequest'),
        ),
      ).thenThrow(_dioBadResponse(409));

      await expectLater(
        repository.createClientReview(bookingId: 'booking-1', rating: 5),
        throwsA(isA<ClientReviewAlreadyExistsFailure>()),
      );
    });

    test('403 (not the provider) → ClientReviewNotAllowedFailure', () async {
      when(
        () => api.create(
          createClientReviewRequest: any(named: 'createClientReviewRequest'),
        ),
      ).thenThrow(_dioBadResponse(403));

      await expectLater(
        repository.createClientReview(bookingId: 'booking-1', rating: 5),
        throwsA(isA<ClientReviewNotAllowedFailure>()),
      );
    });

    test('400 (e.g. booking not COMPLETED / guest booking) → '
        'ClientReviewNotAllowedFailure', () async {
      when(
        () => api.create(
          createClientReviewRequest: any(named: 'createClientReviewRequest'),
        ),
      ).thenThrow(_dioBadResponse(400));

      await expectLater(
        repository.createClientReview(bookingId: 'booking-1', rating: 5),
        throwsA(isA<ClientReviewNotAllowedFailure>()),
      );
    });

    test('422 → ClientReviewNotAllowedFailure', () async {
      when(
        () => api.create(
          createClientReviewRequest: any(named: 'createClientReviewRequest'),
        ),
      ).thenThrow(_dioBadResponse(422));

      await expectLater(
        repository.createClientReview(bookingId: 'booking-1', rating: 5),
        throwsA(isA<ClientReviewNotAllowedFailure>()),
      );
    });

    test('an unrelated 4xx/5xx falls through to the generic ServerFailure '
        'carrying the status code', () async {
      when(
        () => api.create(
          createClientReviewRequest: any(named: 'createClientReviewRequest'),
        ),
      ).thenThrow(_dioBadResponse(500));

      await expectLater(
        repository.createClientReview(bookingId: 'booking-1', rating: 5),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('connectionError → NetworkFailure', () async {
      when(
        () => api.create(
          createClientReviewRequest: any(named: 'createClientReviewRequest'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _path),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        repository.createClientReview(bookingId: 'booking-1', rating: 5),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('receiveTimeout → NetworkFailure', () async {
      when(
        () => api.create(
          createClientReviewRequest: any(named: 'createClientReviewRequest'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: _path),
          type: DioExceptionType.receiveTimeout,
        ),
      );

      await expectLater(
        repository.createClientReview(bookingId: 'booking-1', rating: 5),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test(
      'a Failure already attached by ErrorMapperInterceptor (e.error) on a '
      'status code outside the 409/403/400/422 set is rethrown UNCHANGED',
      () async {
        // Status 500 is NOT one of the client-review-specific codes, so
        // `_mapClientReviewException` defers to `_mapDioException`, which
        // honours a pre-mapped `e.error` before falling back to a generic
        // ServerFailure — mirrors `booking_repository_test.dart`'s
        // '404 → NotFoundFailure' precedent for `getBookingById`.
        const mapped = ConflictFailure();
        when(
          () => api.create(
            createClientReviewRequest: any(named: 'createClientReviewRequest'),
          ),
        ).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: _path),
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: _path),
              statusCode: 500,
            ),
            error: mapped,
          ),
        );

        await expectLater(
          repository.createClientReview(bookingId: 'booking-1', rating: 5),
          throwsA(same(mapped)),
        );
      },
    );
  });
}
