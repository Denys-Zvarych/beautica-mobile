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
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _MockScheduleRepository extends Mock implements ScheduleRepository {}

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
}
