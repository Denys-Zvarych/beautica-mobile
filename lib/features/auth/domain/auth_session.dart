// Phase 2.4 — AuthSession sealed union (replaces AuthState from stub).
//
// The sealed union for the auth lifecycle. [Authenticated] carries the
// in-memory access token AND the [User] profile returned by `GET /auth/me`.
//
// Security invariants (mobile-security MS-1 / MS-2):
//   - [accessToken] is held in memory only — never written to any persistent
//     store. Only the refresh token is persisted (via SecureStorage).
//   - The refresh token is NOT a field on any of these classes. It lives
//     exclusively in [SecureStorage] (see StorageKeys.refreshToken).
//
// Pure Dart: no Flutter imports.

import 'package:freezed_annotation/freezed_annotation.dart';

import 'user.dart';

part 'auth_session.freezed.dart';

/// The sealed authentication state for the Beautica mobile app.
///
/// Consumers should pattern-match to distinguish authenticated from
/// unauthenticated states, for example:
///
/// ```dart
/// final session = ref.watch(authProvider).value;
/// switch (session) {
///   case Authenticated(:final user, :final accessToken): ...
///   case Unauthenticated(): ...
///   case null: ... // still loading
/// }
/// ```
@freezed
sealed class AuthSession with _$AuthSession {
  /// The user has no valid session (not logged in, or the session was cleared).
  const factory AuthSession.unauthenticated() = Unauthenticated;

  /// The user is logged in and holds a valid in-memory access token.
  ///
  /// [accessToken] is the short-lived JWT for API requests. It is kept
  /// in memory only and is never persisted to disk.
  ///
  /// [user] contains the profile data loaded from `GET /auth/me` during the
  /// login or cold-start refresh flow.
  const factory AuthSession.authenticated({
    required User user,
    required String accessToken,
  }) = Authenticated;
}
