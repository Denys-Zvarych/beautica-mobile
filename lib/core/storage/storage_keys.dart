// Phase 2.1 — Storage key constants for flutter_secure_storage.
//
// Access token is intentionally absent — it lives in AuthNotifier's in-memory
// state only and is NEVER persisted to disk. Only the refresh token (long-lived)
// and the serialised user JSON (for offline bootstrap) touch secure storage.
//
// Key strings use SCREAMING_SNAKE_CASE with a "BEAUTICA_" namespace prefix to
// avoid collisions when the app shares a Keystore namespace with other apps on
// the same device (rare, but valid on work-profile setups).

/// Namespaced keys for [flutter_secure_storage] reads and writes.
///
/// Do not use bare string literals in repository or notifier code — always
/// reference this class so a key rename is a single-site change.
abstract final class StorageKeys {
  /// Key under which the JWT refresh token is stored.
  ///
  /// Written on successful login / token refresh; deleted on logout or when
  /// the refresh call itself returns 401.
  static const String refreshToken = 'BEAUTICA_REFRESH_TOKEN';

  /// Key under which the serialised [User] JSON is cached.
  ///
  /// Written after login and profile updates; read during cold-start to
  /// restore the session without a round-trip to the server.
  static const String userJson = 'BEAUTICA_USER_JSON';
}
