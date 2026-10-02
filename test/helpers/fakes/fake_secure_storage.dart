// Phase 2.1 — In-memory SecureStorage fake for unit and widget tests.
//
// Backed by a plain [Map] — no platform channels, no async I/O. Each test
// that needs storage isolation should create a fresh [FakeSecureStorage]
// instance rather than sharing one across tests.
//
// Usage with ProviderContainer:
//   final fake = FakeSecureStorage();
//   final container = ProviderContainer(overrides: [
//     secureStorageProvider.overrideWithValue(fake),
//   ]);
//   addTearDown(container.dispose);
//
// Usage with ProviderScope (widget tests):
//   ProviderScope(
//     overrides: [secureStorageProvider.overrideWithValue(FakeSecureStorage())],
//     child: MyWidget(),
//   )

import 'package:beautica_mobile/core/storage/secure_storage.dart';
import 'package:beautica_mobile/core/storage/storage_keys.dart';

/// Map-backed [SecureStorage] for tests.
///
/// All methods are synchronous under the hood (the `async` wrapper satisfies
/// the interface contract). Last write wins — there is no expiry or eviction.
class FakeSecureStorage implements SecureStorage {
  final Map<String, String> _backing = {};

  @override
  Future<String?> readRefreshToken() async =>
      _backing[StorageKeys.refreshToken];

  @override
  Future<void> writeRefreshToken(String token) async {
    _backing[StorageKeys.refreshToken] = token;
  }

  @override
  Future<String?> readUserJson() async => _backing[StorageKeys.userJson];

  @override
  Future<void> writeUserJson(String json) async {
    _backing[StorageKeys.userJson] = json;
  }

  @override
  Future<String?> readPendingLocality() async =>
      _backing[StorageKeys.pendingLocality];

  @override
  Future<void> writePendingLocality(String json) async {
    _backing[StorageKeys.pendingLocality] = json;
  }

  @override
  Future<void> deletePendingLocality() async {
    _backing.remove(StorageKeys.pendingLocality);
  }

  @override
  Future<String?> readLastSalon() async => _backing[StorageKeys.lastSalon];

  @override
  Future<void> writeLastSalon(String json) async {
    _backing[StorageKeys.lastSalon] = json;
  }

  @override
  Future<void> deleteLastSalon() async {
    _backing.remove(StorageKeys.lastSalon);
  }

  @override
  Future<bool> readPushPermissionAsked() async =>
      _backing.containsKey(StorageKeys.pushPermissionAsked);

  @override
  Future<void> writePushPermissionAsked() async {
    _backing[StorageKeys.pushPermissionAsked] = '1';
  }

  @override
  Future<bool> readPushRevokePending() async =>
      _backing.containsKey(StorageKeys.pushRevokePending);

  @override
  Future<void> writePushRevokePending() async {
    _backing[StorageKeys.pushRevokePending] = '1';
  }

  @override
  Future<void> clearPushRevokePending() async {
    _backing.remove(StorageKeys.pushRevokePending);
  }

  // Mirrors production: the per-device flags survive logout.
  @override
  Future<void> deleteAll() async {
    final Map<String, String> kept = <String, String>{
      for (final String k in StorageKeys.deviceScoped)
        if (_backing.containsKey(k)) k: _backing[k]!,
    };
    _backing.clear();
    _backing.addAll(kept);
  }
}
