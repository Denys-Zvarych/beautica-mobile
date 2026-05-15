// Phase 2.2 — HTTP logging interceptor.
//
// Active only in debug builds (`kDebugMode`). Logs each request/response at
// the FINE level (700) using `dart:developer`'s `log()` — never `print()`.
//
// Sensitive data is redacted before logging:
//   • The `Authorization` header value is replaced with `***REDACTED***`.
//   • The full request body for auth endpoints is suppressed (shows "[REDACTED]").
//
// Response timing is measured from [onRequest] to [onResponse] / [onError]
// using [Stopwatch]. The stopwatch is stored on [RequestOptions.extra] under
// the key `_kStopwatchKey` so it survives through the interceptor chain.

import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'auth_paths.dart';

/// [RequestOptions.extra] key under which this interceptor stores its
/// [Stopwatch] instance for response-time measurement.
const _kStopwatchKey = '_beautica_log_stopwatch';

/// Debug-only Dio interceptor that logs HTTP traffic to `dart:developer`.
///
/// Only installed when [kDebugMode] is `true` (controlled by [dioProvider]).
/// Safe to instantiate in non-debug builds but the constructor should never
/// be reached in release mode — [dioProvider] guards the `if (kDebugMode)`
/// branch before calling `LoggingInterceptor()`.
final class LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!kDebugMode) {
      handler.next(options);
      return;
    }

    // Start timing.
    final stopwatch = Stopwatch()..start();
    options.extra[_kStopwatchKey] = stopwatch;

    // Redact Authorization header for log output.
    final headers = Map<String, dynamic>.from(options.headers);
    if (headers.containsKey('Authorization')) {
      headers['Authorization'] = '***REDACTED***';
    }

    // Redact body for sensitive endpoints.
    final dynamic body = kAuthPaths.contains(options.path)
        ? '[REDACTED]'
        : options.data;

    log(
      '--> ${options.method} ${options.baseUrl}${options.path}\n'
      '    headers: $headers\n'
      '    body: $body',
      name: 'http',
      level: 700, // FINE
    );

    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    if (!kDebugMode) {
      handler.next(response);
      return;
    }

    final elapsed = _stopElapsed(response.requestOptions);

    log(
      '<-- ${response.statusCode} ${response.requestOptions.method} '
      '${response.requestOptions.path} (${elapsed}ms)',
      name: 'http',
      level: 700, // FINE
    );

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (!kDebugMode) {
      handler.next(err);
      return;
    }

    final elapsed = _stopElapsed(err.requestOptions);

    log(
      '<-- ERROR ${err.requestOptions.method} ${err.requestOptions.path} '
      '(${elapsed}ms) ${err.type} ${err.response?.statusCode ?? ""}',
      name: 'http',
      level: 900, // WARNING
      error: '${err.type} ${err.response?.statusCode}',
    );

    handler.next(err);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  int _stopElapsed(RequestOptions options) {
    final stopwatch = options.extra[_kStopwatchKey];
    if (stopwatch is Stopwatch) {
      stopwatch.stop();
      return stopwatch.elapsedMilliseconds;
    }
    return -1;
  }
}
