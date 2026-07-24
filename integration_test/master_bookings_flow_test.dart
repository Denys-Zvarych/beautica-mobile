// Phase 7.2 + 7.6 — E2E: the INDEPENDENT MASTER's «Мої записи» → day rail →
// «Деталі запису» (PROVIDER view) → back journey.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — integration-test gate)
// --------------------------------------------------------------
// The widget/unit tier proves each surface in isolation:
// `master_bookings_screen_test` (four async states, two empties, rail dots,
// debounce, server order), `master_bookings_notifier_test` (query → wire,
// paging, no re-sort), `booking_detail_provider_view_test` (role branching of
// the header + footer), `master_bookings_route_guard_test` (the two-way role
// fence), `booking_viewer_role_test` (fail-closed derivation). NONE of them
// proves the journey wired together against a real HTTP boundary:
//
//   1. A master logs in and lands on the master shell.
//   2. Tapping «Мої записи» (nav tile 1) PUSHES `/master/bookings` — not the
//      CLIENT `/bookings`, which the role gate would bounce them off.
//   3. The list is served by `GET /bookings/me` and the rail's dots by the
//      SEPARATE, filter-independent `GET /bookings/me/booked-days`. Two
//      distinct endpoints — a regression that fed the rail from the list would
//      be invisible to a widget test that stubs the repository.
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
// ✅ EXECUTION STATUS (2026-07-22): every case in this file has now RUN AND
// PASSED on a real handset — Samsung SM-M127F, Android, debug integration_test
// APK, 15/15 green. The per-test "not run on a device" notes that used to sit
// above each case have been removed rather than left to rot.
//
// The first real run found ELEVEN failures, every one of them in the test
// code, and they are worth recording because they are the traps this harness
// sets for anything authored blind against it:
//
//   • THE INJECTED CLOCK. `AppHarness.boot` overrides `clockProvider` with
//     `kFixedNow` (2026-06-14), and `BookingsDiscoveryView` honours it — so
//     the screen's "today", its rail and its landing query are all June 14th
//     2026 whatever day the suite runs on. Any expectation derived from
//     `DateTime.now()` disagrees with the app by the drift between the two.
//     Use `_kyivToday`.
//   • THE LAZY RAIL. The day rail is a `ListView.builder` of 361 cells that
//     opens today-first, so ~6 days exist at a time. `fb.bookingStartsAt` is
//     anchored to the REAL clock, leaving the seeded day ~45 cells off-screen
//     and unbuilt. Scroll it in — `_selectRailDay`.
//   • THE NAV BAR USES `go`, NOT `push`. A tab tap REPLACES the stack, so
//     `router.canPop()` is false after one, and `router.pop()` is not how a
//     user leaves a tab.
//   • RIVERPOD 3 RETRIES FAILED PROVIDERS automatically — ten times over
//     ~38 s, sitting in `AsyncLoading` in between — so a stubbed failure does
//     NOT surface an error state promptly. See `AppHarness.boot`'s [retry].
//   • THE SKELETON SHIMMERS FOREVER. `BookingsSkeleton` calls
//     `AnimationController.repeat`, so `pumpAndSettle` can never settle while
//     it is up. CI emulators hid this by zeroing the animation scales; a real
//     handset does not.
//   • THE DAY CACHE IS REAL. `bookingsDayProvider` is a keepAlive family
//     behind a bounded LRU, so returning to an already-loaded day is served
//     from cache and issues NO new request.
//
// KEY POLICY (AppHarness): all TAPS are key-based; Ukrainian text appears in
// CONTENT ASSERTIONS only.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_bookings_states.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/my_bookings_states.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/formatters/booking_price_labels.dart';
import 'package:beautica_mobile/shared/formatters/month_names.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:beautica_mobile/shared/widgets/velvet_bottom_nav_bar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/pump_app.dart';
import 'support/app_harness.dart';

/// The REAL rendered geometry of the [MasterBookingCard] keyed
/// `timeline-card-<id>` — mirrors `bookings_timeline_grid_test.dart`'s own
/// `_cardRect` helper, reading actual screen geometry rather than a
/// `Positioned` widget's declared properties (there is no `Positioned`
/// ancestor any more — see the R3 fix in `bookings_timeline_grid.dart`).
Rect _masterCardRect(WidgetTester tester, String bookingId) =>
    tester.getRect(find.byKey(ValueKey<String>('timeline-card-$bookingId')));

/// Resolves the localisation instance off a MOUNTED screen's own element —
/// mirrors `client_leave_review_flow_test.dart`'s identically-named helper.
/// Lets a flow assert against `l10n.<key>` (locale-invariant, rename-proof)
/// instead of a Cyrillic literal, without threading a `BuildContext` through
/// every test body.
AppLocalizations _l10nOf(WidgetTester tester, Type screen) =>
    AppLocalizations.of(tester.element(find.byType(screen)));

/// Kyiv "today" **as the app under test computes it** — derived from the
/// harness's INJECTED clock (`kFixedNow`, 2026-06-14 12:00 UTC), never from
/// the host device clock.
///
/// `BookingsDiscoveryView.initState` reads `clockProvider`, which
/// `AppHarness.boot` overrides to `kFixedNow`, so the screen's "today", its
/// day rail and its landing query are all anchored to June 14th 2026 no
/// matter what day the suite runs on. A test that reaches for
/// `DateTime.now()` instead is asserting against the RUNNER's calendar and
/// will disagree with the app by however far the two have drifted — which is
/// exactly how the month-switcher and «Сьогодні» flows first failed (the app
/// rendered «Червень 2026», the test demanded «Липень 2026»).
///
/// Using the injected clock is the STRONGER assertion, not a concession:
/// because `kFixedNow` is deliberately far from any real run date, an app
/// that fell back to a bare `DateTime.now()` would now fail this file loudly
/// instead of passing by coincidence.
final DateTime _kyivToday = dateOnly(toBeauticaTime(kFixedNow));

/// Scrolls the day rail until [day]'s chip is actually built, taps it, and
/// waits out the screen's 220 ms day-tap debounce.
///
/// The rail is a LAZY `ListView.builder` — 361 chips at a fixed
/// `kRailItemExtent`, of which only the visible handful are ever built — and
/// it opens aligned to "today"-first, so roughly six days are on screen at
/// once. Every seeded-booking day in this file comes from
/// `fb.bookingStartsAt`, which is anchored to the REAL clock (7 days out)
/// while the rail is anchored to the INJECTED one, leaving the target ~45
/// cells to the right of the viewport and therefore never built. A bare
/// `tester.tap(find.byKey(dayChipKey(day)))` then fails the finder outright:
/// "Found 0 widgets with key master-bookings-day-chip-2026-07-29".
///
/// Production is correct here — a real master scrolls the rail to reach a
/// day, which is precisely what this helper does. Same class of fix, and the
/// same reasoning, as `tapCalendarDay` in `test/helpers/pump_app.dart`
/// (commit `e177305`), which scrolls `MonthCalendar` cells into view before
/// tapping them.
/// Scrolls the day rail until [day]'s chip is BUILT and on screen, without
/// tapping it — for assertions about a cell's own content (its
/// has-bookings dot) that must not also change the selection.
///
/// A no-op when the chip is already visible, so it is safe to call ahead of
/// [_selectRailDay] on the same day.
Future<void> _scrollRailTo(WidgetTester tester, DateTime day) async {
  await tester.scrollUntilVisible(
    find.byKey(dayChipKey(day)),
    400,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('master-bookings-day-rail')),
          matching: find.byType(Scrollable),
        )
        .first,
    maxScrolls: 200,
  );
}

Future<void> _selectRailDay(WidgetTester tester, DateTime day) async {
  await _scrollRailTo(tester, day);
  await tester.tap(find.byKey(dayChipKey(day)));
  // fixed-wait-ok: advancing past the 220 ms day-tap debounce.
  await tester.pump(const Duration(milliseconds: 300));
  await AppHarness.settle(tester);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'INDEPENDENT_MASTER opens «Мої записи», narrows by a rail day, and opens '
    'the booking in the PROVIDER view',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      final GoRouter router = await AppHarness.boot(tester, fb);

      expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      // ── 1. The master lands on their own shell, NOT the client one. ───────
      expect(AppHarness.location(router), startsWith(RouteNames.masterProfile));

      // ── 2. «Мої записи» (nav tile 1) pushes the MASTER route. ─────────────
      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);

      expect(
        AppHarness.location(router),
        startsWith(RouteNames.masterBookings),
        reason:
            'tile 1 must reach /master/bookings; /bookings is the CLIENT '
            'branch and the role gate would bounce a master straight off it',
      );
      expect(
        AppHarness.location(router),
        isNot(startsWith('${RouteNames.clientBookings}/')),
      );
      expect(find.byType(MasterBookingsScreen), findsOneWidget);
      expect(
        router.canPop(),
        isFalse,
        reason:
            'go, NOT push — the bottom nav bar REPLACES the stack on a tab '
            'switch (`_VelvetNavTile.onTap` calls `context.go`, a deliberate '
            'reversal of the earlier push behaviour; see that call site). '
            '`push` grew the back stack once per tab tap, so hopping the four '
            'tabs left it four deep. A revert to `push` would make this true '
            'again and fail here.',
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
      // The seeded day sits ~45 lazily-built cells right of the opening
      // viewport — scroll it into existence before reading its dot.
      await _scrollRailTo(tester, bookedDay);
      expect(
        find.byKey(dayDotKey(bookedDay)),
        findsOneWidget,
        reason: 'the seeded booking\'s day must carry a dot',
      );

      // ── 5. Selecting that rail day re-queries with from == to ON THE WIRE. ─
      final int callsBeforeNarrow = fb.getMyBookingsCalls;
      await _selectRailDay(tester, bookedDay);

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
        AppHarness.location(router),
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

      expect(
        AppHarness.location(router),
        startsWith(RouteNames.masterBookings),
      );
      expect(find.byType(MasterBookingsScreen), findsOneWidget);
      expect(find.byType(BookingDetailScreen), findsNothing);
      expect(
        find.byKey(const Key('master-booking-card-booking-1')),
        findsOneWidget,
      );
    },
  );

  // ── Phase 7.13 — filter sheet rework ────────────────────────────────────────
  //
  // Step 2.7 Rule 3b: this phase reworked a user-facing surface — the filter
  // sheet lost its Дата section. The widget/unit tier already proves this in
  // isolation against a MOCKED repository — `bookings_filter_sheet_test.dart`
  // (exactly two sections, the 4-row/5-wire-value status model, draft
  // semantics). None of it proves the sheet reaches a REAL HTTP boundary
  // through a real login — this does.
  //
  // Phase 7.16 retired the rail's calendar escape hatch outright (day
  // selection is by scrolling the rail alone, with the month switcher and
  // «Сьогодні» covering the long-distance jumps it used to exist for), so the
  // parts of this test that used to drive it through a real fetch are gone
  // with it — `bookings_day_picker.dart` and `bookings_day_picker_test.dart`
  // no longer exist.
  testWidgets('the filter sheet has no Дата section — Phase 7.13', (
    tester,
  ) async {
    final fb = FakeBackend()..currentRole = UserRole.independentMaster;
    final GoRouter router = await AppHarness.boot(tester, fb);

    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
    await tester.tap(find.byKey(const Key('master-nav-tile-1')));
    await AppHarness.settle(tester);
    expect(find.byType(MasterBookingsScreen), findsOneWidget);
    expect(AppHarness.location(router), startsWith(RouteNames.masterBookings));

    // The filter sheet is Статус + Послуга only — no Дата anywhere.
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

    // The calendar escape hatch is gone (Phase 7.16) — no such key exists
    // to find any more.
    expect(
      find.byKey(const Key('master-bookings-calendar-button')),
      findsNothing,
    );
  });

  // ── mobile-qa disposition follow-up (2026-07-20) ────────────────────────────
  //
  // The widget tier (`master_bookings_filter_wiring_test.dart`, mutation-
  // verified: the pinned line was broken, the test went RED, restored) proves
  // the filter sheet's OWN callback wiring — the right arguments reach a
  // MOCKED repository. It cannot prove the request that actually leaves the
  // device carries those arguments correctly: a regression at the
  // Dio/serialisation boundary (a `serviceId` key silently renamed, `status`
  // collapsed to a bare scalar where a repeated param is expected, …) would
  // still pass every widget-tier assertion, because the mock never re-derives
  // wire shape from what it was called with. This flow drives a REAL status +
  // service selection through the filter sheet and pins the resulting
  // `GET /bookings/me` at the wire via `FakeBackend.lastMyBookingsQuery` —
  // recorded unconditionally on every hit, see that field's own doc — then
  // confirms the rendered list actually narrowed, not just that the "right"
  // query was recorded (a fake/backend that silently ignored the status
  // filter would still leave both cards on screen even with a correct
  // recorded query).
  testWidgets(
    'selecting a status AND a service in the filter sheet reaches GET '
    '/bookings/me as real query params, and the rendered list narrows to '
    'match',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;

      // Two bookings on the SAME Kyiv day as the fake's booked-days seed
      // (`fb.bookingStartsAt`'s date), one CONFIRMED and one COMPLETED — the
      // exact pair the «Завершено» filter chip must isolate to prove the
      // wiring, not merely that SOME request fired.
      final DateTime seededStart = DateTime.parse(fb.bookingStartsAt);
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        fb.datasetBookingRow(
          id: 'filter-confirmed',
          status: 'CONFIRMED',
          startsAt: seededStart,
        ),
        fb.datasetBookingRow(
          id: 'filter-completed',
          status: 'COMPLETED',
          startsAt: seededStart.add(const Duration(hours: 2)),
        ),
      ]);

      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);
      expect(find.byType(MasterBookingsScreen), findsOneWidget);
      expect(
        AppHarness.location(router),
        startsWith(RouteNames.masterBookings),
      );

      // Narrow the rail to the seeded day so both bookings are in view before
      // any status/service filter narrows them further — same pattern as the
      // "two back-to-back" test above.
      final DateTime bookedDay = parseApiDate(
        fb.bookingStartsAt.substring(0, 10),
      );
      await _selectRailDay(tester, bookedDay);

      expect(
        find.byKey(const ValueKey<String>('timeline-card-filter-confirmed')),
        findsOneWidget,
        reason:
            'both seeded bookings must be visible before any filter is '
            'applied',
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-card-filter-completed')),
        findsOneWidget,
      );

      // ── Open the sheet, select «Завершено» (COMPLETED) + the master's
      //      first real service, apply. ─────────────────────────────────────
      await tester.tap(find.byKey(const Key('master-bookings-filter-button')));
      await AppHarness.settle(tester);
      expect(
        find.byKey(const Key('master-bookings-filter-sheet')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('master-bookings-filter-status-completed')),
      );
      await AppHarness.settle(tester);

      // `assign-1` is FakeBackend's first seeded `/independent-masters/me
      // /services` entry — the same catalogue `masterServiceCatalogProvider`
      // resolves for every flow in this suite (see `_services` in
      // `support/fake_backend.dart`).
      final Finder serviceRow = find.byKey(
        const Key('master-bookings-filter-service-assign-1'),
      );
      await tester.scrollUntilVisible(
        serviceRow,
        80,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('master-bookings-filter-sheet')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(serviceRow);
      await AppHarness.settle(tester);

      await tester.tap(find.byKey(const Key('master-bookings-filter-apply')));
      await AppHarness.settle(tester);

      // ── The real request carries BOTH filters, at the wire — not just
      //      inside the notifier's own in-memory state. ───────────────────────
      expect(
        fb.lastMyBookingsQuery,
        isNotNull,
        reason: 'applying the sheet must have issued a GET /bookings/me',
      );
      expect(fb.lastMyBookingsQuery!['status'], <String>['COMPLETED']);
      expect(fb.lastMyBookingsQuery!['serviceId'], <String>['assign-1']);
      expect(fb.lastMyBookingsQuery!['from'], toApiDate(bookedDay));
      expect(fb.lastMyBookingsQuery!['to'], toApiDate(bookedDay));

      // ── The rendered list actually narrowed. `_slicedBookingsPageEnvelope`
      //      filters the fake's dataset by `status` (it does not filter by
      //      `serviceId` — see its own doc), so this is the layer that would
      //      catch a status-filter regression the query-param assertion above
      //      cannot: a notifier that recorded the right query but dropped it
      //      before actually re-fetching would leave BOTH cards on screen. ──
      expect(
        find.byKey(const ValueKey<String>('timeline-card-filter-confirmed')),
        findsNothing,
        reason:
            'the CONFIRMED booking must be filtered OUT once «Завершено» is '
            'applied',
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-card-filter-completed')),
        findsOneWidget,
        reason: 'the COMPLETED booking must remain visible',
      );
    },
  );

  // ── Phase 7.14 — the master bottom nav bar ─────────────────────────────────
  //
  // Before this phase «Мої записи» was a dead end: reachable via nav tile 1,
  // but rendering no chrome of its own, so the ONLY way off it was the OS back
  // gesture. The widget tier (`master_bookings_screen_test.dart`'s "bottom
  // nav" group) proves this against a mocked repository; this flow proves the
  // SAME bar survives a REAL login + a REAL router + a REAL second screen
  // («Послуги», backed by the fake `GET /independent-masters/me/services`)
  // round trip — the class of thing a widget test stubbing the repository
  // cannot exercise.
  testWidgets(
    '«Мої записи» is no longer a dead end — the bottom nav bar round-trips '
    'to «Послуги» and back, and the already-active tile is a no-op',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);
      expect(find.byType(MasterBookingsScreen), findsOneWidget);
      expect(
        AppHarness.location(router),
        startsWith(RouteNames.masterBookings),
      );

      // ── A. The bar is there at all — the fix this phase exists for. ────────
      expect(find.byType(VelvetBottomNavBar), findsOneWidget);
      expect(
        tester
            .widget<VelvetBottomNavBar>(find.byType(VelvetBottomNavBar))
            .activeIndex,
        1,
        reason:
            '«Мої записи» is tile 1 — a stray copy-paste of the profile '
            "screen's `activeIndex: 3` would still render *a* bar and pass a "
            'bare presence check',
      );
      expect(
        router.canPop(),
        isFalse,
        reason: 'precondition: nothing pushed yet',
      );

      // ── B. Tapping a non-active tile (Послуги) REPLACES the stack with the
      //      real services screen, backed by the fake services endpoint. ────
      await tester.tap(find.byKey(const Key('master-nav-tile-0')));
      await AppHarness.settle(tester);

      expect(find.byType(ServicesListScreen), findsOneWidget);
      expect(AppHarness.location(router), startsWith(RouteNames.services));
      expect(
        router.canPop(),
        isFalse,
        reason:
            'go, NOT push — `_VelvetNavTile.onTap` calls `context.go`, so a '
            'tab switch REPLACES the stack instead of growing it. This is '
            'the load-bearing assertion of the unbounded-back-stack fix: '
            'under the old `push` behaviour each of the four tabs left '
            'another entry behind, and this would read true.',
      );

      // ── C. The bar itself is the way back — «Мої записи» round-trips to the
      //      bookings screen, and the stack STILL has not grown. ─────────────
      //
      // `router.pop()` is deliberately NOT used here: with `go` there is
      // nothing to pop, and popping is not how a user leaves a tab. The bar
      // rendered on every one of the four tab screens IS the return path —
      // that is the property that makes stack-replacing `go` safe (see
      // `_VelvetNavTile.build`'s comment), so exercising it is the point.
      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);

      expect(find.byType(MasterBookingsScreen), findsOneWidget);
      expect(find.byType(ServicesListScreen), findsNothing);
      expect(
        AppHarness.location(router),
        startsWith(RouteNames.masterBookings),
      );
      expect(
        router.canPop(),
        isFalse,
        reason:
            'a full there-and-back tab round-trip must leave the stack '
            'exactly as it started — one entry, nothing to pop',
      );

      // ── D. Tapping the now-active tile (Мої записи) again is a no-op — it
      //      neither navigates nor re-issues the day fetch. ──────────────────
      final int callsBeforeNoOp = fb.getMyBookingsCalls;
      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);

      expect(
        router.canPop(),
        isFalse,
        reason:
            'the already-active tile must resolve to a null route — a '
            'regression here would stack a second /master/bookings on top '
            'of the first',
      );
      expect(find.byType(MasterBookingsScreen), findsOneWidget);
      expect(
        AppHarness.location(router),
        startsWith(RouteNames.masterBookings),
      );
      // Under `go` a redundant re-navigation would not grow the stack, so
      // `canPop` alone can no longer prove the active tile is inert. The
      // absence of a fresh `GET /bookings/me` can: re-entering the route
      // would remount the screen and re-issue its landing query.
      expect(
        fb.getMyBookingsCalls,
        callsBeforeNoOp,
        reason:
            'the active tile must not re-navigate — a `go` to the current '
            'location would remount MasterBookingsScreen and refetch the day',
      );
    },
  );

  // ── Phase 7.10/7.11 rework — clipping + same-lane overlap regression ───────
  //
  // Step 2.7 Rule 3b: the real-device bug report this covers ("I can see only
  // half of the card, and another card is cut off") happened on the exact
  // journey this file already drives (login → «Мої записи» → timeline grid →
  // tap a card), so extending THIS flow — rather than authoring a new one —
  // is the right call; a brand-new flow would just re-derive the same
  // login/router/HTTP scaffolding for no added confidence.
  //
  // `bookings_timeline_grid_test.dart` already pins the R2 (clip) and R3
  // (overlap) fixes at the widget tier with REAL render geometry
  // (`tester.getRect`) — the app's actual `VelvetText`/`VelvetShadows`
  // metrics run there too (`pumpApp` mounts a real `MaterialApp` + l10n). What
  // that tier CANNOT prove is that the fix survives being fed by a REAL
  // `GET /bookings/me` response (dataset-shaped, not hand-authored `Booking`
  // objects) through the REAL `MasterBookingsScreen` → `BookingsDayNotifier` →
  // `BookingsTimelineGrid` wiring behind a REAL login. That gap is what this
  // test closes — it does not re-prove every widget-tier assertion (that
  // would be coverage theater), only the two whose class of bug was the
  // actual field report: a card renders its FULL height (not clipped), and a
  // tap on the visually-earlier card resolves to the earlier booking (not
  // the later one it used to render on top of).
  testWidgets(
    'two back-to-back short bookings on the same day both render their full '
    'natural height and the earlier card wins the tap, through a real GET '
    '/bookings/me',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;

      // Two CONFIRMED, 20-minute, back-to-back bookings on the SAME Kyiv day
      // as the fake's booked-days seed (`fb.bookingStartsAt`'s date):
      // 09:00–09:20 then 09:20–09:40.
      // Same shape as `bookings_timeline_grid_test.dart`'s "R3 regression"
      // group, but arriving over the wire via [FakeBackend.seedManyBookingsDataset]
      // instead of hand-built `Booking` objects.
      //   * 20 minutes is short enough to hit R2 (the old floor-at-48dp
      //     Positioned height clipped anything under ~50 minutes).
      //   * Zero gap between them is the R3 case (the old duration-derived
      //     `top` advance left the second card's top inside the first
      //     card's real ~150-190dp body).
      //
      // The DAY is derived from `fb.bookingStartsAt` (same idiom as the filter
      // test above), never hand-typed. These two rows used to hardcode
      // `DateTime.utc(2026, 7, 20, ...)` to match what was then a hardcoded
      // `bookingStartsAt`; once that field was re-anchored to a rolling date,
      // the hardcoded copy pointed at a day the booked-days rail no longer
      // offers, so the `dayChipKey(bookedDay)` tap below narrowed to an EMPTY
      // day and neither card could ever be found. Deriving the day keeps the
      // two in lockstep by construction.
      final DateTime seededDay = DateTime.parse(fb.bookingStartsAt);
      // 06:00 UTC == 09:00 Kyiv (UTC+3, summer time).
      final DateTime firstStart = DateTime.utc(
        seededDay.year,
        seededDay.month,
        seededDay.day,
        6,
      );
      final List<Map<String, dynamic>> dataset = <Map<String, dynamic>>[
        fb.datasetBookingRow(
          id: 'booking-1',
          status: 'CONFIRMED',
          startsAt: firstStart, // 09:00 Kyiv
          duration: const Duration(minutes: 20),
        ),
        fb.datasetBookingRow(
          id: 'booking-2-overlap',
          status: 'CONFIRMED',
          startsAt: firstStart.add(const Duration(minutes: 20)), // 09:20 Kyiv
          duration: const Duration(minutes: 20),
        ),
      ];
      fb.seedManyBookingsDataset(dataset);

      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);
      expect(find.byType(MasterBookingsScreen), findsOneWidget);

      // Narrow to the seeded day explicitly (same pattern as the earlier test
      // in this file) — deterministic regardless of `kFixedNow`'s own date.
      final DateTime bookedDay = parseApiDate(
        fb.bookingStartsAt.substring(0, 10),
      );
      await _selectRailDay(tester, bookedDay);

      // ── Both cards actually reached the screen over the real wire. ────────
      expect(
        find.byKey(const ValueKey<String>('timeline-card-booking-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-card-booking-2-overlap')),
        findsOneWidget,
      );

      // ── R2 — neither card is clipped: each one renders at least its
      //      layout's FULL natural height, not a truncated sliver. ──────────
      //
      // The bound is `MasterBookingCard.microLayoutNaturalHeight` — the card's
      // own published constant for the SHORTEST body it can render — not a
      // hand-picked number, and deliberately the shortest of the three rather
      // than the layout these particular fixtures happen to select.
      //
      // R2's real meaning is "nothing is truncated", which is a statement
      // about the card's own natural height, not about which density it
      // chose. Two earlier revisions of this bound tracked a specific layout
      // and both went stale within one scale change: `greaterThan(120)` (the
      // FULL body's bound applied to cards that must render compact,
      // unsatisfiable by construction), then
      // `MasterBookingCard.estimatedNaturalHeight` (56dp, the COMPACT body's)
      // — which ADDENDUM 8 broke in turn, because at 120dp/hour these
      // 20-minute bookings floor at 40dp and correctly select the MICRO row.
      // The shortest natural is the one bound that stays true across every
      // scale and density pass while still failing on a clipped sliver, which
      // is the field bug this guards.
      final double earlyHeight = tester
          .getSize(
            find.byKey(const ValueKey<String>('timeline-card-booking-1')),
          )
          .height;
      final double laterHeight = tester
          .getSize(
            find.byKey(
              const ValueKey<String>('timeline-card-booking-2-overlap'),
            ),
          )
          .height;
      expect(
        earlyHeight,
        greaterThanOrEqualTo(MasterBookingCard.microLayoutNaturalHeight),
      );
      expect(
        laterHeight,
        greaterThanOrEqualTo(MasterBookingCard.microLayoutNaturalHeight),
      );

      // ── R3 — the two rendered Rects do not intersect, and the later card
      //      sits entirely below the earlier one. ────────────────────────────
      final Rect earlyRect = _masterCardRect(tester, 'booking-1');
      final Rect laterRect = _masterCardRect(tester, 'booking-2-overlap');
      expect(
        earlyRect.overlaps(laterRect),
        isFalse,
        reason:
            'booking-1 $earlyRect and booking-2-overlap $laterRect must not '
            'intersect on the real screen, fed by a real GET /bookings/me — '
            'this is the exact real-device report ("I can see only half of '
            'the card, and another card is cut off")',
      );
      expect(laterRect.top, greaterThanOrEqualTo(earlyRect.bottom));

      // ── R3 — tapping at the EARLIER card's real rendered centre must open
      //      the EARLIER booking. Before the fix this point could have been
      //      inside BOTH cards' hit-test regions, with the later one (painted
      //      on top) winning every time. `booking-2-overlap` has no detail
      //      route wired in the fake — proving THIS side of the tap resolves
      //      correctly is sufficient; a wrong resolution here would push a
      //      route this app never gets to render, which the location
      //      assertion below still catches directly (routing happens from the
      //      tapped `Booking` object, before any HTTP round trip). ──────────
      await tester.tapAt(earlyRect.center);
      await AppHarness.settle(tester);

      expect(
        AppHarness.location(router),
        RouteNames.masterBookingDetail('booking-1'),
        reason:
            'a tap at the earlier card\'s own rendered centre must push the '
            'earlier booking\'s detail route, not the later one it used to '
            'silently render on top of',
      );
      expect(find.byType(BookingDetailScreen), findsOneWidget);
    },
  );

  // ── 2026-07-21 — the card's time is a RANGE, sourced from the wire `endsAt`,
  //      and carries NO date ────────────────────────────────────────────────
  //
  // Step 2.7 Rule 3b: this pass changed what a real screen prints, so the
  // widget tier alone does not close the gate. `master_booking_card_test.dart`
  // proves both layouts print `formatSlotTimeRange(startAt, endAt)` and no
  // date — but it hands the widget a hand-built `Booking` object, so it can
  // only ever prove the WIDGET reads the field it is given. Two links of the
  // real chain are outside its reach:
  //
  //   * `endsAt` has to survive the wire -> generated DTO -> `BookingMapper` ->
  //     `Booking.endAt` path at all. A mapper that dropped `endsAt` and
  //     back-filled it from `durationMinutesAtBooking` would leave every
  //     widget-tier assertion green (they are fed a `Booking` whose `endAt` is
  //     already correct) while shipping a card that silently prints the
  //     derived end.
  //   * The card also has to be the one the day-scoped timeline actually
  //     mounts, with the day rail above it — which is the whole justification
  //     for dropping the per-card date.
  //
  // THE DISCRIMINATING FIXTURE: the seeded row's `endsAt` is deliberately set
  // 45 minutes past its `startsAt` while `durationMinutesAtBooking` still says
  // 60. Against an ordinary row the two derivations agree exactly and this
  // test would pass through a mapper regression unchanged; with them in
  // disagreement, only a card fed by the real persisted `endsAt` prints
  // 09:45. Same discrimination the widget tier applies, carried down to the
  // HTTP boundary. (60 minutes is also what keeps the card on its FULL layout
  // — `durationMinutes` is what the timeline's height floor reads — so this
  // exercises the fuller of the two bodies.)
  testWidgets(
    'the timeline card prints a start–end range read from the wire endsAt, '
    'and no date, through a real GET /bookings/me',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;

      // Same Kyiv day as the fake's booked-days seed, derived from
      // `fb.bookingStartsAt` rather than hand-typed (see the "two back-to-back"
      // test below for the incident that idiom prevents).
      final DateTime seededDay = DateTime.parse(fb.bookingStartsAt);
      // 06:00 UTC == 09:00 Kyiv (UTC+3, summer time).
      final DateTime wireStart = DateTime.utc(
        seededDay.year,
        seededDay.month,
        seededDay.day,
        6,
      );
      const int wireDurationMinutes = 60;
      final DateTime wireEnd = wireStart.add(const Duration(minutes: 45));

      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        <String, dynamic>{
          ...fb.datasetBookingRow(
            id: 'range-card',
            status: 'CONFIRMED',
            startsAt: wireStart,
            duration: const Duration(minutes: wireDurationMinutes),
          ),
          // The deliberate divergence — see this test's header. Overriding the
          // key AFTER the spread is what makes `endsAt` disagree with
          // `durationMinutesAtBooking`, which `datasetBookingRow` otherwise
          // keeps in lockstep by construction.
          'endsAt': wireEnd.toIso8601String(),
        },
      ]);

      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);
      expect(find.byType(MasterBookingsScreen), findsOneWidget);
      expect(
        AppHarness.location(router),
        startsWith(RouteNames.masterBookings),
      );

      // Narrow the rail to the seeded day so the card is on screen.
      final DateTime bookedDay = parseApiDate(
        fb.bookingStartsAt.substring(0, 10),
      );
      await _selectRailDay(tester, bookedDay);

      final Finder card = find.byKey(
        const Key('master-booking-card-range-card'),
      );
      expect(
        card,
        findsOneWidget,
        reason: 'the seeded booking must have reached the timeline',
      );

      // ── The RANGE, anchored to the two instants that actually went on the
      //      wire — not to whatever the widget happens to hold. ──────────────
      final String expectedRange = formatSlotTimeRange(wireStart, wireEnd);
      expect(
        find.descendant(of: card, matching: find.text(expectedRange)),
        findsOneWidget,
        reason:
            'the card must print «$expectedRange» — both wire instants '
            'converted to the Kyiv wall-clock',
      );

      // ── …and NOT the duration-derived end. This is the assertion the
      //      fixture's deliberate endsAt/durationMinutesAtBooking divergence
      //      exists for: a mapper (or card) that re-derived the end from the
      //      duration prints 09:00–10:00 here and nothing else in this file
      //      would notice. ───────────────────────────────────────────────────
      final String durationDerived = formatTimeRange(
        wireStart,
        wireDurationMinutes,
      );
      expect(
        durationDerived,
        isNot(expectedRange),
        reason:
            'the fixture must keep endsAt and durationMinutesAtBooking in '
            'DISAGREEMENT, or the assertion below proves nothing',
      );
      expect(
        find.descendant(of: card, matching: find.text(durationDerived)),
        findsNothing,
        reason:
            're-deriving the end from durationMinutesAtBooking is exactly the '
            'second source of truth the persisted endAt avoids',
      );

      // ── …and NOT the bare start time the range replaced. ──────────────────
      expect(
        find.descendant(
          of: card,
          matching: find.text(formatSlotTime(wireStart)),
        ),
        findsNothing,
        reason: 'the bare start time alone is the retired pre-range shape',
      );

      // ── NO DATE anywhere on the card. Probed by the seeded day's own Kyiv
      //      short-month token (derived, never a Cyrillic literal — the
      //      `forbid_cyrillic_finder.sh` gate) and SCOPED to the card
      //      subtree: the `BookingsDayRail` above the timeline legitimately
      //      renders the month, and that is precisely why the card no longer
      //      needs to. An unscoped probe would fail on the rail and prove
      //      nothing about the card. ────────────────────────────────────────
      final String monthToken =
          kMonthsUkShort[toBeauticaTime(wireStart).month - 1];
      expect(
        find.descendant(of: card, matching: find.textContaining(monthToken)),
        findsNothing,
        reason:
            'a date component ("$monthToken") reached the card — «Мої записи» '
            'is day-scoped and the rail above already names the day',
      );
      expect(
        find.byType(BookingsDayRail),
        findsOneWidget,
        reason:
            'the rail is the surface that carries the day now; if it ever '
            'disappears, dropping the per-card date stops being safe',
      );
    },
  );

  // ── 2026-07-21 — the compact card is a MINIATURE of the >=1h card, and the
  //      45-minute booking is on the COMPACT side of the threshold ──────────
  //
  // Step 2.7 Rule 3b. The two tests below close the one gap the widget tier is
  // STRUCTURALLY unable to reach, and it is not a coverage gap — it is a
  // harness-shape gap:
  //
  //   `master_booking_card_test.dart` selects a layout by HANDING THE WIDGET A
  //   `minHeight:` LITERAL (e.g. `minHeight: 90` / `minHeight: 120`). That
  //   is the test author's own transcription of what
  //   `bookings_timeline_grid.dart`'s `_cardMinHeightFor` is believed to
  //   compute. Nothing in that file executes `_cardMinHeightFor`. So the
  //   user-facing decision this pass actually made — "a 45-minute booking gets
  //   the compact card, a 60-minute one gets the full card" — is asserted
  //   there against a NUMBER, never against a DURATION. Change
  //   `_cardMinHeightFor`'s floor, or `_kHourH`, or the `durationMinutes` the
  //   mapper decodes off `durationMinutesAtBooking`, and every widget-tier
  //   layout-selection case stays green while the shipped app flips 45-minute
  //   bookings onto the full body — the exact "cards drift off their hour
  //   line" regression the compact pass exists to prevent.
  //
  // These flows drive it from the only end that can prove it: a
  // `durationMinutesAtBooking` on the wire, through the real mapper, the real
  // grid, the real height derivation, into the real card.
  testWidgets(
    'a 45-minute booking renders the COMPACT card and a 60-minute one the '
    'FULL card — the layout threshold, driven from durationMinutes on the wire',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;

      // Same Kyiv day as the fake's booked-days seed, derived from
      // `fb.bookingStartsAt` rather than hand-typed — see the "two back-to-back"
      // test above for the incident that idiom prevents.
      final DateTime seededDay = DateTime.parse(fb.bookingStartsAt);
      // 06:00 UTC == 09:00 Kyiv (UTC+3, summer time).
      final DateTime firstStart = DateTime.utc(
        seededDay.year,
        seededDay.month,
        seededDay.day,
        6,
      );

      // 45 minutes and 60 minutes, back to back with a gap, so both land in the
      // SAME lane column. The durations are the whole fixture: at ADDENDUM 8's
      // 120dp/hour, `_cardMinHeightFor(45, 120)` = 90dp (below
      // `_kFullLayoutMinHeight`, 117) and `_cardMinHeightFor(60, 120)` = 120dp
      // (just above it). Nothing here passes a `minHeight` — the grid derives
      // both from `durationMinutesAtBooking` as decoded off the wire, which is
      // exactly why this test survived a scale change that invalidated the
      // dp literals in the widget tier.
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        fb.datasetBookingRow(
          id: 'forty-five',
          status: 'CONFIRMED',
          startsAt: firstStart, // 09:00–09:45 Kyiv
          duration: const Duration(minutes: 45),
        ),
        fb.datasetBookingRow(
          id: 'sixty',
          status: 'CONFIRMED',
          startsAt: firstStart.add(const Duration(minutes: 60)),
          duration: const Duration(minutes: 60), // 10:00–11:00 Kyiv
        ),
      ]);

      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);

      // The MOUNTED screen, not just the location string — a shell-nested push
      // reads as its parent through `router.location` alone.
      expect(find.byType(MasterBookingsScreen), findsOneWidget);
      expect(
        AppHarness.location(router),
        startsWith(RouteNames.masterBookings),
      );

      final DateTime bookedDay = parseApiDate(
        fb.bookingStartsAt.substring(0, 10),
      );
      await _selectRailDay(tester, bookedDay);

      expect(
        fb.getMyBookingsCalls,
        greaterThan(0),
        reason: 'both cards must be served by the real endpoint',
      );

      final Finder shortCard = find.byKey(
        const Key('master-booking-card-forty-five'),
      );
      final Finder longCard = find.byKey(
        const Key('master-booking-card-sixty'),
      );
      expect(shortCard, findsOneWidget);
      expect(longCard, findsOneWidget);

      // ── The 45-minute card is COMPACT. Both bodies now draw a hairline and
      //      print the same range string, so the ONLY observable difference is
      //      WHICH divider key rendered and whether the status indicator is a
      //      dot or a labelled pill — assert both, in both directions. ────────
      expect(
        find.byKey(const Key('master-booking-card-compact-divider-forty-five')),
        findsOneWidget,
        reason:
            'a 45-minute booking derives an 84dp floor, below the 112dp '
            'full-layout threshold — it must render the compact miniature',
      );
      expect(
        find.byKey(const Key('master-booking-card-divider-forty-five')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: shortCard,
          matching: find.byType(TimelineStatusDot),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: shortCard,
          matching: find.byType(TimelineStatusBadge),
        ),
        findsNothing,
      );

      // ── The 60-minute card is FULL. ───────────────────────────────────────
      expect(
        find.byKey(const Key('master-booking-card-divider-sixty')),
        findsOneWidget,
        reason:
            'a 60-minute booking derives a 120dp floor at ADDENDUM 8\'s '
            '120dp/hour, just above the 117dp threshold — it must render the '
            'full divided layout',
      );
      expect(
        find.byKey(const Key('master-booking-card-compact-divider-sixty')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: longCard,
          matching: find.byType(TimelineStatusBadge),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: longCard, matching: find.byType(TimelineStatusDot)),
        findsNothing,
      );

      // ── The real rendered boxes, so a "compact layout inside an oversized
      //      box" regression cannot pass the key checks above.
      //
      // THESE LITERALS WERE STALE AND THIS TEST WAS RED (mobile-qa,
      // 2026-07-24). They were `84` and `>= 112`, derived from the retired
      // 112dp/hour scale. ADDENDUM 8 moved `_kHourH` to 120, so the 45-minute
      // floor is `45/60 × 120 = 90` and the 60-minute floor is `120` — the
      // `expect(shortHeight, 84)` below could not pass. Nothing caught it
      // because `integration_test/` needs an emulator and is not part of the
      // CI gate, so a scale change silently broke a test no one runs.
      //
      // Hence the RATIO assertion that follows the two absolute ones: it is
      // the only one of the three that survives the next scale change without
      // an edit, and it is the property actually under test — that a card's
      // box tracks its DURATION proportionally rather than rounding to a
      // fixed unit per layout.
      final double shortHeight = tester.getSize(shortCard).height;
      final double longHeight = tester.getSize(longCard).height;
      expect(
        shortHeight,
        closeTo(90, 0.5),
        reason:
            'the 45-minute card measured ${shortHeight}dp against its 90dp '
            'duration-derived floor (45/60 × 120) — either _cardMinHeightFor '
            'drifted or the compact body no longer fits the slot its duration '
            'owns',
      );
      expect(
        shortHeight,
        greaterThanOrEqualTo(MasterBookingCard.estimatedNaturalHeight),
        reason:
            'the 45-minute card selects the COMPACT body, so its box can '
            'never be shorter than that body\'s own natural height',
      );
      expect(
        longHeight,
        closeTo(120, 0.5),
        reason:
            'the 60-minute card measured ${longHeight}dp against its 120dp '
            'floor (60/60 × 120) — the full body\'s 117dp natural is BELOW '
            'that floor, so the floor governs and the card lands exactly on '
            'its end-time line',
      );
      expect(
        longHeight,
        greaterThanOrEqualTo(MasterBookingCard.fullLayoutNaturalHeight),
        reason:
            'the 60-minute card measured ${longHeight}dp — below the full '
            'body\'s own natural means the compact body was selected after '
            'all, whatever the divider keys above reported',
      );
      // THE SCALE-FREE INVARIANT: both durations clear their layout's natural
      // height, so both boxes equal their wall-clock bands exactly — and the
      // ratio of the boxes must therefore equal the ratio of the durations,
      // at ANY dp-per-hour. A future scale pass that breaks proportionality
      // fails here even if it updates the two literals above.
      expect(
        longHeight / shortHeight,
        closeTo(60 / 45, 0.02),
        reason:
            'a 60-minute card (${longHeight}dp) must be exactly 60/45 of a '
            '45-minute one (${shortHeight}dp); a different ratio means one of '
            'the two hit a floor or a layout natural instead of its own band',
      );
    },
  );

  // The compact card's SHAPE, end to end. `master_booking_card_test.dart`
  // asserts the same reading order against a hand-built `Booking`; this proves
  // the five fields it arranges each survive the wire → generated DTO →
  // `BookingMapper` → `Booking` → card path, and that the arrangement holds
  // inside the real timeline rather than under a bare `Center`.
  testWidgets(
    'the compact card reads identity above the hairline and transaction '
    'below, every field sourced from a real GET /bookings/me',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;

      final DateTime seededDay = DateTime.parse(fb.bookingStartsAt);
      // 06:00 UTC == 09:00 Kyiv (UTC+3, summer time).
      final DateTime wireStart = DateTime.utc(
        seededDay.year,
        seededDay.month,
        seededDay.day,
        6,
      );
      const Duration wireDuration = Duration(minutes: 30);

      // `datasetBookingRow` seeds the MASTER-side identity only — the compact
      // row 1 renders the CLIENT, so the counterparty fields are spread in on
      // top, from the same `/users/me` persona every other flow asserts
      // against. Without them the card falls back to the guest label and the
      // "row 1 names the client" assertion below would silently pass on a
      // placeholder.
      final Map<String, dynamic> row = <String, dynamic>{
        ...fb.datasetBookingRow(
          id: 'mini',
          status: 'CONFIRMED',
          startsAt: wireStart,
          duration: wireDuration,
        ),
        'clientId': 'client-1',
        'clientFirstName': fb.clientFirstName,
        'clientLastName': fb.clientLastName,
      };
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[row]);

      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);
      expect(find.byType(MasterBookingsScreen), findsOneWidget);
      expect(
        AppHarness.location(router),
        startsWith(RouteNames.masterBookings),
      );

      final DateTime bookedDay = parseApiDate(
        fb.bookingStartsAt.substring(0, 10),
      );
      await _selectRailDay(tester, bookedDay);

      final Finder card = find.byKey(const Key('master-booking-card-mini'));
      expect(card, findsOneWidget);
      expect(
        find.byKey(const Key('master-booking-card-compact-divider-mini')),
        findsOneWidget,
        reason: 'precondition: a 30-minute booking must be the COMPACT card',
      );

      // Every expected string is derived from what actually went on the wire —
      // the range from the two instants, the name from the fake's own persona,
      // the service name and price straight out of the seeded row map. Nothing
      // here is a re-typed literal, so a fixture change cannot leave a stale
      // expectation behind (and no Cyrillic reaches a finder).
      final String expectedRange = formatSlotTimeRange(
        wireStart,
        wireStart.add(wireDuration),
      );
      final String expectedClient =
          '${fb.clientFirstName} ${fb.clientLastName}';
      final String expectedService = row['serviceName'] as String;
      final String expectedPrice = formatBookingPrice(
        price: (row['priceAtBooking'] as num).toDouble(),
        priceMax: (row['priceMaxAtBooking'] as num?)?.toDouble(),
      );

      Finder inCard(Finder matching) =>
          find.descendant(of: card, matching: matching);

      for (final ({String label, String value}) field
          in <({String label, String value})>[
            (label: 'the start–end range', value: expectedRange),
            (label: 'the client name', value: expectedClient),
            (label: 'the service name', value: expectedService),
            (label: 'the price', value: expectedPrice),
          ]) {
        expect(
          inCard(find.text(field.value)),
          findsOneWidget,
          reason: '${field.label} must reach the compact card off the wire',
        );
      }

      // ── ROW 1 (IDENTITY) sits ABOVE the hairline, ROW 2 (TRANSACTION)
      //      BELOW it. This is the property that makes the compact card a
      //      MINIATURE of the >=1h card rather than a differently-shaped card
      //      showing the same fields — and the one a reordering "tidy-up"
      //      would leave every presence assertion above untouched. ───────────
      final double hairlineY = tester
          .getTopLeft(
            find.byKey(const Key('master-booking-card-compact-divider-mini')),
          )
          .dy;

      for (final ({String label, Finder finder}) above
          in <({String label, Finder finder})>[
            (
              label: 'the start–end range',
              finder: inCard(find.text(expectedRange)),
            ),
            (
              label: 'the client name',
              finder: inCard(find.text(expectedClient)),
            ),
            (
              label: 'the status dot',
              finder: inCard(find.byType(TimelineStatusDot)),
            ),
          ]) {
        expect(
          tester.getTopLeft(above.finder).dy,
          lessThan(hairlineY),
          reason: '${above.label} belongs to the identity row, above the rule',
        );
      }

      for (final ({String label, Finder finder}) below
          in <({String label, Finder finder})>[
            (
              label: 'the service name',
              finder: inCard(find.text(expectedService)),
            ),
            (label: 'the price', finder: inCard(find.text(expectedPrice))),
          ]) {
        expect(
          tester.getTopLeft(below.finder).dy,
          greaterThan(hairlineY),
          reason:
              '${below.label} belongs to the transaction row, below the rule',
        );
      }

      // …and within row 1 the lighter range LEADS the heavier client name, and
      // the dot is hard right of both — the diagonal the compact layout's
      // legibility rests on.
      final double rangeX = tester
          .getTopLeft(inCard(find.text(expectedRange)))
          .dx;
      final double nameX = tester
          .getTopLeft(inCard(find.text(expectedClient)))
          .dx;
      final double dotX = tester
          .getTopLeft(inCard(find.byType(TimelineStatusDot)))
          .dx;
      expect(rangeX, lessThan(nameX));
      expect(nameX, lessThan(dotX));

      // The compact card never draws the labelled pill — the label lives in
      // the dot's Semantics/Tooltip channel instead (pinned per status at the
      // widget tier).
      expect(inCard(find.byType(TimelineStatusBadge)), findsNothing);
    },
  );

  // ── 2026-07-22 — the month switcher is a PURE rail-scroll affordance ───────
  //
  // Step 2.7 Rule 3b: `_prevMonth`/`_nextMonth` (`bookings_discovery_view
  // .dart`) are documented as deliberately NOT touching `_day`/`_liveQuery` —
  // stepping the month moves only the switcher's own label and the rail's
  // scroll position, mirroring the approved design's own `_prevMonth`. Nothing
  // in the widget tier drives this through a REAL `GET /bookings/me` call
  // count: a regression that made a month step start re-selecting a day (and
  // re-fetching) would leave every mocked-repository assertion untouched,
  // because a mock never notices an EXTRA call it wasn't told to expect.
  testWidgets(
    'the month switcher only moves the rail — the label changes but the '
    'selected day and the live query do not, and no extra GET /bookings/me '
    'fires',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);
      expect(find.byType(MasterBookingsScreen), findsOneWidget);
      expect(
        AppHarness.location(router),
        startsWith(RouteNames.masterBookings),
      );

      // The screen opens on Kyiv "today"'s month — where "today" is the
      // INJECTED clock the screen actually reads (`clockProvider`, overridden
      // to `kFixedNow` by `AppHarness.boot`), not the host runner's date. See
      // `_kyivToday`'s doc: reaching for `DateTime.now()` here made this
      // assertion demand «Липень 2026» of a screen correctly rendering
      // «Червень 2026».
      final DateTime todayKyiv = _kyivToday;
      final String initialLabel =
          '${monthNominative(todayKyiv.month)} ${todayKyiv.year}';
      expect(find.text(initialLabel), findsOneWidget);

      final int callsBeforeSwitch = fb.getMyBookingsCalls;
      final Map<String, dynamic>? queryBeforeSwitch = fb.lastMyBookingsQuery;

      // ── Step forward one month — only the label moves. ────────────────────
      await tester.tap(find.byKey(const Key('master-bookings-month-next')));
      await AppHarness.settle(tester);

      final DateTime nextMonth = DateTime(todayKyiv.year, todayKyiv.month + 1);
      final String nextLabel =
          '${monthNominative(nextMonth.month)} ${nextMonth.year}';
      expect(find.text(nextLabel), findsOneWidget);
      expect(find.text(initialLabel), findsNothing);

      // ── …then back — the label returns to the original month. ─────────────
      await tester.tap(find.byKey(const Key('master-bookings-month-prev')));
      await AppHarness.settle(tester);
      expect(find.text(initialLabel), findsOneWidget);
      expect(find.text(nextLabel), findsNothing);

      // ── Neither step touched the selection or issued a new request. ───────
      expect(
        fb.getMyBookingsCalls,
        callsBeforeSwitch,
        reason:
            'a month step is a pure rail-scroll affordance — it must not '
            'issue a NEW GET /bookings/me',
      );
      expect(
        fb.lastMyBookingsQuery,
        same(queryBeforeSwitch),
        reason:
            'the recorded query object itself must be the SAME instance — a '
            'new fetch would have replaced it with a fresh map',
      );
      expect(
        find.byKey(const Key('master-booking-card-booking-1')),
        findsOneWidget,
        reason: "the originally-selected day's content must still be shown",
      );
    },
  );

  // ── 2026-07-22 — «Сьогодні» jumps the SELECTION back to Kyiv today ─────────
  //
  // Step 2.7 Rule 3b: unlike the month switcher above, `_goToToday` DOES
  // re-select the day and re-fetch (mirrors `_applySelectedDay`) — the widget
  // tier cannot prove the resulting request actually carries Kyiv "today" at
  // the wire (`from == to == today`), only that the notifier's own in-memory
  // query argument looks right against a mocked repository.
  testWidgets(
    '«Сьогодні» returns the selection to the INJECTED clock\'s Kyiv today, '
    'whose from == to == today query the wire already saw',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);
      expect(find.byType(MasterBookingsScreen), findsOneWidget);
      expect(
        AppHarness.location(router),
        startsWith(RouteNames.masterBookings),
      );

      // ── The LANDING query, on the wire: from == to == the Kyiv date of the
      //      injected clock. This is the "today query" «Сьогодні» must later
      //      return to, captured before anything narrows it. ────────────────
      final String expectedToday = toApiDate(_kyivToday);
      expect(
        fb.lastMyBookingsQuery!['from'],
        expectedToday,
        reason:
            'the landing fetch must carry the Kyiv date of the INJECTED '
            'clock, not the host device\'s own date. The two are deliberately '
            'far apart in this harness (`kFixedNow` is 2026-06-14; the runner '
            'is whenever the suite runs), so a screen that fell back to a '
            'bare `DateTime.now()` fails here rather than passing by '
            'accident.',
      );
      expect(fb.lastMyBookingsQuery!['to'], expectedToday);

      // Narrow to a NON-today rail day first — the seeded booking's own day
      // (`fb.bookingStartsAt`'s date). That fixture is anchored to the REAL
      // clock while the screen's "today" comes from the INJECTED one, so the
      // two are far apart and the day is emphatically not today — exactly the
      // precondition this step needs. (It is also why the chip must be
      // scrolled into view; see `_selectRailDay`.)
      final DateTime bookedDay = parseApiDate(
        fb.bookingStartsAt.substring(0, 10),
      );
      await _selectRailDay(tester, bookedDay);
      expect(
        fb.lastMyBookingsQuery!['from'],
        toApiDate(bookedDay),
        reason:
            'precondition: the selection must have actually moved off '
            'today before «Сьогодні» is asked to bring it back',
      );

      final int callsBeforeToday = fb.getMyBookingsCalls;

      // ── Tap «Сьогодні». ─────────────────────────────────────────────────
      await tester.tap(find.byKey(const Key('master-bookings-today')));
      await AppHarness.settle(tester);

      // ── 1. The SELECTION really came back to the injected clock's Kyiv
      //      today — read off the rail's own `selectedDay`, which the screen
      //      state feeds directly. ──────────────────────────────────────────
      expect(
        tester
            .widget<BookingsDayRail>(find.byType(BookingsDayRail))
            .selectedDay,
        _kyivToday,
        reason:
            '«Сьогодні» must re-select Kyiv today, not merely recentre the '
            'rail (that is the month switcher\'s job) and not leave the '
            'selection parked on the booked day',
      );

      // ── 2. …and it resolved to the SAME query the landing fetch used, not
      //      merely to some other day. Proven by the ABSENCE of a new
      //      request: `bookingsDayProvider` is a keepAlive family bounded by
      //      an LRU, and today's member is still resident (only two distinct
      //      days have been visited, under the LRU's budget). A cache HIT is
      //      therefore only possible if «Сьогодні» produced a query equal to
      //      the landing one — any other date, or a host-clock fallback,
      //      would MISS and fire a fetch. ───────────────────────────────────
      //
      // The earlier `greaterThan(callsBeforeToday)` here asserted the exact
      // opposite and could never hold: it demanded a refetch of a day the app
      // deliberately caches, so it was a regression guard pointing backwards
      // — it would have passed only if the keepAlive cache broke.
      expect(
        fb.getMyBookingsCalls,
        callsBeforeToday,
        reason:
            'returning to an already-loaded day must be served from the '
            'bounded keepAlive cache — a NEW GET /bookings/me here means '
            '«Сьогодні» built a query that is not equal to the landing '
            'day\'s (wrong date, or a host-clock fallback), or that the '
            'cache regressed',
      );
    },
  );

  // ── 2026-07-22 — the header's «+» add-booking affordance ───────────────────
  //
  // Step 2.7 Rule 3b: `_showAddComingSoon` (`bookings_discovery_view.dart`)
  // reads `AppLocalizations`/`ScaffoldMessenger` off a REAL `BuildContext` —
  // the widget tier can prove the callback fires against a mocked notifier,
  // but not that the real chrome (a real `Scaffold`/`MaterialApp`-hosted
  // `ScaffoldMessenger`, behind a real login) actually surfaces the SnackBar.
  testWidgets('the «+» add-booking affordance shows a coming-soon SnackBar', (
    tester,
  ) async {
    final fb = FakeBackend()..currentRole = UserRole.independentMaster;
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
    await tester.tap(find.byKey(const Key('master-nav-tile-1')));
    await AppHarness.settle(tester);
    expect(find.byType(MasterBookingsScreen), findsOneWidget);
    expect(AppHarness.location(router), startsWith(RouteNames.masterBookings));

    final AppLocalizations l10n = _l10nOf(tester, MasterBookingsScreen);

    await tester.tap(find.byKey(const Key('master-bookings-add')));
    await AppHarness.settle(tester);

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text(l10n.masterBookingsAddComingSoon), findsOneWidget);

    // Drain the SnackBar's auto-dismiss timer so none is pending at teardown
    // (mirrors `client_leave_review_flow_test.dart`'s identical drain).
    await tester.pumpUntilGone(find.text(l10n.masterBookingsAddComingSoon));
  });

  // ── 2026-07-22 — the day-scoped SKELETON, while the first fetch is pending ─
  //
  // Step 2.7 Rule 3b: `master_bookings_screen_test.dart` proves the skeleton
  // renders on `AsyncLoading` against a repository whose `Future` the test
  // controls directly. It cannot prove the SAME skeleton renders while a REAL
  // `GET /bookings/me` — through Dio's real interceptor chain — is genuinely
  // in flight. The gate below is a Dio interceptor added to
  // `FakeBackend.dio` from the TEST side (not a change to the fake's own
  // route wiring in `support/fake_backend.dart`, which this file does not
  // own): it holds the first `/bookings/me` request open with a `Completer`
  // until the test lets it through, exactly mirroring how a slow real network
  // would leave the day-scoped provider on `AsyncLoading`.
  testWidgets(
    'the day-scoped skeleton renders while the first day load is in flight, '
    'and clears once it resolves',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      // Gate ONLY the day-scoped `/bookings/me` fetch, not the FILTER-
      // INDEPENDENT `/bookings/me/booked-days` rail call — the latter's path
      // ends in "booked-days", so `endsWith('/bookings/me')` never matches it
      // and the rail still loads normally while the body stays pending.
      final Completer<void> gate = Completer<void>();
      int hits = 0;
      fb.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest:
              (
                RequestOptions options,
                RequestInterceptorHandler handler,
              ) async {
                if (options.path.endsWith('/bookings/me') && hits == 0) {
                  hits++;
                  await gate.future;
                }
                handler.next(options);
              },
        ),
      );

      await tester.tap(find.byKey(const Key('master-nav-tile-1')));

      // `pumpUntilFound`, NOT `pumpAndSettle` — `BookingsSkeleton` drives a
      // shimmer with `AnimationController.repeat(reverse: true)`, so while it
      // is on screen a frame is ALWAYS scheduled and `pumpAndSettle` can
      // never settle; it runs to its timeout and throws instead.
      //
      // This is why the flow passed on the CI emulator and failed on a real
      // handset: the skeleton only repeats when animations are enabled
      // (`MediaQuery.disableAnimations` short-circuits it to a static
      // `_controller.value = 1.0`), and CI emulators run with the animation
      // scales zeroed. The device has them at 1, so it hit the real
      // behaviour. Pumping until the awaited state appears is correct on
      // both, and is what the fixed-wait gate asks for besides.
      await tester.pumpUntilFound(
        find.byKey(const Key('master-bookings-skeleton')),
      );

      expect(
        AppHarness.location(router),
        startsWith(RouteNames.masterBookings),
      );

      expect(
        find.byKey(const Key('master-bookings-skeleton')),
        findsOneWidget,
        reason:
            'the day-scoped fetch is still pending — the skeleton must be '
            'showing, not an empty or loaded body',
      );
      expect(
        find.byKey(const Key('master-booking-card-booking-1')),
        findsNothing,
      );

      // ── Let the gated request resolve. ─────────────────────────────────────
      gate.complete();
      await AppHarness.settle(tester);

      expect(find.byKey(const Key('master-bookings-skeleton')), findsNothing);
      expect(
        find.byKey(const Key('master-booking-card-booking-1')),
        findsOneWidget,
        reason:
            'once the fetch resolves the skeleton must clear and the '
            'seeded booking must render',
      );
    },
  );

  // ── 2026-07-22 — a genuinely empty day: the TRUE empty state ───────────────
  //
  // Step 2.7 Rule 3b: `MasterBookingsEmptyState` vs `MasterBookingsNoResultsState`
  // is a real product distinction (see `master_bookings_states.dart`'s file
  // header) the widget tier already pins against a mocked, hand-built empty
  // page. This closes the same gap every other flow in this file closes for
  // its own surface: proving the distinction survives a REAL, empty
  // `GET /bookings/me` page — `seedManyBookingsDataset` with an EMPTY list is
  // the fake's own supported way to serve a real (statuses, sort, page) slice
  // over NOTHING, so no filter needs to be forced to get here, matching the
  // "no filter active, nothing to reset" precondition the true-empty copy
  // requires.
  testWidgets('a genuinely empty day renders the TRUE empty state, not the '
      'no-results-from-filter one', (tester) async {
    final fb = FakeBackend()
      ..currentRole = UserRole.independentMaster
      ..seedManyBookingsDataset(const <Map<String, dynamic>>[]);
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

    await tester.tap(find.byKey(const Key('master-nav-tile-1')));
    await AppHarness.settle(tester);

    expect(find.byType(MasterBookingsScreen), findsOneWidget);
    expect(AppHarness.location(router), startsWith(RouteNames.masterBookings));
    expect(
      find.byType(MasterBookingsEmptyState),
      findsOneWidget,
      reason:
          'no filter is active — an empty day must render the TRUE empty '
          'state, not the filter-empty one',
    );
    expect(find.byKey(const Key('master-bookings-empty')), findsOneWidget);
    expect(find.byKey(const Key('master-bookings-no-results')), findsNothing);
    expect(
      find.byKey(const Key('master-booking-card-booking-1')),
      findsNothing,
    );
  });

  // ── 2026-07-22 — a failed fetch: the error state, and a working retry ──────
  //
  // Step 2.7 Rule 3b: `master_bookings_screen_test.dart` proves the error
  // widget renders on `AsyncError` and that its `onRetry` calls
  // `ref.invalidate` against a MOCKED repository. It cannot prove a real
  // failed `GET /bookings/me` — through the real Dio interceptor chain, the
  // real repository's `DioException` → `Failure` mapping — actually reaches
  // that widget, or that tapping retry issues a real SECOND request that
  // succeeds. Same TEST-SIDE Dio interceptor technique as the skeleton flow
  // above (added to `FakeBackend.dio`, not to the fake's own route wiring):
  // it rejects only the FIRST `/bookings/me` attempt, before the request ever
  // reaches the fake's adapter — so `fb.getMyBookingsCalls` (incremented
  // inside the fake's own route callback) never counts the rejected attempt,
  // and only the real, successful retry increments it.
  testWidgets(
    'a failed GET /bookings/me renders the error state, and retry issues a '
    'real, successful refetch',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      // Auto-retry OFF for this flow only — see `AppHarness.boot`'s [retry]
      // doc. Riverpod 3 transparently retries a failed provider ten times
      // over ~38 s, staying in `AsyncLoading` between attempts, so the error
      // branch does not render until that budget is spent. With retry
      // disabled the failure surfaces on the first attempt and this test
      // asserts the error surface itself rather than racing the framework.
      //
      // Nothing here is weakened by that: the endpoint still really fails,
      // the real error state still has to render, and the «retry» button
      // still has to issue a real, successful `GET /bookings/me` that really
      // renders the seeded booking. Only the framework's invisible
      // self-healing is taken out of the way.
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        retry: (int retryCount, Object error) => null,
      );
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      int hits = 0;
      fb.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest:
              (RequestOptions options, RequestInterceptorHandler handler) {
                if (options.path.endsWith('/bookings/me') && hits == 0) {
                  hits++;
                  handler.reject(
                    DioException(
                      requestOptions: options,
                      type: DioExceptionType.connectionError,
                      error: 'simulated connection failure (test-side gate)',
                    ),
                  );
                  return;
                }
                handler.next(options);
              },
        ),
      );

      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);
      expect(
        AppHarness.location(router),
        startsWith(RouteNames.masterBookings),
      );

      expect(find.byType(MyBookingsErrorState), findsOneWidget);
      expect(find.byKey(const Key('my_bookings_error')), findsOneWidget);
      expect(find.byKey(const Key('my_bookings_error_retry')), findsOneWidget);
      expect(
        find.byKey(const Key('master-booking-card-booking-1')),
        findsNothing,
      );

      final int callsBeforeRetry = fb.getMyBookingsCalls;

      await tester.tap(find.byKey(const Key('my_bookings_error_retry')));
      await AppHarness.settle(tester);

      expect(
        fb.getMyBookingsCalls,
        callsBeforeRetry + 1,
        reason:
            'retry must have issued exactly one real, successful GET '
            '/bookings/me — the rejected first attempt never reached the '
            'fake, so this counts ONLY the retry',
      );
      expect(find.byKey(const Key('my_bookings_error')), findsNothing);
      expect(
        find.byKey(const Key('master-booking-card-booking-1')),
        findsOneWidget,
        reason:
            'the retry must have succeeded and rendered the seeded '
            'booking',
      );
    },
  );
}
