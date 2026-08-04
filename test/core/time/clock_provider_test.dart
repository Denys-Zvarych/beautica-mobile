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
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

void main() {
  group('clockProvider', () {
    test('default resolves to a real, advancing clock near DateTime.now', () {
      final container = ProviderContainer(retry: beauticaProviderRetry);
      addTearDown(container.dispose);

      // This test's SUBJECT is that the UN-overridden clockProvider returns the
      // real device instant. `before`/`after` bracket the read as absolute
      // instants and are consumed only by `.isBefore`/`.isAfter` against it —
      // no calendar day is ever derived from either, so Kyiv-anchoring them via
      // kyivToday would destroy the very property under test.
      // instant-ok: opening half of an absolute-instant bracket; see above
      final before = DateTime.now();
      final now = container.read(clockProvider)();
      // instant-ok: closing half of the bracket above — same rationale.
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
      final fixed = DateTime.utc(2026, 6, 14, 12);
      final container = ProviderContainer(
        retry: beauticaProviderRetry,
        overrides: [clockProvider.overrideWithValue(() => fixed)],
      );
      addTearDown(container.dispose);

      final now = container.read(clockProvider)();

      expect(now, equals(fixed));
    });

    test('overridden clock returns the same fixed instant on every read', () {
      final fixed = DateTime.utc(2026, 1, 1, 0, 0, 0);
      final container = ProviderContainer(
        retry: beauticaProviderRetry,
        overrides: [clockProvider.overrideWithValue(() => fixed)],
      );
      addTearDown(container.dispose);

      final first = container.read(clockProvider)();
      final second = container.read(clockProvider)();

      expect(first, equals(fixed));
      expect(second, equals(fixed));
      expect(first, equals(second));
    });

    test('is keepAlive — state survives its last listener being removed '
        '(single retained instance, not rebuilt)', () async {
      // Directly proves the `@Riverpod(keepAlive: true)` contract that the
      // rest of the suite relies on only indirectly. We override the create
      // fn so it (a) counts how many times the provider is built and (b)
      // hands back a *fresh* closure each build, making `identical` a sound
      // rebuild detector. `overrideWith` swaps the body only — it preserves
      // the provider's intrinsic keepAlive (non-autoDispose) nature, so this
      // exercises the real disposal policy. For an autoDispose provider the
      // element would be disposed once its last listener is removed and the
      // next read would re-run the body (buildCount == 2, new instance).
      var buildCount = 0;
      final container = ProviderContainer(
        retry: beauticaProviderRetry,
        overrides: [
          clockProvider.overrideWith((ref) {
            buildCount++;
            final fixed = DateTime.utc(2026, 6, 14, 12);
            return () => fixed;
          }),
        ],
      );
      addTearDown(container.dispose);

      // Materialise the provider through a transient listener.
      final sub = container.listen(clockProvider, (_, _) {});
      final first = container.read(clockProvider);
      expect(buildCount, 1);

      // Remove the only listener and let any scheduled disposal run.
      sub.close();
      await Future<void>.delayed(Duration.zero);

      // keepAlive: the element was retained, so the body did NOT re-run and
      // the very same instance is returned.
      final second = container.read(clockProvider);
      expect(
        buildCount,
        1,
        reason:
            'keepAlive provider must not rebuild after its last '
            'listener is removed',
      );
      expect(
        identical(first, second),
        isTrue,
        reason: 'keepAlive provider must return the same retained instance',
      );
    });
  });
}
