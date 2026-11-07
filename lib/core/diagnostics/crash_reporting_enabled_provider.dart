// Phase 410 (R.3 D8) — the «Надсилати звіти про збої» toggle state.
//
// `build()` reads `diagnostics.enabled` (absent → ON). [setEnabled] persists
// the choice, rotates the install ID on an off→on flip, and applies it to the
// running SDK via [CrashReporting.applyOptIn]. Storage failures never surface
// as an error state: an unreadable flag shows the decided default (ON), a
// failed write keeps the previous value.

import 'dart:developer';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'crash_reporting.dart';
import 'install_id.dart';

part 'crash_reporting_enabled_provider.g.dart';

/// The diagnostics key-value store. Override with an in-memory fake in tests.
@Riverpod(keepAlive: true)
DiagnosticsStore diagnosticsStore(Ref ref) => crashReportingStore();

@riverpod
class CrashReportingEnabled extends _$CrashReportingEnabled {
  @override
  Future<bool> build() async {
    try {
      return await readCrashReportingOptIn(ref.watch(diagnosticsStoreProvider));
    } on Object catch (e) {
      log(
        'opt-out read failed: ${e.runtimeType}',
        name: 'diagnostics',
        level: 900,
      );
      return true;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    final bool? previous = state.value;
    if (previous == enabled) return;
    final DiagnosticsStore store = ref.read(diagnosticsStoreProvider);
    state = AsyncData<bool>(enabled);
    try {
      await writeCrashReportingOptIn(store, enabled);
    } on Object catch (e) {
      log(
        'opt-out write failed: ${e.runtimeType}',
        name: 'diagnostics',
        level: 1000,
      );
      if (ref.mounted) state = AsyncData<bool>(previous ?? !enabled);
      return;
    }
    // The choice is persisted: a failure below (id rotation, `Sentry.close`,
    // re-init) must NOT revert the switch — it would show a state that
    // disagrees with storage. The opt-out flag already gates `beforeSend`.
    try {
      final String? freshId = enabled
          ? await InstallId(store).regenerate()
          : null;
      await CrashReporting.applyOptIn(
        enabled: enabled,
        freshInstallId: freshId,
      );
    } on Object catch (e) {
      log(
        'opt-out apply failed: ${e.runtimeType}',
        name: 'diagnostics',
        level: 1000,
      );
    }
  }
}
