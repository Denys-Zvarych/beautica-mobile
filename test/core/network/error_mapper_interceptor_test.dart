// Phase 2.2 — Unit tests for ErrorMapperInterceptor.
//
// Strategy: construct a real [ErrorMapperInterceptor] and drive [onError]
// directly with crafted [DioException]s. The [ErrorInterceptorHandler] is
// mocked with `mocktail` to capture the [DioException] passed to `reject`.
// The test then unwraps `error` from the captured exception and verifies it
// is the expected [Failure] subtype.
//
// No ProviderScope, no widget tree, no platform channels — pure Dart.
//
// Test cases:
//   1. HTTP 401 → UnauthorizedFailure
//   2. HTTP 404 → NotFoundFailure
//   3. HTTP 400 with field errors → ValidationFailure with correct fieldErrors
//   4. HTTP 500 → ServerFailure(statusCode: 500)
//   5. DioExceptionType.connectionTimeout → NetworkFailure
//   6. DioExceptionType.connectionError → NetworkFailure
//   7. DioExceptionType.receiveTimeout → NetworkFailure
//   8. HTTP 409 Conflict → ServerFailure(statusCode: 409)
//   9. HTTP 422 with field errors → ValidationFailure (SECURITY M3)
//  10. Field error value > 200 chars → truncated to 200 (SECURITY M1)

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/error_mapper_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocktail mock
// ---------------------------------------------------------------------------

class _MockErrorInterceptorHandler extends Mock
    implements ErrorInterceptorHandler {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a minimal [RequestOptions] for test use.
RequestOptions _opts({String path = '/test'}) =>
    RequestOptions(path: path, baseUrl: 'http://10.0.2.2:8080/api/v1');

/// Builds a [DioException] with a given HTTP status and optional response body.
DioException _httpError(int statusCode, {String path = '/test', dynamic body}) {
  final opts = _opts(path: path);
  return DioException(
    requestOptions: opts,
    response: Response<dynamic>(
      requestOptions: opts,
      statusCode: statusCode,
      data: body,
    ),
    type: DioExceptionType.badResponse,
  );
}

/// Builds a [DioException] for a network-level (no-response) error.
DioException _typeError(DioExceptionType type, {String path = '/test'}) =>
    DioException(
      requestOptions: _opts(path: path),
      type: type,
    );

/// Runs [onError] on a fresh [ErrorMapperInterceptor] and returns the
/// [DioException] that was passed to [ErrorInterceptorHandler.reject].
DioException _captureRejected(DioException input) {
  final handler = _MockErrorInterceptorHandler();
  final captured = <DioException>[];

  when(() => handler.reject(any())).thenAnswer((inv) {
    captured.add(inv.positionalArguments.first as DioException);
  });

  ErrorMapperInterceptor().onError(input, handler);

  expect(captured, hasLength(1), reason: 'handler.reject must be called once');
  return captured.first;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    // Register fallback values for mocktail.
    registerFallbackValue(
      DioException(requestOptions: _opts(), type: DioExceptionType.unknown),
    );
  });

  group('ErrorMapperInterceptor — HTTP status mapping', () {
    test('HTTP 401 → UnauthorizedFailure', () {
      final rejected = _captureRejected(_httpError(401));
      expect(rejected.error, isA<UnauthorizedFailure>());
    });

    test('HTTP 404 → NotFoundFailure', () {
      final rejected = _captureRejected(_httpError(404));
      expect(rejected.error, isA<NotFoundFailure>());
    });

    test(
      'HTTP 400 with field errors map → ValidationFailure with fieldErrors',
      () {
        final rejected = _captureRejected(
          _httpError(
            400,
            body: {
              'errors': {'email': 'Invalid format', 'name': 'Too short'},
            },
          ),
        );

        expect(rejected.error, isA<ValidationFailure>());
        final failure = rejected.error as ValidationFailure;
        expect(failure.fieldErrors['email'], 'Invalid format');
        expect(failure.fieldErrors['name'], 'Too short');
      },
    );

    test(
      'HTTP 400 with missing errors key → ValidationFailure with empty map',
      () {
        final rejected = _captureRejected(
          _httpError(400, body: {'message': 'Bad request'}),
        );

        expect(rejected.error, isA<ValidationFailure>());
        final failure = rejected.error as ValidationFailure;
        expect(failure.fieldErrors, isEmpty);
      },
    );

    test('HTTP 500 → ServerFailure with statusCode 500', () {
      final rejected = _captureRejected(_httpError(500));
      expect(rejected.error, isA<ServerFailure>());
      final failure = rejected.error as ServerFailure;
      expect(failure.statusCode, 500);
    });

    test('HTTP 503 → ServerFailure with statusCode 503', () {
      final rejected = _captureRejected(_httpError(503));
      expect(rejected.error, isA<ServerFailure>());
      final failure = rejected.error as ServerFailure;
      expect(failure.statusCode, 503);
    });

    test('HTTP 409 Conflict → ServerFailure(statusCode: 409)', () {
      final rejected = _captureRejected(_httpError(409));
      expect(rejected.error, isA<ServerFailure>());
      final failure = rejected.error as ServerFailure;
      expect(failure.statusCode, 409);
    });

    test('HTTP 403 (unmapped status) → UnknownFailure', () {
      final rejected = _captureRejected(_httpError(403));
      expect(rejected.error, isA<UnknownFailure>());
    });
  });

  group('ErrorMapperInterceptor — network-level errors', () {
    test('connectionTimeout → NetworkFailure', () {
      final rejected = _captureRejected(
        _typeError(DioExceptionType.connectionTimeout),
      );
      expect(rejected.error, isA<NetworkFailure>());
    });

    test('connectionError → NetworkFailure', () {
      final rejected = _captureRejected(
        _typeError(DioExceptionType.connectionError),
      );
      expect(rejected.error, isA<NetworkFailure>());
    });

    test('sendTimeout → NetworkFailure', () {
      final rejected = _captureRejected(
        _typeError(DioExceptionType.sendTimeout),
      );
      expect(rejected.error, isA<NetworkFailure>());
    });

    test('receiveTimeout → NetworkFailure', () {
      final rejected = _captureRejected(
        _typeError(DioExceptionType.receiveTimeout),
      );
      expect(rejected.error, isA<NetworkFailure>());
    });
  });

  group('ErrorMapperInterceptor — HTTP 422 (Spring @Validated)', () {
    test(
      'HTTP 422 with field errors map → ValidationFailure (SECURITY M3)',
      () {
        final rejected = _captureRejected(
          _httpError(
            422,
            body: {
              'errors': {'email': 'already in use'},
            },
          ),
        );

        expect(rejected.error, isA<ValidationFailure>());
        final failure = rejected.error as ValidationFailure;
        expect(failure.fieldErrors['email'], 'already in use');
      },
    );

    test(
      'HTTP 422 with missing errors key → ValidationFailure with empty map',
      () {
        final rejected = _captureRejected(
          _httpError(422, body: {'message': 'Unprocessable'}),
        );

        expect(rejected.error, isA<ValidationFailure>());
        final failure = rejected.error as ValidationFailure;
        expect(failure.fieldErrors, isEmpty);
      },
    );
  });

  group('ErrorMapperInterceptor — field error length cap (SECURITY M1)', () {
    test('field error value of 250 chars is truncated to 200 chars', () {
      final longValue = 'x' * 250;
      final rejected = _captureRejected(
        _httpError(
          400,
          body: {
            'errors': {'email': longValue},
          },
        ),
      );

      expect(rejected.error, isA<ValidationFailure>());
      final failure = rejected.error as ValidationFailure;
      expect(failure.fieldErrors['email']?.length, 200);
    });

    test('field error value of exactly 200 chars is kept as-is', () {
      final exactValue = 'a' * 200;
      final rejected = _captureRejected(
        _httpError(
          400,
          body: {
            'errors': {'name': exactValue},
          },
        ),
      );

      expect(rejected.error, isA<ValidationFailure>());
      final failure = rejected.error as ValidationFailure;
      expect(failure.fieldErrors['name'], exactValue);
      expect(failure.fieldErrors['name']?.length, 200);
    });

    test('field error value under 200 chars is kept as-is', () {
      const shortValue = 'must not be blank';
      final rejected = _captureRejected(
        _httpError(
          400,
          body: {
            'errors': {'phone': shortValue},
          },
        ),
      );

      expect(rejected.error, isA<ValidationFailure>());
      final failure = rejected.error as ValidationFailure;
      expect(failure.fieldErrors['phone'], shortValue);
    });
  });

  // ---------------------------------------------------------------------------
  // Phase 2.11 — verify-email typed-code envelope (backend Phase 1.5)
  // ---------------------------------------------------------------------------

  group('ErrorMapperInterceptor — verify-email typed errors', () {
    test(
      '400 with data.code = INVALID_CODE → VerificationFailure(invalidCode)',
      () {
        final rejected = _captureRejected(
          _httpError(
            400,
            path: '/auth/verify-email',
            body: {
              'success': false,
              'data': {'code': 'INVALID_CODE'},
            },
          ),
        );

        expect(rejected.error, isA<VerificationFailure>());
        expect(
          (rejected.error as VerificationFailure).code,
          equals(VerificationErrorCode.invalidCode),
        );
      },
    );

    test(
      '400 with data.code = CODE_EXPIRED → VerificationFailure(codeExpired)',
      () {
        final rejected = _captureRejected(
          _httpError(
            400,
            path: '/auth/verify-email',
            body: {
              'success': false,
              'data': {'code': 'CODE_EXPIRED'},
            },
          ),
        );

        expect(rejected.error, isA<VerificationFailure>());
        expect(
          (rejected.error as VerificationFailure).code,
          equals(VerificationErrorCode.codeExpired),
        );
      },
    );

    test(
      '400 with data.code = ALREADY_VERIFIED → VerificationFailure(alreadyVerified)',
      () {
        final rejected = _captureRejected(
          _httpError(
            400,
            path: '/auth/verify-email',
            body: {
              'success': false,
              'data': {'code': 'ALREADY_VERIFIED'},
            },
          ),
        );

        expect(rejected.error, isA<VerificationFailure>());
        expect(
          (rejected.error as VerificationFailure).code,
          equals(VerificationErrorCode.alreadyVerified),
        );
      },
    );

    test('400 with unknown wire code → falls back to invalidCode', () {
      final rejected = _captureRejected(
        _httpError(
          400,
          path: '/auth/verify-email',
          body: {
            'success': false,
            'data': {'code': 'SOME_FUTURE_CODE'},
          },
        ),
      );

      expect(rejected.error, isA<VerificationFailure>());
      expect(
        (rejected.error as VerificationFailure).code,
        equals(VerificationErrorCode.invalidCode),
      );
    });

    test(
      '400 on /auth/verify-email WITHOUT data.code key → ValidationFailure '
      'fallback (genuinely-malformed 400s still surface as field-errors)',
      () {
        final rejected = _captureRejected(
          _httpError(
            400,
            path: '/auth/verify-email',
            body: {
              'success': false,
              'errors': {'code': 'must not be blank'},
            },
          ),
        );

        // No data.code envelope → falls through to the generic 400 branch.
        expect(rejected.error, isA<ValidationFailure>());
        expect(rejected.error, isNot(isA<VerificationFailure>()));
      },
    );

    test('400 with data.code on a DIFFERENT path → ValidationFailure '
        '(typed-code mapping is scoped to /auth/verify-email)', () {
      final rejected = _captureRejected(
        _httpError(
          400,
          path: '/auth/login',
          body: {
            'success': false,
            'data': {'code': 'INVALID_CODE'},
          },
        ),
      );

      expect(rejected.error, isA<ValidationFailure>());
      expect(rejected.error, isNot(isA<VerificationFailure>()));
    });
  });

  // ---------------------------------------------------------------------------
  // Phase 2.11 — resend-verification 429 throttle (backend Phase 1.6)
  // ---------------------------------------------------------------------------

  group('ErrorMapperInterceptor — resend-verification 429 throttle', () {
    // -------------------------------------------------------------------------
    // Helper — builds a 429 DioException with a real Retry-After response header
    // so that the header-first resolution path in _extractRetryAfterSeconds is
    // exercised. The JSON body is intentionally absent to prove the header path
    // fires in isolation (RFC 7231 §7.1.3 — integer seconds form).
    // -------------------------------------------------------------------------
    DioException httpErrorWithRetryAfterHeader(
      String retryAfterValue, {
      String path = '/auth/resend-verification',
      dynamic body,
    }) {
      final opts = _opts(path: path);
      return DioException(
        requestOptions: opts,
        response: Response<dynamic>(
          requestOptions: opts,
          statusCode: 429,
          data: body,
          headers: Headers.fromMap({
            'retry-after': [retryAfterValue],
          }),
        ),
        type: DioExceptionType.badResponse,
      );
    }

    // ---- Retry-After header path (RFC 7231 §7.1.3) ----

    test('429 with Retry-After: 60 header → ResendThrottledFailure(60) '
        '(header takes precedence over absent body)', () {
      final rejected = _captureRejected(httpErrorWithRetryAfterHeader('60'));

      expect(rejected.error, isA<ResendThrottledFailure>());
      expect(
        (rejected.error as ResendThrottledFailure).retryAfterSeconds,
        equals(60),
        reason:
            'Retry-After header value must be parsed and returned when no '
            'JSON body is present',
      );
    });

    test('429 with Retry-After: 30 header AND data.retryAfterSeconds: 99 → '
        'header wins (RFC 7231 resolution order)', () {
      final opts = _opts(path: '/auth/resend-verification');
      final rejected = _captureRejected(
        DioException(
          requestOptions: opts,
          response: Response<dynamic>(
            requestOptions: opts,
            statusCode: 429,
            data: {
              'success': false,
              'data': {'retryAfterSeconds': 99},
            },
            headers: Headers.fromMap({
              'retry-after': ['30'],
            }),
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      expect(rejected.error, isA<ResendThrottledFailure>());
      expect(
        (rejected.error as ResendThrottledFailure).retryAfterSeconds,
        equals(30),
        reason:
            'When both Retry-After header and data.retryAfterSeconds are '
            'present, the header must win (resolution order rule 1)',
      );
    });

    test('429 with Retry-After header containing leading/trailing whitespace '
        '→ parsed correctly after trim()', () {
      final rejected = _captureRejected(
        httpErrorWithRetryAfterHeader('  45  '),
      );

      expect(rejected.error, isA<ResendThrottledFailure>());
      expect(
        (rejected.error as ResendThrottledFailure).retryAfterSeconds,
        equals(45),
        reason: 'trim() must be applied before int.tryParse',
      );
    });

    test(
      '429 with non-integer Retry-After header (HTTP-date form) falls back to '
      'data.retryAfterSeconds in the JSON body',
      () {
        final opts = _opts(path: '/auth/resend-verification');
        final rejected = _captureRejected(
          DioException(
            requestOptions: opts,
            response: Response<dynamic>(
              requestOptions: opts,
              statusCode: 429,
              data: {
                'success': false,
                'data': {'retryAfterSeconds': 77},
              },
              headers: Headers.fromMap({
                'retry-after': ['Mon, 01 Jan 2040 00:00:00 GMT'],
              }),
            ),
            type: DioExceptionType.badResponse,
          ),
        );

        // HTTP-date form is intentionally not parsed — falls through to body.
        expect(rejected.error, isA<ResendThrottledFailure>());
        expect(
          (rejected.error as ResendThrottledFailure).retryAfterSeconds,
          equals(77),
          reason:
              'HTTP-date Retry-After is not supported; must fall back to the '
              'data.retryAfterSeconds JSON field',
        );
      },
    );

    // ---- JSON body path (existing tests — unchanged) ----

    test(
      '429 with data.retryAfterSeconds → ResendThrottledFailure with value',
      () {
        final rejected = _captureRejected(
          _httpError(
            429,
            path: '/auth/resend-verification',
            body: {
              'success': false,
              'message': 'Too many resend attempts',
              'data': {'retryAfterSeconds': 42},
            },
          ),
        );

        expect(rejected.error, isA<ResendThrottledFailure>());
        expect(
          (rejected.error as ResendThrottledFailure).retryAfterSeconds,
          equals(42),
        );
      },
    );

    test(
      '429 with missing data → ResendThrottledFailure(retryAfterSeconds: 0)',
      () {
        final rejected = _captureRejected(
          _httpError(
            429,
            path: '/auth/resend-verification',
            body: {'success': false, 'message': 'Too many resend attempts'},
          ),
        );

        expect(rejected.error, isA<ResendThrottledFailure>());
        expect(
          (rejected.error as ResendThrottledFailure).retryAfterSeconds,
          equals(0),
        );
      },
    );

    test('429 with negative retryAfterSeconds → clamped to 0', () {
      final rejected = _captureRejected(
        _httpError(
          429,
          path: '/auth/resend-verification',
          body: {
            'success': false,
            'data': {'retryAfterSeconds': -7},
          },
        ),
      );

      expect(rejected.error, isA<ResendThrottledFailure>());
      expect(
        (rejected.error as ResendThrottledFailure).retryAfterSeconds,
        equals(0),
      );
    });

    test('429 on a DIFFERENT path → UnknownFailure '
        '(throttle mapping is scoped to /auth/resend-verification)', () {
      final rejected = _captureRejected(
        _httpError(
          429,
          path: '/auth/login',
          body: {
            'success': false,
            'data': {'retryAfterSeconds': 42},
          },
        ),
      );

      // 429 is not in the generic mapping table, so it falls through.
      expect(rejected.error, isA<UnknownFailure>());
    });
  });

  group('ErrorMapperInterceptor — Failure carries original cause', () {
    test('cause is the original DioException', () {
      final input = _httpError(404);
      final rejected = _captureRejected(input);
      final failure = rejected.error as Failure;
      expect(failure.cause, same(input));
    });
  });

  group('ErrorMapperInterceptor — handler.reject called exactly once', () {
    test('reject called once per onError invocation', () {
      final handler = _MockErrorInterceptorHandler();
      when(() => handler.reject(any())).thenReturn(null);

      ErrorMapperInterceptor().onError(_httpError(500), handler);

      verify(() => handler.reject(any())).called(1);
      verifyNever(() => handler.next(any()));
    });
  });
}
