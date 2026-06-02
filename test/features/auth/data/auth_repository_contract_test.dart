// Contract-drift regression net (2026-06-02) — auth login + token refresh.
//
// WHY THIS FILE EXISTS
// --------------------
// http_auth_repository_test.dart mocks the *generated* AuthControllerApi, so the
// real request body, path/verb resolution, built_value deserialization, AND the
// production ErrorMapperInterceptor status→Failure mapping never run. The auth
// surface is exactly where contract drift is most dangerous: a misparsed login
// envelope or a 401 that maps to the wrong Failure means a user cannot sign in,
// or sees the wrong recovery affordance.
//
// HERE the only fake is the HTTP socket (http_mock_adapter). On top of it run:
//   • a REAL Dio carrying the production ErrorMapperInterceptor;
//   • the REAL generated AuthControllerApi/UserControllerApi + standardSerializers;
//   • the REAL HttpAuthRepository (with a real TokenRefreshLock).
//
// POSITIVE: success envelope → parsed (User, AuthTokens).
// NEGATIVE: every realistic auth failure → the CORRECT typed Failure, with the
// auth-specific remaps (401 plain → InvalidCredentialsFailure; 401
// EMAIL_NOT_VERIFIED → UnauthorizedFailure with the flag set so the login banner
// branches correctly).
//
// Runs headless in CI:
//   flutter test test/features/auth/data/auth_repository_contract_test.dart

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/error_mapper_interceptor.dart';
import 'package:beautica_mobile/core/network/token_refresh_lock.dart';
import 'package:beautica_mobile/features/auth/data/http_auth_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

const _baseUrl = 'http://localhost:8080';
const _loginPath = '/api/v1/auth/login';
const _refreshPath = '/api/v1/auth/refresh';
const _mePath = '/api/v1/users/me';

Map<String, dynamic> _authEnvelope({
  String accessToken = 'access-1',
  String refreshToken = 'refresh-1',
}) => <String, dynamic>{
  'success': true,
  'message': 'ok',
  'data': <String, dynamic>{
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'tokenType': 'Bearer',
    'userId': 'user-1',
    'email': 'master@beautica.ua',
    'role': 'INDEPENDENT_MASTER',
  },
};

({Dio dio, DioAdapter adapter, HttpAuthRepository repo}) _wire() {
  final dio = Dio(
    BaseOptions(
      baseUrl: _baseUrl,
      headers: const <String, dynamic>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ),
  );
  dio.interceptors.add(ErrorMapperInterceptor());
  final adapter = DioAdapter(dio: dio);
  final repo = HttpAuthRepository(
    AuthControllerApi(dio, standardSerializers),
    UserControllerApi(dio, standardSerializers),
    TokenRefreshLock(),
  );
  return (dio: dio, adapter: adapter, repo: repo);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  // login
  // =========================================================================
  group('login — full transport contract', () {
    test(
      'POSITIVE: 200 envelope → (User, AuthTokens) parsed correctly',
      () async {
        final h = _wire();
        h.adapter.onPost(
          _loginPath,
          (s) => s.reply(200, _authEnvelope()),
          data: Matchers.any,
        );

        final (user, tokens) = await h.repo.login(
          email: 'master@beautica.ua',
          password: 'pw',
        );

        expect(user.id, 'user-1');
        expect(user.email, 'master@beautica.ua');
        expect(tokens.accessToken, 'access-1');
        expect(tokens.refreshToken, 'refresh-1');
      },
    );

    test('POSITIVE: real wire body carries email + password', () async {
      final h = _wire();
      Map<String, dynamic>? sentBody;
      h.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, handler) {
            if (o.method == 'POST' && o.path.endsWith('/auth/login')) {
              sentBody = o.data as Map<String, dynamic>?;
            }
            handler.next(o);
          },
        ),
      );
      h.adapter.onPost(
        _loginPath,
        (s) => s.reply(200, _authEnvelope()),
        data: Matchers.any,
      );

      await h.repo.login(email: 'master@beautica.ua', password: 'secret');

      expect(sentBody, isNotNull);
      expect(sentBody!['email'], 'master@beautica.ua');
      expect(sentBody!['password'], 'secret');
    });

    test('NEGATIVE: 401 plain → InvalidCredentialsFailure (auth remap, NOT a '
        'bare UnauthorizedFailure)', () async {
      final h = _wire();
      h.adapter.onPost(
        _loginPath,
        (s) => s.reply(401, {'success': false, 'message': 'Bad credentials'}),
        data: Matchers.any,
      );

      await expectLater(
        h.repo.login(email: 'master@beautica.ua', password: 'wrong'),
        throwsA(isA<InvalidCredentialsFailure>()),
      );
    });

    test('NEGATIVE: 401 EMAIL_NOT_VERIFIED → UnauthorizedFailure with '
        'emailNotVerified flag (login banner branch)', () async {
      final h = _wire();
      h.adapter.onPost(
        _loginPath,
        (s) => s.reply(401, {
          'success': false,
          'data': {'code': 'EMAIL_NOT_VERIFIED'},
          'message': 'EMAIL_NOT_VERIFIED',
        }),
        data: Matchers.any,
      );

      await expectLater(
        h.repo.login(email: 'master@beautica.ua', password: 'pw'),
        throwsA(
          isA<UnauthorizedFailure>().having(
            (f) => f.emailNotVerified,
            'emailNotVerified',
            isTrue,
          ),
        ),
      );
    });

    test('NEGATIVE: 400 field errors → ValidationFailure', () async {
      final h = _wire();
      h.adapter.onPost(
        _loginPath,
        (s) => s.reply(400, {
          'success': false,
          'errors': {'email': 'must be a valid email'},
        }),
        data: Matchers.any,
      );

      await expectLater(
        h.repo.login(email: 'bad', password: 'pw'),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('NEGATIVE: 500 → ServerFailure(500)', () async {
      final h = _wire();
      h.adapter.onPost(
        _loginPath,
        (s) => s.reply(500, {'message': 'boom'}),
        data: Matchers.any,
      );

      await expectLater(
        h.repo.login(email: 'master@beautica.ua', password: 'pw'),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('NEGATIVE: connection timeout → NetworkFailure', () async {
      final h = _wire();
      h.adapter.onPost(
        _loginPath,
        (s) => s.throws(
          408,
          DioException.connectionTimeout(
            timeout: const Duration(seconds: 1),
            requestOptions: RequestOptions(path: _loginPath),
          ),
        ),
        data: Matchers.any,
      );

      await expectLater(
        h.repo.login(email: 'master@beautica.ua', password: 'pw'),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('NEGATIVE: 200 but unexpected JSON shape (missing data) → throws '
        '(never returns a half-built session)', () async {
      final h = _wire();
      h.adapter.onPost(
        _loginPath,
        (s) => s.reply(200, {'success': true, 'message': 'ok', 'data': null}),
        data: Matchers.any,
      );

      // res.data!.data! on a null payload throws — the repository must surface a
      // failure rather than fabricate an empty AuthSession.
      await expectLater(
        h.repo.login(email: 'master@beautica.ua', password: 'pw'),
        throwsA(anything),
      );
    });
  });

  // =========================================================================
  // refresh — token rotation contract
  // =========================================================================
  group('refresh — full transport contract', () {
    test('POSITIVE: 200 → new AuthTokens pair parsed', () async {
      final h = _wire();
      h.adapter.onPost(
        _refreshPath,
        (s) => s.reply(
          200,
          _authEnvelope(accessToken: 'access-2', refreshToken: 'refresh-2'),
        ),
        data: Matchers.any,
      );

      final tokens = await h.repo.refresh('refresh-1');

      expect(tokens.accessToken, 'access-2');
      expect(tokens.refreshToken, 'refresh-2');
    });

    test('POSITIVE: X-No-Retry header is set on the refresh request '
        '(prevents the double-refresh loop)', () async {
      final h = _wire();
      String? noRetry;
      h.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, handler) {
            if (o.path.endsWith('/auth/refresh')) {
              noRetry = o.headers['X-No-Retry']?.toString();
            }
            handler.next(o);
          },
        ),
      );
      h.adapter.onPost(
        _refreshPath,
        (s) =>
            s.reply(200, _authEnvelope(accessToken: 'a2', refreshToken: 'r2')),
        data: Matchers.any,
      );

      await h.repo.refresh('refresh-1');

      expect(noRetry, 'true', reason: 'refresh must send X-No-Retry: true');
    });

    test(
      'NEGATIVE: 401 (refresh token expired/revoked) → UnauthorizedFailure',
      () async {
        final h = _wire();
        h.adapter.onPost(
          _refreshPath,
          (s) => s.reply(401, {'success': false, 'message': 'expired'}),
          data: Matchers.any,
        );

        await expectLater(
          h.repo.refresh('stale-token'),
          throwsA(isA<UnauthorizedFailure>()),
        );
      },
    );

    test('NEGATIVE: 500 during refresh → ServerFailure(500)', () async {
      final h = _wire();
      h.adapter.onPost(
        _refreshPath,
        (s) => s.reply(500, {'message': 'boom'}),
        data: Matchers.any,
      );

      await expectLater(
        h.repo.refresh('refresh-1'),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('NEGATIVE: refresh failure releases the single-flight lock so a later '
        'refresh can proceed (no permanent deadlock)', () async {
      final h = _wire();
      // First refresh → 401. If the lock were not released on failure, a later
      // refresh would await a dead completer and hang forever.
      h.adapter.onPost(
        _refreshPath,
        (s) => s.reply(401, {'message': 'expired'}),
        data: Matchers.any,
      );

      await expectLater(
        h.repo.refresh('stale'),
        throwsA(isA<UnauthorizedFailure>()),
      );

      // Same repository instance (same TokenRefreshLock), socket now succeeds —
      // the second refresh must complete, proving the lock was released.
      h.adapter.onPost(
        _refreshPath,
        (s) =>
            s.reply(200, _authEnvelope(accessToken: 'a3', refreshToken: 'r3')),
        data: Matchers.any,
      );
      final tokens = await h.repo.refresh('fresh');
      expect(tokens.accessToken, 'a3');
    });
  });

  // =========================================================================
  // me — session bootstrap parses the profile envelope
  // =========================================================================
  group('me — full transport contract', () {
    test('POSITIVE: 200 → User with first/last name', () async {
      final h = _wire();
      h.adapter.onGet(
        _mePath,
        (s) => s.reply(200, {
          'success': true,
          'message': 'ok',
          'data': {
            'id': 'user-1',
            'email': 'master@beautica.ua',
            'role': 'INDEPENDENT_MASTER',
            'firstName': 'Олена',
            'lastName': 'Ковальчук',
          },
        }),
      );

      final user = await h.repo.me();

      expect(user.id, 'user-1');
      expect(user.firstName, 'Олена');
      expect(user.lastName, 'Ковальчук');
    });

    test('NEGATIVE: 401 on /users/me → UnauthorizedFailure', () async {
      final h = _wire();
      h.adapter.onGet(_mePath, (s) => s.reply(401, {'message': 'unauth'}));

      await expectLater(h.repo.me(), throwsA(isA<UnauthorizedFailure>()));
    });

    test('NEGATIVE: network error on /users/me → NetworkFailure', () async {
      final h = _wire();
      h.adapter.onGet(
        _mePath,
        (s) => s.throws(
          0,
          DioException.connectionError(
            requestOptions: RequestOptions(path: _mePath),
            reason: 'socket closed',
          ),
        ),
      );

      await expectLater(h.repo.me(), throwsA(isA<NetworkFailure>()));
    });
  });
}
