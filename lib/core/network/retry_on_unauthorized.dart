// Single-use-body 401 retry — the ONE shared seam for multipart sends.
//
// `FormData` is finalised on first send, so `RefreshInterceptor` refreshes the
// token on a 401 but cannot replay the request; it hands the 401 back
// (`refresh_interceptor.dart`). A caller that owns the payload re-sends ONCE
// with a freshly built body so the file is delivered with the new token.
// Used by `HttpMediaUploadRepository` and `HttpSupportRepository`.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

/// True when [e] is a 401 (raw status or the mapper's [UnauthorizedFailure]).
bool isUnauthorizedDio(DioException e) =>
    e.response?.statusCode == 401 || e.error is UnauthorizedFailure;

/// Runs [attempt]; on a 401 [DioException] re-runs it exactly ONCE (so the
/// caller builds a fresh body inside [attempt]) unless [isUnauthorized] says no
/// or [isSessionLive] reports the session ended. Any other error, and a second
/// 401, is rethrown unchanged. [onRetry] fires just before the re-attempt.
Future<T> retryOnceOnUnauthorized<T>(
  Future<T> Function() attempt, {
  bool Function(DioException e) isUnauthorized = isUnauthorizedDio,
  bool Function()? isSessionLive,
  void Function(DioException e)? onRetry,
}) async {
  for (var n = 0; ; n++) {
    try {
      return await attempt();
    } on DioException catch (e) {
      if (n == 0 && isUnauthorized(e) && (isSessionLive?.call() ?? true)) {
        onRetry?.call(e);
        continue;
      }
      rethrow;
    }
  }
}

/// Imperative read of the auth session (never a watch — a bare authProvider
/// watch would rebuild/destroy the caller on every auth emission). Mirrors the
/// router's `resolvedSession()`: only a settled AsyncData counts as ended.
bool isAuthSessionLive(Ref ref) {
  final auth = ref.read(authProvider);
  return auth is! AsyncData<AuthSession> || auth.value is Authenticated;
}
