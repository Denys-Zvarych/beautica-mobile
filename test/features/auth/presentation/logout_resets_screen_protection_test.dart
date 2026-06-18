// Regression test (SEC, M5-adjacent): AuthNotifier.logout() must force-reset the
// app-wide ScreenProtectionManager so a PII screen that was never disposed (e.g.
// a logout triggered from a dialog above a live acquirer) cannot leave native
// screenshot protection latched across the auth boundary.
//
// The manager is a keepAlive singleton; logout calls `.reset()` on it. We
// override `screenProtectionProvider` with a spy subclass that records reset()
// calls and drive the REAL AuthNotifier.logout() through a ProviderContainer.
//
// Layer: Unit (ProviderContainer — no widget tree).

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/storage/secure_storage.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

/// Spy manager that records how many times [reset] was invoked. `reset()`'s
/// native teardown is `!kDebugMode`-guarded so it is a no-op under the test
/// runner; we only assert the call was made.
class _SpyScreenProtectionManager extends ScreenProtectionManager {
  int resetCalls = 0;

  @override
  void reset() {
    resetCalls++;
    super.reset();
  }
}

/// Manager whose [reset] THROWS a [PlatformException] — reproduces the RELEASE
/// failure mode of `ScreenProtectionManager._disable()` (the `screen_protector`
/// platform channels can throw on real devices) WITHOUT needing release mode.
/// The real `_disable()` is a `kDebugMode` no-op under the test runner, so the
/// only way to exercise the unguarded `ref.read(screenProtectionProvider)
/// .reset()` call at logout is to inject a throwing override here.
class _ThrowingScreenProtectionManager extends ScreenProtectionManager {
  int resetCalls = 0;

  @override
  void reset() {
    resetCalls++;
    throw PlatformException(
      code: 'channel-error',
      message: 'preventScreenshotOff failed on the platform channel',
    );
  }
}

/// SecureStorage fake that records whether [deleteAll] ran, so the regression
/// test can prove the session was wiped before any throw from reset().
final class _RecordingSecureStorage implements SecureStorage {
  bool deleteAllCalled = false;

  @override
  Future<void> deleteAll() async {
    deleteAllCalled = true;
  }

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> writeRefreshToken(String token) async {}

  @override
  Future<String?> readUserJson() async => null;

  @override
  Future<void> writeUserJson(String json) async {}
}

void main() {
  test(
    'AuthNotifier.logout() invokes screenProtectionProvider.reset()',
    () async {
      final spy = _SpyScreenProtectionManager();
      // Simulate a live PII acquirer that was never released.
      spy.acquire();
      expect(spy.acquirerCount, 1);

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
          screenProtectionProvider.overrideWithValue(spy),
        ],
      );
      addTearDown(container.dispose);

      // Settle the AuthNotifier build (cold start → unauthenticated).
      await container.read(authProvider.future);

      await container.read(authProvider.notifier).logout();

      expect(
        spy.resetCalls,
        1,
        reason:
            'logout() must call screenProtectionProvider.reset() exactly once so '
            'a never-disposed PII screen cannot leave protection latched.',
      );
      expect(
        spy.acquirerCount,
        0,
        reason: 'reset() must zero the live acquirer count on logout.',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // Regression (release-mode logout bug) — a THROWING screenProtection.reset()
  // must not break the logout. Today the call at auth_notifier.dart L713 is
  // NOT wrapped in try/catch, so when `_disable()` throws on a real device the
  // throw escapes BEFORE state is set to Unauthenticated (L717): storage is
  // wiped (logged out on relaunch) but the UI catch in logout_action.dart shows
  // logoutFailed. This test injects a throwing reset() to reproduce that path
  // in debug and asserts the CORRECT post-fix behaviour. It MUST FAIL red
  // against today's unfixed code (the PlatformException propagates and state
  // never reaches Unauthenticated).
  // ---------------------------------------------------------------------------
  test(
    'logout() tolerates a throwing screenProtection.reset(): storage is wiped, '
    'state ends Unauthenticated, and no error surfaces',
    () async {
      final manager = _ThrowingScreenProtectionManager();
      // Simulate a live PII acquirer that was never released (the scenario the
      // logout-time reset exists to clean up).
      manager.acquire();

      final storage = _RecordingSecureStorage();

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          secureStorageProvider.overrideWith((_) => storage),
          screenProtectionProvider.overrideWithValue(manager),
        ],
      );
      addTearDown(container.dispose);

      // Settle the AuthNotifier build (cold start → unauthenticated).
      await container.read(authProvider.future);

      // logout() must complete WITHOUT rethrowing — the unguarded reset() throw
      // must be tolerated exactly like the best-effort server-revocation call.
      await expectLater(
        container.read(authProvider.notifier).logout(),
        completes,
        reason:
            'a PlatformException from screenProtection.reset() must not escape '
            'logout() — it would surface logoutFailed in the UI while the '
            'session is already wiped (logged out on relaunch).',
      );

      // The session WAS wiped before the throw — proves storage.deleteAll ran.
      expect(
        storage.deleteAllCalled,
        isTrue,
        reason:
            'logout() must wipe secure storage regardless of reset() faults.',
      );

      // reset() was actually exercised (the throwing path was reached).
      expect(manager.resetCalls, 1);

      // State must end at AsyncData<Unauthenticated> so the router guard
      // redirects to /login and the UI treats the logout as a success.
      final after = container.read(authProvider);
      expect(after, isA<AsyncData<AuthSession>>());
      expect(after.value, equals(const AuthSession.unauthenticated()));
    },
  );
}
