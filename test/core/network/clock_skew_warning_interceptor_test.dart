// 2026-08-02 — unit tests for [ClockSkewWarningInterceptor].
//
// This interceptor is diagnostics-only (see its file header): it never
// mutates the request/response, and `dart:developer`'s `log()` cannot be
// intercepted from a `flutter test` process (a VM-service native call — see
// `logging_interceptor.dart`'s identical note), so these tests assert on the
// one thing that IS observable from the outside: the response always passes
// through the interceptor UNCHANGED and the handler is always advanced,
// regardless of whether a skew warning fires internally. That is exactly the
// "never trusted or applied" contract the file header promises.

import 'dart:async';

import 'package:beautica_mobile/core/network/clock_skew_warning_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

Response<dynamic> _response({String? dateHeader}) {
  final requestOptions = RequestOptions(path: '/ping');
  final headers = Headers();
  if (dateHeader != null) {
    headers.set('date', dateHeader);
  }
  return Response<dynamic>(
    requestOptions: requestOptions,
    statusCode: 200,
    headers: headers,
  );
}

void main() {
  late ClockSkewWarningInterceptor interceptor;

  setUp(() {
    interceptor = ClockSkewWarningInterceptor();
  });

  group('ClockSkewWarningInterceptor — diagnostics only, never mutates', () {
    test('a response with a valid, in-sync Date header passes through '
        'unchanged', () async {
      final now = DateTime.now().toUtc();
      final response = _response(dateHeader: HttpDateFormat.format(now));

      final passedThrough = await _run(interceptor, response);

      expect(identical(passedThrough, response), isTrue);
    });

    test(
      'a response with a Date header far in the past (large skew) still '
      'passes through unchanged — the skew is logged, never acted on',
      () async {
        final skewed = DateTime.utc(2000, 1, 1);
        final response = _response(dateHeader: HttpDateFormat.format(skewed));

        final passedThrough = await _run(interceptor, response);

        expect(identical(passedThrough, response), isTrue);
      },
    );

    test('a response with NO Date header passes through unchanged', () async {
      final response = _response();

      final passedThrough = await _run(interceptor, response);

      expect(identical(passedThrough, response), isTrue);
    });

    test('a response with a MALFORMED Date header passes through unchanged '
        '(malformed header is swallowed, not thrown)', () async {
      final response = _response(dateHeader: 'not-a-date');

      final passedThrough = await _run(interceptor, response);

      expect(identical(passedThrough, response), isTrue);
    });
  });
}

/// Drives [interceptor]'s `onResponse` and returns whatever it forwards to
/// the handler (or throws if it never calls `next`/`reject`).
Future<Response<dynamic>> _run(
  Interceptor interceptor,
  Response<dynamic> response,
) {
  final completer = Completer<Response<dynamic>>();
  interceptor.onResponse(
    response,
    _RecordingHandler((r) => completer.complete(r)),
  );
  return completer.future;
}

class _RecordingHandler extends ResponseInterceptorHandler {
  _RecordingHandler(this._onNext);

  final void Function(Response<dynamic>) _onNext;

  @override
  void next(Response<dynamic> response) => _onNext(response);
}

/// Minimal RFC 1123 formatter for test fixtures — the inverse of
/// `dart:io`'s `HttpDate.parse`, which the interceptor uses internally.
abstract final class HttpDateFormat {
  static String format(DateTime dateTime) {
    const weekdays = <String>[
      'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun', //
    ];
    const months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
    ];
    final utc = dateTime.toUtc();
    final wd = weekdays[utc.weekday - 1];
    final mo = months[utc.month - 1];
    String pad2(int n) => n.toString().padLeft(2, '0');
    return '$wd, ${pad2(utc.day)} $mo ${utc.year} '
        '${pad2(utc.hour)}:${pad2(utc.minute)}:${pad2(utc.second)} GMT';
  }
}
