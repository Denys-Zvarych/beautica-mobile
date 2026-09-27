// Phase 2.1 — SecureStorage interface + FlutterSecureStorageImpl.
//
// The interface is purposefully narrow: one method per logical datum. This
// makes fakes trivial (see test/helpers/fakes/fake_secure_storage.dart) and
// keeps test setup independent of the flutter_secure_storage internals.
//
// Android: RSA-OAEP key-wrap + AES-256-GCM value encryption, both
//          Keystore-resident (flutter_secure_storage v10+ — no longer
//          Jetpack EncryptedSharedPreferences).
// iOS:     Keychain with `first_unlock_this_device` accessibility — data
//          survives a device restart (unlocked once) so background refresh
//          can read the token without the user re-authenticating.
//
// Security invariant (mobile-security MS-1):
//   Tokens and PII MUST be stored via this class. SharedPreferences is
//   forbidden for any auth material — see analysis_options.yaml for the CI
//   grep gate and Phase 2.1 security notes.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'storage_keys.dart';

/// Contract for reading and writing auth-sensitive values.
///
/// Concrete implementations: [FlutterSecureStorageImpl] (production),
/// `FakeSecureStorage` (tests).
abstract interface class SecureStorage {
  /// Reads the stored refresh token, or `null` if none exists.
  Future<String?> readRefreshToken();

  /// Writes (or overwrites) the refresh token.
  Future<void> writeRefreshToken(String token);

  /// Reads the serialised user JSON, or `null` if none exists.
  Future<String?> readUserJson();

  /// Writes (or overwrites) the serialised user JSON.
  Future<void> writeUserJson(String json);

  /// Reads the durable post-OTP locality slice JSON, or `null` if none exists.
  ///
  /// This is the registration locality stashed on Step 3 so that the
  /// verification screen can persist it even when the in-memory draft was
  /// discarded (app backgrounded for the OTP email / OS-killed). NEVER carries
  /// the password or the OTP — only the locality slice + email + role.
  Future<String?> readPendingLocality();

  /// Writes (or overwrites) the durable post-OTP locality slice JSON.
  Future<void> writePendingLocality(String json);

  /// Deletes the durable post-OTP locality slice (called on `/done` arrival).
  Future<void> deletePendingLocality();

  /// Reads the last-visited salon pointer JSON (`{userId, salonId}`), or
  /// `null` if none exists.
  ///
  /// Phase 286 — storage slot only; nothing reads it yet (Phase 288 adds the
  /// reader).
  Future<String?> readLastSalon();

  /// Writes (or overwrites) the last-visited salon pointer JSON.
  ///
  /// Phase 286 — storage slot only; nothing writes it yet (Phase 287 adds
  /// the writer).
  Future<void> writeLastSalon(String json);

  /// Deletes the last-visited salon pointer.
  Future<void> deleteLastSalon();

  /// Deletes all keys managed by this storage (called on logout).
  Future<void> deleteAll();
}

/// Production [SecureStorage] backed by [FlutterSecureStorage].
///
/// Android: RSA-OAEP-wrapped AES-256-GCM, Keystore-resident (not
/// EncryptedSharedPreferences — that mechanism was dropped in
/// flutter_secure_storage v10.0.0).
/// iOS:     Keychain item with [KeychainAccessibility.first_unlock_this_device].
///
/// Accepts an optional [FlutterSecureStorage] for constructor injection in
/// integration tests that need the real platform channel (not the in-memory
/// fake used in unit tests).
final class FlutterSecureStorageImpl implements SecureStorage {
  FlutterSecureStorageImpl([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // Android: flutter_secure_storage 10.x uses custom ciphers backed
            // by the Android Keystore by default. The former
            // `encryptedSharedPreferences: true` option was removed in v11
            // and is now a no-op / deprecated in v10 — omit it entirely.
            aOptions: AndroidOptions(),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readRefreshToken() =>
      _storage.read(key: StorageKeys.refreshToken);

  @override
  Future<void> writeRefreshToken(String token) =>
      _storage.write(key: StorageKeys.refreshToken, value: token);

  @override
  Future<String?> readUserJson() => _storage.read(key: StorageKeys.userJson);

  @override
  Future<void> writeUserJson(String json) =>
      _storage.write(key: StorageKeys.userJson, value: json);

  @override
  Future<String?> readPendingLocality() =>
      _storage.read(key: StorageKeys.pendingLocality);

  @override
  Future<void> writePendingLocality(String json) =>
      _storage.write(key: StorageKeys.pendingLocality, value: json);

  @override
  Future<void> deletePendingLocality() =>
      _storage.delete(key: StorageKeys.pendingLocality);

  @override
  Future<String?> readLastSalon() => _storage.read(key: StorageKeys.lastSalon);

  @override
  Future<void> writeLastSalon(String json) =>
      _storage.write(key: StorageKeys.lastSalon, value: json);

  @override
  Future<void> deleteLastSalon() => _storage.delete(key: StorageKeys.lastSalon);

  // deleteAll() wipes every key managed by this storage — including
  // [StorageKeys.pendingLocality] and [StorageKeys.lastSalon] — so logout
  // clears the locality slice and the last-visited-salon pointer too.
  @override
  Future<void> deleteAll() => _storage.deleteAll();
}
