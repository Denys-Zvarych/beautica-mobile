// Phase 244 — E2E: the master «Мої записи» timeline is bounded by WORKING
// HOURS, not by whichever bookings happen to exist that day.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — integration-test gate)
// --------------------------------------------------------------
// The widget/unit tier proves the mechanism in isolation:
// `schedule_timeline_window_test.dart` (the pure window derivation),
// `bookings_inside_schedule_window_test.dart` (the filter + its identity perf
// contract), `bookings_timeline_grid_schedule_window_test.dart` (grid
// geometry + the memoization gate), `bookings_discovery_view_schedule_window_
// test.dart` (the composition, against a MOCKED `BookingRepository` and a
// STATIC `EffectiveScheduleNotifier` fake). NONE of them proves the journey
// wired together against a real HTTP boundary:
//
//   1. A master opens «Мої записи» on a day with NO published working hours
//      (the FakeBackend default — `effective-schedule` returns an empty list
//      unless seeded) → the gray "no working hours" state replaces the WHOLE
//      body, not just an empty-list message.
//   2. Tapping its CTA navigates to `/schedule?date=<that day>` — a REAL
//      `context.go` through a REAL GoRouter, not a captured callback — and
//      `MasterScheduleScreen` actually pre-selects that date.
//   3. A DIFFERENT day, seeded with both a real booking (via
//      `GET /bookings/me`) AND published working hours (via
//      `GET .../effective-schedule`, seeded through this session's new
//      `FakeBackend.seedEffectiveSchedule`), renders the TIMELINE — no gray
//      state — with the booking's card actually reachable.
//
// Patrol is NOT required — nothing here is a native interaction (no OS
// dialog, no deep link, no push, no biometric).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/schedule/presentation/master_schedule_screen.dart';
import 'package:beautica_mobile/features/schedule/presentation/widgets/schedule_widgets.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';
import 'support/pager_drag.dart';

/// Kyiv "today" **as the app under test computes it** — see
/// `master_bookings_flow_test.dart`'s identically-named constant for why this
/// must be derived from the harness's injected `kFixedNow`, never the host
/// device clock.
final DateTime _kyivToday = dateOnly(toBeauticaTime(kFixedNow));

/// The day the fake backend's ONE seeded booking (`fb.bookingStartsAt`) falls
/// on, in Kyiv — anchored to the REAL device clock (see `FakeBackend`'s own
/// `_kFixtureDay` doc), which is why the rail has to be scrolled to reach it
/// (mirrors `master_bookings_flow_test.dart`'s `_selectRailDay`).
DateTime _bookingDay(FakeBackend fb) =>
    dateOnly(toBeauticaTime(DateTime.parse(fb.bookingStartsAt)));

/// Scrolls the timeline grid VERTICALLY until [card] is built — mirrors
/// `master_bookings_flow_test.dart`'s identically-named helper. The grid
/// culls any card whose planned top falls more than 1.5 viewports below the
/// scroll offset (`bookings_timeline_grid.dart`'s "ADDENDUM 4/9"), and the
/// working-hours window here opens at 09:00 while the fixture booking lands
/// in the evening — comfortably past the initial cull window.
Future<void> _scrollTimelineTo(WidgetTester tester, Finder card) async {
  await tester.scrollUntilVisible(
    card,
    200,
    scrollable: find
        .descendant(
          of: find.byType(BookingsTimelineGrid),
          matching: find.byType(Scrollable),
        )
        .first,
    maxScrolls: 60,
  );
  await AppHarness.settle(tester);
}

/// Pages the rail forward until [day]'s chip is on screen, then taps it.
///
/// The rail is a Mon→Sun WEEK pager (`PageScrollPhysics`), so it moves one
/// whole week per fling and only the current page is built — mirrors
/// `master_bookings_flow_test.dart`'s `_scrollRailTo`, including why this
/// flings-and-settles instead of using `scrollUntilVisible`.
/// Pages the rail forward one WHOLE week — deterministically.
///
/// Delegates to [dragPagerByOnePage] (`support/pager_drag.dart`), which
/// documents the full "why not `fling`" write-up and the steps=4 regression
/// this call site used to carry (mobile-debugger, 2026-08-14: with 4 samples
/// `PageController.page` froze mid-drag and never crossed the page boundary).
Future<void> _pageRailForward(WidgetTester tester) => dragPagerByOnePage(
  tester,
  const Key('master-bookings-day-rail'),
  forward: true,
);

Future<void> _selectRailDay(WidgetTester tester, DateTime day) async {
  final Finder chip = find.byKey(dayChipKey(day));
  for (int i = 0; i < 60 && chip.evaluate().isEmpty; i++) {
    await _pageRailForward(tester);
  }
  expect(
    chip,
    findsOneWidget,
    reason:
        'the rail never paged forward to $day in 60 whole-week turns. If this '
        'is a fresh failure, check the two clocks first: the rail opens on '
        'the INJECTED kFixedNow week.',
  );
  await tester.tap(chip);
  // fixed-wait-ok: advancing past the 220 ms day-tap debounce.
  await tester.pump(const Duration(milliseconds: 300));
  await AppHarness.settle(tester);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'a day with NO published working hours shows the gray state and its CTA '
    'lands on the schedule screen with that date pre-selected; a day WITH '
    'both a booking and published hours renders the bounded timeline',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;

      // `_bookingDay`/`_kyivToday` read `beauticaZone` (via `toBeauticaTime`),
      // which is only initialised once `AppHarness.boot` has run (mirrors the
      // app's own startup sequence) — so both the seeding below and every
      // later reference must come AFTER `boot`, not before it.
      final GoRouter router = await AppHarness.boot(tester, fb);

      // The booking day gets 09:00–21:00 published hours — wide enough to
      // comfortably contain the fixture booking (~17:00–19:30 Kyiv in winter,
      // ~18:00–19:30 in summer; see `FakeBackend._kFixtureDay`'s own doc)
      // regardless of which DST half of the year the suite runs in. TODAY is
      // deliberately left unseeded — the FakeBackend default (empty list —
      // every unseeded date resolves to NO_SCHEDULE) is exactly the gray-
      // state fixture this test needs for it.
      final DateTime bookingDay = _bookingDay(fb);
      fb.seedEffectiveSchedule(<Map<String, dynamic>>[
        FakeBackend.seedEffectiveScheduleDay(
          bookingDay,
          intervals: const <(String, String)>[('09:00:00', '21:00:00')],
        ),
      ]);

      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      // ── «Мої записи» (nav tile 1). ─────────────────────────────────────
      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.masterBookings);
      expect(find.byType(MasterBookingsScreen), findsOneWidget);

      // ═══════════════════════════════════════════════════════════════════
      // PART 1 — TODAY: no published hours → the gray state, unconditionally
      // ═══════════════════════════════════════════════════════════════════
      expect(
        find.byKey(const Key('master-bookings-no-schedule')),
        findsOneWidget,
        reason:
            'today has no seeded effective-schedule entry (FakeBackend '
            'default = empty list = NO_SCHEDULE for every unseeded date) — '
            'the gray state must replace the whole body',
      );
      expect(
        find.byType(BookingsTimelineGrid),
        findsNothing,
        reason:
            'the gray state must fully replace the timeline, not sit beside it',
      );

      // The CTA — a REAL navigation through a REAL GoRouter, not a captured
      // callback (the widget-tier test for this already proves the callback
      // itself fires with the right day; this proves the ROUTE actually
      // resolves and MasterScheduleScreen actually pre-selects it).
      await tester.tap(
        find.byKey(const Key('master-bookings-no-schedule-cta')),
      );
      await AppHarness.settle(tester);

      expect(
        AppHarness.location(router),
        startsWith(
          '${RouteNames.masterSchedule}?date=${toApiDate(_kyivToday)}',
        ),
        reason:
            'the CTA must route to /schedule?date=<today>, formatted through '
            'toApiDate — not a bare /schedule (which would silently reopen on '
            'the schedule screen\'s OWN idea of today instead of the exact '
            'day the master was looking at)',
      );
      expect(find.byType(MasterScheduleScreen), findsOneWidget);

      final Iterable<WeekStripDay> stripCells = tester.widgetList<WeekStripDay>(
        find.byType(WeekStripDay),
      );
      final WeekStripDay selectedCell = stripCells.singleWhere(
        (WeekStripDay c) => c.selected,
      );
      expect(
        selectedCell.day,
        _kyivToday.day,
        reason:
            'MasterScheduleScreen must pre-select the day the CTA carried, '
            'not whatever day it would otherwise open on',
      );

      // Back to «Мої записи» for part 2.
      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.masterBookings);

      // ═══════════════════════════════════════════════════════════════════
      // PART 2 — THE SEEDED BOOKING DAY: published hours + a real booking →
      // the bounded timeline, no gray state
      // ═══════════════════════════════════════════════════════════════════
      await _selectRailDay(tester, bookingDay);

      expect(
        find.byKey(const Key('master-bookings-no-schedule')),
        findsNothing,
        reason:
            'this day has seeded working hours (09:00–21:00) — the gray '
            'state must not appear',
      );
      expect(find.byType(BookingsTimelineGrid), findsOneWidget);
      final Finder bookingCard = find.byKey(
        const ValueKey<String>('timeline-card-booking-1'),
      );
      await _scrollTimelineTo(tester, bookingCard);
      expect(
        bookingCard,
        findsOneWidget,
        reason:
            'the fixture booking must render INSIDE the working-hours-bounded '
            'grid — proving the window did not accidentally drop it',
      );

      expect(tester.takeException(), isNull);
    },
  );
}
