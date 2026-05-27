// Phase 3.x — RegisterResult sealed union.
//
// The backend's /auth/register endpoints return one of TWO possible shapes:
//
//   1. Verification-required (current default):
//        { "success": true,
//          "data": { "message": "...", "email": "..." },
//          "message": null }
//      The user is created but unauthenticated; the client must take them to
//      the OTP verification screen.
//
//   2. Authenticated immediately (legacy / future "auto-login" path):
//        { "success": true,
//          "data": { "user": {...}, "accessToken": "...", "refreshToken": "..." },
//          "message": null }
//      The user is created AND logged in; the client persists the refresh
//      token and transitions straight to the home shell.
//
// Both shapes are valid happy paths — the repository must surface which one
// occurred so the notifier and screen can dispatch correctly. Hand-throwing a
// Failure on the verification envelope was the bug that produced the
// `_TypeError: type 'Null' is not a subtype of type 'Map<String, dynamic>'`
// crash during registration.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

import 'auth_tokens.dart';
import 'user.dart';

part 'register_result.freezed.dart';

/// The sealed result of a successful registration call.
///
/// Consumers pattern-match to handle both happy paths:
///
/// ```dart
/// switch (await repo.registerIndependentMaster(...)) {
///   case VerificationRequired(:final email): /* go to /verification */
///   case Authenticated(:final user, :final tokens): /* persist + go home */
/// }
/// ```
@freezed
sealed class RegisterResult with _$RegisterResult {
  /// The backend created the account but the user must verify their email
  /// before a session is issued. The client navigates to the OTP screen.
  const factory RegisterResult.verificationRequired({required String email}) =
      VerificationRequired;

  /// The backend created the account AND issued a session in the same
  /// response. The client persists the refresh token and transitions
  /// straight to the authenticated shell.
  const factory RegisterResult.authenticated({
    required User user,
    required AuthTokens tokens,
  }) = AuthenticatedRegisterResult;
}
