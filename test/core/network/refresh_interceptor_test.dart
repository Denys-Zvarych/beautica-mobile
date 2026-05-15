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

import 'package:beautica_mobile/core/network/refresh_dio_provider.dart';
import 'package:beautica_mobile/core/network/refresh_interceptor.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../helpers/fakes/fake_auth_repository.dart';
import '../../helpers/fakes/fake_secure_storage.dart';

part 'refresh_interceptor_test.g.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockDio extends Mock implements Dio {}

class MockInterceptorHandler extends Mock implements ErrorInterceptorHandler {}

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
}) {
  final container = ProviderContainer(
    overrides: [
      secureStorageProvider.overrideWith((_) => storage),
      authRepositoryProvider.overrideWith((_) => repo),
      refreshDioProvider.overrideWith((_) => refreshDio),
    ],
  );
  addTearDown(container.dispose);
  return container;
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
        '/auth/refresh',
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: _opts('/auth/refresh'),
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

    await interceptor.onError(make401(_opts('/protected')), handler);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // Exactly one refresh call.
    verify(
      () => refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
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
          '/auth/refresh',
          data: any(named: 'data'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: _opts('/auth/refresh'),
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

      await interceptor.onError(make401(_opts('/protected')), handler);
      await Future<void>.delayed(const Duration(milliseconds: 200));

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
        '/auth/refresh',
        data: any(named: 'data'),
      ),
    ).thenAnswer((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return Response(
        requestOptions: _opts('/auth/refresh'),
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
    final interceptor = RefreshInterceptor(ref, mainDio);

    final handlers = List.generate(3, (_) => MockInterceptorHandler());
    await Future.wait(
      List.generate(
        3,
        (i) => interceptor.onError(make401(_opts('/protected')), handlers[i]),
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 300));

    verify(
      () => refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: any(named: 'data'),
      ),
    ).called(1);
  });
}
