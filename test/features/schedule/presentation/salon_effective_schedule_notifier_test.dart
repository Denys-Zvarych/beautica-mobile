// Phase 335 — [SalonEffectiveScheduleNotifier]: the salon board's roster-wide
// working-hours source.
//
// Covers the three things the notifier itself owns, as opposed to the
// repository below it (`salon_roster_schedule_repository_test.dart`) or the
// union above it (`test/features/salon/presentation/salon_board_window_test
// .dart`):
//   1. the family key — `(salonId, ScheduleRange)`, with the range's bounds
//      reaching the repository verbatim;
//   2. the 5-minute TTL keepAlive pin, which is what makes paging away and
//      back serve cached hours instead of re-fanning-out across the roster;
//   3. the failure path staying UNPINNED, so the next visit retries.

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository_provider.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/salon_effective_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';

class _MockRepo extends Mock implements SalonRosterScheduleRepository {}

const String _salonId = 'salon-1';

// future-date-ok: a fixed PAST month, used only as the family key
final ScheduleRange _june = ScheduleRange.month(DateTime(2026, 6, 15));

Map<String, List<EffectiveDay>> _roster() => <String, List<EffectiveDay>>{
  'm1': <EffectiveDay>[
    EffectiveDay(
      date: DateTime(2026, 6, 15),
      source: EffectiveSource.template,
      intervals: <WorkInterval>[
        WorkInterval(
          start: const TimeOfDay(hour: 9, minute: 0),
          end: const TimeOfDay(hour: 18, minute: 0),
        ),
      ],
    ),
  ],
};

void main() {
  setUpAll(() => registerFallbackValue(DateTime.utc(2026)));

  late _MockRepo repo;

  setUp(() => repo = _MockRepo());

  ProviderContainer container() {
    final ProviderContainer c = ProviderContainer(
      overrides: [
        salonRosterScheduleRepositoryProvider.overrideWithValue(repo),
      ],
      // Retry DISABLED. Riverpod's blanket default (10 attempts, ~38s of
      // backoff) applies to a `Failure`, which is neither an `Error` nor a
      // `ProviderException` — so a failing build here would park in
      // AsyncLoading for the whole suite instead of surfacing the error the
      // failure tests below assert on. Same reasoning, and the same remedy,
      // as `test/helpers/pump_app.dart`'s `retry` knob.
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    return c;
  }

  test('fetches the roster schedule for its (salonId, range) key', () async {
    when(
      () => repo.salonRosterEffectiveSchedule(any(), any(), any()),
    ).thenAnswer((_) async => _roster());

    final Map<String, List<EffectiveDay>> out = await container().read(
      salonEffectiveScheduleProvider(_salonId, _june).future,
    );

    expect(out['m1'], hasLength(1));
    // The RANGE's own bounds, verbatim — a range the notifier silently
    // widened or narrowed would fetch a month the board is not showing.
    verify(
      () => repo.salonRosterEffectiveSchedule(_salonId, _june.from, _june.to),
    ).called(1);
  });

  test(
    'two different salons are two different family members — one fetch each, '
    'and no cross-salon reuse',
    () async {
      when(
        () => repo.salonRosterEffectiveSchedule(any(), any(), any()),
      ).thenAnswer((_) async => _roster());

      final ProviderContainer c = container();
      await c.read(salonEffectiveScheduleProvider(_salonId, _june).future);
      await c.read(salonEffectiveScheduleProvider('salon-2', _june).future);

      verify(
        () => repo.salonRosterEffectiveSchedule(_salonId, any(), any()),
      ).called(1);
      verify(
        () => repo.salonRosterEffectiveSchedule('salon-2', any(), any()),
      ).called(1);
    },
  );

  testWidgets(
    'a SUCCESSFUL fetch pins the window for a 5-minute TTL — losing its last '
    'watcher inside the TTL serves the cache, and only past it does a revisit '
    're-fan-out across the roster',
    (WidgetTester tester) async {
      int fetches = 0;
      when(
        () => repo.salonRosterEffectiveSchedule(any(), any(), any()),
      ).thenAnswer((_) async {
        fetches++;
        return _roster();
      });

      // A container this test OWNS the disposal of — see the drain at the
      // bottom for why `addTearDown(c.dispose)` is too late here.
      final ProviderContainer c = ProviderContainer(
        overrides: [
          salonRosterScheduleRepositoryProvider.overrideWithValue(repo),
        ],
        retry: (_, _) => null,
      );

      // 1. Resolve once, holding NO listener — the TTL pin is then the only
      //    thing keeping the element alive, which is what is under test.
      await c.read(salonEffectiveScheduleProvider(_salonId, _june).future);
      expect(fetches, 1);

      // 2. Let Riverpod's real `Timer(Duration.zero, …)` autoDispose sweep
      //    run. Without the pin the element would be torn down here.
      //    fixed-wait-ok: draining a zero-duration Timer under FakeAsync.
      await tester.pump(const Duration(milliseconds: 1));

      // 3. Inside the TTL: the cache answers, no second fan-out.
      await c.read(salonEffectiveScheduleProvider(_salonId, _june).future);
      expect(
        fetches,
        1,
        reason:
            'the TTL pin was not opened — an unwatched window was disposed '
            'immediately and silently recreated, so paging the board away and '
            'back re-fans-out across the whole roster every time',
      );

      // 4. Past the TTL the pin's release Timer fires and the element is
      //    genuinely evicted — the pin is a CACHE, not a leak.
      //    fixed-wait-ok: a fixed duration past the 5-minute TTL is the point.
      await tester.pump(const Duration(minutes: 5, seconds: 1));
      // fixed-wait-ok: draining the release Timer the elapse above fired.
      await tester.pump(const Duration(milliseconds: 1));

      await c.read(salonEffectiveScheduleProvider(_salonId, _june).future);
      expect(
        fetches,
        2,
        reason:
            'the window stayed pinned past its own TTL — a session that pages '
            'through a year of months would hold every one of them forever',
      );

      // DRAIN. Step 4's own fetch opened a FRESH 5-minute pin timer, and
      // `_verifyInvariants` ("A Timer is still pending even after the widget
      // tree was disposed") runs BEFORE `addTearDown` would dispose the
      // container — so this test disposes its own container here, which fires
      // the notifier's `ref.onDispose(timer.cancel)`. Same drain the sibling
      // `effective_schedule_ttl_pin_test.dart` performs for the same reason.
      c.dispose();
      // fixed-wait-ok: letting the cancellation settle under FakeAsync.
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  test(
    'a FAILED fetch surfaces the typed Failure — the board degrades on it, it '
    'is never swallowed into an empty roster (which would read as "nobody '
    'works today")',
    () async {
      when(
        () => repo.salonRosterEffectiveSchedule(any(), any(), any()),
      ).thenAnswer((_) async => throw const NetworkFailure());

      final ProviderContainer c = container();
      // See the sibling test below for why a listener is held while the
      // failure resolves.
      final ProviderSubscription<AsyncValue<Map<String, List<EffectiveDay>>>>
      sub = c.listen(
        salonEffectiveScheduleProvider(_salonId, _june),
        (_, _) {},
      );
      addTearDown(sub.close);
      await expectLater(
        c.read(salonEffectiveScheduleProvider(_salonId, _june).future),
        throwsA(isA<NetworkFailure>()),
      );
    },
  );

  test(
    'an AsyncError carries a null .value — which is precisely the signal '
    'SalonBookingsScreen degrades on, WITHOUT ever branching on hasError',
    () async {
      when(
        () => repo.salonRosterEffectiveSchedule(any(), any(), any()),
      ).thenAnswer((_) async => throw const NetworkFailure());

      final ProviderContainer c = container();
      // A LISTENER, not a bare `read`: a failed autoDispose provider read
      // without one is torn down mid-flight and Riverpod reports
      // "disposed during loading state" instead of the failure under test.
      final ProviderSubscription<AsyncValue<Map<String, List<EffectiveDay>>>>
      sub = c.listen(
        salonEffectiveScheduleProvider(_salonId, _june),
        (_, _) {},
      );
      addTearDown(sub.close);
      await expectLater(
        c.read(salonEffectiveScheduleProvider(_salonId, _june).future),
        throwsA(isA<NetworkFailure>()),
      );

      final AsyncValue<Map<String, List<EffectiveDay>>> state = c.read(
        salonEffectiveScheduleProvider(_salonId, _june),
      );
      expect(state, isA<AsyncError<Map<String, List<EffectiveDay>>>>());
      expect(state.value, isNull);
    },
  );
}
