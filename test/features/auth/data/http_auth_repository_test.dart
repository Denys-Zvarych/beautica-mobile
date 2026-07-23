// Phase 3.2 — HttpAuthRepository unit tests (re-pointed to generated API classes).
//
// After Phase 3.2, [HttpAuthRepository] takes [AuthControllerApi] and
// [UserControllerApi] instead of raw [Dio]. Tests now mock the generated API
// classes directly via mocktail instead of intercepting low-level Dio calls.
//
// Test structure:
//   Group 1 — login
//     1. success → returns (User, AuthTokens) with correct values
//     2. 401 DioException (error = UnauthorizedFailure) → re-throws
//     2b. 401 emailNotVerified=true → NOT remapped
//     3. 400 DioException (error = ValidationFailure) → re-throws
//     4. raw DioException (error = null) → throws UnknownFailure
//   Group 2 — registerIndependentMaster
//     5. success (verification-required envelope) → VerificationRequired
//     5b. verification-required (no email) → UnknownFailure
//   Group 3 — refresh
//     6. success → returns AuthTokens with new token pair
//     6b. failure → throws UnauthorizedFailure via Completer
//   Group 4 — me
//     7. success → returns User with firstName + lastName
//     8. 401 DioException → re-throws UnauthorizedFailure
//     9. NetworkFailure → re-throws
//     10. raw DioException (no Failure) → throws UnknownFailure
//   Group 5 — UserRole.fromWire
//   Group 6 — verifyEmail
//   Group 7 — role routing (independent-master vs /auth/register)
//   Group 8 — acceptInvite
//   Group 9 — validateInvite

import 'dart:async';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/token_refresh_lock.dart';
import 'package:beautica_mobile/features/auth/data/http_auth_repository.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/domain/register_result.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockAuthApi extends Mock implements AuthControllerApi {}

class MockUserApi extends Mock implements UserControllerApi {}

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

/// Builds a mock [ApiResponseAuthResponse] envelope with sensible defaults.
///
/// Mirrors the flat AuthResponse the backend returns for login / refresh /
/// verifyEmail / acceptInvite. userId (not id), no firstName/lastName.
Response<ApiResponseAuthResponse> _authResponse({
  String userId = 'usr-1',
  String role = 'INDEPENDENT_MASTER',
}) {
  final dto = AuthResponse(
    (b) => b
      ..userId = userId
      ..email = 'master@beautica.test'
      ..role = AuthResponseRoleEnum.valueOf(role)
      ..accessToken = 'access.jwt.token'
      ..refreshToken = 'refresh.jwt.token'
      ..tokenType = 'Bearer',
  );
  final envelope = ApiResponseAuthResponse(
    (b) => b
      ..success = true
      ..data = dto.toBuilder(),
  );
  return Response(
    data: envelope,
    statusCode: 200,
    requestOptions: _fakeOptions('/auth/login'),
  );
}

/// Builds a mock [ApiResponseAuthResponse] with new token pair for refresh.
Response<ApiResponseAuthResponse> _refreshResponse() {
  final dto = AuthResponse(
    (b) => b
      ..userId = 'usr-1'
      ..email = 'master@beautica.test'
      ..role = AuthResponseRoleEnum.INDEPENDENT_MASTER
      ..accessToken = 'new.access.token'
      ..refreshToken = 'new.refresh.token'
      ..tokenType = 'Bearer',
  );
  final envelope = ApiResponseAuthResponse(
    (b) => b
      ..success = true
      ..data = dto.toBuilder(),
  );
  return Response(
    data: envelope,
    statusCode: 200,
    requestOptions: _fakeOptions('/auth/refresh'),
  );
}

/// Builds a mock [ApiResponseUserProfileResponse] for GET /users/me.
Response<ApiResponseUserProfileResponse> _meResponse({
  String role = 'INDEPENDENT_MASTER',
}) {
  final dto = UserProfileResponse(
    (b) => b
      ..id = 'usr-1'
      ..email = 'master@beautica.test'
      ..role = role
      ..firstName = 'Іванна'
      ..lastName = 'Коваль',
  );
  final envelope = ApiResponseUserProfileResponse(
    (b) => b
      ..success = true
      ..data = dto.toBuilder(),
  );
  return Response(
    data: envelope,
    statusCode: 200,
    requestOptions: _fakeOptions('/users/me'),
  );
}

/// Builds a verification-required registration response.
Response<ApiResponseRegistrationResponse> _verificationRequiredResponse({
  String email = 'master@beautica.test',
}) {
  final dto = RegistrationResponse(
    (b) => b
      ..email = email
      ..message = 'Registration successful. Check your email for the code.',
  );
  final envelope = ApiResponseRegistrationResponse(
    (b) => b
      ..success = true
      ..data = dto.toBuilder(),
  );
  return Response(
    data: envelope,
    statusCode: 200,
    requestOptions: _fakeOptions('/auth/register'),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockAuthApi mockAuthApi;
  late MockUserApi mockUserApi;
  late HttpAuthRepository repository;

  setUpAll(() {
    // Register fallback values required by mocktail for built_value request
    // types. Mocktail needs a concrete instance to use as a fallback whenever
    // any(named: ...) is used with a non-primitive type.
    registerFallbackValue(RequestOptions(path: '/fallback'));
    registerFallbackValue(
      LoginRequest(
        (b) => b
          ..email = 'a@a.com'
          ..password = 'pw',
      ),
    );
    registerFallbackValue(
      RegisterIndependentMasterRequest(
        (b) => b
          ..email = 'a@a.com'
          ..password = 'pw'
          ..firstName = 'A'
          ..lastName = 'B'
          ..phoneNumber = '',
      ),
    );
    registerFallbackValue(RefreshRequest((b) => b..refreshToken = 'token'));
    registerFallbackValue(
      VerifyEmailRequest(
        (b) => b
          ..email = 'a@a.com'
          ..code = '000000',
      ),
    );
    registerFallbackValue(
      RegisterRequest(
        (b) => b
          ..email = 'a@a.com'
          ..password = 'pw'
          ..role = RegisterRequestRoleEnum.CLIENT
          ..firstName = 'A'
          ..lastName = 'B'
          ..phoneNumber = '',
      ),
    );
    registerFallbackValue(
      ResendVerificationRequest((b) => b..email = 'a@a.com'),
    );
    registerFallbackValue(ForgotPasswordRequest((b) => b..email = 'a@a.com'));
    registerFallbackValue(
      ResetPasswordRequest(
        (b) => b
          ..resetTicket = 'tok'
          ..newPassword = 'pw',
      ),
    );
    registerFallbackValue(
      VerifyPasswordResetOtpRequest(
        (b) => b
          ..email = 'a@a.com'
          ..code = '000000',
      ),
    );
    registerFallbackValue(
      InviteAcceptRequest(
        (b) => b
          ..token = 'tok'
          ..password = 'pw'
          ..firstName = 'A'
          ..lastName = 'B'
          ..phoneNumber = '',
      ),
    );
  });

  setUp(() {
    mockAuthApi = MockAuthApi();
    mockUserApi = MockUserApi();
    // Fresh lock per test so state from one test cannot leak into the next.
    repository = HttpAuthRepository(
      mockAuthApi,
      mockUserApi,
      TokenRefreshLock(),
    );
  });

  // -------------------------------------------------------------------------
  // Group 1 — login
  // -------------------------------------------------------------------------

  group('login', () {
    test(
      '1. success → returns (User, AuthTokens) with correct values',
      () async {
        when(
          () => mockAuthApi.login(loginRequest: any(named: 'loginRequest')),
        ).thenAnswer((_) async => _authResponse());

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

    test('2. 401 plain UnauthorizedFailure (emailNotVerified=false) → remapped '
        'to InvalidCredentialsFailure (wrong-password fix)', () async {
      const failure = UnauthorizedFailure();
      when(
        () => mockAuthApi.login(loginRequest: any(named: 'loginRequest')),
      ).thenThrow(_dioWithFailure(failure, statusCode: 401));

      await expectLater(
        () => repository.login(email: 'x@x.com', password: 'wrong'),
        throwsA(isA<InvalidCredentialsFailure>()),
      );
    });

    test(
      '2b. 401 UnauthorizedFailure(emailNotVerified=true) → NOT remapped; '
      'UnauthorizedFailure propagates unchanged for AuthBanner routing',
      () async {
        const failure = UnauthorizedFailure(emailNotVerified: true);
        when(
          () => mockAuthApi.login(loginRequest: any(named: 'loginRequest')),
        ).thenThrow(_dioWithFailure(failure, statusCode: 401));

        await expectLater(
          () => repository.login(email: 'unverified@x.com', password: 'pw'),
          throwsA(
            isA<UnauthorizedFailure>().having(
              (f) => f.emailNotVerified,
              'emailNotVerified',
              isTrue,
            ),
          ),
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
          () => mockAuthApi.login(loginRequest: any(named: 'loginRequest')),
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
          () => mockAuthApi.login(loginRequest: any(named: 'loginRequest')),
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
      '5. success (verification-required envelope) → returns VerificationRequired',
      () async {
        when(
          () => mockAuthApi.registerIndependentMaster(
            registerIndependentMasterRequest: any(
              named: 'registerIndependentMasterRequest',
            ),
          ),
        ).thenAnswer((_) async => _verificationRequiredResponse());

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

    test(
      '5b. registration response missing email → throws UnknownFailure',
      () async {
        // Build a RegistrationResponse with no email to simulate a broken shape.
        final dto = RegistrationResponse(
          (b) => b..message = 'something happened',
        );
        final envelope = ApiResponseRegistrationResponse(
          (b) => b
            ..success = true
            ..data = dto.toBuilder(),
        );
        final res = Response(
          data: envelope,
          statusCode: 200,
          requestOptions: _fakeOptions('/auth/register/independent-master'),
        );
        when(
          () => mockAuthApi.registerIndependentMaster(
            registerIndependentMasterRequest: any(
              named: 'registerIndependentMasterRequest',
            ),
          ),
        ).thenAnswer((_) async => res);

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

    test(
      '5c. ValidationFailure (duplicate email) → re-throws unchanged',
      () async {
        const failure = ValidationFailure(
          fieldErrors: {'email': 'already exists'},
        );
        when(
          () => mockAuthApi.registerIndependentMaster(
            registerIndependentMasterRequest: any(
              named: 'registerIndependentMasterRequest',
            ),
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

    test('5d. EmailAlreadyRegisteredFailure propagates unchanged', () async {
      const failure = EmailAlreadyRegisteredFailure();
      when(
        () => mockAuthApi.registerIndependentMaster(
          registerIndependentMasterRequest: any(
            named: 'registerIndependentMasterRequest',
          ),
        ),
      ).thenThrow(_dioWithFailure(failure, statusCode: 409));

      await expectLater(
        () => repository.registerIndependentMaster(
          email: 'dup@beautica.test',
          password: 'P@ssw0rd!',
          firstName: 'Іванна',
          lastName: 'Коваль',
        ),
        throwsA(isA<EmailAlreadyRegisteredFailure>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Group 3 — refresh
  // -------------------------------------------------------------------------

  group('refresh', () {
    test('6. success → returns AuthTokens with new token pair', () async {
      when(
        () => mockAuthApi.refresh(
          refreshRequest: any(named: 'refreshRequest'),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer((_) async => _refreshResponse());

      final tokens = await repository.refresh('old.refresh.token');

      expect(tokens.accessToken, 'new.access.token');
      expect(tokens.refreshToken, 'new.refresh.token');
      expect(tokens, isA<AuthTokens>());
    });

    test(
      '6b. 401 on /auth/refresh → throws UnauthorizedFailure via Completer error branch',
      () async {
        const failure = UnauthorizedFailure();
        when(
          () => mockAuthApi.refresh(
            refreshRequest: any(named: 'refreshRequest'),
            headers: any(named: 'headers'),
          ),
        ).thenThrow(_dioWithFailure(failure, statusCode: 401));

        // HttpAuthRepository.refresh() uses an internal Completer to coalesce
        // concurrent calls. When a single call fails, completeError() is called
        // on the Completer whose .future has no listener (no concurrent caller),
        // creating an unhandled async error. runZonedGuarded absorbs that
        // secondary error while still asserting the primary throw.
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
  // Group 4 — me
  // -------------------------------------------------------------------------

  group('me', () {
    test('7. success → returns User with firstName + lastName', () async {
      when(
        () => mockUserApi.getMe(headers: any(named: 'headers')),
      ).thenAnswer((_) async => _meResponse());

      final user = await repository.me();

      expect(user.id, 'usr-1');
      expect(user.role, UserRole.independentMaster);
      expect(user.email, 'master@beautica.test');
      // firstName and lastName are ONLY available from /users/me — absent from
      // the flat AuthResponse. If the mapper stops parsing these the done screen
      // greeting falls back to "друже".
      expect(
        user.firstName,
        equals('Іванна'),
        reason: 'me() must parse firstName from UserProfileResponse',
      );
      expect(
        user.lastName,
        equals('Коваль'),
        reason: 'me() must parse lastName from UserProfileResponse',
      );
    });

    test('8. 401 DioException → re-throws UnauthorizedFailure', () async {
      const failure = UnauthorizedFailure();
      when(
        () => mockUserApi.getMe(headers: any(named: 'headers')),
      ).thenThrow(_dioWithFailure(failure, statusCode: 401));

      await expectLater(
        () => repository.me(),
        throwsA(isA<UnauthorizedFailure>()),
      );
    });

    test('9. NetworkFailure on /users/me → re-throws NetworkFailure', () async {
      const failure = NetworkFailure();
      when(
        () => mockUserApi.getMe(headers: any(named: 'headers')),
      ).thenThrow(_dioWithFailure(failure, statusCode: 503));

      await expectLater(() => repository.me(), throwsA(isA<NetworkFailure>()));
    });

    test(
      '10. raw DioException on /users/me (no attached Failure) → throws UnknownFailure',
      () async {
        when(
          () => mockUserApi.getMe(headers: any(named: 'headers')),
        ).thenThrow(_rawDioException());

        await expectLater(
          () => repository.me(),
          throwsA(isA<UnknownFailure>()),
        );
      },
    );
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
  // Group 6 — verifyEmail
  // -------------------------------------------------------------------------

  group('verifyEmail', () {
    test('success → returns (User, AuthTokens)', () async {
      when(
        () => mockAuthApi.verifyEmail(
          verifyEmailRequest: any(named: 'verifyEmailRequest'),
        ),
      ).thenAnswer((_) async => _authResponse());

      final (user, tokens) = await repository.verifyEmail(
        email: 'master@beautica.test',
        otp: '123456',
      );

      expect(user.id, 'usr-1');
      expect(tokens.accessToken, 'access.jwt.token');
    });

    test('DioException → re-throws mapped Failure', () async {
      const failure = ValidationFailure(fieldErrors: {});
      when(
        () => mockAuthApi.verifyEmail(
          verifyEmailRequest: any(named: 'verifyEmailRequest'),
        ),
      ).thenThrow(_dioWithFailure(failure));

      await expectLater(
        () => repository.verifyEmail(email: 'x@x.com', otp: '000000'),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Group 7 — role-based endpoint routing
  // -------------------------------------------------------------------------

  group('registerIndependentMaster — role routing', () {
    test(
      'salonOwner → calls authApi.register (not registerIndependentMaster)',
      () async {
        when(
          () => mockAuthApi.register(
            registerRequest: any(named: 'registerRequest'),
          ),
        ).thenAnswer(
          (_) async =>
              _verificationRequiredResponse(email: 'owner@beautica.test'),
        );

        final result = await repository.registerIndependentMaster(
          email: 'owner@beautica.test',
          password: 'P@ssw0rd!',
          firstName: 'Марія',
          lastName: 'Ковальчук',
          role: UserRole.salonOwner,
          businessName: 'Краса Студія',
        );

        expect(result, isA<VerificationRequired>());
        verify(
          () => mockAuthApi.register(
            registerRequest: any(named: 'registerRequest'),
          ),
        ).called(1);
        verifyNever(
          () => mockAuthApi.registerIndependentMaster(
            registerIndependentMasterRequest: any(
              named: 'registerIndependentMasterRequest',
            ),
          ),
        );
      },
    );

    test(
      'client → calls authApi.register (not registerIndependentMaster)',
      () async {
        when(
          () => mockAuthApi.register(
            registerRequest: any(named: 'registerRequest'),
          ),
        ).thenAnswer(
          (_) async =>
              _verificationRequiredResponse(email: 'client@beautica.test'),
        );

        final result = await repository.registerIndependentMaster(
          email: 'client@beautica.test',
          password: 'P@ssw0rd!',
          firstName: 'Катерина',
          lastName: 'Мороз',
          role: UserRole.client,
        );

        expect(result, isA<VerificationRequired>());
        verify(
          () => mockAuthApi.register(
            registerRequest: any(named: 'registerRequest'),
          ),
        ).called(1);
      },
    );

    test(
      'EmailAlreadyRegisteredFailure propagates from /auth/register path',
      () async {
        const failure = EmailAlreadyRegisteredFailure();
        when(
          () => mockAuthApi.register(
            registerRequest: any(named: 'registerRequest'),
          ),
        ).thenThrow(_dioWithFailure(failure, statusCode: 409));

        await expectLater(
          () => repository.registerIndependentMaster(
            email: 'dup@beautica.test',
            password: 'P@ssw0rd!',
            firstName: 'Марія',
            lastName: 'Ковальчук',
            role: UserRole.salonOwner,
            businessName: 'Краса Студія',
          ),
          throwsA(isA<EmailAlreadyRegisteredFailure>()),
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Group 8 — acceptInvite
  // -------------------------------------------------------------------------

  group('acceptInvite', () {
    test('success → returns (User, AuthTokens)', () async {
      when(
        () => mockAuthApi.acceptInvite(
          inviteAcceptRequest: any(named: 'inviteAcceptRequest'),
        ),
      ).thenAnswer((_) async => _authResponse());

      final (user, tokens) = await repository.acceptInvite(
        token: 'invite-token-123',
        password: 'P@ssw0rd!',
        firstName: 'Іванна',
        lastName: 'Коваль',
        phoneNumber: '+380501111111',
      );

      expect(user.id, 'usr-1');
      expect(tokens.accessToken, 'access.jwt.token');
    });

    test('DioException → re-throws mapped Failure', () async {
      const failure = ValidationFailure(fieldErrors: {'token': 'invalid'});
      when(
        () => mockAuthApi.acceptInvite(
          inviteAcceptRequest: any(named: 'inviteAcceptRequest'),
        ),
      ).thenThrow(_dioWithFailure(failure));

      await expectLater(
        () => repository.acceptInvite(
          token: 'bad-token',
          password: 'pw',
          firstName: 'A',
          lastName: 'B',
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Group 9 — validateInvite
  // -------------------------------------------------------------------------

  group('validateInvite', () {
    test('success → returns InviteDetails with typed role', () async {
      final dto = InvitePreviewResponse(
        (b) => b
          ..invitedEmail = 'admin@salon.test'
          ..role = InvitePreviewResponseRoleEnum.SALON_ADMIN
          ..expiresAt = DateTime.utc(2030),
      );
      final envelope = ApiResponseInvitePreviewResponse(
        (b) => b
          ..success = true
          ..data = dto.toBuilder(),
      );
      final res = Response(
        data: envelope,
        statusCode: 200,
        requestOptions: _fakeOptions('/auth/invite/validate'),
      );

      when(
        () => mockAuthApi.validateInvite(token: any(named: 'token')),
      ).thenAnswer((_) async => res);

      final details = await repository.validateInvite(token: 'valid-token');

      expect(details.email, 'admin@salon.test');
      expect(details.role, UserRole.salonAdmin);
      expect(details.expiresAt, DateTime.utc(2030));
    });

    test('404 → remapped to ValidationFailure', () async {
      const failure = NotFoundFailure(cause: 'invite not found');
      when(
        () => mockAuthApi.validateInvite(token: any(named: 'token')),
      ).thenThrow(_dioWithFailure(failure, statusCode: 404));

      await expectLater(
        () => repository.validateInvite(token: 'dead-token'),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Group 10 — confirmPasswordReset (backend Phase 11.3) — HIGHEST PRIORITY
  //
  // The domain-significant behaviour here is the remap of a generic 400
  // (surfaced as ValidationFailure by ErrorMapperInterceptor) into the
  // dedicated [ResetTokenInvalidFailure] the forgot-password recovery screen
  // renders as its "link invalid or expired" state. If that remap is deleted
  // or made conditional, the screen silently shows the wrong (or no) error
  // state and account recovery breaks — these tests pin it.
  // -------------------------------------------------------------------------

  group('confirmPasswordReset', () {
    test('success (200) → completes without throwing; no auto-login', () async {
      final res = Response<ApiResponseVoid>(
        data: ApiResponseVoid((b) => b..success = true),
        statusCode: 200,
        requestOptions: _fakeOptions('/auth/reset-password'),
      );
      when(
        () => mockAuthApi.resetPassword(
          resetPasswordRequest: any(named: 'resetPasswordRequest'),
        ),
      ).thenAnswer((_) async => res);

      await expectLater(
        repository.confirmPasswordReset(
          resetTicket: 'valid-reset-ticket',
          newPassword: 'N3wP@ssw0rd!',
        ),
        completes,
      );
    });

    test(
      'forwards resetTicket + newPassword to ResetPasswordRequest (arg-match)',
      () async {
        // M4 strict arg-match: the happy-path tests above use any(named: ...),
        // so they would pass even if the wrong ticket / password reached the
        // wire. Capture the actual request and pin both fields — a regression
        // that swaps the args (or drops one) silently breaks account recovery.
        final res = Response<ApiResponseVoid>(
          data: ApiResponseVoid((b) => b..success = true),
          statusCode: 200,
          requestOptions: _fakeOptions('/auth/reset-password'),
        );
        when(
          () => mockAuthApi.resetPassword(
            resetPasswordRequest: any(named: 'resetPasswordRequest'),
          ),
        ).thenAnswer((_) async => res);

        await repository.confirmPasswordReset(
          resetTicket: 'reset-ticket-xyz',
          newPassword: 'N3wP@ssw0rd!',
        );

        final captured =
            verify(
                  () => mockAuthApi.resetPassword(
                    resetPasswordRequest: captureAny(
                      named: 'resetPasswordRequest',
                    ),
                  ),
                ).captured.single
                as ResetPasswordRequest;
        expect(captured.resetTicket, 'reset-ticket-xyz');
        expect(captured.newPassword, 'N3wP@ssw0rd!');
      },
    );

    test(
      'ValidationFailure (400) → remapped to ResetTokenInvalidFailure',
      () async {
        const failure = ValidationFailure(
          fieldErrors: {},
          cause: 'invalid or expired ticket',
        );
        when(
          () => mockAuthApi.resetPassword(
            resetPasswordRequest: any(named: 'resetPasswordRequest'),
          ),
        ).thenThrow(_dioWithFailure(failure, statusCode: 400));

        await expectLater(
          () => repository.confirmPasswordReset(
            resetTicket: 'used-or-expired-ticket',
            newPassword: 'N3wP@ssw0rd!',
          ),
          throwsA(isA<ResetTokenInvalidFailure>()),
        );
      },
    );

    test('non-ValidationFailure (e.g. NetworkFailure) → propagates unchanged, '
        'NOT remapped to ResetTokenInvalidFailure', () async {
      const failure = NetworkFailure();
      when(
        () => mockAuthApi.resetPassword(
          resetPasswordRequest: any(named: 'resetPasswordRequest'),
        ),
      ).thenThrow(_dioWithFailure(failure, statusCode: 503));

      await expectLater(
        () => repository.confirmPasswordReset(
          resetTicket: 'tok',
          newPassword: 'pw',
        ),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test(
      'raw DioException (no mapped Failure) → throws UnknownFailure',
      () async {
        when(
          () => mockAuthApi.resetPassword(
            resetPasswordRequest: any(named: 'resetPasswordRequest'),
          ),
        ).thenThrow(_rawDioException());

        await expectLater(
          () => repository.confirmPasswordReset(
            resetTicket: 'tok',
            newPassword: 'pw',
          ),
          throwsA(isA<UnknownFailure>()),
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Group 11 — requestPasswordReset (backend Phase 11.2)
  //
  // Contract pinned against the ACTUAL implementation: the anti-enumeration
  // "always 200" guarantee is enforced BACKEND-side. The repository does NOT
  // swallow errors — it forwards a successful call as a completed Future, and
  // re-throws a mapped [Failure] on a DioException. These tests pin that real
  // behaviour (no silent swallow at the repo layer).
  // -------------------------------------------------------------------------

  group('requestPasswordReset', () {
    test('success (200) → completes without throwing', () async {
      final res = Response<ApiResponseVoid>(
        data: ApiResponseVoid((b) => b..success = true),
        statusCode: 200,
        requestOptions: _fakeOptions('/auth/forgot-password'),
      );
      when(
        () => mockAuthApi.forgotPassword(
          forgotPasswordRequest: any(named: 'forgotPasswordRequest'),
        ),
      ).thenAnswer((_) async => res);

      await expectLater(
        repository.requestPasswordReset('known@beautica.test'),
        completes,
      );
    });

    test(
      'forwards the supplied email to ForgotPasswordRequest (arg-match)',
      () async {
        // The finding calls for asserting the email is forwarded correctly. The
        // happy-path test above only asserts completion with any(named: ...) —
        // it would pass even if the email were dropped or mangled. Capture the
        // request and pin the exact wire value.
        final res = Response<ApiResponseVoid>(
          data: ApiResponseVoid((b) => b..success = true),
          statusCode: 200,
          requestOptions: _fakeOptions('/auth/forgot-password'),
        );
        when(
          () => mockAuthApi.forgotPassword(
            forgotPasswordRequest: any(named: 'forgotPasswordRequest'),
          ),
        ).thenAnswer((_) async => res);

        await repository.requestPasswordReset('known@beautica.test');

        final captured =
            verify(
                  () => mockAuthApi.forgotPassword(
                    forgotPasswordRequest: captureAny(
                      named: 'forgotPasswordRequest',
                    ),
                  ),
                ).captured.single
                as ForgotPasswordRequest;
        expect(captured.email, 'known@beautica.test');
      },
    );

    test('DioException → re-throws mapped Failure (repo does NOT swallow; '
        'anti-enumeration is enforced backend-side, not here)', () async {
      const failure = NetworkFailure();
      when(
        () => mockAuthApi.forgotPassword(
          forgotPasswordRequest: any(named: 'forgotPasswordRequest'),
        ),
      ).thenThrow(_dioWithFailure(failure, statusCode: 503));

      await expectLater(
        () => repository.requestPasswordReset('x@beautica.test'),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test(
      'raw DioException (no mapped Failure) → throws UnknownFailure',
      () async {
        when(
          () => mockAuthApi.forgotPassword(
            forgotPasswordRequest: any(named: 'forgotPasswordRequest'),
          ),
        ).thenThrow(_rawDioException());

        await expectLater(
          () => repository.requestPasswordReset('x@beautica.test'),
          throwsA(isA<UnknownFailure>()),
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Group 11b — requestChangePasswordOtp (Beautica OTP task Phase A3 / B2)
  //
  // Authenticated entry point — no request body. Happy path completes; a
  // DioException surfaces as the mapped Failure (e.g. ResendThrottledFailure
  // on a 429, mapped by ErrorMapperInterceptor and not this repository).
  // -------------------------------------------------------------------------

  group('requestChangePasswordOtp', () {
    test('success (200) → completes without throwing', () async {
      final res = Response<ApiResponseVoid>(
        data: ApiResponseVoid((b) => b..success = true),
        statusCode: 200,
        requestOptions: _fakeOptions('/users/me/change-password/request-otp'),
      );
      when(
        () => mockUserApi.requestChangePasswordOtp(),
      ).thenAnswer((_) async => res);

      await expectLater(repository.requestChangePasswordOtp(), completes);
    });

    test('ResendThrottledFailure (429) → re-thrown unchanged', () async {
      const failure = ResendThrottledFailure(retryAfterSeconds: 42);
      when(
        () => mockUserApi.requestChangePasswordOtp(),
      ).thenThrow(_dioWithFailure(failure, statusCode: 429));

      await expectLater(
        () => repository.requestChangePasswordOtp(),
        throwsA(isA<ResendThrottledFailure>()),
      );
    });

    test(
      'raw DioException (no mapped Failure) → throws UnknownFailure',
      () async {
        when(
          () => mockUserApi.requestChangePasswordOtp(),
        ).thenThrow(_rawDioException());

        await expectLater(
          () => repository.requestChangePasswordOtp(),
          throwsA(isA<UnknownFailure>()),
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Group 11c — verifyPasswordResetOtp (Beautica OTP task Phase A3 / B2)
  //
  // Success returns the resetTicket string from the envelope. A typed 400
  // (data.code) is mapped by ErrorMapperInterceptor to PasswordResetOtpFailure
  // — this repository just re-throws whatever the interceptor attached.
  // -------------------------------------------------------------------------

  group('verifyPasswordResetOtp', () {
    Response<ApiResponseVerifyPasswordResetOtpResponse> okResponse({
      String resetTicket = 'raw-reset-ticket',
    }) {
      final dto = VerifyPasswordResetOtpResponse(
        (b) => b..resetTicket = resetTicket,
      );
      final envelope = ApiResponseVerifyPasswordResetOtpResponse(
        (b) => b
          ..success = true
          ..data = dto.toBuilder(),
      );
      return Response(
        data: envelope,
        statusCode: 200,
        requestOptions: _fakeOptions('/auth/verify-password-reset-otp'),
      );
    }

    test('success (200) → returns resetTicket from the envelope', () async {
      when(
        () => mockAuthApi.verifyPasswordResetOtp(
          verifyPasswordResetOtpRequest: any(
            named: 'verifyPasswordResetOtpRequest',
          ),
        ),
      ).thenAnswer((_) async => okResponse(resetTicket: 'ticket-abc-123'));

      final ticket = await repository.verifyPasswordResetOtp(
        email: 'anya@example.com',
        code: '123456',
      );

      expect(ticket, 'ticket-abc-123');
    });

    test(
      'forwards email + code to VerifyPasswordResetOtpRequest (arg-match)',
      () async {
        when(
          () => mockAuthApi.verifyPasswordResetOtp(
            verifyPasswordResetOtpRequest: any(
              named: 'verifyPasswordResetOtpRequest',
            ),
          ),
        ).thenAnswer((_) async => okResponse());

        await repository.verifyPasswordResetOtp(
          email: 'anya@example.com',
          code: '654321',
        );

        final captured =
            verify(
                  () => mockAuthApi.verifyPasswordResetOtp(
                    verifyPasswordResetOtpRequest: captureAny(
                      named: 'verifyPasswordResetOtpRequest',
                    ),
                  ),
                ).captured.single
                as VerifyPasswordResetOtpRequest;
        expect(captured.email, 'anya@example.com');
        expect(captured.code, '654321');
      },
    );

    test(
      'PasswordResetOtpFailure (400, typed) → re-thrown unchanged',
      () async {
        const failure = PasswordResetOtpFailure(
          code: PasswordResetOtpErrorCode.invalidCode,
        );
        when(
          () => mockAuthApi.verifyPasswordResetOtp(
            verifyPasswordResetOtpRequest: any(
              named: 'verifyPasswordResetOtpRequest',
            ),
          ),
        ).thenThrow(_dioWithFailure(failure, statusCode: 400));

        await expectLater(
          () => repository.verifyPasswordResetOtp(
            email: 'anya@example.com',
            code: '000000',
          ),
          throwsA(isA<PasswordResetOtpFailure>()),
        );
      },
    );

    test(
      'raw DioException (no mapped Failure) → throws UnknownFailure',
      () async {
        when(
          () => mockAuthApi.verifyPasswordResetOtp(
            verifyPasswordResetOtpRequest: any(
              named: 'verifyPasswordResetOtpRequest',
            ),
          ),
        ).thenThrow(_rawDioException());

        await expectLater(
          () => repository.verifyPasswordResetOtp(
            email: 'anya@example.com',
            code: '000000',
          ),
          throwsA(isA<UnknownFailure>()),
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Group 12 — resendVerificationCode (backend Phase 1.6)
  //
  // Returns void; the mobile layer needs no field from the body. Happy path
  // completes; a DioException surfaces as the mapped Failure.
  // -------------------------------------------------------------------------

  group('resendVerificationCode', () {
    test('success (200) → completes without throwing', () async {
      final res = Response<ApiResponseRegistrationResponse>(
        data: ApiResponseRegistrationResponse((b) => b..success = true),
        statusCode: 200,
        requestOptions: _fakeOptions('/auth/resend-verification'),
      );
      when(
        () => mockAuthApi.resendVerification(
          resendVerificationRequest: any(named: 'resendVerificationRequest'),
        ),
      ).thenAnswer((_) async => res);

      await expectLater(
        repository.resendVerificationCode(email: 'master@beautica.test'),
        completes,
      );
    });

    test('DioException → re-throws mapped Failure', () async {
      const failure = ValidationFailure(fieldErrors: {'email': 'unknown'});
      when(
        () => mockAuthApi.resendVerification(
          resendVerificationRequest: any(named: 'resendVerificationRequest'),
        ),
      ).thenThrow(_dioWithFailure(failure, statusCode: 400));

      await expectLater(
        () => repository.resendVerificationCode(email: 'x@beautica.test'),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test(
      'raw DioException (no mapped Failure) → throws UnknownFailure',
      () async {
        when(
          () => mockAuthApi.resendVerification(
            resendVerificationRequest: any(named: 'resendVerificationRequest'),
          ),
        ).thenThrow(_rawDioException());

        await expectLater(
          () => repository.resendVerificationCode(email: 'x@beautica.test'),
          throwsA(isA<UnknownFailure>()),
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Group 13 — logout (best-effort server call)
  //
  // Pinned against the ACTUAL implementation: HttpAuthRepository.logout() makes
  // a best-effort POST /auth/logout and SWALLOWS any DioException so the caller
  // can unconditionally wipe local storage afterwards. NOTE: this repository
  // layer does NOT touch flutter_secure_storage itself — token clearing is the
  // caller's (notifier's) responsibility (see source comment, line ~275). So
  // the storage-clear assertion belongs in a notifier-level test, tracked as a
  // backlog gap below. Here we pin: (a) network failure does not propagate,
  // (b) the server call IS still attempted exactly once.
  // -------------------------------------------------------------------------

  group('logout', () {
    test(
      'network failure on POST /auth/logout → does NOT propagate (swallowed)',
      () async {
        when(() => mockAuthApi.logout()).thenThrow(
          DioException(
            requestOptions: _fakeOptions('/auth/logout'),
            type: DioExceptionType.connectionError,
          ),
        );

        await expectLater(repository.logout(), completes);
      },
    );

    test('4xx DioException on logout → swallowed (still completes)', () async {
      const failure = UnauthorizedFailure();
      when(
        () => mockAuthApi.logout(),
      ).thenThrow(_dioWithFailure(failure, statusCode: 401));

      await expectLater(repository.logout(), completes);
    });

    test('success → server logout invoked exactly once', () async {
      final res = Response<void>(
        statusCode: 200,
        requestOptions: _fakeOptions('/auth/logout'),
      );
      when(() => mockAuthApi.logout()).thenAnswer((_) async => res);

      await repository.logout();

      verify(() => mockAuthApi.logout()).called(1);
    });

    test(
      'server logout still attempted even though the call will fail (best-effort)',
      () async {
        when(() => mockAuthApi.logout()).thenThrow(
          DioException(
            requestOptions: _fakeOptions('/auth/logout'),
            type: DioExceptionType.connectionError,
          ),
        );

        await repository.logout();

        // The server call is made unconditionally; swallowing the error must
        // not skip the network attempt (otherwise sessions never get
        // server-side invalidated when the network later recovers).
        verify(() => mockAuthApi.logout()).called(1);
      },
    );
  });
}
