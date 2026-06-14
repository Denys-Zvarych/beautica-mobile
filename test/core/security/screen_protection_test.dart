// Unit tests for the ref-counted ScreenProtectionManager (SEC MEDIUM-1/-2).
//
// The native ScreenProtector calls are all `!kDebugMode`-guarded, so under the
// test runner (kDebugMode == true) `_enable()` / `_disable()` are no-ops — no
// platform channel is touched. These tests therefore assert the OBSERVABLE
// reference-count contract via the `@visibleForTesting` [acquirerCount] getter:
//   • 0 → 1 enables (count reaches 1 only on the first acquire),
//   • 1 → 0 disables (count reaches 0 only when the last releaser releases),
//   • underflow guard (a stray release never drives the count below zero),
//   • reset() zeroes the count regardless of how many acquirers were live.
//
// Pure Dart: no widget tree, no ProviderScope. Layer: Unit.

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScreenProtectionManager ref-count', () {
    late ScreenProtectionManager manager;

    setUp(() {
      manager = ScreenProtectionManager();
    });

    test('starts at zero acquirers', () {
      expect(manager.acquirerCount, 0);
    });

    test('acquire increments the count (0 → 1 enables)', () {
      manager.acquire();

      expect(manager.acquirerCount, 1);
    });

    test('nested acquires stack the count without re-enabling', () {
      manager.acquire();
      manager.acquire();
      manager.acquire();

      expect(manager.acquirerCount, 3);
    });

    test('release decrements the count back toward zero (1 → 0 disables)', () {
      manager.acquire();
      manager.release();

      expect(manager.acquirerCount, 0);
    });

    test('a stacked pair only reaches zero on the last release', () {
      manager.acquire();
      manager.acquire();

      manager.release();
      expect(
        manager.acquirerCount,
        1,
        reason: 'protection must stay live while a second acquirer holds it',
      );

      manager.release();
      expect(manager.acquirerCount, 0);
    });

    test('underflow guard: release on an empty manager stays at zero', () {
      manager.release();

      expect(
        manager.acquirerCount,
        0,
        reason: 'a stray release must never drive the count below zero',
      );
    });

    test(
      'underflow guard: extra release after balance never goes negative',
      () {
        manager.acquire();
        manager.release();
        // One release too many.
        manager.release();

        expect(manager.acquirerCount, 0);
      },
    );

    test('reset zeroes the count regardless of live acquirers', () {
      manager.acquire();
      manager.acquire();
      manager.acquire();
      expect(manager.acquirerCount, 3);

      manager.reset();

      expect(
        manager.acquirerCount,
        0,
        reason:
            'reset() must force the count to zero so a never-disposed PII '
            'screen cannot leave protection latched across the auth boundary',
      );
    });

    test('after reset, a fresh acquire re-enables from zero', () {
      manager.acquire();
      manager.reset();

      manager.acquire();

      expect(manager.acquirerCount, 1);
    });
  });
}
