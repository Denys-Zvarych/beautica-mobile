// Phase 17.1 — unit guard for the injectable wall-clock seam.
//
// `clockProvider` exists so production code that needs "now" reads it through
// Riverpod instead of calling `DateTime.now` directly, letting tests pin time
// to a fixed value for deterministic ordering. These tests assert the two
// contracts the rest of the suite relies on:
//   1. The default resolves to `DateTime.now` (a real, advancing clock).
//   2. `clockProvider.overrideWithValue(() => fixed)` makes every read return
//      the pinned instant — the exact override pattern documented in the
//      provider header and used by widget/golden tests.

import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('clockProvider', () {
    test('default resolves to a real, advancing clock near DateTime.now', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final before = DateTime.now();
      final now = container.read(clockProvider)();
      final after = DateTime.now();

      // The default clock returns the real instant — within the wall-clock
      // window bracketing the read (allow a small slop for slow CI).
      expect(
        now.isBefore(before.subtract(const Duration(seconds: 1))),
        isFalse,
      );
      expect(now.isAfter(after.add(const Duration(seconds: 1))), isFalse);
    });

    test('overrideWithValue pins "now" to a fixed instant', () {
      final fixed = DateTime(2026, 6, 14, 12);
      final container = ProviderContainer(
        overrides: [clockProvider.overrideWithValue(() => fixed)],
      );
      addTearDown(container.dispose);

      final now = container.read(clockProvider)();

      expect(now, equals(fixed));
    });

    test('overridden clock returns the same fixed instant on every read', () {
      final fixed = DateTime(2026, 1, 1, 0, 0, 0);
      final container = ProviderContainer(
        overrides: [clockProvider.overrideWithValue(() => fixed)],
      );
      addTearDown(container.dispose);

      final first = container.read(clockProvider)();
      final second = container.read(clockProvider)();

      expect(first, equals(fixed));
      expect(second, equals(fixed));
      expect(first, equals(second));
    });
  });
}
