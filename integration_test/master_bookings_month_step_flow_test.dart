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

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// Kyiv "today" as the app under test computes it — see
/// `master_bookings_flow_test.dart`'s identically-named constant for the
/// full rationale (the injected `kFixedNow` clock, never the host device
/// clock).
final DateTime _kyivToday = dateOnly(toBeauticaTime(kFixedNow));

/// One month forward from [_kyivToday], same day-of-month — mirrors
/// `_BookingsDiscoveryViewState._stepMonth`'s own derivation exactly (not
/// re-implemented independently: both June and July 2026 have ≥14 days, so
/// there is no clamping to account for here, which is deliberate — this
/// file is about the query/list following the step, not about the
/// day-of-month clamp, which has its own widget-tier coverage).
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

/// Scrolls the timeline grid vertically until [card] is built — mirrors
/// `master_bookings_flow_test.dart`'s identically-named helper (both cards in
/// this file sit at 09:00 Kyiv, well inside the default culling band, so this
/// is a defensive no-op in practice but kept for parity with the rest of the
/// suite's pattern).
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'stepping the Варіант D calendar forward one month moves BOTH the '
    'selection AND the fetched list to the new day — the original '
    'relabel-without-reselect bug, pinned against a real GET /bookings/me',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;

      // `AppHarness.boot` FIRST, unconditionally — it is what initialises
      // the timezone database (`initBeauticaTimeZones()`) that `_kyivToday`
      // (via `toBeauticaTime`) depends on. `_kyivToday`/`_nextMonthDay` are
      // top-level `final`s (lazily initialised on first READ, per Dart
      // semantics) — reading either one before `boot()` throws "must be
      // called before beauticaZone is read", which is exactly why every
      // seeding call below comes AFTER this line, mirroring
      // `master_bookings_flow_test.dart`'s own ordering.
      final GoRouter router = await AppHarness.boot(tester, fb);

      _seedWorkingHours(fb, <DateTime>[_kyivToday, _nextMonthDay]);
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        fb.datasetBookingRow(
          id: 'booking-june',
          status: 'CONFIRMED',
          // 06:00 UTC == 09:00 Kyiv (UTC+3, summer time) — matches the
          // published working-hours window's own start.
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

      // ── 1. The landing day is June 14th — booking-june renders, and the
      //      wire query is from == to == June 14th. ────────────────────────
      await _scrollTimelineTo(
        tester,
        find.byKey(const ValueKey<String>('timeline-card-booking-june')),
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-card-booking-june')),
        findsOneWidget,
        reason: 'the landing day must render the June booking',
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-card-booking-july')),
        findsNothing,
        reason: 'the July booking must NOT be visible before any month step',
      );
      final Map<String, dynamic> landingQuery = fb.lastMyBookingsQuery!;
      expect(landingQuery['from'], toApiDate(_kyivToday));
      expect(landingQuery['to'], toApiDate(_kyivToday));

      // ── 2. Expand the calendar and step forward one month. ────────────────
      await tester.tap(find.byKey(const Key('bookings-month-calendar-toggle')));
      await AppHarness.settle(tester);

      final String labelBefore = tester
          .widget<Text>(
            find
                .descendant(
                  of: find.byKey(const Key('bookings-month-calendar-grid')),
                  matching: find.byType(Text),
                )
                .first,
          )
          .data!;

      await tester.tap(find.byKey(const Key('booking-calendar-next-month')));
      // A resolved month step funnels through `_selectImmediate`, which does
      // not itself debounce, but the surrounding settle below covers both
      // the query round trip and any animation.
      // fixed-wait-ok: advancing past the 220 ms day-select debounce
      await tester.pump(const Duration(milliseconds: 300));
      await AppHarness.settle(tester);

      final String labelAfter = tester
          .widget<Text>(
            find
                .descendant(
                  of: find.byKey(const Key('bookings-month-calendar-grid')),
                  matching: find.byType(Text),
                )
                .first,
          )
          .data!;
      expect(
        labelAfter,
        isNot(labelBefore),
        reason:
            'fixture guard: the month step did not relabel the calendar at '
            'all, so nothing below is proven',
      );

      // ── 3. THE PIN — the wire query moved to July 14th, on the SAME body
      //      the master is looking at (not merely "some new request fired
      //      eventually"). ───────────────────────────────────────────────────
      final Map<String, dynamic> steppedQuery = fb.lastMyBookingsQuery!;
      expect(
        steppedQuery['from'],
        toApiDate(_nextMonthDay),
        reason:
            'a month step must move the FETCHED query to the new day — this '
            'is the exact field bug: the switcher used to relabel without '
            'moving the query at all',
      );
      expect(steppedQuery['to'], toApiDate(_nextMonthDay));

      // ── 4. THE PIN, rendered — the list itself flipped, not just the wire
      //      params. A regression that recorded the right query but left the
      //      OLD list on screen (or vice versa) would fail exactly here. ────
      await _scrollTimelineTo(
        tester,
        find.byKey(const ValueKey<String>('timeline-card-booking-july')),
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-card-booking-july')),
        findsOneWidget,
        reason:
            'the timeline must now show the JULY booking — the whole point '
            'of "month step selects"',
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-card-booking-june')),
        findsNothing,
        reason:
            'the June booking must be GONE — a master who tapped ‹ / › must '
            'never see one month\'s label over another month\'s list, which '
            'is exactly the bug this port fixes',
      );

      // ── 5. The RAIL agrees too — its selected chip is now July 14th, not
      //      still on June 14th. Scrolled into view since the rail spans 361
      //      lazily-built cells and the jump is 30 days away. ────────────────
      await tester.scrollUntilVisible(
        find.byKey(dayChipKey(_nextMonthDay)),
        400,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('master-bookings-day-rail')),
              matching: find.byType(Scrollable),
            )
            .first,
        maxScrolls: 200,
      );
      final BookingsDayRail rail = tester.widget<BookingsDayRail>(
        find.byType(BookingsDayRail),
      );
      expect(
        rail.selectedDay,
        _nextMonthDay,
        reason:
            'the rail must agree with the grid and the list on the '
            'selected day — the original bug moved the rail\'s SCROLL '
            'position without moving its selectedDay',
      );
    },
  );
}
