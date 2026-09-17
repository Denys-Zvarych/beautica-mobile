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
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_column_strip.dart';
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

        // ── 3. THE ROSTER CHIP agrees with the column beneath it ───────────
        expect(
          find.descendant(
            of: find.byKey(
              const ValueKey<String>('salon-bookings-column-chip-master-aaa'),
            ),
            matching: find.text(l10n.salonBookingsColumnDayOff),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(
              const ValueKey<String>('salon-bookings-column-chip-master-ddd'),
            ),
            matching: find.text(l10n.salonBookingsMasterColumnFree),
          ),
          findsOneWidget,
          reason:
              'the unknown master reads «вільно» on the chip, matching the '
              '«Вільний день» on their column',
        );

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
}
