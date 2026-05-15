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
final class FakeSecureStorage implements SecureStorage {
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
  Future<void> deleteAll() async => _backing.clear();
}
