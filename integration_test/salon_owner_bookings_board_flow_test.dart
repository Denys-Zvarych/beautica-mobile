// Phase 21.12 — E2E: the SALON_OWNER's real «Записи» board journey.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ----------------------------------------
// Phase 21.12 replaced a shell PLACEHOLDER with a real screen that owns a new
// wire scope, a new provider seam and a new drill-in. The widget tier
// (`salon_bookings_screen_test.dart`, `salon_bookings_board_test.dart`,
// `salon_day_narrowing_test.dart`, `salon_bookings_route_shadowing_test.dart`)
// each prove one slice against a bespoke `GoRouter` and a hand-built
// container. NONE of that tier drives:
//   • the REAL post-login landing dispatch putting a SALON_OWNER on their own
//     `/salons/{primary}` shell;
//   • the REAL `SalonBottomNav` tile 1, through a REAL tap, mounting the
//     board in shell slot 1;
//   • the REAL `GET /bookings/salon/{salonId}` + `GET /salons/{id}/masters`
//     chain behind `BookingsDiscoveryView` against a real (fake) HTTP
//     backend — including that NOTHING filter-shaped goes on that wire;
//   • the REAL `auth_redirect.dart` gate deciding where a card tap lands.
//
// SEVEN ASSERTIONS HERE ARE IMPLICIT CULL-BAND ASSERTIONS (2026-09-20)
// ---------------------------------------------------------------------
// Seven `find.byKey(ValueKey('timeline-card-<id>'))` lookups below — at lines
// 362, 366, 575, 886, 1131, 1446 and the `_id`-driven loop at 1055 — resolve a
// card WITHOUT first scrolling it into view. `findsOneWidget` on an unscrolled
// key is therefore also a claim that the card is inside
// `bookings_timeline_grid.dart`'s vertical culling band at rest, on the REAL
// board's viewport (174dp on the 800x600 `flutter-tester` surface, because the
// board attaches its controller to the INNER scroller).
//
// That is why this file, and not the widget tier, caught the 2026-09-20
// attempt to narrow the board's vertical slack to 0.25: a 12:00 card on an
// 09:00–20:00 board is planned at 252dp and fell out of the tree on frame 2.
// `salon_bookings_board_test.dart` could not see it — it pumped the grid bare
// on a 536dp viewport, 3.1x the real one. It has since been rewritten onto a
// faithful 174dp harness; keep BOTH, they fail for different reasons.
//
// Practical consequence: DO NOT "fix" a red assertion here by adding a scroll
// before it. The absence of the scroll is the assertion.
//
// THE BUG THIS FLOW WOULD HAVE CAUGHT
// -----------------------------------
// The board shipped pushing `RouteNames.bookingDetail` (`/bookings/:id`).
// `/bookings` is a CLIENT branch prefix, so the REAL redirect bounced the
// owner to `roleHomePath(SALON_OWNER)` — clean out of the salon shell. Every
// widget-tier test passed, because each stubbed `onBookingTap` or registered
// its own router without the gate. Only this tier runs the real one, which is
// exactly why Rule 3b exists.
//
// NO PATROL FLOW: this journey touches no OS permission dialog, no deep link
// / app link, no FCM or local notification, no WebView and no biometric
// prompt. It is a pure screen / route / provider / GET journey, so Step 2.7
// Rule 3b's `integration_test/patrol/` requirement does not apply. Stated
// explicitly (mobile-qa), not omitted.
//
// CLOCK: `AppHarness.boot` pins `clockProvider` to `kFixedNow` for the whole
// tier (`e2e_boot_policy.dart`), and every fixture below is derived from that
// SAME constant. One clock, both halves — the coherence invariant is about
// MIXING a pinned clock with a host-clock fixture, never about pinning.
//
// FINDERS: widget Keys and widget TYPES only — never a Cyrillic UI string
// (`forbid_cyrillic_finder.sh`). The resolved PAGE TYPE is what is asserted
// after the drill-in, not the location string, per this repo's
// literal-before-dynamic go_router shadowing trap.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_archive_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_column_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/timeline_hour_ruler.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_bookings_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations_uk.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// The owner's OWN primary salon — the id `roleHomePath` lands them on, and
/// therefore the id the board mounts for. NOT `salon-xyz`: pointing the flow
/// at the older fixture salon would have exercised a shell the owner never
/// reaches by logging in.
const String _kSalonId = FakeBackend.kOwnerSalonId;

/// 10:00 and 12:30 Kyiv on the board's own day, as the canonical UTC instants
/// a `BookingResponse` carries. Derived from [kFixedNow] through the SAME
/// `kyivToday` the screen's seed query uses, so the fixtures and the fetched
/// day cannot disagree on ANY host timezone (the dev VM is Europe/Kyiv, which
/// masks exactly this class of bug).
DateTime _atKyivHour(int hour, int minute) {
  final DateTime day = kyivToday(() => kFixedNow);
  // Kyiv is UTC+3 in June.
  return DateTime.utc(day.year, day.month, day.day, hour - 3, minute);
}

/// Opens `BookingsFilterSheet` from the board's own toolbar and gates on it.
///
/// `AppHarness.tapVisible`, not a bare `tester.tap`: the funnel sits in the
/// discovery header, which is inside the board's scroll view, and a target
/// that is laid out but not yet hit-testable fails a bare tap with a warning
/// rather than an attributed timeout.
Future<void> _openFilterSheet(WidgetTester tester) async {
  await AppHarness.tapVisible(
    tester,
    find.byKey(const Key('master-bookings-filter-button')),
  );
  await AppHarness.settle(tester);
  expect(
    find.byKey(const Key('master-bookings-filter-sheet')),
    findsOneWidget,
    reason: 'the filter sheet must be open before any row is ticked',
  );
}

/// Scrolls one of the sheet's OWN lazy rows into view, then taps it.
///
/// The «Майстер» rows are the LAST section of the sheet's `ListView` — the
/// four status rows come first, and the board passes `showServiceFilter:
/// false`, so no «Послуга» section sits between them. `-d flutter-tester`'s
/// surface is 800×600 and the sheet is capped at `0.85 × height`, so an
/// eight-master roster puts the tail rows below the fold where they are never
/// BUILT and a bare `find.byKey` resolves to nothing
/// (`project_integration_scroll_filter_into_view`). Same recipe as
/// `master_bookings_flow_test.dart`'s `_applyStatusFilter`.
Future<void> _tickSheetRow(WidgetTester tester, Key rowKey) async {
  final Finder row = find.byKey(rowKey);
  await tester.scrollUntilVisible(
    row,
    80,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('master-bookings-filter-sheet')),
          matching: find.byType(Scrollable),
        )
        .first,
    maxScrolls: 30,
  );
  await tester.tap(row);
  await AppHarness.settle(tester);
}

/// Taps «Застосувати» and waits for the sheet to actually LEAVE the tree.
///
/// Gating on the sheet's disappearance rather than on `settle` alone is what
/// makes every assertion that follows a statement about the BOARD: a modal
/// route that is still animating out would let a stale barrier swallow the
/// very finders the caller is about to run.
Future<void> _applySheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('master-bookings-filter-apply')));
  await AppHarness.settle(tester);
  await AppHarness.pumpUntilGone(
    tester,
    find.byKey(const Key('master-bookings-filter-sheet')),
    timeout: const Duration(seconds: 20),
  );
}

/// The roster ids the board is CURRENTLY drawing a column for, in order.
///
/// Read off the rendered `MasterColumnStrip` rather than reconstructed from
/// the fixture, so a filter that narrowed the columns while leaving the strip
/// alone (or the reverse) cannot pass. The strip is a plain `Row`, never a
/// lazy list, so every chip is BUILT even at 800dp — which is exactly why
/// this is the one finder that can assert an ABSENCE across the whole roster,
/// including the tail masters whose own columns are off-screen.
List<String> _renderedMasterIds(WidgetTester tester) => tester
    .widget<MasterColumnStrip>(find.byType(MasterColumnStrip))
    .entries
    .map((MasterColumnEntry e) => e.masterId)
    .toList(growable: false);

/// Cold start → login as the fixture SALON_OWNER → their own salon shell →
/// bottom-nav tile 1 → the «Записи» board, rendered and fetched.
///
/// The five flows above each inline this preamble; this helper is introduced
/// for the phase-344 arm rather than retrofitted onto them, so no existing
/// flow's observable behaviour is disturbed by a refactor shipped inside a
/// QA pass.
Future<void> _landOnSalonBoard(
  WidgetTester tester,
  FakeBackend fb,
  GoRouter router,
) async {
  await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
  await AppHarness.pumpUntilFound(
    tester,
    find.byType(SalonShellScreen),
    timeout: const Duration(seconds: 20),
  );
  AppHarness.expectLocation(router, RouteNames.salonShell(_kSalonId));

  final Finder bookingsTab = find.byKey(const Key('salon-nav-tile-1'));
  await AppHarness.pumpUntilFound(
    tester,
    bookingsTab.hitTestable(),
    timeout: const Duration(seconds: 20),
  );
  await tester.tap(bookingsTab);
  await tester.pump();

  await AppHarness.pumpUntilFound(
    tester,
    find.byType(SalonBookingsScreen),
    timeout: const Duration(seconds: 20),
  );
  await AppHarness.pumpUntilFound(
    tester,
    find.byType(BookingsTimelineGrid),
    timeout: const Duration(seconds: 20),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'SALON_OWNER logs in, taps «Записи» in their own salon shell, sees the '
    'salon-wide board with one column per roster master, and drills into a '
    'booking WITHOUT being bounced out of the shell',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final FakeBackend fb = FakeBackend()
          ..currentRole = UserRole.salonOwner
          // Phase 320 — this flow drills into `GET /bookings/booking-1` as the
          // OWNER, who is not `booking-1`'s performing master (`master-aaa`).
          // `BookingService#computeProviderCanReviewClient` (backend
          // `a0df4cf`) answers on `isPerformingMasterOfBooking(...)` alone, so
          // the real server returns `false` here; the fake's `true` default
          // models the performing master's view and would misrepresent this
          // session.
          ..bookingProviderCanReviewClient = false;

        final GoRouter router = await AppHarness.boot(tester, fb);

        // Seeded AFTER boot, deliberately: [_atKyivHour] reads
        // `beauticaZone`, which `initBeauticaTimeZones()` only populates as
        // part of app/harness startup. The handler reads this list at REQUEST
        // time (never at registration), and the board does not mount until
        // the tab tap far below, so nothing has been fetched yet.
        //
        // Two DIFFERENT masters on one day — the whole point of a salon-wide
        // board, and the only shape that can tell a real partition apart from
        // a single-column list that happens to render.
        fb.salonBoardBookings = <Map<String, dynamic>>[
          fb.salonBoardBookingRow(
            id: 'booking-1',
            masterId: 'master-aaa',
            masterFirstName: 'Софія',
            masterLastName: 'Бондар',
            startsAt: _atKyivHour(10, 0),
          ),
          fb.salonBoardBookingRow(
            id: 'board-booking-2',
            masterId: 'master-ccc',
            masterFirstName: 'Марія',
            masterLastName: 'Гриценко',
            startsAt: _atKyivHour(12, 30),
          ),
        ];
        await AppHarness.loginAs(tester, fb, UserRole.salonOwner);

        // ── The REAL landing dispatch ──────────────────────────────────────
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(SalonShellScreen),
          timeout: const Duration(seconds: 20),
        );
        AppHarness.expectLocation(router, RouteNames.salonShell(_kSalonId));

        // ── The REAL bottom-nav tap onto slot 1 ────────────────────────────
        final Finder bookingsTab = find.byKey(const Key('salon-nav-tile-1'));
        await AppHarness.pumpUntilFound(
          tester,
          bookingsTab,
          timeout: const Duration(seconds: 20),
        );
        try {
          await tester.ensureVisible(bookingsTab);
        } catch (_) {}
        await AppHarness.pumpUntilFound(
          tester,
          bookingsTab.hitTestable(),
          timeout: const Duration(seconds: 20),
        );
        await tester.tap(bookingsTab);
        await tester.pump();

        await AppHarness.pumpUntilFound(
          tester,
          find.byType(SalonBookingsScreen),
          timeout: const Duration(seconds: 20),
        );
        expect(find.byKey(const Key('salon-bookings-screen')), findsOneWidget);

        // ── The REAL fetch chain ───────────────────────────────────────────
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(BookingsTimelineGrid),
          timeout: const Duration(seconds: 20),
        );

        expect(
          fb.getSalonBookingsCalls,
          greaterThan(0),
          reason: 'the board must fetch GET /bookings/salon/{salonId}',
        );
        // The endpoint takes NO status list and NO service predicate — the
        // narrowing is client-side. Asserted at the ONE tier that can see the
        // real query string Dio produced.
        final Map<String, dynamic> query = fb.lastSalonBookingsQuery!;
        expect(
          query.containsKey('status'),
          isFalse,
          reason:
              'sending a single status would make the truncation boundary '
              'depend on which filter the owner picked — the rejected design '
              'named in bookings_day_notifier.dart',
        );
        expect(query.containsKey('serviceId'), isFalse);
        expect(query['size'].toString(), '100');

        // ── The rail's DOTS come from the SALON endpoint ───────────────────
        //
        // Backend Phase 319. `/bookings/me/booked-days` is the CALLER's days:
        // for this owner it aggregates every salon they own, and for a
        // SALON_ADMIN the backend rejects it outright — neither is THIS
        // board's answer. Asserted at the E2E tier because the distinction is
        // a PATH, which only a real Dio round trip can show.
        expect(
          fb.salonBookedDaysCalls,
          greaterThan(0),
          reason:
              'the salon rail must be fed by '
              'GET /bookings/salon/{salonId}/booked-days',
        );
        expect(
          fb.bookedDaysCalls,
          0,
          reason:
              'and never by the caller-scoped /bookings/me/booked-days, whose '
              'days are not this salon\'s',
        );
        // Filter-independent, exactly like the master rail's: a dot marks
        // where bookings ARE, so nothing filter-shaped may narrow it.
        final Map<String, dynamic> dotsQuery = fb.lastSalonBookedDaysQuery!;
        expect(dotsQuery.containsKey('status'), isFalse);
        expect(dotsQuery.containsKey('serviceId'), isFalse);
        expect(dotsQuery.containsKey('masterId'), isFalse);
        // Both bounds are REQUIRED on this endpoint (unlike the sibling
        // list's optional range) — an unbounded default would scan the
        // salon's entire booking history.
        expect(dotsQuery['from'], isNotNull);
        expect(dotsQuery['to'], isNotNull);

        // ── The board itself: a COLUMN PER MASTER, not one merged list ─────
        expect(find.byType(MasterColumnStrip), findsOneWidget);
        expect(
          find.byKey(
            const ValueKey<String>('salon-bookings-column-chip-master-aaa'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(
            const ValueKey<String>('salon-bookings-column-chip-master-ccc'),
          ),
          findsOneWidget,
        );
        // Both masters' cards, by id — data binding, not a smoke check.
        expect(
          find.byKey(const ValueKey<String>('timeline-card-booking-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('timeline-card-board-booking-2')),
          findsOneWidget,
        );

        // ── THE DRILL-IN ───────────────────────────────────────────────────
        final Finder card = find.byKey(
          const ValueKey<String>('timeline-card-booking-1'),
        );
        try {
          await tester.ensureVisible(card);
        } catch (_) {}
        await AppHarness.pumpUntilFound(
          tester,
          card.hitTestable(),
          timeout: const Duration(seconds: 20),
        );
        await tester.tap(card);
        await tester.pump();

        await AppHarness.pumpUntilFound(
          tester,
          find.byType(BookingDetailScreen),
          timeout: const Duration(seconds: 20),
        );

        // ANTI-VACUITY: "the detail screen rendered" is not enough on its own
        // — the owner must ALSO still be inside their salon shell. The
        // shipped bug rendered no detail screen at all AND left the owner on
        // `roleHomePath`, so both halves are asserted.
        //
        // The board itself stays MOUNTED underneath: the detail is pushed
        // onto the root navigator over the shell, which is the whole point of
        // a pushed leaf (swipe-back returns to the still-scrolled board). So
        // the observable is the LOCATION, not the board's absence.
        expect(find.byType(SalonBookingsScreen), findsOneWidget);
        expect(
          AppHarness.location(router),
          equals(RouteNames.salonStaffBookingDetail('booking-1')),
          reason:
              'RouteNames.bookingDetail (/bookings/:id) is CLIENT-gated — an '
              'owner who lands there is redirected to roleHomePath and leaves '
              'the salon shell entirely',
        );
        expect(
          AppHarness.location(router),
          isNot(equals(RouteNames.bookingDetail('booking-1'))),
        );
      });
    },
  );

  testWidgets(
    'the board renders NO cards and no crash when the salon day is empty — '
    'the roster strip still states WHICH masters are free',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final FakeBackend fb = FakeBackend()
          ..currentRole = UserRole.salonOwner
          ..salonBoardBookings = <Map<String, dynamic>>[];

        final GoRouter router = await AppHarness.boot(tester, fb);
        await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(SalonShellScreen),
          timeout: const Duration(seconds: 20),
        );
        AppHarness.expectLocation(router, RouteNames.salonShell(_kSalonId));

        final Finder bookingsTab = find.byKey(const Key('salon-nav-tile-1'));
        await AppHarness.pumpUntilFound(
          tester,
          bookingsTab.hitTestable(),
          timeout: const Duration(seconds: 20),
        );
        await tester.tap(bookingsTab);
        await tester.pump();

        await AppHarness.pumpUntilFound(
          tester,
          find.byType(MasterColumnStrip),
          timeout: const Duration(seconds: 20),
        );

        // The locked decision: an owner must be able to see WHICH masters are
        // free, so an empty day draws the roster and a ruled, card-less grid
        // rather than an illustration.
        expect(find.byType(MasterBookingCard), findsNothing);
        expect(
          find.byKey(
            const ValueKey<String>('salon-bookings-column-chip-master-aaa'),
          ),
          findsOneWidget,
        );
        expect(find.byType(BookingsTimelineGrid), findsOneWidget);
      });
    },
  );

  // ══════════════════════════════════════════════════════════════════════
  // Phase 335 — the board's timeline spans the ROSTER'S HOURS.
  //
  // WHY THIS BELONGS AT THIS TIER. The widget tier proves the union maths
  // and the screen's own composition against a mocked repository. It cannot
  // prove the PATH: `GET /salons/{salonId}/masters/effective-schedule` is a
  // route that exists only on the wire, and the client reaches it through a
  // repository, a family provider and a month derivation that no widget test
  // exercises end to end. Only a real Dio round trip against the fake
  // backend shows that the request is issued at all, at the right path, with
  // both bounds — and that its answer moves the rendered ruler.
  // ══════════════════════════════════════════════════════════════════════
  testWidgets(
    'the board fetches the salon roster\'s effective schedule and bounds its '
    'timeline by the UNION of every master\'s hours, not by the bookings',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final FakeBackend fb = FakeBackend()
          ..currentRole = UserRole.salonOwner
          ..bookingProviderCanReviewClient = false;

        final GoRouter router = await AppHarness.boot(tester, fb);

        // Seeded AFTER boot, same reason as the first flow: `_atKyivHour` and
        // `kyivToday` both read `beauticaZone`, which only exists once the
        // harness has initialised the timezone database.
        final DateTime boardDay = kyivToday(() => kFixedNow);
        fb.salonBoardBookings = <Map<String, dynamic>>[
          fb.salonBoardBookingRow(
            id: 'board-midday',
            masterId: 'master-aaa',
            masterFirstName: 'Софія',
            masterLastName: 'Бондар',
            startsAt: _atKyivHour(12, 0),
          ),
        ];
        // Two masters, DIFFERENT shifts. Neither master's own window is
        // 09:00–20:00 — that pair exists only as a union, which is what makes
        // the assertion below about the union rather than about whichever
        // entry happens to come first.
        fb.salonRosterEffectiveSchedule = <Map<String, dynamic>>[
          FakeBackend.salonRosterScheduleEntry(
            masterId: 'master-aaa',
            dates: <DateTime>[boardDay],
            intervals: const <(String, String)>[('09:00:00', '18:00:00')],
          ),
          FakeBackend.salonRosterScheduleEntry(
            masterId: 'master-ccc',
            dates: <DateTime>[boardDay],
            intervals: const <(String, String)>[('11:00:00', '20:00:00')],
          ),
        ];

        await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(SalonShellScreen),
          timeout: const Duration(seconds: 20),
        );
        AppHarness.expectLocation(router, RouteNames.salonShell(_kSalonId));

        final Finder bookingsTab = find.byKey(const Key('salon-nav-tile-1'));
        await AppHarness.pumpUntilFound(
          tester,
          bookingsTab.hitTestable(),
          timeout: const Duration(seconds: 20),
        );
        await tester.tap(bookingsTab);
        await tester.pump();

        await AppHarness.pumpUntilFound(
          tester,
          find.byType(BookingsTimelineGrid),
          timeout: const Duration(seconds: 20),
        );

        // The REQUEST happened at all — a silent degradation would leave this
        // at 0 and every rendering assertion below would still be reachable
        // through the booking-derived fallback, so this is checked first.
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(TimelineHourRuler),
          timeout: const Duration(seconds: 20),
        );
        expect(
          fb.getSalonRosterEffectiveScheduleCalls,
          greaterThan(0),
          reason:
              'the board must fetch '
              'GET /salons/{salonId}/masters/effective-schedule',
        );

        // And it moved the RULER. 09:00 comes from one master, 20:00 from the
        // other; the only booking is 12:00–13:00, so the booking-derived
        // window this same fixture would otherwise render is 12:00 → 13:00.
        // Both ends therefore MOVE — neither assertion can pass vacuously.
        final List<String> labels = tester
            .widgetList<Text>(
              find.descendant(
                of: find.byType(TimelineHourRuler),
                matching: find.byType(Text),
              ),
            )
            .map((Text t) => t.data ?? '')
            .toList(growable: false);
        expect(labels.first, '09:00');
        expect(labels.last, '20:00');

        // The booking still renders on the widened grid.
        expect(
          find.byKey(const ValueKey<String>('timeline-card-board-midday')),
          findsOneWidget,
        );
      });
    },
  );

  // ══════════════════════════════════════════════════════════════════════
  // Phase 336 — the DAY-OFF COLUMN, end to end (Step 2.7 Rule 3b, mobile-qa).
  //
  // WHY THIS BELONGS AT THIS TIER, and is not a duplicate of the 16 predicate
  // tests + 7 column tests + 3 goldens already shipped. Every one of those
  // hands `dayOff:` (or an `EffectiveDay` map) STRAIGHT to the thing under
  // test. None of them proves the WIRE → PREDICATE → RENDER chain: that a
  // real `GET /salons/{id}/masters/effective-schedule` response, parsed by the
  // generated client, keyed through `salonEffectiveScheduleProvider`, matched
  // against the day the rail actually selected, reaches
  // `MasterColumnEntry.dayOff` on the right column of the real roster. A
  // single wrong hop anywhere on that chain — a masterId that does not match
  // the roster's, a date parsed off by a timezone, a month window that
  // excludes the selected day — leaves every one of those tiers green and the
  // board silently un-greyed. Only a real Dio round trip can see it.
  //
  // THE ANTI-VACUITY SHAPE. Three columns are asserted, and two of them are
  // EMPTY:
  //   • `master-aaa` — OFF by the response          → wash + «Вихідний»
  //   • `master-ddd` — no entry in the response at all (fail-open unknown 2),
  //     and no bookings                             → no wash + «Вільний день»
  //   • `master-ccc` — working, one card            → no wash, no marker
  // The first two differ ONLY in what the schedule says. `bookings.isEmpty` is
  // identical across them, so a regression that derives the mark from the
  // booking list — the exact bug this phase exists to remove — cannot pass
  // here, and neither can one that greys every column it has no answer for.
  //
  // NO PATROL FLOW, restated for this arm: the day-off state is a render
  // driven by a GET. No OS permission dialog, no deep/app link, no FCM or
  // local notification, no WebView, no biometric. `integration_test/patrol/`
  // does not apply.
  // ══════════════════════════════════════════════════════════════════════
  testWidgets(
    'the board greys the column of a master the roster says is NOT WORKING '
    'the selected day and marks it as a day off, while a working master and '
    'a master the response says nothing about both render ordinary columns',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final AppLocalizationsUk l10n = AppLocalizationsUk();
        final FakeBackend fb = FakeBackend()
          ..currentRole = UserRole.salonOwner
          ..bookingProviderCanReviewClient = false;

        final GoRouter router = await AppHarness.boot(tester, fb);

        // Seeded AFTER boot — `kyivToday` reads `beauticaZone`, which only
        // exists once the harness has initialised the timezone database.
        // Same reason, same shape, as the two flows above.
        final DateTime boardDay = kyivToday(() => kFixedNow);

        // ONE card, on the WORKING master. `master-aaa` (the off one) is left
        // card-less on purpose: its column has to render the marker, and a
        // column that carries a booking deliberately renders none.
        fb.salonBoardBookings = <Map<String, dynamic>>[
          fb.salonBoardBookingRow(
            id: 'board-working-card',
            masterId: 'master-ccc',
            masterFirstName: 'Марія',
            masterLastName: 'Гриценко',
            startsAt: _atKyivHour(12, 0),
          ),
        ];

        // EXACTLY TWO entries for an EIGHT-master roster. That is not a
        // shortcut — it is the third assertion: every other master is an
        // "unknown 2" (present on the roster, absent from the schedule
        // response) and MUST come back un-greyed. A predicate that guessed
        // "off" at an unknown would grey six columns here.
        fb.salonRosterEffectiveSchedule = <Map<String, dynamic>>[
          FakeBackend.salonRosterScheduleEntry(
            masterId: 'master-aaa',
            dates: <DateTime>[boardDay],
            dayOff: true,
          ),
          FakeBackend.salonRosterScheduleEntry(
            masterId: 'master-ccc',
            dates: <DateTime>[boardDay],
            intervals: const <(String, String)>[('09:00:00', '18:00:00')],
          ),
        ];

        await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(SalonShellScreen),
          timeout: const Duration(seconds: 20),
        );
        AppHarness.expectLocation(router, RouteNames.salonShell(_kSalonId));

        final Finder bookingsTab = find.byKey(const Key('salon-nav-tile-1'));
        await AppHarness.pumpUntilFound(
          tester,
          bookingsTab.hitTestable(),
          timeout: const Duration(seconds: 20),
        );
        await tester.tap(bookingsTab);
        await tester.pump();

        await AppHarness.pumpUntilFound(
          tester,
          find.byType(BookingsTimelineGrid),
          timeout: const Duration(seconds: 20),
        );

        // The schedule resolves AFTER the grid's first paint (the board mounts
        // with `_rosterSchedule == null` — unknown 1, nobody greyed — and
        // re-renders when the response lands), so the wait is on the FETCH,
        // never on the wash itself. Waiting on the thing under test would
        // convert a broken feature into a 20-second timeout instead of the
        // one-line expectation failure below.
        await AppHarness.pumpUntilCondition(
          tester,
          () => fb.getSalonRosterEffectiveScheduleCalls > 0,
          description:
              'GET /salons/{salonId}/masters/effective-schedule to be issued',
          timeout: const Duration(seconds: 20),
        );
        // …and one more frame for the provider emission to reach the board.
        await tester.pump();
        await tester.pump();

        // The request went out at all. Checked FIRST: the whole feature
        // degrades silently to "nobody is off" when this fetch does not
        // happen, and a silent degradation would make every render assertion
        // below reachable for the wrong reason.
        expect(
          fb.getSalonRosterEffectiveScheduleCalls,
          greaterThan(0),
          reason:
              'the day-off mark comes off '
              'GET /salons/{salonId}/masters/effective-schedule — the same '
              'response Phase 335 already fetches for the timeline union',
        );

        // The mark is a COLUMN INDEX on screen, and the roster's order is the
        // backend's. Resolved from the rendered strip rather than hard-coded,
        // so a fixture reorder can never quietly re-point these finders at
        // the wrong master. The strip is a plain `Row` (never a lazy list),
        // so all eight chips are BUILT even though flutter-tester is 800dp
        // wide and only the first few are visible.
        final List<MasterColumnEntry> entries = tester
            .widget<MasterColumnStrip>(find.byType(MasterColumnStrip))
            .entries;
        int columnOf(String masterId) {
          final int i = entries.indexWhere(
            (MasterColumnEntry e) => e.masterId == masterId,
          );
          expect(
            i,
            isNonNegative,
            reason: '$masterId must have a column on the salon board',
          );
          return i;
        }

        final int offColumn = columnOf('master-aaa');
        final int workingColumn = columnOf('master-ccc');
        final int unknownColumn = columnOf('master-ddd');

        // ── 1. THE WASH: exactly one column, and it is the off one ─────────
        expect(
          find.byKey(
            ValueKey<String>('timeline-column-day-off-wash-$offColumn'),
          ),
          findsOneWidget,
          reason: 'the master the response marked OVERRIDE_DAY_OFF is greyed',
        );
        for (int i = 0; i < entries.length; i++) {
          if (i == offColumn) continue;
          expect(
            find.byKey(ValueKey<String>('timeline-column-day-off-wash-$i')),
            findsNothing,
            reason:
                'column $i (${entries[i].masterId}) is either working or not '
                'mentioned by the response at all — an unknown must fail OPEN '
                'and render as an ordinary column',
          );
        }

        // ── 2. THE MARKER: two EMPTY columns, two DIFFERENT words ──────────
        // This pair is the load-bearing one. Both columns hold zero bookings,
        // so nothing derived from the booking list can tell them apart; only
        // the schedule response can.
        expect(
          tester
              .widget<Text>(
                find.byKey(
                  ValueKey<String>('timeline-column-marker-$offColumn'),
                ),
              )
              .data,
          l10n.salonBookingsColumnDayOff,
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(
                  ValueKey<String>('timeline-column-marker-$unknownColumn'),
                ),
              )
              .data,
          l10n.salonBookingsColumnFreeDay,
          reason:
              'a master the schedule says nothing about is «working, nothing '
              'booked» — never «off»',
        );
        // …and the two are genuinely different strings, so the pair above
        // cannot both be passing against one shared value.
        expect(
          l10n.salonBookingsColumnDayOff,
          isNot(l10n.salonBookingsColumnFreeDay),
        );

        // ── 3. THE ROSTER CHIP draws NO load readout, in any state ─────────
        // The chip used to echo the column's word («Вихідний» / «вільно») and
        // the booking figure. It no longer draws any of the three — the
        // column marker below it and the chip's Semantics label carry that
        // information now. Asserted per chip, paired with the master's NAME
        // so a chip that lost its whole content cannot pass here.
        for (final String masterId in <String>[
          'master-aaa', // OFF
          'master-ddd', // unknown → working, nothing booked
          'master-ccc', // working, has a card
        ]) {
          final Finder chip = find.byKey(
            ValueKey<String>('salon-bookings-column-chip-$masterId'),
          );
          expect(chip, findsOneWidget);
          for (final String gone in <String>[
            l10n.salonBookingsColumnDayOff,
            l10n.salonBookingsMasterColumnFree,
            l10n.masterBookingsCount(1),
            '1',
          ]) {
            expect(
              find.descendant(of: chip, matching: find.text(gone)),
              findsNothing,
              reason: '$masterId\'s chip must draw no load readout («$gone»)',
            );
          }
          final MasterColumnEntry entry = entries.firstWhere(
            (MasterColumnEntry e) => e.masterId == masterId,
          );
          expect(
            find.descendant(of: chip, matching: find.text(entry.name)),
            findsOneWidget,
            reason: 'the chip still carries the master identity it exists for',
          );
          // mobile-qa STRENGTHENING (2026-09-18) — the name alone is a weak
          // positive control: it is the chip's FIRST `Text`, drawn by a
          // different branch of the widget from the sub-stack the readout was
          // deleted out of. A change that gutted that whole sub-stack (rating
          // readout included) would still leave the name standing and satisfy
          // every `findsNothing` above. So also pin the readout's surviving
          // NEIGHBOUR — the line the removal deliberately promoted to last.
          expect(
            find.descendant(
              of: chip,
              matching: find.byType(MasterRatingReadout),
            ),
            findsOneWidget,
            reason:
                'the rating readout is what the deleted load line sat beside; '
                'if it vanished too, the sub-stack was gutted rather than '
                'trimmed, and the absence assertions above would be vacuous',
          );

          // ── THE LOAD MOVED, IT WAS NOT DELETED ──────────────────────────
          // The whole point of this change is that the figure stops being
          // DRAWN while still being SPOKEN — a screen-reader user has no grid
          // to scan and would otherwise lose it outright. Asserting only the
          // absence would pass identically against a version that dropped the
          // information entirely, so pin the surviving channel here.
          //
          // `Semantics` WRAPS the keyed `GestureDetector`, so it is the chip
          // finder's nearest ancestor of that type.
          final String? spoken = tester
              .widget<Semantics>(
                find.ancestor(of: chip, matching: find.byType(Semantics)).first,
              )
              .properties
              .label;
          final String expectedLoad = entry.dayOff
              ? l10n.salonBookingsColumnDayOff
              : (entry.bookingCount == 0
                    ? l10n.salonBookingsMasterColumnFree
                    : l10n.masterBookingsCount(entry.bookingCount));
          expect(
            spoken,
            contains(expectedLoad),
            reason:
                '$masterId\'s load must still be ANNOUNCED even though it is '
                'no longer drawn',
          );
          expect(
            spoken,
            contains(entry.name),
            reason: 'the label must still identify whose load it is',
          );
        }

        // ── 4. The working master's board is untouched ─────────────────────
        expect(
          find.byKey(
            const ValueKey<String>('timeline-card-board-working-card'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey<String>('timeline-column-marker-$workingColumn')),
          findsNothing,
          reason: 'a column with a card carries no marker at all',
        );
      });
    },
  );

  // ══════════════════════════════════════════════════════════════════════
  // 2026-09-18 — the «Майстер» FILTER, end to end (Step 2.7 Rule 3b, mobile-qa).
  //
  // WHY THIS BELONGS AT THIS TIER, and is not a 18th copy of
  // `test/features/salon/presentation/salon_bookings_master_filter_test.dart`.
  // That file (17 tests) pumps `SalonBookingsScreen` against a hand-built
  // container with the roster, the day and the columns handed straight in. It
  // proves the PARTITION and the column memo. It cannot prove the JOURNEY:
  //   • that the sheet the owner actually reaches from the board's funnel
  //     renders a «Майстер» section AT ALL — the flag, the roster fetch and
  //     the `masterFilterOptions` memo are three separate hops, and any one of
  //     them silently empty renders NO section, which looks identical to "the
  //     feature is off";
  //   • that the ticked ids survive `showModalBottomSheet`'s own route, its
  //     `context.pop` result and `_applyFilters`' resolve-against-offered
  //     filter — a chain no widget test drives;
  //   • that the selection reaches the board WITHOUT touching the wire. This
  //     is the locked design ("client-side"), and the ONLY tier that can see
  //     the real query string Dio produced is this one. A drift to a
  //     server-side `?masterId=` would keep every widget test green and
  //     collapse the board to one column against the real backend.
  //
  // THE ANTI-VACUITY SHAPE. The seed gives THREE masters ONE distinct card
  // each, and the seed's own distinctness is asserted before it is used: a
  // roster where every master held the same content would satisfy every
  // assertion below against a filter that narrowed nothing. Each absence is
  // paired with a positive control — the surviving masters' cards, the hour
  // ruler, the strip itself and the explicit absence of the
  // «salon-bookings-no-masters» empty state — so a change that GUTS the board
  // cannot pass here as "filtered".
  //
  // NO PATROL FLOW, restated for this arm: a bottom sheet, a set of ticks and
  // a re-render. No OS permission dialog, no deep/app link, no FCM or local
  // notification, no WebView, no biometric — nothing needs `$.native.*` or
  // `$.platform.*`. `integration_test/patrol/` does not apply.
  //
  // FINDERS: keys only, plus names resolved from the RENDERED strip entries —
  // never a Cyrillic literal inside `find.text(...)`
  // (`forbid_cyrillic_finder.sh`).
  // ══════════════════════════════════════════════════════════════════════
  testWidgets(
    'the owner narrows the board through the «Майстер» filter section: only '
    'the ticked masters keep a column, the funnel badge lights without the '
    'sheet open, nothing master-shaped reaches the wire, and a reset restores '
    'the full roster',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final FakeBackend fb = FakeBackend()
          ..currentRole = UserRole.salonOwner
          ..bookingProviderCanReviewClient = false;

        final GoRouter router = await AppHarness.boot(tester, fb);

        // ── THE DISCRIMINATING SEED ────────────────────────────────────────
        // Three DIFFERENT masters, one card each, every card its own id.
        // `master-ddd` is the one that gets filtered AWAY, and it is column
        // index 2 of the eight-master roster — inside the built range at
        // 800dp, so its card and its chip are genuinely findable BEFORE the
        // filter and genuinely absent after. An absence asserted against a
        // master whose column was never built would be vacuous.
        //
        // Seeded AFTER boot: `_atKyivHour` reads `beauticaZone`, which only
        // exists once the harness has initialised the timezone database, and
        // the handler reads this list at REQUEST time.
        fb.salonBoardBookings = <Map<String, dynamic>>[
          fb.salonBoardBookingRow(
            id: 'board-filter-aaa',
            masterId: 'master-aaa',
            masterFirstName: 'Софія',
            masterLastName: 'Бондар',
            startsAt: _atKyivHour(10, 0),
          ),
          fb.salonBoardBookingRow(
            id: 'board-filter-ccc',
            masterId: 'master-ccc',
            masterFirstName: 'Марія',
            masterLastName: 'Гриценко',
            startsAt: _atKyivHour(10, 0),
          ),
          fb.salonBoardBookingRow(
            id: 'board-filter-ddd',
            masterId: 'master-ddd',
            masterFirstName: 'Оксана',
            masterLastName: 'Іванова',
            startsAt: _atKyivHour(10, 0),
          ),
        ];
        // THE FIXTURE ACTUALLY DIFFERS — asserted, not assumed. Three
        // distinct masters and three distinct card ids; collapse either and
        // every filter assertion in this flow becomes satisfiable by a no-op.
        expect(
          fb.salonBoardBookings
              .map((Map<String, dynamic> r) => r['masterId'] as String)
              .toSet(),
          <String>{'master-aaa', 'master-ccc', 'master-ddd'},
          reason:
              'the seed must be able to tell masters apart — identical rows '
              'would let a filter that narrows NOTHING pass this flow',
        );
        expect(
          fb.salonBoardBookings
              .map((Map<String, dynamic> r) => r['id'] as String)
              .toSet()
              .length,
          3,
          reason: 'each column must carry its own assertable card id',
        );

        await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(SalonShellScreen),
          timeout: const Duration(seconds: 20),
        );
        AppHarness.expectLocation(router, RouteNames.salonShell(_kSalonId));

        final Finder bookingsTab = find.byKey(const Key('salon-nav-tile-1'));
        await AppHarness.pumpUntilFound(
          tester,
          bookingsTab.hitTestable(),
          timeout: const Duration(seconds: 20),
        );
        await tester.tap(bookingsTab);
        await tester.pump();

        await AppHarness.pumpUntilFound(
          tester,
          find.byType(BookingsTimelineGrid),
          timeout: const Duration(seconds: 20),
        );
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(MasterColumnStrip),
          timeout: const Duration(seconds: 20),
        );

        // ── BEFORE: the WHOLE roster, and all three cards on it ────────────
        final List<String> fullRoster = _renderedMasterIds(tester);
        expect(
          fullRoster,
          containsAll(<String>['master-aaa', 'master-ccc', 'master-ddd']),
        );
        expect(
          fullRoster.length,
          greaterThan(2),
          reason:
              'the unfiltered board must draw MORE than the two masters this '
              'flow is about to tick, or "narrowed" and "unnarrowed" are the '
              'same picture',
        );
        for (final String id in <String>[
          'board-filter-aaa',
          'board-filter-ccc',
          'board-filter-ddd',
        ]) {
          expect(
            find.byKey(ValueKey<String>('timeline-card-$id')),
            findsOneWidget,
            reason: '$id must be on the board BEFORE any filter is applied',
          );
        }
        expect(
          find.byKey(
            const ValueKey<String>('salon-bookings-column-chip-master-ddd'),
          ),
          findsOneWidget,
          reason:
              'the master this flow filters AWAY must have a chip to lose — '
              'its later absence is otherwise unfalsifiable',
        );
        final Finder badge = find.byKey(
          const Key('master-bookings-filter-badge'),
        );
        expect(
          badge,
          findsNothing,
          reason: 'nothing is filtered yet, so the funnel carries no count',
        );

        // ── THE SHEET: a real «Майстер» section, one row per roster master ──
        await _openFilterSheet(tester);
        expect(
          find.byKey(const Key('master-bookings-filter-section-master')),
          findsOneWidget,
          reason:
              'the board sets showMasterFilter: true AND supplies the roster; '
              'either hop empty renders no section at all, which is '
              'indistinguishable from the feature being off',
        );
        // The section's universe is the ROSTER, not the day's bookings: the
        // five masters with nothing booked must still be tickable. Asserted
        // on a master that has NO card anywhere in the seed.
        await _tickSheetRow(
          tester,
          const Key('master-bookings-filter-master-master-eee'),
        );
        // …and untick it again, so the rest of the flow is about the two
        // masters it means to tick. The row responded, which is the point.
        await _tickSheetRow(
          tester,
          const Key('master-bookings-filter-master-master-eee'),
        );

        await _tickSheetRow(
          tester,
          const Key('master-bookings-filter-master-master-aaa'),
        );
        await _tickSheetRow(
          tester,
          const Key('master-bookings-filter-master-master-ccc'),
        );

        // Captured immediately before «Застосувати» — see the wire assertion
        // below.
        final int listCallsBeforeApply = fb.getSalonBookingsCalls;
        await _applySheet(tester);

        // ── AFTER: BOTH DIRECTIONS, off the rendered strip ─────────────────
        // Presence-only would let the filter no-op and still pass, so this is
        // an exact list: the two ticked masters are there, and every one of
        // the other six — `master-ddd` included — is not.
        expect(
          _renderedMasterIds(tester),
          <String>['master-aaa', 'master-ccc'],
          reason:
              'the board must draw a column for the ticked masters and for '
              'NOBODY else',
        );

        // The render-level half of the same claim, on the master whose column
        // was proven built above.
        expect(
          find.byKey(const ValueKey<String>('timeline-card-board-filter-ddd')),
          findsNothing,
          reason: 'a filtered-out master\'s cards leave the board with it',
        );
        expect(
          find.byKey(
            const ValueKey<String>('salon-bookings-column-chip-master-ddd'),
          ),
          findsNothing,
        );

        // ── POSITIVE CONTROLS: the board is NARROWED, not GUTTED ───────────
        // Every assertion above is an absence, and a change that destroyed
        // the board outright would satisfy all of them. These four cannot be
        // satisfied by destruction.
        expect(
          find.byKey(const ValueKey<String>('timeline-card-board-filter-aaa')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('timeline-card-board-filter-ccc')),
          findsOneWidget,
        );
        expect(
          find.byType(TimelineHourRuler),
          findsOneWidget,
          reason: 'the timeline itself still renders',
        );
        expect(
          find.byKey(const Key('salon-bookings-no-masters')),
          findsNothing,
          reason:
              'narrowing to two masters must never fall into the «this salon '
              'has no masters» empty state, which would be flatly false',
        );
        // The surviving chips still carry the identity they exist for,
        // resolved from the rendered entries rather than from a literal.
        final List<MasterColumnEntry> narrowedEntries = tester
            .widget<MasterColumnStrip>(find.byType(MasterColumnStrip))
            .entries;
        for (final MasterColumnEntry e in narrowedEntries) {
          expect(
            find.descendant(
              of: find.byKey(
                ValueKey<String>('salon-bookings-column-chip-${e.masterId}'),
              ),
              matching: find.text(e.name),
            ),
            findsOneWidget,
            reason: '${e.masterId}\'s chip still names its master',
          );
        }

        // ── THE BADGE, WITHOUT REOPENING THE SHEET ─────────────────────────
        // The whole reason the badge exists: a narrowed board must announce
        // that it is narrowed to an owner who is only looking at it.
        expect(
          badge,
          findsOneWidget,
          reason:
              'an active «Майстер» selection must light the funnel badge with '
              'the sheet closed',
        );
        expect(
          tester
              .widget<Text>(
                find.descendant(of: badge, matching: find.byType(Text)),
              )
              .data,
          '1',
          reason:
              'GROUPS, not values — two ticked masters are ONE active filter, '
              'exactly as two ticked statuses are',
        );

        // ── THE WIRE: nothing master-shaped, and no refetch ────────────────
        // The locked design is CLIENT-SIDE. This is the only tier that can
        // see the query string Dio actually produced, and a drift to a
        // server-side `?masterId=` would leave every widget test green while
        // collapsing the real board to a single master's column.
        final Map<String, dynamic> query = fb.lastSalonBookingsQuery!;
        expect(
          query.containsKey('masterId'),
          isFalse,
          reason:
              'SalonDayQuery.masterId stays null — the «Майстер» selection is '
              'client-side and never becomes a query parameter',
        );
        expect(query.containsKey('status'), isFalse);
        expect(
          fb.getSalonBookingsCalls,
          listCallsBeforeApply,
          reason:
              'a filter that only chooses what to PAINT must not re-issue '
              'GET /bookings/salon/{salonId}',
        );
        // The rail's dots are filter-independent for the same reason.
        expect(fb.lastSalonBookedDaysQuery!.containsKey('masterId'), isFalse);

        // ── «Скинути» → the full roster returns ────────────────────────────
        await _openFilterSheet(tester);
        final Finder reset = find.byKey(
          const Key('master-bookings-filter-reset'),
        );
        expect(
          reset,
          findsOneWidget,
          reason:
              'the reset affordance renders only while something is active, '
              'so its presence is itself proof the selection survived the '
              'sheet round trip',
        );
        await tester.tap(reset);
        await AppHarness.settle(tester);
        await _applySheet(tester);

        expect(
          _renderedMasterIds(tester),
          fullRoster,
          reason: 'a reset restores the board to the roster it started from',
        );
        expect(
          find.byKey(const ValueKey<String>('timeline-card-board-filter-ddd')),
          findsOneWidget,
          reason: 'the filtered-out master\'s card comes back with its column',
        );
        expect(
          badge,
          findsNothing,
          reason: 'and the funnel stops claiming a filter is set',
        );
      });
    },
  );

  // ── Step 2.7 Rule 3b — the SALON day-LIST invalidation, END TO END ────────
  //
  // THE BUG THIS FLOW WOULD HAVE CAUGHT (2026-09-19). Teaching
  // `invalidateBookingViewsAfterProviderClose` to drop
  // `salonBookedDaysProvider` refreshed the rail DOT, while the BOARD'S LIST
  // kept serving the closed booking at its old slot: both that helper and its
  // reschedule sibling built only `MasterOwnDayQuery` keys, and this board
  // watches a `SalonDayQuery`. Before that arm existed both halves went stale
  // together; afterwards they disagreed, which is strictly worse.
  //
  // WHY THIS TIER AND NOT ONLY THE WIDGET ONE. `booking_calendar_invalidation
  // _test.dart`'s own salon day-LIST group pins the enumeration mechanism
  // directly (filtered key, wrong salon, wrong day, null salonId, the
  // `isWatched` gate) against a hand-built container. NONE of that tier drives
  // the three things that have to line up for a real owner to see the fix:
  //   • `BookingDetailScreen` being mounted from the SALON route so
  //     `widget.salonId` is non-null at all (it is `null` on every /master/*
  //     and archive mount — one wrong route and the whole arm is inert);
  //   • the board's own live member being a PAUSED, pushed-over consumer
  //     rather than a plain listener — the state in which this helper
  //     deliberately does NOT eagerly re-read, leaving the refetch to land on
  //     RESUME after the pop;
  //   • the day actually matching: the fan-out is scoped to
  //     `kyivDayOf(booking.startAt)`, so the detail's own start instant and
  //     the board's day must agree or the sweep skips this board silently.
  //
  // CLOCK: one clock, both halves — `fb.bookingStartsAt` is set from the SAME
  // `_atKyivHour` the board rows use, which is derived from `kFixedNow`
  // through the same `kyivToday` the screen's seed query uses.
  testWidgets(
    'declining from the board\'s own drill-in takes the card OFF the board '
    'list after the pop — not only off the rail dot set',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final FakeBackend fb = FakeBackend()
          ..currentRole = UserRole.salonOwner
          // Same reasoning as the first flow: the owner is not `booking-1`'s
          // performing master.
          ..bookingProviderCanReviewClient = false;

        final GoRouter router = await AppHarness.boot(tester, fb);

        // 16:00 Kyiv on the board's own day — FUTURE relative to `kFixedNow`
        // (15:00 Kyiv), so the detail footer offers «Відхилити» at all, and on
        // the SAME Kyiv calendar day the board is showing, so
        // `kyivDayOf(booking.startAt)` lands inside the sweep's `affectedDays`.
        // A fixture on any other day would make this test pass for the wrong
        // reason — the sweep would skip the board and the card would linger.
        final DateTime start = _atKyivHour(16, 0);
        fb.bookingStartsAt = start.toIso8601String();
        fb.bookingEndsAt = start
            .add(const Duration(minutes: 60))
            .toIso8601String();

        fb.salonBoardBookings = <Map<String, dynamic>>[
          fb.salonBoardBookingRow(
            id: 'booking-1',
            masterId: 'master-aaa',
            masterFirstName: 'Софія',
            masterLastName: 'Бондар',
            startsAt: start,
          ),
          // A SECOND master's card, deliberately: it is what tells "the
          // declined card left" apart from "the board failed to render", and
          // it must SURVIVE — the sweep drops caches, it does not blank the
          // board.
          fb.salonBoardBookingRow(
            id: 'board-booking-2',
            masterId: 'master-ccc',
            masterFirstName: 'Марія',
            masterLastName: 'Гриценко',
            // 17:30, i.e. AFTER `booking-1` — so `booking-1` sits at the very
            // TOP of the booking-derived timeline window and is built and
            // on-screen at `-d flutter-tester`'s 800×600 surface without any
            // scrolling. (A 12:30 sibling put the 16:00 card five hours down
            // the grid, where it was never built and the finder resolved to
            // nothing — the lazily-inflated-tile trap.)
            startsAt: _atKyivHour(17, 30),
          ),
        ];

        await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(SalonShellScreen),
          timeout: const Duration(seconds: 20),
        );

        final Finder bookingsTab = find.byKey(const Key('salon-nav-tile-1'));
        await AppHarness.pumpUntilFound(
          tester,
          bookingsTab.hitTestable(),
          timeout: const Duration(seconds: 20),
        );
        await tester.tap(bookingsTab);
        await tester.pump();
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(BookingsTimelineGrid),
          timeout: const Duration(seconds: 20),
        );

        final Finder declinedCard = find.byKey(
          const ValueKey<String>('timeline-card-booking-1'),
        );
        expect(
          declinedCard,
          findsOneWidget,
          reason: 'sanity: the board draws the booking BEFORE the decline',
        );
        final int fetchesBefore = fb.getSalonBookingsCalls;

        // ── Drill in ──────────────────────────────────────────────────────
        try {
          await tester.ensureVisible(declinedCard);
        } catch (_) {}
        await AppHarness.pumpUntilFound(
          tester,
          declinedCard.hitTestable(),
          timeout: const Duration(seconds: 20),
        );
        await tester.tap(declinedCard);
        await tester.pump();
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(BookingDetailScreen),
          timeout: const Duration(seconds: 20),
        );
        AppHarness.expectLocation(
          router,
          RouteNames.salonStaffBookingDetail('booking-1'),
        );

        // ── The REAL provider decline ─────────────────────────────────────
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(const Key('booking-detail-decline')),
          timeout: const Duration(seconds: 20),
        );
        await tester.tap(find.byKey(const Key('booking-detail-decline')));
        await AppHarness.settle(tester);
        expect(find.byKey(const Key('decline-booking-dialog')), findsOneWidget);
        await tester.tap(find.byKey(const Key('decline-booking-confirm')));
        await AppHarness.pumpUntilGone(
          tester,
          find.byKey(const Key('decline-booking-dialog')),
          timeout: const Duration(seconds: 20),
        );
        expect(
          fb.declineBookingCalls,
          1,
          reason: 'the per-booking PATCH /bookings/{id}/decline must have run',
        );

        // ── Back to the board ─────────────────────────────────────────────
        router.pop();
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(BookingsTimelineGrid),
          timeout: const Duration(seconds: 20),
        );

        // THE ASSERTION. The board's own live `SalonDayQuery` must have been
        // dropped, so the resumed consumer refetches and the now-DECLINED row
        // is hidden by the day-list default (CANCELLED/DECLINED excluded,
        // locked 2026-08-13). Without the salon day-LIST arm this stays on
        // screen at its old slot until a pull-to-refresh or an LRU eviction.
        await AppHarness.pumpUntilGone(
          tester,
          declinedCard,
          timeout: const Duration(seconds: 20),
        );
        expect(
          fb.getSalonBookingsCalls,
          greaterThan(fetchesBefore),
          reason:
              'the board must have gone back to the wire — a cached list is '
              'exactly the regression',
        );
        expect(
          find.byKey(const ValueKey<String>('timeline-card-board-booking-2')),
          findsOneWidget,
          reason:
              'ANTI-VACUITY: the other master\'s card must still be there. '
              'Otherwise "the declined card is gone" would also be satisfied '
              'by a board that rendered nothing at all.',
        );
        expect(tester.takeException(), isNull);
      });
    },
  );

  // ══════════════════════════════════════════════════════════════════════
  // Phase 344 — the salon «Архів», END TO END (Step 2.7 Rule 3b, mobile-qa).
  //
  // WHY THIS ARM EXISTS, AND WHY IT COULD NOT EXIST BEFORE. Phases 342 and
  // 343 built the archive's salon arm — the scope on the family key, the
  // `GET /bookings/salon/{id}?partition=HISTORY` branch, the per-row master
  // attribution — behind NO ROUTE. Nothing in the app could reach it, so
  // Rule 3b was explicitly waived for both. Phase 344 registers the route
  // and lights the board's header button, which is the first moment a USER
  // JOURNEY exists at all. This is that journey.
  //
  // WHAT ONLY THIS TIER CAN SEE. `salon_bookings_screen_test.dart` proves the
  // board pushes a path with an extra (against a sentinel route);
  // `salon_bookings_route_shadowing_test.dart` proves the production router
  // resolves that path to `MasterArchiveScreen` ahead of the `:bookingId`
  // sibling; `master_archive_screen_test.dart` proves the three parameters
  // change the render (against a MOCKED repository). None of them joins the
  // two halves: that the id the BOARD holds, carried through `extra`, through
  // the real redirect, into the real family key, produces a real
  // `GET /bookings/salon/{id}` — and NOT the `GET /bookings/me` the same
  // screen serves its two master hosts. Only a real Dio round trip can tell
  // those two apart, because the difference is a PATH.
  //
  // THE ANTI-VACUITY SHAPE, stated up front:
  //   • TWO masters' rows. A single-master fixture renders identically
  //     whether the scope is "this salon" or "mine", so it would pass against
  //     a dropped `salonId`. Two DIFFERENT performing masters is the only
  //     shape that distinguishes them, and both names are read off the
  //     rendered `Text` and asserted DIFFERENT.
  //   • The `/bookings/me` call counter is asserted UNCHANGED across the
  //     whole archive visit. Dropping `salonId` swaps the branch inside
  //     `_fetchPage`, and this is the assertion that sees it.
  //   • The «Послуга» facet's absence is asserted with a POSITIVE CONTROL
  //     (the status section) so it cannot pass on an empty sheet — but it is
  //     labelled at its call site as a RENDER check, not as a pin of
  //     `showServiceFilter: false`, because the M14 probe showed it stays
  //     green under that mutation for a reason that has nothing to do with
  //     the flag. See the note there; the flag's real pin is one tier down.
  //
  // NO PATROL FLOW: a header tap, a redirect and two GETs. No OS permission
  // dialog, no deep/app link, no FCM or local notification, no WebView, no
  // biometric. `integration_test/patrol/` does not apply — stated, not
  // omitted.
  // ══════════════════════════════════════════════════════════════════════
  testWidgets(
    'SALON_OWNER opens «Архів» from the board header and lands on the '
    'SALON-scoped archive: rows performed by TWO DIFFERENT masters, each '
    'attributed by name, fetched off GET /bookings/salon/{id} and never off '
    '/bookings/me, with no «Послуга» facet and no read of the owner\'s own '
    'service catalogue',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final FakeBackend fb = FakeBackend()
          ..currentRole = UserRole.salonOwner
          ..bookingProviderCanReviewClient = false;

        final GoRouter router = await AppHarness.boot(tester, fb);

        // Seeded AFTER boot for the same reason every flow above does:
        // `_atKyivHour` reads `beauticaZone`, which only exists once the
        // harness has initialised the timezone database.
        //
        // TWO masters, one Kyiv day. COMPLETED rather than the file's usual
        // CONFIRMED because this is a HISTORY read — a terminal outcome is
        // what the partition actually returns, and it keeps the fixture
        // honest about what an owner would be looking at.
        fb.salonBoardBookings = <Map<String, dynamic>>[
          fb.salonBoardBookingRow(
            // `booking-1` and not a bespoke id: the fake registers
            // `GET /api/v1/bookings/booking-1` for exactly ONE id, and the
            // drill-in at the end of this arm needs a detail response. The
            // second row keeps an id of its own — the two-master assertion
            // is about the PAIR, not about either id.
            id: 'booking-1',
            masterId: 'master-aaa',
            masterFirstName: 'Софія',
            masterLastName: 'Бондар',
            startsAt: _atKyivHour(10, 0),
            status: 'COMPLETED',
          ),
          fb.salonBoardBookingRow(
            id: 'arch-ccc',
            masterId: 'master-ccc',
            masterFirstName: 'Марія',
            masterLastName: 'Гриценко',
            startsAt: _atKyivHour(12, 30),
            status: 'COMPLETED',
          ),
        ];
        // ⚠ ADDED BY PHASE 345 D2, AND THE REASON D2 EXISTS.
        //
        // This arm used to seed ONLY `salonBoardBookings` and still pass,
        // because `GET /bookings/salon/{id}` ignored `partition` outright and
        // handed the board's own day list back for ANY query — so "the archive
        // rendered two attributed masters" was, at this tier, a statement about
        // the board's fixture and not about a HISTORY read at all. Phase 345
        // taught the fake to branch on `partition`, which turned this arm RED
        // on its first run and is exactly the hazard D2 says to check for
        // before trusting a green archive assertion.
        //
        // The same rows, now seeded where the ARCHIVE actually reads them. They
        // are all `COMPLETED`, so they classify as HISTORY under
        // `FakeBackend._partitionOf` against the pinned `serverNow`.
        fb.salonArchiveBookings = List<Map<String, dynamic>>.from(
          fb.salonBoardBookings,
        );

        await _landOnSalonBoard(tester, fb, router);

        // Snapshotted, never assumed to be zero: login + the board's own
        // render have already driven traffic through all three counters'
        // neighbourhoods. Every assertion below is about the DELTA the
        // archive visit itself causes.
        final int salonCallsBefore = fb.getSalonBookingsCalls;
        final int meCallsBefore = fb.getMyBookingsCalls;

        // ── THE BUTTON, AND THE TAP ───────────────────────────────────────
        //
        // The SHARED key — `bookings_discovery_view.dart`'s own. This button
        // did not render on this board at all before phase 344 (the screen
        // passed `onOpenArchive: null`, which the shared widget renders as
        // "no button"), so its presence here is a genuine phase-344
        // observable and not a pre-existing affordance.
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

        // ── THE LANDING ───────────────────────────────────────────────────
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(MasterArchiveScreen),
          timeout: const Duration(seconds: 20),
        );
        expect(find.byKey(const Key('master-archive-screen')), findsOneWidget);
        // The PAGE TYPE above is the load-bearing half (this repo's
        // literal-before-dynamic go_router trap: a location assertion passes
        // while `BookingDetailScreen` renders booking `'archive'`). The
        // location is asserted too, and the shadowed alternative explicitly
        // denied.
        expect(
          AppHarness.location(router),
          equals(RouteNames.salonStaffBookingsArchive),
        );
        expect(find.byType(BookingDetailScreen), findsNothing);

        // ── THE SCOPE, ON THE WIRE ────────────────────────────────────────
        await AppHarness.pumpUntilCondition(
          tester,
          () => fb.getSalonBookingsCalls > salonCallsBefore,
          description: 'the archive to issue its own GET /bookings/salon/{id}',
          timeout: const Duration(seconds: 20),
        );
        final Map<String, dynamic> archiveQuery = fb.lastSalonBookingsQuery!;
        expect(
          archiveQuery['partition'],
          'HISTORY',
          reason:
              'the archive hard-requires partition=HISTORY — only the server '
              'can classify an elapsed CONFIRMED row, and `status` alone '
              'cannot express it',
        );
        // THE salonId PIN. Dropped from the route builder, `_fetchPage` takes
        // its `salonId == null` arm and reads `GET /bookings/me` — the
        // SIGNED-IN OWNER's own history, which is not this salon's.
        expect(
          fb.getMyBookingsCalls,
          meCallsBefore,
          reason:
              'the salon archive must never touch /bookings/me — that is the '
              'two master hosts\' scope, and for an owner it is a different '
              'list entirely',
        );

        // ── TWO MASTERS, NAMED ────────────────────────────────────────────
        //
        // Both rows first: an attribution assertion on a list that rendered
        // only one row would be half a test.
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(const Key('master-booking-card-booking-1')),
          timeout: const Duration(seconds: 20),
        );
        final Finder secondRow = find.byKey(
          const Key('master-booking-card-arch-ccc'),
        );
        // `-d flutter-tester` is 800×600 and the archive is a `ListView`, so
        // the second full-layout card can sit below the fold where it is
        // never BUILT and a bare finder resolves to nothing. Scroll it in
        // first (the repo's lazily-inflated-tile trap).
        if (secondRow.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            secondRow,
            120,
            scrollable: find
                .descendant(
                  of: find.byKey(const Key('master-archive-list')),
                  matching: find.byType(Scrollable),
                )
                .first,
            maxScrolls: 30,
          );
          await AppHarness.settle(tester);
        }
        expect(secondRow, findsOneWidget);

        // `showMasterAttribution: true` is set on THIS route and nowhere else
        // in `lib/` — the two master hosts leave it at its `false` default.
        // So these two finders exist only because the route passes the flag.
        final Finder attributionA = find.byKey(
          const Key('master-booking-card-master-booking-1'),
        );
        final Finder attributionC = find.byKey(
          const Key('master-booking-card-master-arch-ccc'),
        );
        expect(attributionA, findsOneWidget);
        expect(attributionC, findsOneWidget);
        final String? nameA = tester.widget<Text>(attributionA).data;
        final String? nameC = tester.widget<Text>(attributionC).data;
        // DIFFERENT, read off the render. A hardcoded label, a row-wide
        // single name, or an attribution wired to the VIEWER rather than to
        // the performing master all fail here; `findsOneWidget` twice would
        // not.
        expect(nameA, isNotNull);
        expect(nameA, isNot(equals(nameC)));
        expect(nameA, isNot(isEmpty));
        expect(nameC, isNot(isEmpty));

        // ── THE «ПОСЛУГА» FACET IS GONE, AND SO IS ITS FETCH ──────────────
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('master-bookings-filter-button')),
        );
        await AppHarness.settle(tester);
        expect(
          find.byKey(const Key('master-bookings-filter-sheet')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('master-bookings-filter-section-service')),
          findsNothing,
          reason:
              'showServiceFilter: false — an owner has no master catalogue, '
              'and a ticked service would make MasterArchiveQuery.of throw on '
              'a salon scope',
        );
        // POSITIVE CONTROL: the sheet really did render its sections, so the
        // absence above is about «Послуга» and not about an empty sheet.
        expect(
          find.byKey(const Key('master-bookings-filter-status-completed')),
          findsOneWidget,
        );
        // ⚠ MEASURED, NOT ASSUMED (mobile-qa phase 344, M14 probe). The two
        // assertions above are a RENDER check, and they do NOT pin
        // `showServiceFilter: false`. Mutating the route builder to
        // `showServiceFilter: true` leaves this arm GREEN, because a
        // SALON_OWNER's `masterServiceCatalogProvider` never yields a
        // catalogue at all: `serviceRepositoryProvider` is built from
        // `masterProfileProvider`, which an owner has none of, so
        // `_applyFilters`' `ref.read(...).asData?.value ?? const []` is empty
        // on EITHER branch and the sheet omits «Послуга» either way. Probed
        // directly — `fb.getServicesCalls` stayed 0 across the whole visit
        // under BOTH the shipped flag and the mutation, so even a call-count
        // pin cannot see the flag here.
        //
        // The flag IS pinned, and mutation-proven, one tier down where a
        // catalogue can be stubbed:
        // `master_archive_screen_test.dart`'s «FILTER — `showServiceFilter:
        // false` drops the «Послуга» section» case. Do not "strengthen" this
        // arm by adding a counter assertion — it would read as a pin while
        // being unfalsifiable, which is worse than the honest render check
        // above. What this tier genuinely adds is that the sheet an owner
        // actually opens, on the real screen, has no service facet in it.

        // ── THE DRILL-IN STAYS INSIDE `/salon/*` ──────────────────────────
        //
        // `detailRouteBuilder: RouteNames.salonStaffBookingDetail` is the
        // third thing this route passes, and the only one nothing observed
        // before this arm — the phase-344 shadowing suite asserts the other
        // two flags as widget FIELDS and stops there. Left null,
        // `_openDetail` falls back to `RouteNames.masterBookingDetail`
        // (`/master/bookings/:id`), whose INDEPENDENT_MASTER-only gate
        // bounces an owner clean out of the salon shell to `/salons/mine`.
        //
        // Not hypothetical: that is the EXACT bug this flow file was written
        // for in phase 21.12, when the board shipped pushing the
        // CLIENT-gated `/bookings/:id`. Every widget-tier test passed then
        // too, because each registered its own router without the real
        // `auth_redirect.dart` gate. Only this tier runs it.
        //
        // «Застосувати» with nothing ticked is the sheet's only close
        // affordance and leaves the selection untouched, so the list under
        // it is the same one asserted above.
        await _applySheet(tester);

        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('master-booking-card-booking-1')),
        );
        await AppHarness.settle(tester);
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(BookingDetailScreen),
          timeout: const Duration(seconds: 20),
        );
        expect(
          AppHarness.location(router),
          equals(RouteNames.salonStaffBookingDetail('booking-1')),
          reason:
              "the salon archive's rows must drill into the SALON detail "
              'route; the master fallback is gated to INDEPENDENT_MASTER and '
              'ejects an owner from the shell',
        );
        expect(
          AppHarness.location(router),
          isNot(equals(RouteNames.masterBookingDetail('booking-1'))),
        );
        // The archive stays MOUNTED underneath — a push, not a go, so
        // swipe-back returns to the still-scrolled list.
        expect(
          find.byType(MasterArchiveScreen, skipOffstage: false),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    },
  );
}
