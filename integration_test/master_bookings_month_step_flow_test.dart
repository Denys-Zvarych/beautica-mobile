// Варіант D port (mobile-qa, Step 2.7 Rule 3b) — the REGRESSION this whole
// rework exists to fix, pinned end-to-end against a real HTTP boundary.
//
// THE BUG THIS FILE PINS
// ------------------------
// Before this port, `BookingsDiscoveryView` split its date state across TWO
// fields: `_day` (drove the query/list) and `_focusedMonth` (a
// `ValueNotifier` that drove ONLY the month switcher's label and the day
// rail's scroll position). The chevron handlers moved `_focusedMonth`
// without touching `_day` — so tapping ‹ / › relabelled the switcher and
// scrolled the rail to a different month, while the timeline below kept
// showing the ORIGINAL day's bookings. A master could tap "next month",
// watch the header say July, and still be looking at June's list.
//
// The fix (`bookings_month_calendar_panel.dart` + `bookings_discovery_view
// .dart`'s `_stepMonth`) collapses this to ONE piece of state: `_day`. A
// month step now SELECTS (same day-of-month, clamped) exactly like a rail
// tap or «Сьогодні» — so the label, the rail, AND the query always agree.
//
// WHY THIS NEEDS integration_test/, NOT JUST A WIDGET TEST
// -----------------------------------------------------------
// `bookings_day_rebuild_isolation_test.dart`'s "month step" group already
// proves — against a MOCKED repository — that a month step causes a NEW
// fetch (`expectFetchCount`) and reconstructs `BookingsTimelineGrid`. What
// it cannot prove is that the NEW fetch actually carries the RIGHT day to a
// REAL HTTP boundary, and that the OLD day's data is genuinely gone from the
// rendered list rather than merely "some new widget got built" — a mocked
// repository returns the SAME canned response regardless of what query it
// was called with, so a regression that silently kept querying the OLD day
// (or queried a WRONG day) would still satisfy every widget-tier assertion.
// This flow drives a real login, a real month-step tap, and asserts against
// `FakeBackend`'s actually-recorded query AND the actually-rendered cards —
// the two things the original field bug disagreed on.
//
// FIXTURE DESIGN: two bookings on the SAME day-of-month (the 14th) in two
// DIFFERENT months — `kFixedNow` is 2026-06-14, so the landing day is June
// 14th and one month-step forward (`_stepMonth(1)`) lands on July 14th
// (`_day.day > lastDayOfTargetMonth` clamping never engages — June and July
// both have ≥14 days). Each city has its OWN uniquely-identifiable booking,
// so "the list shows the right one and not the other" is a real assertion,
// not a coincidence of both months returning the same fixture.
//
// PHASE 485 REWIRE (2026-11-12). The master «Записи» is the WEEK layout: the
// month grid opens from the week title ([WeekNavBar.titleKey]), a month page
// lands the same day-of-month and shows ITS week (`_onWeekMonthStep`), the
// list read is the whole Mon→Sun week, and the timeline is [WeekTimeGrid]
// (cards keyed [WeekTimeGrid.cardKey]). Both tests keep their intent: the
// step moves the selection AND the fetched list (June's week → July's), and
// opening the month grid DISPLACES the timeline rather than painting over it.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/domain/week_day_model.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_nav_bar.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_time_grid.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';
import 'support/pager_drag.dart';
import 'support/week_grid_driver.dart';

/// Kyiv "today" as the app under test computes it — see
/// `master_bookings_flow_test.dart`'s identically-named constant for the
/// full rationale (the injected `kFixedNow` clock, never the host device
/// clock).
final DateTime _kyivToday = dateOnly(toBeauticaTime(kFixedNow));

/// One month forward from [_kyivToday], same day-of-month — the week
/// layout's month-step rule (`_onWeekMonthStep`; June and July 2026 both
/// have ≥14 days, so no clamping is involved, deliberately).
final DateTime _nextMonthDay = DateTime(
  _kyivToday.year,
  _kyivToday.month + 1,
  _kyivToday.day,
);

void _seedWorkingHours(FakeBackend fb, Iterable<DateTime> days) {
  fb.seedEffectiveSchedule(<Map<String, dynamic>>[
    for (final DateTime day in days)
      FakeBackend.seedEffectiveScheduleDay(
        day,
        intervals: const <(String, String)>[('09:00:00', '21:00:00')],
      ),
  ]);
}

/// Brings [card] into view on the week grid (its vertical scroll and, if
/// needed, the day pager) and settles.
Future<void> _scrollGridTo(WidgetTester tester, Finder card) async {
  await tester.ensureVisible(card);
  await AppHarness.settle(tester);
}

/// The Monday of the week the strip (and so the grid) shows.
DateTime _shownWeek(WidgetTester tester) =>
    tester.widget<WeekStrip>(find.byType(WeekStrip)).weekStart;

/// Turns the expanded month grid forward by exactly one page — see
/// [dragPagerByOnePage] for why not `fling`. The week layout's month step
/// selects at once (no day-select debounce on this path).
Future<void> _pageMonthForward(WidgetTester tester) async {
  await dragPagerByOnePage(
    tester,
    const Key('bookings-month-calendar-grid'),
    forward: true,
  );
  await AppHarness.settle(tester);
}

Future<void> _toggleMonth(WidgetTester tester) async {
  await tester.tap(find.byKey(WeekNavBar.titleKey));
  await AppHarness.settle(tester);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'stepping the month grid forward one month moves BOTH the shown week AND '
    'the fetched list to the new day\'s week — the original '
    'relabel-without-reselect bug, pinned against a real GET /bookings/me',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;

      final GoRouter router = await AppHarness.boot(tester, fb);

      final DateTime juneWeek = kyivWeekStart(_kyivToday);
      final DateTime julyWeek = kyivWeekStart(_nextMonthDay);
      _seedWorkingHours(fb, <DateTime>[
        for (int i = 0; i < kWeekGridDays; i++) ...<DateTime>[
          kyivAddDays(juneWeek, i),
          kyivAddDays(julyWeek, i),
        ],
      ]);
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        fb.datasetBookingRow(
          id: 'booking-june',
          status: 'CONFIRMED',
          startsAt: DateTime.utc(
            _kyivToday.year,
            _kyivToday.month,
            _kyivToday.day,
            6,
          ),
        ),
        fb.datasetBookingRow(
          id: 'booking-july',
          status: 'CONFIRMED',
          startsAt: DateTime.utc(
            _nextMonthDay.year,
            _nextMonthDay.month,
            _nextMonthDay.day,
            6,
          ),
        ),
      ]);

      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);
      expect(find.byType(MasterBookingsScreen), findsOneWidget);
      expect(
        AppHarness.location(router),
        startsWith(RouteNames.masterBookings),
      );
      await AppHarness.pumpUntilFound(tester, find.byType(WeekTimeGrid));

      final Finder juneCard = find.byKey(WeekTimeGrid.cardKey('booking-june'));
      final Finder julyCard = find.byKey(WeekTimeGrid.cardKey('booking-july'));
      await _scrollGridTo(tester, juneCard);
      expect(
        juneCard,
        findsOneWidget,
        reason: 'the landing week must render the June booking',
      );
      expect(
        julyCard,
        findsNothing,
        reason: 'the July booking must NOT be visible before any month step',
      );
      final Map<String, dynamic> landingQuery = fb.lastMyBookingsQuery!;
      expect(landingQuery['from'], toApiDate(juneWeek));
      expect(
        landingQuery['to'],
        toApiDate(kyivAddDays(juneWeek, kWeekGridDays - 1)),
      );

      await _toggleMonth(tester);
      await _pageMonthForward(tester);

      expect(
        _shownWeek(tester),
        julyWeek,
        reason:
            'fixture guard: the month step did not move the week at all, so '
            'nothing below is proven',
      );

      final Map<String, dynamic> steppedQuery = fb.lastMyBookingsQuery!;
      expect(
        steppedQuery['from'],
        toApiDate(julyWeek),
        reason:
            'a month step must move the FETCHED query to the new week — this '
            'is the exact field bug: the switcher used to relabel without '
            'moving the query at all',
      );
      expect(
        steppedQuery['to'],
        toApiDate(kyivAddDays(julyWeek, kWeekGridDays - 1)),
      );

      await _toggleMonth(tester);
      expect(
        visibleWeekDay(tester),
        lessThanOrEqualTo(kyivDaysBetween(julyWeek, _nextMonthDay)),
        reason:
            'the grid did not open on the stepped-to day — the month grid, '
            'the strip and the pager have desynced',
      );
      expect(
        visibleWeekDay(tester) + 2,
        greaterThanOrEqualTo(kyivDaysBetween(julyWeek, _nextMonthDay)),
        reason: 'the stepped-to day is not among the three visible columns',
      );
      await _scrollGridTo(tester, julyCard);
      expect(
        julyCard,
        findsOneWidget,
        reason:
            'the grid must now show the JULY booking — the whole point of '
            '"month step selects"',
      );
      expect(
        juneCard,
        findsNothing,
        reason:
            'the June booking must be GONE — a master who paged the month '
            'must never see one month\'s title over another month\'s list',
      );
      expect(
        find.byKey(weekStripDayKey(_nextMonthDay)),
        findsOneWidget,
        reason: 'the strip did not move to the stepped-to day\'s week',
      );
    },
  );

  testWidgets(
    'opening the month grid DISPLACES the week grid down, end-to-end against '
    'a real screen — it must never paint over the list (locked product '
    'requirement; mobile-qa gap-4, 2026-08-13)',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      final GoRouter router = await AppHarness.boot(tester, fb);

      _seedWorkingHours(fb, <DateTime>[_kyivToday]);
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        fb.datasetBookingRow(
          id: 'booking-displacement',
          status: 'CONFIRMED',
          startsAt: DateTime.utc(
            _kyivToday.year,
            _kyivToday.month,
            _kyivToday.day,
            6,
          ),
        ),
      ]);

      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);
      expect(find.byType(MasterBookingsScreen), findsOneWidget);
      expect(
        AppHarness.location(router),
        startsWith(RouteNames.masterBookings),
      );
      await AppHarness.pumpUntilFound(tester, find.byType(WeekTimeGrid));

      final Finder card = find.byKey(
        WeekTimeGrid.cardKey('booking-displacement'),
      );
      await _scrollGridTo(tester, card);
      final double cardTopClosed = tester.getRect(card).top;

      await _toggleMonth(tester);

      final double panelBottom = tester
          .getRect(find.byKey(const Key('bookings-month-calendar')))
          .bottom;
      final double cardTop = tester.getRect(card).top;

      expect(
        cardTop,
        greaterThan(cardTopClosed),
        reason: 'fixture guard: the open grid did not move the card at all',
      );
      expect(
        cardTop,
        greaterThanOrEqualTo(panelBottom),
        reason:
            'the real booking card\'s top edge ($cardTop) sits ABOVE the '
            'open month grid\'s painted bottom edge ($panelBottom) on the '
            'REAL screen — the calendar is painting over the list, the '
            'exact overlay the user rejected',
      );
    },
  );
}
