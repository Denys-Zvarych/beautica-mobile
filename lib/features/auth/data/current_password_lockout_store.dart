// M517 (AUTH-D19) — device-local persistence of the client-side
// current-password lockout tally ([CurrentPasswordLockout]) per user id, under
// ONE secure-storage key ([StorageKeys.passwordLockout], device-scoped:
// survives logout). Same seam and shape as [EmailPromptStore] — the shared
// [UserKeyedJsonStore] — so an app restart inside the 15-minute window keeps
// the lock. Best-effort: unreadable reads as no failures (the server stays the
// boundary); a failed write is logged.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/diagnostics/crash_reporting_enabled_provider.dart';
import '../../../core/diagnostics/install_id.dart';
import '../../../core/storage/storage_keys.dart';
import '../domain/current_password_lockout.dart';
import 'user_keyed_json_store.dart';

part 'current_password_lockout_store.g.dart';

/// Reads / writes [CurrentPasswordLockout] per user id.
final class CurrentPasswordLockoutStore {
  CurrentPasswordLockoutStore(DiagnosticsStore kv)
    : _store = UserKeyedJsonStore(
        kv,
        key: StorageKeys.passwordLockout,
        label: 'password lockout',
        logName: 'auth.passwordLockout',
      );

  final UserKeyedJsonStore _store;

  /// Every stored tally, by user id.
  Future<Map<String, CurrentPasswordLockout>> readAll() async =>
      <String, CurrentPasswordLockout>{
        for (final MapEntry<String, dynamic> e
            in (await _store.readAll()).entries)
          e.key: CurrentPasswordLockout.fromJson(e.value),
      };

  /// Persists [lockout] for [userId]; `null` clears it.
  Future<void> write(String userId, CurrentPasswordLockout? lockout) =>
      _store.write(userId, lockout?.toJson());
}

@Riverpod(keepAlive: true)
CurrentPasswordLockoutStore currentPasswordLockoutStore(Ref ref) =>
    CurrentPasswordLockoutStore(ref.watch(diagnosticsStoreProvider));
