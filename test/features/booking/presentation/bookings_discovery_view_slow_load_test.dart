// The slow-load escape hatch, driven through the REAL provider on «Мої
// записи» — the view-level half of
// `widgets/my_bookings_slow_load_notice_test.dart`.
//
// That file pins the widget's own contract against an injected `delay`. This
// one pins the WIRING: that `bookings_discovery_view.dart`'s `loading:` branch
// actually mounts the notice, that its `onRetry` is bound to an
// `invalidate` of the day the view is looking at (so pressing it puts a NEW
// request on the wire), and that a healthy load never shows it. None of that
// is observable from the widget in isolation, and all of it is what the master
// stuck on an indefinite skeleton actually needed.
//
// The production 8-second threshold is used verbatim here — no seam, no
// override — because "does the real branch wire the real widget with the real
// callback" is the whole question. The wait is virtual: `pumpUntilFound`
// advances the fake clock in bounded steps and returns the instant the notice
// appears, so this costs milliseconds of wall clock.
//
// `pumpAndSettle` is unusable while the skeleton is up (`BookingsSkeleton`
// repeats its shimmer forever) — every wait below is `pumpUntil*`.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_query.dart';
import 'package:beautica_mobile/features/booking/presentation/bookings_discovery_view.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/my_bookings_states.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_scope.dart';
import 'package:beautica_mobile/features/schedule/presentation/effective_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

final DateTime _fixedNow = futureBookingStart();
final DateTime _day = kyivToday(() => _fixedNow);

/// Comfortably past `kMyBookingsSlowLoadThreshold` (8 s) — the budget the
/// notice must appear INSIDE, not a sleep: `pumpUntilFound` returns the moment
/// it does.
final Duration _kBudget = kMyBookingsSlowLoadThreshold * 2;

/// The notice sits BELOW the skeleton in the `loading:` `ListView`, so on the
/// 800x600 test surface it is laid out off-screen and every default finder
/// (`skipOffstage: true`) reports it as absent. `skipOffstage: false` is
/// therefore load-bearing here, not a convenience — and it is why the taps
/// below go through `ensureVisible` first.
Finder _notice({bool visibleOnly = false}) =>
    find.byKey(const Key('my_bookings_slow_load'), skipOffstage: visibleOnly);

/// A RESOLVED 09:00–18:00 working-hours verdict for [_day] that COUNTS its own
/// builds. The count is what lets the salon-branch retry test prove the escape
/// hatch re-issues the DAY fetch and *only* the day fetch — a retry that
/// invalidated the whole screen instead would move this number too.
class _CountingSchedule extends EffectiveScheduleNotifier {
  static int builds = 0;

  @override
  Future<List<EffectiveDay>> build(
    ScheduleScope scope,
    ScheduleRange range,
  ) async {
    builds++;
    return <EffectiveDay>[
      EffectiveDay(
        date: _day,
        source: EffectiveSource.template,
        intervals: <WorkInterval>[
          WorkInterval(
            start: const TimeOfDay(hour: 9, minute: 0),
            end: const TimeOfDay(hour: 18, minute: 0),
          ),
        ],
      ),
    ];
  }
}

const PageResponse<Booking> _emptyPage = PageResponse<Booking>(
  items: <Booking>[],
  page: 0,
  totalPages: 1,
  totalElements: 0,
);

void main() {
  setUpAll(() {
    registerFallbackValue(<BookingStatus>{});
    registerFallbackValue(BookingSort.oldest);
  });

  late _MockBookingRepository repo;
  late int fetches;
  late List<Completer<PageResponse<Booking>>> pending;

  setUp(() {
    repo = _MockBookingRepository();
    fetches = 0;
    pending = <Completer<PageResponse<Booking>>>[];
    _CountingSchedule.builds = 0;
  });

  /// Every call parks a fresh `Completer`, so the test decides exactly when —
  /// and whether — a given attempt resolves.
  void stubPending() {
    when(
      () => repo.getMyBookings(
        statuses: any(named: 'statuses'),
        serviceIds: any(named: 'serviceIds'),
        from: any(named: 'from'),
        to: any(named: 'to'),
        sort: any(named: 'sort'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) {
      fetches++;
      final c = Completer<PageResponse<Booking>>();
      pending.add(c);
      return c.future;
    });
  }

  void stubImmediate() {
    when(
      () => repo.getMyBookings(
        statuses: any(named: 'statuses'),
        serviceIds: any(named: 'serviceIds'),
        from: any(named: 'from'),
        to: any(named: 'to'),
        sort: any(named: 'sort'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async {
      fetches++;
      return _emptyPage;
    });
  }

  /// ADDITIVE (2026-08-20, audit cycle 2): [useScheduleWindow] defaults to
  /// `false`, so every call site above pumps byte-for-byte what it always did.
  /// See the "salon-reuse branch" group at the bottom of this file.
  Future<void> pump(WidgetTester tester, {bool useScheduleWindow = false}) =>
      tester.pumpApp(
        BookingsDiscoveryView(
          query: BookingsDayQuery.of(day: _day),
          title: 'Мої записи',
          showMasterFilter: useScheduleWindow,
          useScheduleWindow: useScheduleWindow,
          onAddWorkingHours: useScheduleWindow ? (DateTime _) {} : null,
          onBookingTap: (Booking _) {},
        ),
        overrides: <Object>[
          screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
          bookingRepositoryProvider.overrideWithValue(repo),
          bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
          clockProvider.overrideWithValue(() => _fixedNow),
          if (useScheduleWindow)
            effectiveScheduleProvider.overrideWith(_CountingSchedule.new),
        ],
      );

  testWidgets('a day fetch still pending after the threshold surfaces the '
      'slow-load notice ON TOP of the skeleton', (tester) async {
    stubPending();
    await pump(tester);

    expect(
      find.byKey(const Key('master-bookings-skeleton')),
      findsOneWidget,
      reason: 'sanity: the view is on its loading branch',
    );
    expect(
      _notice(),
      findsNothing,
      reason: 'nothing at all before the threshold — no flash, no reserved gap',
    );

    await tester.pumpUntilFound(_notice(), timeout: _kBudget);

    expect(
      find.byKey(const Key('master-bookings-skeleton')),
      findsOneWidget,
      reason:
          'the fetch is still genuinely in flight — the notice supplements the '
          'skeleton, it does not lie and call this an error',
    );
    expect(find.byKey(const Key('my_bookings_error')), findsNothing);

    // Nothing was cancelled or restarted just by the notice appearing.
    expect(fetches, 1);

    // Let the parked request land so the test leaves no dangling future.
    for (final Completer<PageResponse<Booking>> c in pending) {
      if (!c.isCompleted) c.complete(_emptyPage);
    }
    await tester.pumpUntilGone(
      find.byKey(const Key('master-bookings-skeleton')),
    );
  });

  testWidgets('tapping the slow-load retry puts a NEW request on the wire', (
    tester,
  ) async {
    stubPending();
    await pump(tester);
    await tester.pumpUntilFound(_notice(), timeout: _kBudget);
    expect(fetches, 1);

    final Finder retry = find.byKey(
      const Key('my_bookings_slow_load_retry'),
      skipOffstage: false,
    );
    await tester.ensureVisible(retry);
    await tester.pump();
    await tester.tap(retry);
    await tester.pump();

    expect(
      fetches,
      2,
      reason:
          'the escape hatch must actually re-issue the day fetch — an '
          '`invalidate` that reached the wrong family member, or a callback '
          'wired to nothing, would leave this at 1 while still LOOKING '
          'correct on screen',
    );

    // And the re-issued attempt can still succeed, replacing the whole
    // loading subtree — the notice is not a terminal state.
    pending.last.complete(_emptyPage);
    await tester.pumpUntilGone(
      find.byKey(const Key('master-bookings-skeleton')),
    );
    expect(_notice(), findsNothing);
    expect(find.byKey(const Key('master-bookings-empty')), findsOneWidget);

    for (final Completer<PageResponse<Booking>> c in pending) {
      if (!c.isCompleted) c.complete(_emptyPage);
    }
    await tester.pump();
  });

  testWidgets('a fast successful load never constructs the notice at all — '
      'the no-flash guarantee, at the view level', (tester) async {
    stubImmediate();
    await pump(tester);
    await tester.pumpUntilGone(
      find.byKey(const Key('master-bookings-skeleton')),
    );

    expect(find.byKey(const Key('master-bookings-empty')), findsOneWidget);
    expect(
      find.byType(MyBookingsSlowLoadNotice, skipOffstage: false),
      findsNothing,
    );
    expect(_notice(), findsNothing);
    // No `Timer` survives either: `flutter_test` fails at teardown on a
    // pending one, and the notice's 8-second timer would still be armed here
    // had `dispose` not cancelled it when the data branch replaced the
    // loading subtree.
  });

  // ══════════════════════════════════════════════════════════════════════
  // THE SALON-REUSE BRANCH (audit cycle 2, 2026-08-20 — MEDIUM gap)
  // ══════════════════════════════════════════════════════════════════════
  //
  // Every test above pumps the DEFAULT configuration. The reuse seam
  // (`showMasterFilter` / `useScheduleWindow`) makes the same widget watch a
  // SECOND async source alongside the day fetch — `effectiveScheduleProvider`,
  // watched at `bookings_discovery_view.dart:889-896`, deliberately hoisted
  // OUT of `_Loaded` so both round trips fire in parallel.
  //
  // That is exactly what makes "does the escape hatch still work here"
  // a real question rather than a restatement:
  //
  //   • the `loading:` arm that mounts the notice is chosen by
  //     `bookingsDayProvider` ALONE (`…:898-946`), so a schedule that has
  //     already resolved must NOT suppress the notice, and the resolved
  //     working-hours verdict must NOT short-circuit to the gray
  //     «no working hours» state while the day fetch is still in flight —
  //     `_Loaded` (which owns that state) is never even mounted on this arm;
  //   • `onRetry` invalidates `bookingsDayProvider(_liveQuery)` and nothing
  //     else (`…:941-944`). On a screen with two live async sources that
  //     narrowness is a claim, not a tautology: a retry that reached for the
  //     whole screen would re-run the schedule round trip too — free-looking
  //     on the master's own list, a per-teammate fan-out on a salon one.
  //
  // The `_CountingSchedule.builds` assertions below are what pin the second
  // half; the terminal `BookingsTimelineGrid` assertion is what proves the
  // branch was genuinely active (on the default branch an empty day resolves
  // to `master-bookings-empty` and no grid at all).
  //
  // MUTATION PROBE (M14) — with the `loading:` arm's `MyBookingsSlowLoadNotice`
  // wrapped in `if (!widget.useScheduleWindow)`, this group goes RED
  // (`pumpUntilFound` times out) while all three tests above stay GREEN;
  // restored, everything is GREEN. So this group covers a branch the existing
  // three genuinely do not reach.
  group('the schedule-window (salon-reuse) branch', () {
    testWidgets('the slow-load notice still surfaces when a RESOLVED '
        'working-hours window is watched alongside the stuck day fetch', (
      tester,
    ) async {
      stubPending();
      await pump(tester, useScheduleWindow: true);

      expect(
        find.byKey(const Key('master-bookings-skeleton')),
        findsOneWidget,
        reason: 'sanity: the view is on its loading branch',
      );
      expect(
        find.byKey(const Key('master-bookings-no-schedule')),
        findsNothing,
        reason:
            'the schedule verdict must not paint the gray «no working hours» '
            'state over a day whose bookings simply have not landed yet',
      );
      expect(_notice(), findsNothing);

      await tester.pumpUntilFound(_notice(), timeout: _kBudget);

      expect(
        find.byKey(const Key('master-bookings-skeleton')),
        findsOneWidget,
        reason: 'the fetch is still genuinely in flight',
      );
      expect(find.byKey(const Key('my_bookings_error')), findsNothing);
      expect(fetches, 1);

      for (final Completer<PageResponse<Booking>> c in pending) {
        if (!c.isCompleted) c.complete(_emptyPage);
      }
      await tester.pumpUntilGone(
        find.byKey(const Key('master-bookings-skeleton')),
      );
    });

    testWidgets('tapping retry re-issues the DAY fetch and leaves the '
        'schedule round trip alone', (tester) async {
      stubPending();
      await pump(tester, useScheduleWindow: true);
      await tester.pumpUntilFound(_notice(), timeout: _kBudget);

      expect(fetches, 1);
      final int schedulesBefore = _CountingSchedule.builds;
      expect(
        schedulesBefore,
        1,
        reason:
            'sanity: the schedule provider IS watched on this branch — if it '
            'were 0 the assertion below would be vacuously satisfied',
      );

      final Finder retry = find.byKey(
        const Key('my_bookings_slow_load_retry'),
        skipOffstage: false,
      );
      await tester.ensureVisible(retry);
      await tester.pump();
      await tester.tap(retry);
      await tester.pump();

      expect(
        fetches,
        2,
        reason:
            'the escape hatch must re-issue the day fetch on this branch too',
      );
      expect(
        _CountingSchedule.builds,
        schedulesBefore,
        reason:
            'onRetry invalidates bookingsDayProvider ONLY — a retry that '
            'reached for the whole screen would re-run the working-hours '
            'round trip, which on a salon-scope list is a per-teammate fan-out',
      );

      // The re-issued attempt succeeds and the window branch takes over —
      // which is also what proves this whole group ran on the salon branch:
      // an empty day on the DEFAULT branch renders `master-bookings-empty`
      // and no grid at all.
      pending.last.complete(_emptyPage);
      await tester.pumpUntilGone(
        find.byKey(const Key('master-bookings-skeleton')),
      );
      expect(_notice(), findsNothing);
      expect(
        find.byType(BookingsTimelineGrid),
        findsOneWidget,
        reason:
            'a resolved window renders the grid even with zero bookings; '
            'seeing `master-bookings-empty` here would mean this group had '
            'silently been exercising the default branch',
      );
      expect(find.byKey(const Key('master-bookings-empty')), findsNothing);

      for (final Completer<PageResponse<Booking>> c in pending) {
        if (!c.isCompleted) c.complete(_emptyPage);
      }
      await tester.pump();
    });
  });
}
