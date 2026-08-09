// Phase 2.7 — Tests for RefreshInterceptor behaviour.
//
// RefreshInterceptor receives a Riverpod [Ref] which is available only inside
// a Riverpod provider context. To obtain a real [Ref] in tests, we create a
// dummy provider that captures its [Ref] and expose it for use in the test.
//
// Covered scenarios:
//   1. 401 → refresh → retry with new Bearer token (exactly one refresh call).
//   2. 401 with X-No-Retry set → no second refresh attempt; handler.next called.
//   3. Multiple concurrent 401s → exactly one /auth/refresh call (single-flight).
//   4. Refresh call throws (network error) → logout() called; handler.next called.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/refresh_dio_provider.dart';
import 'package:beautica_mobile/core/network/refresh_interceptor.dart';
import 'package:beautica_mobile/core/network/token_refresh_lock.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../helpers/fakes/fake_auth_repository.dart';
import '../../helpers/fakes/fake_secure_storage.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

part 'refresh_interceptor_test.g.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockDio extends Mock implements Dio {}

class MockInterceptorHandler extends Mock implements ErrorInterceptorHandler {}

// ---------------------------------------------------------------------------
// Recording lock
//
// A [TokenRefreshLock] subclass that records the object passed to the claimed
// completer's `completeError`. This is the deterministic seam used to assert
// EXACTLY what `_runRefresh` surfaces to concurrent waiters (and rethrows):
// the regression we guard requires it to ALWAYS be a typed [Failure], never a
// raw [TypeError]/[CastError]/[Error] escaping from the cast-based body parse.
//
// The production [claim] creates a `Completer<AuthTokens>` and `_runRefresh`
// calls `completer.completeError(failure, st)` on it. We attach a listener to
// that completer's future so we capture the error object verbatim, with its
// real runtime type intact (the `onError` catch later swallows it).
class _RecordingRefreshLock extends TokenRefreshLock {
  /// The error object the most recent in-flight completer failed with, if any.
  Object? capturedError;

  @override
  Completer<AuthTokens> claim() {
    final completer = super.claim();
    // Observe the terminal error without consuming it for real waiters.
    completer.future.then<void>(
      (_) {},
      onError: (Object e, StackTrace _) => capturedError = e,
    );
    return completer;
  }
}

// ---------------------------------------------------------------------------
// Ref-capture provider
//
// A keepAlive provider whose sole job is to expose its [Ref] so we can pass
// it to [RefreshInterceptor] in tests. In production, [RefreshInterceptor] is
// constructed inside [dioProvider] which already has a real [Ref].
// ---------------------------------------------------------------------------

@Riverpod(keepAlive: true)
Ref testRef(Ref ref) => ref;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

RequestOptions _opts(String path, {Map<String, dynamic>? headers}) =>
    RequestOptions(
      path: path,
      baseUrl: 'https://api.beautica.test',
      headers: headers ?? {},
    );

DioException make401(RequestOptions opts) => DioException(
  requestOptions: opts,
  response: Response(requestOptions: opts, statusCode: 401),
  type: DioExceptionType.badResponse,
);

Map<String, dynamic> refreshEnvelope({
  String access = 'new-access',
  String refresh = 'new-refresh',
}) => {
  'data': {'accessToken': access, 'refreshToken': refresh},
};

ProviderContainer makeContainer({
  required FakeSecureStorage storage,
  required FakeAuthRepository repo,
  required Dio refreshDio,
  TokenRefreshLock? lock,
}) {
  final container = ProviderContainer(
    retry: beauticaProviderRetry,
    overrides: [
      secureStorageProvider.overrideWith((_) => storage),
      authRepositoryProvider.overrideWith((_) => repo),
      refreshDioProvider.overrideWith((_) => refreshDio),
      if (lock != null) tokenRefreshLockProvider.overrideWith((_) => lock),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Stubs the `/auth/refresh` POST to return a 200 with a malformed [body] —
/// the transient empty/mistyped envelope that used to throw a raw
/// `TypeError`/`CastError` from the `as Map`/`as String` casts in `_runRefresh`.
void _stubMalformedRefresh(MockDio refreshDio, Map<String, dynamic>? body) {
  when(
    () => refreshDio.post<Map<String, dynamic>>(
      '/api/v1/auth/refresh',
      data: any(named: 'data'),
    ),
  ).thenAnswer(
    (_) async => Response(
      requestOptions: _opts('/api/v1/auth/refresh'),
      statusCode: 200,
      data: body,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/'));
    registerFallbackValue(
      Response<dynamic>(requestOptions: RequestOptions(path: '/')),
    );
    registerFallbackValue(
      DioException(requestOptions: RequestOptions(path: '/')),
    );
  });

  // -------------------------------------------------------------------------
  // Test 1 — Retry once on 401 with new token
  // -------------------------------------------------------------------------
  test('should retry once on 401 with new access token', () async {
    final storage = FakeSecureStorage();
    await storage.writeRefreshToken('stored-refresh');
    final repo = FakeAuthRepository();
    final refreshDio = MockDio();
    final mainDio = MockDio();

    when(
      () => refreshDio.post<Map<String, dynamic>>(
        '/api/v1/auth/refresh',
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: _opts('/api/v1/auth/refresh'),
        statusCode: 200,
        data: refreshEnvelope(),
      ),
    );

    when(() => mainDio.fetch<dynamic>(any())).thenAnswer(
      (_) async => Response(
        requestOptions: _opts('/protected'),
        statusCode: 200,
        data: 'ok',
      ),
    );

    final container = makeContainer(
      storage: storage,
      repo: repo,
      refreshDio: refreshDio,
    );

    final ref = container.read(testRefProvider);
    // Allow authProvider cold-start to settle (no stored RT → Unauthenticated).
    await container.read(authProvider.future);

    final handler = MockInterceptorHandler();
    final interceptor = RefreshInterceptor(ref, mainDio);

    // M6 (MEDIUM-2): `onError` awaits `(_refreshing ??= _runRefresh()).future`
    // and only then resolves/forwards the handler, so awaiting onError is the
    // interceptor's actual completion signal — no timer sleep needed.
    await interceptor.onError(make401(_opts('/protected')), handler);

    // Exactly one refresh call.
    verify(
      () => refreshDio.post<Map<String, dynamic>>(
        '/api/v1/auth/refresh',
        data: any(named: 'data'),
      ),
    ).called(1);

    // Retry was issued.
    final fetched = verify(() => mainDio.fetch<dynamic>(captureAny())).captured;
    expect(fetched, hasLength(1));

    final retriedOpts = fetched.first as RequestOptions;
    expect(retriedOpts.headers['X-No-Retry'], equals('true'));
    expect(retriedOpts.headers['Authorization'], equals('Bearer new-access'));

    // handler.resolve was called; handler.next must NOT have been called.
    verify(() => handler.resolve(any())).called(1);
    verifyNever(() => handler.next(any()));
  });

  // -------------------------------------------------------------------------
  // Test 2 — X-No-Retry set → no refresh; handler.next called
  // -------------------------------------------------------------------------
  test('should not retry when X-No-Retry is set; calls handler.next', () async {
    final storage = FakeSecureStorage();
    final repo = FakeAuthRepository();
    final refreshDio = MockDio();
    final mainDio = MockDio();

    final container = makeContainer(
      storage: storage,
      repo: repo,
      refreshDio: refreshDio,
    );

    final ref = container.read(testRefProvider);
    final handler = MockInterceptorHandler();
    final interceptor = RefreshInterceptor(ref, mainDio);

    final opts = _opts('/protected', headers: {'X-No-Retry': 'true'});
    await interceptor.onError(make401(opts), handler);

    // handler.next is called; no refresh attempted; handler.resolve not called.
    verify(() => handler.next(any())).called(1);
    verifyNever(() => handler.resolve(any()));
    verifyNever(
      () => refreshDio.post<Map<String, dynamic>>(
        any(),
        data: any(named: 'data'),
      ),
    );
  });

  // -------------------------------------------------------------------------
  // Test 3a — Refresh call fails → logout; handler.next called (not resolve)
  // -------------------------------------------------------------------------
  test(
    'calls logout and handler.next when refresh fails with network error',
    () async {
      final storage = FakeSecureStorage();
      // Write a refresh token so the interceptor attempts the refresh call.
      await storage.writeRefreshToken('stored-refresh');
      final repo = FakeAuthRepository();
      final refreshDio = MockDio();
      final mainDio = MockDio();

      // Stub the refresh call to throw a network-level DioException.
      when(
        () => refreshDio.post<Map<String, dynamic>>(
          '/api/v1/auth/refresh',
          data: any(named: 'data'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: _opts('/api/v1/auth/refresh'),
          type: DioExceptionType.connectionError,
          message: 'Network unreachable',
        ),
      );

      final container = makeContainer(
        storage: storage,
        repo: repo,
        refreshDio: refreshDio,
      );

      final ref = container.read(testRefProvider);
      // Allow authProvider cold-start to settle before running the interceptor.
      await container.read(authProvider.future);

      final handler = MockInterceptorHandler();
      final interceptor = RefreshInterceptor(ref, mainDio);

      // M6 (MEDIUM-2): awaiting onError is deterministic — it awaits the
      // single-flight refresh future and only then calls logout()/handler.next.
      await interceptor.onError(make401(_opts('/protected')), handler);

      // logout() must have been called on the auth notifier.
      expect(repo.logoutCallCount, equals(1));

      // handler.next must be called (not handler.resolve — the request failed).
      verify(() => handler.next(any())).called(1);
      verifyNever(() => handler.resolve(any()));

      // The main Dio should NOT have been asked to retry the request.
      verifyNever(() => mainDio.fetch<dynamic>(any()));
    },
  );

  // -------------------------------------------------------------------------
  // Test 3 — Concurrent 401s → single-flight (exactly one refresh)
  // -------------------------------------------------------------------------
  test('concurrent 401s trigger exactly one refresh call', () async {
    final storage = FakeSecureStorage();
    await storage.writeRefreshToken('stored-refresh');
    final repo = FakeAuthRepository();
    final refreshDio = MockDio();
    final mainDio = MockDio();

    when(
      () => refreshDio.post<Map<String, dynamic>>(
        '/api/v1/auth/refresh',
        data: any(named: 'data'),
      ),
    ).thenAnswer((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return Response(
        requestOptions: _opts('/api/v1/auth/refresh'),
        statusCode: 200,
        data: refreshEnvelope(),
      );
    });

    when(() => mainDio.fetch<dynamic>(any())).thenAnswer(
      (_) async => Response(
        requestOptions: _opts('/protected'),
        statusCode: 200,
        data: 'ok',
      ),
    );

    final container = makeContainer(
      storage: storage,
      repo: repo,
      refreshDio: refreshDio,
    );

    final ref = container.read(testRefProvider);
    // Settle authProvider's cold-start background restore BEFORE running the
    // interceptor. With a stored refresh token present, the background task
    // (build() → _restoreSessionInBackground) writes `state` asynchronously;
    // settling it here keeps that write inside the test rather than racing
    // container disposal at tearDown (which would throw "Ref ... disposed").
    await container.read(authProvider.future);
    final interceptor = RefreshInterceptor(ref, mainDio);

    final handlers = List.generate(3, (_) => MockInterceptorHandler());
    // M6 (MEDIUM-2): Future.wait resolves only after all three onError calls
    // complete — each awaits the shared single-flight Completer — so this is
    // the deterministic completion signal. No trailing timer sleep needed.
    await Future.wait(
      List.generate(
        3,
        (i) => interceptor.onError(make401(_opts('/protected')), handlers[i]),
      ),
    );

    verify(
      () => refreshDio.post<Map<String, dynamic>>(
        '/api/v1/auth/refresh',
        data: any(named: 'data'),
      ),
    ).called(1);
  });

  // -------------------------------------------------------------------------
  // Test 5 — null refresh token path
  // -------------------------------------------------------------------------
  test(
    'null refresh token → UnauthorizedFailure thrown; logout called; handler.next called',
    () async {
      // Storage is empty — no refresh token written.
      final storage = FakeSecureStorage();
      final repo = FakeAuthRepository();
      final refreshDio = MockDio();
      final mainDio = MockDio();

      final container = makeContainer(
        storage: storage,
        repo: repo,
        refreshDio: refreshDio,
      );
      final ref = container.read(testRefProvider);
      await container.read(authProvider.future);

      final handler = MockInterceptorHandler();
      final interceptor = RefreshInterceptor(ref, mainDio);

      // M6 (MEDIUM-2): awaiting onError is deterministic — the null-token path
      // throws inside _runRefresh, the catch awaits logout(), then handler.next.
      await interceptor.onError(make401(_opts('/protected')), handler);

      // logout() must be called (RefreshInterceptor calls
      // _ref.read(authProvider.notifier).logout() on any refresh failure).
      expect(repo.logoutCallCount, equals(1));

      // handler.next must be called (not handler.resolve — the request failed).
      verify(() => handler.next(any())).called(1);
      verifyNever(() => handler.resolve(any()));
      verifyNever(() => mainDio.fetch<dynamic>(any()));
    },
  );

  // -------------------------------------------------------------------------
  // Regression — malformed refresh body must surface a Failure, never a raw
  // TypeError/CastError. (Profile-save flaky errUnknown root cause.)
  //
  // Before the fix, `_runRefresh` parsed the body with
  // `response.data!['data'] as Map` + `as String`. A transient 200 with an
  // empty/mistyped body threw a raw TypeError that escaped _runRefresh,
  // propagated to concurrent waiters via completeError, and bubbled past the
  // repository's `on DioException` arm out to the screen as errUnknown.
  // -------------------------------------------------------------------------
  group('malformed refresh body guard (regression)', () {
    // The malformed shapes that previously triggered raw cast errors.
    final malformedBodies = <String, Map<String, dynamic>?>{
      'null body': null,
      'empty map': <String, dynamic>{},
      'null data': {'data': null},
      'data is not a map (String)': {'data': 'not-a-map'},
      'data missing tokens': {'data': <String, dynamic>{}},
      'tokens are wrong type (int)': {
        'data': {'accessToken': 1, 'refreshToken': 2},
      },
      'empty token strings': {
        'data': {'accessToken': '', 'refreshToken': ''},
      },
    };

    for (final entry in malformedBodies.entries) {
      test(
        '_runRefresh surfaces a Failure (not a raw Error) for ${entry.key}',
        () async {
          final storage = FakeSecureStorage();
          await storage.writeRefreshToken('stored-refresh');
          final repo = FakeAuthRepository();
          final refreshDio = MockDio();
          final mainDio = MockDio();
          final lock = _RecordingRefreshLock();

          _stubMalformedRefresh(refreshDio, entry.value);

          final container = makeContainer(
            storage: storage,
            repo: repo,
            refreshDio: refreshDio,
            lock: lock,
          );
          final ref = container.read(testRefProvider);
          await container.read(authProvider.future);

          final handler = MockInterceptorHandler();
          final interceptor = RefreshInterceptor(ref, mainDio);

          await interceptor.onError(make401(_opts('/protected')), handler);

          // The error the in-flight completer failed with — i.e. exactly what
          // `_runRefresh` rethrew and what a concurrent waiter would receive.
          final captured = lock.capturedError;
          expect(
            captured,
            isNotNull,
            reason: 'the refresh must fail on a malformed body',
          );
          expect(
            captured,
            isA<Failure>(),
            reason: 'a malformed refresh body must surface a typed Failure',
          );
          expect(
            captured,
            isA<UnauthorizedFailure>(),
            reason: 'malformed refresh body is treated as an auth failure',
          );
          // The crux of the regression: NEVER a raw runtime Error/TypeError.
          expect(
            captured,
            isNot(isA<Error>()),
            reason: 'a raw TypeError/CastError must never escape _runRefresh',
          );
          expect(captured, isNot(isA<TypeError>()));

          // Behavioural guarantee: the failed refresh logs the user out and
          // forwards the original error (never resolves the request).
          expect(repo.logoutCallCount, equals(1));
          verify(() => handler.next(any())).called(1);
          verifyNever(() => handler.resolve(any()));
          verifyNever(() => mainDio.fetch<dynamic>(any()));
        },
      );
    }

    test(
      'concurrent waiter on malformed refresh receives a Failure, not a raw error',
      () async {
        final storage = FakeSecureStorage();
        await storage.writeRefreshToken('stored-refresh');
        final repo = FakeAuthRepository();
        final refreshDio = MockDio();
        final mainDio = MockDio();
        final lock = _RecordingRefreshLock();

        // Delay so the second onError arrives while the first holds the lock
        // and is awaiting the (malformed) refresh response — exercising the
        // `lock.pending != null` concurrent-waiter branch in onError.
        when(
          () => refreshDio.post<Map<String, dynamic>>(
            '/api/v1/auth/refresh',
            data: any(named: 'data'),
          ),
        ).thenAnswer((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return Response(
            requestOptions: _opts('/api/v1/auth/refresh'),
            statusCode: 200,
            // Malformed: empty envelope → typed UnauthorizedFailure.
            data: const <String, dynamic>{},
          );
        });

        final container = makeContainer(
          storage: storage,
          repo: repo,
          refreshDio: refreshDio,
          lock: lock,
        );
        final ref = container.read(testRefProvider);
        await container.read(authProvider.future);

        final interceptor = RefreshInterceptor(ref, mainDio);
        final handlers = List.generate(2, (_) => MockInterceptorHandler());

        // Both onError calls await the single shared completer. The waiter
        // (handler[1]) receives the SAME terminal error as the claimant.
        await Future.wait(
          List.generate(
            2,
            (i) =>
                interceptor.onError(make401(_opts('/protected')), handlers[i]),
          ),
        );

        // Exactly one refresh issued (single-flight preserved).
        verify(
          () => refreshDio.post<Map<String, dynamic>>(
            '/api/v1/auth/refresh',
            data: any(named: 'data'),
          ),
        ).called(1);

        // The error shared with the concurrent waiter is a typed Failure.
        expect(lock.capturedError, isA<UnauthorizedFailure>());
        expect(
          lock.capturedError,
          isNot(isA<Error>()),
          reason:
              'concurrent waiter must never receive a raw TypeError/CastError',
        );
      },
    );
  });
}
