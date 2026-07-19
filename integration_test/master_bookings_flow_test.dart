// Phase 7.2 + 7.6 + 7.12 — E2E: the INDEPENDENT MASTER's «Мої записи» → day
// rail → time-of-day window → «Деталі запису» (PROVIDER view) → back journey.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — integration-test gate)
// --------------------------------------------------------------
// The widget/unit tier proves each surface in isolation:
// `master_bookings_screen_test` (four async states, two empties, rail dots,
// debounce, server order), `master_bookings_notifier_test` (query → wire,
// paging, no re-sort), `booking_detail_provider_view_test` (role branching of
// the header + footer), `master_bookings_route_guard_test` (the two-way role
// fence), `booking_viewer_role_test` (fail-closed derivation),
// `day_time_window_test` (Phase 7.12's `DayTimeWindow` domain rules, the
// sheet's picker-field wiring, and the view wiring — all against a MOCKED
// `BookingRepository`). NONE of them proves the journey wired together
// against a real HTTP boundary:
//
//   1. A master logs in and lands on the master shell.
//   2. Tapping «Мої записи» (nav tile 1) PUSHES `/master/bookings` — not the
//      CLIENT `/bookings`, which the role gate would bounce them off.
//   3. The list is served by `GET /bookings/me` and the rail's dots by the
//      SEPARATE, filter-independent `GET /bookings/me/booked-days`. Two
//      distinct endpoints — a regression that fed the rail from the list would
//      be invisible to a widget test that stubs the repository.
//   3c. Phase 7.12's time-of-day window narrows the SAME already-fetched day
//      — zero-network, no-results-vs-true-empty, and the reset affordance —
//      all proven against the FakeBackend's real call counter, not a mock.
//   4. Selecting a rail day re-queries with `from == to` ON THE WIRE.
//   5. Tapping the card pushes `/master/bookings/:id` and the SAME
//      `BookingDetailScreen` renders its PROVIDER branch: the CLIENT as
//      counterparty, and no client action footer.
//   6. Back returns to the still-mounted list.
//
// The provider-vs-client branch is the load-bearing part. It is derived from
// the SESSION (`bookingViewerRoleProvider`), and the only way to exercise that
// derivation end-to-end is to drive a REAL master login through a real router
// — which is exactly what a widget test cannot do.
//
// ⚠ EXECUTION STATUS: this flow has NOT been run on a device. The dev VM has no
// attached emulator (the known host-only-adapter limitation, backlog #179/#191),
// so it is verified here as analyze-clean and correctly wired into BOTH
// aggregators; its first real execution is the CI emulator job. This is stated
// rather than implied — it has not passed, it has been authored.
//
// KEY POLICY (AppHarness): all TAPS are key-based; Ukrainian text appears in
// CONTENT ASSERTIONS only.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:beautica_mobile/shared/widgets/period_range_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  String locationOf(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.toString();

  testWidgets(
    'INDEPENDENT_MASTER opens «Мої записи», narrows by a rail day, and opens '
    'the booking in the PROVIDER view',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      final GoRouter router = await AppHarness.boot(tester, fb);

      expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      // ── 1. The master lands on their own shell, NOT the client one. ───────
      expect(locationOf(router), startsWith(RouteNames.masterProfile));

      // ── 2. «Мої записи» (nav tile 1) pushes the MASTER route. ─────────────
      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);

      expect(
        locationOf(router),
        startsWith(RouteNames.masterBookings),
        reason:
            'tile 1 must reach /master/bookings; /bookings is the CLIENT '
            'branch and the role gate would bounce a master straight off it',
      );
      expect(
        locationOf(router),
        isNot(startsWith('${RouteNames.clientBookings}/')),
      );
      expect(find.byType(MasterBookingsScreen), findsOneWidget);
      expect(
        router.canPop(),
        isTrue,
        reason: 'push, not go — the profile origin stays on the back stack',
      );

      // ── 3. The list rendered from GET /bookings/me. ───────────────────────
      expect(
        fb.getMyBookingsCalls,
        greaterThan(0),
        reason: 'the list must be served by the real endpoint',
      );
      expect(
        find.byKey(const Key('master-booking-card-booking-1')),
        findsOneWidget,
      );
      // The PROVIDER-side identity fields the mapper gained in Phase 7.2 must
      // survive the whole wire → DTO → domain → widget path.
      expect(
        find.text('${fb.clientFirstName} ${fb.clientLastName}'),
        findsWidgets,
        reason:
            'the master\'s card must name the CLIENT — clientFirstName/'
            'clientLastName decoded off the wire, not the master\'s own name',
      );

      // ── 3b. Phases 7.9–7.11: the TIMELINE body, and the day-scoped wire
      //        shape — this is the part this flow did NOT prove before the
      //        rework (it predates it and never asserted anything specific to
      //        it; the widget/unit tier covers this shape against a MOCKED
      //        repository — `bookings_day_notifier_test.dart`,
      //        `master_bookings_screen_test.dart` — this is the same
      //        invariant proven against a REAL HTTP round trip instead). ────
      expect(
        find.byType(BookingsTimelineGrid),
        findsOneWidget,
        reason: 'the body must be the day-scoped timeline, not a vertical list',
      );
      expect(
        find.byKey(const Key('master-bookings-list')),
        findsNothing,
        reason: 'the retired paginated vertical list must not resurface',
      );
      final Map<String, dynamic>? landingQuery = fb.lastMyBookingsQuery;
      expect(
        landingQuery,
        isNotNull,
        reason: 'the landing fetch must have reached the fake backend',
      );
      expect(
        landingQuery!['from'],
        landingQuery['to'],
        reason:
            'the day-scoped landing fetch is from == to — Phase 7.9 fetches '
            'exactly one Kyiv calendar day, never a range',
      );
      expect(
        landingQuery['size'],
        100,
        reason:
            'Phase 7.9\'s single-fetch contract: size=100 in one request, no '
            'page-1 loop, so a whole day is provably covered',
      );
      expect(
        landingQuery['sort'],
        'startsAt,asc',
        reason:
            'ascending order is load-bearing for Phase 7.10\'s lane '
            'assignment — the notifier must not have re-sorted or requested '
            'descending',
      );

      // ── 3c. Phase 7.12: the intra-day time-of-day window, against a REAL
      //        HTTP round trip. The widget/unit tier already proves the
      //        zero-network, no-results-vs-true-empty, and reset-clears-
      //        window invariants against a MOCKED repository
      //        (`day_time_window_test.dart`) — this proves the same
      //        properties hold when the sheet, the view state, and the
      //        `FakeBackend`'s real call counter are all wired together
      //        through an actual login + router, which a widget test
      //        stubbing the repository cannot exercise (Step 2.7 Rule 3b:
      //        this phase shipped a new sheet, a new view-state field, and a
      //        filtered body on an existing screen). ─────────────────────
      final int callsBeforeWindow = fb.getMyBookingsCalls;

      await tester.tap(
        find.byKey(const Key('master-bookings-time-window-button')),
      );
      await AppHarness.settle(tester);
      expect(find.byKey(const Key('day-time-window-sheet')), findsOneWidget);

      // The sheet's seeded draft is 09:00–18:00 with no wheel interaction
      // needed here — `velvet_time_picker_test.dart` already pins that
      // confirming without scrolling returns the seeded value verbatim, and
      // `day_time_window_test.dart`'s own field-wiring group already proves
      // the wheel → draft-field wiring in isolation. `fb.bookingStartsAt`
      // (`2026-07-20T15:00:00Z`) is exactly 18:00 Kyiv in July (UTC+3) — the
      // window's own EXCLUSIVE upper bound — so applying the untouched
      // default already excludes the seeded booking.
      await tester.tap(find.byKey(const Key('day-time-window-apply')));
      await AppHarness.settle(tester);

      expect(
        fb.getMyBookingsCalls,
        callsBeforeWindow,
        reason:
            'setting the window is a client-side view filter — it must not '
            'issue a new GET /bookings/me against the real backend',
      );
      expect(
        find.byKey(const Key('master-bookings-time-window-label')),
        findsOneWidget,
        reason:
            'an active window must render its HH:MM–HH:MM chip in the '
            'header — a silently narrowed timeline is the top support '
            'question this affordance exists to prevent',
      );
      expect(find.text('09:00–18:00'), findsOneWidget);
      expect(
        find.byKey(const Key('master-booking-card-booking-1')),
        findsNothing,
        reason:
            'the seeded 18:00 Kyiv booking sits exactly at the window\'s '
            'exclusive upper bound — it must be filtered out',
      );
      expect(
        find.byKey(const Key('master-bookings-no-results')),
        findsOneWidget,
        reason:
            'the day genuinely HAS a booking — a window-emptied day must '
            'render the recoverable no-results state, never the '
            'true-empty one (the Do-NOT-list regression this proves against '
            'a REAL fetch, not a mocked one)',
      );

      // «Скинути фільтри» on the no-results state must clear the window too.
      await tester.tap(find.byKey(const Key('master-bookings-clear-filters')));
      await AppHarness.settle(tester);

      expect(
        find.byKey(const Key('master-bookings-time-window-label')),
        findsNothing,
        reason: 'resetting must clear the window along with the chip',
      );
      expect(
        find.byKey(const Key('master-booking-card-booking-1')),
        findsOneWidget,
        reason: 'clearing the window must bring the booking back into view',
      );
      expect(
        fb.getMyBookingsCalls,
        callsBeforeWindow,
        reason: 'clearing the window must not refetch either',
      );

      // ── 4. The rail dots come from the SEPARATE booked-days endpoint. ─────
      expect(
        fb.bookedDaysCalls,
        greaterThan(0),
        reason:
            'the rail must be fed by GET /bookings/me/booked-days — a rail '
            'derived from the (filtered) list would hide the very days the '
            'master needs to un-narrow to reach',
      );
      final DateTime bookedDay = parseApiDate(
        fb.bookingStartsAt.substring(0, 10),
      );
      expect(find.byType(BookingsDayRail), findsOneWidget);
      expect(
        find.byKey(dayDotKey(bookedDay)),
        findsOneWidget,
        reason: 'the seeded booking\'s day must carry a dot',
      );

      // ── 5. Selecting that rail day re-queries with from == to ON THE WIRE. ─
      final int callsBeforeNarrow = fb.getMyBookingsCalls;
      await tester.tap(find.byKey(dayChipKey(bookedDay)));
      // The screen debounces day-chip taps by 220 ms; the filtered request
      // does not leave until it elapses, so there is no earlier state to
      // pump-until.
      // fixed-wait-ok: advancing past the 220 ms day-tap debounce.
      await tester.pump(const Duration(milliseconds: 300));
      await AppHarness.settle(tester);

      expect(
        fb.getMyBookingsCalls,
        greaterThan(callsBeforeNarrow),
        reason: 'the day selection must have issued a NEW list request',
      );
      final Map<String, dynamic> q = fb.lastMyBookingsQuery!;
      final String expectedDay = toApiDate(bookedDay);
      expect(
        q['from'],
        expectedDay,
        reason: 'a single-day rail selection is from == to on the wire',
      );
      expect(q['to'], expectedDay);
      expect(
        find.byKey(const Key('master-booking-card-booking-1')),
        findsOneWidget,
        reason: 'the narrowed day still contains the seeded booking',
      );

      // ── 6. Open the detail — the PROVIDER view. ───────────────────────────
      await tester.tap(find.byType(MasterBookingCard));
      await AppHarness.settle(tester);

      expect(
        locationOf(router),
        RouteNames.masterBookingDetail('booking-1'),
        reason:
            'the card must push the MASTER detail route, not the client one',
      );
      expect(find.byType(BookingDetailScreen), findsOneWidget);

      // The counterparty is the CLIENT — this is the whole role branch, and it
      // is derived from the SESSION, which only a real login can exercise.
      expect(
        find.byKey(const Key('booking-detail-client-strip')),
        findsOneWidget,
        reason:
            'the PROVIDER view must show the CLIENT strip; the master seeing '
            'their own name here is the exact bug booking_viewer_role.dart '
            'exists to prevent',
      );
      expect(
        find.text('${fb.clientFirstName} ${fb.clientLastName}'),
        findsWidgets,
      );

      // …and NONE of the client action footer. These are the client's own
      // affordances over their own booking; a master must never be offered
      // them (7.3 fills the provider footer separately).
      for (final String clientOnly in <String>[
        'booking-detail-cancel',
        'booking-detail-reschedule',
        'booking-detail-add-calendar',
        'booking-detail-leave-review',
      ]) {
        expect(
          find.byKey(Key(clientOnly)),
          findsNothing,
          reason:
              '«$clientOnly» is a CLIENT affordance and must not render for a '
              'provider viewer',
        );
      }

      // ── 7. Back returns to the list, still narrowed. ──────────────────────
      await tester.tap(find.byKey(const Key('booking-detail-back')));
      await AppHarness.settle(tester);

      expect(locationOf(router), startsWith(RouteNames.masterBookings));
      expect(find.byType(MasterBookingsScreen), findsOneWidget);
      expect(find.byType(BookingDetailScreen), findsNothing);
      expect(
        find.byKey(const Key('master-booking-card-booking-1')),
        findsOneWidget,
      );
    },
  );

  // ── Phase 7.13 — filter sheet rework + single-day jump ─────────────────────
  //
  // Step 2.7 Rule 3b: this phase reworked a user-facing surface (the filter
  // sheet lost its Дата section; the rail's calendar escape hatch became a
  // single-day jump that moves the rail through the SAME mutation path as a
  // rail chip tap). The widget/unit tier already proves each half in
  // isolation against a MOCKED repository — `bookings_day_picker_test.dart`
  // (the picker opens on the current selection, resolves one date-only day,
  // dismissing changes nothing), `bookings_filter_sheet_test.dart` (exactly
  // two sections, the 4-row/5-wire-value status model, draft semantics), and
  // `master_bookings_filter_wiring_test.dart` (the seam between both and the
  // query, `calendarActive` in both directions). None of them proves the
  // jump reaches a REAL HTTP boundary through a real login — this does.
  //
  // ⚠ EXECUTION STATUS: not run on a device — see the file-header note above;
  // the dev VM has no attached emulator (host-only-adapter limitation,
  // backlog #179/#191). Verified analyze-clean and wired into both
  // aggregators; first real execution is the CI emulator job.
  testWidgets(
    'the filter sheet has no Дата section, and the calendar jump moves the '
    'rail through a real GET /bookings/me — Phase 7.13',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);
      expect(find.byType(MasterBookingsScreen), findsOneWidget);
      expect(locationOf(router), startsWith(RouteNames.masterBookings));

      // ── A. The filter sheet is Статус + Послуга only — no Дата anywhere. ───
      await tester.tap(find.byKey(const Key('master-bookings-filter-button')));
      await AppHarness.settle(tester);
      expect(
        find.byKey(const Key('master-bookings-filter-sheet')),
        findsOneWidget,
      );

      expect(
        find.byKey(const Key('master-bookings-filter-section-status')),
        findsOneWidget,
        reason: 'Статус must survive the rework',
      );
      expect(
        find.byKey(const Key('master-bookings-filter-section-service')),
        findsOneWidget,
        reason:
            'Послуга must survive the rework — the master has a seeded '
            'catalogue',
      );
      // No third section key exists any more — `bookings_filter_sheet.dart`
      // only ever mounts `_SectionLabel` for Статус/Послуга post-7.13 (its
      // own file header records the removal); `grep -rn "DateRangeCalendar
      // \|showBookingsDateRangePicker\|_RangeBanner" lib/` (part of the
      // phase's own acceptance criteria, verified separately) is the
      // repo-wide structural check for the retired symbols. A Cyrillic
      // `find.text('Дата')` here would be banned by
      // `forbid_cyrillic_finder.sh` anyway — see `_SectionLabel.labelKey`'s
      // doc for why this codebase keys sections instead.
      expect(
        find.byKey(const Key('master-bookings-filter-status-pending')),
        findsNothing,
        reason: 'PENDING is retired backend-side (track 24.x)',
      );

      // Close without changing anything — apply with an empty draft is a
      // no-op resolve, not a real filter change.
      await tester.tap(find.byKey(const Key('master-bookings-filter-apply')));
      await AppHarness.settle(tester);

      // ── B. The calendar jump moves the rail through a REAL fetch. ──────────
      final DateTime today = dateOnly(toBeauticaTime(DateTime.now()));
      // Five days out — distinct from today (so the debounced `_selectDay`
      // path actually fires a NEW request rather than a cache hit on the
      // unchanged query) and close enough to stay in the picker's initial
      // scroll position, which opens on the CURRENT selection (today, at this
      // point in the flow) per Phase 7.13 — see `bookings_day_picker.dart`.
      final DateTime picked = DateTime(today.year, today.month, today.day + 5);

      final int callsBeforeJump = fb.getMyBookingsCalls;

      // The rail auto-centres on Kyiv-today at open, scrolling the leading
      // calendar button off the left edge — scroll back to reach it, exactly
      // like the widget-tier wiring test does.
      await tester.scrollUntilVisible(
        find.byKey(const Key('master-bookings-calendar-button')),
        -400,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('master-bookings-day-rail')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await AppHarness.settle(tester);
      await tester.tap(
        find.byKey(const Key('master-bookings-calendar-button')),
      );
      await AppHarness.settle(tester);

      final Finder pickedCell = find.byKey(periodDayCellKey(picked));
      await tester.scrollUntilVisible(
        pickedCell,
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(pickedCell);
      await AppHarness.settle(tester);
      // ONE tap both selects and resolves — single mode, no «Зберегти» CTA.
      await tester.tap(pickedCell);
      // The screen debounces the resolved day the same way a rail chip tap
      // does — `_openCalendar` funnels through `_selectDay`.
      // fixed-wait-ok: advancing past the 220 ms day-selection debounce.
      await tester.pump(const Duration(milliseconds: 300));
      await AppHarness.settle(tester);

      expect(
        fb.getMyBookingsCalls,
        callsBeforeJump + 1,
        reason:
            'the calendar jump must issue exactly ONE new GET /bookings/me '
            '— the SAME single mutation path a rail chip tap uses',
      );
      final String expectedDay = toApiDate(picked);
      expect(fb.lastMyBookingsQuery!['from'], expectedDay);
      expect(fb.lastMyBookingsQuery!['to'], expectedDay);
      expect(
        tester
            .widget<BookingsDayRail>(find.byType(BookingsDayRail))
            .selectedDay,
        picked,
        reason: 'the picked day must have moved the rail\'s selection',
      );

      // ── C. Dismissing the picker changes nothing. ───────────────────────────
      final int callsAfterJump = fb.getMyBookingsCalls;
      await tester.tap(
        find.byKey(const Key('master-bookings-calendar-button')),
      );
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('btn-range-picker-back')));
      await AppHarness.settle(tester);

      expect(
        fb.getMyBookingsCalls,
        callsAfterJump,
        reason: 'dismissing the picker must not issue a new request',
      );
      expect(
        tester
            .widget<BookingsDayRail>(find.byType(BookingsDayRail))
            .selectedDay,
        picked,
        reason: 'dismissing must leave the rail on its last selection',
      );
    },
  );
}
