// Phase 14.14 — Unit tests for [WorkingDaysNotifier] (the calendar
// day-availability family provider backing `SlotDateScreen`'s gating).
//
// Strategy: override `slotRepositoryProvider` with a mocktail mock; fresh
// `ProviderContainer` per test (disposed via tearDown). Mirrors
// `schedule/presentation/overrides_notifier_test.dart`'s family-provider
// testing shape.
//
// Retry disabled: Riverpod 3.x's `ProviderContainer` retries a FAILED
// `build()` with its default exponential-backoff policy unless told
// otherwise (`pump_app.dart`'s `PumpApp.pumpApp` exposes the identical knob
// for widget tests). The one test below that fails `build()` itself (not a
// post-build notifier method, unlike `overrides_notifier_test.dart`'s
// failure cases) would otherwise hang for the full backoff window before its
// `.future` ever settles — `retry: (_, _) => null` makes the FIRST failure
// final.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/booking/application/working_days_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/slot_repository.dart';
import 'package:beautica_mobile/features/booking/domain/working_day.dart';
import 'package:beautica_mobile/features/booking/domain/working_days_query.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockSlotRepository extends Mock implements SlotRepository {}

void main() {
  late _MockSlotRepository repo;

  setUp(() {
    repo = _MockSlotRepository();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [slotRepositoryProvider.overrideWithValue(repo)],
      retry: (int _, Object _) => null,
    );
    addTearDown(container.dispose);
    return container;
  }

  test('build() delegates to SlotRepository.getWorkingDays with the query\'s '
      'masterId/from/to and resolves to its result', () async {
    final query = WorkingDaysQuery.month(
      masterId: 'master-1',
      anyDayInMonth: DateTime(2026, 7, 15),
    );
    final List<WorkingDay> fixture = <WorkingDay>[
      WorkingDay(date: DateTime(2026, 7, 1), working: true),
      WorkingDay(date: DateTime(2026, 7, 2), working: false),
    ];
    when(
      () => repo.getWorkingDays(
        masterId: any(named: 'masterId'),
        from: any(named: 'from'),
        to: any(named: 'to'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => fixture);

    final container = makeContainer();
    final result = await container.read(workingDaysProvider(query).future);

    expect(result, fixture);
    final captured = verify(
      () => repo.getWorkingDays(
        masterId: captureAny(named: 'masterId'),
        from: captureAny(named: 'from'),
        to: captureAny(named: 'to'),
        cancelToken: captureAny(named: 'cancelToken'),
      ),
    ).captured;
    expect(captured[0], 'master-1');
    expect(captured[1], DateTime(2026, 7, 1));
    expect(captured[2], DateTime(2026, 7, 31));
  });

  test('different queries (masterId or range) resolve as independent family '
      'members — one repository call each', () async {
    when(
      () => repo.getWorkingDays(
        masterId: any(named: 'masterId'),
        from: any(named: 'from'),
        to: any(named: 'to'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async => const <WorkingDay>[]);

    final container = makeContainer();
    final julyMaster1 = WorkingDaysQuery.month(
      masterId: 'master-1',
      anyDayInMonth: DateTime(2026, 7, 1),
    );
    final julyMaster2 = WorkingDaysQuery.month(
      masterId: 'master-2',
      anyDayInMonth: DateTime(2026, 7, 1),
    );
    final augustMaster1 = WorkingDaysQuery.month(
      masterId: 'master-1',
      anyDayInMonth: DateTime(2026, 8, 1),
    );

    await container.read(workingDaysProvider(julyMaster1).future);
    await container.read(workingDaysProvider(julyMaster2).future);
    await container.read(workingDaysProvider(augustMaster1).future);

    // Re-reading the SAME key does not re-fetch (family caching).
    await container.read(workingDaysProvider(julyMaster1).future);

    verify(
      () => repo.getWorkingDays(
        masterId: any(named: 'masterId'),
        from: any(named: 'from'),
        to: any(named: 'to'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).called(3);
  });

  test('a repository failure surfaces as the provider\'s AsyncError', () async {
    when(
      () => repo.getWorkingDays(
        masterId: any(named: 'masterId'),
        from: any(named: 'from'),
        to: any(named: 'to'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenThrow(const NetworkFailure());

    final container = makeContainer();
    final query = WorkingDaysQuery.month(
      masterId: 'master-1',
      anyDayInMonth: DateTime(2026, 7, 1),
    );

    // Keep a live subscription so the (autoDispose) provider isn't torn
    // down mid-flight while its build future is still pending — mirrors
    // `service_types_provider_test.dart`'s pattern for this exact gotcha.
    final sub = container.listen(workingDaysProvider(query), (_, _) {});
    addTearDown(sub.close);

    await expectLater(
      container.read(workingDaysProvider(query).future),
      throwsA(isA<NetworkFailure>()),
    );
    expect(container.read(workingDaysProvider(query)).hasError, isTrue);
  });

  test('cancels the in-flight request\'s CancelToken when the family instance '
      'is superseded (unwatched + disposed), mirroring '
      'SlotPickerNotifier.loadSlots\' cancel-on-supersede behaviour for rapid '
      'month-nav taps', () async {
    // Never resolves on its own — the point of this test is to observe
    // the CancelToken's state while the request is still in flight, the
    // same way a real month-nav tap would abandon a slow request for the
    // month the user already navigated away from.
    final Completer<List<WorkingDay>> pending = Completer<List<WorkingDay>>();
    when(
      () => repo.getWorkingDays(
        masterId: any(named: 'masterId'),
        from: any(named: 'from'),
        to: any(named: 'to'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) => pending.future);

    final container = makeContainer();
    final query = WorkingDaysQuery.month(
      masterId: 'master-1',
      anyDayInMonth: DateTime(2026, 7, 1),
    );

    final sub = container.listen(workingDaysProvider(query), (_, _) {});

    // Let `build()` run far enough to reach the repository call and
    // register its `ref.onDispose` cancellation hook.
    await Future<void>.delayed(Duration.zero);

    final captured = verify(
      () => repo.getWorkingDays(
        masterId: any(named: 'masterId'),
        from: any(named: 'from'),
        to: any(named: 'to'),
        cancelToken: captureAny(named: 'cancelToken'),
      ),
    ).captured;
    final CancelToken token = captured.single as CancelToken;
    expect(token.isCancelled, isFalse);

    // Simulate month-nav superseding this family member: the caller
    // stops watching it (mirrors `SlotDateScreen` swapping which
    // `WorkingDaysQuery` it watches) and it's explicitly invalidated,
    // which — for an unwatched autoDispose family member — tears the
    // instance down and fires `ref.onDispose` synchronously.
    sub.close();
    container.invalidate(workingDaysProvider(query));

    expect(token.isCancelled, isTrue);

    // Let the still-pending repository Future settle so it doesn't leak
    // into a later test.
    pending.complete(const <WorkingDay>[]);
  });
}
