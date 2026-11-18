// M517 — ONE device-local, per-user-id JSON map under a single secure-storage
// key, over the app's key-value seam ([DiagnosticsStore] /
// `diagnosticsStoreProvider`, phase 410). Shared by [EmailPromptStore]
// (AUTH-D17) and [CurrentPasswordLockoutStore] (AUTH-D19) so both persist the
// same way: `{userId: <entry json>}`, every other account's entry kept.
//
// Best-effort: an unreadable store reads as empty and a failed write is
// logged; neither ever throws to a caller or blocks a screen.

import 'dart:convert';
import 'dart:developer';

import '../../../core/diagnostics/install_id.dart';

/// Reads / writes one JSON entry per user id under [key].
final class UserKeyedJsonStore {
  const UserKeyedJsonStore(
    this._kv, {
    required this.key,
    required this.label,
    required this.logName,
  });

  final DiagnosticsStore _kv;

  /// The secure-storage key (a [StorageKeys] constant).
  final String key;

  /// What the entries are, for log lines (`'email prompt state'`).
  final String label;

  /// The `log(name:)` channel.
  final String logName;

  /// Every stored entry (empty when absent or unreadable).
  Future<Map<String, dynamic>> readAll() async {
    try {
      final String? raw = await _kv.read(key);
      if (raw == null || raw.isEmpty) return <String, dynamic>{};
      final Object? decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on Object catch (e) {
      log('$label unreadable: ${e.runtimeType}', name: logName, level: 900);
      return <String, dynamic>{};
    }
  }

  /// The raw entry of [userId] (`null` when absent or unreadable).
  Future<Object?> read(String userId) async => (await readAll())[userId];

  /// Persists [entry] for [userId] (`null` removes it), keeping every other
  /// account's entry.
  Future<void> write(String userId, Object? entry) async {
    try {
      final Map<String, dynamic> all = await readAll();
      if (entry == null) {
        all.remove(userId);
      } else {
        all[userId] = entry;
      }
      await _kv.write(key, jsonEncode(all));
    } on Object catch (e) {
      log('$label not saved: ${e.runtimeType}', name: logName, level: 900);
    }
  }
}
