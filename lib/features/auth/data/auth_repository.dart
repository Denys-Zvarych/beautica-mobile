// Phase 2.3 — AuthRepository interface.
//
// Abstract contract for the auth data layer. The concrete implementation
// ([HttpAuthRepository]) is hidden behind this interface so that tests can
// swap in a fake without depending on Dio or the real backend.
//
// The only allowed imports are domain models — no Flutter, no Dio, no
// platform packages. This keeps the interface a pure-Dart declaration.

import '../domain/auth_tokens.dart';
import '../domain/user.dart';

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

  /// Registers a new account with the INDEPENDENT_MASTER role.
  ///
  /// Returns a tuple of the newly-created [User] and the issued [AuthTokens]
  /// on success — the user is logged in immediately after registration.
  ///
  /// Throws:
  /// - [ValidationFailure] — email already in use, password too weak, etc.
  /// - [NetworkFailure] — connectivity issues.
  /// - [UnknownFailure] — any other unexpected error.
  Future<(User, AuthTokens)> registerIndependentMaster({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
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
}
