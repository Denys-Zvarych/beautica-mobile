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

/// Signature of the sink [LoggingInterceptor] writes its formatted lines to.
///
/// Exists ONLY so tests can observe what actually reaches the log. See the
/// [LoggingInterceptor.sink] doc comment for why a test seam is unavoidable
/// here.
typedef LogSink =
    void Function(String message, {String name, int level, Object? error});

/// The production sink — `dart:developer`'s `log()`, never `print()`.
void _developerLogSink(
  String message, {
  String name = '',
  int level = 0,
  Object? error,
}) => log(message, name: name, level: level, error: error);

/// Debug-only Dio interceptor that logs HTTP traffic to `dart:developer`.
///
/// Only installed when [kDebugMode] is `true` (controlled by [dioProvider]).
/// Safe to instantiate in non-debug builds but the constructor should never
/// be reached in release mode — [dioProvider] guards the `if (kDebugMode)`
/// branch before calling `LoggingInterceptor()`.
final class LoggingInterceptor extends Interceptor {
  /// [sink] defaults to `dart:developer`'s `log()` — production behaviour is
  /// byte-identical to the pre-seam version.
  LoggingInterceptor({LogSink? sink}) : sink = sink ?? _developerLogSink;

  /// Where formatted log lines are written.
  ///
  /// WHY THIS SEAM EXISTS (2026-07-22 vacuous-assertion audit)
  /// --------------------------------------------------------
  /// The redaction below operates on a DEFENSIVE COPY of the headers and on a
  /// LOCAL `body` variable — it deliberately never mutates [RequestOptions].
  /// That is correct, but it made the redaction untestable through the
  /// interceptor's inputs: the two tests that claimed to guard it
  /// (`test/core/network/logging_interceptor_test.dart`) only asserted the
  /// SOURCE options were unchanged, which is true whether the redaction runs
  /// or is deleted outright. Both passed with the redaction removed entirely,
  /// so nothing in CI verified that bearer tokens and passwords stay out of
  /// the logs.
  ///
  /// `dart:developer`'s `log()` cannot be intercepted from a `flutter test`
  /// process (it is a VM-service native call — a `runZoned`
  /// `ZoneSpecification.print` capture observes nothing; verified
  /// empirically). Injecting the sink is therefore the only way to assert on
  /// the string that actually reaches the log.
  @visibleForTesting
  final LogSink sink;

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

    sink(
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

    sink(
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

    sink(
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
