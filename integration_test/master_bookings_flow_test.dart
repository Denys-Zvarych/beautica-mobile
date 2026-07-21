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
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/formatters/booking_price_labels.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:beautica_mobile/shared/widgets/velvet_bottom_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// The REAL rendered geometry of the [MasterBookingCard] keyed
/// `timeline-card-<id>` — mirrors `bookings_timeline_grid_test.dart`'s own
/// `_cardRect` helper, reading actual screen geometry rather than a
/// `Positioned` widget's declared properties (there is no `Positioned`
/// ancestor any more — see the R3 fix in `bookings_timeline_grid.dart`).
Rect _masterCardRect(WidgetTester tester, String bookingId) =>
    tester.getRect(find.byKey(ValueKey<String>('timeline-card-$bookingId')));

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
  //
  // ⚠ EXECUTION STATUS: not run on a device — see the file-header note above;
  // the dev VM has no attached emulator (host-only-adapter limitation,
  // backlog #179/#191). Verified analyze-clean and wired into both
  // aggregators; first real execution is the CI emulator job.
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
  //
  // ⚠ EXECUTION STATUS: this flow has NOT been run on a device — see the file
  // header note above; the dev VM has no attached emulator (host-only-adapter
  // limitation, backlog #179/#191). It is verified analyze-clean and wired
  // into BOTH aggregators that carry this file — `all_tests.dart` and
  // `all_tests_part2.dart` (this file has no import in `all_tests_part1.dart`;
  // that split shard never carried it) — via this file's EXISTING import, no
  // new aggregator wiring needed. Its first real execution is the CI emulator
  // job, so state it as authored, not passing.
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
      await tester.tap(find.byKey(dayChipKey(bookedDay)));
      // fixed-wait-ok: advancing past the 220 ms day-tap debounce.
      await tester.pump(const Duration(milliseconds: 300));
      await AppHarness.settle(tester);

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
  //
  // ⚠ EXECUTION STATUS: not run on a device — see the file-header note above;
  // the dev VM has no attached emulator (host-only-adapter limitation,
  // backlog #179/#191). Verified analyze-clean and wired into both
  // aggregators; first real execution is the CI emulator job.
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

      // ── B. Tapping a non-active tile (Послуги) pushes and mounts the real
      //      services screen, backed by the fake services endpoint. ─────────
      await tester.tap(find.byKey(const Key('master-nav-tile-0')));
      await AppHarness.settle(tester);

      expect(find.byType(ServicesListScreen), findsOneWidget);
      expect(AppHarness.location(router), startsWith(RouteNames.services));
      expect(
        router.canPop(),
        isTrue,
        reason: 'push, not go — «Мої записи» stays on the back stack',
      );

      // ── C. Popping back lands on the SAME still-mounted bookings screen. ───
      router.pop();
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
        reason: 'back on the tab root — nothing left to pop',
      );

      // ── D. Tapping the now-active tile (Мої записи) again is a no-op — no
      //      duplicate /master/bookings gets pushed onto itself. ─────────────
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
  //
  // ⚠ EXECUTION STATUS: not run on a device — see the file-header note above;
  // the dev VM has no attached emulator (host-only-adapter limitation,
  // backlog #179/#191). Verified analyze-clean and wired into both
  // aggregators (via this file's existing import in `all_tests.dart` /
  // `all_tests_part1.dart` / `all_tests_part2.dart` — no new import needed);
  // first real execution is the CI emulator job.
  testWidgets(
    'two back-to-back short bookings on the same day both render full-height '
    'and the earlier card wins the tap, through a real GET /bookings/me',
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
      await tester.tap(find.byKey(dayChipKey(bookedDay)));
      // fixed-wait-ok: advancing past the 220 ms day-tap debounce.
      await tester.pump(const Duration(milliseconds: 300));
      await AppHarness.settle(tester);

      // ── Both cards actually reached the screen over the real wire. ────────
      expect(
        find.byKey(const ValueKey<String>('timeline-card-booking-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('timeline-card-booking-2-overlap')),
        findsOneWidget,
      );

      // ── R2 — neither card is clipped: both clear the old 48dp floor by a
      //      wide margin, proving the FULL content (avatar, divider, service
      //      row, price/status row) rendered, not a truncated sliver. ───────
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
      expect(earlyHeight, greaterThan(120));
      expect(laterHeight, greaterThan(120));

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
  //
  // ⚠ EXECUTION STATUS: not run on a device — see the file-header note above;
  // the dev VM has no attached emulator (host-only-adapter limitation,
  // backlog #179/#191). Verified analyze-clean, `dart format`-clean, and
  // carried into BOTH aggregators by this file's EXISTING imports in
  // `all_tests.dart` and `all_tests_part2.dart` — no new aggregator wiring is
  // needed because this extends the existing flow file rather than adding one.
  // Its first real execution is the CI emulator job: authored, not passing.
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
      await tester.tap(find.byKey(dayChipKey(bookedDay)));
      // fixed-wait-ok: advancing past the 220 ms day-tap debounce.
      await tester.pump(const Duration(milliseconds: 300));
      await AppHarness.settle(tester);

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
  //   `minHeight:` LITERAL (`minHeight: 84` / `minHeight: 112`). That literal
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
  //
  // ⚠ EXECUTION STATUS: not run on a device — see the file-header note above;
  // the dev VM has no attached emulator (host-only-adapter limitation,
  // backlog #179/#191), and the headless-proxy workaround does not survive
  // `AppHarness.loginAs`'s `tap(login_submit)` under the plain
  // `LiveTestWidgetsFlutterBinding`, so it is not a usable substitute for any
  // flow in this file. Verified analyze-clean and `dart format`-clean, and
  // carried into BOTH aggregators by this file's EXISTING imports in
  // `all_tests.dart` and `all_tests_part2.dart` — extending the flow file adds
  // no new aggregator wiring. Authored, not passing: CI owns the first run.
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
      // SAME lane column and neither can be nudged by collision handling. The
      // durations are the whole fixture: `_cardMinHeightFor(45, 112)` = 84dp
      // (below `_kFullLayoutMinHeight`) and `_cardMinHeightFor(60, 112)` = 112dp
      // (exactly at it). Nothing here passes a `minHeight` — the grid derives
      // both from `durationMinutesAtBooking` as decoded off the wire.
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
      await tester.tap(find.byKey(dayChipKey(bookedDay)));
      // fixed-wait-ok: advancing past the 220 ms day-tap debounce.
      await tester.pump(const Duration(milliseconds: 300));
      await AppHarness.settle(tester);

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
            'a 60-minute booking derives a 112dp floor, exactly at the '
            'threshold — it must render the full divided layout',
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
      //      box" regression cannot pass the key checks above. 84dp is the
      //      45-minute floor met EXACTLY (the compact body's 56dp of content
      //      leaves 28dp of intentional blank room); the 60-minute card is at
      //      or above its own 112dp floor because the full body out-measures
      //      it. ────────────────────────────────────────────────────────────
      final double shortHeight = tester.getSize(shortCard).height;
      final double longHeight = tester.getSize(longCard).height;
      expect(
        shortHeight,
        84,
        reason:
            'the 45-minute card measured ${shortHeight}dp against its 84dp '
            'duration-derived floor — either _cardMinHeightFor drifted or the '
            'compact body no longer fits the slot its duration owns',
      );
      expect(
        longHeight,
        greaterThanOrEqualTo(112),
        reason:
            'the 60-minute card measured ${longHeight}dp — the full body is '
            'taller than its own 112dp floor, so anything below it means the '
            'compact body was selected after all',
      );
    },
  );

  // The compact card's SHAPE, end to end. `master_booking_card_test.dart`
  // asserts the same reading order against a hand-built `Booking`; this proves
  // the five fields it arranges each survive the wire → generated DTO →
  // `BookingMapper` → `Booking` → card path, and that the arrangement holds
  // inside the real timeline rather than under a bare `Center`.
  //
  // ⚠ EXECUTION STATUS: not run on a device — see the block above; authored,
  // analyze-clean, aggregator-carried, CI owns the first run.
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
      await tester.tap(find.byKey(dayChipKey(bookedDay)));
      // fixed-wait-ok: advancing past the 220 ms day-tap debounce.
      await tester.pump(const Duration(milliseconds: 300));
      await AppHarness.settle(tester);

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
}
