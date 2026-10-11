// Phase 364 — "the thing you asked for is gone or no longer yours".
//
// A 404 arrives as [NotFoundFailure]; a 403 has no dedicated failure type
// (`ErrorMapperInterceptor` maps it to [UnknownFailure]) and is read off the
// carried [DioException], the same way `isAuthRejection` reads it.

import 'package:dio/dio.dart';

import 'failures.dart';

/// Whether [error] says the requested resource is not visible to the caller:
/// HTTP 404 or 403.
///
/// Everything else — no network, a 5xx, a mapping failure — is NOT
/// "unavailable"; those are retryable and keep the caller's normal error UI.
bool isResourceUnavailable(Object error) {
  if (error is NotFoundFailure) return true;
  if (error is Failure) {
    final Object? cause = error.cause;
    if (cause is DioException) {
      final int? status = cause.response?.statusCode;
      return status == 403 || status == 404;
    }
  }
  return false;
}
