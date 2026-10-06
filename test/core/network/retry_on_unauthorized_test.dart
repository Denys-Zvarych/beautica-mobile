import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/retry_on_unauthorized.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_container.dart';

DioException _dio(int? status, {Object? error}) {
  final ro = RequestOptions(path: '/x');
  return DioException(
    requestOptions: ro,
    error: error,
    response: status == null
        ? null
        : Response<Object?>(requestOptions: ro, statusCode: status),
  );
}

/// [AuthNotifier] stub whose `build()` is supplied per test, so a test can park
/// the provider in loading, error or settled-data.
class _StubAuth extends AuthNotifier {
  _StubAuth(this._build);

  final Future<AuthSession> Function() _build;

  @override
  Future<AuthSession> build() => _build();
}

/// Probe provider so the test can hand `isAuthSessionLive` a real [Ref].
final _liveProbe = Provider<bool>(isAuthSessionLive);

ProviderContainer _containerWith(Future<AuthSession> Function() build) =>
    makeTestContainer(
      overrides: [authProvider.overrideWith(() => _StubAuth(build))],
      retry: (_, _) => null,
    );

void main() {
  group('retryOnceOnUnauthorized', () {
    test('success path runs the action exactly once', () async {
      var calls = 0;
      final result = await retryOnceOnUnauthorized<int>(() async {
        calls++;
        return 7;
      });
      expect(result, 7);
      expect(calls, 1);
    });

    test('retries once on a 401 and returns the second result', () async {
      var calls = 0;
      var retries = 0;
      final result = await retryOnceOnUnauthorized<String>(() async {
        calls++;
        if (calls == 1) throw _dio(401);
        return 'ok';
      }, onRetry: (_) => retries++);
      expect(result, 'ok');
      expect(calls, 2);
      expect(retries, 1);
    });

    test('retries on mapped UnauthorizedFailure without a response', () async {
      var calls = 0;
      final result = await retryOnceOnUnauthorized<int>(() async {
        calls++;
        if (calls == 1) throw _dio(null, error: const UnauthorizedFailure());
        return 1;
      });
      expect(result, 1);
      expect(calls, 2);
    });

    test('rethrows a second 401 after exactly two attempts', () async {
      var calls = 0;
      await expectLater(
        retryOnceOnUnauthorized<int>(() async {
          calls++;
          throw _dio(401);
        }),
        throwsA(isA<DioException>()),
      );
      expect(calls, 2);
    });

    test('does not retry when the session is not live', () async {
      var calls = 0;
      await expectLater(
        retryOnceOnUnauthorized<int>(() async {
          calls++;
          throw _dio(401);
        }, isSessionLive: () => false),
        throwsA(isA<DioException>()),
      );
      expect(calls, 1);
    });

    test('does not retry on non-401 errors', () async {
      for (final status in [400, 403, 500]) {
        var calls = 0;
        await expectLater(
          retryOnceOnUnauthorized<int>(() async {
            calls++;
            throw _dio(status);
          }),
          throwsA(isA<DioException>()),
        );
        expect(calls, 1, reason: 'status $status');
      }
    });

    test('non-Dio exceptions propagate without retry', () async {
      var calls = 0;
      await expectLater(
        retryOnceOnUnauthorized<int>(() async {
          calls++;
          throw StateError('boom');
        }),
        throwsStateError,
      );
      expect(calls, 1);
    });

    test('custom isUnauthorized predicate is honoured', () async {
      var calls = 0;
      await expectLater(
        retryOnceOnUnauthorized<int>(() async {
          calls++;
          throw _dio(401);
        }, isUnauthorized: (_) => false),
        throwsA(isA<DioException>()),
      );
      expect(calls, 1);
    });
  });

  group('isAuthSessionLive', () {
    test('loading auth state is live (true)', () {
      final c = _containerWith(() => Completer<AuthSession>().future);
      expect(c.read(authProvider), isA<AsyncLoading<AuthSession>>());
      expect(c.read(_liveProbe), isTrue);
    });

    test('error auth state is live (true)', () async {
      final c = _containerWith(
        () => Future<AuthSession>.error(StateError('x')),
      );
      await expectLater(c.read(authProvider.future), throwsStateError);
      expect(c.read(authProvider), isA<AsyncError<AuthSession>>());
      expect(c.read(_liveProbe), isTrue);
    });

    test('AsyncData(Authenticated) is live (true)', () async {
      final c = _containerWith(
        () async => const AuthSession.authenticated(
          user: User(id: 'u1', email: 'u@b.c', role: UserRole.client),
          accessToken: 'tkn',
        ),
      );
      await c.read(authProvider.future);
      expect(c.read(authProvider).value, isA<Authenticated>());
      expect(c.read(_liveProbe), isTrue);
    });

    test('AsyncData(Unauthenticated) is NOT live (false)', () async {
      final c = _containerWith(() async => const AuthSession.unauthenticated());
      await c.read(authProvider.future);
      expect(c.read(authProvider).value, isA<Unauthenticated>());
      expect(c.read(_liveProbe), isFalse);
    });
  });
}
