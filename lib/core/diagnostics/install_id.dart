// Phase 410 (R.3 D8) — anonymous install ID + crash-report opt-out storage.
//
// The install ID is a random 128-bit hex created on first use and stored in
// secure storage under [StorageKeys.diagnosticsInstallId]. It is NOT the
// backend user ID and is never sent to the backend — only to Sentry, as
// `user.id`, so crash-free-user stats work without identifying anyone. It is
// regenerated when the user turns reporting off and on again, so a re-enabled
// device cannot be joined to its earlier reports.
//
// The opt-out flag lives under [StorageKeys.diagnosticsEnabled]; absent means
// ON (decided default, 2026-10-14). Both keys are device-scoped: they survive
// logout ([StorageKeys.deviceScoped]).
//
// [DiagnosticsStore] is deliberately separate from `SecureStorage`: it is read
// from `main()` BEFORE the ProviderContainer exists, and widening the
// `SecureStorage` interface would break every fake implementing it. Both use
// the same [beauticaFlutterSecureStorage] namespace.

import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../storage/secure_storage.dart';
import '../storage/storage_keys.dart';

/// Minimal key-value seam over secure storage for the diagnostics keys.
abstract interface class DiagnosticsStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Production [DiagnosticsStore] on the app's one secure-storage namespace.
final class SecureDiagnosticsStore implements DiagnosticsStore {
  const SecureDiagnosticsStore([
    FlutterSecureStorage storage = beauticaFlutterSecureStorage,
  ]) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

final RegExp _hex128 = RegExp(r'^[0-9a-f]{32}$');

/// Random 128-bit id as 32 lowercase hex chars ([Random.secure] by default).
/// The ONE generator for the install ID and the HTTP `X-Request-Id`.
String randomHex128([Random? random]) {
  final Random r = random ?? Random.secure();
  final StringBuffer b = StringBuffer();
  for (int i = 0; i < 16; i++) {
    b.write(r.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return b.toString();
}

/// Reads / creates / rotates the anonymous install ID.
final class InstallId {
  InstallId(this._store, {Random? random}) : _random = random;

  final DiagnosticsStore _store;
  final Random? _random;

  /// The stored id, creating (and persisting) one on first use. A stored
  /// value that is not 32 hex chars is replaced.
  Future<String> read() async {
    final String? stored = await _store.read(StorageKeys.diagnosticsInstallId);
    if (stored != null && _hex128.hasMatch(stored)) return stored;
    return regenerate();
  }

  /// Replaces the id with a fresh one (off→on toggle).
  Future<String> regenerate() async {
    final String id = randomHex128(_random);
    await _store.write(StorageKeys.diagnosticsInstallId, id);
    return id;
  }
}

/// Opt-out flag: `true` unless the user switched reporting off.
Future<bool> readCrashReportingOptIn(DiagnosticsStore store) async =>
    await store.read(StorageKeys.diagnosticsEnabled) != 'false';

Future<void> writeCrashReportingOptIn(DiagnosticsStore store, bool enabled) =>
    store.write(StorageKeys.diagnosticsEnabled, enabled ? 'true' : 'false');
