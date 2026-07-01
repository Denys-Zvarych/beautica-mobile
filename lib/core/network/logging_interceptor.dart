// Phase 2.2 — HTTP logging interceptor.
//
// Active only in debug builds (`kDebugMode`). Logs each request/response at
// the FINE level (700) using `dart:developer`'s `log()` — never `print()`.
//
// Sensitive data is redacted before logging:
//   • The `Authorization` header value is replaced with `***REDACTED***`.
//   • The full request body for PII routes (see [isPiiPath]) is suppressed
//     (shows "[REDACTED]"). This covers unauthenticated auth endpoints,
//     authenticated endpoints that carry PII location data, dynamic-segment
//     routes (service create/update, working-hours / weekly-schedules) and
//     free-text search input.
//   • The URL query string for PII routes is masked as `?[REDACTED]` (see
//     [redactLogPath]) so a typed name (search `q`) or token never lands in
//     the log.
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

    // Redact body for sensitive endpoints (auth credentials, OTPs, PII
    // location fields, free-text service / search input). Uses [isPiiPath],
    // which matches exact paths, dynamic-segment prefixes ({serviceDefId}) and
    // segment substrings ({masterId}/working-hours) — a strict superset of the
    // old `kPiiPaths.contains` check.
    final bool pii = isPiiPath(options.path);
    final dynamic body = pii ? '[REDACTED]' : options.data;

    // Mask the query string for PII routes so a typed name (search `q`) or any
    // token in the URL never reaches the log. Non-PII routes keep their query
    // (harmless pagination params stay visible).
    final String loggedPath = redactLogPath(options.path);

    log(
      '--> ${options.method} ${options.baseUrl}$loggedPath\n'
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
      '${redactLogPath(response.requestOptions.path)} (${elapsed}ms)',
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

    // Redact response body for sensitive endpoints to avoid leaking tokens,
    // credentials, or PII location data in error logs. Uses [isPiiPath] to
    // cover auth paths, authenticated PII endpoints AND dynamic-segment routes.
    final dynamic errBody = isPiiPath(err.requestOptions.path)
        ? '[REDACTED]'
        : err.response?.data;

    log(
      '<-- ERROR ${err.requestOptions.method} '
      '${redactLogPath(err.requestOptions.path)} '
      '(${elapsed}ms) ${err.type} ${err.response?.statusCode ?? ""}'
      '${errBody != null ? "\n    body: $errBody" : ""}',
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
