// Phase 6.1 — Unit tests for [WorkingHoursNotifier].
//
// Covers the AsyncNotifier contract that the Phase 6.2 editor relies on:
//   build()
//     - reads the week from WorkingHoursRepository.list() (a pure cache read).
//   save() happy path
//     - calls replaceAll() with the supplied week,
//     - emits AsyncData with the server-confirmed (gap-filled) result,
//     - invalidates masterProfileProvider so the canonical profile cache stays
//       coherent (PERF M2) — asserted via a rebuild counter on an override.
//   save() failure path
//     - a thrown Failure becomes AsyncError (AsyncValue.guard), never a raw
//       exception,
//     - masterProfileProvider is NOT invalidated on failure (no result.hasValue).
//
// Strategy:
//   Pure Dart — ProviderContainer + a mocktail WorkingHoursRepository. The
//   notifier's own keepAlive repository provider is overridden with the mock so
//   no profile/auth chain is constructed. masterProfileProvider is overridden
//   with a counting notifier so the save()-time invalidation is observable
//   without touching the real auth/master stack. No widget tree.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/calendar/data/working_hours_repository.dart';
import 'package:beautica_mobile/features/calendar/data/working_hours_repository_provider.dart';
import 'package:beautica_mobile/features/calendar/domain/working_hours.dart';
import 'package:beautica_mobile/features/calendar/presentation/working_hours_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockWorkingHoursRepository extends Mock
    implements WorkingHoursRepository {}

/// A stand-in [MasterProfile] override that records how many times it builds.
/// Each invalidate(masterProfileProvider) forces a rebuild, so [buildCount]
/// lets the save() tests assert whether the cache was invalidated.
class _CountingMasterProfile extends MasterProfile {
  static int buildCount = 0;

  @override
  Future<Master> build() async {
    buildCount++;
    return _master;
  }
}

const _master = Master(
  id: 'master-1',
  firstName: 'Test',
  lastName: 'Master',
  avgRating: 0,
  reviewCount: 0,
  type: MasterType.independentMaster,
);

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
    overrides: [
      workingHoursRepositoryProvider.overrideWithValue(repo),
      masterProfileProvider.overrideWith(_CountingMasterProfile.new),
    ],
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
    _CountingMasterProfile.buildCount = 0;
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

    test('invalidates masterProfileProvider on success (PERF M2)', () async {
      when(() => repo.list()).thenAnswer((_) async => _week());
      when(() => repo.replaceAll(any())).thenAnswer((_) async => _week());

      final container = _makeContainer(repo);
      // Build the profile so it has an initial value to be invalidated.
      await container.read(masterProfileProvider.future);
      await container.read(workingHoursProvider.future);
      final before = _CountingMasterProfile.buildCount;

      await container.read(workingHoursProvider.notifier).save(_week());
      // invalidate() schedules a rebuild on the next microtask; force it.
      await container.read(masterProfileProvider.future);

      expect(
        _CountingMasterProfile.buildCount,
        greaterThan(before),
        reason: 'save() must invalidate the profile cache so it re-derives',
      );
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

    test('does NOT invalidate masterProfileProvider on failure', () async {
      when(() => repo.list()).thenAnswer((_) async => _week());
      when(() => repo.replaceAll(any())).thenThrow(const NetworkFailure());

      final container = _makeContainer(repo);
      await container.read(masterProfileProvider.future);
      await container.read(workingHoursProvider.future);
      final before = _CountingMasterProfile.buildCount;

      await container.read(workingHoursProvider.notifier).save(_week());
      // Give any (erroneously) scheduled invalidation a chance to fire.
      await Future<void>.delayed(Duration.zero);

      expect(
        _CountingMasterProfile.buildCount,
        before,
        reason: 'a failed save must leave the profile cache untouched',
      );
    });
  });
}
