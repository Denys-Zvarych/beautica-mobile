// M517 — pure rules: the AUTH-D19 current-password lockout mirror and the
// AUTH-D17 email-prompt state (client card once; the provider card was
// removed 2026-11-19), plus the User getters that gate them.
// QA additions: both are kept PER USER ID — the prompt store on the device
// (one secure-storage key, every account's entry kept), the lockout tally for
// the app session (a second account never inherits the first one's lock).

import 'dart:convert';

import 'package:beautica_mobile/core/diagnostics/crash_reporting_enabled_provider.dart';
import 'package:beautica_mobile/core/storage/storage_keys.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/data/current_password_lockout_store.dart';
import 'package:beautica_mobile/features/auth/data/email_prompt_store.dart';
import 'package:beautica_mobile/features/auth/domain/current_password_lockout.dart';
import 'package:beautica_mobile/features/auth/domain/email_prompt_state.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/state/current_password_lockout_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_diagnostics_store.dart';

void main() {
  final DateTime t0 = DateTime.utc(2026, 11, 18, 10);

  group('CurrentPasswordLockout (AUTH-D19)', () {
    CurrentPasswordLockout failN(int n, {Duration step = Duration.zero}) {
      CurrentPasswordLockout l = const CurrentPasswordLockout();
      for (int i = 0; i < n; i++) {
        l = l.recordFailure(t0.add(step * i));
      }
      return l;
    }

    test('9 wrong passwords do not lock; the 10th does', () {
      expect(failN(9).isLockedAt(t0), isFalse);
      expect(failN(10).isLockedAt(t0), isTrue);
    });

    test('the window restarts on each failure (14 min apart still counts)', () {
      final CurrentPasswordLockout l = failN(
        10,
        step: const Duration(minutes: 14),
      );
      expect(l.failures, 10);
      expect(l.isLockedAt(t0.add(const Duration(minutes: 14 * 9))), isTrue);
    });

    test('a failure after the window closed starts a new count', () {
      final CurrentPasswordLockout l = failN(
        9,
      ).recordFailure(t0.add(const Duration(minutes: 16)));
      expect(l.failures, 1);
      expect(l.isLockedAt(t0.add(const Duration(minutes: 16))), isFalse);
    });

    test('the lock lifts 15 minutes after the last failure', () {
      final CurrentPasswordLockout l = failN(10);
      expect(
        l.isLockedAt(t0.add(const Duration(minutes: 14, seconds: 59))),
        isTrue,
      );
      expect(l.isLockedAt(t0.add(const Duration(minutes: 15))), isFalse);
    });
  });

  group('EmailPromptState (AUTH-D17)', () {
    test('client card: due once, never after it was shown', () {
      const EmailPromptState fresh = EmailPromptState();
      expect(fresh.clientCardDue, isTrue);
      expect(fresh.withClientCardShown().clientCardDue, isFalse);
    });

    test('JSON round-trip keeps every field; junk reads as the default', () {
      final EmailPromptState s = const EmailPromptState().withClientCardShown();
      final EmailPromptState back = EmailPromptState.fromJson(s.toJson());
      expect(back.clientCardShown, isTrue);

      // A stale entry from the removed provider card (2026-11-19) still
      // parses: the old keys are ignored, the client flag is kept.
      final EmailPromptState legacy =
          EmailPromptState.fromJson(<String, dynamic>{
            'clientCardShown': true,
            'providerHiddenAt': '2026-11-18T09:00:00.000Z',
            'providerRetired': true,
          });
      expect(legacy.clientCardShown, isTrue);

      final EmailPromptState junk = EmailPromptState.fromJson('nope');
      expect(junk.clientCardDue, isTrue);
    });
  });

  group('User M517 getters', () {
    const User base = User(id: 'u', role: UserRole.client);

    test('mustAddPhone only on an explicit phoneRequiredBy + unverified', () {
      expect(base.mustAddPhone, isFalse);
      expect(base.copyWith(phoneVerified: false).mustAddPhone, isFalse);
      expect(
        base
            .copyWith(phoneVerified: false, phoneRequiredBy: '2026-11-18')
            .mustAddPhone,
        isTrue,
      );
      expect(
        base
            .copyWith(phoneVerified: true, phoneRequiredBy: '2026-11-18')
            .mustAddPhone,
        isFalse,
      );
    });

    test('confirmedEmail / lacksConfirmedEmail read emailVerified', () {
      const User withEmail = User(
        id: 'u',
        role: UserRole.client,
        email: 'a@b.ua',
      );
      expect(withEmail.confirmedEmail, isNull, reason: 'unknown ≠ confirmed');
      expect(withEmail.lacksConfirmedEmail, isFalse, reason: 'unknown');
      expect(withEmail.copyWith(emailVerified: true).confirmedEmail, 'a@b.ua');
      expect(base.copyWith(emailVerified: false).lacksConfirmedEmail, isTrue);
    });
  });

  group('EmailPromptStore — per user id (AUTH-D17)', () {
    test('a dismissal is stored under that user id only; other accounts keep '
        'their own entry and stay due', () async {
      final FakeDiagnosticsStore kv = FakeDiagnosticsStore();
      final EmailPromptStore store = EmailPromptStore(kv);

      await store.write(
        'client-a',
        const EmailPromptState().withClientCardShown(),
      );
      await store.write('master-b', const EmailPromptState());

      expect((await store.read('client-a')).clientCardDue, isFalse);
      expect((await store.read('master-b')).clientCardDue, isTrue);
      expect((await store.read('someone-new')).clientCardDue, isTrue);

      final Object? all = jsonDecode(kv.values[StorageKeys.emailPrompts]!);
      expect((all! as Map<String, dynamic>).keys, <String>[
        'client-a',
        'master-b',
      ]);
    });

    test('a fresh store over the same device storage reads the dismissal '
        'back (survives an app restart / re-login)', () async {
      final FakeDiagnosticsStore kv = FakeDiagnosticsStore();
      await EmailPromptStore(
        kv,
      ).write('client-a', const EmailPromptState().withClientCardShown());

      final EmailPromptState reread = await EmailPromptStore(
        kv,
      ).read('client-a');

      expect(reread.clientCardDue, isFalse);
    });

    test('unreadable storage reads as "never shown" and a failed write never '
        'throws', () async {
      final FakeDiagnosticsStore kv = FakeDiagnosticsStore()
        ..values[StorageKeys.emailPrompts] = '{not json';
      final EmailPromptStore store = EmailPromptStore(kv);

      expect((await store.read('client-a')).clientCardDue, isTrue);
      kv.failWrites = true;
      await store.write(
        'client-a',
        const EmailPromptState().withClientCardShown(),
      );
    });
  });

  group('CurrentPasswordLockoutNotifier — per user id (AUTH-D19)', () {
    ProviderContainer containerAt(
      DateTime Function() now, {
      FakeDiagnosticsStore? kv,
    }) {
      final ProviderContainer c = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(now),
          diagnosticsStoreProvider.overrideWithValue(
            kv ?? FakeDiagnosticsStore(),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('10 wrong passwords lock that account only', () {
      final ProviderContainer c = containerAt(() => t0);
      final CurrentPasswordLockoutNotifier n = c.read(
        currentPasswordLockoutProvider.notifier,
      );

      bool lockedNow = false;
      for (int i = 0; i < kCurrentPasswordLockoutThreshold; i++) {
        lockedNow = n.recordFailure('a');
      }

      expect(lockedNow, isTrue);
      expect(n.isLocked('a'), isTrue);
      expect(n.isLocked('b'), isFalse);
    });

    test('a correct password clears the tally: 9 wrong + clear + 1 wrong '
        'does not lock', () {
      final ProviderContainer c = containerAt(() => t0);
      final CurrentPasswordLockoutNotifier n = c.read(
        currentPasswordLockoutProvider.notifier,
      );

      for (int i = 0; i < 9; i++) {
        n.recordFailure('a');
      }
      n.clear('a');

      expect(n.recordFailure('a'), isFalse);
      expect(c.read(currentPasswordLockoutProvider)['a']?.failures, 1);
    });

    test('the lock lifts on the injected clock 15 minutes after the last '
        'failure', () {
      DateTime now = t0;
      final ProviderContainer c = containerAt(() => now);
      final CurrentPasswordLockoutNotifier n = c.read(
        currentPasswordLockoutProvider.notifier,
      );
      for (int i = 0; i < kCurrentPasswordLockoutThreshold; i++) {
        n.recordFailure('a');
      }

      now = t0.add(const Duration(minutes: 14, seconds: 59));
      expect(n.isLocked('a'), isTrue);
      now = t0.add(kCurrentPasswordLockoutWindow);
      expect(n.isLocked('a'), isFalse);
    });

    // Audit LOW (item 6): the tally is persisted per user id in device
    // secure storage, so an app restart inside the window keeps the lock.
    test('the tally survives an app restart (a fresh container over the same '
        'device storage) and a clear is persisted too', () async {
      final FakeDiagnosticsStore kv = FakeDiagnosticsStore();
      final ProviderContainer first = containerAt(() => t0, kv: kv);
      final CurrentPasswordLockoutNotifier n1 = first.read(
        currentPasswordLockoutProvider.notifier,
      );
      for (int i = 0; i < kCurrentPasswordLockoutThreshold; i++) {
        n1.recordFailure('a');
      }
      await pumpEventQueue();
      final Object? stored = jsonDecode(
        kv.values[StorageKeys.passwordLockout]!,
      );
      expect((stored! as Map<String, dynamic>).keys, <String>['a']);
      first.dispose();

      // "Restart": a new container over the same device storage.
      final ProviderContainer second = containerAt(() => t0, kv: kv);
      final CurrentPasswordLockoutNotifier n2 = second.read(
        currentPasswordLockoutProvider.notifier,
      );
      await pumpEventQueue();
      expect(n2.isLocked('a'), isTrue, reason: 'hydrated from storage');
      expect(n2.isLocked('b'), isFalse, reason: 'per user id');
      expect(n2.unlocksAt('a'), t0.add(kCurrentPasswordLockoutWindow));

      n2.clear('a');
      await pumpEventQueue();
      expect(
        (await CurrentPasswordLockoutStore(kv).readAll()).containsKey('a'),
        isFalse,
      );
    });

    // Audit LOW (cycle 2): an account touched in memory before hydration
    // resolves keeps its in-memory state; every other stored tally hydrates.
    // Safe for a CLEAR (a correct password is the server's own verdict).
    test('a clear made before hydration beats the stored lock; other '
        'accounts still hydrate their stored tally', () async {
      final FakeDiagnosticsStore kv = FakeDiagnosticsStore();
      await _seedLock(kv, <String>['a', 'b'], t0);
      final ProviderContainer c = containerAt(() => t0, kv: kv);
      final CurrentPasswordLockoutNotifier n = c.read(
        currentPasswordLockoutProvider.notifier,
      );

      n.clear('a'); // before _hydrate's readAll resolves
      await pumpEventQueue();

      expect(n.isLocked('a'), isFalse, reason: 'in-memory clear wins');
      expect(n.isLocked('b'), isTrue, reason: 'untouched account hydrates');
      expect(c.read(currentPasswordLockoutProvider).keys, <String>['b']);
      final Map<String, CurrentPasswordLockout> stored =
          await CurrentPasswordLockoutStore(kv).readAll();
      expect(stored.keys, <String>['b']);
    });

    // AUTH-D19 security outcome: a stored 10-failure lock must survive a
    // wrong password recorded before hydration — the pre-hydration failure is
    // added to the stored tally, in memory AND storage.
    test('a wrong password recorded before hydration never downgrades a stored '
        'lock', () async {
      final FakeDiagnosticsStore kv = FakeDiagnosticsStore();
      await _seedLock(kv, <String>['a'], t0);
      final ProviderContainer c = containerAt(() => t0, kv: kv);
      final CurrentPasswordLockoutNotifier n = c.read(
        currentPasswordLockoutProvider.notifier,
      );

      n.recordFailure('a'); // before _hydrate's readAll resolves
      await pumpEventQueue();

      expect(n.isLocked('a'), isTrue);
      final CurrentPasswordLockout? stored = (await CurrentPasswordLockoutStore(
        kv,
      ).readAll())['a'];
      expect(stored?.isLockedAt(t0), isTrue);
    });

    // Pins the ADD (not "stored wins" / "memory wins"): 9 stored + 1
    // pre-hydration failure is the 10th and locks, in memory and storage.
    test('a wrong password before hydration is added to a stored 9-failure '
        'tally and locks', () async {
      final FakeDiagnosticsStore kv = FakeDiagnosticsStore();
      await _seedLock(kv, <String>['a'], t0, failures: 9);
      final ProviderContainer c = containerAt(() => t0, kv: kv);
      final CurrentPasswordLockoutNotifier n = c.read(
        currentPasswordLockoutProvider.notifier,
      );

      n.recordFailure('a'); // before _hydrate's readAll resolves
      await pumpEventQueue();

      expect(c.read(currentPasswordLockoutProvider)['a']?.failures, 10);
      expect(n.isLocked('a'), isTrue);
      final CurrentPasswordLockout? stored = (await CurrentPasswordLockoutStore(
        kv,
      ).readAll())['a'];
      expect(stored?.failures, 10);
    });

    test('a stored tally whose window has closed is not added to a '
        'pre-hydration failure', () async {
      final FakeDiagnosticsStore kv = FakeDiagnosticsStore();
      await _seedLock(kv, <String>['a'], t0);
      final DateTime later = t0.add(kCurrentPasswordLockoutWindow);
      final ProviderContainer c = containerAt(() => later, kv: kv);
      final CurrentPasswordLockoutNotifier n = c.read(
        currentPasswordLockoutProvider.notifier,
      );

      n.recordFailure('a'); // before _hydrate's readAll resolves
      await pumpEventQueue();

      expect(c.read(currentPasswordLockoutProvider)['a']?.failures, 1);
      expect(n.isLocked('a'), isFalse);
    });

    test('unreadable lockout storage hydrates as no failures', () async {
      final FakeDiagnosticsStore kv = FakeDiagnosticsStore()
        ..values[StorageKeys.passwordLockout] = '{not json';
      final ProviderContainer c = containerAt(() => t0, kv: kv);
      final CurrentPasswordLockoutNotifier n = c.read(
        currentPasswordLockoutProvider.notifier,
      );
      await pumpEventQueue();
      expect(n.isLocked('a'), isFalse);
      expect(c.read(currentPasswordLockoutProvider), isEmpty);
    });
  });
}

/// Stores a [failures]-count tally (default: a 10-failure lock) at [at] for each of [userIds] (a prior session).
Future<void> _seedLock(
  FakeDiagnosticsStore kv,
  List<String> userIds,
  DateTime at, {
  int failures = kCurrentPasswordLockoutThreshold,
}) async {
  CurrentPasswordLockout lock = const CurrentPasswordLockout();
  for (int i = 0; i < failures; i++) {
    lock = lock.recordFailure(at);
  }
  final CurrentPasswordLockoutStore store = CurrentPasswordLockoutStore(kv);
  for (final String id in userIds) {
    await store.write(id, lock);
  }
}
