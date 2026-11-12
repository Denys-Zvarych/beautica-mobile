// Phase 485 — the master «Записи» week view end to end on the fake backend
// (headless: `flutter test integration_test/master_bookings_week_flow_test.dart
// -d flutter-tester`).
//
//   open «Записи» → «3 дні» (three columns) → back to Monday on the strip →
//   fling the grid (8 real pointer samples) + the 180 ms day-snap settle to
//   Sunday → tap the booking → detail opens → back → «День» → one column.
//
// One week request for all of it (D3: «День» and every in-week move read the
// same week data). A second case runs the same open at text scale 1.3.
//
// The fixture booking is moved INTO the injected clock's week (kFixedNow,
// Sun 2026-06-14) — fixture windows anchor to the injected clock, never the
// host (pattern M).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/application/master_bookings_view_mode.dart';
import 'package:beautica_mobile/features/booking/domain/week_day_model.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_nav_bar.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_time_grid.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';
import 'support/week_grid_driver.dart';

/// The injected clock's Kyiv day and its week.
/// Getters, not finals: the time-zone database is initialised by
/// `AppHarness.boot`, so these may only be read after it.
DateTime get _kyivToday => dateOnly(toBeauticaTime(kFixedNow));
DateTime get _weekMonday => kyivWeekStart(_kyivToday);

/// Moves the seeded `booking-1` to 09:00 UTC on the injected clock's own
/// Kyiv day (a Sunday), 90 minutes long.
void _seedBookingThisWeek(FakeBackend fb) {
  final DateTime start = DateTime.utc(
    _kyivToday.year,
    _kyivToday.month,
    _kyivToday.day,
    9,
  );
  fb
    ..bookingStartsAt = start.toIso8601String()
    ..bookingEndsAt = start.add(const Duration(minutes: 90)).toIso8601String();
}

WeekTimeGrid _grid(WidgetTester tester) =>
    tester.widget<WeekTimeGrid>(find.byType(WeekTimeGrid));

Future<GoRouter> _openBookings(WidgetTester tester, FakeBackend fb) async {
  final GoRouter router = await AppHarness.boot(tester, fb);
  _seedBookingThisWeek(fb);
  await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
  await tester.tap(find.byKey(const Key('master-nav-tile-1')));
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.masterBookings);
  expect(find.byType(MasterBookingsScreen), findsOneWidget);
  await AppHarness.pumpUntilFound(tester, find.byType(WeekTimeGrid));
  return router;
}

/// `GET /bookings/me` requests that fetched THIS week (from Monday to
/// Sunday) — the week grid's own reads, not the archive badge's.
int _weekRequests(FakeBackend fb, int since) => fb.getMyBookingsCalls - since;

/// Phase 485 (mobile-qa) — 480 AC1's request log: `GET /bookings/me` reads
/// of exactly [monday]'s Mon→Sun range.
int _bookingReadsOf(FakeBackend fb, DateTime monday) => fb.myBookingsQueries
    .where((Map<String, dynamic> q) => _isWeekRange(q, monday))
    .length;

/// `GET …/effective-schedule` reads of exactly [monday]'s Mon→Sun range.
int _scheduleReadsOf(FakeBackend fb, DateTime monday) => fb
    .masterEffectiveScheduleQueries
    .where((Map<String, dynamic> q) => _isWeekRange(q, monday))
    .length;

bool _isWeekRange(Map<String, dynamic> q, DateTime monday) =>
    '${q['from']}' == toApiDate(monday) &&
    '${q['to']}' == toApiDate(kyivAddDays(monday, kWeekGridDays - 1));

/// Logs out through the master hub (Профіль → ☰ → «Вийти» → confirm) and
/// waits for the login form — the bounded poll `master_archive_review_flow`
/// documents (logout schedules no frames of its own).
Future<void> _logoutMaster(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('master-nav-tile-3')));
  await AppHarness.settle(tester);
  await tester.tap(find.byKey(const Key('btn-menu-master')));
  await AppHarness.settle(tester);
  await tester.ensureVisible(find.byKey(const Key('row-logout')));
  await AppHarness.settle(tester);
  await tester.tap(find.byKey(const Key('row-logout')));
  await AppHarness.settle(tester);
  await tester.tap(find.byKey(const Key('btn-logout-confirm')));
  await AppHarness.pumpUntilFound(
    tester,
    find.byKey(const ValueKey<String>('login_email')),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    '«3 дні» → fling to Sunday → booking detail → back → «День»: one week '
    'request throughout',
    (WidgetTester tester) async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.independentMaster;

      final GoRouter router = await AppHarness.boot(tester, fb);
      _seedBookingThisWeek(fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      final int before = fb.getMyBookingsCalls;
      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);
      await AppHarness.pumpUntilFound(tester, find.byType(WeekTimeGrid));
      final int afterOpen = fb.getMyBookingsCalls;
      expect(
        fb.lastMyBookingsQuery?['from'],
        toApiDate(_weekMonday),
        reason: 'the landing read is the injected clock\'s Kyiv week',
      );

      expect(_grid(tester).visibleColumns, 3);
      expect(_grid(tester).weekStart, _weekMonday);

      // Back to Monday on the strip, then ONE fling runs the week to Sunday.
      await selectWeekDay(tester, _weekMonday, settle: AppHarness.settle);
      expect(visibleWeekDay(tester), 0);
      final double width = tester
          .getRect(find.byKey(WeekTimeGrid.pagerKey))
          .width;
      await flingWeek(tester, -width * 2, settle: AppHarness.settle);
      expect(
        visibleWeekDay(tester),
        4,
        reason: 'the fling must rest on a day boundary with Sunday in view',
      );

      final Finder card = find.byKey(WeekTimeGrid.cardKey('booking-1'));
      await tester.ensureVisible(card);
      await AppHarness.settle(tester);
      await tester.tap(card);
      await AppHarness.settle(tester);
      expect(find.byType(BookingDetailScreen), findsOneWidget);
      // Positive control for the SALON_MASTER case below: the SAME booking's
      // detail DOES offer a status transition to a master who may act on it.
      expect(find.byKey(const Key('booking-detail-decline')), findsOneWidget);

      await tester.tap(find.byKey(const Key('booking-detail-back')));
      await AppHarness.settle(tester);
      expect(find.byType(BookingDetailScreen), findsNothing);
      AppHarness.expectLocation(router, RouteNames.masterBookings);

      await switchViewMode(
        tester,
        BookingsWeekViewMode.day,
        settle: AppHarness.settle,
      );
      expect(_grid(tester).visibleColumns, 1);

      // «День» = ONE day per swipe, however hard the fling (BOOK-70).
      // mobile-qa (phase 485): the flow above only proved the toggle drew one
      // column; a «День» fling that ran several days would pass it.
      final int dayLeft = visibleWeekDay(tester);
      expect(dayLeft, lessThan(6), reason: 'fixture guard: room to swipe');
      final double dayWidth = tester
          .getRect(find.byKey(WeekTimeGrid.pagerKey))
          .width;
      // A fast swipe of less than one page (8 samples in 320 ms ≈ 1.1k
      // px/s at 360 dp) — momentum must not carry it past the next day.
      await flingWeek(tester, -dayWidth * 0.6, settle: AppHarness.settle);
      expect(
        visibleWeekDay(tester),
        dayLeft + 1,
        reason: 'a fast «День» swipe must move exactly one day forward',
      );
      await flingWeek(tester, dayWidth * 0.6, settle: AppHarness.settle);
      expect(
        visibleWeekDay(tester),
        dayLeft,
        reason: 'a fast «День» swipe back must move exactly one day back',
      );
      expect(_grid(tester).visibleColumns, 1);

      expect(
        _weekRequests(fb, afterOpen),
        0,
        reason:
            'strip, fling, detail round trip and «День» all read the SAME '
            'week (D3) — no further list request',
      );
      expect(afterOpen - before, 1, reason: 'ONE week request opens the tab');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('at text scale 1.3 the week still opens on three columns with '
      'no overflow', (WidgetTester tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final FakeBackend fb = FakeBackend()
      ..currentRole = UserRole.independentMaster;

    await _openBookings(tester, fb);

    expect(_grid(tester).visibleColumns, 3);
    final Finder card = find.byKey(WeekTimeGrid.cardKey('booking-1'));
    await tester.ensureVisible(card);
    await AppHarness.settle(tester);
    expect(card, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 480 AC1 (owed here): one week load = exactly ONE bookings + ONE schedule
  // read; every ‹ › step to a new week = one of each; in-week scrolling and
  // the «День» toggle = none.
  testWidgets('request log: a week load is 1 bookings + 1 schedule read, each '
      '‹ › step to a new week 1 + 1, in-week scrolling and «День» 0', (
    WidgetTester tester,
  ) async {
    final FakeBackend fb = FakeBackend()
      ..currentRole = UserRole.independentMaster;
    await AppHarness.boot(tester, fb);
    _seedBookingThisWeek(fb);
    // Hours on every day of the three weeks visited, so each week renders
    // its grid (an empty week with no hours is the no-hours state).
    fb.seedEffectiveSchedule(<Map<String, dynamic>>[
      for (int i = -kWeekGridDays; i < 2 * kWeekGridDays; i++)
        FakeBackend.seedEffectiveScheduleDay(
          kyivAddDays(_weekMonday, i),
          intervals: const <(String, String)>[('09:00:00', '18:00:00')],
        ),
    ]);
    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
    final int bookingsBefore = fb.myBookingsQueries.length;
    final int scheduleBefore = fb.masterEffectiveScheduleQueries.length;

    await tester.tap(find.byKey(const Key('master-nav-tile-1')));
    await AppHarness.settle(tester);
    await AppHarness.pumpUntilFound(tester, find.byType(WeekTimeGrid));

    final DateTime week = _weekMonday;
    expect(_bookingReadsOf(fb, week), 1, reason: 'one bookings read / week');
    expect(_scheduleReadsOf(fb, week), 1, reason: 'one schedule read / week');
    expect(
      fb.myBookingsQueries.length - bookingsBefore,
      1,
      reason: 'opening the tab reads NOTHING but the week',
    );
    expect(
      fb.masterEffectiveScheduleQueries.length - scheduleBefore,
      1,
      reason: 'opening the tab reads no schedule range but the week',
    );

    // In-week scrolling: the strip back to Monday, a fling, «День», a
    // «День» swipe — all the SAME week's data.
    final int bookingsOpen = fb.myBookingsQueries.length;
    final int scheduleOpen = fb.masterEffectiveScheduleQueries.length;
    await selectWeekDay(tester, week, settle: AppHarness.settle);
    final double width = tester
        .getRect(find.byKey(WeekTimeGrid.pagerKey))
        .width;
    await flingWeek(tester, -width * 2, settle: AppHarness.settle);
    await switchViewMode(
      tester,
      BookingsWeekViewMode.day,
      settle: AppHarness.settle,
    );
    await flingWeek(tester, width, settle: AppHarness.settle);
    await switchViewMode(
      tester,
      BookingsWeekViewMode.threeDays,
      settle: AppHarness.settle,
    );
    expect(fb.myBookingsQueries.length, bookingsOpen, reason: 'in-week = 0');
    expect(
      fb.masterEffectiveScheduleQueries.length,
      scheduleOpen,
      reason: 'in-week = 0 schedule reads',
    );

    // › → the next week: one + one, for exactly that week.
    await tester.tap(find.byKey(WeekStepButton.nextKey));
    await AppHarness.settle(tester);
    final DateTime next = kyivAddDays(week, kWeekGridDays);
    expect(_grid(tester).weekStart, next);
    expect(fb.myBookingsQueries.length - bookingsOpen, 1);
    expect(fb.masterEffectiveScheduleQueries.length - scheduleOpen, 1);
    expect(_bookingReadsOf(fb, next), 1);
    expect(_scheduleReadsOf(fb, next), 1);

    // ‹ twice → the previous week (passing the cached current week): one +
    // one for the new week, and the cached week is not read twice.
    await tester.tap(find.byKey(WeekStepButton.prevKey));
    await AppHarness.settle(tester);
    await tester.tap(find.byKey(WeekStepButton.prevKey));
    await AppHarness.settle(tester);
    final DateTime prev = kyivAddDays(week, -kWeekGridDays);
    expect(_grid(tester).weekStart, prev);
    expect(_bookingReadsOf(fb, prev), 1);
    expect(_scheduleReadsOf(fb, prev), 1);
    expect(
      _bookingReadsOf(fb, week),
      lessThanOrEqualTo(2),
      reason: 'passing through the current week never double-fetches it',
    );
    expect(tester.takeException(), isNull);
  });

  // SALON_MASTER (`/staff/bookings`, read-only): the week renders, there is
  // no empty-grid create layer on any day, and a card opens the STAFF detail
  // route with no status transitions.
  testWidgets('SALON_MASTER: week grid with no create layer; a card opens the '
      'read-only staff detail', (WidgetTester tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()..currentRole = UserRole.salonMaster;
      final GoRouter router = await AppHarness.boot(tester, fb);
      _seedBookingThisWeek(fb);
      await AppHarness.loginAs(tester, fb, UserRole.salonMaster);
      await AppHarness.settle(tester);
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('master-nav-tile-1')),
      );
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.salonMasterBookings);
      await AppHarness.pumpUntilFound(tester, find.byType(WeekTimeGrid));

      expect(_grid(tester).visibleColumns, 3);
      expect(
        _grid(tester).onTapEmpty,
        isNull,
        reason: 'read-only staff: no create callback reaches the grid',
      );
      for (int i = 0; i < kWeekGridDays; i++) {
        expect(find.byKey(WeekTimeGrid.emptyTapKey(i)), findsNothing);
      }
      expect(find.byKey(const Key('master-bookings-add')), findsNothing);

      final Finder card = find.byKey(WeekTimeGrid.cardKey('booking-1'));
      await AppHarness.pumpUntilFound(tester, card);
      await tester.ensureVisible(card);
      await AppHarness.settle(tester);
      await tester.tap(card);
      await AppHarness.settle(tester);
      expect(find.byType(BookingDetailScreen), findsOneWidget);
      AppHarness.expectLocation(
        router,
        RouteNames.salonMasterBookingDetail('booking-1'),
      );
      for (final String k in <String>[
        'booking-detail-decline',
        'booking-detail-complete',
        'booking-detail-provider-reschedule',
      ]) {
        expect(
          find.byKey(Key(k)),
          findsNothing,
          reason: 'read-only staff detail must not offer «$k»',
        );
      }
    });
  });

  // D2: default «3 дні», remembered across a tab switch within the session,
  // back to «3 дні» after logout + login.
  testWidgets('view mode: default «3 дні», «День» survives a tab switch, a '
      'logout resets it to «3 дні»', (WidgetTester tester) async {
    final FakeBackend fb = FakeBackend()
      ..currentRole = UserRole.independentMaster;
    await _openBookings(tester, fb);
    expect(_grid(tester).visibleColumns, 3, reason: 'default «3 дні»');

    await switchViewMode(
      tester,
      BookingsWeekViewMode.day,
      settle: AppHarness.settle,
    );
    expect(_grid(tester).visibleColumns, 1);

    // Another tab and back — the screen is rebuilt, the choice stays.
    await tester.tap(find.byKey(const Key('master-nav-tile-2')));
    await AppHarness.settle(tester);
    expect(find.byType(WeekTimeGrid), findsNothing, reason: 'left the tab');
    await tester.tap(find.byKey(const Key('master-nav-tile-1')));
    await AppHarness.settle(tester);
    await AppHarness.pumpUntilFound(tester, find.byType(WeekTimeGrid));
    expect(
      _grid(tester).visibleColumns,
      1,
      reason: '«День» is remembered for the session',
    );

    await _logoutMaster(tester);
    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
    await tester.tap(find.byKey(const Key('master-nav-tile-1')));
    await AppHarness.settle(tester);
    await AppHarness.pumpUntilFound(tester, find.byType(WeekTimeGrid));
    expect(
      _grid(tester).visibleColumns,
      3,
      reason: 'a new session opens on «3 дні» again',
    );
    expect(tester.takeException(), isNull);
  });
}
