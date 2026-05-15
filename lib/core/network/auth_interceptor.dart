// Phase 2.2 — Auth interceptor.
//
// Attaches the in-memory JWT access token to outgoing requests as a Bearer
// token. Auth endpoints are excluded to avoid attaching a stale token to
// login / registration / refresh calls.
//
// The interceptor reads the current [AuthState] from [authNotifierProvider].
// It intentionally does NOT handle 401 responses — that is the responsibility
// of the RefreshInterceptor added in Phase 2.7.
//
// Threading note: Dio interceptors are called on the same isolate that
// initiated the request; `ref.read` is safe here (not inside `build`).

import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_notifier.dart';

/// Paths that must never receive an `Authorization` header.
///
/// These are matched against [RequestOptions.path], which contains only the
/// path segment (no host), as set by [BaseOptions.baseUrl].
const _authEndpoints = {'/auth/login', '/auth/register', '/auth/refresh'};

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
    // `.value` returns null when the AsyncValue is loading or in an error
    // state — both are treated as unauthenticated (no token attached).
    final state = _ref.read(authProvider).value;

    if (state is Authenticated && !_authEndpoints.contains(options.path)) {
      options.headers['Authorization'] = 'Bearer ${state.accessToken}';
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
