// Phase 2.7 — Refresh interceptor (single-flight 401 handler).
// MEDIUM-1   — Shared TokenRefreshLock replaces the instance-local
//             _refreshing Completer so the single-flight guard is shared with
//             HttpAuthRepository.refresh() (mobile-perf 2026-05-28).
//
// Responsibilities:
//   - On HTTP 401: attempt a silent token refresh via POST /auth/refresh.
//   - Single-flight: if multiple requests 401 concurrently, exactly one
//     refresh is issued; others await the same Completer via
//     [TokenRefreshLock]. The lock is also consulted by
//     [HttpAuthRepository.refresh] so the cold-start AuthNotifier path and
//     the 401-triggered interceptor path can never overlap.
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

import 'package:flutter/foundation.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'refresh_dio_provider.dart';
import 'token_refresh_lock.dart';

/// Dio interceptor that handles 401 responses with a silent token refresh.
///
/// Injected into [dioProvider]'s interceptor chain **after**
/// [ErrorMapperInterceptor]. Constructed with the enclosing [Ref] and the
/// parent [Dio] instance (so it can replay failed requests via `_dio.fetch`).
///
/// Thread safety: Dio interceptors run on the same isolate as the initiating
/// request. The [TokenRefreshLock]-based single-flight guard is therefore safe.
/// The lock is shared with [HttpAuthRepository] via the Riverpod provider graph,
/// preventing simultaneous cross-path refreshes.
final class RefreshInterceptor extends Interceptor {
  RefreshInterceptor(this._ref, this._dio);

  final Ref _ref;

  /// The [Dio] instance whose interceptor chain this object belongs to.
  /// Used to replay failed requests after a successful token refresh.
  final Dio _dio;

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
      // Consult the shared lock. If HttpAuthRepository.refresh() or a
      // concurrent interceptor call already started a refresh, await the
      // same Completer result rather than issuing a duplicate request.
      final lock = _ref.read(tokenRefreshLockProvider);
      final AuthTokens tokens;
      if (lock.pending != null) {
        tokens = await lock.pending!.future;
      } else {
        tokens = await _runRefresh(lock);
      }

      // Replay the original request with the updated token.
      opts.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
      // Mark so that a second 401 on the retry doesn't loop.
      opts.headers['X-No-Retry'] = 'true';

      final retried = await _dio.fetch<dynamic>(opts);
      handler.resolve(retried);
    } catch (e, st) {
      if (kDebugMode) {
        log(
          'Token refresh failed — logging out',
          name: 'auth.refresh',
          level: 1000,
          error: e,
          stackTrace: st,
        );
      }
      // Wipe the session; router guard will redirect to /login.
      await _ref.read(authProvider.notifier).logout();
      handler.next(err);
    }
  }

  /// Starts a single token-refresh network call and returns the new
  /// [AuthTokens] pair.
  ///
  /// Claims [lock] for the duration of the network call and releases it in
  /// a `finally` block. Concurrent callers on either path that arrive after
  /// [claim] is called will await [lock.pending!.future] and share the result.
  ///
  /// Uses [refreshDioProvider] — the clean Dio with no interceptors — to
  /// avoid triggering [AuthInterceptor] or [RefreshInterceptor] recursively.
  Future<AuthTokens> _runRefresh(TokenRefreshLock lock) async {
    final completer = lock.claim();
    // Silence "unhandled future error" for the case where this is the only
    // caller (no concurrent waiter is subscribed to completer.future). The
    // error still propagates to any listener that IS attached (concurrent
    // 401 callers awaiting lock.pending!.future). ignore() prevents the Dart
    // runtime from treating the unlistened error as uncaught.
    completer.future.ignore();
    try {
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

      if (kDebugMode) {
        log('Token refreshed silently', name: 'auth.refresh', level: 800);
      }

      final tokens = AuthTokens(
        accessToken: newAccessToken,
        refreshToken: newRefreshToken,
      );
      completer.complete(tokens);
      return tokens;
    } catch (e, st) {
      if (kDebugMode) {
        log(
          '_runRefresh failed',
          name: 'auth.refresh',
          level: 1000,
          error: e,
          stackTrace: st,
        );
      }
      completer.completeError(e, st);
      rethrow;
    } finally {
      lock.release();
    }
  }
}
