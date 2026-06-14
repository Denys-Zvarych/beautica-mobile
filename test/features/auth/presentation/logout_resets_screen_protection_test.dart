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
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
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
}
