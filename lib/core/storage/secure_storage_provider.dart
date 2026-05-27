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
//
// MP4/MP-STARTUP-A — The [FlutterSecureStorageImpl] constructor is intentionally
// created lazily here (only when the provider is first read, NOT when the
// ProviderScope is created). Do NOT pre-warm or eagerly ref.watch this provider
// from any keepAlive provider that is constructed on app startup. All reads of
// [SecureStorage] must happen inside async callbacks (microtasks, futures) so
// that the Android Keystore cipher initialisation — which can take 3–10 s on
// some Samsung/Xiaomi devices on the very first cold start — never blocks the
// main isolate before the first Flutter frame.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'secure_storage.dart';

part 'secure_storage_provider.g.dart';

/// Provides the singleton [SecureStorage] implementation for the app lifetime.
///
/// Override with [FakeSecureStorage] in unit/widget tests.
///
/// STARTUP-CRITICAL: This provider must only be read inside async callbacks.
/// Never ref.watch() or ref.read() this provider synchronously from within
/// a keepAlive provider's constructor or build() body — doing so pulls
/// [FlutterSecureStorageImpl] (and its Android Keystore cipher init) onto the
/// main thread before the first frame renders.
@Riverpod(keepAlive: true)
SecureStorage secureStorage(Ref ref) => FlutterSecureStorageImpl();
