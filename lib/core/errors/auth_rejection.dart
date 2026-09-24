// Audit (2026-09-24, security LOW) — the ONE test for "the server rejected
// these credentials", which is the only thing allowed to wipe a stored
// session on cold start.
//
// Before this, `AuthNotifier.build()` wiped secure storage on ANY failure —
// including a 200 whose body the client could not parse (an unknown enum
// value, a malformed envelope), a 5xx, or no network. Each of those logged the
// user out for good over something that says nothing about their credentials.

import 'package:dio/dio.dart';

import 'failures.dart';

/// Whether [error] is a genuine authentication rejection: HTTP 401 or 403.
///
/// A 401 arrives as [UnauthorizedFailure]; a 403 has no dedicated failure
/// type (`ErrorMapperInterceptor` maps it to [UnknownFailure]) and is read off
/// the carried [DioException]. When [includeValidation] is true (the
/// `/auth/refresh` call), a [ValidationFailure] also counts: the refresh
/// endpoint rejecting the token it was handed as malformed.
///
/// Everything else — no network, a 5xx, a 2xx the client could not map, a
/// non-[Failure] error — is NOT a rejection.
bool isAuthRejection(Object error, {bool includeValidation = false}) {
  if (error is UnauthorizedFailure) return true;
  if (includeValidation && error is ValidationFailure) return true;
  if (error is Failure) {
    final Object? cause = error.cause;
    if (cause is DioException) {
      final int? status = cause.response?.statusCode;
      return status == 401 || status == 403;
    }
  }
  return false;
}
