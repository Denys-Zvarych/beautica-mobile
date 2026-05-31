// Phase 2.2 — Auth interceptor.
//
// Attaches the in-memory JWT access token to outgoing requests as a Bearer
// token. Auth endpoints are excluded to avoid attaching a stale token to
// login / registration / refresh calls.
//
// The interceptor reads the current [AuthSession] from [authProvider].
// It intentionally does NOT handle 401 responses — that is the responsibility
// of the RefreshInterceptor added in Phase 2.7.
//
// Threading note: Dio interceptors are called on the same isolate that
// initiated the request; `ref.read` is safe here (not inside `build`).

import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/domain/auth_session.dart';
import '../../features/auth/presentation/auth_notifier.dart';
import 'auth_paths.dart';

/// Riverpod-aware Dio interceptor that injects the Bearer access token.
///
/// Constructed by [dioProvider] and given the enclosing [Ref] so it can read
/// [authProvider] without holding a stale reference.
///
/// Note: the generated provider name is `authProvider` (Riverpod 3.x strips
/// the "Notifier" suffix from the class name when generating the accessor).
final class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._ref);

  final Ref _ref;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final path = options.path;

    // Exact-match skip-list — auth endpoints (login, refresh, register, …).
    if (kAuthPaths.contains(path)) {
      handler.next(options);
      return;
    }

    // Prefix-match skip-list — public endpoints with dynamic path segments
    // (e.g. /api/v1/locations/oblasts/{uuid}/cities). Bearer token must not
    // be attached to these even when the user is authenticated.
    if (kPublicPathPrefixes.any(path.startsWith)) {
      handler.next(options);
      return;
    }

    // Prefer the settled Authenticated state (normal post-cold-start path).
    final session = _ref.read(authProvider).value;
    final String? accessToken;

    if (session is Authenticated) {
      accessToken = session.accessToken;
    } else {
      // HIGH-1 (mobile-security 2026-05-24): during cold-start, authProvider
      // is still in AsyncLoading while build() awaits repo.me(). The notifier
      // stores the freshly-rotated access token in [coldStartAccessToken] so
      // we can inject the Bearer header on /users/me without a mid-build
      // state mutation (which would cause provider.future to resolve with a
      // sentinel user rather than the real user).
      accessToken = _ref.read(authProvider.notifier).coldStartAccessToken;
    }

    if (accessToken != null) {
      options.headers['Authorization'] = 'Bearer $accessToken';
      if (kDebugMode) {
        log(
          'Attaching Bearer token to ${options.method} ${options.path}',
          name: 'network.auth',
          level: 700, // FINE
        );
      }
    }

    handler.next(options);
  }
}
