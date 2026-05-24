// Phase 2.2 — Error mapper interceptor.
//
// Converts Dio-level exceptions into typed [Failure] subclasses from
// `core/errors/failures.dart`. After this interceptor, callers in the
// repository layer only ever receive typed [Failure]s — never raw
// [DioException]s.
//
// Mapping rules:
//   connectionTimeout | connectionError | sendTimeout | receiveTimeout
//                                         → NetworkFailure
//   HTTP 401          → UnauthorizedFailure
//   HTTP 404          → NotFoundFailure
//   HTTP 409          → ServerFailure(statusCode: 409)
//   HTTP 400          → ValidationFailure (field errors extracted from body)
//   HTTP 500–599      → ServerFailure(statusCode: ...)
//   anything else     → UnknownFailure(cause: err)
//
// The interceptor re-rejects with a new [DioException] wrapping the [Failure]
// as its `error` field. Repositories extract it with:
//   `(e.error is Failure) ? e.error as Failure : UnknownFailure(cause: e)`

import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../errors/failures.dart';

/// Dio interceptor that maps [DioException] → typed [Failure].
///
/// Must be the last interceptor in the chain (after LoggingInterceptor,
/// before nothing) so that logging sees the raw error before it is wrapped.
final class ErrorMapperInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final failure = _mapError(err);

    if (kDebugMode) {
      log(
        'Mapped ${err.type} / ${err.response?.statusCode} → ${failure.runtimeType}',
        name: 'network.error',
        level: 900, // WARNING
        // Sanitized: raw DioException is intentionally NOT passed — its
        // toString() can include response.data which for /auth/verify-email
        // carries OTP + email (mobile-security MS-LOG-01).
        error: '${err.type} ${err.response?.statusCode}',
      );
    }

    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        type: err.type,
        error: failure,
        message: err.message,
        stackTrace: err.stackTrace,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Mapping logic
  // ---------------------------------------------------------------------------

  Failure _mapError(DioException err) {
    // Network-level errors (no HTTP response).
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkFailure(cause: err);
      default:
        break;
    }

    // HTTP response errors.
    final statusCode = err.response?.statusCode;
    final path = err.requestOptions.path;
    if (statusCode != null) {
      // Phase 2.11 — verify-email typed errors (backend Phase 1.5).
      // The backend returns 400 with envelope {success:false, data:{code:"..."}}
      // for INVALID_CODE / CODE_EXPIRED / ALREADY_VERIFIED. Surface as a
      // VerificationFailure so the screen can render the right UA copy.
      // Must be checked BEFORE the generic 400/422 → ValidationFailure branch
      // so the typed-code envelope wins over the field-errors fallback.
      if (statusCode == 400 && path.endsWith('/auth/verify-email')) {
        final code = _extractVerificationCode(err);
        if (code != null) {
          return VerificationFailure(code: code, cause: err);
        }
      }

      // Phase 2.11 — resend-verification 429 throttle (backend Phase 1.6).
      // Envelope: {success:false, message:"...", data:{retryAfterSeconds:42}}.
      if (statusCode == 429 && path.endsWith('/auth/resend-verification')) {
        return ResendThrottledFailure(
          retryAfterSeconds: _extractRetryAfterSeconds(err),
          cause: err,
        );
      }

      if (statusCode == 401) {
        // MEDIUM-2 (mobile-security 2026-05-24): decode the EMAIL_NOT_VERIFIED
        // sub-code into a typed field so login_screen.dart can branch on
        // `e.emailNotVerified` instead of probing `e.cause?.toString()`.
        final bool emailNotVerified = _extractEmailNotVerified(err);
        return UnauthorizedFailure(
          cause: err,
          emailNotVerified: emailNotVerified,
        );
      }
      if (statusCode == 404) return NotFoundFailure(cause: err);
      // HTTP 409 Conflict — email already registered during sign-up (or any
      // other resource-conflict). Map to ServerFailure so the screen surfaces
      // the generic "server error" copy rather than the opaque errUnknown.
      if (statusCode == 409) {
        return ServerFailure(statusCode: statusCode, cause: err);
      }
      if (statusCode == 400 || statusCode == 422) {
        return ValidationFailure(
          fieldErrors: _extractFieldErrors(err),
          cause: err,
        );
      }
      if (statusCode >= 500 && statusCode <= 599) {
        return ServerFailure(statusCode: statusCode, cause: err);
      }
    }

    return UnknownFailure(cause: err);
  }

  /// Returns `true` when the 401 response body contains the `EMAIL_NOT_VERIFIED`
  /// sub-code (i.e. the account exists but OTP has not been completed).
  ///
  /// Expected backend envelope shape:
  /// ```json
  /// { "success": false, "data": { "code": "EMAIL_NOT_VERIFIED" } }
  /// ```
  /// Returns `false` on any other 401 shape (wrong credentials, expired token,
  /// malformed body) so that the fallback generic-unauthorized handling applies.
  bool _extractEmailNotVerified(DioException err) {
    try {
      final body = err.response?.data;
      if (body is Map<String, dynamic>) {
        final data = body['data'];
        if (data is Map<String, dynamic>) {
          return data['code'] == 'EMAIL_NOT_VERIFIED';
        }
        // Backend may also put the code at top-level message or errors.
        final message = body['message'];
        if (message is String) {
          return message.contains('EMAIL_NOT_VERIFIED');
        }
      }
    } catch (_) {
      // Swallow parse errors — fall back to false.
    }
    return false;
  }

  /// Extracts the typed `data.code` string from the verify-email envelope
  /// and decodes it into a [VerificationErrorCode].
  ///
  /// Returns `null` if the body is not a `{data:{code:String}}` shape — in
  /// that case the caller falls through to the generic ValidationFailure
  /// mapping (so genuinely-malformed responses still surface as 400 errors
  /// instead of swallowing the typed-code branch).
  VerificationErrorCode? _extractVerificationCode(DioException err) {
    try {
      final body = err.response?.data;
      if (body is Map<String, dynamic>) {
        final data = body['data'];
        if (data is Map<String, dynamic>) {
          final code = data['code'];
          if (code is String && code.isNotEmpty) {
            return VerificationErrorCode.fromWire(code);
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        log(
          'Failed to parse verify-email code from response: $e',
          name: 'network.error',
          level: 900,
        );
      }
    }
    return null;
  }

  /// Extracts the resend-cooldown seconds from the 429 response.
  ///
  /// Resolution order (first non-null result wins):
  ///   1. `Retry-After` HTTP response header (RFC 7231 — authoritative).
  ///   2. `data.retryAfterSeconds` in the JSON body envelope (backend Phase 1.6
  ///      secondary field; present alongside the header for clients that can't
  ///      read raw headers through a Dio response).
  ///
  /// Falls back to `0` when both sources are absent or malformed — the screen
  /// still shows the throttle banner and the user can manually retry.
  ///
  /// All values are clamped to [0, 2^31] to prevent a rogue server from
  /// pinning the resend cooldown to a multi-year value (MASVS-PLATFORM).
  int _extractRetryAfterSeconds(DioException err) {
    const kMaxCooldown = 1 << 31;

    // 1. Retry-After header (RFC 7231 §7.1.3 — integer seconds form only;
    //    HTTP-date form is intentionally not parsed here since the backend
    //    always emits an integer).
    try {
      final headerRaw = err.response?.headers.value('retry-after');
      if (headerRaw != null) {
        final parsed = int.tryParse(headerRaw.trim());
        if (parsed != null && parsed >= 0) {
          return parsed.clamp(0, kMaxCooldown);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        log(
          'Failed to parse Retry-After header: $e',
          name: 'network.error',
          level: 900,
        );
      }
    }

    // 2. JSON body fallback: {data: {retryAfterSeconds: N}}.
    try {
      final body = err.response?.data;
      if (body is Map<String, dynamic>) {
        final data = body['data'];
        if (data is Map<String, dynamic>) {
          final raw = data['retryAfterSeconds'];
          if (raw is int) return raw.clamp(0, kMaxCooldown);
          if (raw is num) return raw.toInt().clamp(0, kMaxCooldown);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        log(
          'Failed to parse retry-after-seconds from response body: $e',
          name: 'network.error',
          level: 900,
        );
      }
    }

    return 0;
  }

  /// Safely extracts field-level error messages from the response body.
  ///
  /// Expected backend shape (Spring `MethodArgumentNotValidException`):
  /// ```json
  /// { "errors": { "email": "must not be blank", "name": "size must be ≥ 2" } }
  /// ```
  /// Only the `"errors"` key at the top level is consulted. Any other shape
  /// returns an empty map — callers must handle the empty-map case gracefully.
  ///
  /// Each value is truncated to 200 characters before storage to prevent
  /// unbounded server strings reaching UI labels (SECURITY M1).
  ///
  /// Returns an empty map if:
  ///   - the response body is absent or not a JSON object
  ///   - the body does not contain an `"errors"` key
  ///   - the `"errors"` value is not a map
  ///   - any parse exception is thrown
  Map<String, String> _extractFieldErrors(DioException err) {
    try {
      final data = err.response?.data;
      if (data is Map<String, dynamic>) {
        final errors = data['errors'];
        if (errors is Map) {
          return errors.map((key, value) {
            final raw = value.toString();
            final capped = raw.length > 200 ? raw.substring(0, 200) : raw;
            return MapEntry(key.toString(), capped);
          });
        }
      }
    } catch (e) {
      if (kDebugMode) {
        log(
          'Failed to parse field errors from response: $e',
          name: 'network.error',
          level: 900,
        );
      }
    }
    return const {};
  }
}
