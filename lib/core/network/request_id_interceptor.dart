// Phase 410 (R.3 D5) — request-ID correlation + scrubbed HTTP breadcrumbs.
//
// Every outbound request carries `X-Request-Id` = a fresh random 128-bit hex.
// The backend (phase 371 D5, `RequestIdFilter`) accepts any id matching
// `^[A-Za-z0-9._-]{8,64}$` and echoes it in the response header, its logs and
// the `ApiResponse.requestId` error-body field — so a phone crash, a timeout
// and a server log line share one id.
//
// Each finished request (response OR error) adds ONE Sentry breadcrumb,
// category `http`, data `{method, path, status, request_id, duration_ms}`:
//   - `path` is [normalisePath]-ed — UUIDs, digit runs, `@`/`%` segments and
//     long segments become `{id}` (invite tokens, phone numbers, encoded free
//     text never leave the device);
//   - NEVER the query string, headers, or request/response body.
// `Sentry.addBreadcrumb` is a no-op when crash reporting is not initialised
// (debug, local, no DSN), so this interceptor is inert there.
//
// Order: FIRST in the `dioProvider` chain (before `AuthInterceptor`), so the
// id is on the request before anything else can reject or replay it.

import 'dart:math';

import 'package:dio/dio.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../diagnostics/install_id.dart' show randomHex128;

/// Header the backend reads/echoes (`RequestIdFilter.HEADER`).
const String kRequestIdHeader = 'X-Request-Id';

/// `RequestOptions.extra` key holding the request's running [Stopwatch].
const String _kStartedAtExtra = 'beautica.requestStartedAtUs';

/// The request id of [err]: the server's echo (response header, then the
/// 371 `requestId` body field) and, failing both (timeout, no connection), the
/// id this app sent. `null` only when the request never passed
/// [RequestIdInterceptor].
String? requestIdOf(DioException err) {
  final String? echoed = err.response?.headers.value(kRequestIdHeader);
  if (echoed != null && echoed.isNotEmpty) return echoed;
  final Object? data = err.response?.data;
  if (data is Map) {
    final Object? body = data['requestId'];
    if (body is String && body.isNotEmpty) return body;
  }
  final Object? sent = err.requestOptions.headers[kRequestIdHeader];
  return sent is String && sent.isNotEmpty ? sent : null;
}

final RegExp _ownRequestId = RegExp(r'^[0-9a-f]{32}$');

/// The id THIS APP sent for [err]'s request ([RequestIdInterceptor] format:
/// 32 lowercase hex), or `null` when absent or of any other shape. Unlike
/// [requestIdOf] it never returns the server echo — crash-report tags must
/// carry only a value the app itself generated.
String? sentRequestIdOf(DioException err) {
  final Object? sent = err.requestOptions.headers[kRequestIdHeader];
  return sent is String && _ownRequestId.hasMatch(sent) ? sent : null;
}

final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
final RegExp _digitRun = RegExp(r'\d{3,}');

/// Replaces every path segment that can carry an identifier with `{id}`:
/// UUIDs, segments with a run of ≥ 3 digits, segments containing `@` or a
/// percent-escape, and segments longer than 24 chars. Short literal segments
/// (`api`, `v1`, `bookings`) are kept. Query and fragment are never part of
/// the input — callers pass `uri.path`.
String normalisePath(String path) {
  final List<String> segments = path.split('/');
  return segments
      .map((String s) {
        if (s.isEmpty) return s;
        if (_uuid.hasMatch(s) ||
            _digitRun.hasMatch(s) ||
            s.contains('@') ||
            s.contains('%') ||
            s.length > 24) {
          return '{id}';
        }
        return s;
      })
      .join('/');
}

final class RequestIdInterceptor extends Interceptor {
  RequestIdInterceptor({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // A fresh id per ATTEMPT — a refresh-replayed request is a separate
    // server request with its own log line.
    options.headers[kRequestIdHeader] = randomHex128(_random);
    options.extra[_kStartedAtExtra] = Stopwatch()..start();
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _breadcrumb(response.requestOptions, response.statusCode, null);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _breadcrumb(err.requestOptions, err.response?.statusCode, err.type);
    handler.next(err);
  }

  void _breadcrumb(RequestOptions o, int? status, DioExceptionType? errorType) {
    final Object? started = o.extra[_kStartedAtExtra];
    final int? durationMs = started is Stopwatch
        ? started.elapsedMilliseconds
        : null;
    final Object? id = o.headers[kRequestIdHeader];
    Sentry.addBreadcrumb(
      Breadcrumb(
        type: 'http',
        category: 'http',
        level: errorType == null ? SentryLevel.info : SentryLevel.warning,
        data: buildHttpBreadcrumbData(
          method: o.method,
          path: o.uri.path,
          status: status,
          requestId: id is String ? id : null,
          durationMs: durationMs,
          errorType: errorType,
        ),
      ),
    );
  }
}

/// The breadcrumb `data` map — exposed for the unit test. Contains ONLY these
/// keys; [path] is normalised here so no caller can forget.
Map<String, dynamic> buildHttpBreadcrumbData({
  required String method,
  required String path,
  required int? status,
  required String? requestId,
  required int? durationMs,
  DioExceptionType? errorType,
}) => <String, dynamic>{
  'method': method,
  'path': normalisePath(path),
  'status': ?status,
  'request_id': ?requestId,
  'duration_ms': ?durationMs,
  if (errorType != null) 'error_type': errorType.name,
};
