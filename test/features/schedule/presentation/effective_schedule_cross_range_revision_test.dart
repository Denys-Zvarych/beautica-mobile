// Phase 244 follow-up — REGRESSION for the user-reported bug: the master
// saved per-date custom hours in the editor, opened «Мої записи», and the
// day still showed the gray "not worked" state.
//
// ROOT CAUSE (see `overrides_revision_provider.dart`'s header for the full
// story): the schedule editor mutates `overridesProvider` under a MONTH
// `ScheduleRange`; «Мої записи» watches `effectiveScheduleProvider` under a
// SINGLE-DAY range — distinct family members. `EffectiveScheduleNotifier
// .build`'s reactive `ref.watch(overridesProvider(range).future)` link only
// ever reaches an instance keyed to the SAME range, so the day-range instance
// never recomputed, and `ref.keepAlive()` pinned its stale value for up to
// 5 minutes.
//
// This test reproduces the exact cross-range shape on the REAL provider
// graph (no widget tree needed — this is a provider-level bug):
//   1. resolve `effectiveScheduleProvider(scope, dayRange)` to a stale NO_SCHEDULE
//      verdict, and keep it WATCHED (mirrors «Мої записи» staying open);
//   2. `putOverride(...)` on `overridesProvider(scope, monthRange)` against a fake
//      repo that now serves `effectiveSchedule` as OVERRIDE_CUSTOM /
//      times:[11:00] (mirrors the server having genuinely persisted the
//      write);
//   3. assert a subsequent read of the DAY range reflects the new data —
//      WITHOUT this test ever calling `ref.invalidate`/`ref.refresh` itself.
//
// Must be RED before the fix (the day range never recomputes) and GREEN
// after. Verified here by reverting the `overridesRevisionProvider.bump()`
// call in [OverridesNotifier._mutate] rather than by assertion-tampering —
// see the QA report's mutation-verification log for the exact diff and
// observed failure.

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository_provider.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_scope.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/effective_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/overrides_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockScheduleRepository extends Mock implements ScheduleRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      ScheduleOverride.dayOff(
        start: DateTime(2026, 6, 1),
        end: DateTime(2026, 6, 1),
      ),
    );
  });

  test('putOverride under a MONTH range makes an ALREADY-WATCHED DAY range '
      'instance recompute — no manual invalidate needed', () async {
    final repo = _MockScheduleRepository();
    final monthRange = ScheduleRange.month(DateTime(2026, 6, 15));
    const scope = ScheduleScope.own(masterId: 'cross-range-revision-master');
    final dayRange = ScheduleRange(
      from: DateTime(2026, 6, 20),
      to: DateTime(2026, 6, 20),
    );

    // Both families' `listOverrides` reload — empty is enough, this test
    // does not exercise the overrides list itself.
    when(
      () => repo.listOverrides(any(), any()),
    ).thenAnswer((_) async => const <ScheduleOverride>[]);

    // The server's effective-schedule projection — STALE (NO_SCHEDULE)
    // until the write below, then OVERRIDE_CUSTOM/times:[11:00]. Keyed off
    // a flag rather than call count, since the fix's whole point is that
    // the day range refetches on its OWN — this must reflect whatever the
    // "server" holds at the moment of each call, not a scripted sequence.
    bool written = false;
    when(() => repo.effectiveSchedule(any(), any())).thenAnswer((_) async {
      if (!written) {
        return <EffectiveDay>[
          EffectiveDay(
            date: dayRange.from,
            source: EffectiveSource.noSchedule,
            intervals: const <WorkInterval>[],
          ),
        ];
      }
      return <EffectiveDay>[
        EffectiveDay(
          date: dayRange.from,
          source: EffectiveSource.overrideCustom,
          intervals: const <WorkInterval>[],
          times: const <TimeOfDay>[TimeOfDay(hour: 11, minute: 0)],
        ),
      ];
    });

    when(() => repo.putOverride(any(), cancelOverlapping: false)).thenAnswer(
      (inv) async => inv.positionalArguments.first as ScheduleOverride,
    );

    final container = ProviderContainer(
      retry: beauticaProviderRetry,
      overrides: [
        scheduleRepositoryProvider.overrideWith((ref, scope) => repo),
      ],
    );
    addTearDown(container.dispose);

    // ── 1. Resolve the DAY range to the stale NO_SCHEDULE verdict, and
    // keep it WATCHED — mirrors «Мої записи» staying open on that day.
    final List<EffectiveDay> initial = await container.read(
      effectiveScheduleProvider(scope, dayRange).future,
    );
    expect(initial.single.source, EffectiveSource.noSchedule);

    final ProviderSubscription<AsyncValue<List<EffectiveDay>>> dayListener =
        container.listen<AsyncValue<List<EffectiveDay>>>(
          effectiveScheduleProvider(scope, dayRange),
          (_, _) {},
        );
    addTearDown(dayListener.close);

    // ── 2. The "server" now holds the fresh override; the master saves it
    // through the editor's MONTH-range notifier.
    written = true;
    await container
        .read(overridesProvider(scope, monthRange).notifier)
        .putOverride(
          ScheduleOverride.explicitTimes(
            start: dayRange.from,
            end: dayRange.from,
            times: const <TimeOfDay>[TimeOfDay(hour: 11, minute: 0)],
          ),
        );

    // ── 3. The DAY range must reflect the new data — no invalidate/refresh
    // call from this test.
    final List<EffectiveDay> after = await container.read(
      effectiveScheduleProvider(scope, dayRange).future,
    );
    expect(
      after.single.source,
      EffectiveSource.overrideCustom,
      reason:
          'the day-range instance must have recomputed off the '
          'cross-range revision bump — see overrides_revision_provider.dart',
    );
    expect(after.single.times, <TimeOfDay>[
      const TimeOfDay(hour: 11, minute: 0),
    ]);
  });
}
