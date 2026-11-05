// Phase 410 (R.3 D8) — anonymous install ID + opt-out flag.
import 'package:beautica_mobile/core/diagnostics/crash_reporting_enabled_provider.dart';
import 'package:beautica_mobile/core/diagnostics/install_id.dart';
import 'package:beautica_mobile/core/storage/storage_keys.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes/fake_diagnostics_store.dart';

final RegExp _hex32 = RegExp(r'^[0-9a-f]{32}$');

void main() {
  group('InstallId', () {
    test('first read creates a 32-hex id and persists it', () async {
      final FakeDiagnosticsStore store = FakeDiagnosticsStore();
      final String id = await InstallId(store).read();
      expect(id, matches(_hex32));
      expect(store.values[StorageKeys.diagnosticsInstallId], id);
    });

    test('stable across reads (and across InstallId instances)', () async {
      final FakeDiagnosticsStore store = FakeDiagnosticsStore();
      final String first = await InstallId(store).read();
      final String second = await InstallId(store).read();
      expect(second, first);
      expect(store.writes, 1, reason: 'the second read must not rewrite');
    });

    test('a malformed stored value is replaced', () async {
      final FakeDiagnosticsStore store = FakeDiagnosticsStore()
        ..values[StorageKeys.diagnosticsInstallId] = 'user-42@x.ua';
      final String id = await InstallId(store).read();
      expect(id, matches(_hex32));
      expect(id, isNot('user-42@x.ua'));
    });

    test('regenerate replaces the stored id', () async {
      final FakeDiagnosticsStore store = FakeDiagnosticsStore();
      final String before = await InstallId(store).read();
      final String after = await InstallId(store).regenerate();
      expect(after, matches(_hex32));
      expect(after, isNot(before));
      expect(await InstallId(store).read(), after);
    });
  });

  group('opt-out flag', () {
    test('absent means ON (decided default)', () async {
      expect(await readCrashReportingOptIn(FakeDiagnosticsStore()), isTrue);
    });

    test('round-trips off and on', () async {
      final FakeDiagnosticsStore store = FakeDiagnosticsStore();
      await writeCrashReportingOptIn(store, false);
      expect(store.values[StorageKeys.diagnosticsEnabled], 'false');
      expect(await readCrashReportingOptIn(store), isFalse);
      await writeCrashReportingOptIn(store, true);
      expect(await readCrashReportingOptIn(store), isTrue);
    });
  });

  test('both diagnostics keys survive logout (device-scoped)', () {
    expect(
      StorageKeys.deviceScoped,
      containsAll(<String>[
        StorageKeys.diagnosticsInstallId,
        StorageKeys.diagnosticsEnabled,
      ]),
    );
  });

  group('crashReportingEnabledProvider', () {
    late FakeDiagnosticsStore store;
    late ProviderContainer container;

    setUp(() {
      store = FakeDiagnosticsStore();
      container = ProviderContainer(
        overrides: [diagnosticsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      // Keep the autoDispose notifier alive across awaits.
      container.listen(crashReportingEnabledProvider, (_, _) {});
    });

    test('defaults to ON', () async {
      expect(
        await container.read(crashReportingEnabledProvider.future),
        isTrue,
      );
    });

    test('install id is regenerated on off -> on', () async {
      final String before = await InstallId(store).read();
      await container.read(crashReportingEnabledProvider.future);
      final CrashReportingEnabled n = container.read(
        crashReportingEnabledProvider.notifier,
      );
      await n.setEnabled(false);
      expect(store.values[StorageKeys.diagnosticsEnabled], 'false');
      expect(store.values[StorageKeys.diagnosticsInstallId], before);
      await n.setEnabled(true);
      expect(store.values[StorageKeys.diagnosticsEnabled], 'true');
      final String after = store.values[StorageKeys.diagnosticsInstallId]!;
      expect(after, matches(_hex32));
      expect(after, isNot(before));
    });

    test('unreadable flag shows the default (ON), not an error', () async {
      store.failReads = true;
      expect(
        await container.read(crashReportingEnabledProvider.future),
        isTrue,
      );
    });

    test('failed write keeps the previous value', () async {
      await container.read(crashReportingEnabledProvider.future);
      store.failWrites = true;
      await container
          .read(crashReportingEnabledProvider.notifier)
          .setEnabled(false);
      expect(container.read(crashReportingEnabledProvider).value, isTrue);
    });
  });

  group('crashReportingEnabledProvider — failure after a successful write', () {
    test('a failed install-id rotation is only logged: the switch stays ON '
        'and storage keeps the persisted opt-in', () async {
      final _FailInstallIdWriteStore store = _FailInstallIdWriteStore()
        ..values[StorageKeys.diagnosticsEnabled] = 'false';
      final ProviderContainer container = ProviderContainer(
        overrides: [diagnosticsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      container.listen(crashReportingEnabledProvider, (_, _) {});
      expect(
        await container.read(crashReportingEnabledProvider.future),
        isFalse,
      );

      await container
          .read(crashReportingEnabledProvider.notifier)
          .setEnabled(true);

      expect(store.installIdWriteAttempts, 1, reason: 'rotation was tried');
      expect(store.values[StorageKeys.diagnosticsEnabled], 'true');
      expect(store.values.containsKey(StorageKeys.diagnosticsInstallId), false);
      final AsyncValue<bool> state = container.read(
        crashReportingEnabledProvider,
      );
      expect(state, isA<AsyncData<bool>>());
      expect(state.value, isTrue, reason: 'must agree with storage');
    });
  });
}

/// Persists the opt-out flag but fails every install-id write — drives the
/// "choice persisted, apply step failed" branch of `setEnabled`.
class _FailInstallIdWriteStore extends FakeDiagnosticsStore {
  int installIdWriteAttempts = 0;

  @override
  Future<void> write(String key, String value) async {
    if (key == StorageKeys.diagnosticsInstallId) {
      installIdWriteAttempts++;
      throw StateError('install id write failed');
    }
    return super.write(key, value);
  }
}
