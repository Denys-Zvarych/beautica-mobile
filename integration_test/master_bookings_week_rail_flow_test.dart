// Week-pager / headerless-grid rework (mobile-qa, Step 2.7 Rule 3b) — the
// «Мої записи» day rail as a Mon→Sun WEEK pager, and the permanent month+year
// label, pinned end-to-end against a real HTTP boundary.
//
// WHAT THIS FLOW EXISTS FOR, AND WHY THE WIDGET TIER IS NOT ENOUGH
// -----------------------------------------------------------------
// Three user-requested changes landed on one screen, and each has a widget
// test for the PART of it that lives in one widget. What no widget test can
// reach is the wiring BETWEEN them, which is where every one of this screen's
// historical bugs has lived:
//
//   * the rail's opening page is decided by `_railController`'s `initialPage`
//     in `_BookingsDiscoveryViewState.initState`, from `_railFirstWeekStart`
//     and the Kyiv-today the screen derives itself. A widget test pumping
//     `BookingsDayRail` directly supplies both by hand, so it pins the rail's
//     rendering and nothing about the derivation the master actually gets;
//   * "rail paging selects nothing" is only meaningful against a real QUERY.
//     `bookings_month_calendar_panel_rail_paging_test.dart` proves the panel
//     emits no callback, but a callback is not a request: a regression could
//     equally leave the callbacks alone and invalidate the day provider some
//     other way. `fb.getMyBookingsCalls` is the claim the user actually cares
//     about — no traffic, no timeline churn, for a browsing gesture;
//   * "the label follows a month page, and survives a collapse" spans the
//     panel, the host's `_stepMonth`, and the rail's own `animateToPage`. The
//     original bug this whole port fixes was precisely a label and a query
//     disagreeing.
//
// mobile-qa (2026-08-14) addendum — the day-rail MONTH-LABEL fix
// (`BookingsDayRail.onVisibleWeekChanged`, a pure relabel with NO selection
// and NO fetch, fired on rail settle). Neither pre-existing test below
// exercises it: the first test's paging excursion nets exactly one week
// (never crosses a month, by construction of its own fixture — see that
// test's own group comment for the arithmetic); the second drives the GRID's
// month pager (`_stepMonth`), a SELECTING move on an entirely different code
// path. A third test, right after the first, browses the RAIL across a real
// month boundary and back via «Сьогодні» — the exact composed scenario the
// widget-tier `bookings_discovery_view_visible_month_test.dart` also pins,
// here against the real HTTP boundary instead of a mocked repository.
//
// CLOCK DISCIPLINE (mobile-qa M15). Every date here is derived from the
// harness's INJECTED `kFixedNow` through `toBeauticaTime`/`dateOnly` — the
// same pair the app under test uses — never from `DateTime.now()`. The rail's
// opening page is a function of the app's clock, so a fixture built on the
// host clock would agree with it only on the dev VM (TZ=Europe/Kyiv) and only
// while the two happened to name the same week: a mixed-clock fixture here
// would silently page to a week the app never opened on and every assertion
// below would be about the wrong seven days.
//
// NO PATROL TIER. Nothing in this change touches an OS surface — no
// permission dialog, no deep link, no notification, no WebView, no biometric.
// It is two horizontal `PageView`s and a `Text`. `integration_test/patrol/`
// coverage would add a native-driver boot for zero additional signal, which
// is coverage theatre; the exemption is stated rather than skip-marked.
//
// PHASE 485 REWIRE (2026-11-12). The master «Записи» is now the WEEK layout
// (`BookingsLayout.week`): the day rail, its chips, the permanent month+year
// label and the `bookings-month-calendar-toggle` are gone from this screen
// (the salon board keeps them). Every test below keeps its intent and is
// re-pointed at the week equivalent, through the ONE shared driver
// (`support/week_grid_driver.dart`):
//   * rail opens on today's week / pages whole weeks / browsing fetches
//     nothing → the strip opens on today's Mon–Sun, ‹ › steps exactly one
//     week (one week request, Mon→Sun), and browsing INSIDE the week (a grid
//     fling) fetches nothing and keeps the week (D3); a strip day tap in a
//     past week is the positive control;
//   * the rail-label month relabel across a month boundary → the week title
//     ([weekTitleLabel]) follows ‹ › into another month and «Сьогодні»
//     resyncs it;
//   * the permanent label in both resting states → the week title is the
//     same widget at the same anchor with the month grid open and closed, a
//     month page lands the same day-of-month's week and survives the
//     collapse (the week month grid has the preview's ‹ › header, so the
//     day layout's "no chevrons" rule is not asserted here);
//   * the stale-dot self-heal → the strip's per-day COUNT comes from the
//     week list itself, so an off-device booking the cached booked-days set
//     lacks is counted on landing; the only extra booked-days read is the
//     week layout's one month-dot self-heal sweep (phase 485), and it never
//     loops.

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

/// Kyiv "today" as the app under test computes it — from the INJECTED
/// [kFixedNow], never the host clock. See the file header's clock-discipline
/// note; mirrors `master_bookings_month_step_flow_test.dart`'s constant of
/// the same name, including why it must not be read before `AppHarness.boot`.
DateTime get _kyivToday => dateOnly(toBeauticaTime(kFixedNow));

const Key _gridKey = Key('bookings-month-calendar-grid');

void _seedWorkingHours(FakeBackend fb, Iterable<DateTime> days) {
  fb.seedEffectiveSchedule(<Map<String, dynamic>>[
    for (final DateTime day in days)
      FakeBackend.seedEffectiveScheduleDay(
        day,
        intervals: const <(String, String)>[('09:00:00', '21:00:00')],
      ),
  ]);
}

/// Boots, logs in as the independent master and lands on «Мої записи».
Future<void> _openBookings(WidgetTester tester, FakeBackend fb) async {
  final GoRouter router = await AppHarness.boot(tester, fb);
  // Hours on every day a test can step to — an empty week with no hours
  // renders the no-hours state instead of the grid.
  _seedWorkingHours(fb, <DateTime>[
    for (int i = -6 * kWeekGridDays; i < 10 * kWeekGridDays; i++)
      kyivAddDays(kyivWeekStart(_kyivToday), i),
  ]);
  await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
  await tester.tap(find.byKey(const Key('master-nav-tile-1')));
  await AppHarness.settle(tester);
  expect(find.byType(MasterBookingsScreen), findsOneWidget);
  expect(AppHarness.location(router), startsWith(RouteNames.masterBookings));
  await AppHarness.pumpUntilFound(tester, find.byType(WeekTimeGrid));
}

/// The Monday of the week the strip (and so the grid) shows.
DateTime _shownWeek(WidgetTester tester) =>
    tester.widget<WeekStrip>(find.byType(WeekStrip)).weekStart;

/// The week title currently rendered — exactly one, once settled.
Finder _title(String label) => find.descendant(
  of: find.byKey(WeekNavBar.titleKey),
  matching: find.text(label),
);

/// Asserts the strip shows a WHOLE Mon→Sun week: seven cells inside the
/// strip, Monday first, Sunday last, and neither neighbouring week's edge
/// day — the headline contract the rail's week pager carried ("the first day
/// is monday and last is sunday"), from RENDERED geometry.
void _expectWholeWeek(WidgetTester tester, {required String at}) {
  final DateTime monday = _shownWeek(tester);
  expect(
    monday.weekday,
    DateTime.monday,
    reason: '$at: the shown week does not start on a Monday',
  );
  expect(
    tester.widget<WeekTimeGrid>(find.byType(WeekTimeGrid)).weekStart,
    monday,
    reason: '$at: the grid shows a different week than the strip',
  );
  final Rect strip = tester.getRect(find.byType(WeekStrip));
  double previousLeft = double.negativeInfinity;
  for (int i = 0; i < kWeekGridDays; i++) {
    final Finder cell = find.byKey(weekStripDayKey(kyivAddDays(monday, i)));
    expect(cell, findsOneWidget, reason: '$at: day $i is not on the strip');
    final Rect r = tester.getRect(cell);
    expect(
      r.left >= strip.left - 0.5 && r.right <= strip.right + 0.5,
      isTrue,
      reason: '$at: day $i is outside the strip',
    );
    expect(r.left, greaterThan(previousLeft), reason: '$at: out of order');
    previousLeft = r.left;
  }
  expect(
    find.byKey(weekStripDayKey(kyivAddDays(monday, -1))),
    findsNothing,
    reason: '$at: the PREVIOUS week\'s Sunday is on the strip',
  );
  expect(
    find.byKey(weekStripDayKey(kyivAddDays(monday, kWeekGridDays))),
    findsNothing,
    reason: '$at: the NEXT week\'s Monday is on the strip',
  );
}

Future<void> _step(WidgetTester tester, {required bool forward}) async {
  await tester.tap(
    find.byKey(forward ? WeekStepButton.nextKey : WeekStepButton.prevKey),
  );
  await AppHarness.settle(tester);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'the week opens on the week containing today and steps one WHOLE week at '
    'a time — and browsing inside the week selects no new week and fetches '
    'nothing',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      await _openBookings(tester, fb);

      expect(
        find.byKey(weekStripDayKey(_kyivToday)),
        findsOneWidget,
        reason:
            'today is not on the opening strip — the screen opened on the '
            'wrong week',
      );
      expect(
        _shownWeek(tester),
        kyivWeekStart(_kyivToday),
        reason: 'the opening week is not today\'s own Mon→Sun week',
      );
      _expectWholeWeek(tester, at: 'on open');
      final int fetchesAfterLanding = fb.getMyBookingsCalls;
      expect(
        fetchesAfterLanding,
        greaterThan(0),
        reason:
            'fixture guard: the landing fetch never happened, so the counter '
            'below cannot show a browsing regression adding to it',
      );

      // Browsing INSIDE the week — back to Monday on the strip, then a grid
      // fling — is pure navigation over the SAME week data (D3).
      await selectWeekDay(
        tester,
        kyivWeekStart(_kyivToday),
        settle: AppHarness.settle,
      );
      final double width = tester
          .getRect(find.byKey(WeekTimeGrid.pagerKey))
          .width;
      await flingWeek(tester, -width, settle: AppHarness.settle);
      expect(
        visibleWeekDay(tester),
        greaterThan(0),
        reason: 'fixture guard: the fling did not move the grid at all',
      );
      expect(_shownWeek(tester), kyivWeekStart(_kyivToday));
      expect(
        fb.getMyBookingsCalls,
        fetchesAfterLanding,
        reason:
            'browsing inside the week issued GET /bookings/me — every in-week '
            'move must read the week already loaded (D3)',
      );

      await _step(tester, forward: true);
      _expectWholeWeek(tester, at: 'one week forward');
      final DateTime weekAfterOneForward = _shownWeek(tester);
      expect(
        weekAfterOneForward,
        kyivAddDays(kyivWeekStart(_kyivToday), kWeekGridDays),
        reason: '› did not advance exactly one week',
      );
      expect(fb.lastMyBookingsQuery!['from'], toApiDate(weekAfterOneForward));
      expect(
        fb.lastMyBookingsQuery!['to'],
        toApiDate(kyivAddDays(weekAfterOneForward, kWeekGridDays - 1)),
        reason: 'a week step reads the whole Mon→Sun range, one request',
      );

      await _step(tester, forward: true);
      _expectWholeWeek(tester, at: 'two weeks forward');

      await _step(tester, forward: false);
      _expectWholeWeek(tester, at: 'back one week');
      expect(
        _shownWeek(tester),
        weekAfterOneForward,
        reason: '‹ did not return to the week it came from',
      );

      await _step(tester, forward: false);
      await _step(tester, forward: false);
      _expectWholeWeek(tester, at: 'one week into the past');
      final DateTime pastWeekMonday = _shownWeek(tester);
      expect(
        pastWeekMonday.isBefore(kyivWeekStart(_kyivToday)),
        isTrue,
        reason: 'the week would not step into the past',
      );

      // Positive control — a strip day tap scrolls the grid to THAT day.
      final DateTime pastSaturday = kyivAddDays(pastWeekMonday, 5);
      await selectWeekDay(tester, pastSaturday, settle: AppHarness.settle);
      expect(
        visibleWeekDay(tester),
        4,
        reason:
            'positive control failed: a strip TAP did not bring Saturday into '
            'the middle of «3 дні» (Fri–Sun)',
      );
      expect(_shownWeek(tester), pastWeekMonday);
      expect(fb.lastMyBookingsQuery!['from'], toApiDate(pastWeekMonday));
    },
  );

  testWidgets(
    'stepping the week across a month boundary relabels the week title, and '
    '«Сьогодні» resyncs it back — end-to-end against a real HTTP boundary',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      await _openBookings(tester, fb);

      final String titleOnOpen = weekTitleLabel(kyivWeekStart(_kyivToday));
      expect(_title(titleOnOpen), findsOneWidget);

      for (int i = 0; i < 5; i++) {
        await _step(tester, forward: true);
      }
      _expectWholeWeek(tester, at: 'five weeks forward');

      final DateTime browsedMonday = _shownWeek(tester);
      expect(
        browsedMonday.month,
        isNot(_kyivToday.month),
        reason:
            'fixture guard: five week steps did not leave the landing month, '
            'so the relabel assertion below proves nothing',
      );
      expect(
        _title(weekTitleLabel(browsedMonday)),
        findsOneWidget,
        reason:
            'the week title did not follow the week across a month boundary '
            '— the master reads a range the grid does not show',
      );
      expect(_title(titleOnOpen), findsNothing);
      expect(fb.lastMyBookingsQuery!['from'], toApiDate(browsedMonday));

      await tester.tap(find.byKey(WeekNavBar.todayKey));
      await AppHarness.settle(tester);

      expect(
        _title(titleOnOpen),
        findsOneWidget,
        reason:
            'pressing «Сьогодні» after browsing across a month boundary left '
            'the title on the browsed-to week',
      );
      _expectWholeWeek(tester, at: 'after «Сьогодні»');
      expect(_shownWeek(tester), kyivWeekStart(_kyivToday));
    },
  );

  testWidgets(
    'the week title is permanent, anchored identically with the month grid '
    'open and closed, follows a month page, and survives the collapse — the '
    'month grid keeping its approved ‹ › header',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      await _openBookings(tester, fb);

      final String expectedOpening = weekTitleLabel(kyivWeekStart(_kyivToday));
      expect(_title(expectedOpening), findsOneWidget);
      final Rect titleCollapsed = tester.getRect(
        find.byKey(WeekNavBar.titleKey),
      );

      await tester.tap(find.byKey(WeekNavBar.titleKey));
      await AppHarness.settle(tester);
      expect(
        find.byKey(_gridKey),
        findsOneWidget,
        reason: 'fixture guard: the title tap did not open the month grid',
      );

      expect(
        _title(expectedOpening),
        findsOneWidget,
        reason: 'the week title vanished when the month grid opened',
      );
      expect(
        tester.getRect(find.byKey(WeekNavBar.titleKey)),
        titleCollapsed,
        reason:
            'the title MOVED between the two resting states — it is the '
            'affordance that opened the grid and must stay where it was',
      );
      // Phase 484/485 — the week layout's month grid is the approved
      // MasterWeekBookings preview's, whose month header carries ‹ ›
      // (`_monthPager(withMonthHeader: true)`). The day layout's "swipe ONLY,
      // no chevrons" rule belongs to the salon board's panel, not here.
      expect(
        find.byKey(const Key('booking-calendar-prev-month')),
        findsWidgets,
        reason: 'the week month grid lost its approved ‹ month chevron',
      );
      expect(
        find.byKey(const Key('booking-calendar-next-month')),
        findsWidgets,
        reason: 'the week month grid lost its approved › month chevron',
      );
      expect(
        find.text(expectedOpening),
        findsOneWidget,
        reason: 'the week range is rendered twice',
      );

      await dragPagerByOnePage(tester, _gridKey, forward: true);
      await AppHarness.settle(tester);

      // Same day-of-month in the next month (clamped) — its week.
      final DateTime steppedDay = DateTime(
        _kyivToday.year,
        _kyivToday.month + 1,
        _kyivToday.day,
      );
      final DateTime steppedWeek = kyivWeekStart(steppedDay);
      expect(
        _shownWeek(tester),
        steppedWeek,
        reason:
            'the month page did not land the same day-of-month\'s week — '
            'with the chevrons retired the title is the ONLY feedback that '
            'the swipe landed',
      );
      expect(_title(weekTitleLabel(steppedWeek)), findsOneWidget);

      await tester.tap(find.byKey(WeekNavBar.titleKey));
      await AppHarness.settle(tester);

      expect(
        _title(weekTitleLabel(steppedWeek)),
        findsOneWidget,
        reason: 'collapsing reverted the title to the pre-step week',
      );
      expect(
        find.byKey(weekStripDayKey(steppedDay)),
        findsOneWidget,
        reason: 'the collapsed strip is not showing the stepped-to day\'s week',
      );
      _expectWholeWeek(tester, at: 'after open → page → collapse');

      expect(fb.lastMyBookingsQuery!['from'], toApiDate(steppedWeek));
      expect(
        fb.lastMyBookingsQuery!['to'],
        toApiDate(kyivAddDays(steppedWeek, kWeekGridDays - 1)),
      );
    },
  );

  testWidgets(
    'a day whose booking the cached booked-days set lacks is still counted on '
    'the strip on landing — the count comes from the week list itself',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      final GoRouter router = await AppHarness.boot(tester, fb);
      final DateTime staleDay = kyivAddDays(kyivWeekStart(_kyivToday), 2);
      expect(staleDay, isNot(_kyivToday), reason: 'fixture guard');
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        fb.datasetBookingRow(
          id: 'booking-offdevice',
          status: 'CONFIRMED',
          startsAt: DateTime.utc(
            staleDay.year,
            staleDay.month,
            staleDay.day,
            9,
          ),
        ),
      ]);
      fb.seedStaleBookedDays(fresh: <String>[toApiDate(staleDay)]);
      _seedWorkingHours(fb, <DateTime>[_kyivToday, staleDay]);

      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);
      expect(
        AppHarness.location(router),
        startsWith(RouteNames.masterBookings),
      );
      await AppHarness.pumpUntilFound(tester, find.byType(WeekTimeGrid));

      expect(
        fb.bookedDaysCalls,
        2,
        reason:
            'one stale sweep on landing + exactly one week-layout dot '
            'self-heal (phase 485, behaviour test (d))',
      );
      expect(
        fb.lastMyBookingsQuery!['from'],
        toApiDate(kyivWeekStart(_kyivToday)),
        reason: 'precondition: the landing read is today\'s week',
      );
      expect(
        find.byKey(weekStripCountKey(staleDay)),
        findsOneWidget,
        reason:
            'the week lists a booking on this day but the strip shows no '
            'count — the strip must read the week list, never the cached '
            'booked-days set (the user-reported stale-marker bug)',
      );
      expect(
        find.byKey(weekStripCountKey(_kyivToday)),
        findsNothing,
        reason: 'fixture guard: a day with no booking shows no count',
      );
      expect(
        fb.bookedDaysCalls,
        2,
        reason: 'the strip needs no further sweep — and the heal does not loop',
      );
    },
  );
}
