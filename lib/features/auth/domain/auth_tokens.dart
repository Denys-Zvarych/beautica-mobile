// Phase 2.3 — AuthTokens domain model.
//
// Pairs the short-lived access token (in-memory only) with the long-lived
// refresh token (written to flutter_secure_storage via SecureStorage).
//
// IMPORTANT: The access token is NEVER persisted to disk. Only the refresh
// token is stored — see StorageKeys.refreshToken. Any code that persists
// [accessToken] is a mobile-security CRITICAL finding.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_tokens.freezed.dart';
part 'auth_tokens.g.dart';

/// A pair of JWT tokens returned by login, registration, and token-refresh
/// endpoints.
///
/// - [accessToken] — short-lived; kept in [AuthNotifier] in-memory state only.
/// - [refreshToken] — long-lived; stored to [StorageKeys.refreshToken] by the
///   notifier after a successful auth flow.
@freezed
abstract class AuthTokens with _$AuthTokens {
  const factory AuthTokens({
    /// Short-lived JWT for authenticating API requests.
    ///
    /// Attached as `Authorization: Bearer <token>` by [AuthInterceptor].
    required String accessToken,

    /// Long-lived token used to obtain a new access token when it expires.
    ///
    /// Stored securely; sent to `POST /auth/refresh`.
    required String refreshToken,
  }) = _AuthTokens;

  factory AuthTokens.fromJson(Map<String, dynamic> json) =>
      _$AuthTokensFromJson(json);
}
