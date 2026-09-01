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
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

const _baseUrl = 'http://localhost:8080';
const _loginPath = '/api/v1/auth/login';
const _refreshPath = '/api/v1/auth/refresh';
const _mePath = '/api/v1/users/me';
const _verifyEmailPath = '/api/v1/auth/verify-email';
const _acceptInvitePath = '/api/v1/auth/invite/accept';
// The path the generated client produces when AppConfig.baseUrl carries an
// accidental trailing `/api/v1` (the live silent-error cause, fixed in 70e569b).
// `requestOptions.path` then doubles to this form. A literal-equality check
// (`path == '/api/v1/auth/verify-email'`) silently misses it and degrades the
// typed VerificationFailure to a generic ValidationFailure → silent submit.
const _verifyEmailDriftPath = '/api/v1/api/v1/auth/verify-email';

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

// invite-accept post-success failure design (2026-09-01) — the 'acceptInvite
// — full transport contract' group below drives the mapping BLOCK inside
// HttpAuthRepository.acceptInvite through the REAL generated AuthResponse
// deserializer, which the mocktail-on-AuthControllerApi coverage in
// auth_notifier_test.dart never touches. A malformed/null-field envelope
// must surface as a typed [ResponseUnusableFailure], never a raw
// TypeError/NoSuchMethodError escaping unmapped.
Map<String, dynamic> _acceptInviteEnvelope({
  String? accessToken = 'access-1',
  String? refreshToken = 'refresh-1',
  String? userId = 'user-1',
  String email = 'admin@salon.ua',
  String? role = 'SALON_ADMIN',
  String? salonId = 'salon-1',
}) => <String, dynamic>{
  'success': true,
  'message': 'ok',
  'data': <String, dynamic>{
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'tokenType': 'Bearer',
    'userId': userId,
    'email': email,
    'role': role,
    'salonId': salonId,
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
  // acceptInvite — invite-accept transport contract + the invite-accept
  // post-success failure design's regression net (2026-09-01).
  //
  // Same coverage gap as verifyEmail below, on the endpoint that shipped the
  // reported incident: the mocktail-on-AuthControllerApi coverage in
  // auth_notifier_test.dart never exercises real JSON (de)serialization, so
  // a malformed 201 body (a null field the mapper assumes non-null) never
  // ran through the REAL mapping block. This is exactly the defect class the
  // point-of-no-return design exists to convert into a typed
  // ResponseUnusableFailure instead of a raw, unmapped TypeError.
  // =========================================================================
  group('acceptInvite — full transport contract', () {
    test(
      'POSITIVE 1: 201 SALON_ADMIN envelope WITH salonId → (User, AuthTokens) '
      'parsed, user.role == UserRole.salonAdmin',
      () async {
        final h = _wire();
        h.adapter.onPost(
          _acceptInvitePath,
          (s) => s.reply(201, _acceptInviteEnvelope()),
          data: Matchers.any,
        );

        final (user, tokens) = await h.repo.acceptInvite(
          token: 'invite-abc',
          password: 'SecurePass1',
          firstName: 'Іван',
          lastName: 'Коваль',
          phoneNumber: '+380501234567',
        );

        expect(user.id, 'user-1');
        expect(user.email, 'admin@salon.ua');
        expect(user.role, UserRole.salonAdmin);
        expect(tokens.accessToken, 'access-1');
        expect(tokens.refreshToken, 'refresh-1');
      },
    );

    test('POSITIVE 2: 201 SALON_MASTER envelope → parsed, no throw', () async {
      final h = _wire();
      h.adapter.onPost(
        _acceptInvitePath,
        (s) => s.reply(
          201,
          _acceptInviteEnvelope(role: 'SALON_MASTER', salonId: 'salon-2'),
        ),
        data: Matchers.any,
      );

      final (user, tokens) = await h.repo.acceptInvite(
        token: 'invite-xyz',
        password: 'SecurePass1',
        firstName: 'Олена',
        lastName: 'Шевченко',
        phoneNumber: '+380671234567',
      );

      expect(user.role, UserRole.salonMaster);
      expect(tokens.accessToken, 'access-1');
    });

    test('NEGATIVE 3a: 201 with data.role null → ResponseUnusableFailure, '
        'never a raw TypeError/NoSuchMethodError', () async {
      final h = _wire();
      h.adapter.onPost(
        _acceptInvitePath,
        (s) => s.reply(201, _acceptInviteEnvelope(role: null)),
        data: Matchers.any,
      );

      await expectLater(
        h.repo.acceptInvite(
          token: 't',
          password: 'p',
          firstName: 'f',
          lastName: 'l',
        ),
        throwsA(isA<ResponseUnusableFailure>()),
      );
    });

    test(
      'NEGATIVE 3b: 201 with data.userId null → ResponseUnusableFailure',
      () async {
        final h = _wire();
        h.adapter.onPost(
          _acceptInvitePath,
          (s) => s.reply(201, _acceptInviteEnvelope(userId: null)),
          data: Matchers.any,
        );

        await expectLater(
          h.repo.acceptInvite(
            token: 't',
            password: 'p',
            firstName: 'f',
            lastName: 'l',
          ),
          throwsA(isA<ResponseUnusableFailure>()),
        );
      },
    );

    test(
      'NEGATIVE 3c: 201 with data.accessToken null → ResponseUnusableFailure',
      () async {
        final h = _wire();
        h.adapter.onPost(
          _acceptInvitePath,
          (s) => s.reply(201, _acceptInviteEnvelope(accessToken: null)),
          data: Matchers.any,
        );

        await expectLater(
          h.repo.acceptInvite(
            token: 't',
            password: 'p',
            firstName: 'f',
            lastName: 'l',
          ),
          throwsA(isA<ResponseUnusableFailure>()),
        );
      },
    );

    test(
      'NEGATIVE 4: 400 {success:false,data:null,message:"Invalid request"} → '
      'ValidationFailure with fieldErrors.isEmpty (invite already used/'
      'expired/not found — the AuthNotifier hand-off classifier keys on '
      'this exact shape)',
      () async {
        final h = _wire();
        h.adapter.onPost(
          _acceptInvitePath,
          (s) => s.reply(400, {
            'success': false,
            'data': null,
            'message': 'Invalid request',
          }),
          data: Matchers.any,
        );

        await expectLater(
          h.repo.acceptInvite(
            token: 'spent-token',
            password: 'p',
            firstName: 'f',
            lastName: 'l',
          ),
          throwsA(
            isA<ValidationFailure>().having(
              (f) => f.fieldErrors.isEmpty,
              'fieldErrors.isEmpty',
              isTrue,
            ),
          ),
        );
      },
    );

    test('NEGATIVE 5: 400 WITH a populated errors map → ValidationFailure with '
        'fieldErrors.isNotEmpty (proves the two 400 shapes stay '
        'distinguishable — this one must NOT hand off to /login)', () async {
      final h = _wire();
      h.adapter.onPost(
        _acceptInvitePath,
        (s) => s.reply(400, {
          'success': false,
          'errors': {'phoneNumber': 'must not be blank'},
        }),
        data: Matchers.any,
      );

      await expectLater(
        h.repo.acceptInvite(
          token: 't',
          password: 'p',
          firstName: 'f',
          lastName: 'l',
        ),
        throwsA(
          isA<ValidationFailure>().having(
            (f) => f.fieldErrors.isNotEmpty,
            'fieldErrors.isNotEmpty',
            isTrue,
          ),
        ),
      );
    });

    test(
      'NEGATIVE 6: 409 body without data.code → ServerFailure(statusCode: 409) '
      '(the emailAlreadyRegistered hand-off classifier keys on this shape)',
      () async {
        final h = _wire();
        h.adapter.onPost(
          _acceptInvitePath,
          (s) => s.reply(409, {
            'success': false,
            'message': 'Email is already registered',
          }),
          data: Matchers.any,
        );

        await expectLater(
          h.repo.acceptInvite(
            token: 't',
            password: 'p',
            firstName: 'f',
            lastName: 'l',
          ),
          throwsA(
            isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 409),
          ),
        );
      },
    );
  });

  // =========================================================================
  // verifyEmail — OTP transport contract + the silent-error regression net.
  //
  // These guards drive the REAL HttpAuthRepository.verifyEmail through the REAL
  // ErrorMapperInterceptor over a faked socket. The 400 typed-code envelope must
  // resolve to a VerificationFailure with the correct VerificationErrorCode — a
  // misresolution (e.g. a generic ValidationFailure) is exactly what produced
  // the invalid-OTP "no error shown" bug (fixed 2026-06-02).
  // =========================================================================
  group('verifyEmail — full transport contract', () {
    test(
      'POSITIVE: 200 envelope → (User, AuthTokens) parsed correctly',
      () async {
        final h = _wire();
        h.adapter.onPost(
          _verifyEmailPath,
          (s) => s.reply(200, _authEnvelope()),
          data: Matchers.any,
        );

        final (user, tokens) = await h.repo.verifyEmail(
          email: 'master@beautica.ua',
          otp: '123456',
        );

        expect(user.id, 'user-1');
        expect(user.email, 'master@beautica.ua');
        expect(tokens.accessToken, 'access-1');
        expect(tokens.refreshToken, 'refresh-1');
      },
    );

    test('POSITIVE: real wire request hits a path ending /auth/verify-email '
        'and carries email + code (guards the endsWith match)', () async {
      final h = _wire();
      String? sentPath;
      Map<String, dynamic>? sentBody;
      h.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, handler) {
            if (o.method == 'POST' && o.path.endsWith('/auth/verify-email')) {
              sentPath = o.path;
              sentBody = o.data as Map<String, dynamic>?;
            }
            handler.next(o);
          },
        ),
      );
      h.adapter.onPost(
        _verifyEmailPath,
        (s) => s.reply(200, _authEnvelope()),
        data: Matchers.any,
      );

      await h.repo.verifyEmail(email: 'master@beautica.ua', otp: '654321');

      expect(sentPath, isNotNull);
      expect(
        sentPath!.endsWith('/auth/verify-email'),
        isTrue,
        reason:
            'verifyEmail must POST to a path ending /auth/verify-email so the '
            'interceptor endsWith() match fires regardless of baseUrl prefix.',
      );
      expect(sentBody, isNotNull);
      expect(sentBody!['email'], 'master@beautica.ua');
      // Wire field is `code`, not `otp` (backend Phase 1.5 contract).
      expect(sentBody!['code'], '654321');
    });

    test(
      'NEGATIVE (LIVE-SYMPTOM REGRESSION GUARD): 400 INVALID_CODE → '
      'VerificationFailure(invalidCode), NOT a generic ValidationFailure',
      () async {
        final h = _wire();
        h.adapter.onPost(
          _verifyEmailPath,
          (s) => s.reply(400, {
            'success': false,
            'data': {'code': 'INVALID_CODE'},
            'message': 'Verification failed',
          }),
          data: Matchers.any,
        );

        await expectLater(
          h.repo.verifyEmail(email: 'master@beautica.ua', otp: '000000'),
          throwsA(
            isA<VerificationFailure>().having(
              (f) => f.code,
              'code',
              VerificationErrorCode.invalidCode,
            ),
          ),
          reason:
              'A 400 with data.code=INVALID_CODE must map to VerificationFailure '
              'so the screen renders the OTP error. If the interceptor path match '
              'misses, this degrades to ValidationFailure and the user sees no '
              'error (the live silent-submit bug).',
        );
      },
    );

    test(
      'NEGATIVE: 400 CODE_EXPIRED → VerificationFailure(codeExpired)',
      () async {
        final h = _wire();
        h.adapter.onPost(
          _verifyEmailPath,
          (s) => s.reply(400, {
            'success': false,
            'data': {'code': 'CODE_EXPIRED'},
            'message': 'Verification failed',
          }),
          data: Matchers.any,
        );

        await expectLater(
          h.repo.verifyEmail(email: 'master@beautica.ua', otp: '000000'),
          throwsA(
            isA<VerificationFailure>().having(
              (f) => f.code,
              'code',
              VerificationErrorCode.codeExpired,
            ),
          ),
        );
      },
    );

    test(
      'NEGATIVE: 400 ALREADY_VERIFIED → VerificationFailure(alreadyVerified)',
      () async {
        final h = _wire();
        h.adapter.onPost(
          _verifyEmailPath,
          (s) => s.reply(400, {
            'success': false,
            'data': {'code': 'ALREADY_VERIFIED'},
            'message': 'Verification failed',
          }),
          data: Matchers.any,
        );

        await expectLater(
          h.repo.verifyEmail(email: 'master@beautica.ua', otp: '000000'),
          throwsA(
            isA<VerificationFailure>().having(
              (f) => f.code,
              'code',
              VerificationErrorCode.alreadyVerified,
            ),
          ),
        );
      },
    );

    test('NEGATIVE (BASE-URL PREFIX-DRIFT GUARD): a 400 INVALID_CODE on the '
        'DOUBLED path /api/v1/api/v1/auth/verify-email STILL maps to '
        'VerificationFailure — kills the literal `path ==` mutation', () async {
      final h = _wire();
      // Simulate the live BEAUTICA_BASE_URL `/api/v1` prefix drift at the
      // requestOptions.path level: the generated `/api/v1/auth/verify-email`
      // gets doubled. A hardcoded `path == '/api/v1/auth/verify-email'` check
      // misses this; `path.endsWith('/auth/verify-email')` still matches.
      h.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, handler) {
            if (o.path == _verifyEmailPath) {
              o.path = _verifyEmailDriftPath;
            }
            handler.next(o);
          },
        ),
      );
      h.adapter.onPost(
        _verifyEmailDriftPath,
        (s) => s.reply(400, {
          'success': false,
          'data': {'code': 'INVALID_CODE'},
          'message': 'Verification failed',
        }),
        data: Matchers.any,
      );

      await expectLater(
        h.repo.verifyEmail(email: 'master@beautica.ua', otp: '000000'),
        throwsA(
          isA<VerificationFailure>().having(
            (f) => f.code,
            'code',
            VerificationErrorCode.invalidCode,
          ),
        ),
        reason:
            'Under /api/v1 prefix drift the request path doubles; the typed '
            'VerificationFailure mapping must survive via endsWith(). A literal '
            'equality check fails here → generic ValidationFailure → silent '
            'submit. This is the contract guard for the Part-A fix.',
      );
    });

    test('NEGATIVE: 500 during verifyEmail → ServerFailure(500)', () async {
      final h = _wire();
      h.adapter.onPost(
        _verifyEmailPath,
        (s) => s.reply(500, {'message': 'boom'}),
        data: Matchers.any,
      );

      await expectLater(
        h.repo.verifyEmail(email: 'master@beautica.ua', otp: '000000'),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 500),
        ),
      );
    });

    // -----------------------------------------------------------------------
    // Invite-accept post-success failure design (2026-09-01), Q4: the same
    // ResponseUnusableFailure mapping wrap was generalised to verifyEmail's
    // mapping block. Same null-field regression as acceptInvite's 3a/3b/3c —
    // a malformed 200 body must throw a typed Failure, never a raw
    // TypeError/NoSuchMethodError.
    // -----------------------------------------------------------------------
    test('NEGATIVE: 200 with data.role null → ResponseUnusableFailure, never a '
        'raw TypeError/NoSuchMethodError', () async {
      final h = _wire();
      h.adapter.onPost(
        _verifyEmailPath,
        (s) => s.reply(200, {
          'success': true,
          'message': 'ok',
          'data': {
            'accessToken': 'access-1',
            'refreshToken': 'refresh-1',
            'tokenType': 'Bearer',
            'userId': 'user-1',
            'email': 'master@beautica.ua',
            'role': null,
          },
        }),
        data: Matchers.any,
      );

      await expectLater(
        h.repo.verifyEmail(email: 'master@beautica.ua', otp: '123456'),
        throwsA(isA<ResponseUnusableFailure>()),
      );
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
