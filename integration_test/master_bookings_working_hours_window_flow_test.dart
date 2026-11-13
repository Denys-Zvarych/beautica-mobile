// Phase 485 — the screen is the WEEK view now: a week with no hours and no
// bookings shows the gray state; the booking's week renders `WeekTimeGrid`.
//
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
import 'package:beautica_mobile/features/booking/presentation/widgets/week_time_grid.dart';
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
import 'support/week_grid_driver.dart';

/// Kyiv "today" **as the app under test computes it** — see
/// `master_bookings_flow_test.dart`'s identically-named constant for why this
/// must be derived from the harness's injected `kFixedNow`, never the host
/// device clock.
final DateTime _kyivToday = dateOnly(toBeauticaTime(kFixedNow));

/// The day the fake backend's ONE seeded booking (`fb.bookingStartsAt`) falls
/// on, in Kyiv — anchored to the REAL device clock (see `FakeBackend`'s own
/// `_kFixtureDay` doc), which is why the week header has to be stepped to
/// reach it (`selectWeekDay`, phase 485).
DateTime _bookingDay(FakeBackend fb) =>
    dateOnly(toBeauticaTime(DateTime.parse(fb.bookingStartsAt)));

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
      // The gray state renders only once the effective-schedule response
      // lands; on a cold CI emulator `settle` can return before it does.
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('master-bookings-no-schedule')),
      );
      expect(
        find.byKey(const Key('master-bookings-no-schedule')),
        findsOneWidget,
        reason:
            'today has no seeded effective-schedule entry (FakeBackend '
            'default = empty list = NO_SCHEDULE for every unseeded date) — '
            'the gray state must replace the whole body',
      );
      expect(
        find.byType(WeekTimeGrid),
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

      // The week strip is gated behind the schedule screen's own
      // effective-schedule + weekly fetch (spinner until both resolve).
      await AppHarness.pumpUntilFound(tester, find.byType(WeekStripDay));
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
      // Phase 485 — the ONE shared driver: steps the week header to the
      // booking's week and taps its strip cell.
      await selectWeekDay(tester, bookingDay, settle: AppHarness.settle);
      // The timeline replaces the gray state only once this day's
      // effective-schedule response lands — wait for it, not for `settle`.
      await AppHarness.pumpUntilFound(tester, find.byType(WeekTimeGrid));

      expect(
        find.byKey(const Key('master-bookings-no-schedule')),
        findsNothing,
        reason:
            'this day has seeded working hours (09:00–21:00) — the gray '
            'state must not appear',
      );
      expect(find.byType(WeekTimeGrid), findsOneWidget);
      final Finder bookingCard = find.byKey(WeekTimeGrid.cardKey('booking-1'));
      await tester.ensureVisible(bookingCard);
      await AppHarness.settle(tester);
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
