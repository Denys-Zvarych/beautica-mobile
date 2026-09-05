// Phase 2.2 — Error mapper interceptor.
//
// Converts Dio-level exceptions into typed [Failure] subclasses from
// `core/errors/failures.dart`. After this interceptor, callers in the
// repository layer only ever receive typed [Failure]s — never raw
// [DioException]s.
//
// Mapping rules:
//   any DioException carrying a 2xx response
//                                         → ResponseUnusableFailure
//   connectionTimeout | connectionError | sendTimeout
//                                         → NetworkFailure(mayHaveReachedServer: false)
//   receiveTimeout    → NetworkFailure(mayHaveReachedServer: true)
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
    // Invite-accept post-success design (2026-09-01): a 2xx response
    // attached to a DioException means Dio's response transformer (or a
    // downstream mapper) threw AFTER the server already answered success —
    // typically surfaced as DioExceptionType.unknown. The request DID take
    // effect; only the client-side parse failed. Must be checked before the
    // transport-error switch below and before the status-code chain so it
    // wins over both.
    final sc = err.response?.statusCode;
    if (sc != null && sc >= 200 && sc < 300) {
      return ResponseUnusableFailure(cause: err);
    }

    // Network-level errors (no HTTP response).
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.sendTimeout:
        // The request never completed — retry is genuinely safe, and an
        // offline user must keep seeing plain errNetwork copy, never "your
        // account may exist" (invite-accept post-success design, 2026-09-01).
        return NetworkFailure(cause: err);
      case DioExceptionType.receiveTimeout:
        // The request body was fully SENT before the client gave up waiting
        // for a response — the server may have processed it.
        return NetworkFailure(cause: err, mayHaveReachedServer: true);
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
      // Suffix match (not equality) so the mapping is immune to any
      // AppConfig.baseUrl `/api/v1` prefix drift or generated-path change —
      // an exact-literal match silently misses and degrades the typed
      // VerificationFailure to a generic ValidationFailure (silent-submit bug).
      if (statusCode == 400 && path.endsWith('/auth/verify-email')) {
        final code = _extractVerificationCode(err);
        if (code != null) {
          return VerificationFailure(code: code, cause: err);
        }
      }

      // Phase 2.11 — resend-verification 429 throttle (backend Phase 1.6).
      // Envelope: {success:false, message:"...", data:{retryAfterSeconds:42}}.
      // Suffix match (see verify-email above) — immune to baseUrl prefix drift.
      if (statusCode == 429 && path.endsWith('/auth/resend-verification')) {
        return ResendThrottledFailure(
          retryAfterSeconds: _extractRetryAfterSecondsNullable(err),
          cause: err,
        );
      }

      // Backend Phase A3 — verify-password-reset-otp typed errors. The
      // backend deliberately reuses the same generic 400 shape as
      // /auth/verify-email ({success:false, data:{code:"..."}}) for invalid /
      // expired / exhausted / locked-account states — no oracle. Surface as
      // a dedicated PasswordResetOtpFailure (NOT VerificationFailure) so the
      // password-reset OTP screen never shows email-verification-specific
      // copy ("account already verified") in this context.
      if (statusCode == 400 &&
          path.endsWith('/auth/verify-password-reset-otp')) {
        final code = _extractPasswordResetOtpCode(err);
        if (code != null) {
          return PasswordResetOtpFailure(code: code, cause: err);
        }
      }

      // Backend Phase A3 — authenticated change-password OTP resend cooldown.
      // Unlike /auth/forgot-password (anti-enumeration — no 429 surfaced),
      // this authenticated entry point DOES throw the same
      // ResendThrottledException shape as /auth/resend-verification.
      if (statusCode == 429 &&
          path.endsWith('/users/me/change-password/request-otp')) {
        return ResendThrottledFailure(
          retryAfterSeconds: _extractRetryAfterSecondsNullable(err),
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
      // HTTP 409 Conflict — backend `disclose-duplicate-registration` mode
      // (currently dev only via application-local.yml) returns 409 with
      // {success:false, data:{code:"EMAIL_ALREADY_REGISTERED"}} on duplicate
      // registration. Surface as the dedicated typed failure so the step-3
      // submit handler can render an inline error + Sign In CTA without
      // probing strings. This mapping is NOT path-gated — it keys purely on
      // the body code — so it also covers backend Phase 287's
      // `POST /auth/invite` / `POST /salons/{id}/invite`, which return the
      // SAME {code:"EMAIL_ALREADY_REGISTERED"} envelope when the invited
      // email already has an account; `InviteStaffScreen` (mobile Phase 303)
      // branches on this same typed failure to render its own inline error.
      // Other 409 shapes (resource-conflict, future codes) still fall
      // through to a generic `ServerFailure(statusCode: 409)`.
      //
      // That fallthrough is NOT retryable, despite `ServerFailure` being the
      // type 5xx also maps to. `beauticaProviderRetry`
      // (`lib/core/errors/failure_retry_policy.dart`) classifies a
      // `ServerFailure` by its `statusCode`, not by its type, and retries only
      // 500–599 — so a 409 surfaces `AsyncError` on the first attempt. A
      // conflict is a deterministic statement about current server state;
      // re-issuing the identical request cannot resolve it. Keep the two files
      // in step: widening what a bare 409 maps to here changes retry
      // behaviour there.
      if (statusCode == 409) {
        if (_isEmailAlreadyRegistered(err)) {
          return EmailAlreadyRegisteredFailure(cause: err);
        }
        return ServerFailure(statusCode: statusCode, cause: err);
      }
      if (statusCode == 400 || statusCode == 422) {
        return ValidationFailure(
          fieldErrors: _extractFieldErrors(err),
          serverMessage: _extractServerMessage(err),
          cause: err,
        );
      }
      if (statusCode >= 500 && statusCode <= 599) {
        return ServerFailure(statusCode: statusCode, cause: err);
      }
    }

    return UnknownFailure(cause: err);
  }

  /// Returns `true` when the 409 response body contains the
  /// `EMAIL_ALREADY_REGISTERED` sub-code.
  ///
  /// Expected backend envelope shape (`disclose-duplicate-registration=true`):
  /// ```json
  /// {
  ///   "success": false,
  ///   "data": { "code": "EMAIL_ALREADY_REGISTERED" },
  ///   "message": "Email already registered"
  /// }
  /// ```
  /// Returns `false` for any other 409 shape so the caller falls through to
  /// the generic [ServerFailure] mapping (other resource-conflict variants
  /// continue to surface their existing retryable behaviour).
  bool _isEmailAlreadyRegistered(DioException err) {
    try {
      final body = err.response?.data;
      if (body is Map<String, dynamic>) {
        final data = body['data'];
        if (data is Map<String, dynamic>) {
          return data['code'] == 'EMAIL_ALREADY_REGISTERED';
        }
      }
    } catch (_) {
      // Swallow parse errors — fall back to false (generic ServerFailure).
    }
    return false;
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

  /// Extracts the typed `data.code` string from the verify-password-reset-otp
  /// envelope and decodes it into a [PasswordResetOtpErrorCode].
  ///
  /// Returns `null` if the body is not a `{data:{code:String}}` shape — in
  /// that case the caller falls through to the generic ValidationFailure
  /// mapping (so genuinely-malformed responses still surface as 400 errors
  /// instead of swallowing the typed-code branch).
  PasswordResetOtpErrorCode? _extractPasswordResetOtpCode(DioException err) {
    try {
      final body = err.response?.data;
      if (body is Map<String, dynamic>) {
        final data = body['data'];
        if (data is Map<String, dynamic>) {
          final code = data['code'];
          if (code is String && code.isNotEmpty) {
            return PasswordResetOtpErrorCode.fromWire(code);
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        log(
          'Failed to parse verify-password-reset-otp code from response: $e',
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
  /// Two-tier clamping (Batch-2 A4 / UX fix):
  ///   - Security clamp: [0, 2^31] prevents integer overflow from a rogue server.
  ///   - UX clamp: values above [kMaxUxCooldownSeconds] (600 s / 10 min) return
  ///     `null` so the UI shows a static "Спробуйте пізніше" message instead of
  ///     a multi-year countdown. A rogue or misconfigured backend sending
  ///     `Retry-After: 999999999` will therefore never display a countdown.
  ///
  /// Returns `null` when the server value exceeds [kMaxUxCooldownSeconds].
  /// Returns `0` when both sources are absent or malformed.
  int? _extractRetryAfterSecondsNullable(DioException err) {
    const int kMaxCooldown = 1 << 31; // overflow guard (MASVS-PLATFORM)
    const int kMaxUxCooldownSeconds = 600; // 10 min UX ceiling

    // 1. Retry-After header (RFC 7231 §7.1.3 — integer seconds form only;
    //    HTTP-date form is intentionally not parsed here since the backend
    //    always emits an integer).
    try {
      final headerRaw = err.response?.headers.value('retry-after');
      if (headerRaw != null) {
        final parsed = int.tryParse(headerRaw.trim());
        if (parsed != null && parsed >= 0) {
          final clamped = parsed.clamp(0, kMaxCooldown);
          return clamped > kMaxUxCooldownSeconds ? null : clamped;
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
          if (raw is int) {
            final clamped = raw.clamp(0, kMaxCooldown);
            return clamped > kMaxUxCooldownSeconds ? null : clamped;
          }
          if (raw is num) {
            final clamped = raw.toInt().clamp(0, kMaxCooldown);
            return clamped > kMaxUxCooldownSeconds ? null : clamped;
          }
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

  /// Safely extracts the top-level `message` string from a 400/422 envelope.
  ///
  /// Expected backend shape:
  /// ```json
  /// { "success": false, "message": "Validation failed", "errors": { ... } }
  /// ```
  /// Captured onto [ValidationFailure.serverMessage] so the UI can show a
  /// generic SnackBar even when the `errors` field map is empty — the durable
  /// guard against a contract that returns a 400 with no usable field map.
  ///
  /// Truncated to 200 characters (SECURITY M1: untrusted server strings must
  /// not reach UI labels unbounded). Returns `null` when the body is absent,
  /// not a JSON object, has no string `message`, or the message is blank.
  String? _extractServerMessage(DioException err) {
    try {
      final data = err.response?.data;
      if (data is Map<String, dynamic>) {
        final message = data['message'];
        if (message is String && message.trim().isNotEmpty) {
          final trimmed = message.trim();
          return trimmed.length > 200 ? trimmed.substring(0, 200) : trimmed;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        log(
          'Failed to parse server message from response: $e',
          name: 'network.error',
          level: 900,
        );
      }
    }
    return null;
  }
}
