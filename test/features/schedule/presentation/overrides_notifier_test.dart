// Phase 15.1 — Unit tests for [OverridesNotifier] (per-date override CRUD) and
// the perf-fix contract that just landed:
//   • putSpan rejects a span > kMaxOverrideSpanDays BEFORE any PUT;
//   • a span within the cap issues exactly one PUT per calendar date (batched);
//   • a partial failure throws a ValidationFailure naming the failed date(s).
//
// Strategy: override scheduleRepositoryProvider with a mocktail mock; fresh
// ProviderContainer per test (disposed via tearDown).

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository_provider.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/presentation/overrides_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _MockScheduleRepository extends Mock implements ScheduleRepository {}

ScheduleOverride _spanDayOff(DateTime start, DateTime end) =>
    ScheduleOverride.dayOff(start: start, end: end);

ScheduleOverride _explicit(DateTime date, List<TimeOfDay> times) =>
    ScheduleOverride.explicitTimes(start: date, end: date, times: times);

void main() {
  late _MockScheduleRepository repo;
  final range = ScheduleRange(
    from: DateTime(2026, 6, 1),
    to: DateTime(2026, 8, 31),
  );

  setUpAll(() {
    registerFallbackValue(
      ScheduleOverride.dayOff(
        start: DateTime(2026, 6, 1),
        end: DateTime(2026, 6, 1),
      ),
    );
    registerFallbackValue(DateTime(2026, 6, 1));
  });

  setUp(() {
    repo = _MockScheduleRepository();
    when(
      () => repo.listOverrides(any(), any()),
    ).thenAnswer((_) async => const <ScheduleOverride>[]);
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [scheduleRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test(
    'putSpan over kMaxOverrideSpanDays throws ValidationFailure before any PUT',
    () async {
      final container = makeContainer();
      await container.read(overridesProvider(range).future);

      // 93 days inclusive (start..start+92) — one past the cap of 92.
      final start = DateTime(2026, 6, 1);
      final end = start.add(
        const Duration(days: kMaxOverrideSpanDays),
      ); // 92 days later = 93 dates

      await container
          .read(overridesProvider(range).notifier)
          .putSpan(_spanDayOff(start, end));

      final state = container.read(overridesProvider(range));
      expect(state.hasError, isTrue);
      expect(state.error, isA<ValidationFailure>());
      // Guard fired before any network mutation.
      verifyNever(() => repo.putOverride(any()));
    },
  );

  test('span within cap issues exactly one PUT per date (batched)', () async {
    when(() => repo.putOverride(any())).thenAnswer(
      (inv) async => inv.positionalArguments.first as ScheduleOverride,
    );

    final container = makeContainer();
    await container.read(overridesProvider(range).future);

    // A 5-day span → 5 PUTs, one per calendar date.
    final start = DateTime(2026, 6, 10);
    final end = DateTime(2026, 6, 14);
    await container
        .read(overridesProvider(range).notifier)
        .putSpan(_spanDayOff(start, end));

    final state = container.read(overridesProvider(range));
    expect(state.hasError, isFalse);

    final captured = verify(
      () => repo.putOverride(captureAny()),
    ).captured.cast<ScheduleOverride>();
    expect(captured, hasLength(5));
    // Each PUT is a single-date override across the contiguous span.
    expect(captured.every((o) => o.isSingleDay), isTrue);
    expect(captured.map((o) => o.start.day).toList()..sort(), [
      10,
      11,
      12,
      13,
      14,
    ]);
    // Range reloaded after the mutation.
    verify(() => repo.listOverrides(any(), any())).called(2); // build + reload
  });

  test(
    'partial failure → ValidationFailure naming the failed date(s)',
    () async {
      // PUT for 2026-06-12 fails; the others succeed.
      when(() => repo.putOverride(any())).thenAnswer((inv) async {
        final o = inv.positionalArguments.first as ScheduleOverride;
        if (o.start.day == 12) {
          throw const ServerFailure(statusCode: 500);
        }
        return o;
      });

      final container = makeContainer();
      await container.read(overridesProvider(range).future);

      await container
          .read(overridesProvider(range).notifier)
          .putSpan(_spanDayOff(DateTime(2026, 6, 10), DateTime(2026, 6, 14)));

      final state = container.read(overridesProvider(range));
      expect(state.hasError, isTrue);
      final err = state.error;
      expect(err, isA<ValidationFailure>());
      expect((err as ValidationFailure).serverMessage, contains('2026-06-12'));
    },
  );

  test('putOverride single date reloads range and clears error', () async {
    when(() => repo.putOverride(any())).thenAnswer(
      (inv) async => inv.positionalArguments.first as ScheduleOverride,
    );

    final container = makeContainer();
    await container.read(overridesProvider(range).future);

    await container
        .read(overridesProvider(range).notifier)
        .putOverride(_spanDayOff(DateTime(2026, 6, 20), DateTime(2026, 6, 20)));

    expect(container.read(overridesProvider(range)).hasError, isFalse);
    verify(() => repo.putOverride(any())).called(1);
    verify(() => repo.listOverrides(any(), any())).called(2);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Phase 15.7 — EXPLICIT_TIMES override validation guard.
  // ───────────────────────────────────────────────────────────────────────────

  group('putOverride — EXPLICIT_TIMES validation', () {
    test('accepts a working EXPLICIT_TIMES override and sends mode + times', () async {
      when(() => repo.putOverride(any())).thenAnswer(
        (inv) async => inv.positionalArguments.first as ScheduleOverride,
      );

      final container = makeContainer();
      await container.read(overridesProvider(range).future);

      await container.read(overridesProvider(range).notifier).putOverride(
        _explicit(DateTime(2026, 6, 20), const <TimeOfDay>[
          TimeOfDay(hour: 9, minute: 0),
          TimeOfDay(hour: 15, minute: 0),
        ]),
      );

      expect(container.read(overridesProvider(range)).hasError, isFalse);
      final sent = verify(
        () => repo.putOverride(captureAny()),
      ).captured.single as ScheduleOverride;
      expect(sent.kind, OverrideKind.custom);
      expect(sent.mode, WeekdayMode.explicitTimes);
      expect(sent.times, <TimeOfDay>[
        const TimeOfDay(hour: 9, minute: 0),
        const TimeOfDay(hour: 15, minute: 0),
      ]);
      // The opposite-shape field is cleared — an EXPLICIT_TIMES override carries
      // NO intervals (the explicitTimes ctor clears them).
      expect(sent.intervals, isEmpty);
    });

    test(
      'rejects an empty-times EXPLICIT_TIMES override → ValidationFailure, '
      'no PUT',
      () async {
        final container = makeContainer();
        await container.read(overridesProvider(range).future);

        await container
            .read(overridesProvider(range).notifier)
            .putOverride(_explicit(DateTime(2026, 6, 20), const <TimeOfDay>[]));

        final state = container.read(overridesProvider(range));
        expect(state.hasError, isTrue);
        expect(state.error, isA<ValidationFailure>());
        verifyNever(() => repo.putOverride(any()));
      },
    );

    test('mode-flip: a CUSTOM interval override carries no times', () {
      // The interval ctor clears the discrete-times field — the two shapes
      // never coexist on one override.
      final interval = ScheduleOverride.custom(
        start: DateTime(2026, 6, 21),
        end: DateTime(2026, 6, 21),
        intervals: <WorkInterval>[
          WorkInterval(
            start: const TimeOfDay(hour: 10, minute: 0),
            end: const TimeOfDay(hour: 14, minute: 0),
          ),
        ],
      );
      expect(interval.mode, WeekdayMode.interval);
      expect(interval.times, isEmpty);

      // The explicitTimes ctor is the inverse — clears intervals.
      final explicit = _explicit(DateTime(2026, 6, 21), const <TimeOfDay>[
        TimeOfDay(hour: 10, minute: 0),
      ]);
      expect(explicit.mode, WeekdayMode.explicitTimes);
      expect(explicit.intervals, isEmpty);
    });
  });

  group('putSpan — EXPLICIT_TIMES validation', () {
    test('accepts an EXPLICIT_TIMES span and sends one EXPLICIT_TIMES PUT per date', () async {
      when(() => repo.putOverride(any())).thenAnswer(
        (inv) async => inv.positionalArguments.first as ScheduleOverride,
      );

      final container = makeContainer();
      await container.read(overridesProvider(range).future);

      // A 3-day EXPLICIT_TIMES span → 3 EXPLICIT_TIMES PUTs, one per date.
      await container.read(overridesProvider(range).notifier).putSpan(
        ScheduleOverride.explicitTimes(
          start: DateTime(2026, 6, 10),
          end: DateTime(2026, 6, 12),
          times: const <TimeOfDay>[
            TimeOfDay(hour: 11, minute: 0),
            TimeOfDay(hour: 16, minute: 0),
          ],
        ),
      );

      expect(container.read(overridesProvider(range)).hasError, isFalse);
      final captured = verify(
        () => repo.putOverride(captureAny()),
      ).captured.cast<ScheduleOverride>();
      expect(captured, hasLength(3));
      expect(captured.every((o) => o.isSingleDay), isTrue);
      expect(captured.every((o) => o.mode == WeekdayMode.explicitTimes), isTrue);
      expect(captured.every((o) => o.intervals.isEmpty), isTrue);
      expect(
        captured.every(
          (o) => o.times.contains(const TimeOfDay(hour: 11, minute: 0)),
        ),
        isTrue,
      );
    });

    test(
      'rejects an empty-times EXPLICIT_TIMES span → ValidationFailure before '
      'any PUT',
      () async {
        final container = makeContainer();
        await container.read(overridesProvider(range).future);

        await container.read(overridesProvider(range).notifier).putSpan(
          ScheduleOverride.explicitTimes(
            start: DateTime(2026, 6, 10),
            end: DateTime(2026, 6, 12),
            times: const <TimeOfDay>[],
          ),
        );

        final state = container.read(overridesProvider(range));
        expect(state.hasError, isTrue);
        expect(state.error, isA<ValidationFailure>());
        verifyNever(() => repo.putOverride(any()));
      },
    );
  });
}
