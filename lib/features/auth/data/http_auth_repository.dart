// Phase 3.2 — HttpAuthRepository re-pointed to generated API classes.
//
// Replaces all raw _dio.post/get calls with type-safe generated API methods
// from [AuthControllerApi] and [UserControllerApi]. The domain-level Failure
// hierarchy, X-No-Retry headers, and _pendingRefresh Completer pattern are
// preserved verbatim from Phase 2.x.
//
// HIGH-1 (mobile-security 2026-05-24): refresh() and me() pass
// headers: {'X-No-Retry': 'true'} to the generated API methods so
// RefreshInterceptor cannot re-intercept a failed /auth/refresh 401 and
// issue a second refresh with the same expired token (double-refresh loop).
// The header is forwarded into Dio's Options.headers by the generated code.
//
// Backend response envelope for all endpoints:
//   { "success": bool, "data": T, "message": String }
// The generated deserialization unwraps the outer envelope; the payload is
// accessed via response.data!.data!.

import 'dart:async';
import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../domain/auth_tokens.dart';
import '../domain/invite_details.dart';
import '../domain/register_result.dart';
import '../domain/user.dart';
import '../domain/user_role.dart';
import 'auth_repository.dart';
import 'user_mapper.dart';

/// HTTP implementation of [AuthRepository] backed by generated API classes.
///
/// Inject via [authRepositoryProvider] — never construct directly.
final class HttpAuthRepository implements AuthRepository {
  HttpAuthRepository(this._authApi, this._userApi);

  final AuthControllerApi _authApi;
  final UserControllerApi _userApi;

  /// Guards against concurrent refresh races: if a refresh call is already
  /// in-flight, subsequent callers await the same [Completer] instead of
  /// issuing duplicate network requests.
  Completer<AuthTokens>? _pendingRefresh;

  // ---------------------------------------------------------------------------
  // AuthRepository
  // ---------------------------------------------------------------------------

  @override
  Future<(User, AuthTokens)> login({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _authApi.login(
        loginRequest: LoginRequest(
          (b) => b
            ..email = email
            ..password = password,
        ),
      );
      final dto = res.data!.data!;
      final tokens = AuthTokens(
        accessToken: dto.accessToken!,
        refreshToken: dto.refreshToken!,
      );
      final user = UserMapper.fromAuthResponse(dto);
      // A 401 on /auth/login means wrong credentials, not a session expiry.
      // The user has no session at this point — the server rejected the supplied
      // email/password. The remap to [InvalidCredentialsFailure] is done in the
      // DioException catch below; this path only executes on 2xx.
      return (user, tokens);
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'login failed: ${e.type} ${e.response?.statusCode}',
          name: 'auth.repository',
          level: 900,
          stackTrace: st,
        );
      }
      final failure = _mapDioException(e);
      // EMAIL_NOT_VERIFIED (emailNotVerified == true) is intentionally excluded
      // from this remap — that sub-code triggers the inline AuthBanner flow in
      // [LoginScreen], which must receive [UnauthorizedFailure] to branch
      // correctly on `e.emailNotVerified`.
      if (failure is UnauthorizedFailure && !failure.emailNotVerified) {
        throw InvalidCredentialsFailure(cause: failure.cause);
      }
      throw failure;
    }
  }

  @override
  Future<RegisterResult> registerIndependentMaster({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    UserRole role = UserRole.independentMaster,
    String? businessName,
    String? address,
    String? phone,
  }) async {
    // Backend contract:
    //   INDEPENDENT_MASTER → POST /auth/register/independent-master
    //     Body: { email, password, firstName, lastName, phoneNumber }
    //     Note: no `role` field; backend derives it from the path.
    //
    //   CLIENT → POST /auth/register
    //     Body: { email, password, role, firstName, lastName, phoneNumber }
    //
    //   SALON_OWNER → POST /auth/register
    //     Body: { email, password, role, firstName, lastName, phoneNumber,
    //             businessName? }
    //     Note: `businessName` is REQUIRED when role == SALON_OWNER.
    //     Note: firstName/lastName are sent as empty strings for salon owners
    //           because the backend schema still requires the fields; the
    //           meaningful identity for a salon owner is businessName.
    //
    // The generated request models require phoneNumber (non-nullable). When
    // the caller provides no phone, an empty string is sent as the wire value —
    // this matches the existing raw-Dio behaviour (the field was conditional).
    // The backend validates and rejects blank phones only for certain roles.
    try {
      if (role == UserRole.independentMaster) {
        final trimmedPhone = phone?.trim() ?? '';
        final res = await _authApi.registerIndependentMaster(
          registerIndependentMasterRequest: RegisterIndependentMasterRequest(
            (b) => b
              ..email = email
              ..password = password
              ..firstName = firstName
              ..lastName = lastName
              ..phoneNumber = trimmedPhone,
          ),
        );
        return _parseRegisterResultFromResponse(
          res.data?.data?.message,
          res.data?.data?.email,
          res.data?.data,
        );
      } else {
        final trimmedPhone = phone?.trim() ?? '';
        final trimmedBusiness = businessName?.trim();
        final wireRole = switch (role) {
          UserRole.client => RegisterRequestRoleEnum.CLIENT,
          UserRole.salonOwner => RegisterRequestRoleEnum.SALON_OWNER,
          // Only CLIENT and SALON_OWNER can self-register via this path.
          _ => throw const UnknownFailure(
            cause: 'registerIndependentMaster: unsupported role for /register',
          ),
        };
        final res = await _authApi.register(
          registerRequest: RegisterRequest(
            (b) => b
              ..email = email
              ..password = password
              ..role = wireRole
              ..firstName = firstName
              ..lastName = lastName
              ..phoneNumber = trimmedPhone
              ..businessName = trimmedBusiness,
          ),
        );
        return _parseRegisterResultFromResponse(
          res.data?.data?.message,
          res.data?.data?.email,
          res.data?.data,
        );
      }
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'register failed (role=${role.toWire}): ${e.type} ${e.response?.statusCode}',
          name: 'auth.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    // If a refresh is already in-flight, reuse its result rather than
    // issuing a duplicate request (e.g. two expired requests racing).
    if (_pendingRefresh != null) return _pendingRefresh!.future;

    _pendingRefresh = Completer<AuthTokens>();
    try {
      // HIGH-1 (mobile-security 2026-05-24): X-No-Retry prevents
      // RefreshInterceptor from re-intercepting a 401 response from
      // /auth/refresh and issuing a redundant second refresh with the
      // same already-expired token. The header is checked by
      // RefreshInterceptor.onError() before attempting any refresh.
      final res = await _authApi.refresh(
        refreshRequest: RefreshRequest((b) => b..refreshToken = refreshToken),
        headers: const {'X-No-Retry': 'true'},
      );
      final dto = res.data!.data!;
      final result = AuthTokens(
        accessToken: dto.accessToken!,
        refreshToken: dto.refreshToken!,
      );
      _pendingRefresh!.complete(result);
      return result;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'refresh failed',
          name: 'auth.repository',
          level: 1000,
          error: '${e.type} ${e.response?.statusCode}',
          stackTrace: st,
        );
      }
      final failure = _mapDioException(e);
      _pendingRefresh!.completeError(failure, st);
      throw failure;
    } finally {
      _pendingRefresh = null;
    }
  }

  @override
  Future<User> me() async {
    try {
      // MEDIUM fix (mobile-security): X-No-Retry prevents RefreshInterceptor
      // from intercepting a 401 on /users/me and issuing a second refresh when
      // me() is called right after obtaining a fresh access token (e.g. during
      // login or verifyEmail). Without this header a clock-skew / split-brain
      // 401 on /users/me would destroy the just-created session via logout().
      // Every call to me() carries a fresh token that must not be refreshed
      // again — the flag is unconditional, matching the pattern in refresh().
      final res = await _userApi.getMe(headers: const {'X-No-Retry': 'true'});
      return UserMapper.fromProfileDto(res.data!.data!);
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'me failed',
          name: 'auth.repository',
          level: 1000,
          error: '${e.type} ${e.response?.statusCode}',
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<void> logout() async {
    // The generated logout() sends POST /auth/logout with no request body.
    // Session identification is handled by the Authorization: Bearer header
    // injected by AuthInterceptor — the backend reads the token from there.
    // Best-effort: any network / 4xx error is intentionally swallowed because
    // the caller always wipes local storage unconditionally after this returns.
    try {
      await _authApi.logout();
    } on DioException catch (e) {
      if (kDebugMode) {
        log(
          'logout server call failed (tolerated): ${e.type} ${e.response?.statusCode}',
          name: 'auth.repository',
          level: 900,
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // OTP / email verification — backend Phase 1.5 + 1.6
  // ---------------------------------------------------------------------------

  /// Posts the 6-digit [otp] to `POST /api/v1/auth/verify-email`.
  ///
  /// Backend Phase 1.5 contract (locked):
  ///   Request:  `{"email": "...", "code": "123456"}`  — wire field is `code`,
  ///             not `otp`. The mobile param name stays `otp` to match the
  ///             HTML mockup vocabulary; only the body field is `code`.
  ///   Success:  `ApiResponse<AuthResponse>` flat envelope — identical shape
  ///             to /auth/login.
  @override
  Future<(User, AuthTokens)> verifyEmail({
    required String email,
    required String otp,
  }) async {
    try {
      final res = await _authApi.verifyEmail(
        verifyEmailRequest: VerifyEmailRequest(
          (b) => b
            ..email = email
            ..code = otp,
        ),
      );
      final dto = res.data!.data!;
      return (
        UserMapper.fromAuthResponse(dto),
        AuthTokens(
          accessToken: dto.accessToken!,
          refreshToken: dto.refreshToken!,
        ),
      );
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'verifyEmail failed: ${e.type} ${e.response?.statusCode}',
          name: 'auth.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  /// Posts to `POST /api/v1/auth/resend-verification`.
  ///
  /// Backend Phase 1.6 contract (locked): returns void — the mobile layer
  /// does not need any field from the body.
  @override
  Future<void> resendVerificationCode({required String email}) async {
    try {
      await _authApi.resendVerification(
        resendVerificationRequest: ResendVerificationRequest(
          (b) => b..email = email,
        ),
      );
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'resendVerificationCode failed: ${e.type} ${e.response?.statusCode}',
          name: 'auth.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  // ---------------------------------------------------------------------------
  // Password reset — backend Phase 11.2 (request) + 11.3 (confirm)
  // ---------------------------------------------------------------------------

  /// Posts to `POST /auth/forgot-password`.
  ///
  /// Backend Phase 11.2 contract (locked): ALWAYS returns a generic 200
  /// regardless of whether the email is known — anti-enumeration.
  ///
  /// SECURITY: the request body (`{email}`) is redacted by [LoggingInterceptor]
  /// because `/auth/forgot-password` is in [kAuthPaths].
  @override
  Future<void> requestPasswordReset(String email) async {
    try {
      await _authApi.forgotPassword(
        forgotPasswordRequest: ForgotPasswordRequest((b) => b..email = email),
      );
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'requestPasswordReset failed: ${e.type} ${e.response?.statusCode}',
          name: 'auth.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  /// Posts to `POST /auth/reset-password`.
  ///
  /// Backend Phase 11.3 contract (locked): success → generic 200; no
  /// auto-login by design. 400 → mapped to [ResetTokenInvalidFailure] so
  /// the screen renders its "link invalid or expired" state.
  ///
  /// SECURITY: the request body carries the single-use reset token + the new
  /// password — both PII. `/auth/reset-password` is redacted by
  /// [LoggingInterceptor]; debug logs here are sanitised to Dio type + status.
  @override
  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) async {
    try {
      await _authApi.resetPassword(
        resetPasswordRequest: ResetPasswordRequest(
          (b) => b
            ..token = token
            ..newPassword = newPassword,
        ),
      );
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'confirmPasswordReset failed: ${e.type} ${e.response?.statusCode}',
          name: 'auth.repository',
          level: 900,
          stackTrace: st,
        );
      }
      final failure = _mapDioException(e);
      // The backend returns a generic 400 for invalid / used / expired tokens.
      // The interceptor surfaces that as a ValidationFailure; re-map it to the
      // dedicated invalid-token failure the screen renders as its recovery state.
      if (failure is ValidationFailure) {
        throw ResetTokenInvalidFailure(cause: failure.cause);
      }
      throw failure;
    }
  }

  // ---------------------------------------------------------------------------
  // Invite flow — backend Phase 2.20
  // ---------------------------------------------------------------------------

  /// Validates an invite token against `GET /auth/invite/validate?token=<token>`.
  ///
  /// The generated API returns [ApiResponseInvitePreviewResponse] with
  /// [InvitePreviewResponse] as the payload. The role is a typed
  /// [InvitePreviewResponseRoleEnum] whose [name] is the wire string.
  @override
  Future<InviteDetails> validateInvite({required String token}) async {
    try {
      final res = await _authApi.validateInvite(token: token);
      final dto = res.data!.data!;
      final UserRole role;
      try {
        role = UserRole.fromWire(dto.role!.name);
      } catch (_) {
        throw const UnknownFailure(cause: 'invite validate: unknown role');
      }
      return InviteDetails(
        email: dto.invitedEmail!,
        role: role,
        expiresAt: dto.expiresAt!,
      );
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'validateInvite failed: ${e.type} ${e.response?.statusCode}',
          name: 'auth.repository',
          level: 900,
          stackTrace: st,
        );
      }
      final failure = _mapDioException(e);
      // 400 / 404 from the backend mean "invalid or expired invite" — normalise
      // both to ValidationFailure so notifier and screen handle one type only.
      if (failure is NotFoundFailure) {
        throw ValidationFailure(
          fieldErrors: const <String, String>{},
          cause: failure.cause,
        );
      }
      throw failure;
    }
  }

  /// Accepts an invite via `POST /auth/invite/accept`.
  ///
  /// SECURITY: the request body carries the single-use invite token plus
  /// the new password — both are PII. `/auth/invite/accept` is redacted by
  /// [LoggingInterceptor] (starts with `/auth/`). Debug logs are sanitised.
  @override
  Future<(User, AuthTokens)> acceptInvite({
    required String token,
    required String password,
    required String firstName,
    required String lastName,
    String? phoneNumber,
  }) async {
    try {
      final trimmedPhone = phoneNumber?.trim() ?? '';
      final res = await _authApi.acceptInvite(
        inviteAcceptRequest: InviteAcceptRequest(
          (b) => b
            ..token = token
            ..password = password
            ..firstName = firstName
            ..lastName = lastName
            ..phoneNumber = trimmedPhone,
        ),
      );
      final dto = res.data!.data!;
      return (
        UserMapper.fromAuthResponse(dto),
        AuthTokens(
          accessToken: dto.accessToken!,
          refreshToken: dto.refreshToken!,
        ),
      );
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'acceptInvite failed: ${e.type} ${e.response?.statusCode}',
          name: 'auth.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Inspects a registration response payload and returns the appropriate
  /// [RegisterResult] variant.
  ///
  /// The backend returns two shapes:
  ///   Verification-required (current default):
  ///     data contains { message, email }
  ///   Auto-login (when email verification is not required):
  ///     data contains { userId, email, role, accessToken, refreshToken, … }
  ///
  /// The generated [RegistrationResponse] only has [message] and [email],
  /// so the auto-login path is not reachable via this branch — the backend
  /// currently always returns verification-required for new registrations.
  /// The auto-login guard is kept for forward-compatibility.
  RegisterResult _parseRegisterResultFromResponse(
    String? message,
    String? email,
    Object? data,
  ) {
    if (email != null && email.isNotEmpty) {
      return RegisterResult.verificationRequired(email: email);
    }
    throw const UnknownFailure(
      cause: 'unexpected register response shape (no email)',
    );
  }

  /// Maps a [DioException] to a typed [Failure].
  ///
  /// If [ErrorMapperInterceptor] has already attached a [Failure] as
  /// `e.error`, that value is re-thrown directly. Otherwise a catch-all
  /// [UnknownFailure] is returned. Raw [DioException] must never escape this
  /// class.
  Failure _mapDioException(DioException e) {
    if (e.error is Failure) return e.error as Failure;
    return UnknownFailure(cause: e);
  }
}
