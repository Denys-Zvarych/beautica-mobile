// Phase 485 (mobile-qa) — week-layout behaviour on the master «Записи»
// beyond `master_bookings_week_view_test.dart`:
//
//   * a TRUNCATED week shows the notice and no «Вільно» marker (phase 483's
//     security contract, through the screen) — GREEN, with a positive
//     control proving the markers render on a complete week;
//   * the vertical «hour before now» opening, measured — GREEN control.
//
// Audit-fix cycle 1 (phase 485) — formerly PENDING, now GREEN:
//   (a) opening / closing the month panel does not rebuild WeekTimeGrid;
//   (b) a schedule that resolves AFTER the bookings keeps the vertical view
//       anchored on the hour before now when the hour window grows;
//   (c) the «День / 3 дні» toggle keeps the visible hour;
//   (d) the month grid's booked-day dots self-heal on the week layout like
//       the day layout (`master_bookings_week_rail_flow_test` history:
//       stale cached set → the dot appears, at most one extra sweep).
//
// Clock: ONE pinned clock (Wed 2026-06-10 12:00 Kyiv) for both the app
// (`clockProvider`) and every fixture — pattern M15, both-pinned.

import 'dart:async';

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/application/bookings_capability.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/week_day_model.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_nav_bar.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_time_grid.dart';
import 'package:beautica_mobile/features/booking_links/presentation/booking_link_setup_hints_provider.dart';
import 'package:beautica_mobile/features/booking_links/presentation/master_nav_setup_hints_provider.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_scope.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/effective_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';
import 'package:beautica_mobile/features/services/data/master_service_catalog_provider.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:beautica_mobile/shared/widgets/calendar_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

/// 12:00 Kyiv (UTC+3, summer) on Wednesday 2026-06-10.
// future-date-ok: the app clock itself (clockProvider) is pinned to this instant and every fixture derives from it — nothing compares it to the host clock.
final DateTime _now = DateTime.utc(2026, 6, 10, 9);
DateTime _clock() => _now;
DateTime get _today => kyivToday(_clock);
DateTime get _monday => kyivWeekStart(_today);

/// Every day of the asked range: 09:00–18:00, or the declared [times]
/// (EXPLICIT_TIMES) when given. [gate], when set, holds the answer back
/// until completed — the "schedule lands after the bookings" race.
class _ScheduleFake extends EffectiveScheduleNotifier {
  _ScheduleFake({this.times, this.gate});

  final List<TimeOfDay>? times;
  final Completer<void>? gate;

  @override
  Future<List<EffectiveDay>> build(
    ScheduleScope scope,
    ScheduleRange range,
  ) async {
    final Completer<void>? g = gate;
    if (g != null) await g.future;
    return <EffectiveDay>[
      for (DateTime d = range.from; !d.isAfter(range.to); d = kyivAddDays(d, 1))
        EffectiveDay(
          date: d,
          source: EffectiveSource.template,
          intervals: times != null
              ? const <WorkInterval>[]
              : <WorkInterval>[
                  WorkInterval(
                    start: const TimeOfDay(hour: 9, minute: 0),
                    end: const TimeOfDay(hour: 18, minute: 0),
                  ),
                ],
          times: times ?? const <TimeOfDay>[],
        ),
    ];
  }
}

/// A 60-minute booking at 12:00 Kyiv (09:00 UTC) on [day].
Booking _booking(String id, DateTime day) {
  final DateTime start = DateTime.utc(day.year, day.month, day.day, 9);
  return Booking(
    id: id,
    masterId: 'm1',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterType: 'INDEPENDENT_MASTER',
    clientId: 'c-$id',
    clientFirstName: 'Олена',
    clientLastName: 'Ковальчук',
    serviceId: 's1',
    serviceName: 'Манікюр',
    durationMinutes: 60,
    price: 500,
    startAt: start,
    endAt: start.add(const Duration(minutes: 60)),
    status: BookingStatus.confirmed,
    canReview: false,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(BookingStatus.confirmed);
    registerFallbackValue(BookingSort.oldest);
    registerFallbackValue(<BookingStatus>[]);
  });

  late _MockBookingRepository repo;

  /// Answers the week read with [items]; page 0 reports [totalElements]
  /// (> items.length = a truncated week), later pages are empty.
  void stubWeek(List<Booking> items, {int? totalElements}) {
    when(
      () => repo.getMyBookings(
        statuses: any(named: 'statuses'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        cancelToken: any(named: 'cancelToken'),
        sort: any(named: 'sort'),
        serviceIds: any(named: 'serviceIds'),
        from: any(named: 'from'),
        to: any(named: 'to'),
        partition: any(named: 'partition'),
        asMaster: any(named: 'asMaster'),
      ),
    ).thenAnswer((Invocation i) async {
      final int page = i.namedArguments[#page] as int? ?? 0;
      return PageResponse<Booking>(
        items: page == 0 ? items : const <Booking>[],
        page: page,
        totalPages: 1,
        totalElements: totalElements ?? items.length,
      );
    });
  }

  setUp(() {
    repo = _MockBookingRepository();
    stubWeek(<Booking>[_booking('b1', _today)]);
  });

  Future<void> pump(
    WidgetTester tester, {
    _ScheduleFake Function()? schedule,
    Future<Set<DateTime>> Function()? bookedDays,
  }) async {
    final GoRouter router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) =>
              const MasterBookingsScreen(),
        ),
      ],
    );
    await tester.pumpRoutedApp(
      router,
      overrides: <Object>[
        masterNavSetupHintsProvider.overrideWithValue(
          BookingLinkSetupHints.none,
        ),
        screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
        bookingRepositoryProvider.overrideWithValue(repo),
        bookedDaysProvider.overrideWith(
          (ref) => bookedDays?.call() ?? Future<Set<DateTime>>.value({}),
        ),
        ownerMasterBookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
        bookingCreationEnabledProvider.overrideWithValue(true),
        masterServiceCatalogProvider.overrideWith(
          (ref) async => const <MasterService>[],
        ),
        effectiveScheduleProvider.overrideWith2(
          (_) => schedule?.call() ?? _ScheduleFake(),
        ),
        clockProvider.overrideWithValue(_clock),
      ],
    );
    await tester.pumpAndSettle();
  }

  WeekTimeGrid grid(WidgetTester tester) =>
      tester.widget<WeekTimeGrid>(find.byType(WeekTimeGrid));

  ScrollPosition vertical(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(WeekTimeGrid.verticalScrollKey),
              matching: find.byType(Scrollable),
            )
            .first, // the vertical one; the column pagers sit inside it
      )
      .position;

  /// The Kyiv minute-of-day at the top edge of the grid's vertical viewport.
  double topMinute(WidgetTester tester) {
    final WeekTimeGrid g = grid(tester);
    final double hourH =
        g.hourHeight ??
        WeekTimeGrid.hourHeightFor(
          tester.element(find.byType(WeekTimeGrid)),
          g.visibleColumns,
        );
    return weekGridWindow(g.days).firstHour * 60 +
        vertical(tester).pixels / hourH * 60;
  }

  /// 11:00 Kyiv — one hour before the pinned now.
  const double hourBeforeNow = 11 * 60;

  group('truncated week', () {
    // Thursday — visible on the opening «3 дні» page (Tue–Thu around the
    // Wednesday "today") and in the FUTURE, so its free times are not past.
    final List<TimeOfDay> declared = <TimeOfDay>[
      const TimeOfDay(hour: 10, minute: 0),
      const TimeOfDay(hour: 16, minute: 0),
    ];
    int thursday() => kyivDaysBetween(_monday, _today) + 1;

    testWidgets('positive control: a COMPLETE week shows «Вільно» markers on '
        'an EXPLICIT_TIMES day and no truncation notice', (
      WidgetTester tester,
    ) async {
      await pump(tester, schedule: () => _ScheduleFake(times: declared));

      expect(
        find.byKey(const Key('master-bookings-truncated-notice')),
        findsNothing,
      );
      expect(find.byKey(WeekTimeGrid.freeMarkerKey(thursday(), 600)), findsOne);
      expect(find.byKey(WeekTimeGrid.freeMarkerKey(thursday(), 960)), findsOne);
    });

    // MUTATION (mobile-qa 2026-11-12): dropped `&& !model.week.isTruncated`
    // from `_weekBody`'s `showsAllOccupancy` → the markers rendered on the
    // truncated week and this test went RED. Restored by cp.
    testWidgets('a TRUNCATED week shows the notice and NO «Вільно» marker '
        'anywhere', (WidgetTester tester) async {
      stubWeek(<Booking>[_booking('b1', _today)], totalElements: 150);
      await pump(tester, schedule: () => _ScheduleFake(times: declared));

      expect(
        find.byKey(const Key('master-bookings-truncated-notice')),
        findsOne,
      );
      for (int i = 0; i < kWeekGridDays; i++) {
        for (final int m in <int>[600, 960]) {
          expect(
            find.byKey(WeekTimeGrid.freeMarkerKey(i, m)),
            findsNothing,
            reason: 'a truncated week cannot back a «Вільно» claim (day $i)',
          );
        }
      }
      expect(
        find.byKey(WeekTimeGrid.cardKey('b1')),
        findsOne,
        reason: 'the bookings that WERE read still render',
      );
    });
  });

  testWidgets('control: with the schedule resolved, the week opens with the '
      'hour before now at the top of the viewport', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    expect(topMinute(tester), closeTo(hourBeforeNow, 1));
  });

  testWidgets('control: a FRESH booked-days set draws the month grid dot '
      '(proves (d)\'s dot finder can pass)', (WidgetTester tester) async {
    final DateTime day = kyivAddDays(_today, 1);
    await pump(tester, bookedDays: () async => <DateTime>{day});
    await tester.tap(find.byKey(WeekNavBar.titleKey));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<CalendarDayCell>(find.byType(CalendarDayCell))
          .any((CalendarDayCell c) => c.day == day.day && (c.dots ?? 0) > 0),
      isTrue,
    );
  });

  // ── Audit-fix cycle 1 (formerly PENDING) ──────────────────────────────

  testWidgets('(a): opening and closing the month panel does not '
      'rebuild the week grid', (WidgetTester tester) async {
    await pump(tester);
    final WeekTimeGrid before = grid(tester);

    await tester.tap(find.byKey(WeekNavBar.titleKey));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bookings-month-calendar-grid')), findsOne);
    expect(
      identical(grid(tester), before),
      isTrue,
      reason: 'opening the month panel rebuilt WeekTimeGrid',
    );

    await tester.tap(find.byKey(WeekNavBar.titleKey));
    await tester.pumpAndSettle();
    expect(
      identical(grid(tester), before),
      isTrue,
      reason: 'closing the month panel rebuilt WeekTimeGrid',
    );
  });

  testWidgets('(b): a schedule that lands AFTER the bookings keeps the '
      'hour before now at the top when the hour window grows', (
    WidgetTester tester,
  ) async {
    final Completer<void> gate = Completer<void>();
    await pump(tester, schedule: () => _ScheduleFake(gate: gate));
    // Fixture guard: the bookings-only window (12:00 booking) starts later
    // than the 09:00–18:00 one, so the window genuinely grows below.
    final int bookingsOnlyFirstHour = weekGridWindow(
      grid(tester).days,
    ).firstHour;

    gate.complete();
    await tester.pumpAndSettle();

    expect(
      weekGridWindow(grid(tester).days).firstHour,
      lessThan(bookingsOnlyFirstHour),
      reason: 'fixture guard: the schedule must widen the hour window',
    );
    expect(
      topMinute(tester),
      closeTo(hourBeforeNow, 1),
      reason:
          'the late schedule grew the window upward and the view slid off '
          'the hour before now',
    );
  });

  testWidgets('(c): the «День / 3 дні» toggle keeps the visible hour', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    // Move off the opening anchor so a reset to it is visible.
    final ScrollPosition v = vertical(tester);
    v.jumpTo(v.pixels + 144);
    await tester.pumpAndSettle();
    final double shown = topMinute(tester);
    expect(
      shown,
      greaterThan(hourBeforeNow + 60),
      reason: 'fixture guard: scrolled away from the opening hour',
    );

    await tester.tap(find.byKey(ViewModeToggle.dayKey));
    await tester.pumpAndSettle();
    expect(grid(tester).visibleColumns, 1);
    expect(
      topMinute(tester),
      closeTo(shown, 2),
      reason: '«День» lost the hour the master was looking at',
    );

    await tester.tap(find.byKey(ViewModeToggle.threeDaysKey));
    await tester.pumpAndSettle();
    expect(grid(tester).visibleColumns, 3);
    expect(
      topMinute(tester),
      closeTo(shown, 2),
      reason: '«3 дні» lost the hour the master was looking at',
    );
  });

  testWidgets('(d): a stale booked-days cache self-heals on the week '
      'layout — the month grid dot appears, at most one extra sweep', (
    WidgetTester tester,
  ) async {
    // Thursday of this week, same month: the week lists a booking there the
    // first (cached) dot sweep does not know about.
    final DateTime staleDay = kyivAddDays(_today, 1);
    expect(staleDay.month, _today.month, reason: 'fixture guard');
    stubWeek(<Booking>[_booking('off-device', staleDay)]);
    int sweeps = 0;
    await pump(
      tester,
      bookedDays: () async {
        sweeps++;
        return sweeps == 1 ? <DateTime>{} : <DateTime>{staleDay};
      },
    );
    expect(sweeps, greaterThanOrEqualTo(1), reason: 'precondition');

    await tester.tap(find.byKey(WeekNavBar.titleKey));
    await tester.pumpAndSettle();

    final Iterable<CalendarDayCell> cells = tester
        .widgetList<CalendarDayCell>(find.byType(CalendarDayCell))
        .where((CalendarDayCell c) => c.day == staleDay.day);
    expect(cells, isNotEmpty, reason: 'fixture guard: the day is on the grid');
    expect(
      cells.any((CalendarDayCell c) => (c.dots ?? 0) > 0),
      isTrue,
      reason:
          'the week lists a booking on ${staleDay.day} but the month grid '
          'shows no dot — the stale set was never healed on the week layout',
    );
    expect(sweeps, lessThanOrEqualTo(2), reason: 'one heal, no loop');
  });
}
