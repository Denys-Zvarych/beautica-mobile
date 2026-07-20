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
      // as the fake's booked-days seed (`fb.bookingStartsAt`'s date,
      // 2026-07-20 — Kyiv summer time, UTC+3): 09:00–09:20 then 09:20–09:40.
      // Same shape as `bookings_timeline_grid_test.dart`'s "R3 regression"
      // group, but arriving over the wire via [FakeBackend.seedManyBookingsDataset]
      // instead of hand-built `Booking` objects.
      //   * 20 minutes is short enough to hit R2 (the old floor-at-48dp
      //     Positioned height clipped anything under ~50 minutes).
      //   * Zero gap between them is the R3 case (the old duration-derived
      //     `top` advance left the second card's top inside the first
      //     card's real ~150-190dp body).
      final List<Map<String, dynamic>> dataset = <Map<String, dynamic>>[
        fb.datasetBookingRow(
          id: 'booking-1',
          status: 'CONFIRMED',
          startsAt: DateTime.utc(2026, 7, 20, 6), // 09:00 Kyiv
          duration: const Duration(minutes: 20),
        ),
        fb.datasetBookingRow(
          id: 'booking-2-overlap',
          status: 'CONFIRMED',
          startsAt: DateTime.utc(2026, 7, 20, 6, 20), // 09:20 Kyiv
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
}
