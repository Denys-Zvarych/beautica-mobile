// Phase 2.3 — AuthRepository interface.
//
// Abstract contract for the auth data layer. The concrete implementation
// ([HttpAuthRepository]) is hidden behind this interface so that tests can
// swap in a fake without depending on Dio or the real backend.
//
// The only allowed imports are domain models — no Flutter, no Dio, no
// platform packages. This keeps the interface a pure-Dart declaration.

import '../domain/auth_tokens.dart';
import '../domain/invite_details.dart';
import '../domain/register_result.dart';
import '../domain/user.dart';
import '../domain/user_role.dart';

/// Contract for all authentication and session-related API interactions.
///
/// Every method either resolves with the requested value or throws a [Failure]
/// subclass from `core/errors/failures.dart`. Raw exceptions (e.g.
/// [DioException]) must never escape — they are caught inside the
/// implementation.
abstract interface class AuthRepository {
  /// Authenticates a user with [email] and [password].
  ///
  /// Returns a tuple of the authenticated [User] and the issued [AuthTokens]
  /// on success.
  ///
  /// Throws:
  /// - [UnauthorizedFailure] — wrong credentials (401).
  /// - [ValidationFailure] — malformed request body (422).
  /// - [NetworkFailure] — connectivity issues.
  /// - [UnknownFailure] — any other unexpected error.
  Future<(User, AuthTokens)> login({
    required String email,
    required String password,
  });

  /// Registers a new account with the given [role].
  ///
  /// The backend determines which roles are eligible for self-registration and
  /// returns a 400 for invite-only roles (e.g. [UserRole.salonAdmin],
  /// [UserRole.salonMaster]). The client does not enforce this guard — the
  /// error surfaces via the existing [ValidationFailure] / [ServerFailure]
  /// snackbar flow.
  ///
  /// Returns a [RegisterResult] union — the backend may respond with EITHER:
  /// - [VerificationRequired] — current default. The account is created but
  ///   the user must verify their email via OTP before a session is issued.
  ///   The repository returns the registered email so the UI can navigate to
  ///   the verification screen.
  /// - [AuthenticatedRegisterResult] — legacy / future auto-login path. The
  ///   account is created AND a session is issued immediately; the caller
  ///   persists the refresh token and transitions straight to home.
  ///
  /// Throws:
  /// - [ValidationFailure] — email already in use, password too weak, etc.
  /// - [NetworkFailure] — connectivity issues.
  /// - [UnknownFailure] — any other unexpected error, including a 200 with
  ///   an unrecognised response shape.
  Future<RegisterResult> registerIndependentMaster({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    UserRole role = UserRole.independentMaster,
    String? businessName,
    String? address,
    String? phone,
  });

  /// Exchanges a valid [refreshToken] for a fresh token pair.
  ///
  /// Throws:
  /// - [UnauthorizedFailure] — the refresh token is expired or revoked.
  /// - [NetworkFailure] — connectivity issues.
  /// - [UnknownFailure] — any other unexpected error.
  Future<AuthTokens> refresh(String refreshToken);

  /// Returns the profile of the currently authenticated user.
  ///
  /// Requires a valid access token to be attached by [AuthInterceptor].
  ///
  /// Throws:
  /// - [UnauthorizedFailure] — no valid session.
  /// - [NetworkFailure] — connectivity issues.
  /// - [UnknownFailure] — any other unexpected error.
  Future<User> me();

  /// Best-effort server-side token revocation.
  ///
  /// Sends the current refresh token to `POST /auth/logout` so the backend
  /// can invalidate it. 4xx and network errors are swallowed — the local
  /// token wipe always proceeds regardless of the server response.
  ///
  /// Callers (i.e. [AuthNotifier.logout]) must NOT depend on this completing
  /// successfully; they should wipe local storage unconditionally after the
  /// call returns or throws.
  Future<void> logout();

  /// Verifies the email address by submitting the [otp] code that was sent to
  /// [email].
  ///
  /// On success the backend issues a full session (Phase 1.5 contract): the
  /// returned tuple carries both the authenticated [User] and the freshly
  /// minted [AuthTokens]. The caller persists the refresh token and flips
  /// the auth state to [Authenticated].
  ///
  /// Throws:
  /// - [VerificationFailure] — typed `INVALID_CODE` / `CODE_EXPIRED` /
  ///   `ALREADY_VERIFIED` from the backend.
  /// - [ValidationFailure] — fallback for generic 400 without a typed code.
  /// - [NetworkFailure] — connectivity issues.
  /// - [UnknownFailure] — any other unexpected error.
  Future<(User, AuthTokens)> verifyEmail({
    required String email,
    required String otp,
  });

  /// Re-sends the email verification code to [email].
  ///
  /// Throws:
  /// - [ResendThrottledFailure] — backend 429 with `retryAfterSeconds` payload.
  /// - [NetworkFailure] — connectivity issues.
  /// - [UnknownFailure] — any other unexpected error.
  Future<void> resendVerificationCode({required String email});

  /// Requests a password-reset link for [email] (backend Phase 11.2).
  ///
  /// `POST /auth/forgot-password` ALWAYS returns a generic 200 regardless of
  /// whether the account exists (anti-enumeration). This method therefore
  /// resolves with no value on the happy path; the UI shows the same generic
  /// confirmation either way. A real failure (network / 5xx / malformed)
  /// still surfaces so the screen can offer a retry.
  ///
  /// Throws:
  /// - [NetworkFailure] — connectivity issues.
  /// - [ServerFailure] — 5xx.
  /// - [ValidationFailure] — 400 bean-validation (e.g. blank/invalid email),
  ///   though the client validates the email locally first.
  /// - [UnknownFailure] — any other unexpected error.
  Future<void> requestPasswordReset(String email);

  /// Confirms a password reset with the single-use [token] from the emailed
  /// deep link and the user's chosen [newPassword] (backend Phase 11.3).
  ///
  /// `POST /auth/reset-password`. On success the backend updates the password
  /// and revokes all sessions but does NOT issue a session — the caller routes
  /// to the login screen (no auto-login by design).
  ///
  /// Throws:
  /// - [ResetTokenInvalidFailure] — the backend's generic 400 for an invalid,
  ///   used, or expired token. The screen renders its invalid-link state.
  /// - [NetworkFailure] — connectivity issues.
  /// - [ServerFailure] — 5xx.
  /// - [UnknownFailure] — any other unexpected error.
  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
  });

  /// Validates an invite token and returns the pre-filled [InviteDetails].
  ///
  /// `GET /auth/invite/validate?token=<token>`. Called immediately on screen
  /// arrival to pre-populate the read-only invite preview (email, role, expiry)
  /// before the user fills in their profile.
  ///
  /// Throws:
  /// - [ValidationFailure] — the token is invalid or expired (400/404).
  /// - [NetworkFailure] — connectivity issues.
  /// - [UnknownFailure] — any other unexpected error.
  Future<InviteDetails> validateInvite({required String token});

  /// Accepts an invite by completing account setup with [password], [firstName],
  /// [lastName] and optional [phoneNumber].
  ///
  /// `POST /auth/invite/accept`. On success the backend creates the account and
  /// issues a full session (identical shape to `/auth/login`). The caller
  /// persists the refresh token and transitions to [Authenticated].
  ///
  /// Throws:
  /// - [ValidationFailure] — password too weak, duplicate email, expired token, etc.
  /// - [NetworkFailure] — connectivity issues.
  /// - [ServerFailure] — 5xx.
  /// - [UnknownFailure] — any other unexpected error.
  Future<(User, AuthTokens)> acceptInvite({
    required String token,
    required String password,
    required String firstName,
    required String lastName,
    String? phoneNumber,
  });
}
