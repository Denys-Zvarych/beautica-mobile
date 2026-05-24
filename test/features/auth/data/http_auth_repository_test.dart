// Phase 2.3 — HttpAuthRepository unit tests.
//
// Uses `mocktail` to mock [Dio] at the call-site level. Each test verifies
// one method + scenario from the contract table in the task spec.
//
// Test structure:
//   Group 1 — login
//     1. success → returns (User, AuthTokens) with correct values
//     2. 401 DioException (error = UnauthorizedFailure) → re-throws
//     3. 400 DioException (error = ValidationFailure with fieldErrors) → re-throws
//     4. raw DioException (error = null) → throws UnknownFailure
//   Group 2 — registerIndependentMaster
//     5. success (independentMaster) → hits /auth/register/independent-master
//     11. success (salonOwner) → hits /auth/register/salon-owner
//     12. success (client) → hits /auth/register/client
//   Group 3 — refresh
//     6. success → returns AuthTokens with new token pair
//   Group 4 — me
//     7. success → returns User with correct role
//     8. 401 DioException → re-throws UnauthorizedFailure

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/data/http_auth_repository.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/domain/register_result.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fakes/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockDio extends Mock implements Dio {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a minimal [RequestOptions] instance for use in [DioException]s.
RequestOptions _fakeOptions(String path) =>
    RequestOptions(path: path, baseUrl: 'https://api.beautica.test');

/// Wraps [failure] in a [DioException] the way [ErrorMapperInterceptor] would.
DioException _dioWithFailure(Failure failure, {int statusCode = 400}) =>
    DioException(
      requestOptions: _fakeOptions('/test'),
      response: Response(
        requestOptions: _fakeOptions('/test'),
        statusCode: statusCode,
      ),
      type: DioExceptionType.badResponse,
      error: failure,
    );

/// Returns a [DioException] with no attached [Failure] (unmapped error).
DioException _rawDioException() => DioException(
  requestOptions: _fakeOptions('/test'),
  type: DioExceptionType.unknown,
);

/// Fixture backend envelope for a login / register response.
///
/// Shape mirrors the flat [AuthResponse] the backend serialises:
///   { userId, email, role, accessToken, refreshToken, tokenType }
/// There is no nested `user` object — the session data is at the top level
/// of `data`.
Map<String, dynamic> _loginEnvelope({
  String userId = 'usr-1',
  String role = 'INDEPENDENT_MASTER',
}) => {
  'success': true,
  'message': 'OK',
  'data': {
    'userId': userId,
    'email': 'master@beautica.test',
    'role': role,
    'accessToken': 'access.jwt.token',
    'refreshToken': 'refresh.jwt.token',
    'tokenType': 'Bearer',
  },
};

/// Fixture backend envelope for a refresh response.
Map<String, dynamic> _refreshEnvelope() => {
  'success': true,
  'message': 'OK',
  'data': {
    'accessToken': 'new.access.token',
    'refreshToken': 'new.refresh.token',
  },
};

/// Fixture backend envelope for a me response.
Map<String, dynamic> _meEnvelope({String role = 'INDEPENDENT_MASTER'}) => {
  'success': true,
  'message': 'OK',
  'data': {
    'id': 'usr-1',
    'email': 'master@beautica.test',
    'role': role,
    'firstName': 'Іванна',
    'lastName': 'Коваль',
  },
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockDio mockDio;
  late HttpAuthRepository repository;

  setUp(() {
    mockDio = MockDio();
    // Phase 2.8: HttpAuthRepository now requires SecureStorage for logout().
    // FakeSecureStorage is used here — no platform channels needed.
    repository = HttpAuthRepository(mockDio, FakeSecureStorage());

    // Default fallback for Options — mocktail needs this registered.
    registerFallbackValue(Options());
  });

  // -------------------------------------------------------------------------
  // Group 1 — login
  // -------------------------------------------------------------------------

  group('login', () {
    test(
      '1. success → returns (User, AuthTokens) with correct values',
      () async {
        when(
          () => mockDio.post<Map<String, dynamic>>(
            '/auth/login',
            data: any(named: 'data'),
          ),
        ).thenAnswer(
          (_) async => Response(
            requestOptions: _fakeOptions('/auth/login'),
            statusCode: 200,
            data: _loginEnvelope(),
          ),
        );

        final (user, tokens) = await repository.login(
          email: 'master@beautica.test',
          password: 's3cr3t!',
        );

        expect(user.id, 'usr-1');
        expect(user.email, 'master@beautica.test');
        expect(user.role, UserRole.independentMaster);
        // AuthResponse is flat — firstName/lastName are not part of the login
        // response; they come from GET /users/me separately.
        expect(user.firstName, isNull);
        expect(user.lastName, isNull);
        expect(tokens.accessToken, 'access.jwt.token');
        expect(tokens.refreshToken, 'refresh.jwt.token');
      },
    );

    test(
      '2. 401 DioException (error = UnauthorizedFailure) → re-throws UnauthorizedFailure',
      () async {
        const failure = UnauthorizedFailure();
        when(
          () => mockDio.post<Map<String, dynamic>>(
            '/auth/login',
            data: any(named: 'data'),
          ),
        ).thenThrow(_dioWithFailure(failure, statusCode: 401));

        await expectLater(
          () => repository.login(email: 'x@x.com', password: 'wrong'),
          throwsA(isA<UnauthorizedFailure>()),
        );
      },
    );

    test(
      '3. 400 DioException (error = ValidationFailure) → re-throws ValidationFailure with fieldErrors',
      () async {
        const failure = ValidationFailure(
          fieldErrors: {'email': 'must be a valid email'},
        );
        when(
          () => mockDio.post<Map<String, dynamic>>(
            '/auth/login',
            data: any(named: 'data'),
          ),
        ).thenThrow(_dioWithFailure(failure, statusCode: 400));

        await expectLater(
          () => repository.login(email: 'bad-email', password: 'pw'),
          throwsA(
            isA<ValidationFailure>().having(
              (f) => f.fieldErrors,
              'fieldErrors',
              {'email': 'must be a valid email'},
            ),
          ),
        );
      },
    );

    test(
      '4. raw DioException (error = null) → throws UnknownFailure',
      () async {
        when(
          () => mockDio.post<Map<String, dynamic>>(
            '/auth/login',
            data: any(named: 'data'),
          ),
        ).thenThrow(_rawDioException());

        await expectLater(
          () => repository.login(email: 'x@x.com', password: 'pw'),
          throwsA(isA<UnknownFailure>()),
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Group 2 — registerIndependentMaster
  // -------------------------------------------------------------------------

  group('registerIndependentMaster', () {
    test(
      '5. success (auto-login envelope) → returns AuthenticatedRegisterResult',
      () async {
        when(
          () => mockDio.post<Map<String, dynamic>>(
            '/auth/register/independent-master',
            data: any(named: 'data'),
          ),
        ).thenAnswer(
          (_) async => Response(
            requestOptions: _fakeOptions('/auth/register/independent-master'),
            statusCode: 201,
            data: _loginEnvelope(),
          ),
        );

        final result = await repository.registerIndependentMaster(
          email: 'master@beautica.test',
          password: 'P@ssw0rd!',
          firstName: 'Іванна',
          lastName: 'Коваль',
        );

        expect(result, isA<AuthenticatedRegisterResult>());
        final auth = result as AuthenticatedRegisterResult;
        expect(auth.user.role, UserRole.independentMaster);
        expect(auth.tokens.accessToken, 'access.jwt.token');
        expect(auth.tokens.refreshToken, 'refresh.jwt.token');
      },
    );

    // -------------------------------------------------------------------------
    // 5b — verification-required envelope (current backend default)
    //
    // Regression guard for the `_TypeError: type 'Null' is not a subtype of
    // type 'Map<String, dynamic>'` crash: the backend returns
    //   { "success": true, "data": { "message": "...", "email": "..." } }
    // for newly-registered accounts that still need email verification. The
    // repository must surface that as VerificationRequired, NOT call
    // _parseUserAndTokens (which casts data['user'] and would crash on null).
    // -------------------------------------------------------------------------
    test(
      '5b. success (verification-required envelope) → returns VerificationRequired',
      () async {
        when(
          () => mockDio.post<Map<String, dynamic>>(
            '/auth/register/independent-master',
            data: any(named: 'data'),
          ),
        ).thenAnswer(
          (_) async => Response(
            requestOptions: _fakeOptions('/auth/register/independent-master'),
            statusCode: 200,
            data: {
              'success': true,
              'data': {
                'message':
                    'Registration successful. Check your email for the verification code.',
                'email': 'master@beautica.test',
              },
              'message': null,
            },
          ),
        );

        final result = await repository.registerIndependentMaster(
          email: 'master@beautica.test',
          password: 'P@ssw0rd!',
          firstName: 'Іванна',
          lastName: 'Коваль',
        );

        expect(result, isA<VerificationRequired>());
        expect(
          (result as VerificationRequired).email,
          equals('master@beautica.test'),
        );
      },
    );

    // -------------------------------------------------------------------------
    // 5c — malformed envelope (no user AND no email) → UnknownFailure
    //
    // The repository must not silently swallow a genuinely-broken response
    // shape: throw UnknownFailure so the screen surfaces a snackbar instead
    // of crashing with a generic cast error.
    // -------------------------------------------------------------------------
    test(
      '5c. malformed envelope (no user, no email) → throws UnknownFailure',
      () async {
        when(
          () => mockDio.post<Map<String, dynamic>>(
            '/auth/register/independent-master',
            data: any(named: 'data'),
          ),
        ).thenAnswer(
          (_) async => Response(
            requestOptions: _fakeOptions('/auth/register/independent-master'),
            statusCode: 200,
            data: {
              'success': true,
              'data': {'message': 'something happened'},
              'message': null,
            },
          ),
        );

        await expectLater(
          () => repository.registerIndependentMaster(
            email: 'master@beautica.test',
            password: 'P@ssw0rd!',
            firstName: 'Іванна',
            lastName: 'Коваль',
          ),
          throwsA(isA<UnknownFailure>()),
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Group 3 — refresh
  // -------------------------------------------------------------------------

  group('refresh', () {
    test('6. success → returns AuthTokens with new token pair', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/auth/refresh',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: _fakeOptions('/auth/refresh'),
          statusCode: 200,
          data: _refreshEnvelope(),
        ),
      );

      final tokens = await repository.refresh('old.refresh.token');

      expect(tokens.accessToken, 'new.access.token');
      expect(tokens.refreshToken, 'new.refresh.token');
      expect(tokens, isA<AuthTokens>());
    });
  });

  // -------------------------------------------------------------------------
  // Group 4 — me
  // -------------------------------------------------------------------------

  group('me', () {
    test('7. success → returns User with correct role', () async {
      when(() => mockDio.get<Map<String, dynamic>>('/user/me')).thenAnswer(
        (_) async => Response(
          requestOptions: _fakeOptions('/user/me'),
          statusCode: 200,
          data: _meEnvelope(),
        ),
      );

      final user = await repository.me();

      expect(user.id, 'usr-1');
      expect(user.role, UserRole.independentMaster);
      expect(user.email, 'master@beautica.test');
    });

    test('8. 401 DioException → re-throws UnauthorizedFailure', () async {
      const failure = UnauthorizedFailure();
      when(
        () => mockDio.get<Map<String, dynamic>>('/user/me'),
      ).thenThrow(_dioWithFailure(failure, statusCode: 401));

      await expectLater(
        () => repository.me(),
        throwsA(isA<UnauthorizedFailure>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Group 5 — UserRole.fromWire
  // -------------------------------------------------------------------------

  group('UserRole.fromWire', () {
    test('CLIENT maps to UserRole.client', () {
      expect(UserRole.fromWire('CLIENT'), equals(UserRole.client));
    });

    test('SALON_OWNER maps to UserRole.salonOwner', () {
      expect(UserRole.fromWire('SALON_OWNER'), equals(UserRole.salonOwner));
    });

    test('SALON_ADMIN maps to UserRole.salonAdmin', () {
      expect(UserRole.fromWire('SALON_ADMIN'), equals(UserRole.salonAdmin));
    });

    test('SALON_MASTER maps to UserRole.salonMaster', () {
      expect(UserRole.fromWire('SALON_MASTER'), equals(UserRole.salonMaster));
    });

    test('INDEPENDENT_MASTER maps to UserRole.independentMaster', () {
      expect(
        UserRole.fromWire('INDEPENDENT_MASTER'),
        equals(UserRole.independentMaster),
      );
    });

    test('unknown wire value throws ArgumentError', () {
      expect(() => UserRole.fromWire('UNKNOWN'), throwsArgumentError);
    });
  });

  // -------------------------------------------------------------------------
  // Group 6 — refresh failure (Completer error branch)
  // -------------------------------------------------------------------------

  group('refresh — failure path', () {
    test(
      '9. 401 on /auth/refresh → throws UnauthorizedFailure via Completer error branch',
      () async {
        const failure = UnauthorizedFailure();
        when(
          () => mockDio.post<Map<String, dynamic>>(
            '/auth/refresh',
            data: any(named: 'data'),
          ),
        ).thenThrow(_dioWithFailure(failure, statusCode: 401));

        // HttpAuthRepository.refresh() uses an internal Completer to coalesce
        // concurrent calls. When a single call fails, completeError() is called
        // on the Completer whose .future has no listener (no concurrent caller),
        // creating an unhandled async error. We use runZonedGuarded to absorb
        // that secondary error while still asserting the primary throw.
        Object? caught;
        final completerErrors = <Object>[];
        await runZonedGuarded(() async {
          try {
            await repository.refresh('old-token');
          } on Failure catch (e) {
            caught = e;
          }
        }, (err, _) => completerErrors.add(err));

        expect(caught, isA<UnauthorizedFailure>());
      },
    );
  });

  // -------------------------------------------------------------------------
  // Group 7 — registerIndependentMaster failure path
  // -------------------------------------------------------------------------

  group('registerIndependentMaster — failure path', () {
    test(
      '10. ValidationFailure (duplicate email) → re-throws ValidationFailure with fieldErrors',
      () async {
        const failure = ValidationFailure(
          fieldErrors: {'email': 'already exists'},
        );
        when(
          () => mockDio.post<Map<String, dynamic>>(
            '/auth/register/independent-master',
            data: any(named: 'data'),
          ),
        ).thenThrow(_dioWithFailure(failure));

        await expectLater(
          () => repository.registerIndependentMaster(
            email: 'dup@beautica.test',
            password: 'P@ssw0rd!',
            firstName: 'Іванна',
            lastName: 'Коваль',
          ),
          throwsA(
            isA<ValidationFailure>().having(
              (f) => f.fieldErrors,
              'fieldErrors',
              {'email': 'already exists'},
            ),
          ),
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Group 8 — unified /auth/register routing for salonOwner + client roles
  //
  // Backend contract (Phase 2.x):
  //   CLIENT + SALON_OWNER → POST /auth/register  (role discriminator in body)
  //   INDEPENDENT_MASTER   → POST /auth/register/independent-master  (no role)
  // -------------------------------------------------------------------------

  group('registerIndependentMaster — role-based endpoint routing', () {
    test(
      '11. role=salonOwner → POST to /auth/register with role=SALON_OWNER in body',
      () async {
        when(
          () => mockDio.post<Map<String, dynamic>>(
            '/auth/register',
            data: any(named: 'data'),
          ),
        ).thenAnswer(
          (_) async => Response(
            requestOptions: _fakeOptions('/auth/register'),
            statusCode: 201,
            data: _loginEnvelope(role: 'SALON_OWNER'),
          ),
        );

        final result = await repository.registerIndependentMaster(
          email: 'owner@beautica.test',
          password: 'P@ssw0rd!',
          firstName: 'Марія',
          lastName: 'Ковальчук',
          role: UserRole.salonOwner,
          businessName: 'Краса Студія',
        );

        expect(result, isA<AuthenticatedRegisterResult>());
        final auth = result as AuthenticatedRegisterResult;
        expect(auth.user.role, UserRole.salonOwner);
        expect(auth.tokens.accessToken, 'access.jwt.token');

        // Verify the exact unified endpoint was hit — if the routing were wrong
        // and /auth/register/independent-master were used instead, mocktail would
        // throw MissingStubError on the unstubbed path, failing the test.
        verify(
          () => mockDio.post<Map<String, dynamic>>(
            '/auth/register',
            data: any(named: 'data'),
          ),
        ).called(1);
      },
    );

    test(
      '12. role=client → POST to /auth/register with role=CLIENT in body',
      () async {
        when(
          () => mockDio.post<Map<String, dynamic>>(
            '/auth/register',
            data: any(named: 'data'),
          ),
        ).thenAnswer(
          (_) async => Response(
            requestOptions: _fakeOptions('/auth/register'),
            statusCode: 201,
            data: _loginEnvelope(role: 'CLIENT'),
          ),
        );

        final result = await repository.registerIndependentMaster(
          email: 'client@beautica.test',
          password: 'P@ssw0rd!',
          firstName: 'Катерина',
          lastName: 'Мороз',
          role: UserRole.client,
        );

        expect(result, isA<AuthenticatedRegisterResult>());
        final auth = result as AuthenticatedRegisterResult;
        expect(auth.user.role, UserRole.client);
        expect(auth.tokens.refreshToken, 'refresh.jwt.token');

        verify(
          () => mockDio.post<Map<String, dynamic>>(
            '/auth/register',
            data: any(named: 'data'),
          ),
        ).called(1);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Group 9 — businessName body contract
  //
  // The backend enforces that businessName is REQUIRED for SALON_OWNER and
  // must be absent for INDEPENDENT_MASTER (which uses a separate path).
  // These tests capture the exact request body by intercepting the Dio call
  // so that a refactor silently dropping businessName from the body is caught.
  // -------------------------------------------------------------------------

  group('registerIndependentMaster — businessName body contract', () {
    test(
      '13. salonOwner with businessName → body includes businessName trimmed',
      () async {
        Map<String, dynamic>? capturedBody;

        when(
          () => mockDio.post<Map<String, dynamic>>(
            '/auth/register',
            data: any(named: 'data'),
          ),
        ).thenAnswer((invocation) async {
          capturedBody =
              invocation.namedArguments[const Symbol('data')]
                  as Map<String, dynamic>;
          return Response(
            requestOptions: _fakeOptions('/auth/register'),
            statusCode: 201,
            data: _loginEnvelope(role: 'SALON_OWNER'),
          );
        });

        await repository.registerIndependentMaster(
          email: 'owner@beautica.test',
          password: 'P@ssw0rd!',
          firstName: 'Марія',
          lastName: 'Ковальчук',
          role: UserRole.salonOwner,
          businessName: '  Краса Студія  ', // whitespace — must be trimmed
        );

        expect(capturedBody, isNotNull);
        expect(capturedBody!['businessName'], equals('Краса Студія'));
        expect(capturedBody!['role'], equals('SALON_OWNER'));
        // independentMaster path must NOT be used
        verifyNever(
          () => mockDio.post<Map<String, dynamic>>(
            '/auth/register/independent-master',
            data: any(named: 'data'),
          ),
        );
      },
    );

    test(
      '14. salonOwner with null businessName → body does NOT include businessName key',
      () async {
        Map<String, dynamic>? capturedBody;

        when(
          () => mockDio.post<Map<String, dynamic>>(
            '/auth/register',
            data: any(named: 'data'),
          ),
        ).thenAnswer((invocation) async {
          capturedBody =
              invocation.namedArguments[const Symbol('data')]
                  as Map<String, dynamic>;
          return Response(
            requestOptions: _fakeOptions('/auth/register'),
            statusCode: 201,
            data: _loginEnvelope(role: 'SALON_OWNER'),
          );
        });

        await repository.registerIndependentMaster(
          email: 'owner@beautica.test',
          password: 'P@ssw0rd!',
          firstName: 'Марія',
          lastName: 'Ковальчук',
          role: UserRole.salonOwner,
          // businessName intentionally omitted — backend returns 400 for this,
          // but this test verifies the client contract: key is absent, not null.
        );

        expect(capturedBody, isNotNull);
        expect(capturedBody!.containsKey('businessName'), isFalse);
      },
    );

    test(
      '15. salonOwner with blank businessName → body does NOT include businessName key',
      () async {
        Map<String, dynamic>? capturedBody;

        when(
          () => mockDio.post<Map<String, dynamic>>(
            '/auth/register',
            data: any(named: 'data'),
          ),
        ).thenAnswer((invocation) async {
          capturedBody =
              invocation.namedArguments[const Symbol('data')]
                  as Map<String, dynamic>;
          return Response(
            requestOptions: _fakeOptions('/auth/register'),
            statusCode: 201,
            data: _loginEnvelope(role: 'SALON_OWNER'),
          );
        });

        await repository.registerIndependentMaster(
          email: 'owner@beautica.test',
          password: 'P@ssw0rd!',
          firstName: 'Марія',
          lastName: 'Ковальчук',
          role: UserRole.salonOwner,
          businessName: '   ', // all whitespace — must be treated as absent
        );

        expect(capturedBody, isNotNull);
        expect(capturedBody!.containsKey('businessName'), isFalse);
      },
    );

    test(
      '16. independentMaster → POST to /auth/register/independent-master; body has no role or businessName keys',
      () async {
        Map<String, dynamic>? capturedBody;

        when(
          () => mockDio.post<Map<String, dynamic>>(
            '/auth/register/independent-master',
            data: any(named: 'data'),
          ),
        ).thenAnswer((invocation) async {
          capturedBody =
              invocation.namedArguments[const Symbol('data')]
                  as Map<String, dynamic>;
          return Response(
            requestOptions: _fakeOptions('/auth/register/independent-master'),
            statusCode: 201,
            data: _loginEnvelope(),
          );
        });

        await repository.registerIndependentMaster(
          email: 'master@beautica.test',
          password: 'P@ssw0rd!',
          firstName: 'Іванна',
          lastName: 'Коваль',
          // role defaults to independentMaster; businessName omitted
        );

        expect(capturedBody, isNotNull);
        // Backend derives the role from the path — do NOT send a role field.
        expect(capturedBody!.containsKey('role'), isFalse);
        expect(capturedBody!.containsKey('businessName'), isFalse);
        // Required fields must be present.
        expect(capturedBody!['email'], equals('master@beautica.test'));
        expect(capturedBody!['firstName'], equals('Іванна'));
        expect(capturedBody!['lastName'], equals('Коваль'));
      },
    );

    test(
      '17. salonOwner ValidationFailure (blank businessName on server) → re-throws ValidationFailure',
      () async {
        const failure = ValidationFailure(
          fieldErrors: {'businessName': 'must not be blank'},
        );
        when(
          () => mockDio.post<Map<String, dynamic>>(
            '/auth/register',
            data: any(named: 'data'),
          ),
        ).thenThrow(_dioWithFailure(failure));

        await expectLater(
          () => repository.registerIndependentMaster(
            email: 'owner@beautica.test',
            password: 'P@ssw0rd!',
            firstName: 'Марія',
            lastName: 'Ковальчук',
            role: UserRole.salonOwner,
          ),
          throwsA(
            isA<ValidationFailure>().having(
              (f) => f.fieldErrors,
              'fieldErrors',
              {'businessName': 'must not be blank'},
            ),
          ),
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Group 10 — registerIndependentMaster — phone body contract
  //
  // The backend enforces that phoneNumber is trimmed before sending and must be
  // absent from the body when the caller passes null (rather than sent as null
  // or an empty string, which could cause a backend schema error).
  //
  // These tests capture the exact request body so that a refactor that
  // accidentally includes/excludes phoneNumber is caught immediately.
  // -------------------------------------------------------------------------

  group('registerIndependentMaster — phone body contract', () {
    test('IM with phone: body includes phoneNumber trimmed', () async {
      Map<String, dynamic>? capturedBody;

      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/auth/register/independent-master',
          data: any(named: 'data'),
        ),
      ).thenAnswer((invocation) async {
        capturedBody =
            invocation.namedArguments[const Symbol('data')]
                as Map<String, dynamic>;
        return Response(
          requestOptions: _fakeOptions('/auth/register/independent-master'),
          statusCode: 201,
          data: _loginEnvelope(),
        );
      });

      await repository.registerIndependentMaster(
        email: 'master@beautica.test',
        password: 'P@ssw0rd!',
        firstName: 'Іванна',
        lastName: 'Коваль',
        // Leading and trailing whitespace must be stripped before sending.
        phone: '  +380 67 123 45 67  ',
      );

      expect(capturedBody, isNotNull);
      expect(
        capturedBody!['phoneNumber'],
        equals('+380 67 123 45 67'),
        reason:
            'phone is trimmed before inclusion; whitespace must be '
            'stripped from the request body',
      );
      // role and businessName must be absent — IM path derives role from URL.
      expect(capturedBody!.containsKey('role'), isFalse);
      expect(capturedBody!.containsKey('businessName'), isFalse);
    });

    test('IM with null phone: body excludes phoneNumber key', () async {
      Map<String, dynamic>? capturedBody;

      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/auth/register/independent-master',
          data: any(named: 'data'),
        ),
      ).thenAnswer((invocation) async {
        capturedBody =
            invocation.namedArguments[const Symbol('data')]
                as Map<String, dynamic>;
        return Response(
          requestOptions: _fakeOptions('/auth/register/independent-master'),
          statusCode: 201,
          data: _loginEnvelope(),
        );
      });

      await repository.registerIndependentMaster(
        email: 'master@beautica.test',
        password: 'P@ssw0rd!',
        firstName: 'Іванна',
        lastName: 'Коваль',
        // phone is intentionally omitted (defaults to null).
      );

      expect(capturedBody, isNotNull);
      // A null phone must not appear in the body at all — sending
      // "phoneNumber": null would fail backend schema validation.
      expect(
        capturedBody!.containsKey('phoneNumber'),
        isFalse,
        reason:
            'null phone must not insert a phoneNumber key into the '
            'request body',
      );
    });

    test('salonOwner with phone: body includes phoneNumber', () async {
      Map<String, dynamic>? capturedBody;

      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/auth/register',
          data: any(named: 'data'),
        ),
      ).thenAnswer((invocation) async {
        capturedBody =
            invocation.namedArguments[const Symbol('data')]
                as Map<String, dynamic>;
        return Response(
          requestOptions: _fakeOptions('/auth/register'),
          statusCode: 201,
          data: _loginEnvelope(role: 'SALON_OWNER'),
        );
      });

      await repository.registerIndependentMaster(
        email: 'owner@beautica.test',
        password: 'P@ssw0rd!',
        firstName: 'Марія',
        lastName: 'Ковальчук',
        role: UserRole.salonOwner,
        businessName: 'Краса',
        phone: '+380 50 123 45 67',
      );

      expect(capturedBody, isNotNull);
      expect(
        capturedBody!['phoneNumber'],
        equals('+380 50 123 45 67'),
        reason:
            'salonOwner phone must be included as phoneNumber in the '
            'body, matching the backend contract',
      );
      expect(capturedBody!['role'], equals('SALON_OWNER'));
    });
  });

  // -------------------------------------------------------------------------
  // Group 11 — verifyEmail (backend Phase 1.5)
  //
  // Contract:
  //   Request:  POST /auth/verify-email  {email, code: <otp>}
  //   Success:  ApiResponse<AuthResponse> — full session envelope.
  //   400:      ApiResponse<{code: "INVALID_CODE" | "CODE_EXPIRED" |
  //             "ALREADY_VERIFIED"}> → VerificationFailure via interceptor.
  // -------------------------------------------------------------------------

  group('verifyEmail', () {
    test('success → returns (User, AuthTokens) parsed from envelope', () async {
      Map<String, dynamic>? capturedBody;

      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/auth/verify-email',
          data: any(named: 'data'),
        ),
      ).thenAnswer((invocation) async {
        capturedBody =
            invocation.namedArguments[const Symbol('data')]
                as Map<String, dynamic>;
        return Response(
          requestOptions: _fakeOptions('/auth/verify-email'),
          statusCode: 200,
          data: _loginEnvelope(),
        );
      });

      final (user, tokens) = await repository.verifyEmail(
        email: 'master@beautica.test',
        otp: '654321',
      );

      // Request body uses the wire field `code` (not `otp`).
      expect(capturedBody, isNotNull);
      expect(capturedBody!['email'], equals('master@beautica.test'));
      expect(
        capturedBody!['code'],
        equals('654321'),
        reason:
            'Backend Phase 1.5 wire field is `code`, not `otp` — '
            'mobile param name is `otp` for HTML-mockup parity only',
      );

      // Response is parsed via the same helper as /auth/login.
      expect(user.id, 'usr-1');
      expect(user.email, 'master@beautica.test');
      expect(user.role, UserRole.independentMaster);
      expect(tokens.accessToken, 'access.jwt.token');
      expect(tokens.refreshToken, 'refresh.jwt.token');
    });

    test(
      'INVALID_CODE → throws VerificationFailure(invalidCode) via interceptor',
      () async {
        const failure = VerificationFailure(
          code: VerificationErrorCode.invalidCode,
        );
        when(
          () => mockDio.post<Map<String, dynamic>>(
            '/auth/verify-email',
            data: any(named: 'data'),
          ),
        ).thenThrow(_dioWithFailure(failure, statusCode: 400));

        await expectLater(
          () => repository.verifyEmail(email: 'x@x.com', otp: '000000'),
          throwsA(
            isA<VerificationFailure>().having(
              (f) => f.code,
              'code',
              VerificationErrorCode.invalidCode,
            ),
          ),
        );
      },
    );

    test(
      'CODE_EXPIRED → throws VerificationFailure(codeExpired) via interceptor',
      () async {
        const failure = VerificationFailure(
          code: VerificationErrorCode.codeExpired,
        );
        when(
          () => mockDio.post<Map<String, dynamic>>(
            '/auth/verify-email',
            data: any(named: 'data'),
          ),
        ).thenThrow(_dioWithFailure(failure, statusCode: 400));

        await expectLater(
          () => repository.verifyEmail(email: 'x@x.com', otp: '111111'),
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
      'ALREADY_VERIFIED → throws VerificationFailure(alreadyVerified) via interceptor',
      () async {
        const failure = VerificationFailure(
          code: VerificationErrorCode.alreadyVerified,
        );
        when(
          () => mockDio.post<Map<String, dynamic>>(
            '/auth/verify-email',
            data: any(named: 'data'),
          ),
        ).thenThrow(_dioWithFailure(failure, statusCode: 400));

        await expectLater(
          () => repository.verifyEmail(email: 'x@x.com', otp: '222222'),
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

    test('raw DioException → throws UnknownFailure', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/auth/verify-email',
          data: any(named: 'data'),
        ),
      ).thenThrow(_rawDioException());

      await expectLater(
        () => repository.verifyEmail(email: 'x@x.com', otp: '333333'),
        throwsA(isA<UnknownFailure>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Group 12 — resendVerificationCode (backend Phase 1.6)
  //
  // Contract:
  //   Request:  POST /auth/resend-verification  {email}
  //   Success:  ApiResponse<RegistrationResponse> — repository returns void.
  //   429:      {success:false, message:"...", data:{retryAfterSeconds:N}}
  //             → ResendThrottledFailure via interceptor.
  // -------------------------------------------------------------------------

  group('resendVerificationCode', () {
    test('success → request body carries {email}, completes void', () async {
      Map<String, dynamic>? capturedBody;

      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/auth/resend-verification',
          data: any(named: 'data'),
        ),
      ).thenAnswer((invocation) async {
        capturedBody =
            invocation.namedArguments[const Symbol('data')]
                as Map<String, dynamic>;
        return Response(
          requestOptions: _fakeOptions('/auth/resend-verification'),
          statusCode: 200,
          data: {
            'success': true,
            'data': {
              'message': 'Verification code resent.',
              'email': 'master@beautica.test',
            },
            'message': null,
          },
        );
      });

      await repository.resendVerificationCode(email: 'master@beautica.test');

      expect(capturedBody, isNotNull);
      expect(capturedBody!['email'], equals('master@beautica.test'));
      // Only the email is sent — nothing else.
      expect(capturedBody!.length, equals(1));
    });

    test(
      '429 ResendThrottledFailure → throws ResendThrottledFailure with retryAfterSeconds',
      () async {
        const failure = ResendThrottledFailure(retryAfterSeconds: 42);
        when(
          () => mockDio.post<Map<String, dynamic>>(
            '/auth/resend-verification',
            data: any(named: 'data'),
          ),
        ).thenThrow(_dioWithFailure(failure, statusCode: 429));

        await expectLater(
          () =>
              repository.resendVerificationCode(email: 'master@beautica.test'),
          throwsA(
            isA<ResendThrottledFailure>().having(
              (f) => f.retryAfterSeconds,
              'retryAfterSeconds',
              42,
            ),
          ),
        );
      },
    );

    test('raw DioException → throws UnknownFailure', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/auth/resend-verification',
          data: any(named: 'data'),
        ),
      ).thenThrow(_rawDioException());

      await expectLater(
        () => repository.resendVerificationCode(email: 'x@x.com'),
        throwsA(isA<UnknownFailure>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Group 13 — requestPasswordReset (backend Phase 11.2)
  //
  // Contract:
  //   Request:  POST /auth/forgot-password  {email}
  //   Success:  ALWAYS generic 200 (anti-enumeration) → repository returns void.
  //   Genuine transport/server errors still propagate as typed Failures.
  // -------------------------------------------------------------------------

  group('requestPasswordReset', () {
    test('success → request body carries {email}, completes void', () async {
      Map<String, dynamic>? capturedBody;

      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/auth/forgot-password',
          data: any(named: 'data'),
        ),
      ).thenAnswer((invocation) async {
        capturedBody =
            invocation.namedArguments[const Symbol('data')]
                as Map<String, dynamic>;
        return Response(
          requestOptions: _fakeOptions('/auth/forgot-password'),
          statusCode: 200,
          data: {
            'success': true,
            'data': null,
            'message': 'If an account exists for that email, a reset link…',
          },
        );
      });

      await repository.requestPasswordReset('master@beautica.test');

      expect(capturedBody, isNotNull);
      expect(capturedBody!['email'], equals('master@beautica.test'));
      // Only the email is sent — nothing else.
      expect(capturedBody!.length, equals(1));
    });

    test('network error → throws NetworkFailure', () async {
      const failure = NetworkFailure();
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/auth/forgot-password',
          data: any(named: 'data'),
        ),
      ).thenThrow(_dioWithFailure(failure, statusCode: 503));

      await expectLater(
        () => repository.requestPasswordReset('x@x.com'),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('raw DioException → throws UnknownFailure', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/auth/forgot-password',
          data: any(named: 'data'),
        ),
      ).thenThrow(_rawDioException());

      await expectLater(
        () => repository.requestPasswordReset('x@x.com'),
        throwsA(isA<UnknownFailure>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Group 14 — confirmPasswordReset (backend Phase 11.3)
  //
  // Contract:
  //   Request:  POST /auth/reset-password  {token, newPassword}
  //   Success:  generic 200, NO session → repository returns void.
  //   400:      generic envelope for invalid/used/expired token → the
  //             interceptor surfaces a ValidationFailure (no field errors),
  //             which the repository re-maps to ResetTokenInvalidFailure.
  // -------------------------------------------------------------------------

  group('confirmPasswordReset', () {
    test(
      'success → body carries {token, newPassword}, completes void',
      () async {
        Map<String, dynamic>? capturedBody;

        when(
          () => mockDio.post<Map<String, dynamic>>(
            '/auth/reset-password',
            data: any(named: 'data'),
          ),
        ).thenAnswer((invocation) async {
          capturedBody =
              invocation.namedArguments[const Symbol('data')]
                  as Map<String, dynamic>;
          return Response(
            requestOptions: _fakeOptions('/auth/reset-password'),
            statusCode: 200,
            data: {
              'success': true,
              'data': null,
              'message': 'Password has been reset. Please sign in.',
            },
          );
        });

        await repository.confirmPasswordReset(
          token: 'raw-reset-token',
          newPassword: 'NewSecret123',
        );

        expect(capturedBody, isNotNull);
        expect(capturedBody!['token'], equals('raw-reset-token'));
        expect(capturedBody!['newPassword'], equals('NewSecret123'));
        expect(capturedBody!.length, equals(2));
      },
    );

    test(
      'generic 400 (ValidationFailure from interceptor) → throws ResetTokenInvalidFailure',
      () async {
        // The backend returns a generic 400 with no `errors` map for an
        // invalid/used/expired token; ErrorMapperInterceptor maps that to a
        // ValidationFailure with empty fieldErrors.
        const failure = ValidationFailure(fieldErrors: {});
        when(
          () => mockDio.post<Map<String, dynamic>>(
            '/auth/reset-password',
            data: any(named: 'data'),
          ),
        ).thenThrow(_dioWithFailure(failure, statusCode: 400));

        await expectLater(
          () => repository.confirmPasswordReset(
            token: 'expired-token',
            newPassword: 'NewSecret123',
          ),
          throwsA(isA<ResetTokenInvalidFailure>()),
        );
      },
    );

    test('network error → throws NetworkFailure (not re-mapped)', () async {
      const failure = NetworkFailure();
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/auth/reset-password',
          data: any(named: 'data'),
        ),
      ).thenThrow(_dioWithFailure(failure, statusCode: 503));

      await expectLater(
        () => repository.confirmPasswordReset(
          token: 't',
          newPassword: 'NewSecret123',
        ),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test(
      '5xx → throws ServerFailure (not re-mapped to token-invalid)',
      () async {
        const failure = ServerFailure(statusCode: 500);
        when(
          () => mockDio.post<Map<String, dynamic>>(
            '/auth/reset-password',
            data: any(named: 'data'),
          ),
        ).thenThrow(_dioWithFailure(failure, statusCode: 500));

        await expectLater(
          () => repository.confirmPasswordReset(
            token: 't',
            newPassword: 'NewSecret123',
          ),
          throwsA(isA<ServerFailure>()),
        );
      },
    );

    test('raw DioException → throws UnknownFailure', () async {
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/auth/reset-password',
          data: any(named: 'data'),
        ),
      ).thenThrow(_rawDioException());

      await expectLater(
        () => repository.confirmPasswordReset(
          token: 't',
          newPassword: 'NewSecret123',
        ),
        throwsA(isA<UnknownFailure>()),
      );
    });
  });
}
