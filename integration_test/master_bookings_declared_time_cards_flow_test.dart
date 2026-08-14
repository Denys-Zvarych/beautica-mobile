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
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_filter_sheet.dart';
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
import 'support/pager_drag.dart';

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

/// Pages the rail forward one WHOLE week — deterministically.
///
/// Delegates to [dragPagerByOnePage] (`support/pager_drag.dart`), which
/// documents the full "why not `fling`" write-up and the steps=4 regression
/// this call site used to carry (mobile-debugger, 2026-08-14: with 4 samples
/// `PageController.page` froze mid-drag and never crossed the page boundary).
Future<void> _pageRailForward(WidgetTester tester) => dragPagerByOnePage(
  tester,
  const Key('master-bookings-day-rail'),
  forward: true,
);

/// Pages the rail forward until [day]'s chip is on screen, then taps it —
/// mirrors `master_bookings_working_hours_window_flow_test.dart`'s
/// identically-named helper.
///
/// The rail is a `PageView.builder` of Monday-first WEEK pages (see
/// `bookings_day_rail.dart`'s "A WEEK PAGER, not a continuous strip"), which
/// only builds the current page (plus whatever its cache extent reaches).
/// `tester.scrollUntilVisible` — the previous implementation here — drives
/// the scrollable with plain pixel-offset drags, which is the wrong
/// primitive for a snapping pager: it can find [day]'s chip because a
/// neighbour page got lazily built into the cache extent, WITHOUT the pager
/// ever actually landing on that page, so the follow-up tap lands on a
/// render object whose global offset sits outside the live viewport
/// entirely (an off-viewport `Offset` regardless of the surface's own
/// size — this is not a viewport-size artifact, see the fix's own commit
/// message). Real page turns only.
Future<void> _selectRailDay(WidgetTester tester, DateTime day) async {
  final Finder chip = find.byKey(dayChipKey(day));
  for (int i = 0; i < 60 && chip.evaluate().isEmpty; i++) {
    await _pageRailForward(tester);
  }
  expect(
    chip,
    findsOneWidget,
    reason:
        'the rail never paged forward to $day in 60 whole-week turns. If this '
        'is a fresh failure, check the two clocks first: the rail opens on '
        'the INJECTED kFixedNow week.',
  );
  await tester.tap(chip);
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
///     ARE DROPPED" section and `consumesDeclaredTimes`'s allowlist.
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

/// Opens the «Мої записи» filter sheet, toggles every row in [groups], and
/// applies — mirrors `master_bookings_flow_test.dart`'s identically-named
/// helper (kept local rather than shared: `integration_test/` files have no
/// common non-`support/` library, and `support/app_harness.dart` is the
/// harness, not a per-screen driver).
///
/// Needed by any flow asserting on a CANCELLED or DECLINED card: locked
/// product decision 2026-08-13 hides both from the provider's day list —
/// EXPLICIT_TIMES days included, since the exclusion lives on the shared
/// `BookingsDiscoveryView` query and not in either render branch — until the
/// master ticks «Скасовані».
Future<void> _applyStatusFilter(
  WidgetTester tester,
  List<BookingStatusFilterGroup> groups,
) async {
  await tester.tap(find.byKey(const Key('master-bookings-filter-button')));
  await AppHarness.settle(tester);
  expect(
    find.byKey(const Key('master-bookings-filter-sheet')),
    findsOneWidget,
    reason: 'the filter sheet must have opened before any row is ticked',
  );

  for (final BookingStatusFilterGroup group in groups) {
    final Finder row = find.byKey(
      Key('master-bookings-filter-status-${group.name}'),
    );
    await tester.scrollUntilVisible(
      row,
      80,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('master-bookings-filter-sheet')),
            matching: find.byType(Scrollable),
          )
          .first,
      maxScrolls: 20,
    );
    await tester.tap(row);
    await AppHarness.settle(tester);
  }

  await tester.tap(find.byKey(const Key('master-bookings-filter-apply')));
  await AppHarness.settle(tester);
}

Key _freeCardKey(TimeOfDay t) => Key(
  'declared-time-card-free-'
  '${t.hour.toString().padLeft(2, '0')}'
  '${t.minute.toString().padLeft(2, '0')}',
);

/// Scrolls `DeclaredTimeCards`' own `ListView.separated` until [target] is
/// on screen.
///
/// NOT decoration: on the 800×600 E2E surface a third 120dp-floored entry
/// sits below the fold, and a lazy `ListView` has not built it yet — so a
/// bare `findsOneWidget` would fail for a reason that has nothing to do with
/// the rule under test. Only ever used before a PRESENCE assertion; every
/// ABSENCE assertion below is deliberately made BEFORE any scroll, on an
/// entry that would sit ABOVE the fold if it existed, so it can never pass
/// merely because the row was unbuilt.
Future<void> _scrollCardsTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('declared-time-cards')),
          matching: find.byType(Scrollable),
        )
        .first,
    maxScrolls: 20,
  );
}

/// Asserts the free card for [t] renders, scrolling to it first — see
/// [_scrollCardsTo].
Future<void> _expectFreeCard(
  WidgetTester tester,
  TimeOfDay t,
  String why,
) async {
  await _scrollCardsTo(tester, find.byKey(_freeCardKey(t)));
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

  // CANCELLED is NOT incidental here — several assertions below are claims
  // about that specific status: `consumesDeclaredTimes` returns `false` for
  // it (so the slot inside its former span is free again, unlike the
  // CONFIRMED case one test above), `BookingDisplayX.showsPrice` returns
  // `false` for it because the appointment did not happen and no sum is owed,
  // and the label must read «Скасовано». NOT_COMPLETED happens to share both
  // booleans, but for a different documented reason ("genuinely ambiguous
  // whether the provider charges"), so swapping the fixture to it would
  // quietly re-point this test at a claim it does not make.
  //
  // ── REWRITTEN 2026-08-13 (the false-«Вільно» fix) ─────────────────────────
  // This case used to assert, after ticking «Скасовані», that the two other
  // declared times still rendered as FREE cards — i.e. it BLESSED the bug: it
  // asserted that a list narrowed to `{CANCELLED, DECLINED}` on the wire may
  // still claim a declared time is «Вільно». It walked within one row of the
  // real defect and passed only because its fixture held a single CANCELLED
  // booking, the one status where a free card genuinely IS right.
  //
  // The fixture now carries a SECOND, CONFIRMED booking on the third declared
  // time (via `seedManyBookingsDataset`, which filters by the real `status`
  // query param instead of the single-booking route's hand-picked bucket), so
  // the «Скасовані» view is genuinely blind to an occupied slot — exactly the
  // reported bug — and the flow ends by ticking EVERY group, which resolves
  // to the empty (unfiltered) wire set and brings the free cards back. That
  // last phase is both the negative control for suppression and where the
  // status-allowlist claim now lives, with the cancelled booking actually ON
  // the wire while its former span reads free.
  testWidgets(
    'a CANCELLED booking on a declared-times day is hidden by default; once '
    '«Скасовані» is ticked it renders with its own status label and no '
    'price, and NO declared time claims to be «Вільно» while the filter '
    'hides an occupying CONFIRMED booking; ticking every group restores both',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      // Pre-boot fixture mutation — the repo-wide convention (see
      // `_bootToDeclaredTimesDay`'s doc) for seeding a booking that is
      // already in a terminal state when the screen first loads. Kept in sync
      // with the dataset row below so `GET /bookings/booking-1` (the detail
      // route, which never reads the dataset) cannot disagree with the list.
      fb.bookingStatus = 'CANCELLED';

      // TWO bookings, served by the REAL (statuses, sort, page) slice — the
      // single-booking route cannot express "two rows in different statuses".
      //   * `booking-1`  CANCELLED, 90 min from the fixture start — spans
      //     `consumedTime`, which is what makes the allowlist claim below a
      //     real one.
      //   * `booking-occupier` CONFIRMED, starting on the THIRD declared time
      //     (`freeTime`, start + 2 h). It genuinely occupies that slot, and
      //     «Скасовані» hides it — the exact false-«Вільно» setup.
      final DateTime fixtureStart = DateTime.parse(fb.bookingStartsAt);
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        fb.datasetBookingRow(
          id: 'booking-1',
          status: 'CANCELLED',
          startsAt: fixtureStart,
          duration: const Duration(minutes: 90),
        ),
        fb.datasetBookingRow(
          id: 'booking-occupier',
          status: 'CONFIRMED',
          startsAt: fixtureStart.add(const Duration(hours: 2)),
          duration: const Duration(minutes: 60),
        ),
      ]);

      final ({TimeOfDay bookedTime, TimeOfDay consumedTime, TimeOfDay freeTime})
      times = await _bootToDeclaredTimesDay(tester, fb);

      final Finder cancelledCard = find.byKey(
        const ValueKey<String>('master-booking-card-booking-1'),
      );
      final Finder occupierCard = find.byKey(
        const ValueKey<String>('master-booking-card-booking-occupier'),
      );

      // ══ PHASE A — the DEFAULT view. ══════════════════════════════════════
      // The 2026-08-13 exclusion lives on `BookingsDiscoveryView`'s shared
      // query, so it applies here exactly as it does to the timeline grid.
      // The default wire set is `{CONFIRMED, COMPLETED, NOT_COMPLETED}` —
      // occupancy-COMPLETE (it carries both statuses that take the master's
      // clock), so free cards are still entitled to render. Asserted BEFORE
      // any scroll, on the list's first entries, so nothing can pass merely
      // because a row was unbuilt.
      expect(
        cancelledCard,
        findsNothing,
        reason:
            'a CANCELLED booking is off the master\'s day list until '
            '«Скасовані» is ticked (locked 2026-08-13)',
      );
      expect(
        find.byKey(_freeCardKey(times.bookedTime)),
        findsOneWidget,
        reason:
            'the DEFAULT wire set contains both CONFIRMED and COMPLETED, so '
            'this view can see everything that occupies the clock — «Вільно» '
            'is a claim it is entitled to make, and a cancelled booking '
            'releases the slot anyway',
      );
      await _scrollCardsTo(tester, occupierCard);
      expect(
        occupierCard,
        findsOneWidget,
        reason:
            'the CONFIRMED booking is visible by default — the fixture guard '
            'for PHASE B, which depends on this slot being genuinely taken',
      );

      // ══ PHASE B — «Скасовані» only: the wire set becomes {CANCELLED,
      //    DECLINED}, which cannot see a CONFIRMED booking at all. ══════════
      await _applyStatusFilter(tester, <BookingStatusFilterGroup>[
        BookingStatusFilterGroup.cancelled,
      ]);

      expect(
        occupierCard,
        findsNothing,
        reason:
            'fixture guard — the CONFIRMED booking really is off the wire '
            'now, so the next assertion is about an UNSEEN occupied slot',
      );
      expect(
        find.byKey(_freeCardKey(times.freeTime)),
        findsNothing,
        reason:
            'THE USER-REPORTED BUG: this declared time is occupied by a '
            'CONFIRMED booking the filter hid. The view cannot see it, so it '
            'must not claim the slot is «Вільно» — it renders nothing at all '
            '(MUTATION-VERIFIED: hard-coding showsAllOccupancy: true turns '
            'this RED)',
      );
      expect(
        find.byKey(_freeCardKey(times.consumedTime)),
        findsNothing,
        reason:
            'suppression is total, not a per-slot heuristic — the whole '
            'question "is this free?" is unanswerable from this list',
      );

      expect(
        cancelledCard,
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
          of: cancelledCard,
          matching: find.text(l10n.bookingStatusCancelled),
        ),
        findsOneWidget,
        reason: 'the CANCELLED status must be visible on the real card',
      );
      expect(
        find.descendant(
          of: cancelledCard,
          matching: find.text(l10n.bookingStatusConfirmed),
        ),
        findsNothing,
        reason:
            'THE REGRESSION THE CARD SWAP FIXES: the retired bespoke card '
            'never read Booking.status, so a CANCELLED booking rendered '
            'identically to a CONFIRMED one — this must never be true again',
      );
      expect(
        find.descendant(of: cancelledCard, matching: find.textContaining('₴')),
        findsNothing,
        reason: 'a CANCELLED booking owes nothing — no price pill',
      );

      // ══ PHASE C — tick the remaining two groups. All three ticked
      //    resolves to the EMPTY wire set (no `status` param at all), which
      //    is occupancy-COMPLETE again. (2026-08-15: the sheet's fourth row,
      //    `notCompleted`, was retired — nothing in the app can SET that
      //    status; see `BookingStatusFilterGroup`'s header in
      //    `bookings_filter_sheet.dart`. `BookingsDayQuery.dayList`'s
      //    `maximalStatuses` argument keeps "every remaining row ticked"
      //    resolving to select-all despite the smaller universe — see
      //    `booking_status_test.dart`'s `maximal`-parameter group for the
      //    unit-level proof.) ════════════════════════════════════════════════
      await _applyStatusFilter(tester, <BookingStatusFilterGroup>[
        BookingStatusFilterGroup.confirmed,
        BookingStatusFilterGroup.completed,
      ]);

      expect(
        cancelledCard,
        findsOneWidget,
        reason: 'select-all still shows the cancelled booking',
      );
      // THE STATUS ALLOWLIST, at the E2E tier — the counterpart to the
      // CONFIRMED test's consumed-slot assertion, on the SAME declared time,
      // and now with the cancelled booking genuinely ON the wire. A CANCELLED
      // booking releases the master's clock, so the slot inside its 90-minute
      // span is bookable again and must render as free. Together the two
      // tests prove the E2E composition reads the booking's real STATUS into
      // the membership rule, not merely its `endAt`.
      await _expectFreeCard(
        tester,
        times.consumedTime,
        'a CANCELLED booking consumes nothing — the declared time inside its '
        'former span is free again and must render, unlike the CONFIRMED '
        'case one test above',
      );
      // THE NEGATIVE CONTROL for PHASE B: free cards are suppressed by an
      // incomplete QUERY, never removed outright. Restore occupancy
      // completeness and they come straight back.
      await _scrollCardsTo(tester, occupierCard);
      expect(
        occupierCard,
        findsOneWidget,
        reason:
            'the CONFIRMED booking is back on the wire, so its declared time '
            'renders as a real card rather than as nothing',
      );

      expect(tester.takeException(), isNull);
    },
  );
}
