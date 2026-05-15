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
        error: err,
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
    if (statusCode != null) {
      if (statusCode == 401) return UnauthorizedFailure(cause: err);
      if (statusCode == 404) return NotFoundFailure(cause: err);
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
