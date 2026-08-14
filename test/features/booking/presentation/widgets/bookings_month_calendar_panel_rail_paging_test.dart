// mobile-qa (2026-08-14) — the two NEGATIVE contracts of the week-pager /
// headerless-grid rework, plus the day-cell key uniqueness the whole widget
// suite silently depends on.
//
// WHAT THIS FILE PINS, AND WHY NOTHING ELSE DOES
// ----------------------------------------------
// 1. RAIL PAGING SELECTS NOTHING. `bookings_discovery_view.dart`'s
//    `_selectDay` doc states it as move #2 of the four-move consistency
//    contract: a week flick moves the rail's own viewport and NOTHING else.
//    It is the only one of the four with no positive evidence anywhere — the
//    other three are pinned by a fetch, a label change or a rendered card.
//    A regression that wired `onPageChanged` on the rail (exactly what
//    mobile-perf had to unpick on the MONTH pager, in this same diff) would
//    fire one selection and one `GET /bookings/me` per flicked week, and
//    EVERY existing test would stay green: they all assert what a selection
//    does, never that an absent one did not happen.
//
//    Per mobile-qa M14 a negative assertion has to be mutation-probed or it
//    can pass for the wrong reason forever, so each one below is paired with
//    a POSITIVE control in the same test — the same finder, the same widget,
//    a gesture that MUST fire — so "nothing fired" can never mean "the probe
//    was pointed at nothing".
//
// 2. RAIL PAGING DOES NOT RELABEL. The month+year label is derived from
//    `selectedDay`, so paging the rail across a month boundary must leave it
//    alone. This is the user-visible half of (1) and is what makes the label
//    trustworthy: it names the SELECTED month, never the browsed one.
//
// 3. DAY-CELL KEY UNIQUENESS AT REST. `month_calendar.dart:689` keys a grid
//    cell `booking-calendar-day-<dayOfMonth>` — unique only while ONE month
//    is mounted. The month pager can mount two (mid-drag), so the property
//    that keeps all 27 existing `find.byKey(Key('booking-calendar-day-N'))`
//    call sites unambiguous is precisely that a SETTLED pager holds exactly
//    one page. `PageView` gets there via `cacheExtent: allowImplicitScrolling
//    ? 1.0 : 0.0` with `allowImplicitScrolling` defaulting to false — an
//    implementation default, not a stated contract, and flipping it is a
//    one-word change that would make every such finder resolve to two
//    widgets at rest. The guard below is that stated contract.
//
// The synthetic host mirrors `bookings_month_calendar_panel_month_step_test
// .dart`'s `_StepProbeHost` deliberately: the behaviour under test is
// entirely inside the panel, and a real `ProviderScope`/repository would add
// a debounce and a fetch between the gesture and the assertion without
// making either sharper.

import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_month_calendar_panel.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/month_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

/// Mid-July 2026 — a Wednesday, mid-month, so neither the week nor the month
/// arithmetic is sitting on a boundary this file is not about.
final DateTime _today = DateTime(2026, 7, 15);

const Key _railKey = Key('master-bookings-day-rail');
const Key _gridKey = Key('bookings-month-calendar-grid');
const Key _toggleKey = Key('bookings-month-calendar-toggle');
const Key _labelKey = Key('bookings-month-calendar-label');

/// Every callback the panel can emit, recorded in one place so a test can
/// assert on the WHOLE set rather than on the one channel it happened to
/// think of. A rail pager wired to select could plausibly route through any
/// of the three.
class _Emissions {
  final List<DateTime> railTaps = <DateTime>[];
  final List<DateTime> immediateSelects = <DateTime>[];
  final List<int> monthSteps = <int>[];

  bool get isEmpty =>
      railTaps.isEmpty && immediateSelects.isEmpty && monthSteps.isEmpty;

  @override
  String toString() =>
      'railTaps=$railTaps immediateSelects=$immediateSelects '
      'monthSteps=$monthSteps';
}

class _PanelHost extends StatefulWidget {
  const _PanelHost({required this.emissions});

  final _Emissions emissions;

  @override
  State<_PanelHost> createState() => _PanelHostState();
}

class _PanelHostState extends State<_PanelHost> {
  late DateTime selectedDay = _today;

  /// The rail's first page starts on the Monday of the week
  /// [kBookingsDayRailWeekSpan] weeks BEFORE today's — the production
  /// derivation (`_BookingsDiscoveryViewState.initState`), not a re-spelling
  /// of it, so the page index the controller opens on means the same thing
  /// here as on the real screen.
  late final DateTime firstWeekStart = railDayAt(
    mondayOf(_today),
    -kRailWeekLength * kBookingsDayRailWeekSpan,
  );

  late final PageController railController = PageController(
    initialPage: railWeekIndex(firstWeekStart, selectedDay),
  );

  @override
  void dispose() {
    railController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BookingsMonthCalendarPanel(
      railController: railController,
      railFirstWeekStart: firstWeekStart,
      weekCount: kBookingsDayRailWeekSpan * 2 + 1,
      today: _today,
      selectedDay: selectedDay,
      bookedDays: const <DateTime>{},
      onSelectRailDay: (DateTime d) {
        widget.emissions.railTaps.add(d);
        setState(() => selectedDay = d);
      },
      onSelectDay: (DateTime d) {
        widget.emissions.immediateSelects.add(d);
        setState(() => selectedDay = d);
      },
      onStepMonth: (int delta) {
        widget.emissions.monthSteps.add(delta);
        final DateTime target = DateTime(
          selectedDay.year,
          selectedDay.month + delta,
        );
        final int lastDay = DateTime(target.year, target.month + 1, 0).day;
        setState(() {
          selectedDay = DateTime(
            target.year,
            target.month,
            selectedDay.day > lastDay ? lastDay : selectedDay.day,
          );
        });
      },
      timeline: const SizedBox.shrink(key: Key('timeline-stand-in')),
    );
  }
}

void main() {
  Future<_Emissions> pumpPanel(WidgetTester tester) async {
    final _Emissions emissions = _Emissions();
    await tester.pumpApp(_PanelHost(emissions: emissions));
    await tester.pumpAndSettle();
    return emissions;
  }

  String label(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(_labelKey)).data!;

  Future<void> flingRail(WidgetTester tester, double dx) async {
    await tester.fling(find.byKey(_railKey), Offset(dx, 0), 800);
    await tester.pumpAndSettle();
    // The rail-chip path is debounced by 220 ms in production. Nothing here
    // is debounced, but advancing past that window means a REAL screen's
    // timer would also have fired by now — so "still nothing" is a claim
    // about the production path, not about this host's directness.
    // fixed-wait-ok: advancing past the 220 ms rail-tap debounce window.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  // ── Contract 2 of the four-move consistency contract ────────────────────

  testWidgets(
    'paging the rail — forward, back, and several weeks out — selects '
    'NOTHING, on any of the panel\'s three callbacks',
    (tester) async {
      final _Emissions emissions = await pumpPanel(tester);

      // Five weeks forward, then three back: a browsing excursion, not a
      // single flick, so a per-settle OR a per-midpoint-crossing regression
      // both have many chances to fire.
      for (int i = 0; i < 5; i++) {
        await flingRail(tester, -300);
      }
      for (int i = 0; i < 3; i++) {
        await flingRail(tester, 300);
      }

      expect(
        emissions.isEmpty,
        isTrue,
        reason:
            'paging the rail emitted a selection ($emissions). Move #2 of the '
            'rail↔calendar consistency contract is that a week flick moves '
            'the rail\'s viewport and nothing else — a pager that selects on '
            'settle fires one GET /bookings/me per flicked week, which is '
            'exactly what the 220 ms day-tap debounce exists to prevent',
      );

      // ── POSITIVE CONTROL (M14) ────────────────────────────────────────
      // The assertion above is an ABSENCE. Without this half it would pass
      // just as happily if the fling had missed the rail entirely, or if the
      // panel had never mounted. Tapping a chip on the week the rail has
      // actually paged to must fire — through the SAME callback set, on the
      // SAME widget, after the SAME gestures.
      // `selectedDay` has not moved (that is the point), so the week now on
      // screen has to be derived from the rail's own settled PAGE instead.
      final BookingsDayRail rail = tester.widget<BookingsDayRail>(
        find.byType(BookingsDayRail),
      );
      final int settledPage = rail.controller.page!.round();
      final DateTime pagedMonday = railDayAt(
        rail.firstWeekStart,
        settledPage * kRailWeekLength,
      );
      expect(
        pagedMonday,
        isNot(mondayOf(_today)),
        reason:
            'fixture guard: the rail never left the week it opened on, so '
            'the excursion above exercised nothing',
      );
      expect(
        rail.selectedDay,
        _today,
        reason:
            'the rail\'s own selectedDay moved during a pure paging '
            'excursion — the host wrote date state from a viewport move',
      );

      await tester.tap(find.byKey(dayChipKey(pagedMonday)));
      // fixed-wait-ok: advancing past the 220 ms rail-tap debounce window.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(
        emissions.railTaps,
        <DateTime>[pagedMonday],
        reason:
            'positive control failed: a chip TAP on the paged-to week did '
            'not select either, so the "paging selects nothing" assertion '
            'above was vacuous — the probe was pointed at a rail that could '
            'not select at all',
      );
    },
  );

  testWidgets(
    'paging the rail ACROSS a month boundary leaves the month+year label '
    'untouched — the label names the SELECTED month, never the browsed one',
    (tester) async {
      final _Emissions emissions = await pumpPanel(tester);
      final String opening = label(tester);

      // Six weeks forward from mid-July is comfortably into September, so a
      // label derived from the rail's viewport rather than from the selection
      // cannot fail to change.
      for (int i = 0; i < 6; i++) {
        await flingRail(tester, -300);
      }

      final BookingsDayRail rail = tester.widget<BookingsDayRail>(
        find.byType(BookingsDayRail),
      );
      final DateTime pagedMonday = railDayAt(
        rail.firstWeekStart,
        rail.controller.page!.round() * kRailWeekLength,
      );
      expect(
        pagedMonday.month,
        isNot(_today.month),
        reason:
            'fixture guard: six week pages did not leave July, so a label '
            'tracking the viewport would look identical to one tracking the '
            'selection and the assertion below proves nothing',
      );

      expect(
        label(tester),
        opening,
        reason:
            'the month label followed the RAIL\'s viewport instead of the '
            'selection — the master is now looking at a month name that no '
            'part of the query, the grid or the timeline agrees with',
      );
      expect(emissions.isEmpty, isTrue, reason: emissions.toString());
    },
  );

  // ── Day-cell key uniqueness ─────────────────────────────────────────────

  testWidgets('a SETTLED month pager holds exactly ONE month — every '
      'booking-calendar-day-N key resolves to exactly one widget', (
    tester,
  ) async {
    // ⚠ This is the property all 27 existing `find.byKey(Key(
    // 'booking-calendar-day-N'))` call sites across the suite depend on and
    // none of them states. The cell key is the DAY-OF-MONTH only
    // (`month_calendar.dart:689`), so it is unique only while one month is
    // mounted. `PageView` mounts one at rest solely because
    // `allowImplicitScrolling` defaults to false (`page_view.dart` sets
    // `cacheExtent: allowImplicitScrolling ? 1.0 : 0.0`) — an
    // implementation default that a one-word change would flip, silently
    // turning every one of those finders into a "found 2 widgets" failure
    // or, worse, a `.first` that resolves to the wrong month.
    await pumpPanel(tester);
    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();

    expect(
      find.byType(MonthCalendar),
      findsOneWidget,
      reason:
          'the settled month pager has more than one month grid mounted — '
          'booking-calendar-day-N is keyed by day-of-month alone, so every '
          'such finder in the suite is now ambiguous',
    );

    // Not just "one grid": one grid means every day number in the visible
    // month is addressable, which is the usable form of the guarantee.
    // 1..28 is the intersection every month shares, so this does not
    // depend on which month the fixture lands on.
    for (int day = 1; day <= 28; day++) {
      expect(
        find.byKey(Key('booking-calendar-day-$day')),
        findsOneWidget,
        reason: 'day-of-month $day is ambiguous or missing at rest',
      );
    }
  });

  testWidgets(
    'MID-DRAG the pager DOES mount two months — a bookings-panel cell must '
    'never be addressed by a bare day-of-month key without settling first',
    (tester) async {
      // KNOWN, DELIBERATELY-DOCUMENTED TRAP (routed to mobile-qa by
      // mobile-security, 2026-08-14). This test does not assert a bug is
      // absent — it asserts the trap is exactly where the docs say it is, so
      // that a future author who reads a "found 2 widgets" failure finds the
      // explanation instead of re-deriving it, and so that a production fix
      // (widening the key to the full date, as `dayChipKey` already does)
      // announces itself here rather than passing unnoticed.
      //
      // It is NOT reachable from a settled tree: the guard above pins that
      // every assertion made after `pumpAndSettle` sees exactly one month.
      await pumpPanel(tester);
      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_gridKey)),
      );
      // Half a viewport across, in steps, so two pages genuinely straddle it.
      Duration stamp = Duration.zero;
      for (int i = 0; i < 4; i++) {
        stamp += const Duration(milliseconds: 40);
        await gesture.moveBy(const Offset(-60, 0), timeStamp: stamp);
        // fixed-wait-ok: advancing the pointer-sample clock in lockstep with
        // the synthetic move timestamps.
        await tester.pump(const Duration(milliseconds: 40));
      }

      final int monthsMounted = find.byType(MonthCalendar).evaluate().length;
      expect(
        monthsMounted,
        greaterThan(1),
        reason:
            'fixture guard: the drag did not bring a second month into the '
            'viewport, so this test is asserting nothing about the collision '
            'it documents',
      );

      // The collision itself, made concrete: the 15th exists in every month,
      // so two mounted months means two identically-keyed cells.
      expect(
        find.byKey(const Key('booking-calendar-day-15')).evaluate().length,
        monthsMounted,
        reason:
            'the day-of-month cell key stopped colliding mid-drag — if that '
            'is because the key was widened to the full date (the suggested '
            'fix), delete this test and the note above it; if it is because '
            'the pager stopped building its neighbour, the drag no longer '
            'renders a partial page and the swipe has lost its transition',
      );

      await gesture.up();
      await tester.pumpAndSettle();
    },
  );
}
