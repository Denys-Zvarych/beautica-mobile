// Tests for LoggingInterceptor request-path behaviour.
//
// LoggingInterceptor attaches timing data and redacts sensitive headers/bodies
// before logging. In debug mode it:
//   - Replaces the Authorization header value with '***REDACTED***'.
//   - Suppresses request body logging for PII paths.
//
// We drive onRequest directly without constructing a full Dio instance.
//
// WHAT CHANGED (2026-07-22 vacuous-assertion audit)
// -------------------------------------------------
// The two redaction tests below used to assert that the SOURCE
// `RequestOptions` were unmodified — `opts.headers['Authorization'] ==
// 'Bearer super-secret-token'` and `opts.data['password'] == 'secret'`. The
// interceptor redacts a defensive COPY of the headers and a LOCAL `body`
// variable and deliberately never mutates the source, so those assertions
// held whether the redaction ran or not: BOTH tests passed with the redaction
// deleted outright. A test named "Authorization header is replaced with
// ***REDACTED***" was verifying nothing about redaction at all, and nothing in
// CI checked that bearer tokens or passwords stay out of the log.
//
// They now assert on the string that ACTUALLY reaches the log, captured via
// `LoggingInterceptor.sink` (see that field's doc comment for why the sink
// seam exists — `dart:developer`'s `log()` cannot be intercepted from a
// `flutter test` process). Each test asserts BOTH directions: the redaction
// marker is present AND the secret is absent.
//
// MUTATION-VERIFIED: deleting the header redaction (`headers['Authorization']
// = '***REDACTED***'`) and the body redaction (`pii ? '[REDACTED]' :
// options.data`) in logging_interceptor.dart turns these tests red. Restored
// immediately; not committed.

import 'package:beautica_mobile/core/network/auth_paths.dart';
import 'package:beautica_mobile/core/network/logging_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRequestHandler extends Mock implements RequestInterceptorHandler {}

/// Collects every line the interceptor writes, so a test can assert on what is
/// actually logged rather than on the (deliberately unmutated) source options.
class _CapturingSink {
  final List<String> lines = <String>[];

  void call(String message, {String name = '', int level = 0, Object? error}) =>
      lines.add(message);

  /// The single line emitted by a one-request drive. Fails loudly rather than
  /// silently passing when nothing was logged at all — a sink that captured
  /// zero lines would make every `isNot(contains(...))` assertion vacuous.
  String get only {
    expect(
      lines,
      hasLength(1),
      reason:
          'expected exactly one log line from the interceptor, got '
          '${lines.length}: $lines',
    );
    return lines.single;
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/'));
    registerFallbackValue(
      DioException(requestOptions: RequestOptions(path: '/')),
    );
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

    test('Authorization header is replaced with ***REDACTED*** in the log', () {
      final sink = _CapturingSink();
      final interceptor = LoggingInterceptor(sink: sink.call);
      final handler = MockRequestHandler();
      final opts = buildOpts(
        '/user/me',
        headers: {'Authorization': 'Bearer super-secret-token'},
      );

      interceptor.onRequest(opts, handler);

      final String logged = sink.only;
      expect(
        logged,
        contains('***REDACTED***'),
        reason: 'the logged headers must carry the redaction marker',
      );
      expect(
        logged,
        isNot(contains('super-secret-token')),
        reason: 'the bearer token must never reach the log',
      );

      // The interceptor redacts a defensive COPY — the live options that go on
      // to the transport must still carry the real credential.
      expect(
        opts.headers['Authorization'],
        equals('Bearer super-secret-token'),
      );
      verify(() => handler.next(any())).called(1);
    });

    // FIXTURE FIX (2026-07-22 audit): this test used to drive the path
    // '/auth/login' — WITHOUT the `/api/v1` prefix every real request carries
    // (AppConfig.baseUrl deliberately excludes it; see auth_paths.dart's
    // header). `isPiiPath('/auth/login')` is FALSE, so the interceptor logged
    // the credentials in full. The old assertion only checked that the source
    // `opts.data` was unmutated, so an unrealistic fixture sat here unnoticed
    // for the whole life of the test. The realistic path is used below; the
    // prefix-sensitivity itself is pinned by the dedicated test further down.
    test(
      'auth-path request body is logged as [REDACTED], not the credentials',
      () {
        final sink = _CapturingSink();
        final interceptor = LoggingInterceptor(sink: sink.call);
        final handler = MockRequestHandler();
        final opts = buildOpts(
          '/api/v1/auth/login',
          data: {'email': 'user@example.com', 'password': 'secret'},
        );

        interceptor.onRequest(opts, handler);

        final String logged = sink.only;
        expect(
          logged,
          contains('body: [REDACTED]'),
          reason: 'a PII path must log the redaction placeholder, not the body',
        );
        expect(
          logged,
          isNot(contains('secret')),
          reason: 'the submitted password must never reach the log',
        );
        expect(
          logged,
          isNot(contains('user@example.com')),
          reason: 'the submitted email must never reach the log',
        );

        // The interceptor must pass the request through regardless of path, and
        // the live body (which the transport still needs) is never mutated.
        verify(() => handler.next(any())).called(1);
        expect(
          (opts.data as Map<String, dynamic>)['password'],
          equals('secret'),
        );
      },
    );

    test('a non-PII request still logs its body (redaction is targeted, not '
        'blanket)', () {
      final sink = _CapturingSink();
      final interceptor = LoggingInterceptor(sink: sink.call);
      final handler = MockRequestHandler();
      final opts = buildOpts('/api/v1/locations/oblasts', data: {'page': 2});

      interceptor.onRequest(opts, handler);

      // Guards the opposite failure mode: a redaction that swallows EVERY body
      // would satisfy the two tests above while destroying the logger's value.
      expect(sink.only, contains('page: 2'));
    });

    // Latent-hazard pin, surfaced by the fixture defect above. Redaction is
    // driven by EXACT/PREFIX matching against paths that all start `/api/v1/`,
    // so if the `/api/v1` prefix ever moves into `AppConfig.baseUrl`, EVERY
    // `RequestOptions.path` loses it and EVERY body-redaction rule silently
    // stops matching — credentials would start landing in the log with no test
    // failing anywhere. This test states that coupling out loud.
    test('body redaction is coupled to the /api/v1 path prefix (moving it into '
        'baseUrl would silently disable redaction)', () {
      expect(
        isPiiPath('/api/v1/auth/login'),
        isTrue,
        reason: 'the real, prefixed request path must be classified PII',
      );
      expect(
        isPiiPath('/auth/login'),
        isFalse,
        reason:
            'documenting the coupling, not endorsing it: an unprefixed path is '
            'NOT redacted. If AppConfig.baseUrl ever absorbs /api/v1, every '
            'entry in kPiiPaths/kPiiPathPrefixes must be re-prefixed in the '
            'same change.',
      );
    });
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

    // mobile-security HIGH mandatory companion (2026-09-01) — the new
    // SALON_MASTER profile-save endpoint. kPiiPaths is EXACT-match only (no
    // prefix semantics — see that Set's own doc comment), so a typo'd entry
    // (wrong case, a stray trailing slash, the wrong sibling copy-pasted)
    // would silently stop matching the REAL request path with nothing
    // failing anywhere — the redaction would just quietly stop firing. This
    // pins the real production path string exactly, and the sibling
    // near-miss below (missing the `/profile` suffix a copy-paste could
    // drop) proves that string alone, not a prefix on `/api/v1/masters/me`,
    // is what makes the real path match.
    test(
      'matches the exact SALON_MASTER profile-save path, not a near-miss',
      () {
        expect(isPiiPath('/api/v1/masters/me/profile'), isTrue);
        expect(
          isPiiPath('/api/v1/masters/me/profile/'),
          isFalse,
          reason:
              'a trailing slash is a DIFFERENT string under exact matching — '
              'if this ever becomes true, kPiiPaths gained an unintended '
              'prefix/segment rule.',
        );
      },
    );
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
    // Carried the SAME vacuity as the two tests above (audit found two; this
    // is the third instance of the shape): it asserted only that `opts.data`
    // was unmutated, which holds with the redaction deleted. Now asserts the
    // free-text service name does not reach the log.
    test('a dynamic service-update body is redacted in the log and left intact '
        'on the wire', () {
      final sink = _CapturingSink();
      final interceptor = LoggingInterceptor(sink: sink.call);
      final handler = MockRequestHandler();
      // This path is NOT in the exact kPiiPaths set — it only matches via the
      // {serviceDefId} prefix, which the old `kPiiPaths.contains` check missed.
      final opts = buildOpts(
        '/api/v1/services/abc-123',
        data: {'name': 'Стрижка для Олени', 'basePrice': 500},
      );

      interceptor.onRequest(opts, handler);

      final String logged = sink.only;
      expect(logged, contains('body: [REDACTED]'));
      expect(
        logged,
        isNot(contains('Олени')),
        // i18n-finder-ok: asserting a PII value is ABSENT from a log line, not
        // locating a widget by UI copy.
        reason:
            'the free-text service name (a client\'s first name here) must not '
            'reach the log via a dynamic {serviceDefId} route',
      );

      verify(() => handler.next(any())).called(1);
      // The live request body is never mutated by the logger.
      expect(
        (opts.data as Map<String, dynamic>)['name'],
        equals('Стрижка для Олени'),
      );
      // Sanity: the interceptor classifies this dynamic route as PII.
      expect(isPiiPath(opts.path), isTrue);
    });

    // Phase 246 (2026-08-19 security fix) — mobile-security HIGH: the master
    // walk-in booking write carries a third party's name/surname/phone, and
    // `/bookings` sits behind a dynamic {masterId} segment (same shape as
    // `/working-hours` above), so before this phase's `kPiiPathSegments` entry
    // the body reached the log verbatim. Behavioural proof, not just the
    // `isPiiPath` unit assertion in `auth_paths_test.dart`: drives the actual
    // interceptor and asserts the guest's phone/name are ABSENT from the
    // logged line, mirroring this group's own vacuous-assertion lesson.
    test('master walk-in booking create body (guest name/surname/phone) is '
        'redacted in the log and left intact on the wire', () {
      final sink = _CapturingSink();
      final interceptor = LoggingInterceptor(sink: sink.call);
      final handler = MockRequestHandler();
      final opts = buildOpts(
        '/api/v1/masters/master-123/bookings',
        data: {
          'masterServiceId': 'service-1',
          'startsAt': '2026-07-10T11:00:00Z',
          'guest': {
            'name': 'Іван',
            'surname': 'Петренко',
            'phone': '+380501234567',
          },
        },
      );

      interceptor.onRequest(opts, handler);

      final String logged = sink.only;
      expect(logged, contains('body: [REDACTED]'));
      expect(
        logged,
        isNot(contains('Петренко')),
        reason: 'the walk-in guest surname must never reach the log',
      );
      expect(
        logged,
        isNot(contains('+380501234567')),
        reason:
            'the walk-in guest phone (E.164 PII) must never reach the '
            'log',
      );

      verify(() => handler.next(any())).called(1);
      // The live request body is never mutated by the logger.
      final Map<String, dynamic> guest =
          (opts.data as Map<String, dynamic>)['guest'] as Map<String, dynamic>;
      expect(guest['phone'], equals('+380501234567'));
      // Sanity: the interceptor classifies this dynamic route as PII.
      expect(isPiiPath(opts.path), isTrue);
    });

    // The error path (onError) redacts response bodies too — a 403/409/422
    // from this same endpoint could echo the guest payload back. Proven
    // separately since onRequest/onError are independent code paths sharing
    // only `isPiiPath`.
    test('master walk-in booking ERROR response body is also redacted (onError '
        'path, independent of onRequest)', () {
      final sink = _CapturingSink();
      final interceptor = LoggingInterceptor(sink: sink.call);
      final handler = _MockErrorHandler();
      final requestOptions = RequestOptions(
        path: '/api/v1/masters/master-123/bookings',
        baseUrl: 'https://api.beautica.test',
      );
      final err = DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: requestOptions,
          statusCode: 409,
          data: {
            'success': false,
            'message': 'Slot taken',
            'guest': {'name': 'Іван', 'surname': 'Петренко'},
          },
        ),
      );

      interceptor.onError(err, handler);

      final String logged = sink.only;
      expect(logged, contains('body: [REDACTED]'));
      expect(logged, isNot(contains('Петренко')));
      verify(() => handler.next(any())).called(1);
    });
  });

  // mobile-security HIGH mandatory companion (2026-09-01) — the SALON_MASTER
  // profile-save endpoint carries the same phone/bio/Instagram PII shape as
  // its `/independent-masters/me/profile` sibling (already covered by the
  // `auth-path request body` test above, which drives `/api/v1/auth/login`
  // rather than this path). This path is an EXACT [kPiiPaths] member, not a
  // dynamic-segment route, so it belongs in its own group rather than the
  // "dynamic PII routes" one above. Item 2 of the 2026-09-01 QA pass:
  // "pin that a PATCH to it does not log its body" — driven as a real PATCH
  // (not the default GET `buildOpts` produces) since that is the verb the
  // real call site (`HttpMasterRepository.updateMyProfile`) issues.
  group('LoggingInterceptor body redaction for /api/v1/masters/me/profile '
      '(mobile-security HIGH mandatory companion, 2026-09-01)', () {
    test('a PATCH to /api/v1/masters/me/profile logs [REDACTED], not the '
        'phone/bio/instagram body', () {
      final sink = _CapturingSink();
      final interceptor = LoggingInterceptor(sink: sink.call);
      final handler = MockRequestHandler();
      final opts = RequestOptions(
        path: '/api/v1/masters/me/profile',
        baseUrl: 'https://api.beautica.test',
        method: 'PATCH',
        data: {
          'firstName': 'Марія',
          'lastName': 'Бондар',
          'phoneNumber': '+380671234567',
          'bio': 'Перукар-стиліст',
          'instagram': '@masha_style',
          'professionalTitle': '',
        },
      );

      interceptor.onRequest(opts, handler);

      final String logged = sink.only;
      expect(logged, contains('body: [REDACTED]'));
      expect(
        logged,
        isNot(contains('+380671234567')),
        reason: 'the SALON_MASTER phone number must never reach the log',
      );
      expect(
        logged,
        isNot(contains('masha_style')),
        reason: 'the SALON_MASTER Instagram handle must never reach the log',
      );
      expect(
        logged,
        isNot(contains('Бондар')),
        reason: 'the SALON_MASTER surname must never reach the log',
      );

      verify(() => handler.next(any())).called(1);
      // The live request body is never mutated by the logger.
      expect(
        (opts.data as Map<String, dynamic>)['phoneNumber'],
        equals('+380671234567'),
      );
      expect(isPiiPath(opts.path), isTrue);
    });
  });
}

class _MockErrorHandler extends Mock implements ErrorInterceptorHandler {}
