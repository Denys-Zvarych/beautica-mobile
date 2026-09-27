// Phase 314 — the [ServiceTarget] value contract.
//
// WHY THIS FILE EXISTS AT ALL.
// As FIRST written in phase 314, `SalonMasterTarget` was a plain `final class`
// with two `String` fields and NO `==` / `hashCode`, i.e. identity equality.
// That was not a cosmetic gap: `serviceTargetProvider` is a riverpod
// `Provider`, and
// riverpod gates dependent rebuilds on `!=`
// (`riverpod-3.1.0/lib/src/providers/provider.dart:349`, and
// `override_with_value.dart:78` for the `overrideWithValue` path). With identity
// equality, a `ProviderScope` that rebuilds and hands down a FRESH
// `SalonMasterTarget` carrying the SAME two ids tears down and rebuilds
// `serviceRepositoryProvider` — a `keepAlive: true` provider a dozen call sites
// read — for no semantic change. Phase 317 is the phase that will build that
// target inside a route subtree, i.e. the phase that turns this from latent into
// live.
//
// `ScheduleScope` — this track's exact analogue, the viewer-scope union of the
// schedule feature — is `@freezed` for precisely this reason
// (`lib/features/schedule/domain/schedule_scope.dart:33`). `ServiceTarget`
// should mirror it.
//
// STATUS OF THE CASES BELOW.
// The fix landed in the phase 314 audit pass: `ServiceTarget` is now `@freezed`
// (`lib/features/services/domain/service_target.dart`), so the group below runs
// unskipped and green. Do NOT "restore" the plain sealed class — the phase
// doc's D1 was superseded by that perf HIGH.
//
// MUTATION RECIPE — freezed emits the equality TWICE, and BOTH must be stripped.
// `service_target.freezed.dart` carries `operator ==` / `hashCode` in two
// places (line numbers verified 2026-09-10; freezed output shifts, so re-grep
// `"bool operator ==\|int get hashCode"` rather than trusting these):
//
//   a. the BASE mixin `_ServiceTarget`     — `:28-35`
//   b. `SalonMasterTarget`'s own override  — `:222-229`
//
// (b) merely SHADOWS (a). Both are `runtimeType`-plus-fields comparisons, so
// deleting (b) alone leaves the inherited (a) doing the same work:
//
//   strip (b) ONLY  → all 5 cases in this file stay GREEN, and
//                     `service_repository_provider_test.dart`'s `an EQUAL-VALUED
//                     but distinct target does NOT rebuild the repository` stays
//                     GREEN too. The recipe is INSUFFICIENT — a reader who stops
//                     here wrongly concludes these pins are vacuous.
//   strip BOTH      → cases 1 ("same ids are ==") and 2 ("share a hashCode") go
//                     RED, and that provider pin goes RED as well. Cases 3, 4
//                     and the union-shape case stay green by construction — they
//                     assert INequality and exhaustiveness, which identity
//                     equality still satisfies.
//
// Restore with a `cp` backup, never `git checkout`
// (`project_agents_git_checkout_destroys_work`).
//
// Pure Dart: `ServiceTarget` lives in `domain/` and imports no Flutter.

import 'package:beautica_mobile/features/services/domain/service_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ── The identity-equality gap (perf HIGH) ────────────────────────────────
  //
  // `ServiceTarget` is `@freezed`, so this group runs. Do not "fix" these tests
  // to match identity equality — the whole point is that identity equality is
  // the defect.
  group('SalonMasterTarget value equality', () {
    /// Two SEPARATELY CONSTRUCTED targets carrying identical ids.
    ///
    /// The ids are assembled at runtime (`join`) on purpose. Writing two
    /// `const SalonMasterTarget(...)` literals would let the compiler
    /// canonicalise them to ONE instance, and every assertion below would
    /// then pass under identity equality — vacuous in exactly the way
    /// `project_fixture_values_can_defang_assertions` warns about. It also
    /// keeps `prefer_const_constructors: error` satisfied.
    (SalonMasterTarget, SalonMasterTarget) twoEqualTargets() {
      final salonId = <String>['salon', 'row', 'uuid'].join('-');
      final masterId = <String>['master', 'row', 'uuid'].join('-');
      return (
        SalonMasterTarget(salonId: salonId, masterId: masterId),
        SalonMasterTarget(salonId: salonId, masterId: masterId),
      );
    }

    test('two instances carrying the same ids are ==', () {
      final (a, b) = twoEqualTargets();

      expect(
        identical(a, b),
        isFalse,
        reason:
            'guards the guard: if these were canonicalised to one instance '
            'the assertion below would pass under identity equality and '
            'prove nothing',
      );
      expect(a, equals(b));
    });

    test('two instances carrying the same ids share a hashCode', () {
      final (a, b) = twoEqualTargets();

      expect(a.hashCode, b.hashCode);
    });

    test('a different salonId makes them unequal', () {
      const a = SalonMasterTarget(
        salonId: 'salon-row-uuid',
        masterId: 'master-row-uuid',
      );
      const b = SalonMasterTarget(
        salonId: 'a-DIFFERENT-salon',
        masterId: 'master-row-uuid',
      );

      expect(a, isNot(equals(b)));
    });

    test('a different masterId makes them unequal', () {
      const a = SalonMasterTarget(
        salonId: 'salon-row-uuid',
        masterId: 'master-row-uuid',
      );
      const b = SalonMasterTarget(
        salonId: 'salon-row-uuid',
        masterId: 'a-DIFFERENT-master',
      );

      expect(
        a,
        isNot(equals(b)),
        reason:
            'masterId is the `masters` ROW id — two masters on the same '
            'salon roster must never collapse to one target',
      );
    });
  });

  // ── Always green: the sealed-union shape itself ──────────────────────────
  //
  // Not skipped — this holds before and after the @freezed conversion, and it
  // is what makes `_assertAuthenticated`'s `switch` exhaustive (a third state
  // added without a repository arm is a COMPILE error, not a red test).
  test('ServiceTarget is a two-state union a switch resolves exhaustively', () {
    String describe(ServiceTarget? target) => switch (target) {
      null => 'independent-master',
      SalonMasterTarget(:final salonId, :final masterId) =>
        'salon:$salonId/master:$masterId',
    };

    expect(describe(null), 'independent-master');
    expect(
      describe(const SalonMasterTarget(salonId: 's-1', masterId: 'm-1')),
      'salon:s-1/master:m-1',
    );
  });
}
