// Phase 15.1 — Unit tests for [WeeklyScheduleNotifier].
//
// Strategy: override scheduleRepositoryProvider with a mocktail mock; drive the
// notifier through a fresh ProviderContainer per test (disposed via tearDown).
//
// Covers: save() upserts then re-emits the server-confirmed (re-loaded) list;
// on success it invalidates the effective-schedule cache so a watched window
// re-fetches; a failed save becomes AsyncError and performs NO invalidation.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository_provider.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/effective_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';
import 'package:beautica_mobile/features/schedule/presentation/weekly_schedule_notifier.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

class _MockScheduleRepository extends Mock implements ScheduleRepository {}

/// A 7-day schedule whose Monday is an EXPLICIT_TIMES working day carrying
/// [mondayTimes]; the rest of the week is a day-off. Empty [mondayTimes] gives
/// an EXPLICIT_TIMES Monday with NO times — the invalid working-day case.
WeeklySchedule _explicitSchedule(List<TimeOfDay> mondayTimes) => WeeklySchedule(
  validFrom: DateTime(2026, 6, 1),
  validTo: null,
  days: <TemplateDay>[
    TemplateDay(
      dayOfWeek: 1,
      label: 'd1',
      mode: WeekdayMode.explicitTimes,
      intervals: const <WorkInterval>[],
      times: mondayTimes,
    ),
    for (var dow = 2; dow <= 7; dow++)
      TemplateDay(
        dayOfWeek: dow,
        label: 'd$dow',
        intervals: const <WorkInterval>[],
      ),
  ],
);

WeeklySchedule _schedule({String? id, int validFromDay = 1}) => WeeklySchedule(
  id: id,
  validFrom: DateTime(2026, 6, validFromDay),
  validTo: null,
  days: <TemplateDay>[
    for (var dow = 1; dow <= 7; dow++)
      TemplateDay(
        dayOfWeek: dow,
        label: 'd$dow',
        intervals: const <WorkInterval>[],
      ),
  ],
);

void main() {
  late _MockScheduleRepository repo;

  setUpAll(() {
    registerFallbackValue(_schedule());
  });

  setUp(() {
    repo = _MockScheduleRepository();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      retry: beauticaProviderRetry,
      overrides: [scheduleRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('build loads the weekly templates from the repository', () async {
    when(
      () => repo.listWeeklySchedules(),
    ).thenAnswer((_) async => <WeeklySchedule>[_schedule(id: 's1')]);

    final container = makeContainer();
    final list = await container.read(weeklyScheduleProvider.future);

    expect(list, hasLength(1));
    expect(list.single.id, 's1');
  });

  test('save upserts then re-emits the server-confirmed reloaded list', () async {
    // Initial load is empty; after save the repo returns the persisted row.
    var loadCount = 0;
    when(() => repo.listWeeklySchedules()).thenAnswer((_) async {
      loadCount++;
      return loadCount == 1
          ? <WeeklySchedule>[]
          : <WeeklySchedule>[_schedule(id: 's1', validFromDay: 15)];
    });
    when(
      () => repo.upsertWeeklySchedule(
        any(),
        scheduleId: any(named: 'scheduleId'),
      ),
    ).thenAnswer((_) async => _schedule(id: 's1'));

    final container = makeContainer();
    await container.read(weeklyScheduleProvider.future); // initial empty load

    await container.read(weeklyScheduleProvider.notifier).save(_schedule());

    final state = container.read(weeklyScheduleProvider);
    expect(state.hasError, isFalse);
    expect(state.value, hasLength(1));
    // The re-emitted state is the RELOADED list, not the upsert's return value.
    expect(state.value!.single.validFrom, DateTime(2026, 6, 15));
    verify(() => repo.upsertWeeklySchedule(any(), scheduleId: null)).called(1);
    verify(() => repo.listWeeklySchedules()).called(2); // build + reload
  });

  test(
    'save invalidates the effective-schedule cache → watched window refetches',
    () async {
      when(
        () => repo.listWeeklySchedules(),
      ).thenAnswer((_) async => <WeeklySchedule>[]);
      when(
        () => repo.upsertWeeklySchedule(
          any(),
          scheduleId: any(named: 'scheduleId'),
        ),
      ).thenAnswer((_) async => _schedule(id: 's1'));
      when(
        () => repo.effectiveSchedule(any(), any()),
      ).thenAnswer((_) async => <EffectiveDay>[]);
      // `EffectiveScheduleNotifier.build` now `await`s `overridesProvider(range)`
      // (the reactive read-after-write dependency the save-refresh fix added), so
      // the genuine `OverridesNotifier` runs end-to-end and its `build` calls
      // `listOverrides`. Stub it so the effective window resolves.
      when(
        () => repo.listOverrides(any(), any()),
      ).thenAnswer((_) async => const <ScheduleOverride>[]);

      final container = makeContainer();
      final range = ScheduleRange(
        from: DateTime(2026, 6, 1),
        to: DateTime(2026, 6, 30),
      );

      // Keep the effective window watched so it re-fetches when invalidated.
      final sub = container.listen(
        effectiveScheduleProvider(range),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      await container.read(effectiveScheduleProvider(range).future);

      await container.read(weeklyScheduleProvider.future);
      await container.read(weeklyScheduleProvider.notifier).save(_schedule());

      // Allow the invalidated effective provider to rebuild.
      await container.read(effectiveScheduleProvider(range).future);

      // Fetched once on first watch, once after the save invalidation.
      verify(() => repo.effectiveSchedule(any(), any())).called(2);
    },
  );

  test(
    'failed save → AsyncError and NO effective-schedule invalidation',
    () async {
      when(
        () => repo.listWeeklySchedules(),
      ).thenAnswer((_) async => <WeeklySchedule>[]);
      when(
        () => repo.upsertWeeklySchedule(
          any(),
          scheduleId: any(named: 'scheduleId'),
        ),
      ).thenThrow(const ServerFailure(statusCode: 500));
      when(
        () => repo.effectiveSchedule(any(), any()),
      ).thenAnswer((_) async => <EffectiveDay>[]);
      // Same as above: the effective window's `build` awaits `overridesProvider`,
      // whose genuine notifier calls `listOverrides`. Stub it so the watched
      // window resolves on its first (and only) fetch.
      when(
        () => repo.listOverrides(any(), any()),
      ).thenAnswer((_) async => const <ScheduleOverride>[]);

      final container = makeContainer();
      final range = ScheduleRange(
        from: DateTime(2026, 6, 1),
        to: DateTime(2026, 6, 30),
      );
      final sub = container.listen(
        effectiveScheduleProvider(range),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      await container.read(effectiveScheduleProvider(range).future);

      await container.read(weeklyScheduleProvider.future);
      await container.read(weeklyScheduleProvider.notifier).save(_schedule());

      final state = container.read(weeklyScheduleProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<ServerFailure>());

      // No invalidation → effective window still resolves from its first fetch.
      await container.read(effectiveScheduleProvider(range).future);
      verify(() => repo.effectiveSchedule(any(), any())).called(1);
    },
  );

  // ───────────────────────────────────────────────────────────────────────────
  // Phase 15.7 — EXPLICIT_TIMES pre-network validation guard.
  // ───────────────────────────────────────────────────────────────────────────

  group('save — EXPLICIT_TIMES validation', () {
    test(
      'accepts a working EXPLICIT_TIMES day and sends mode + times',
      () async {
        when(
          () => repo.listWeeklySchedules(),
        ).thenAnswer((_) async => <WeeklySchedule>[]);
        when(
          () => repo.upsertWeeklySchedule(
            any(),
            scheduleId: any(named: 'scheduleId'),
          ),
        ).thenAnswer((_) async => _schedule(id: 's1'));

        final container = makeContainer();
        await container.read(weeklyScheduleProvider.future);

        final schedule = _explicitSchedule(const <TimeOfDay>[
          TimeOfDay(hour: 9, minute: 0),
          TimeOfDay(hour: 13, minute: 0),
        ]);
        await container.read(weeklyScheduleProvider.notifier).save(schedule);

        expect(container.read(weeklyScheduleProvider).hasError, isFalse);

        // The persisted schedule reached the repo with the EXPLICIT_TIMES Monday
        // intact (mode + the discrete times, no intervals).
        final captured =
            verify(
                  () => repo.upsertWeeklySchedule(
                    captureAny(),
                    scheduleId: any(named: 'scheduleId'),
                  ),
                ).captured.single
                as WeeklySchedule;
        final mon = captured.days.firstWhere((d) => d.dayOfWeek == 1);
        expect(mon.mode, WeekdayMode.explicitTimes);
        expect(mon.times, <TimeOfDay>[
          const TimeOfDay(hour: 9, minute: 0),
          const TimeOfDay(hour: 13, minute: 0),
        ]);
        expect(mon.intervals, isEmpty);
      },
    );

    test('rejects a misaligned-time EXPLICIT_TIMES working day → '
        'ValidationFailure, no network call', () async {
      when(
        () => repo.listWeeklySchedules(),
      ).thenAnswer((_) async => <WeeklySchedule>[]);

      final container = makeContainer();
      await container.read(weeklyScheduleProvider.future);

      // A non-empty (so NOT a day-off) EXPLICIT_TIMES Monday whose single
      // start time is not 15-min aligned — an invalid working day. (An EMPTY
      // times list is treated as a DAY-OFF in EXPLICIT_TIMES mode and is
      // intentionally valid, so the reject path is exercised via alignment.)
      await container
          .read(weeklyScheduleProvider.notifier)
          .save(
            _explicitSchedule(const <TimeOfDay>[TimeOfDay(hour: 9, minute: 7)]),
          );

      final state = container.read(weeklyScheduleProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<ValidationFailure>());
      // Guard fired BEFORE any upsert — no network mutation.
      verifyNever(
        () => repo.upsertWeeklySchedule(
          any(),
          scheduleId: any(named: 'scheduleId'),
        ),
      );
    });

    test('INTERVAL save path is unchanged by the new guard', () async {
      var loadCount = 0;
      when(() => repo.listWeeklySchedules()).thenAnswer((_) async {
        loadCount++;
        return loadCount == 1
            ? <WeeklySchedule>[]
            : <WeeklySchedule>[_schedule(id: 's1')];
      });
      when(
        () => repo.upsertWeeklySchedule(
          any(),
          scheduleId: any(named: 'scheduleId'),
        ),
      ).thenAnswer((_) async => _schedule(id: 's1'));

      final container = makeContainer();
      await container.read(weeklyScheduleProvider.future);

      // A plain INTERVAL schedule (all day-off) still saves without the guard
      // tripping — EXPLICIT_TIMES validation ignores INTERVAL days entirely.
      await container.read(weeklyScheduleProvider.notifier).save(_schedule());

      expect(container.read(weeklyScheduleProvider).hasError, isFalse);
      verify(
        () => repo.upsertWeeklySchedule(any(), scheduleId: null),
      ).called(1);
    });
  });
}
