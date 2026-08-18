// Week-pager / headerless-grid rework (mobile-qa, Step 2.7 Rule 3b) — the
// «Мої записи» day rail as a Mon→Sun WEEK pager, and the permanent month+year
// label, pinned end-to-end against a real HTTP boundary.
//
// WHAT THIS FLOW EXISTS FOR, AND WHY THE WIDGET TIER IS NOT ENOUGH
// -----------------------------------------------------------------
// Three user-requested changes landed on one screen, and each has a widget
// test for the PART of it that lives in one widget. What no widget test can
// reach is the wiring BETWEEN them, which is where every one of this screen's
// historical bugs has lived:
//
//   * the rail's opening page is decided by `_railController`'s `initialPage`
//     in `_BookingsDiscoveryViewState.initState`, from `_railFirstWeekStart`
//     and the Kyiv-today the screen derives itself. A widget test pumping
//     `BookingsDayRail` directly supplies both by hand, so it pins the rail's
//     rendering and nothing about the derivation the master actually gets;
//   * "rail paging selects nothing" is only meaningful against a real QUERY.
//     `bookings_month_calendar_panel_rail_paging_test.dart` proves the panel
//     emits no callback, but a callback is not a request: a regression could
//     equally leave the callbacks alone and invalidate the day provider some
//     other way. `fb.getMyBookingsCalls` is the claim the user actually cares
//     about — no traffic, no timeline churn, for a browsing gesture;
//   * "the label follows a month page, and survives a collapse" spans the
//     panel, the host's `_stepMonth`, and the rail's own `animateToPage`. The
//     original bug this whole port fixes was precisely a label and a query
//     disagreeing.
//
// mobile-qa (2026-08-14) addendum — the day-rail MONTH-LABEL fix
// (`BookingsDayRail.onVisibleWeekChanged`, a pure relabel with NO selection
// and NO fetch, fired on rail settle). Neither pre-existing test below
// exercises it: the first test's paging excursion nets exactly one week
// (never crosses a month, by construction of its own fixture — see that
// test's own group comment for the arithmetic); the second drives the GRID's
// month pager (`_stepMonth`), a SELECTING move on an entirely different code
// path. A third test, right after the first, browses the RAIL across a real
// month boundary and back via «Сьогодні» — the exact composed scenario the
// widget-tier `bookings_discovery_view_visible_month_test.dart` also pins,
// here against the real HTTP boundary instead of a mocked repository.
//
// CLOCK DISCIPLINE (mobile-qa M15). Every date here is derived from the
// harness's INJECTED `kFixedNow` through `toBeauticaTime`/`dateOnly` — the
// same pair the app under test uses — never from `DateTime.now()`. The rail's
// opening page is a function of the app's clock, so a fixture built on the
// host clock would agree with it only on the dev VM (TZ=Europe/Kyiv) and only
// while the two happened to name the same week: a mixed-clock fixture here
// would silently page to a week the app never opened on and every assertion
// below would be about the wrong seven days.
//
// NO PATROL TIER. Nothing in this change touches an OS surface — no
// permission dialog, no deep link, no notification, no WebView, no biometric.
// It is two horizontal `PageView`s and a `Text`. `integration_test/patrol/`
// coverage would add a native-driver boot for zero additional signal, which
// is coverage theatre; the exemption is stated rather than skip-marked.

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/formatters/uk_calendar.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';
import 'support/pager_drag.dart';

/// Kyiv "today" as the app under test computes it — from the INJECTED
/// [kFixedNow], never the host clock. See the file header's clock-discipline
/// note; mirrors `master_bookings_month_step_flow_test.dart`'s constant of
/// the same name, including why it must not be read before `AppHarness.boot`.
DateTime get _kyivToday => dateOnly(toBeauticaTime(kFixedNow));

const Key _railKey = Key('master-bookings-day-rail');
const Key _gridKey = Key('bookings-month-calendar-grid');
const Key _toggleKey = Key('bookings-month-calendar-toggle');
const Key _labelKey = Key('bookings-month-calendar-label');

void _seedWorkingHours(FakeBackend fb, Iterable<DateTime> days) {
  fb.seedEffectiveSchedule(<Map<String, dynamic>>[
    for (final DateTime day in days)
      FakeBackend.seedEffectiveScheduleDay(
        day,
        intervals: const <(String, String)>[('09:00:00', '21:00:00')],
      ),
  ]);
}

/// Boots, logs in as the independent master and lands on «Мої записи».
Future<void> _openBookings(WidgetTester tester, FakeBackend fb) async {
  final GoRouter router = await AppHarness.boot(tester, fb);
  _seedWorkingHours(fb, <DateTime>[_kyivToday]);
  await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
  await tester.tap(find.byKey(const Key('master-nav-tile-1')));
  await AppHarness.settle(tester);
  expect(find.byType(MasterBookingsScreen), findsOneWidget);
  expect(AppHarness.location(router), startsWith(RouteNames.masterBookings));
}

BookingsDayRail _rail(WidgetTester tester) =>
    tester.widget<BookingsDayRail>(find.byType(BookingsDayRail));

String _label(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(_labelKey)).data!;

/// The Monday of the week the rail is CURRENTLY resting on, read from the
/// controller the screen owns rather than from the selection — the two are
/// deliberately allowed to differ while the master browses, and telling them
/// apart is the whole point of this file.
DateTime _restingWeekMonday(WidgetTester tester) {
  final BookingsDayRail rail = _rail(tester);
  return railDayAt(
    rail.firstWeekStart,
    rail.controller.page!.round() * kRailWeekLength,
  );
}

/// Asserts the rail is at rest on a WHOLE Mon→Sun week: seven chips, the
/// Monday flush at the rail's own leading inset, the Sunday last, and neither
/// neighbouring week's edge day on screen.
///
/// This is the headline user-facing contract of the rework ("the first day is
/// monday and last is sunday"), and it is asserted from RENDERED GEOMETRY, not
/// from the controller's page index — an index can be a whole number while the
/// viewport rests between two pages.
void _expectWholeWeekAtRest(WidgetTester tester, {required String at}) {
  final DateTime monday = _restingWeekMonday(tester);
  expect(
    monday.weekday,
    DateTime.monday,
    reason: '$at: the resting page does not start on a Monday',
  );

  final Rect railRect = tester.getRect(find.byKey(_railKey));
  expect(
    tester.getRect(find.byKey(dayChipKey(monday))).left,
    closeTo(railRect.left + VelvetSpacing.lg, 1.5),
    reason:
        '$at: the rail came to rest BETWEEN two weeks — the leftmost chip is '
        'not this week\'s Monday at the rail\'s leading inset. A mid-week '
        'resting span is exactly what the week pager replaced the continuous '
        'strip to make unreachable.',
  );

  for (int i = 0; i < kRailWeekLength; i++) {
    expect(
      find.byKey(dayChipKey(railDayAt(monday, i))),
      findsOneWidget,
      reason: '$at: day $i of the resting week is not on screen',
    );
  }
  final DateTime sunday = railDayAt(monday, kRailWeekLength - 1);
  expect(sunday.weekday, DateTime.sunday, reason: '$at: last chip not Sunday');
  expect(
    tester.getRect(find.byKey(dayChipKey(sunday))).right,
    lessThanOrEqualTo(railRect.right - VelvetSpacing.lg + 1.5),
    reason: '$at: the Sunday chip is not the last one inside the rail\'s inset',
  );
  expect(
    find.byKey(dayChipKey(railDayAt(monday, -1))),
    findsNothing,
    reason:
        '$at: the PREVIOUS week\'s Sunday is on screen — the resting page is '
        'a mid-week span',
  );
  expect(
    find.byKey(dayChipKey(railDayAt(monday, kRailWeekLength))),
    findsNothing,
    reason: '$at: the NEXT week\'s Monday is on screen',
  );
}

/// Turns [pager] by exactly one page, [forward] or back, then advances past
/// the screen's day-tap debounce so a selection a paging regression had
/// queued would have FIRED by the time the "no request" assertions below
/// run. Without that final wait those assertions would only prove the
/// debounce timer had not expired yet.
///
/// The page turn itself is [dragPagerByOnePage] (`support/pager_drag.dart`)
/// — see its doc comment for the full "why not `fling`" writeup and the
/// steps=4 regression this recipe guards against.
Future<void> _pageBy(
  WidgetTester tester,
  Key pager, {
  required bool forward,
}) async {
  await dragPagerByOnePage(tester, pager, forward: forward);
  // fixed-wait-ok: advancing past the screen's 220 ms day-tap debounce, so a
  // selection a paging regression had queued would have FIRED by the time the
  // "no request" assertions below run. Without it those assertions would only
  // prove the debounce timer had not expired yet.
  await tester.pump(const Duration(milliseconds: 300));
  await AppHarness.settle(tester);
}

Future<void> _pageRail(WidgetTester tester, {required bool forward}) =>
    _pageBy(tester, _railKey, forward: forward);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'the rail opens on the week containing today and pages one WHOLE week at '
    'a time — and a paging excursion selects nothing and fetches nothing',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      await _openBookings(tester, fb);

      // ── 1. The opening page is the week CONTAINING today ────────────────
      expect(
        find.byKey(dayChipKey(_kyivToday)),
        findsOneWidget,
        reason:
            'today is not on the rail\'s opening page — the rail opened on '
            'the wrong week, or parked at the start of its multi-year span',
      );
      expect(
        _restingWeekMonday(tester),
        mondayOf(_kyivToday),
        reason: 'the opening page is not today\'s own Mon→Sun week',
      );
      _expectWholeWeekAtRest(tester, at: 'on open');

      final DateTime selectedOnOpen = _rail(tester).selectedDay;
      expect(
        selectedOnOpen,
        _kyivToday,
        reason: 'the landing selection is not Kyiv today',
      );
      final String labelOnOpen = _label(tester);
      final int fetchesAfterLanding = fb.getMyBookingsCalls;
      expect(
        fetchesAfterLanding,
        greaterThan(0),
        reason:
            'fixture guard: the landing fetch never happened, so the counter '
            'below cannot show a paging regression adding to it',
      );

      // ── 2. Paging forward and back always lands on a WHOLE week ─────────
      await _pageRail(tester, forward: true);
      _expectWholeWeekAtRest(tester, at: 'one page forward');
      final DateTime weekAfterOneForward = _restingWeekMonday(tester);
      expect(
        weekAfterOneForward,
        railDayAt(mondayOf(_kyivToday), kRailWeekLength),
        reason:
            'one fling did not advance exactly one week — a page turn must '
            'move seven days, never a partial stride',
      );

      await _pageRail(tester, forward: true);
      _expectWholeWeekAtRest(tester, at: 'two pages forward');

      await _pageRail(tester, forward: false);
      _expectWholeWeekAtRest(tester, at: 'back one page');
      expect(
        _restingWeekMonday(tester),
        weekAfterOneForward,
        reason: 'paging back did not return to the week it came from',
      );

      // Past weeks stay reachable — the opening page sets a resting position,
      // it does not clamp the span.
      await _pageRail(tester, forward: false);
      await _pageRail(tester, forward: false);
      _expectWholeWeekAtRest(tester, at: 'one page into the past');
      final DateTime pastWeekMonday = _restingWeekMonday(tester);
      expect(
        pastWeekMonday.isBefore(mondayOf(_kyivToday)),
        isTrue,
        reason:
            'the rail would not page into the past — the opening page has '
            'clamped the range instead of only setting a resting position',
      );

      // ── 3. THE PIN — none of that browsing selected or fetched anything ──
      expect(
        _rail(tester).selectedDay,
        selectedOnOpen,
        reason:
            'paging the rail moved the SELECTION. Move #2 of the '
            'rail↔calendar consistency contract (bookings_discovery_view.dart '
            '_selectDay) is that a week flick moves the viewport and nothing '
            'else — only a chip TAP selects.',
      );
      // FIXTURE GUARD (mobile-qa, 2026-08-14): this excursion is 2 pages
      // forward + 3 pages back — net ONE WEEK INTO THE PAST from
      // `mondayOf(_kyivToday)` — which stays inside the SAME calendar month
      // by construction of the fixture (`_kyivToday` is mid-June; one week
      // earlier is still June). So `_label(tester) == labelOnOpen` below is
      // true whether or not the label actually follows the rail's viewport
      // across a MONTH boundary — it only proves the label does not move
      // for a same-month browse. This assertion pins PAGING MECHANICS only
      // and is NOT month-label coverage; the real month-crossing case is the
      // dedicated "browsing the WEEK RAIL across a month boundary…" test
      // below (see also the file header's 2026-08-14 addendum).
      expect(
        _label(tester),
        labelOnOpen,
        reason:
            'the month+year label followed the rail\'s VIEWPORT instead of '
            'the selection — the master is reading a month name that the '
            'query, the grid and the timeline all disagree with',
      );
      expect(
        fb.getMyBookingsCalls,
        fetchesAfterLanding,
        reason:
            'paging the rail issued GET /bookings/me. A pager that selects on '
            'settle fires one query per flicked week — the exact rate the '
            '220 ms day-tap debounce exists to prevent, and it would be '
            'defeated here because a month/rail step routes through '
            '_selectImmediate, which CANCELS that debounce.',
      );

      // ── 4. POSITIVE CONTROL (mobile-qa M14) ─────────────────────────────
      // Everything above is an ABSENCE, and an absence can pass because the
      // gesture missed, the rail never mounted, or the counter is dead. A
      // chip TAP on the week the rail has actually paged to must move all
      // three of the values just asserted constant.
      final DateTime pastTuesday = railDayAt(pastWeekMonday, 1);
      await tester.tap(find.byKey(dayChipKey(pastTuesday)));
      // fixed-wait-ok: advancing past the 220 ms day-tap debounce.
      await tester.pump(const Duration(milliseconds: 300));
      await AppHarness.settle(tester);

      expect(
        _rail(tester).selectedDay,
        pastTuesday,
        reason:
            'positive control failed: a chip TAP did not select either, so '
            'every "paging changed nothing" assertion above was vacuous',
      );
      expect(
        fb.getMyBookingsCalls,
        greaterThan(fetchesAfterLanding),
        reason:
            'positive control failed: a chip TAP issued no request, so the '
            'fetch-count assertion above was measuring a dead counter',
      );
      expect(fb.lastMyBookingsQuery!['from'], toApiDate(pastTuesday));
      expect(fb.lastMyBookingsQuery!['to'], toApiDate(pastTuesday));
      // The rail stays on the tapped day's own week — a tap is inside the
      // visible page, so nothing pages, and the week must not jump.
      _expectWholeWeekAtRest(tester, at: 'after a chip tap');
      expect(_restingWeekMonday(tester), pastWeekMonday);
    },
  );

  // ═══════════════════════════════════════════════════════════════════════
  // mobile-qa (2026-08-14) — the day-rail month-label fix, composed against a
  // real HTTP boundary.
  //
  // WHY THE TEST ABOVE DOES NOT ALREADY COVER THIS. Its own paging excursion
  // (2 forward, 3 back, net ONE WEEK INTO THE PAST from `_kyivToday` = Kyiv
  // 2026-06-14) never leaves June — `mondayOf(_kyivToday)` is 2026-06-08, and
  // one week earlier is 2026-06-01, still June — so its
  // `_label(tester) == labelOnOpen` assertion is true whether or not paging
  // relabels the screen. It pins "paging selects/fetches nothing"; it was
  // never a test of the label following a MONTH-crossing browse, and reading
  // it as one would be a false sense of coverage. Confirmed by fixture: 5
  // week-pages forward from 2026-06-08 lands on 2026-07-13, genuinely a
  // different month.
  //
  // The second test below (month+year label…) only drives the GRID's month
  // pager (`_stepMonth`, a SELECTING move) — a different code path from the
  // rail's `onVisibleWeekChanged` (a pure relabel, no selection, no fetch)
  // this fix added. Neither existing flow reaches it.
  testWidgets(
    'browsing the WEEK RAIL across a month boundary relabels the panel, '
    'issues no request, and «Сьогодні» resyncs the label back — the exact '
    'composed defect the day-rail month-label fix closes, end-to-end '
    'against a real HTTP boundary',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      await _openBookings(tester, fb);

      final String labelOnOpen = _label(tester);
      final int fetchesAfterLanding = fb.getMyBookingsCalls;
      expect(
        fetchesAfterLanding,
        greaterThan(0),
        reason:
            'fixture guard: the landing fetch never happened, so the '
            'no-extra-fetch assertions below would prove nothing',
      );

      // Five week-pages forward from `_kyivToday`'s own week — see the group
      // comment above for why this (and not the sibling test's ±few-page
      // excursion) is what actually crosses a month boundary.
      for (int i = 0; i < 5; i++) {
        await _pageRail(tester, forward: true);
      }
      _expectWholeWeekAtRest(tester, at: 'five weeks forward');

      final DateTime browsedMonday = _restingWeekMonday(tester);
      expect(
        browsedMonday.month,
        isNot(_kyivToday.month),
        reason:
            'fixture guard: five week-pages did not leave the landing '
            'month, so the relabel assertion below proves nothing',
      );
      expect(
        _rail(tester).selectedDay,
        _kyivToday,
        reason:
            'browsing moved the SELECTION — it must stay pure navigation, '
            'exactly as the sibling test above pins for a same-month '
            'excursion',
      );

      final String expectedBrowsed =
          '${monthNominative(browsedMonday.month)} ${browsedMonday.year}';
      expect(
        _label(tester),
        expectedBrowsed,
        reason:
            'the month+year label did not follow the rail across a month '
            'boundary — this is the production defect ("Мої записи" showing '
            'the OLD month while the rail is scrolled into a new one) the '
            'day-rail month-label fix exists to close.',
      );

      // "Also verify": paging the rail is pure navigation — no request, ever
      // — including across a month boundary, at the level where a request
      // would actually reach the fake backend.
      expect(
        fb.getMyBookingsCalls,
        fetchesAfterLanding,
        reason:
            'browsing the rail across a month boundary issued GET '
            '/bookings/me — a week flick must only ever relabel',
      );

      // «Сьогодні» — the day never actually changes (it was already Kyiv
      // today), so this is a pure relabel-back, the exact scenario the bug
      // report describes.
      await tester.tap(find.byKey(const Key('master-bookings-today')));
      await AppHarness.settle(tester);

      expect(
        _label(tester),
        labelOnOpen,
        reason:
            'pressing «Сьогодні» after browsing across a month boundary '
            'left the label on the browsed-to month instead of the current '
            'one.',
      );
      // No new fetch: `_day` never actually changed (today → today), so the
      // value-equal query never re-triggers `bookingsDayProvider`'s
      // keepalive family — see
      // `bookings_discovery_view_visible_month_test.dart`'s matching widget
      // test for the same observation spelled out in full.
      expect(fb.getMyBookingsCalls, fetchesAfterLanding);
      _expectWholeWeekAtRest(tester, at: 'after «Сьогодні»');
      expect(_restingWeekMonday(tester), mondayOf(_kyivToday));
    },
  );

  testWidgets(
    'the month+year label is permanent, anchored identically in BOTH resting '
    'states, follows a month page, and survives the collapse — with no ‹ › '
    'chevrons anywhere on this screen',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      await _openBookings(tester, fb);

      final String expectedOpening =
          '${monthNominative(_kyivToday.month)} ${_kyivToday.year}';
      expect(
        _label(tester),
        expectedOpening,
        reason:
            'the collapsed label does not name the selected day\'s month — '
            'it is derived from something other than the selection',
      );
      final Rect labelCollapsed = tester.getRect(find.byKey(_labelKey));

      // ── 1. It does NOT vanish when the calendar opens ────────────────────
      // The literal user complaint this rework answers: "keep month and year
      // in same place because now it disappears".
      await tester.tap(find.byKey(_toggleKey));
      await AppHarness.settle(tester);

      expect(
        find.byKey(_labelKey),
        findsOneWidget,
        reason:
            'the month+year label vanished when the calendar expanded — the '
            'exact regression this rework exists to fix',
      );
      expect(_label(tester), expectedOpening);
      expect(
        tester.getRect(find.byKey(_labelKey)),
        labelCollapsed,
        reason:
            'the label MOVED between the two resting states. It is now the '
            'only affordance teaching what the grid\'s horizontal swipe does, '
            'so it must occupy the same anchor at every expand fraction.',
      );

      // ── 2. No month-navigation BUTTONS exist (locked requirement) ────────
      // A negative assertion that catches a re-introduction. Its positive
      // counterpart — that SlotDateScreen / MasterSchedulePage /
      // period_range_picker KEEP their chevrons, because `showHeader`
      // defaults to `true` — is pinned at the widget tier by
      // `month_calendar_show_header_test.dart` (and, behaviourally, by
      // `slot_picker_test.dart`, which taps `booking-calendar-next-month` to
      // change month). Asserting the OTHER screens here would mean booting
      // two more routes for a fact one widget test already proves exactly.
      expect(
        find.byKey(const Key('booking-calendar-prev-month')),
        findsNothing,
        reason:
            'a ‹ chevron is on the expanded bookings calendar — the locked '
            'requirement is that months change by horizontal scroll ONLY, '
            'with no new buttons',
      );
      expect(
        find.byKey(const Key('booking-calendar-next-month')),
        findsNothing,
        reason: 'a › chevron is on the expanded bookings calendar',
      );
      // …and the month name is on screen exactly ONCE, which is what
      // retiring the grid's own header was for.
      expect(
        find.text(expectedOpening),
        findsOneWidget,
        reason:
            'the month+year is rendered twice — the grid has grown its own '
            'header back alongside the panel\'s permanent label',
      );

      // ── 3. A month PAGE moves the label ─────────────────────────────────
      // A hand-driven pointer, not `tester.fling` — see [_pageBy]'s doc for
      // why `fling` is unreliable on the live E2E binding.
      await _pageBy(tester, _gridKey, forward: true);

      final DateTime steppedDay = _rail(tester).selectedDay;
      expect(
        steppedDay.month,
        isNot(_kyivToday.month),
        reason:
            'fixture guard: the fling did not turn the month page at all, so '
            'nothing below is proven',
      );
      final String expectedStepped =
          '${monthNominative(steppedDay.month)} ${steppedDay.year}';
      expect(
        _label(tester),
        expectedStepped,
        reason:
            'the label did not follow the month page — with the chevrons '
            'retired it is the ONLY feedback that the swipe landed',
      );

      // ── 4. Collapse — label AND rail week must agree, by construction ────
      await tester.tap(find.byKey(_toggleKey));
      await AppHarness.settle(tester);

      expect(
        _label(tester),
        expectedStepped,
        reason:
            'collapsing reverted the label to the pre-step month — the label '
            'is being derived from something other than the selection',
      );
      expect(
        find.byKey(dayChipKey(steppedDay)),
        findsOneWidget,
        reason:
            'the collapsed rail is not showing the week containing the '
            'stepped-to day — the two pagers desynced, so the strip shows '
            'one month\'s days under another month\'s label',
      );
      expect(
        _restingWeekMonday(tester),
        mondayOf(steppedDay),
        reason: 'the rail rests on a week that is not the selected day\'s',
      );
      _expectWholeWeekAtRest(tester, at: 'after expand → page → collapse');

      // And the WIRE agrees with both — the original field bug was a label
      // and a query naming different months.
      expect(fb.lastMyBookingsQuery!['from'], toApiDate(steppedDay));
      expect(fb.lastMyBookingsQuery!['to'], toApiDate(steppedDay));
    },
  );
}
