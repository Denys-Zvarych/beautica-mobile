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

  /// Key under which the durable post-OTP locality slice is stashed.
  ///
  /// Registration collects the locality on Step 3, but it can only be persisted
  /// AFTER email verification (the PATCH needs a Bearer token). The in-memory
  /// [RegisterDraft] is routinely lost while the user backgrounds the app to
  /// read the OTP email (or is OS-killed under memory pressure), so the minimal
  /// locality slice — email, role, cityId/districtId (+ provider address) — is
  /// mirrored here so the verification screen can re-hydrate it. NEVER stores
  /// the password or the OTP. Cleared on `/done` arrival and on logout
  /// ([SecureStorage.deleteAll]).
  static const String pendingLocality = 'BEAUTICA_PENDING_LOCALITY';

  /// Key under which the last-visited salon pointer is stashed.
  ///
  /// Phase 286 — storage slot only; nothing reads or writes it yet (Phase 287
  /// adds the writer, Phase 288 the reader). Per-device, client-side (D1):
  /// deliberately NOT a backend field — see
  /// `docs/mobile-phases/phase-286-last-visited-salon-secure-storage-slot.md`.
  ///
  /// The value is `{userId, salonId}` JSON (D2), NOT a bare salon id, so a
  /// session restored from cached [userJson] for a *different* account on
  /// the same device cannot read the previous owner's salon id — a `userId`
  /// mismatch is treated exactly like "no value stored". Two opaque UUIDs,
  /// no PII (D3). Cleared on logout ([SecureStorage.deleteAll]).
  static const String lastSalon = 'BEAUTICA_LAST_SALON';
}
