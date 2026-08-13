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
import 'package:beautica_mobile/l10n/app_localizations.dart';
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

/// Boots the app as an INDEPENDENT_MASTER, seeds the fixture booking's own
/// day as an EXPLICIT_TIMES day, logs in, navigates to «Мої записи», and
/// selects that day. Shared by both `testWidgets` below — [fb]'s
/// `bookingStatus`/`bookingPrice`/`bookingPriceMax` must be set by the caller
/// BEFORE this runs (mirrors the repo-wide pre-boot fixture-mutation
/// convention, e.g. `client_home_hub_flow_test.dart`'s
/// `..bookingStatus = 'COMPLETED'`).
///
/// THREE declared times are seeded, deliberately straddling the fixture
/// booking's own 90-minute span (`FakeBackend.bookingStartsAt` ->
/// `bookingEndsAt`, `+90 min`):
///   * `bookedTime`   — the booking's own Kyiv start; renders its card.
///   * `consumedTime` — start + 1 h, i.e. INSIDE `[start, end)`. Hidden
///     outright when the booking CONSUMES the clock (CONFIRMED/COMPLETED),
///     still free when it does not (CANCELLED/DECLINED/NOT_COMPLETED/
///     UNKNOWN) — see `declared_time_cards.dart`'s "CONSUMED DECLARED TIMES
///     ARE DROPPED" section and `_consumesDeclaredTimes`'s allowlist.
///   * `freeTime`     — start + 2 h, PAST the booking's end, so it is
///     genuinely free under every status.
///
/// Before 2026-08-13 this helper seeded only `bookedTime` and a "free" time
/// at start + 1 h — which the consumed-slot fix then correctly HID, turning
/// this file red. That single-hour offset was never a deliberate choice; the
/// three-time shape above replaces it and makes the membership rule an E2E
/// assertion rather than an accident of the fixture's spacing.
///
/// Returns all three [TimeOfDay]s so the caller can derive each card's key
/// without re-deriving the fixture's own Kyiv time again.
Future<({TimeOfDay bookedTime, TimeOfDay consumedTime, TimeOfDay freeTime})>
_bootToDeclaredTimesDay(WidgetTester tester, FakeBackend fb) async {
  // `_bookingDay` reads `beauticaZone` (via `toBeauticaTime`), only
  // initialised once `AppHarness.boot` has run — so both the seeding below
  // and every later reference must come AFTER boot.
  final GoRouter router = await AppHarness.boot(tester, fb);

  final DateTime bookingDay = _bookingDay(fb);
  final tz.TZDateTime bookingKyiv = toBeauticaTime(
    DateTime.parse(fb.bookingStartsAt),
  );
  final TimeOfDay bookedTime = TimeOfDay(
    hour: bookingKyiv.hour,
    minute: bookingKyiv.minute,
  );
  // +1 h — INSIDE the fixture booking's 90-minute span. +2 h — past its end.
  // The fixture booking (`FakeBackend`'s own doc: ~17:00–18:30 Kyiv in
  // winter, ~18:00–19:30 in summer) leaves comfortable headroom before
  // midnight for both.
  final TimeOfDay consumedTime = TimeOfDay(
    hour: (bookedTime.hour + 1) % 24,
    minute: bookedTime.minute,
  );
  final TimeOfDay freeTime = TimeOfDay(
    hour: (bookedTime.hour + 2) % 24,
    minute: bookedTime.minute,
  );

  fb.seedEffectiveSchedule(<Map<String, dynamic>>[
    _explicitTimesDay(bookingDay, <TimeOfDay>[
      bookedTime,
      consumedTime,
      freeTime,
    ]),
  ]);

  await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

  // ── «Мої записи» (nav tile 1). ─────────────────────────────────────────
  await tester.tap(find.byKey(const Key('master-nav-tile-1')));
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.masterBookings);
  expect(find.byType(MasterBookingsScreen), findsOneWidget);

  await _selectRailDay(tester, bookingDay);

  return (
    bookedTime: bookedTime,
    consumedTime: consumedTime,
    freeTime: freeTime,
  );
}

Key _freeCardKey(TimeOfDay t) => Key(
  'declared-time-card-free-'
  '${t.hour.toString().padLeft(2, '0')}'
  '${t.minute.toString().padLeft(2, '0')}',
);

/// Asserts the free card for [t] renders, scrolling `DeclaredTimeCards`' own
/// `ListView.separated` to it first.
///
/// The scroll is NOT decoration: on the 800×600 E2E surface a third
/// 120dp-floored entry sits below the fold, and a lazy `ListView` has not
/// built it yet — so a bare `findsOneWidget` would fail for a reason that has
/// nothing to do with the membership rule under test. Only ever used for
/// PRESENCE; an ABSENCE assertion (the consumed slot) is deliberately made
/// BEFORE any scroll, on an entry that would sit ABOVE the fold if it
/// existed, so it can never pass merely because the row was unbuilt.
Future<void> _expectFreeCard(
  WidgetTester tester,
  TimeOfDay t,
  String why,
) async {
  await tester.scrollUntilVisible(
    find.byKey(_freeCardKey(t)),
    200,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('declared-time-cards')),
          matching: find.byType(Scrollable),
        )
        .first,
    maxScrolls: 20,
  );
  expect(find.byKey(_freeCardKey(t)), findsOneWidget, reason: why);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'a day whose working hours are EXPLICIT_TIMES renders DeclaredTimeCards '
    '— a booked slot AND a free slot both visible, never the grid, never the '
    'gray state; the booked slot shows the real card\'s status AND price; '
    'and the declared time SWALLOWED by the booking\'s duration is hidden '
    'outright',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      // Defaults: bookingStatus = 'CONFIRMED', bookingPrice = 650,
      // bookingPriceMax = null — asserted explicitly below rather than left
      // implicit, so a future change to FakeBackend's defaults cannot
      // silently defang this test.
      fb.bookingStatus = 'CONFIRMED';
      fb.bookingPrice = 650;

      final ({TimeOfDay bookedTime, TimeOfDay consumedTime, TimeOfDay freeTime})
      times = await _bootToDeclaredTimesDay(tester, fb);

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
      // Key moved to `master-booking-card-booking-1` — the shipped
      // `MasterBookingCard`'s OWN key, not one `declared_time_cards.dart`
      // mints itself; see that file's header "THE SWAP" note.
      final Finder bookedCard = find.byKey(
        const ValueKey<String>('master-booking-card-booking-1'),
      );
      expect(
        bookedCard,
        findsOneWidget,
        reason:
            'the fixture booking must render on the declared time matching '
            'its own Kyiv start',
      );

      // ── THE SWAP's whole point, proven at the E2E tier: the real card's
      // status badge and price are visible on a booked declared-time slot —
      // never asserted here before this QA pass (the widget tier already
      // pins this in isolation; this proves the real HTTP-fed composition
      // renders it too). ───────────────────────────────────────────────
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(MasterBookingsScreen)),
      );
      expect(
        find.descendant(
          of: bookedCard,
          matching: find.text(l10n.bookingStatusConfirmed),
        ),
        findsOneWidget,
        reason: 'a CONFIRMED fixture booking must show its status label',
      );
      expect(
        find.descendant(of: bookedCard, matching: find.text('650 ₴')),
        findsOneWidget,
        reason: 'a CONFIRMED fixture booking must show its price',
      );

      // ── THE CONSUMED SLOT — the user-reported bug, at the E2E tier.
      // `consumedTime` falls strictly inside the fixture booking's
      // `[startsAt, endsAt)`, and the booking is CONFIRMED, so the slot is
      // not bookable and must not offer itself as «Вільно». The backend's
      // own `GET /slots` already omits it; this proves the master's day view
      // agrees, through the REAL HTTP boundary rather than a pumped widget.
      //
      // The isolated mechanism is pinned by `declared_time_cards_test.dart`'s
      // "a declared time CONSUMED by an earlier booking's duration" group
      // (half-open boundary, status allowlist, unsorted input, stray
      // consumer) — mutation-verified there. This assertion is the
      // composition proof: the real `endAt` off the wire reaches the merge.
      // ───────────────────────────────────────────────────────────────────
      expect(
        find.byKey(_freeCardKey(times.consumedTime)),
        findsNothing,
        reason:
            'a declared time swallowed by a CONFIRMED booking\'s duration is '
            'HIDDEN ENTIRELY (locked decision, 2026-08-13) — no card, no '
            'muted state',
      );

      // ── The free slot — the declared time PAST the booking's end. ──────
      await _expectFreeCard(
        tester,
        times.freeTime,
        'this declared time sits past the booking\'s end and has no booking '
        'of its own — it must render as a free card',
      );

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a CANCELLED booking on a declared-times day still renders — with a '
    'DIFFERENT status label than CONFIRMED, and no price — proving the E2E '
    'composition, not just the isolated widget, carries the booking\'s real '
    'status through',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      // Pre-boot fixture mutation — the repo-wide convention (see
      // `_bootToDeclaredTimesDay`'s doc) for seeding a booking that is
      // already in a terminal state when the screen first loads.
      fb.bookingStatus = 'CANCELLED';

      final ({TimeOfDay bookedTime, TimeOfDay consumedTime, TimeOfDay freeTime})
      times = await _bootToDeclaredTimesDay(tester, fb);

      // THE STATUS ALLOWLIST, at the E2E tier — the counterpart to the
      // CONFIRMED test's consumed-slot assertion, on the SAME declared time.
      // A CANCELLED booking releases the master's clock, so the slot inside
      // its span is genuinely bookable again and must still render. The two
      // tests together prove the E2E composition reads the booking's real
      // STATUS into the membership rule, not merely its `endAt`
      // (`_consumesDeclaredTimes`'s allowlist).
      expect(
        find.byKey(_freeCardKey(times.consumedTime)),
        findsOneWidget,
        reason:
            'a CANCELLED booking consumes nothing — the declared time inside '
            'its former span is free again and must render, unlike the '
            'CONFIRMED case one test above',
      );

      final Finder bookedCard = find.byKey(
        const ValueKey<String>('master-booking-card-booking-1'),
      );
      expect(
        bookedCard,
        findsOneWidget,
        reason:
            'a CANCELLED booking is still a real entry on its declared '
            'time — never dropped, never silently re-rendered as free',
      );

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(MasterBookingsScreen)),
      );
      expect(
        find.descendant(
          of: bookedCard,
          matching: find.text(l10n.bookingStatusCancelled),
        ),
        findsOneWidget,
        reason: 'the CANCELLED status must be visible on the real card',
      );
      expect(
        find.descendant(
          of: bookedCard,
          matching: find.text(l10n.bookingStatusConfirmed),
        ),
        findsNothing,
        reason:
            'THE REGRESSION THIS SWAP FIXES: the retired bespoke card never '
            'read Booking.status, so a CANCELLED booking rendered '
            'identically to a CONFIRMED one — this must never be true again',
      );
      expect(
        find.descendant(of: bookedCard, matching: find.textContaining('₴')),
        findsNothing,
        reason: 'a CANCELLED booking owes nothing — no price pill',
      );

      // The THIRD declared time (past the booking's end) is unaffected by
      // `booking-1`'s status either — an ordinary free card. Asserted LAST
      // because [_expectFreeCard] scrolls, which can retire the booked card
      // above it from the lazy list.
      await _expectFreeCard(
        tester,
        times.freeTime,
        'the declared time past the booking\'s end is free under every '
        'status — never swallowed by whatever changed on the booked one',
      );

      expect(tester.takeException(), isNull);
    },
  );
}
