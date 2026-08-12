// Phase 244 follow-up — E2E: the master «Мої записи» day view for an
// EXPLICIT_TIMES working day renders `DeclaredTimeCards`, not
// `BookingsTimelineGrid` and not the gray "no working hours" state.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — integration-test gate)
// --------------------------------------------------------------
// The widget/unit tier proves the mechanism in isolation:
// `declared_time_cards_test.dart` (the merge + card rendering, against a bare
// pumped widget) and `bookings_discovery_view_declared_times_test.dart` (the
// composition wiring, against a mocked `BookingRepository` and a STATIC
// `EffectiveScheduleNotifier` fake). Neither proves the journey wired
// together against a real HTTP boundary: a master opens «Мої записи» on a day
// whose `GET .../effective-schedule` genuinely returns discrete `times`
// (not `intervals`) — mirroring `master_bookings_working_hours_window_flow_
// test.dart`'s composition proof for the INTERVAL case, one branch over.
//
// Patrol is NOT required — nothing here is a native interaction.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/declared_time_cards.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// The day the fake backend's ONE seeded booking (`fb.bookingStartsAt`) falls
/// on, in Kyiv — mirrors `master_bookings_working_hours_window_flow_test
/// .dart`'s identically-named helper. Anchored to the REAL device clock (see
/// `FakeBackend`'s own `_kFixtureDay` doc), so the rail has to be scrolled
/// to reach it.
DateTime _bookingDay(FakeBackend fb) =>
    dateOnly(toBeauticaTime(DateTime.parse(fb.bookingStartsAt)));

String _wireTime(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}:00';

/// Builds a raw EXPLICIT_TIMES `EffectiveDayResponse` JSON entry — the shape
/// `FakeBackend.seedEffectiveScheduleDay` does NOT cover (it only builds
/// INTERVAL/day-off days). Mirrors that helper's field set exactly, with
/// `times` populated and `intervals` empty instead.
Map<String, dynamic> _explicitTimesDay(DateTime date, List<TimeOfDay> times) =>
    <String, dynamic>{
      'date': toApiDate(date),
      'source': 'OVERRIDE_CUSTOM',
      'intervals': const <dynamic>[],
      'times': times.map(_wireTime).toList(),
      'windowStart': null,
      'windowEnd': null,
    };

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
    'a day whose working hours are EXPLICIT_TIMES renders DeclaredTimeCards '
    '— a booked slot AND a free slot both visible, never the grid, never the '
    'gray state',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;

      // `_bookingDay` reads `beauticaZone` (via `toBeauticaTime`), only
      // initialised once `AppHarness.boot` has run — so both the seeding
      // below and every later reference must come AFTER boot.
      final GoRouter router = await AppHarness.boot(tester, fb);

      final DateTime bookingDay = _bookingDay(fb);
      final tz.TZDateTime bookingKyiv = toBeauticaTime(
        DateTime.parse(fb.bookingStartsAt),
      );
      final TimeOfDay bookedTime = TimeOfDay(
        hour: bookingKyiv.hour,
        minute: bookingKyiv.minute,
      );
      // A second declared time, one hour after the booked one — the fixture
      // booking (`FakeBackend`'s own doc: ~17:00–19:30 Kyiv in winter,
      // ~18:00–19:30 in summer) leaves comfortable headroom before midnight.
      final TimeOfDay freeTime = TimeOfDay(
        hour: (bookedTime.hour + 1) % 24,
        minute: bookedTime.minute,
      );

      fb.seedEffectiveSchedule(<Map<String, dynamic>>[
        _explicitTimesDay(bookingDay, <TimeOfDay>[bookedTime, freeTime]),
      ]);

      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      // ── «Мої записи» (nav tile 1). ─────────────────────────────────────
      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.masterBookings);
      expect(find.byType(MasterBookingsScreen), findsOneWidget);

      await _selectRailDay(tester, bookingDay);

      // ── The gray state and the grid must both be absent. ───────────────
      expect(
        find.byKey(const Key('master-bookings-no-schedule')),
        findsNothing,
        reason:
            'this day has seeded EXPLICIT_TIMES hours — the gray state must '
            'not appear',
      );
      expect(
        find.byType(BookingsTimelineGrid),
        findsNothing,
        reason: 'an EXPLICIT_TIMES day must never render the hour-ruler grid',
      );
      expect(find.byType(DeclaredTimeCards), findsOneWidget);

      // ── The booked slot — the fixture booking, reachable on its card. ──
      expect(
        find.byKey(const ValueKey<String>('declared-time-card-booking-1')),
        findsOneWidget,
        reason:
            'the fixture booking must render on the declared time matching '
            'its own Kyiv start',
      );

      // ── The free slot — the second declared time, with nothing booked. ─
      final Key freeKey = Key(
        'declared-time-card-free-'
        '${freeTime.hour.toString().padLeft(2, '0')}'
        '${freeTime.minute.toString().padLeft(2, '0')}',
      );
      expect(
        find.byKey(freeKey),
        findsOneWidget,
        reason:
            'the second declared time has no booking — it must render '
            'as a free card',
      );

      expect(tester.takeException(), isNull);
    },
  );
}
