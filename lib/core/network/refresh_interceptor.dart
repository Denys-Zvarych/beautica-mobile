// Phase 2.7 — Refresh interceptor (single-flight 401 handler).
//
// Responsibilities:
//   - On HTTP 401: attempt a silent token refresh via POST /auth/refresh.
//   - Single-flight: if multiple requests 401 concurrently, exactly one
//     refresh is issued; others await the same Completer.
//   - On successful refresh: update the in-memory access token via
//     authProvider.notifier.setAccessToken() and retry the failed request
//     with the new token.
//   - On failed refresh (expired/revoked RT): call logout() to wipe the
//     session and redirect the user to the login screen via the router guard.
//   - X-No-Retry header: set on the retried request to prevent the interceptor
//     from looping on a second 401 from the retry itself.
//
// CRITICAL: Uses [refreshDioProvider] (no interceptors) — never [dioProvider]
// for the refresh call. Using the auth-wired Dio for the refresh would cause
// circular request loops.

import 'dart:async';
import 'dart:developer';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'refresh_dio_provider.dart';

/// Dio interceptor that handles 401 responses with a silent token refresh.
///
/// Injected into [dioProvider]'s interceptor chain **after**
/// [ErrorMapperInterceptor]. Constructed with the enclosing [Ref] and the
/// parent [Dio] instance (so it can replay failed requests via `_dio.fetch`).
///
/// Thread safety: Dio interceptors run on the same isolate as the initiating
/// request. The [Completer]-based single-flight guard is therefore safe.
final class RefreshInterceptor extends Interceptor {
  RefreshInterceptor(this._ref, this._dio);

  final Ref _ref;

  /// The [Dio] instance whose interceptor chain this object belongs to.
  /// Used to replay failed requests after a successful token refresh.
  final Dio _dio;

  /// Non-null while a refresh request is in flight.
  /// Subsequent 401s await this rather than issuing duplicate refreshes.
  Completer<String>? _refreshing;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final opts = err.requestOptions;

    // Only handle 401. Skip if X-No-Retry is set (prevents retry loops) or
    // if the error is not an HTTP response error (network errors, etc.).
    if (err.response?.statusCode != 401 ||
        opts.headers['X-No-Retry'] == 'true') {
      return handler.next(err);
    }

    try {
      // Coalesce concurrent refreshes into a single network call.
      final newAccess = await (_refreshing ??= _runRefresh()).future;
      _refreshing = null;

      // Replay the original request with the updated token.
      opts.headers['Authorization'] = 'Bearer $newAccess';
      // Mark so that a second 401 on the retry doesn't loop.
      opts.headers['X-No-Retry'] = 'true';

      final retried = await _dio.fetch<dynamic>(opts);
      handler.resolve(retried);
    } catch (e, st) {
      _refreshing = null;
      log(
        'Token refresh failed — logging out',
        name: 'auth.refresh',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      // Wipe the session; router guard will redirect to /login.
      await _ref.read(authProvider.notifier).logout();
      handler.next(err);
    }
  }

  /// Starts a single token-refresh network call and returns a [Completer]
  /// whose future resolves to the new access token string.
  ///
  /// Uses [refreshDioProvider] — the clean Dio with no interceptors — to
  /// avoid triggering [AuthInterceptor] or [RefreshInterceptor] recursively.
  Completer<String> _runRefresh() {
    final c = Completer<String>();
    Future<void>(() async {
      final storage = _ref.read(secureStorageProvider);
      final rt = await storage.readRefreshToken();
      if (rt == null) {
        throw const UnauthorizedFailure(
          cause: 'No refresh token in secure storage',
        );
      }

      final response = await _ref
          .read(refreshDioProvider)
          .post<Map<String, dynamic>>(
            '/auth/refresh',
            data: {'refreshToken': rt},
          );

      final data = response.data!['data'] as Map<String, dynamic>;
      final newRefreshToken = data['refreshToken'] as String;
      final newAccessToken = data['accessToken'] as String;

      // Persist the rotated refresh token.
      await storage.writeRefreshToken(newRefreshToken);
      // Update the in-memory access token so AuthInterceptor sends the new one.
      _ref.read(authProvider.notifier).setAccessToken(newAccessToken);

      log('Token refreshed silently', name: 'auth.refresh', level: 800);
      c.complete(newAccessToken);
    }).onError((e, st) {
      log(
        '_runRefresh failed',
        name: 'auth.refresh',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      c.completeError(e ?? const UnknownFailure(), st);
    });
    return c;
  }
}
