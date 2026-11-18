// M517 (AUTH-D17) — device-local persistence of the email-prompt state
// ([EmailPromptState]) per user id, under ONE secure-storage key
// ([StorageKeys.emailPrompts], device-scoped: survives logout, B516 D7).
//
// Reuses the existing key-value seam over the app's secure-storage namespace
// ([DiagnosticsStore] / `diagnosticsStoreProvider`, phase 410) instead of
// widening the `SecureStorage` interface every fake implements — the same
// reason that seam exists. The per-user map is the shared
// [UserKeyedJsonStore]. Best-effort: an unreadable store reads as "never
// shown" (a prompt may show once more) and a failed write is logged; neither
// ever blocks a screen.

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/diagnostics/crash_reporting_enabled_provider.dart';
import '../../../core/diagnostics/install_id.dart';
import '../../../core/storage/storage_keys.dart';
import '../domain/email_prompt_state.dart';
import 'user_keyed_json_store.dart';

part 'email_prompt_store.g.dart';

/// Reads / writes [EmailPromptState] per user id.
final class EmailPromptStore {
  EmailPromptStore(DiagnosticsStore kv)
    : _store = UserKeyedJsonStore(
        kv,
        key: StorageKeys.emailPrompts,
        label: 'email prompt state',
        logName: 'auth.emailPrompts',
      );

  final UserKeyedJsonStore _store;

  /// The state of [userId] (default when absent or unreadable).
  Future<EmailPromptState> read(String userId) async =>
      EmailPromptState.fromJson(await _store.read(userId));

  /// Persists [state] for [userId], keeping every other account's entry.
  Future<void> write(String userId, EmailPromptState state) =>
      _store.write(userId, state.toJson());
}

@Riverpod(keepAlive: true)
EmailPromptStore emailPromptStore(Ref ref) =>
    EmailPromptStore(ref.watch(diagnosticsStoreProvider));
