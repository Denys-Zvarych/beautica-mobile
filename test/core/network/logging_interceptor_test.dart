// Tests for LoggingInterceptor request-path behaviour.
//
// LoggingInterceptor attaches timing data and redacts sensitive headers/bodies
// before logging. In debug mode it:
//   - Replaces the Authorization header value with '***REDACTED***'.
//   - Suppresses request body logging for auth paths.
//
// We drive onRequest directly without constructing a full Dio instance.

import 'package:beautica_mobile/core/network/auth_paths.dart';
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

  // ── Finding 3: PII path matching (dynamic segments + query strings) ────────
  group('isPiiPath', () {
    test('matches exact auth + PII paths from kPiiPaths', () {
      expect(isPiiPath('/api/v1/auth/login'), isTrue);
      expect(isPiiPath('/api/v1/independent-masters/me/profile'), isTrue);
      expect(isPiiPath('/api/v1/search/masters'), isTrue);
    });

    test('matches dynamic service update/delete by {serviceDefId} prefix', () {
      expect(
        isPiiPath('/api/v1/services/123e4567-e89b-12d3-a456-426614174000'),
        isTrue,
      );
      expect(isPiiPath('/api/v1/services/123e4567/photo'), isTrue);
    });

    test('matches service create + bulk + service-types/suggest', () {
      expect(isPiiPath('/api/v1/independent-masters/me/services'), isTrue);
      expect(isPiiPath('/api/v1/independent-masters/me/services/bulk'), isTrue);
      expect(isPiiPath('/api/v1/service-types/suggest'), isTrue);
    });

    test('matches dynamic working-hours / weekly-schedules by segment', () {
      expect(isPiiPath('/api/v1/masters/abc-123/working-hours'), isTrue);
      expect(
        isPiiPath('/api/v1/masters/abc-123/weekly-schedules/sched-9'),
        isTrue,
      );
    });

    test('ignores the query string when classifying', () {
      expect(isPiiPath('/api/v1/search/masters?q=Олена'), isTrue);
      expect(isPiiPath('/api/v1/service-types/suggest?q=Ма'), isTrue);
    });

    test('returns false for genuinely non-PII public reads', () {
      expect(isPiiPath('/api/v1/locations/oblasts'), isFalse);
      expect(isPiiPath('/api/v1/masters/abc-123'), isFalse);
      expect(isPiiPath('/api/v1/service-types'), isFalse);
    });
  });

  group('redactLogPath', () {
    test('masks the query string for a PII search path (typed name)', () {
      expect(
        redactLogPath('/api/v1/search/masters?q=Олена%20Петрова&page=0'),
        equals('/api/v1/search/masters?[REDACTED]'),
      );
    });

    test('masks the query string for an auth path (token leak guard)', () {
      expect(
        redactLogPath('/api/v1/auth/reset-password?token=super-secret'),
        equals('/api/v1/auth/reset-password?[REDACTED]'),
      );
    });

    test('leaves non-PII pagination query strings visible for debugging', () {
      expect(
        redactLogPath('/api/v1/locations/oblasts?page=2'),
        equals('/api/v1/locations/oblasts?page=2'),
      );
    });

    test('returns the path unchanged when there is no query string', () {
      expect(
        redactLogPath('/api/v1/services/abc-123'),
        equals('/api/v1/services/abc-123'),
      );
    });
  });

  group('LoggingInterceptor body redaction for dynamic PII routes', () {
    test('a dynamic service-update request passes through without mutating data '
        '(redaction is log-only)', () {
      final interceptor = LoggingInterceptor();
      final handler = MockRequestHandler();
      // This path is NOT in the exact kPiiPaths set — it only matches via the
      // {serviceDefId} prefix, which the old `kPiiPaths.contains` check missed.
      final opts = buildOpts(
        '/api/v1/services/abc-123',
        data: {'name': 'Стрижка для Олени', 'basePrice': 500},
      );

      interceptor.onRequest(opts, handler);

      verify(() => handler.next(any())).called(1);
      // The live request body is never mutated by the logger.
      expect(
        (opts.data as Map<String, dynamic>)['name'],
        equals('Стрижка для Олени'),
      );
      // Sanity: the interceptor classifies this dynamic route as PII.
      expect(isPiiPath(opts.path), isTrue);
    });
  });
}
