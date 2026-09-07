// Phase 312 — REGRESSION guard for `EffectiveScheduleRangeTracker`'s re-key
// onto `(ScheduleScope, ScheduleRange)` (D7's sharpest trap, per the phase
// brief): "tracker keyed on range only → cross-master re-pin leak".
//
// `effectiveScheduleProvider` gained a `ScheduleScope` family parameter
// alongside the pre-existing `ScheduleRange` one. If the tracker
// (`effective_schedule_notifier.dart`) — or `WeeklyScheduleNotifier
// ._invalidateEffectiveScheduleWindows`'s SCOPE-FILTER over it — ever
// regressed to treating two DIFFERENT scopes' SAME range as the same
// candidate, saving master A's weekly template would eager-re-read (and,
// worse, in the disposal-race shape this whole gate exists for, could even
// dispose-then-resurrect) a DIFFERENT viewed master B's already-open
// calendar — a cross-master data leak, not merely a wasted fetch.
//
// This test pins the boundary directly on the real provider graph (no
// widget tree needed — the bug lives entirely in the provider chain):
//   1. Two DISTINCT `ScheduleScope.salonMaster` values (master A, master B)
//      each watch `effectiveScheduleProvider` under the IDENTICAL
//      `ScheduleRange` — the exact shape a range-only key would conflate.
//   2. `WeeklyScheduleNotifier(scopeA).save(...)` — a template edit for A.
//   3. Assert: A's `effectiveSchedule` repo call count increases (the fix
//      DOES still re-pin A's own window); B's does NOT (the fix must NEVER
//      touch a different scope's window just because the range matches).
//
// MUTATION-VERIFIED (this phase): commenting out
// `_invalidateEffectiveScheduleWindows`'s `if (key.$1 != scope) continue;`
// filter line turns this test's "B is untouched" assertion RED — see the
// phase's mutation-testing log (mutation #7, "tracker keyed on range only →
// cross-master re-pin leak").

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository_provider.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_scope.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/effective_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';
import 'package:beautica_mobile/features/schedule/presentation/weekly_schedule_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockScheduleRepository extends Mock implements ScheduleRepository {}

const ScheduleScope _scopeA = ScheduleScope.salonMaster(
  salonId: 'salon-1',
  masterId: 'master-a',
);
const ScheduleScope _scopeB = ScheduleScope.salonMaster(
  salonId: 'salon-1',
  masterId: 'master-b',
);

WeeklySchedule _openEndedTemplate() => WeeklySchedule(
  id: 'wt-a',
  validFrom: DateTime(2020, 1, 1),
  validTo: null,
  days: <TemplateDay>[
    for (int day = 1; day <= 7; day++)
      TemplateDay(dayOfWeek: day, label: 'day-$day', intervals: const []),
  ],
);

void main() {
  setUpAll(() {
    // mocktail requires a registered fallback for any non-primitive type
    // used with `any()` as a POSITIONAL matcher (here:
    // `repoA.upsertWeeklySchedule(any(), scheduleId: ...)`).
    registerFallbackValue(_openEndedTemplate());
  });

  test('a template save for scope A re-pins ONLY scope A\'s effective-schedule '
      'window under the SAME range — scope B\'s identical-range window is '
      'left untouched', () async {
    final repoA = _MockScheduleRepository();
    final repoB = _MockScheduleRepository();
    final sharedRange = ScheduleRange.month(DateTime(2026, 6, 15));

    for (final _MockScheduleRepository repo in [repoA, repoB]) {
      when(
        () => repo.listOverrides(any(), any()),
      ).thenAnswer((_) async => const <ScheduleOverride>[]);
      when(
        () => repo.effectiveSchedule(any(), any()),
      ).thenAnswer((_) async => const <EffectiveDay>[]);
      when(
        () => repo.listWeeklySchedules(),
      ).thenAnswer((_) async => <WeeklySchedule>[_openEndedTemplate()]);
    }
    when(
      () => repoA.upsertWeeklySchedule(
        any(),
        scheduleId: any(named: 'scheduleId'),
      ),
    ).thenAnswer((_) async => _openEndedTemplate());

    final container = ProviderContainer(
      retry: beauticaProviderRetry,
      overrides: [
        scheduleRepositoryProvider.overrideWith((ref, scope) {
          if (scope == _scopeA) return repoA;
          if (scope == _scopeB) return repoB;
          throw StateError('unexpected scope $scope');
        }),
      ],
    );
    addTearDown(container.dispose);

    // Keep BOTH scopes' identical-range windows genuinely watched —
    // mirrors an owner/admin who has two different masters' calendars
    // open in the same session (or, more simply, the same tracker
    // candidate set an owner switching between two masters would build up
    // across the session's lifetime).
    final subA = container.listen(
      effectiveScheduleProvider(_scopeA, sharedRange),
      (_, _) {},
      fireImmediately: true,
    );
    final subB = container.listen(
      effectiveScheduleProvider(_scopeB, sharedRange),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subA.close);
    addTearDown(subB.close);
    await container.read(
      effectiveScheduleProvider(_scopeA, sharedRange).future,
    );
    await container.read(
      effectiveScheduleProvider(_scopeB, sharedRange).future,
    );

    clearInteractions(repoA);
    clearInteractions(repoB);
    when(
      () => repoA.effectiveSchedule(any(), any()),
    ).thenAnswer((_) async => const <EffectiveDay>[]);
    when(
      () => repoB.effectiveSchedule(any(), any()),
    ).thenAnswer((_) async => const <EffectiveDay>[]);

    // Drop the two subscriptions so both windows become "pinned but
    // unwatched", covered only by EffectiveScheduleNotifier's own TTL —
    // the exact precondition FIX D's `wasPinned` idiom targets, mirroring
    // how a master pages away from a week/month in the real screen.
    subA.close();
    subB.close();

    // The edit — scope A's template.
    await container
        .read(weeklyScheduleProvider(_scopeA).notifier)
        .save(_openEndedTemplate(), scheduleId: 'wt-a');

    // The eager `ref.read()` inside `_invalidateEffectiveScheduleWindows`
    // starts scope A's rebuild synchronously, but `EffectiveScheduleNotifier
    // .build` itself is async (it re-awaits `overridesProvider(scope,
    // range).future` before reaching the `effectiveSchedule(...)` call) —
    // `save()` does not await that rebuild, so give the pending microtasks
    // a tick to run before asserting the repo call actually happened.
    await Future<void>.delayed(Duration.zero);

    // Scope A's window WAS re-pinned (the fix still works for its own
    // scope): its effectiveSchedule was re-fetched at least once.
    verify(
      () => repoA.effectiveSchedule(any(), any()),
    ).called(greaterThanOrEqualTo(1));
    // Scope B's window must NOT have been touched — the cross-master
    // leak this test exists to catch.
    verifyNever(() => repoB.effectiveSchedule(any(), any()));
  });
}
