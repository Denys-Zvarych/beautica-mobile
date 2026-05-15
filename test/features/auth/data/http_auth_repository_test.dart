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
//     5. success → returns (User, AuthTokens)
//   Group 3 — refresh
//     6. success → returns AuthTokens with new token pair
//   Group 4 — me
//     7. success → returns User with correct role
//     8. 401 DioException → re-throws UnauthorizedFailure

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/data/http_auth_repository.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
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
Map<String, dynamic> _loginEnvelope({
  String userId = 'usr-1',
  String role = 'INDEPENDENT_MASTER',
}) => {
  'success': true,
  'message': 'OK',
  'data': {
    'user': {
      'id': userId,
      'email': 'master@beautica.test',
      'role': role,
      'firstName': 'Іванна',
      'lastName': 'Коваль',
    },
    'accessToken': 'access.jwt.token',
    'refreshToken': 'refresh.jwt.token',
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
        expect(user.firstName, 'Іванна');
        expect(user.lastName, 'Коваль');
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
    test('5. success → returns (User, AuthTokens)', () async {
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

      final (user, tokens) = await repository.registerIndependentMaster(
        email: 'master@beautica.test',
        password: 'P@ssw0rd!',
        firstName: 'Іванна',
        lastName: 'Коваль',
      );

      expect(user.role, UserRole.independentMaster);
      expect(tokens.accessToken, 'access.jwt.token');
      expect(tokens.refreshToken, 'refresh.jwt.token');
    });
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
}
