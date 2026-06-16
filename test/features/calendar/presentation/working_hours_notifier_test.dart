// Phase 6.1 — Unit tests for [WorkingHoursNotifier].
//
// Covers the AsyncNotifier contract that the Phase 6.2 editor relies on:
//   build()
//     - reads the week from WorkingHoursRepository.list() (a pure cache read).
//   save() happy path
//     - calls replaceAll() with the supplied week,
//     - emits AsyncData with the server-confirmed (gap-filled) result and
//       lands that exact week in state.
//   save() failure path
//     - a thrown Failure becomes AsyncError (AsyncValue.guard), never a raw
//       exception,
//     - on failure state is AsyncError (the prior week is not silently kept).
//
// Working hours are no longer carried on the master profile (the migration made
// list() a network read), so save() performs ONLY the repository write and does
// NOT invalidate masterProfileProvider. The old PERF-M2 cache-coherence
// invalidation is dead; no profile-rebuild scaffolding is needed here.
//
// Strategy:
//   Pure Dart — ProviderContainer + a mocktail WorkingHoursRepository. The
//   notifier's own keepAlive repository provider is overridden with the mock so
//   no profile/auth chain is constructed. No widget tree.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/calendar/data/working_hours_repository.dart';
import 'package:beautica_mobile/features/calendar/data/working_hours_repository_provider.dart';
import 'package:beautica_mobile/features/calendar/domain/working_hours.dart';
import 'package:beautica_mobile/features/calendar/presentation/working_hours_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockWorkingHoursRepository extends Mock
    implements WorkingHoursRepository {}

/// A dense, gap-filled week the repository would hand back.
List<WorkingHours> _week({bool active = true}) => [
  for (var day = 1; day <= 7; day++)
    WorkingHours(
      dayOfWeek: day,
      startTime: '09:00:00',
      endTime: '18:00:00',
      isActive: active && day <= 5,
    ),
];

ProviderContainer _makeContainer(_MockWorkingHoursRepository repo) {
  final container = ProviderContainer(
    overrides: [workingHoursRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUpAll(() {
    registerFallbackValue(<WorkingHours>[]);
  });

  late _MockWorkingHoursRepository repo;

  setUp(() {
    repo = _MockWorkingHoursRepository();
  });

  group('build', () {
    test('emits AsyncData with the week from repository.list()', () async {
      final cached = _week();
      when(() => repo.list()).thenAnswer((_) async => cached);

      final container = _makeContainer(repo);

      final week = await container.read(workingHoursProvider.future);

      expect(week, same(cached));
      expect(week, hasLength(7));
      verify(() => repo.list()).called(1);
    });
  });

  group('save — happy path', () {
    test('calls replaceAll with the supplied week', () async {
      when(() => repo.list()).thenAnswer((_) async => _week());
      when(() => repo.replaceAll(any())).thenAnswer((_) async => _week());

      final container = _makeContainer(repo);
      await container.read(workingHoursProvider.future);

      final outgoing = _week(active: false);
      await container.read(workingHoursProvider.notifier).save(outgoing);

      final captured =
          verify(() => repo.replaceAll(captureAny())).captured.single
              as List<WorkingHours>;
      expect(captured, same(outgoing));
    });

    test('emits AsyncData with the server-confirmed result', () async {
      final saved = _week();
      when(() => repo.list()).thenAnswer((_) async => _week(active: false));
      when(() => repo.replaceAll(any())).thenAnswer((_) async => saved);

      final container = _makeContainer(repo);
      await container.read(workingHoursProvider.future);

      await container.read(workingHoursProvider.notifier).save(_week());

      final state = container.read(workingHoursProvider);
      expect(state.hasValue, isTrue);
      expect(state.value, same(saved));
    });
  });

  group('save — failure path', () {
    test('a thrown Failure becomes AsyncError, not a raw exception', () async {
      when(() => repo.list()).thenAnswer((_) async => _week());
      when(
        () => repo.replaceAll(any()),
      ).thenThrow(const ValidationFailure(fieldErrors: {'x': 'bad'}));

      final container = _makeContainer(repo);
      await container.read(workingHoursProvider.future);

      await container.read(workingHoursProvider.notifier).save(_week());

      final state = container.read(workingHoursProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<ValidationFailure>());
    });

    test('state surfaces AsyncError — .when routes to error, not data', () async {
      final loaded = _week();
      when(() => repo.list()).thenAnswer((_) async => loaded);
      when(() => repo.replaceAll(any())).thenThrow(const NetworkFailure());

      final container = _makeContainer(repo);
      // Establish a loaded week, then fail the save.
      await container.read(workingHoursProvider.future);

      await container.read(workingHoursProvider.notifier).save(_week());

      final state = container.read(workingHoursProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<NetworkFailure>());
      // The screen renders via AsyncValue.when, which must route to the error
      // branch on a failed save rather than silently re-showing the prior week.
      final branch = state.when(
        data: (_) => 'data',
        loading: () => 'loading',
        error: (_, _) => 'error',
      );
      expect(branch, 'error');
    });
  });
}
