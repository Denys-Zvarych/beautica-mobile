// Phase 485 — the provider «Записи» as a Mon–Sun week (`layout: week` on the
// shared `BookingsDiscoveryView`), across all three `MasterBookingsScreen`
// mounts: independent master, read-only salon master (`/staff/bookings`
// shape), owner master mode (`asOwnerMaster: true`).
//
// Pinned here:
//   * «3 дні» is the default on every mount — three columns on screen;
//   * the «День» toggle keeps the left-most visible day;
//   * a column-header tap in «3 дні» opens «День» on THAT day;
//   * the filter sheet feeds the WEEK query (one request, the week's range);
//   * empty-grid tap opens the create flow — and is absent for a viewer who
//     may not create (read-only staff).

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/application/bookings_capability.dart';
import 'package:beautica_mobile/features/booking/application/master_bookings_view_mode.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
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
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// 09:00–18:00 on every day of whatever range is asked for.
class _WeekHoursFake extends EffectiveScheduleNotifier {
  @override
  Future<List<EffectiveDay>> build(
    ScheduleScope scope,
    ScheduleRange range,
  ) async => <EffectiveDay>[
    for (DateTime d = range.from; !d.isAfter(range.to); d = kyivAddDays(d, 1))
      EffectiveDay(
        date: d,
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

DateTime get _kyivToday => kyivToday(DateTime.now);
DateTime get _weekMonday => kyivWeekStart(_kyivToday);

/// The left-most visible day on a fresh «3 дні» open: today centred,
/// clamped into the week.
int get _openingLeftDay =>
    (kyivDaysBetween(_weekMonday, _kyivToday) - 1).clamp(0, 4);

Booking _booking(String id, {int hourUtc = 10}) {
  final DateTime d = _kyivToday;
  final DateTime start = DateTime.utc(d.year, d.month, d.day, hourUtc);
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

const Key _createMarker = Key('stub-create-booking');
const Key _detailMarker = Key('stub-booking-detail');

enum _Mount { independent, staff, ownerMaster }

void main() {
  setUpAll(() {
    registerFallbackValue(BookingStatus.confirmed);
    registerFallbackValue(BookingSort.oldest);
    registerFallbackValue(<BookingStatus>[]);
  });

  late _MockBookingRepository repo;
  late List<Invocation> calls;

  setUp(() {
    repo = _MockBookingRepository();
    calls = <Invocation>[];
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
      calls.add(i);
      return PageResponse<Booking>(
        items: <Booking>[_booking('b1')],
        page: 0,
        totalPages: 1,
        totalElements: 1,
      );
    });
  });

  Future<GoRouter> pump(
    WidgetTester tester, {
    _Mount mount = _Mount.independent,
    bool canCreate = true,
    DateTime Function()? clock,
  }) async {
    final GoRouter router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) =>
              switch (mount) {
                _Mount.independent => const MasterBookingsScreen(),
                _Mount.staff => const MasterBookingsScreen(
                  detailRouteBuilder: RouteNames.salonMasterBookingDetail,
                  archiveRoute: RouteNames.salonMasterBookingsArchive,
                  navServicesRoute: RouteNames.salonMasterServices,
                  navScheduleRoute: RouteNames.salonMasterSchedule,
                  navProfileRoute: RouteNames.salonMasterProfile,
                  navBookingsRoute: RouteNames.salonMasterBookings,
                  canAddWorkingHours: false,
                ),
                _Mount.ownerMaster => const MasterBookingsScreen(
                  asOwnerMaster: true,
                ),
              },
        ),
        GoRoute(
          path: RouteNames.masterBookingNew,
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: SizedBox.shrink(key: _createMarker)),
        ),
        // AFTER the literal `new` — a dynamic segment first would shadow it.
        GoRoute(
          path: '${RouteNames.masterBookings}/:bookingId',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: SizedBox.shrink(key: _detailMarker)),
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
        bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
        ownerMasterBookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
        bookingCreationEnabledProvider.overrideWithValue(canCreate),
        masterServiceCatalogProvider.overrideWith(
          (ref) async => const <MasterService>[],
        ),
        effectiveScheduleProvider.overrideWith2((_) => _WeekHoursFake()),
        if (clock != null) clockProvider.overrideWithValue(clock),
      ],
    );
    await tester.pumpAndSettle();
    return router;
  }

  WeekTimeGrid grid(WidgetTester tester) =>
      tester.widget<WeekTimeGrid>(find.byType(WeekTimeGrid));

  int leftDay(WidgetTester tester) {
    final PageController c = grid(tester).pageController;
    return (c.page ?? c.initialPage.toDouble()).round();
  }

  for (final _Mount mount in _Mount.values) {
    testWidgets('${mount.name}: opens in «3 дні» on the current week — three '
        'columns, one week request', (WidgetTester tester) async {
      await pump(tester, mount: mount);

      expect(grid(tester).visibleColumns, 3);
      expect(
        grid(tester).pageController.viewportFraction,
        closeTo(1 / 3, 1e-9),
      );
      expect(grid(tester).weekStart, _weekMonday);
      expect(leftDay(tester), _openingLeftDay);
      expect(calls, hasLength(1), reason: 'ONE range read for the week (D3)');
      expect(calls.single.namedArguments[#from], _weekMonday);
      expect(calls.single.namedArguments[#to], kyivAddDays(_weekMonday, 6));
      expect(
        calls.single.namedArguments[#asMaster],
        mount == _Mount.ownerMaster,
      );
    });
  }

  // MUTATION: made `_ensureWeekPager` reset to day 0 on a mode change → the
  // left day moved and this test failed. Restored.
  testWidgets('the «День» toggle shows ONE column on the same left day, and '
      '«3 дні» brings three back — no second fetch path', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    final int left = leftDay(tester);
    calls.clear();

    await tester.tap(find.byKey(ViewModeToggle.dayKey));
    await tester.pumpAndSettle();
    expect(grid(tester).visibleColumns, 1);
    expect(leftDay(tester), left);

    await tester.tap(find.byKey(ViewModeToggle.threeDaysKey));
    await tester.pumpAndSettle();
    expect(grid(tester).visibleColumns, 3);
    expect(leftDay(tester), left.clamp(0, 4));
    expect(calls, isEmpty, reason: 'D3 — «День» reads the same week data');
  });

  testWidgets('the choice is session-remembered: a remount keeps «День»', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(ViewModeToggle.dayKey));
    await tester.pumpAndSettle();
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(MasterBookingsScreen)),
    );
    expect(
      container.read(masterBookingsViewModeProvider),
      BookingsWeekViewMode.day,
    );
  });

  // MUTATION: made `_onWeekHeaderTap` keep three columns → this test failed.
  testWidgets('a column-header tap in «3 дні» opens «День» on THAT day', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    final int tapped = leftDay(tester) + 2;

    await tester.tap(find.byKey(WeekTimeGrid.headerKey(tapped)));
    await tester.pumpAndSettle();

    expect(grid(tester).visibleColumns, 1);
    expect(leftDay(tester), tapped);
  });

  // MUTATION: dropped `_rebuildQuery()` from `_applyFilters`'s setState → no
  // second request and this test failed. Restored.
  testWidgets('a status filter feeds the WEEK query — one request, the '
      'same week range', (WidgetTester tester) async {
    await pump(tester);
    calls.clear();

    await tester.tap(find.byKey(const Key('master-bookings-filter-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('master-bookings-filter-status-cancelled')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('master-bookings-filter-apply')));
    await tester.pumpAndSettle();

    expect(calls, hasLength(1));
    final Invocation call = calls.single;
    expect(call.namedArguments[#from], _weekMonday);
    expect(call.namedArguments[#to], kyivAddDays(_weekMonday, 6));
    expect(
      (call.namedArguments[#statuses] as List<BookingStatus>)
          .map((BookingStatus s) => s.wireValue)
          .toSet(),
      <String>{'CANCELLED', 'DECLINED'},
    );
  });

  // MUTATION: removed `_keepWeekPosition()` from `_applyFilters` → the grid
  // came back on its opening page after the refetch and this test failed.
  testWidgets('a filter refetch keeps the day the master was looking at', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    // Move away from the opening page: Monday on the left.
    await tester.tap(find.byKey(ViewModeToggle.dayKey));
    await tester.pumpAndSettle();
    final int target = leftDay(tester) == 0 ? 6 : 0;
    grid(tester).pageController.jumpToPage(target);
    await tester.pumpAndSettle();
    expect(leftDay(tester), target);

    await tester.tap(find.byKey(const Key('master-bookings-filter-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('master-bookings-filter-status-cancelled')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('master-bookings-filter-apply')));
    await tester.pumpAndSettle();

    expect(leftDay(tester), target);
  });

  testWidgets('an empty-grid tap opens the create flow for a master who may '
      'create', (WidgetTester tester) async {
    final GoRouter router = await pump(tester);
    // A visible column with no booking on it (b1 is today's).
    final int todayIndex = kyivDaysBetween(_weekMonday, _kyivToday);
    final int day = leftDay(tester) == todayIndex
        ? todayIndex + 1
        : leftDay(tester);

    expect(find.byKey(WeekTimeGrid.emptyTapKey(day)), findsOne);
    final Rect column = tester.getRect(find.byKey(WeekTimeGrid.columnKey(day)));
    final Rect viewport = tester.getRect(
      find.byKey(WeekTimeGrid.verticalScrollKey),
    );
    await tester.tapAt(Offset(column.center.dx, viewport.center.dy));
    await tester.pumpAndSettle();

    expect(find.byKey(_createMarker), findsOne);
    expect(router.canPop(), isTrue);
  });

  // MUTATION: passed `onTapEmpty` regardless of `canCreateBooking` → the tap
  // layer rendered for read-only staff and this test failed. Restored.
  testWidgets('read-only staff: no empty-grid create layer at all', (
    WidgetTester tester,
  ) async {
    await pump(tester, mount: _Mount.staff, canCreate: false);

    for (int i = 0; i < 7; i++) {
      expect(find.byKey(WeekTimeGrid.emptyTapKey(i)), findsNothing);
    }
    expect(find.byKey(const Key('master-bookings-add')), findsNothing);
    expect(find.byKey(WeekTimeGrid.cardKey('b1')), findsOne);
  });

  testWidgets('a booking tap still pushes the detail route', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    await tester.ensureVisible(find.byKey(WeekTimeGrid.cardKey('b1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(WeekTimeGrid.cardKey('b1')));
    await tester.pumpAndSettle();
    expect(find.byKey(_detailMarker), findsOne);
  });

  testWidgets('the week title opens the month grid under the header', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(WeekNavBar.titleKey));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bookings-month-calendar-grid')), findsOne);
  });

  // MUTATION: wrapped `_MinuteNow`'s tick in `setState` (the pre-fix
  // rebuild) → a new WeekTimeGrid instance per tick and the identity
  // expectation failed. Restored.
  testWidgets('a minute tick moves the now-line and the now pill without '
      'rebuilding the week grid', (WidgetTester tester) async {
    // Pinned to 12:00 Kyiv on the SAME Kyiv day the fixtures use
    // (`_kyivToday`, host clock) — the clock the grid reads and the day the
    // bookings sit on stay one day (pattern M), and noon is inside the
    // 09:00–18:00 window so the line is drawn.
    DateTime current = kyivMidnight(
      _kyivToday,
    ).add(const Duration(hours: 12)).toUtc();
    await pump(tester, clock: () => current);

    final WeekTimeGrid before = grid(tester);
    final double lineTop = tester
        .getTopLeft(find.byKey(WeekTimeGrid.nowLineKey))
        .dy;
    expect(
      find.descendant(
        of: find.byKey(WeekTimeGrid.nowPillKey),
        matching: find.text('12:00'),
      ),
      findsOne,
    );

    current = current.add(const Duration(minutes: 1));
    // fixed-wait-ok: crossing the minute ticker's on-the-minute Timer (fake
    // async) — the subject under test is exactly that one tick.
    await tester.pump(const Duration(minutes: 1));

    expect(
      identical(grid(tester), before),
      isTrue,
      reason: 'the tick must not rebuild the grid — only its now listeners',
    );
    expect(
      tester.getTopLeft(find.byKey(WeekTimeGrid.nowLineKey)).dy,
      closeTo(lineTop + WeekTimeGrid.threeDayHourHeight / 60, 0.01),
      reason: 'one minute = 1/60 of an hour row lower',
    );
    expect(
      find.descendant(
        of: find.byKey(WeekTimeGrid.nowPillKey),
        matching: find.text('12:01'),
      ),
      findsOne,
    );
  });
}
