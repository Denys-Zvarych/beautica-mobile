// TODO(phase-3.2): replace hand-written DTOs with imports from lib/api/ (generated AuthApi).
//
// Phase 2.3 — HttpAuthRepository.
// Phase 2.8 — Added SecureStorage injection + logout() implementation.
//
// Concrete implementation of [AuthRepository] backed by the Beautica backend
// REST API. Uses the singleton [dioProvider] Dio instance which carries the
// full interceptor chain (Auth → Log → ErrorMapper → Refresh).
//
// Backend response envelope for all endpoints:
//   { "success": bool, "data": T, "message": String }
//
// This class extracts `data` from `response.data['data']`. Field-level
// naming follows the backend DTOs as of Phase 2.x; Phase 3.2 will replace
// these raw Map accesses with generated type-safe API classes.

import 'dart:async';
import 'dart:developer';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/storage/secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../domain/auth_tokens.dart';
import '../domain/invite_details.dart';
import '../domain/register_result.dart';
import '../domain/user.dart';
import '../domain/user_role.dart';
import 'auth_repository.dart';

/// HTTP implementation of [AuthRepository].
///
/// Inject via [authRepositoryProvider] — never construct directly.
final class HttpAuthRepository implements AuthRepository {
  HttpAuthRepository(this._dio, this._storage);

  final Dio _dio;

  /// Used exclusively by [logout] to read the current refresh token so it can
  /// be revoked on the backend. Never used for access tokens.
  final SecureStorage _storage;

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
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
      return _parseUserAndTokens(response.data!);
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'login failed: ${e.type} ${e.response?.statusCode}',
          name: 'auth.repository',
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
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
    //     Body: { email, password, firstName, lastName, phoneNumber? }
    //     Note: no `role` field; backend derives it from the path.
    //
    //   CLIENT → POST /auth/register
    //     Body: { email, password, role, firstName, lastName }
    //
    //   SALON_OWNER → POST /auth/register
    //     Body: { email, password, role, firstName, lastName, businessName?,
    //             address?, phoneNumber? }
    //     Note: `businessName` is REQUIRED when role == SALON_OWNER.
    //     Note: firstName/lastName are sent as empty strings for salon owners
    //           because the backend schema still requires the fields; the
    //           meaningful identity for a salon owner is businessName + address.
    try {
      final Response<Map<String, dynamic>> response;

      if (role == UserRole.independentMaster) {
        // Phone is now required for all roles (Change 7).
        // Use a local trimmed variable to avoid calling .trim() twice
        // (backlog pattern 5).
        final trimmedPhone = phone?.trim();
        final imBody = <String, dynamic>{
          'email': email,
          'password': password,
          'firstName': firstName,
          'lastName': lastName,
        };
        if (trimmedPhone != null && trimmedPhone.isNotEmpty) {
          imBody['phoneNumber'] = trimmedPhone;
        }
        response = await _dio.post<Map<String, dynamic>>(
          '/auth/register/independent-master',
          data: imBody,
        );
      } else {
        final body = <String, dynamic>{
          'email': email,
          'password': password,
          'role': role.toWire,
          // For salon owners firstName/lastName come from the notifier as empty
          // strings (the UI no longer collects them); include them so the
          // backend schema remains satisfied.
          'firstName': firstName,
          'lastName': lastName,
        };
        // Include businessName only when it is non-null and non-blank.
        // Backend enforces its presence for SALON_OWNER with a 400.
        // Use a local trimmed variable to avoid calling .trim() twice
        // (backlog pattern 5).
        final trimmedBusiness = businessName?.trim();
        if (trimmedBusiness != null && trimmedBusiness.isNotEmpty) {
          body['businessName'] = trimmedBusiness;
        }
        // Optional salon details — included only when provided.
        final trimmedAddress = address?.trim();
        if (trimmedAddress != null && trimmedAddress.isNotEmpty) {
          body['address'] = trimmedAddress;
        }
        // Phone is now included for all roles (Change 7), including CLIENT.
        final trimmedPhone = phone?.trim();
        if (trimmedPhone != null && trimmedPhone.isNotEmpty) {
          body['phoneNumber'] = trimmedPhone;
        }
        response = await _dio.post<Map<String, dynamic>>(
          '/auth/register',
          data: body,
        );
      }

      return _parseRegisterResult(response.data!);
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
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final data = response.data!['data'] as Map<String, dynamic>;
      final result = AuthTokens(
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
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
      final response = await _dio.get<Map<String, dynamic>>('/user/me');
      final data = response.data!['data'] as Map<String, dynamic>;
      return User.fromJson(data);
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
    final rt = await _storage.readRefreshToken();
    if (rt == null) return; // nothing to revoke

    try {
      await _dio.post<void>('/auth/logout', data: {'refreshToken': rt});
    } on DioException catch (e) {
      // Best-effort: 4xx / network errors are intentionally swallowed.
      // The caller wipes local storage unconditionally after this returns.
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
  ///   Success:  `ApiResponse<AuthResponse>` flat envelope with `data.{userId,
  ///             email, role, accessToken, refreshToken, tokenType}` — identical
  ///             shape to /auth/login.
  ///   400:      `{success:false, data:{code:"INVALID_CODE"|"CODE_EXPIRED"|
  ///             "ALREADY_VERIFIED"}}` — mapped to [VerificationFailure] by
  ///             [ErrorMapperInterceptor] before reaching this catch block.
  ///
  /// On success the user is fully authenticated — the caller persists the
  /// refresh token and transitions to the home shell via the redirect.
  @override
  Future<(User, AuthTokens)> verifyEmail({
    required String email,
    required String otp,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/verify-email',
        data: {'email': email, 'code': otp},
      );
      return _parseUserAndTokens(response.data!);
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
  /// Backend Phase 1.6 contract (locked):
  ///   Request:  `{"email": "..."}`
  ///   Success:  `ApiResponse<RegistrationResponse>` — `data.{message, email}`.
  ///             The mobile layer does not need any field from the body, so
  ///             the method returns `void`.
  ///   429:      `{success:false, message:"...", data:{retryAfterSeconds:N}}`
  ///             — mapped to [ResendThrottledFailure] by [ErrorMapperInterceptor].
  @override
  Future<void> resendVerificationCode({required String email}) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/auth/resend-verification',
        data: {'email': email},
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
  /// Backend Phase 11.2 contract (locked): ALWAYS returns a generic 200 with
  /// `{success:true, data:null, message:"If an account exists…"}` regardless
  /// of whether the email is known — anti-enumeration. The body carries no
  /// data the mobile layer needs, so this returns `void`. Only genuine
  /// transport / server errors propagate (so the screen can offer a retry).
  ///
  /// SECURITY: the request body (`{email}`) is redacted by [LoggingInterceptor]
  /// because `/auth/forgot-password` is in [kAuthPaths]. The debug log here
  /// carries only the Dio exception type + status — never the raw exception
  /// (its `toString()` includes the request body / email).
  @override
  Future<void> requestPasswordReset(String email) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/auth/forgot-password',
        data: {'email': email},
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
  /// Backend Phase 11.3 contract (locked):
  ///   Request:  `{"token": "<raw token>", "newPassword": "..."}`
  ///   Success:  generic 200, NO session issued (no auto-login by design).
  ///   400:      a single byte-identical generic envelope for invalid / used /
  ///             expired tokens (no oracle). [ErrorMapperInterceptor] maps the
  ///             400 to a [ValidationFailure] with empty `fieldErrors`; here we
  ///             translate that into the dedicated [ResetTokenInvalidFailure]
  ///             so the screen renders its "link invalid or expired" state.
  ///
  /// SECURITY: the request body carries the single-use reset token + the new
  /// password — both PII. `/auth/reset-password` is in [kAuthPaths] so the
  /// body is redacted by [LoggingInterceptor]; the debug log here is sanitised
  /// to the Dio type + status only.
  @override
  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/auth/reset-password',
        data: {'token': token, 'newPassword': newPassword},
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
      // The interceptor surfaces that as a ValidationFailure (no field errors);
      // re-map it to the dedicated invalid-token failure the screen renders as
      // its recovery state. Other failures (network / 5xx / unknown) pass
      // through unchanged so the screen shows a generic retryable error.
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
  /// Backend response (inside the standard ApiResponse envelope):
  ///   `{ "invitedEmail": "...", "role": "SALON_ADMIN|SALON_MASTER",
  ///      "expiresAt": "2025-01-01T12:00:00Z" }`
  ///
  /// Maps 400 / 404 → [ValidationFailure] so the screen can render its
  /// invalid-token state without branching on raw status codes.
  @override
  Future<InviteDetails> validateInvite({required String token}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/auth/invite/validate',
        queryParameters: <String, dynamic>{'token': token},
      );
      final data = response.data!['data'] as Map<String, dynamic>;
      final roleRaw = data['role'] as String;
      final UserRole role;
      try {
        role = UserRole.fromWire(roleRaw);
      } catch (_) {
        throw const UnknownFailure(cause: 'invite validate: unknown role');
      }
      return InviteDetails(
        email: data['invitedEmail'] as String,
        role: role,
        expiresAt: DateTime.parse(data['expiresAt'] as String),
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
      // 400 / 404 from the backend mean "invalid or expired invite" — both
      // surface as ValidationFailure (the interceptor maps 400 to Validation
      // and 404 to NotFound; we normalise both to ValidationFailure here so
      // the notifier and screen only need to handle one type).
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
  /// Backend request body: `{ token, password, firstName, lastName,
  ///   phoneNumber? }`. The response envelope is identical to `/auth/login`:
  ///   `{ "data": { "userId": "...", "email": "...", "role": "...",
  ///     "accessToken": "...", "refreshToken": "...", "tokenType": "Bearer" } }`
  ///
  /// SECURITY: the request body carries the single-use invite token plus
  /// the new password — both are PII. `/auth/invite/accept` is redacted by
  /// [LoggingInterceptor] (it starts with `/auth/`). Debug logs here are
  /// sanitised to Dio type + status only.
  @override
  Future<(User, AuthTokens)> acceptInvite({
    required String token,
    required String password,
    required String firstName,
    required String lastName,
    String? phoneNumber,
  }) async {
    try {
      final body = <String, dynamic>{
        'token': token,
        'password': password,
        'firstName': firstName,
        'lastName': lastName,
      };
      final trimmedPhone = phoneNumber?.trim();
      if (trimmedPhone != null && trimmedPhone.isNotEmpty) {
        body['phoneNumber'] = trimmedPhone;
      }
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/invite/accept',
        data: body,
      );
      return _parseUserAndTokens(response.data!);
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

  /// Extracts the flat `AuthResponse` shape from the backend envelope and
  /// returns the domain tuple.
  ///
  /// The backend serialises [AuthResponse] flat — `userId`, `email`, `role`,
  /// `accessToken` and `refreshToken` are all siblings at the top level of
  /// `data`. There is no nested `user` object.
  (User, AuthTokens) _parseUserAndTokens(Map<String, dynamic> envelope) {
    final data = envelope['data'] as Map<String, dynamic>;
    // Build User from flat AuthResponse fields.
    // Backend uses 'userId' not 'id'; firstName/lastName are not in AuthResponse.
    final user = User(
      id: data['userId'] as String,
      email: data['email'] as String,
      role: UserRole.fromWire(data['role'] as String),
    );
    final tokens = AuthTokens(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
    );
    return (user, tokens);
  }

  /// Inspects the registration response envelope and dispatches to the
  /// appropriate [RegisterResult] variant.
  ///
  /// The backend currently returns a verification-required envelope by
  /// default:
  ///   { "success": true, "data": { "message": "...", "email": "..." } }
  /// Auto-login responses (when email verification is not required) carry the
  /// flat [AuthResponse] session payload detected by the presence of
  /// `accessToken`:
  ///   { "success": true, "data": { "userId": "...", "email": "...",
  ///     "role": "...", "accessToken": "...", "refreshToken": "...",
  ///     "tokenType": "Bearer" } }
  ///
  /// Anything else (no `data`, or a `data` block missing both `email` and
  /// `accessToken`) is genuinely wrong — we throw [UnknownFailure] so the
  /// screen surfaces a snackbar instead of crashing with a generic cast error.
  RegisterResult _parseRegisterResult(Map<String, dynamic> envelope) {
    final data = envelope['data'];
    if (data is! Map<String, dynamic>) {
      throw const UnknownFailure(
        cause: 'register response missing "data" object',
      );
    }
    // Auto-login path — detected by the presence of accessToken in the flat
    // AuthResponse. The old nested `data['user']` check is no longer valid
    // because the backend serialises a flat shape (no nested user object).
    if (data['accessToken'] is String) {
      final (user, tokens) = _parseUserAndTokens(envelope);
      return RegisterResult.authenticated(user: user, tokens: tokens);
    }
    // Verification-required (current default) — only the email comes back.
    final email = data['email'];
    if (email is String && email.isNotEmpty) {
      return RegisterResult.verificationRequired(email: email);
    }
    throw const UnknownFailure(
      cause: 'unexpected register response shape (no user, no email)',
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
