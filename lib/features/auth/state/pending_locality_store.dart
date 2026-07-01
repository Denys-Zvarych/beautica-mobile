// Durable post-OTP locality store (silent-data-loss fix).
//
// Thin async wrapper over [SecureStorage] that (de)serialises a
// [PendingLocality] blob to/from a single namespaced key
// ([StorageKeys.pendingLocality]). Reuses the existing secure-storage
// abstraction (the one backing the auth tokens) — NO new storage dependency.
//
// The blob holds ONLY the locality slice + email + role — NEVER the password or
// the OTP. See [PendingLocality] for the full rationale.

import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/storage/secure_storage.dart';
import '../../../core/storage/secure_storage_provider.dart';
import 'pending_locality.dart';

part 'pending_locality_store.g.dart';

/// Reads / writes / clears the durable [PendingLocality] slice.
final class PendingLocalityStore {
  PendingLocalityStore(this._storage);

  final SecureStorage _storage;

  /// Persists [pending] as JSON under [StorageKeys.pendingLocality].
  Future<void> save(PendingLocality pending) =>
      _storage.writePendingLocality(jsonEncode(pending.toJson()));

  /// Reads the stashed slice, or `null` when absent / malformed.
  ///
  /// A corrupt blob is treated as absent (never throws into the verification
  /// flow); the corruption is logged in debug builds so it is not invisible.
  Future<PendingLocality?> read() async {
    final raw = await _storage.readPendingLocality();
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return PendingLocality.tryFromJson(decoded);
    } on FormatException catch (e) {
      if (kDebugMode) {
        log(
          'PendingLocality blob malformed (treated as absent): ${e.message}',
          name: 'auth.pending_locality',
          level: 900,
        );
      }
      return null;
    }
  }

  /// Removes the stashed slice (called on `/done` arrival).
  Future<void> clear() => _storage.deletePendingLocality();
}

/// Provides the [PendingLocalityStore] backed by the app's [SecureStorage].
///
/// STARTUP-CRITICAL: like [secureStorageProvider], only read this inside async
/// callbacks — never synchronously from a keepAlive provider constructor.
@Riverpod(keepAlive: true)
PendingLocalityStore pendingLocalityStore(Ref ref) =>
    PendingLocalityStore(ref.watch(secureStorageProvider));
