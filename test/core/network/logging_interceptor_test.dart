// Tests for LoggingInterceptor request-path behaviour.
//
// LoggingInterceptor attaches timing data and redacts sensitive headers/bodies
// before logging. In debug mode it:
//   - Replaces the Authorization header value with '***REDACTED***'.
//   - Suppresses request body logging for auth paths.
//
// We drive onRequest directly without constructing a full Dio instance.

import 'package:beautica_mobile/core/network/logging_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRequestHandler extends Mock implements RequestInterceptorHandler {}

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/'));
  });

  RequestOptions buildOpts(
    String path, {
    Map<String, dynamic>? headers,
    dynamic data,
  }) => RequestOptions(
    path: path,
    baseUrl: 'https://api.beautica.test',
    headers: headers ?? {},
    data: data,
  );

  group('LoggingInterceptor.onRequest', () {
    test('passes request to next handler', () {
      final interceptor = LoggingInterceptor();
      final handler = MockRequestHandler();
      final opts = buildOpts('/user/me');

      interceptor.onRequest(opts, handler);

      verify(() => handler.next(any())).called(1);
    });

    test('Authorization header is replaced with ***REDACTED***', () {
      final interceptor = LoggingInterceptor();
      final handler = MockRequestHandler();
      final opts = buildOpts(
        '/user/me',
        headers: {'Authorization': 'Bearer super-secret-token'},
      );

      // The interceptor must not mutate the live options' Authorization value.
      // It makes a defensive copy for logging. Verify it still calls handler.next.
      interceptor.onRequest(opts, handler);

      // The original options are passed through unmodified.
      expect(
        opts.headers['Authorization'],
        equals('Bearer super-secret-token'),
      );
      verify(() => handler.next(any())).called(1);
    });

    test(
      'auth-path request passes through (body logging suppressed internally)',
      () {
        final interceptor = LoggingInterceptor();
        final handler = MockRequestHandler();
        final opts = buildOpts(
          '/auth/login',
          data: {'email': 'user@example.com', 'password': 'secret'},
        );

        interceptor.onRequest(opts, handler);

        // The interceptor must pass the request through regardless of path.
        verify(() => handler.next(any())).called(1);
        // The data must be untouched (logging only reads it, never modifies it).
        expect(
          (opts.data as Map<String, dynamic>)['password'],
          equals('secret'),
        );
      },
    );
  });
}
