// Phase 2.1 — Riverpod provider for SecureStorage.
//
// Exposes [SecureStorage] (the interface) so callers depend on the abstraction,
// not [FlutterSecureStorageImpl]. Tests override this provider with
// `FakeSecureStorage` — no platform channels required.
//
// Generated name: `secureStorageProvider` (riverpod_generator convention).
// Keep-alive: true — the storage wrapper is a singleton for the app lifetime.
// Overriding in tests:
//   ProviderContainer(overrides: [
//     secureStorageProvider.overrideWithValue(FakeSecureStorage()),
//   ])

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'secure_storage.dart';

part 'secure_storage_provider.g.dart';

/// Provides the singleton [SecureStorage] implementation for the app lifetime.
///
/// Override with [FakeSecureStorage] in unit/widget tests.
@Riverpod(keepAlive: true)
SecureStorage secureStorage(Ref ref) => FlutterSecureStorageImpl();
