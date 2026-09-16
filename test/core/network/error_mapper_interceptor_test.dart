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

    test('HTTP 409 Conflict WITHOUT EMAIL_ALREADY_REGISTERED → '
        'ServerFailure(statusCode: 409)', () {
      // No data.code present — must fall through to generic ServerFailure
      // so other 409 resource-conflict variants keep their existing
      // retryable behaviour.
      final rejected = _captureRejected(_httpError(409));
      expect(rejected.error, isA<ServerFailure>());
      expect(rejected.error, isNot(isA<EmailAlreadyRegisteredFailure>()));
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

    // -------------------------------------------------------------------
    // Invite-accept post-success failure design (2026-09-01) —
    // NetworkFailure.mayHaveReachedServer per-DioExceptionType split.
    //
    // Only receiveTimeout means the request body was fully SENT before the
    // client gave up waiting — the server may have processed it.
    // connectionTimeout / connectionError / sendTimeout mean the request
    // never completed at all, so a retry is genuinely safe and an offline
    // user must keep seeing plain errNetwork, never "your account may
    // exist". A mutation collapsing this per-type split back to a single
    // `true` (or a single `false`) must fail at least one of these four.
    // -------------------------------------------------------------------
    test('connectionTimeout → NetworkFailure.mayHaveReachedServer == false '
        '(request never completed)', () {
      final rejected = _captureRejected(
        _typeError(DioExceptionType.connectionTimeout),
      );
      expect((rejected.error as NetworkFailure).mayHaveReachedServer, isFalse);
    });

    test('connectionError → NetworkFailure.mayHaveReachedServer == false '
        '(offline user must not be told the account may exist)', () {
      final rejected = _captureRejected(
        _typeError(DioExceptionType.connectionError),
      );
      expect((rejected.error as NetworkFailure).mayHaveReachedServer, isFalse);
    });

    test('sendTimeout → NetworkFailure.mayHaveReachedServer == false '
        '(request never completed)', () {
      final rejected = _captureRejected(
        _typeError(DioExceptionType.sendTimeout),
      );
      expect((rejected.error as NetworkFailure).mayHaveReachedServer, isFalse);
    });

    test('receiveTimeout → NetworkFailure.mayHaveReachedServer == true '
        '(request body was fully sent — server may have processed it)', () {
      final rejected = _captureRejected(
        _typeError(DioExceptionType.receiveTimeout),
      );
      expect((rejected.error as NetworkFailure).mayHaveReachedServer, isTrue);
    });
  });

  group('ErrorMapperInterceptor — 2xx-carrying DioException (invite-accept '
      'post-success failure design, 2026-09-01)', () {
    // A DioException carrying a 2xx response means Dio's response
    // transformer (or a downstream mapper) threw AFTER the server already
    // answered success — surfaced as DioExceptionType.unknown with the
    // response attached. The request DID take effect; only the
    // client-side parse failed. This must be checked BEFORE both the
    // transport-type switch and the status-code chain — a mutation that
    // drops or reorders this check would fall through to
    // DioExceptionType.unknown's default branch instead.
    test(
      '200 response attached to a DioException → ResponseUnusableFailure',
      () {
        final opts = _opts();
        final err = DioException(
          requestOptions: opts,
          type: DioExceptionType.unknown,
          error: const FormatException('unexpected token'),
          response: Response<dynamic>(
            requestOptions: opts,
            statusCode: 200,
            data: {'success': true, 'data': null},
          ),
        );
        final rejected = _captureRejected(err);
        expect(rejected.error, isA<ResponseUnusableFailure>());
      },
    );

    test('201 response attached to a DioException → ResponseUnusableFailure '
        '(acceptInvite\'s success status)', () {
      final opts = _opts();
      final err = DioException(
        requestOptions: opts,
        type: DioExceptionType.unknown,
        error: const FormatException('unexpected token'),
        response: Response<dynamic>(
          requestOptions: opts,
          statusCode: 201,
          data: {'success': true, 'data': null},
        ),
      );
      final rejected = _captureRejected(err);
      expect(rejected.error, isA<ResponseUnusableFailure>());
    });

    test('299 (upper 2xx boundary) response attached to a DioException → '
        'ResponseUnusableFailure', () {
      final opts = _opts();
      final err = DioException(
        requestOptions: opts,
        type: DioExceptionType.unknown,
        response: Response<dynamic>(requestOptions: opts, statusCode: 299),
      );
      final rejected = _captureRejected(err);
      expect(rejected.error, isA<ResponseUnusableFailure>());
    });

    test('400 response attached to a DioException does NOT map to '
        'ResponseUnusableFailure (boundary — the 2xx-only check must not '
        'swallow ordinary 4xx handling)', () {
      final rejected = _captureRejected(_httpError(400));
      expect(rejected.error, isNot(isA<ResponseUnusableFailure>()));
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
            path: '/api/v1/auth/verify-email',
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
            path: '/api/v1/auth/verify-email',
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
            path: '/api/v1/auth/verify-email',
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
          path: '/api/v1/auth/verify-email',
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
            path: '/api/v1/auth/verify-email',
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
      String path = '/api/v1/auth/resend-verification',
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
      final opts = _opts(path: '/api/v1/auth/resend-verification');
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
        final opts = _opts(path: '/api/v1/auth/resend-verification');
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
            path: '/api/v1/auth/resend-verification',
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
            path: '/api/v1/auth/resend-verification',
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
          path: '/api/v1/auth/resend-verification',
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

    // ---- kMaxUxCooldownSeconds = 600 ceiling tests (Batch-2 A4) ----

    test('429 with data.retryAfterSeconds = 3601 → null '
        '(exceeds kMaxUxCooldownSeconds UX ceiling via JSON body path)', () {
      final rejected = _captureRejected(
        _httpError(
          429,
          path: '/api/v1/auth/resend-verification',
          body: {
            'success': false,
            'data': {'retryAfterSeconds': 3601},
          },
        ),
      );

      expect(rejected.error, isA<ResendThrottledFailure>());
      expect(
        (rejected.error as ResendThrottledFailure).retryAfterSeconds,
        isNull,
        reason:
            'data.retryAfterSeconds of 3601 exceeds kMaxUxCooldownSeconds (600) '
            '— must return null so the UI shows a static message instead of '
            'a multi-minute countdown',
      );
    });

    test('429 with Retry-After: "7200" header → null '
        '(exceeds kMaxUxCooldownSeconds UX ceiling via header path)', () {
      final rejected = _captureRejected(httpErrorWithRetryAfterHeader('7200'));

      expect(rejected.error, isA<ResendThrottledFailure>());
      expect(
        (rejected.error as ResendThrottledFailure).retryAfterSeconds,
        isNull,
        reason:
            'Retry-After header value of 7200 exceeds kMaxUxCooldownSeconds (600) '
            '— must return null so the UI shows a static message instead of '
            'a multi-hour countdown',
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

  // ---------------------------------------------------------------------------
  // Beautica OTP task Phase A3/B2 — verify-password-reset-otp typed errors.
  // Mirrors the verify-email typed-code envelope, but maps to the DEDICATED
  // PasswordResetOtpFailure (NOT VerificationFailure) so the password-reset
  // OTP screen never shows email-verification-specific copy.
  // ---------------------------------------------------------------------------

  group('ErrorMapperInterceptor — verify-password-reset-otp typed errors', () {
    test(
      '400 with data.code = INVALID_CODE → PasswordResetOtpFailure(invalidCode)',
      () {
        final rejected = _captureRejected(
          _httpError(
            400,
            path: '/api/v1/auth/verify-password-reset-otp',
            body: {
              'success': false,
              'data': {'code': 'INVALID_CODE'},
            },
          ),
        );

        expect(rejected.error, isA<PasswordResetOtpFailure>());
        expect(
          (rejected.error as PasswordResetOtpFailure).code,
          equals(PasswordResetOtpErrorCode.invalidCode),
        );
      },
    );

    test(
      '400 with data.code = CODE_EXPIRED → PasswordResetOtpFailure(codeExpired)',
      () {
        final rejected = _captureRejected(
          _httpError(
            400,
            path: '/api/v1/auth/verify-password-reset-otp',
            body: {
              'success': false,
              'data': {'code': 'CODE_EXPIRED'},
            },
          ),
        );

        expect(rejected.error, isA<PasswordResetOtpFailure>());
        expect(
          (rejected.error as PasswordResetOtpFailure).code,
          equals(PasswordResetOtpErrorCode.codeExpired),
        );
      },
    );

    test('400 with unknown wire code → falls back to invalidCode', () {
      final rejected = _captureRejected(
        _httpError(
          400,
          path: '/api/v1/auth/verify-password-reset-otp',
          body: {
            'success': false,
            'data': {'code': 'SOME_FUTURE_CODE'},
          },
        ),
      );

      expect(rejected.error, isA<PasswordResetOtpFailure>());
      expect(
        (rejected.error as PasswordResetOtpFailure).code,
        equals(PasswordResetOtpErrorCode.invalidCode),
      );
    });

    test('400 on /auth/verify-password-reset-otp WITHOUT data.code key → '
        'ValidationFailure fallback', () {
      final rejected = _captureRejected(
        _httpError(
          400,
          path: '/api/v1/auth/verify-password-reset-otp',
          body: {
            'success': false,
            'errors': {'code': 'must not be blank'},
          },
        ),
      );

      expect(rejected.error, isA<ValidationFailure>());
      expect(rejected.error, isNot(isA<PasswordResetOtpFailure>()));
    });

    test(
      '400 with data.code on a DIFFERENT path → ValidationFailure, and NEVER '
      'VerificationFailure (the two typed-code mappings must never cross-fire)',
      () {
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
        expect(rejected.error, isNot(isA<PasswordResetOtpFailure>()));
        expect(rejected.error, isNot(isA<VerificationFailure>()));
      },
    );

    test('400 with data.code on /auth/verify-email → VerificationFailure, '
        'NEVER PasswordResetOtpFailure (mappings do not cross-fire the other '
        'way either)', () {
      final rejected = _captureRejected(
        _httpError(
          400,
          path: '/api/v1/auth/verify-email',
          body: {
            'success': false,
            'data': {'code': 'INVALID_CODE'},
          },
        ),
      );

      expect(rejected.error, isA<VerificationFailure>());
      expect(rejected.error, isNot(isA<PasswordResetOtpFailure>()));
    });
  });

  // ---------------------------------------------------------------------------
  // Beautica OTP task Phase A3/B2 — authenticated change-password OTP resend
  // cooldown. Mirrors resend-verification's 429 mapping but scoped to the
  // authenticated `/users/me/change-password/request-otp` entry point.
  // ---------------------------------------------------------------------------

  group(
    'ErrorMapperInterceptor — change-password/request-otp 429 throttle',
    () {
      test(
        '429 with data.retryAfterSeconds = 42 → ResendThrottledFailure(42)',
        () {
          final rejected = _captureRejected(
            _httpError(
              429,
              path: '/api/v1/users/me/change-password/request-otp',
              body: {
                'success': false,
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
        '429 on a DIFFERENT path → UnknownFailure (throttle mapping is scoped '
        'to /users/me/change-password/request-otp)',
        () {
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

          expect(rejected.error, isA<UnknownFailure>());
        },
      );
    },
  );

  // ---------------------------------------------------------------------------
  // EMAIL_ALREADY_REGISTERED — backend dev mode (disclose-duplicate-
  // registration). Backend returns 409 with envelope:
  //   {success:false, data:{code:"EMAIL_ALREADY_REGISTERED"},
  //    message:"Email already registered"}
  // ---------------------------------------------------------------------------

  group('ErrorMapperInterceptor — 409 EMAIL_ALREADY_REGISTERED', () {
    test('409 with data.code == EMAIL_ALREADY_REGISTERED → '
        'EmailAlreadyRegisteredFailure (must fail if the code-string check is '
        'removed from _mapError)', () {
      final rejected = _captureRejected(
        _httpError(
          409,
          path: '/auth/register',
          body: {
            'success': false,
            'data': {'code': 'EMAIL_ALREADY_REGISTERED'},
            'message': 'Email already registered',
          },
        ),
      );

      expect(rejected.error, isA<EmailAlreadyRegisteredFailure>());
      // Cross-check: must NOT be the generic ServerFailure that the old
      // path would have returned. Removing the code-string check from
      // _mapError causes this assertion to fail.
      expect(rejected.error, isNot(isA<ServerFailure>()));
    });

    test(
      '409 on /auth/register/independent-master with EMAIL_ALREADY_REGISTERED '
      '→ EmailAlreadyRegisteredFailure (path-agnostic — both /auth/register '
      'and /auth/register/independent-master are valid duplicate-email sources)',
      () {
        final rejected = _captureRejected(
          _httpError(
            409,
            path: '/auth/register/independent-master',
            body: {
              'success': false,
              'data': {'code': 'EMAIL_ALREADY_REGISTERED'},
              'message': 'Email already registered',
            },
          ),
        );

        expect(rejected.error, isA<EmailAlreadyRegisteredFailure>());
      },
    );

    test('409 with data.code == EMAIL_ALREADY_REGISTERED carries the original '
        'DioException as cause (logging)', () {
      final input = _httpError(
        409,
        path: '/auth/register',
        body: {
          'success': false,
          'data': {'code': 'EMAIL_ALREADY_REGISTERED'},
        },
      );
      final rejected = _captureRejected(input);
      expect(rejected.error, isA<EmailAlreadyRegisteredFailure>());
      expect((rejected.error as Failure).cause, same(input));
    });

    test(
      '409 with data.code == UNKNOWN_FUTURE_CODE → ServerFailure (only the '
      'exact EMAIL_ALREADY_REGISTERED wire code triggers the typed failure)',
      () {
        final rejected = _captureRejected(
          _httpError(
            409,
            path: '/auth/register',
            body: {
              'success': false,
              'data': {'code': 'SOMETHING_NEW'},
            },
          ),
        );

        expect(rejected.error, isA<ServerFailure>());
        expect(rejected.error, isNot(isA<EmailAlreadyRegisteredFailure>()));
      },
    );

    test('409 with no data envelope → ServerFailure (genuinely-malformed 409s '
        'still fall through to the retryable server-error branch)', () {
      final rejected = _captureRejected(
        _httpError(409, path: '/auth/register', body: {'message': 'Conflict'}),
      );

      expect(rejected.error, isA<ServerFailure>());
      expect(rejected.error, isNot(isA<EmailAlreadyRegisteredFailure>()));
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

  // ---------------------------------------------------------------------------
  // Password-reset journey 429 — per-IP AuthRateLimitFilter (2026-09-15)
  // ---------------------------------------------------------------------------
  //
  // The live bug: a real, active, verified user asked for a password reset and
  // got «Щось пішло не так. Спробуйте ще раз.» — the errUnknown copy. The
  // backend caps each of these three endpoints at 3 requests/hour per IP in a
  // servlet FILTER that runs BEFORE the controller, so forgot-password's
  // anti-enumeration generic-200 contract never gets a say: the filter answers
  // 429 with `Retry-After: 3600` and its own bare `{"error":"Too many
  // requests"}` — no `message`, no `errors`, no `data.code`. With no branch
  // for it the response fell to the terminal UnknownFailure.
  //
  // The body below is that exact filter shape on purpose: a fixture carrying
  // the richer `{data:{retryAfterSeconds}}` envelope would let a branch that
  // merely reads the body look correct, which is the mistake that produced
  // the gap in the first place.
  group('ErrorMapperInterceptor — password-reset 429 (per-IP filter)', () {
    DioException filterThrottle(String path) {
      final opts = _opts(path: path);
      return DioException(
        requestOptions: opts,
        response: Response<dynamic>(
          requestOptions: opts,
          statusCode: 429,
          data: <String, dynamic>{'error': 'Too many requests'},
          headers: Headers.fromMap({
            'retry-after': ['3600'],
          }),
        ),
        type: DioExceptionType.badResponse,
      );
    }

    // All three steps of the same journey (request → verify OTP → set
    // password) have their own bucket and had the identical hole. Gating only
    // the first would leave the user hitting the same wall two taps later.
    for (final String path in <String>[
      '/api/v1/auth/forgot-password',
      '/api/v1/auth/verify-password-reset-otp',
      '/api/v1/auth/reset-password',
    ]) {
      test('429 on $path → PasswordResetRateLimitedFailure, NOT '
          'UnknownFailure', () {
        final rejected = _captureRejected(filterThrottle(path));

        expect(rejected.error, isA<PasswordResetRateLimitedFailure>());
        expect(
          rejected.error,
          isNot(isA<UnknownFailure>()),
          reason:
              'falling through to UnknownFailure is the reported bug — it '
              'renders errUnknown («Спробуйте ще раз»), which at 3 '
              'requests/hour is the one action that cannot work',
        );
      });
    }

    // The suffix match must not swallow the whole 429 space: the
    // change-password entry point immediately above it keeps its own
    // per-account ResendThrottledFailure, and an unrelated 429 keeps falling
    // through. Without this the new branch could be a no-op-looking widening.
    test('429 on /users/me/change-password/request-otp still maps to '
        'ResendThrottledFailure (the new branch did not swallow it)', () {
      final rejected = _captureRejected(
        _httpError(
          429,
          path: '/api/v1/users/me/change-password/request-otp',
          body: <String, dynamic>{
            'data': <String, dynamic>{'retryAfterSeconds': 42},
          },
        ),
      );

      expect(rejected.error, isA<ResendThrottledFailure>());
      expect(
        (rejected.error as ResendThrottledFailure).retryAfterSeconds,
        equals(42),
      );
    });

    test('429 on an unrelated path is untouched by the password-reset '
        'branch', () {
      final rejected = _captureRejected(
        _httpError(429, path: '/api/v1/bookings'),
      );

      expect(rejected.error, isNot(isA<PasswordResetRateLimitedFailure>()));
    });

    // A 400 on the same path must keep its typed-code handling — the new
    // branch is gated on the status code as well as the path.
    test('400 on /auth/verify-password-reset-otp still maps to '
        'PasswordResetOtpFailure', () {
      final rejected = _captureRejected(
        _httpError(
          400,
          path: '/api/v1/auth/verify-password-reset-otp',
          body: <String, dynamic>{
            'data': <String, dynamic>{'code': 'CODE_EXPIRED'},
          },
        ),
      );

      expect(rejected.error, isA<PasswordResetOtpFailure>());
    });

    test('the failure carries the original DioException as its cause', () {
      final input = filterThrottle('/api/v1/auth/forgot-password');
      final rejected = _captureRejected(input);

      // Pin the TYPE as well. Without it this assertion survives deleting the
      // password-reset branch outright: whatever failure the 429 then falls
      // through to still carries `cause`, so it stayed GREEN while the three
      // path tests above went red (mobile-qa mutation M6, 2026-09-16).
      expect(rejected.error, isA<PasswordResetRateLimitedFailure>());
      expect((rejected.error as Failure).cause, same(input));
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
