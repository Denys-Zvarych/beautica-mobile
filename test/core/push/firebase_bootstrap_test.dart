import 'dart:async';

import 'package:beautica_mobile/core/push/firebase_bootstrap.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_test/flutter_test.dart';

// Fake auto-refresh hook: keeps the activation tests off the real
// `FirebaseAppCheck.instance` (no Firebase app exists in unit tests).
Future<void> _noAutoRefresh(bool _) async {}

// Fake App Check start: keeps the init tests off the real activation.
Future<void> _noAppCheck() async {}

void main() {
  group('initFirebaseSafely', () {
    test('returns true when the initializer succeeds', () async {
      var called = false;
      final ok = await initFirebaseSafely(
        isAndroid: true,
        initializer: () async => called = true,
        appCheckActivator: _noAppCheck,
      );
      expect(ok, isTrue);
      expect(called, isTrue);
    });

    test(
      'returns false and does not throw when the initializer throws',
      () async {
        final ok = await initFirebaseSafely(
          isAndroid: true,
          initializer: () async => throw StateError('no Firebase App'),
        );
        expect(ok, isFalse);
      },
    );

    test('returns false without calling the initializer off Android', () async {
      var called = false;
      final ok = await initFirebaseSafely(
        isAndroid: false,
        initializer: () async => called = true,
      );
      expect(ok, isFalse);
      expect(called, isFalse);
    });

    test('returns false when the initializer exceeds the timeout', () async {
      final ok = await initFirebaseSafely(
        isAndroid: true,
        timeout: const Duration(milliseconds: 20),
        initializer: () => Completer<void>().future,
      );
      expect(ok, isFalse);
    });

    test('a slow-but-successful init within the guard returns true', () async {
      final ok = await initFirebaseSafely(
        isAndroid: true,
        timeout: const Duration(milliseconds: 500),
        initializer: () =>
            Future<void>.delayed(const Duration(milliseconds: 60)),
        appCheckActivator: _noAppCheck,
      );
      expect(ok, isTrue);
    });

    // M515 cleanup (INFO) — App Check runs AFTER init, outside the timeout
    // budget, unawaited: push availability never depends on it.
    test(
      'a hanging App Check activation still reports push available',
      () async {
        final Completer<void> appCheck = Completer<void>();
        var started = false;
        final ok = await initFirebaseSafely(
          isAndroid: true,
          timeout: const Duration(milliseconds: 20),
          initializer: () async {},
          appCheckActivator: () {
            started = true;
            return appCheck.future;
          },
        );
        expect(ok, isTrue);
        expect(started, isTrue, reason: 'App Check starts after init succeeds');
        appCheck.complete();
      },
    );

    test(
      'a throwing App Check activation still reports push available',
      () async {
        final ok = await initFirebaseSafely(
          isAndroid: true,
          initializer: () async {},
          appCheckActivator: () async => throw StateError('no App Check'),
        );
        expect(ok, isTrue);
        // Let the unawaited failure settle: it must be swallowed, not leak.
        await Future<void>.delayed(Duration.zero);
      },
    );

    test('a synchronously throwing App Check start is swallowed', () async {
      final ok = await initFirebaseSafely(
        isAndroid: true,
        initializer: () async {},
        appCheckActivator: () => throw StateError('sync'),
      );
      expect(ok, isTrue);
      await Future<void>.delayed(Duration.zero);
    });

    test('App Check never starts when init fails', () async {
      var started = false;
      final ok = await initFirebaseSafely(
        isAndroid: true,
        initializer: () async => throw StateError('no Firebase App'),
        appCheckActivator: () async => started = true,
      );
      expect(ok, isFalse);
      expect(started, isFalse);
    });

    test(
      'default hang guard is 30 seconds (generous, not a startup budget)',
      () {
        expect(kFirebaseInitTimeout, const Duration(seconds: 30));
      },
    );
  });

  // M515 (AUTH-D14) — App Check activation right after initializeApp.
  group('activateAppCheckSafely', () {
    test('debug build → debug provider carrying the define token', () async {
      AndroidAppCheckProvider? used;
      await activateAppCheckSafely(
        debug: true,
        debugToken: 'uuid-1',
        activator: (AndroidAppCheckProvider p) async => used = p,
        setAutoRefresh: _noAutoRefresh,
      );
      expect(used, isA<AndroidDebugProvider>());
      expect((used! as AndroidDebugProvider).debugToken, 'uuid-1');
    });

    test('debug build without a token → debug provider, null token', () async {
      AndroidAppCheckProvider? used;
      await activateAppCheckSafely(
        debug: true,
        debugToken: '',
        activator: (AndroidAppCheckProvider p) async => used = p,
        setAutoRefresh: _noAutoRefresh,
      );
      expect((used! as AndroidDebugProvider).debugToken, isNull);
    });

    test('profile / release → Play Integrity', () async {
      AndroidAppCheckProvider? used;
      await activateAppCheckSafely(
        debug: false,
        debugToken: '',
        activator: (AndroidAppCheckProvider p) async => used = p,
        setAutoRefresh: _noAutoRefresh,
      );
      expect(used, isA<AndroidPlayIntegrityProvider>());
    });

    test('an activation failure never throws (push stays on)', () async {
      await expectLater(
        activateAppCheckSafely(
          debug: false,
          activator: (_) async => throw StateError('no App Check'),
        ),
        completes,
      );
    });

    // M515 audit (perf LOW) — no proactive refresh: tokens are only needed on
    // SMS paths and fetched on demand, saving Play Integrity quota.
    test('turns token auto-refresh OFF after activating', () async {
      final List<String> calls = <String>[];
      await activateAppCheckSafely(
        debug: false,
        activator: (_) async => calls.add('activate'),
        setAutoRefresh: (bool enabled) async =>
            calls.add('autoRefresh=$enabled'),
      );
      expect(calls, <String>['activate', 'autoRefresh=false']);
    });

    // M515 cleanup (INFO) — the steps are guarded separately: a failed
    // auto-refresh disable never throws and does not undo the activation.
    test('an auto-refresh failure after activation never throws', () async {
      final List<String> calls = <String>[];
      await expectLater(
        activateAppCheckSafely(
          debug: false,
          activator: (_) async => calls.add('activate'),
          setAutoRefresh: (bool _) async => throw StateError('refresh'),
        ),
        completes,
      );
      expect(calls, <String>['activate']);
    });

    test('a failed activation skips the auto-refresh step', () async {
      var refreshCalled = false;
      await activateAppCheckSafely(
        debug: false,
        activator: (_) async => throw StateError('no App Check'),
        setAutoRefresh: (bool _) async => refreshCalled = true,
      );
      expect(refreshCalled, isFalse);
    });
  });
}
