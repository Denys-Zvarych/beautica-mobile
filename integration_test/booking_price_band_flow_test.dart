// E2E — the FROZEN RANGE PRICE BAND, end to end through the HTTP boundary.
//
// WHY THIS FLOW EXISTS (Step 2.7 Rule 3b)
// --------------------------------------
// The band change is not a widget tweak: it spans the API contract
// (`priceMaxAtBooking` on both booking DTOs), the mapper
// (`booking_mapper.dart` — the ONE place a null ceiling keeps its meaning),
// the domain (`Booking.priceMax` → `BookingDisplayX.priceLabel`) and three
// render surfaces (client list card, master timeline card, «Деталі запису»
// recap + its add-to-calendar export). Every one of those layers has unit or
// widget coverage against a MOCKED repository or a hand-built `Booking` —
// which means every one of them is proven against a domain object some test
// constructed, never against a JSON payload.
//
// That leaves the exact seam this change introduced untested: does a wire
// `priceMaxAtBooking` actually survive `jsonDecode` → generated
// `BookingResponse` → `BookingMapper.fromDto` → `Booking.priceMax` →
// `priceLabel` → pixels? A mapper unit test answers half of it (it hands the
// mapper a DTO it built itself, skipping deserialization); a widget test
// answers the other half from a `Booking` it built itself. Nothing joined
// them. Concretely: before this flow, `FakeBackend` emitted no
// `priceMaxAtBooking` key AT ALL, so the entire integration suite modelled
// every booking as single-priced and could not have noticed the field being
// dropped from the client anywhere along that chain.
//
// WHAT IS REAL HERE AND WHAT IS FAKED
// -----------------------------------
// Faked: the network transport only (`FakeBackend`'s `DioAdapter`) and the
// `add_2_calendar` platform channel. REAL: the generated `beautica_api`
// deserializer, the repository, `BookingMapper`, every provider, the router,
// and all three widgets. So this is the deserialization + mapping + render
// chain under test, driven by the same JSON shape the backend emits.
//
// THE THREE CASES
// ---------------
//   1. CLIENT — a RANGE booking surfaces «300–500 ₴» on the list card, on the
//      detail recap, AND in the string that LEAVES the app via the OS calendar.
//   2. MASTER — the same wire row renders the band on the timeline card, which
//      is a different widget on a different route behind a different role gate.
//   3. NULL IS NOT MISSING — an explicit `"priceMaxAtBooking": null` on the
//      wire renders the floor ALONE. This is the case a "fix" would most
//      plausibly break (by treating null as an error and rendering «—», or by
//      re-deriving a band from the live catalogue), and it is the majority of
//      real bookings.
//
// FINDERS: keys first (`price-<id>`, `master-booking-card-<id>`); the band
// itself is asserted as a rendered figure — ASCII digits + «₴», locale-
// invariant data with no Cyrillic, so `scripts/forbid_cyrillic_finder.sh` is
// satisfied on its own terms.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/my_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
// `FakeBackend` is re-exported by `app_harness.dart` — importing it again is
// flagged as unnecessary by the analyzer's `--fatal-infos` gate.
import 'support/app_harness.dart';

// The add_2_calendar plugin's platform boundary — intercepted so the export
// assertion never opens a real OS calendar sheet.
const MethodChannel _kCalendarChannel = MethodChannel('add_2_calendar');

// The band this flow seeds on the wire, and the exact string it must become.
const num _kFloor = 300;
const num _kCeiling = 500;
const String _kBand = '300–500 ₴';
const String _kFloorAlone = '300 ₴';

/// Scrolls the timeline grid VERTICALLY until [card] is built — mirrors
/// `master_bookings_flow_test.dart`'s identically-named helper. The
/// published working-hours window (seeded below) anchors the grid's top to
/// 09:00, so the default `booking-1` fixture (18:00 Kyiv) sits well below
/// the initial vertical-culling band and is not built until scrolled to.
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

/// Scrolls the day rail until [day]'s chip is built, taps it, and waits out
/// the screen's 220 ms day-tap debounce — mirrors
/// `master_bookings_flow_test.dart`'s identically-named helper.
Future<void> _selectRailDay(WidgetTester tester, DateTime day) async {
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
    'CLIENT — a RANGE booking off the wire renders its frozen band on the '
    'list card, on «Деталі запису», and in the calendar event it exports',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        // The whole point: a wire payload whose `priceMaxAtBooking` is a real
        // ceiling. Nothing downstream is told about it — the band has to be
        // derived from JSON by the production chain.
        ..bookingPrice = _kFloor
        ..bookingPriceMax = _kCeiling;
      final GoRouter router = await AppHarness.boot(tester, fb);

      expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);
      await AppHarness.loginAs(tester, fb, UserRole.client);

      // ── 1. The Записи branch — served by the real GET /bookings/me. ───────
      await tester.tap(find.byKey(const Key('client-nav-tile-3')));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.clientBookings);
      expect(find.byType(MyBookingsScreen), findsOneWidget);
      expect(
        fb.getMyBookingsCalls,
        greaterThan(0),
        reason: 'the list must come from the endpoint, not a seeded provider',
      );

      // ── 2. The list card carries the BAND, not the floor. ─────────────────
      final Finder listPrice = find.byKey(
        const ValueKey<String>('price-booking-1'),
      );
      expect(
        listPrice,
        findsOneWidget,
        reason: 'a CONFIRMED booking must render its keyed price anchor',
      );
      expect(
        (tester.widget(listPrice) as Text).data,
        _kBand,
        reason:
            'priceMaxAtBooking must survive deserialization → BookingMapper → '
            'Booking.priceMax → priceLabel; the floor alone is the bug',
      );

      // ── 3. «Деталі запису» — a SECOND fetch (GET /bookings/booking-1), a
      //      different DTO (BookingDetailResponse) and a different widget. ──
      await tester.tap(find.byType(BookingCard));
      await AppHarness.settle(tester);
      // NAVIGATION IS ASSERTED BY SCREEN, NOT BY ROUTE STRING — deliberately.
      // «Деталі запису» is pushed with `context.push` from INSIDE the client
      // `StatefulShellRoute` branch, so the push lands on the branch's own
      // nested Navigator: `currentConfiguration.matches` still holds exactly
      // one entry whose `matchedLocation` is the branch root «/bookings», and
      // `.uri` reports the same. Neither `AppHarness.location` nor
      // `salon_booking_flow_test.dart`'s `matches.last.matchedLocation` reader
      // can see through that (verified — both report «/bookings» while the
      // detail screen is genuinely mounted). Asserting either would encode a
      // false expectation; the mounted screen is the fact this flow needs.
      // (`client_my_bookings_cancel_flow_test.dart` had encoded exactly that
      // false expectation and now asserts the screen here too — this is the
      // shared precedent for the push-into-a-shell-branch case, not a
      // one-off.)
      expect(find.byType(BookingDetailScreen), findsOneWidget);
      expect(
        find.text(_kBand),
        findsWidgets,
        reason:
            'the detail recap reads the SAME priceLabel — the band must not '
            'be a list-only decoration',
      );
      expect(
        find.text(_kFloorAlone),
        findsNothing,
        reason: 'the floor must never stand alone on a banded booking',
      );

      // ── 4. EGRESS — the one money string that leaves the app. ─────────────
      // It is written into the device calendar by `add_2_calendar`, i.e. into
      // another vendor's store where the app can never correct it. Intercept
      // the channel and read the description the production call site built.
      final List<MethodCall> calendarCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_kCalendarChannel, (MethodCall call) async {
            calendarCalls.add(call);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_kCalendarChannel, null),
      );

      final Finder calendarButton = find.byKey(
        const Key('booking-detail-add-calendar'),
      );
      expect(calendarButton, findsOneWidget);
      await tester.ensureVisible(calendarButton);
      await AppHarness.settle(tester);
      await tester.tap(calendarButton);
      await AppHarness.settle(tester);

      expect(calendarCalls, hasLength(1));
      final Map<Object?, Object?> args =
          calendarCalls.single.arguments as Map<Object?, Object?>;
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(BookingDetailScreen)),
      );
      final String priceLine = (args['desc'] as String)
          .split('\n')
          .firstWhere(
            (String line) => line.startsWith(l10n.bookingCalendarNotePrice),
            orElse: () => '',
          );
      expect(
        priceLine,
        '${l10n.bookingCalendarNotePrice} $_kBand',
        reason:
            'the exported calendar entry must state the agreed band; a floor '
            'written into a third-party calendar cannot be corrected later',
      );
    },
  );

  testWidgets(
    'INDEPENDENT_MASTER — the same wire row renders the band on the timeline '
    'card (a different widget, route and role gate)',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.independentMaster
        ..bookingPrice = _kFloor
        ..bookingPriceMax = _kCeiling;
      final GoRouter router = await AppHarness.boot(tester, fb);

      // Phase 244 fixture gap: `FakeBackend`'s `/effective-schedule` route
      // defaults to empty (every date resolves to NO_SCHEDULE — see
      // `seedEffectiveSchedule`'s own doc), which now gates the master
      // timeline behind published working hours. Seed `booking-1`'s OWN day
      // (`fb.bookingStartsAt`'s date) — NOT the landing day (Kyiv "today"
      // under the injected clock): `booking-1` is anchored to the REAL
      // device clock + 7 days, deliberately unrelated to the injected
      // clock's "today", so the landing render can never contain it
      // regardless of what hours are published there (Phase 244's
      // window-based filter measures a booking's start in minutes since the
      // VIEWED day's own midnight, and a booking dated on a different
      // calendar day lands far outside any window). The rail is narrowed to
      // `booking-1`'s real day below, mirroring
      // `master_bookings_flow_test.dart`'s pattern. 09:00–21:00 comfortably
      // contains the default `booking-1` fixture (18:00 Kyiv; see
      // `FakeBackend._kFixtureDay`), and deliberately not 18:00 itself,
      // which `ScheduleTimelineWindow.includesStart`'s strict upper bound
      // would exclude.
      final DateTime bookedDay = parseApiDate(
        fb.bookingStartsAt.substring(0, 10),
      );
      fb.seedEffectiveSchedule(<Map<String, dynamic>>[
        FakeBackend.seedEffectiveScheduleDay(
          bookedDay,
          intervals: const <(String, String)>[('09:00:00', '21:00:00')],
        ),
      ]);

      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      expect(AppHarness.location(router), startsWith(RouteNames.masterProfile));

      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);
      expect(
        AppHarness.location(router),
        startsWith(RouteNames.masterBookings),
      );
      expect(find.byType(MasterBookingsScreen), findsOneWidget);

      // Narrow to `booking-1`'s own day — see the seeding note above.
      await _selectRailDay(tester, bookedDay);

      // The published window anchors the grid's top to 09:00, so
      // `booking-1` (18:00 Kyiv) sits well below the initial
      // vertical-culling band — scroll to it before asserting on it.
      await _scrollTimelineTo(
        tester,
        find.byKey(const Key('master-booking-card-booking-1')),
      );

      // The card is on screen, served by the real endpoint…
      expect(
        find.byKey(const Key('master-booking-card-booking-1')),
        findsOneWidget,
      );
      // …and its price pill reads the band. The pill is private and unkeyed,
      // so it is located by the rendered figure — scoped to this card so it
      // cannot match a stray price elsewhere on the timeline.
      expect(
        find.descendant(
          of: find.byKey(const Key('master-booking-card-booking-1')),
          matching: find.text(_kBand),
        ),
        findsOneWidget,
        reason:
            'the provider surface reads the same frozen pair the client does '
            '— a master quoting only the floor would under-state the job',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('master-booking-card-booking-1')),
          matching: find.text(_kFloorAlone),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'CLIENT — an explicit `priceMaxAtBooking: null` on the wire renders the '
    'floor ALONE: null is a single price, not a missing value',
    (tester) async {
      // The default seed: `priceAtBooking` 650, `priceMaxAtBooking` present on
      // the wire and explicitly null. This is the MAJORITY case in production,
      // and the one a well-meaning "handle the new field" change is most
      // likely to break — by rendering the unavailable «—», by falling back to
      // 0, or by re-deriving a band from the live catalogue (which the client
      // must never do: that describes the service TODAY, not what was agreed).
      final fb = FakeBackend()..currentRole = UserRole.client;
      expect(
        fb.bookingPriceMax,
        isNull,
        reason: 'this case must be driven by a genuinely null ceiling',
      );
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.tap(find.byKey(const Key('client-nav-tile-3')));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.clientBookings);

      final Finder listPrice = find.byKey(
        const ValueKey<String>('price-booking-1'),
      );
      expect(listPrice, findsOneWidget);
      expect(
        (tester.widget(listPrice) as Text).data,
        '650 ₴',
        reason:
            'a null ceiling means "one price" — render the floor, with the '
            'currency suffix and no separator',
      );
      // Not the unavailable placeholder, and not a degenerate band.
      expect(find.text('—'), findsNothing);
      expect(find.text('650–650 ₴'), findsNothing);
    },
  );
}
