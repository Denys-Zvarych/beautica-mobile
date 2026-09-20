// Phase 345 — E2E: the SALON «Архів» (`/salon/bookings/archive`), end to end.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — integration-test gate)
// ---------------------------------------------------------------
// Phases 342–344 shipped the salon archive as three additive slices, each
// pinned at the tier it lives in: the family key and the repository scope
// (`master_archive_notifier_test.dart`), the screen's three new params and the
// card's attribution row (`master_archive_screen_test.dart`,
// `master_booking_card_test.dart`), the route's declaration order and `extra`
// contract (`salon_bookings_route_shadowing_test.dart`). Phase 344's own E2E
// arm, inside `salon_owner_bookings_board_flow_test.dart`, walks an owner from
// the board to the archive.
//
// None of that could prove the thing this page exists for, because until this
// phase the FAKE could not express it: `GET /bookings/salon/{id}` ignored
// `partition` outright and returned the board's own day list for any query at
// all. So every archive assertion in the tier passed whatever the app sent —
// phase 345 D2's named hazard, and the reason D2 says to check the fake
// FIRST. `fake_backend_bookings_dataset_test.dart`'s phase-345 group is that
// check; this file is what it unlocks.
//
// WHAT THIS FILE ADDS OVER THE 344 ARM
// -------------------------------------
//   * a fixture that DISCRIMINATES on all three D3 axes — two masters, both
//     values of the server's `providerCanReviewClient` flag, and every
//     partition member INCLUDING an elapsed unclosed `CONFIRMED`, the one row
//     `_legacyStatusesFor`'s status-only fallback structurally cannot reach;
//   * a NEGATIVE control the 344 arm has no way to carry: a row that is
//     genuinely UPCOMING, seeded to sort NEWEST so it would be the first card
//     on screen if the read were not partitioned;
//   * real PAGINATION over the salon endpoint — «Завантажити ще» / the scroll
//     tail fetching `page=1` from `/bookings/salon/{id}`, not from
//     `/bookings/me`;
//   * the «Виконано» write closing a salon row and the list genuinely
//     re-reading the SALON endpoint;
//   * both admitted roles (D4) — `SALON_OWNER` and `SALON_ADMIN` — and
//     `SALON_MASTER` denied, with its own `/staff/bookings/archive` still
//     working.
//
// CLOCK: `AppHarness.boot` pins `clockProvider` to `kFixedNow` for the whole
// tier (`e2e_boot_policy.dart`) and every fixture instant below is derived
// from that SAME constant. One clock, both halves — the coherence invariant is
// about MIXING a pinned clock with a host-clock fixture, never about pinning
// (`project_test_clock_coherence_invariant`).
//
// FINDERS: widget Keys and widget TYPES only — never a Cyrillic UI string
// (`forbid_cyrillic_finder.sh`). After a navigation it is the resolved PAGE
// TYPE that is asserted alongside the location, because
// `/salon/bookings/:bookingId` matches `/salon/bookings/archive` just as well
// and only declaration order decides
// (`project_gorouter_literal_before_dynamic_shadowing`).
//
// LAZY TILES: `-d flutter-tester` is 800×600 and the archive is a `ListView`,
// so any card past the first screenful is never BUILT and a bare finder
// resolves to nothing (`project_integration_scroll_filter_into_view`).
// [_revealRow] scrolls first. The one place this file asserts an ABSENCE of a
// row, the row is seeded to sort FIRST, so the absence is about the partition
// and not about the fold.
//
// NO PATROL FLOW: a header tap, a route redirect, four GETs and one PATCH. No
// OS permission dialog, no deep/app link, no FCM or local notification, no
// WebView, no biometric. `integration_test/patrol/` does not apply — stated,
// not omitted.
//
// Run ALONE — ONE file per `flutter test` invocation; batching kills the
// second with a bogus "log reader failed"
// (`project_integration_test_device_driving`).

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_archive_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_bookings_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// An instant [days] (and optionally [hours]) before the pinned harness clock.
/// Never `DateTime.now()`.
DateTime _before(int days, {int hours = 0}) =>
    kFixedNow.subtract(Duration(days: days, hours: hours));

/// The D3 fixture: 25 HISTORY rows plus one UPCOMING negative control.
///
/// | Axis | What is in here |
/// |---|---|
/// | Master | `master-aaa` (Софія Бондар) and `master-ccc` (Марія Гриценко) |
/// | `providerCanReviewClient` | `arch-review` is `true`; every other row is `false` |
/// | Partition | `COMPLETED`, `NOT_COMPLETED`, `CANCELLED`, `DECLINED`, an elapsed unclosed `CONFIRMED` — and one genuinely UPCOMING row that must NOT come back |
///
/// 25 HISTORY rows is deliberate: the server page size is 20, so page 1
/// exists and the pagination arm has somewhere to page to. A 24-row fixture
/// would make `hasMore` false and that arm silently vacuous.
///
/// `booking-1` is the elapsed unclosed row because the fake registers
/// `PATCH /api/v1/bookings/booking-1/complete` for exactly that id — the
/// established convention whenever a seeded row also needs a WRITE endpoint.
List<Map<String, dynamic>> _archiveFixture(FakeBackend fb) =>
    <Map<String, dynamic>>[
      // NEGATIVE CONTROL. `kFixedNow + 2d`, so under `sort=startsAt,desc` this
      // row sorts FIRST — it would be the top card on the first screenful if
      // the read were not partitioned. That is what makes the `findsNothing`
      // below load-bearing rather than a statement about the fold.
      fb.salonBoardBookingRow(
        id: 'arch-upcoming',
        masterId: 'master-aaa',
        masterFirstName: 'Софія',
        masterLastName: 'Бондар',
        startsAt: kFixedNow.add(const Duration(days: 2)),
      ),
      // The elapsed unclosed CONFIRMED row — D3's sharpest discriminator, and
      // the «Виконано» subject.
      fb.salonBoardBookingRow(
        id: 'booking-1',
        masterId: 'master-aaa',
        masterFirstName: 'Софія',
        masterLastName: 'Бондар',
        startsAt: _before(1),
        status: 'CONFIRMED',
        awaitingClosure: true,
      ),
      // D3 axis 2 — the ONE row the server says the viewer may review.
      fb.salonBoardBookingRow(
        id: 'arch-review',
        masterId: 'master-ccc',
        masterFirstName: 'Марія',
        masterLastName: 'Гриценко',
        startsAt: _before(1, hours: 3),
        status: 'COMPLETED',
        providerCanReviewClient: true,
      ),
      // …and its twin, identical but for the flag.
      fb.salonBoardBookingRow(
        id: 'arch-noreview',
        masterId: 'master-ccc',
        masterFirstName: 'Марія',
        masterLastName: 'Гриценко',
        startsAt: _before(1, hours: 5),
        status: 'COMPLETED',
      ),
      fb.salonBoardBookingRow(
        id: 'arch-cancelled',
        masterId: 'master-aaa',
        masterFirstName: 'Софія',
        masterLastName: 'Бондар',
        startsAt: _before(2),
        status: 'CANCELLED',
      ),
      fb.salonBoardBookingRow(
        id: 'arch-declined',
        masterId: 'master-ccc',
        masterFirstName: 'Марія',
        masterLastName: 'Гриценко',
        startsAt: _before(3),
        status: 'DECLINED',
      ),
      fb.salonBoardBookingRow(
        id: 'arch-noshow',
        masterId: 'master-aaa',
        masterFirstName: 'Софія',
        masterLastName: 'Бондар',
        startsAt: _before(4),
        status: 'NOT_COMPLETED',
      ),
      // Filler, alternating masters, one per day — carries the row count past
      // the 20-row server page so page 1 exists.
      for (int i = 0; i < 19; i++)
        fb.salonBoardBookingRow(
          id: 'arch-fill-$i',
          masterId: i.isEven ? 'master-aaa' : 'master-ccc',
          masterFirstName: i.isEven ? 'Софія' : 'Марія',
          masterLastName: i.isEven ? 'Бондар' : 'Гриценко',
          startsAt: _before(5 + i),
          status: 'COMPLETED',
        ),
    ];

/// Scrolls [row] into the archive list's viewport, then returns it.
Future<Finder> _revealRow(WidgetTester tester, String id) async {
  final Finder row = find.byKey(Key('master-booking-card-$id'));
  if (row.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      row,
      120,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('master-archive-list')),
            matching: find.byType(Scrollable),
          )
          .first,
      maxScrolls: 40,
    );
    await AppHarness.settle(tester);
  }
  return row;
}

/// Cold start → login as [role] → their own salon shell → «Записи» tab → the
/// board, rendered. The only difference between the two admitted roles is
/// which salon id their `roleHomePath` lands them on.
Future<void> _landOnBoard(
  WidgetTester tester,
  FakeBackend fb,
  GoRouter router,
  UserRole role,
  String salonId,
) async {
  await AppHarness.loginAs(tester, fb, role);
  await AppHarness.pumpUntilFound(
    tester,
    find.byType(SalonShellScreen),
    timeout: const Duration(seconds: 20),
  );
  AppHarness.expectLocation(router, RouteNames.salonShell(salonId));

  final Finder bookingsTab = find.byKey(const Key('salon-nav-tile-1'));
  await AppHarness.pumpUntilFound(
    tester,
    bookingsTab.hitTestable(),
    timeout: const Duration(seconds: 20),
  );
  await tester.tap(bookingsTab);
  await AppHarness.settle(tester);
  await AppHarness.pumpUntilFound(
    tester,
    find.byType(SalonBookingsScreen),
    timeout: const Duration(seconds: 20),
  );
}

/// Taps the board header's «Архів» and waits for the archive to render.
Future<void> _openArchive(WidgetTester tester, GoRouter router) async {
  final Finder archiveButton = find.byKey(
    const Key('master-bookings-open-archive'),
  );
  await AppHarness.pumpUntilFound(
    tester,
    archiveButton,
    timeout: const Duration(seconds: 20),
  );
  await AppHarness.tapVisible(tester, archiveButton);
  await AppHarness.settle(tester);
  await AppHarness.pumpUntilFound(
    tester,
    find.byType(MasterArchiveScreen),
    timeout: const Duration(seconds: 20),
  );
  expect(
    AppHarness.location(router),
    equals(RouteNames.salonStaffBookingsArchive),
  );
  // The literal-before-dynamic pin: a location assertion alone passes while
  // `BookingDetailScreen` renders booking `'archive'`.
  expect(find.byType(BookingDetailScreen), findsNothing);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  // ==========================================================================
  // 1 + 2. THE SCOPE AND THE FIXTURE — run for BOTH admitted roles (D4)
  // ==========================================================================
  Future<void> scopeJourney(
    WidgetTester tester, {
    required UserRole role,
    required String salonId,
  }) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()..currentRole = role;
      final GoRouter router = await AppHarness.boot(tester, fb);

      // Seeded AFTER boot: the row instants are derived from `kFixedNow`, but
      // the board's own day list is not, and `AppHarness.boot` is what
      // initialises the timezone database every Kyiv-day derivation needs.
      fb.salonBoardBookings = <Map<String, dynamic>>[];
      fb.salonArchiveBookings = _archiveFixture(fb);

      await _landOnBoard(tester, fb, router, role, salonId);

      // Deltas, never absolutes: login and the board's own render have already
      // driven traffic through these counters' neighbourhoods.
      final int archiveCallsBefore = fb.getSalonArchiveCalls;
      final int meCallsBefore = fb.getMyBookingsCalls;

      await _openArchive(tester, router);

      // ── THE WIRE ────────────────────────────────────────────────────────
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.getSalonArchiveCalls > archiveCallsBefore,
        description: 'the archive to issue its GET /bookings/salon/{id}',
        timeout: const Duration(seconds: 20),
      );
      expect(
        fb.getSalonArchiveCalls - archiveCallsBefore,
        1,
        reason:
            'exactly ONE partition-carrying fetch for the landing — a second '
            'would mean the family key is churning or the screen is '
            'double-mounting',
      );
      final Map<String, dynamic> q = fb.lastSalonArchiveQuery!;
      expect(q['partition'], 'HISTORY');
      expect('${q['page']}', '0');
      expect(
        fb.getMyBookingsCalls,
        meCallsBefore,
        reason:
            'zero GET /bookings/me on this journey — that is the two master '
            'hosts\' scope, and for a salon manager it is a different list',
      );

      // ── THE PARTITION, PROVEN BY THE ROW THAT MUST NOT BE THERE ─────────
      //
      // `arch-upcoming` sorts NEWEST, so if it came back it would be the very
      // first card — built, on screen, unmissable. Its absence is therefore
      // about `partition=HISTORY` and not about the 800×600 fold.
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('master-booking-card-booking-1')),
        timeout: const Duration(seconds: 20),
      );
      expect(
        find.byKey(const Key('master-booking-card-arch-upcoming')),
        findsNothing,
        reason:
            'a CONFIRMED booking that has not elapsed is UPCOMING, not '
            'HISTORY — it would sort first, so this absence is load-bearing',
      );

      // ── D3 AXIS 3 — the elapsed unclosed CONFIRMED row ──────────────────
      expect(
        find.byKey(const Key('master-booking-card-booking-1')),
        findsOneWidget,
        reason:
            'the ONE row a status-only approximation of HISTORY structurally '
            'cannot reach — `_legacyStatusesFor` has no way to express '
            '"CONFIRMED and elapsed"',
      );
      expect(
        find.byKey(const Key('master-booking-card-complete-booking-1')),
        findsOneWidget,
        reason:
            'a salon manager has booking transitions enabled, and the row is '
            'awaitingClosure — so «Виконано» renders',
      );

      // ── D3 AXIS 1 — two masters, attributed DIFFERENTLY ─────────────────
      final Finder attributionA = find.byKey(
        const Key('master-booking-card-master-booking-1'),
      );
      await _revealRow(tester, 'arch-review');
      final Finder attributionC = find.byKey(
        const Key('master-booking-card-master-arch-review'),
      );
      expect(attributionA, findsOneWidget);
      expect(attributionC, findsOneWidget);
      final String? nameA = tester.widget<Text>(attributionA).data;
      final String? nameC = tester.widget<Text>(attributionC).data;
      expect(nameA, isNotNull);
      expect(nameA, isNot(isEmpty));
      expect(nameC, isNot(isEmpty));
      expect(
        nameA,
        isNot(equals(nameC)),
        reason:
            'read off the render — a hardcoded label, a list-wide single name '
            'or an attribution wired to the VIEWER all fail here, and two '
            'findsOneWidget would not',
      );

      // ── D3 AXIS 2 — «Відгук» follows the SERVER FLAG, not the role ──────
      //
      // The two rows below are identical in every respect the UI can see —
      // same master, same status, same Kyiv day, adjacent in the list — and
      // differ only in `providerCanReviewClient`. A role-gated CTA would
      // render on both; a status-gated one would render on both.
      expect(
        find.byKey(const Key('master-booking-card-review-arch-review')),
        findsOneWidget,
      );
      await _revealRow(tester, 'arch-noreview');
      expect(
        find.byKey(const Key('master-booking-card-arch-noreview')),
        findsOneWidget,
        reason: 'positive control — the twin row really did render',
      );
      expect(
        find.byKey(const Key('master-booking-card-review-arch-noreview')),
        findsNothing,
        reason:
            'same master, same COMPLETED status, same viewer — only the '
            'server flag differs, so only the flag can explain the CTA',
      );

      // ── EVERY OTHER PARTITION MEMBER IS GENUINELY SERVED ────────────────
      for (final String id in <String>[
        'arch-cancelled',
        'arch-declined',
        'arch-noshow',
      ]) {
        expect(
          await _revealRow(tester, id),
          findsOneWidget,
          reason:
              'HISTORY is PAST ∪ CANCELLED — $id is exactly what the phase-231 '
              'cutover from PAST exists to surface',
        );
      }

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Phase 345: SALON_OWNER opens «Архів» and gets the SALON\'s whole '
    'history — one partition=HISTORY fetch, zero /bookings/me, two masters '
    'attributed apart, an elapsed unclosed CONFIRMED row present, an '
    'UPCOMING row absent, and «Відгук» following the server flag across two '
    'otherwise identical rows',
    (tester) => scopeJourney(
      tester,
      role: UserRole.salonOwner,
      salonId: FakeBackend.kOwnerSalonId,
    ),
  );

  testWidgets(
    'Phase 345 D4: SALON_ADMIN walks the IDENTICAL arm against their own '
    'salon — the /salon/* gate admits both roles and the archive must not '
    'assume the viewer owns the salon',
    (tester) => scopeJourney(
      tester,
      role: UserRole.salonAdmin,
      salonId: FakeBackend.kAdminSalonId,
    ),
  );

  // ==========================================================================
  // 3. PAGINATION + THE «ВИКОНАНО» WRITE
  // ==========================================================================
  testWidgets(
    'Phase 345: the salon archive pages off the SALON endpoint (page=1, '
    'never /bookings/me) and «Виконано» closes a salon row, which then '
    'leaves the list on a re-read of that same endpoint',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final FakeBackend fb = FakeBackend()..currentRole = UserRole.salonOwner;
        final GoRouter router = await AppHarness.boot(tester, fb);
        fb.salonBoardBookings = <Map<String, dynamic>>[];
        fb.salonArchiveBookings = _archiveFixture(fb);

        await _landOnBoard(
          tester,
          fb,
          router,
          UserRole.salonOwner,
          FakeBackend.kOwnerSalonId,
        );
        final int meCallsBefore = fb.getMyBookingsCalls;
        await _openArchive(tester, router);
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(const Key('master-booking-card-booking-1')),
          timeout: const Duration(seconds: 20),
        );

        // ── THE «ВИКОНАНО» WRITE, FIRST ───────────────────────────────────
        //
        // ORDERING IS DELIBERATE, and was found by running it the other way
        // round: `scrollUntilVisible` only ever drags in ONE direction, so
        // paging to the tail first and then reaching back up for `booking-1`
        // (the NEWEST row, permanently at the top) exhausts `maxScrolls` and
        // dies inside `dragUntilVisible`. The write is done while the row is
        // still on the first screenful; the reload it triggers resets the
        // cursor to page 0, which is exactly the state the pagination half
        // below wants anyway.
        expect(fb.completeBookingCalls, 0);
        expect(
          find.byKey(const Key('master-booking-card-complete-booking-1')),
          findsOneWidget,
        );
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('master-booking-card-complete-booking-1')),
        );
        await AppHarness.settle(tester);
        expect(
          find.byKey(const Key('complete-booking-dialog')),
          findsOneWidget,
          reason: 'the SAME CompleteBookingDialog — no bespoke salon dialog',
        );
        // Captured BEFORE the confirm tap, not after. `AppHarness.settle`
        // returns on "no scheduled frame", and the post-write reload is a
        // SEAMLESS invalidate that paints no spinner — so a baseline taken
        // after the settle can already include the reload it is meant to
        // detect, and the wait below then times out on a delta that has
        // already been spent. (Observed, not theorised: this file failed
        // exactly that way on its first run.)
        final int archiveCallsBeforeReload = fb.getSalonArchiveCalls;
        await tester.tap(find.byKey(const Key('complete-booking-confirm')));
        await AppHarness.settle(tester);

        await AppHarness.pumpUntilCondition(
          tester,
          () =>
              fb.completeBookingCalls == 1 &&
              fb.getSalonArchiveCalls > archiveCallsBeforeReload,
          description:
              'the PATCH to land AND the archive to re-read the SALON '
              'endpoint afterwards',
          timeout: const Duration(seconds: 20),
        );
        expect(fb.lastSalonArchiveQuery!['partition'], 'HISTORY');
        expect(
          fb.getMyBookingsCalls,
          meCallsBefore,
          reason: 'the post-write reload stays on the salon scope too',
        );

        // The row is COMPLETED now, so its «Виконано» slot must be gone —
        // asserted on the SLOT rather than on the row, because the row itself
        // legitimately stays in the unfiltered HISTORY list. That is the
        // strictly stronger check: an assertion that the ROW vanished would
        // also pass if the whole list had gone empty.
        await AppHarness.pumpUntilGone(
          tester,
          find.byKey(const Key('master-booking-card-complete-booking-1')),
          timeout: const Duration(seconds: 20),
        );
        expect(
          find.byKey(const Key('master-booking-card-booking-1')),
          findsOneWidget,
          reason:
              'the row itself STAYS — a COMPLETED booking is still HISTORY; '
              'only its close affordance is gone',
        );
        expect(
          find.byKey(const Key('complete-booking-dialog')),
          findsNothing,
          reason: 'the dialog closed on confirm',
        );

        // ── PAGINATION, SECOND ────────────────────────────────────────────
        //
        // The 25th HISTORY row sits on raw page 1. Reaching it at all requires
        // the tail `loadMore` to have fired AND the fetch to have gone to the
        // salon endpoint — the notifier's `salonId == null` arm would have
        // asked `/bookings/me`, which serves this fixture not at all.
        final int archiveCallsBeforePaging = fb.getSalonArchiveCalls;
        expect(
          await _revealRow(tester, 'arch-fill-18'),
          findsOneWidget,
          reason:
              'the 25th HISTORY row is on the SECOND raw page — it cannot '
              'render without a real page-1 round trip',
        );
        expect(
          fb.getSalonArchiveCalls,
          greaterThan(archiveCallsBeforePaging),
          reason: 'the tail fetch genuinely crossed the HTTP boundary',
        );
        expect(
          '${fb.lastSalonArchiveQuery!['page']}',
          '1',
          reason:
              'stringified — the transport hands `page` back as an int or its '
              'decimal string depending on the DioAdapter path',
        );
        expect(fb.lastSalonArchiveQuery!['partition'], 'HISTORY');
        expect(
          fb.getMyBookingsCalls,
          meCallsBefore,
          reason: 'paging must not fall back to the caller-scoped endpoint',
        );
        expect(tester.takeException(), isNull);
      });
    },
  );

  // ==========================================================================
  // 4. D4 — SALON_MASTER IS DENIED, AND KEEPS ITS OWN ARCHIVE
  // ==========================================================================
  //
  // Note on the "two tiers" this decision names. The UI tier and the route
  // tier do NOT compose independently for this role, and saying so is more
  // honest than manufacturing a second assertion: the salon board itself lives
  // under the same `/salon/*` prefix gate, so a SALON_MASTER cannot reach the
  // screen that carries the «Архів» button at all. The UI-tier denial is
  // therefore SUBSUMED by the route-tier one, and what this arm asserts is the
  // stronger statement — neither the board nor the archive renders — plus the
  // thing a gate-widening would actually break, which is the staff master's
  // own unchanged archive.
  //
  // `test/routing/salon_bookings_route_shadowing_test.dart` already pins the
  // redirect as a PURE FUNCTION over every role. What it cannot pin is that
  // the real router installs that redirect on this route; only this tier runs
  // the real one.
  testWidgets(
    'Phase 345 D4: SALON_MASTER navigating to /salon/bookings/archive is '
    'bounced by the REAL router and never sees the salon board or the '
    'salon-scoped archive — while its OWN /staff/bookings/archive still '
    'renders',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final FakeBackend fb = FakeBackend()
          ..currentRole = UserRole.salonMaster;
        final GoRouter router = await AppHarness.boot(tester, fb);
        fb.salonArchiveBookings = _archiveFixture(fb);

        await AppHarness.loginAs(tester, fb, UserRole.salonMaster);
        await AppHarness.settle(tester);

        final int archiveCallsBefore = fb.getSalonArchiveCalls;

        // `push`, not `go` — `go` excludes `fullPath` from the match, which
        // nav detection depends on (`project_gorouter_imperative_match_
        // fullpath`).
        unawaited(
          router.push<void>(
            RouteNames.salonStaffBookingsArchive,
            extra: FakeBackend.kOwnerSalonId,
          ),
        );
        await AppHarness.settle(tester);

        expect(
          AppHarness.location(router),
          isNot(equals(RouteNames.salonStaffBookingsArchive)),
          reason:
              'the /salon/* prefix gate admits SALON_OWNER and SALON_ADMIN '
              'only — this role has its own archive elsewhere',
        );
        expect(
          find.byType(SalonBookingsScreen),
          findsNothing,
          reason:
              'the board that carries the «Архів» button is behind the SAME '
              'gate, so the UI-tier denial is subsumed by this one',
        );
        expect(
          fb.getSalonArchiveCalls,
          archiveCallsBefore,
          reason:
              'a bounced navigation must not have mounted the screen long '
              'enough to fire a salon-scoped read of another salon\'s history',
        );

        // ── AND THE STAFF MASTER'S OWN ARCHIVE STILL WORKS ────────────────
        //
        // The thing a well-meaning gate widening would break. Seeded through
        // the `/bookings/me` dataset, because `/staff/bookings/archive` is the
        // CALLER-scoped host — `salonId` is null there by construction.
        fb.seedManyBookingsDataset(<Map<String, dynamic>>[
          fb.datasetBookingRow(
            id: 'staff-hist-1',
            status: 'COMPLETED',
            startsAt: _before(2),
          ),
        ]);
        unawaited(router.push<void>(RouteNames.salonMasterBookingsArchive));
        await AppHarness.settle(tester);
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(MasterArchiveScreen),
          timeout: const Duration(seconds: 20),
        );
        expect(
          AppHarness.location(router),
          equals(RouteNames.salonMasterBookingsArchive),
        );
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(const Key('master-booking-card-staff-hist-1')),
          timeout: const Duration(seconds: 20),
        );
        expect(
          find.byKey(const Key('master-booking-card-master-staff-hist-1')),
          findsNothing,
          reason:
              'showMasterAttribution is set on the SALON route and nowhere '
              'else — the staff host must stay at its false default',
        );
        expect(tester.takeException(), isNull);
      });
    },
  );
}
