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
      // The provider is not currently resolvable to an Authenticated AsyncData
      // state. This happens in two situations:
      //   1. Cold-start (HIGH-1, mobile-security 2026-05-24): authProvider is
      //      still in AsyncLoading while build() awaits repo.me(). The notifier
      //      stores the freshly-rotated access token so we can inject the Bearer
      //      header on /users/me without a mid-build state mutation.
      //   2. Mid-rebuild race (delete-service false 401): the delete flow
      //      invalidates masterProfileProvider, which serviceRepositoryProvider
      //      watches; while that rebuild runs, a watcher of authProvider can be
      //      momentarily unresolved. Sending the in-flight DELETE tokenless
      //      yields a false 401 ("Сесія завершилась").
      //
      // [lastKnownAccessToken] resolves both: it returns the cold-start sentinel
      // when present, else the last-known token of the current authenticated
      // session. It is null only when there is genuinely no session (cold start
      // with no stored token, or after logout) — in which case we send the
      // request tokenless and let the backend / RefreshInterceptor decide.
      accessToken = _ref.read(authProvider.notifier).lastKnownAccessToken;
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
