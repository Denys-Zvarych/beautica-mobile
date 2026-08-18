// mobile-perf HIGH regression guard (finding #1, audit cycle 1, 2026-08-14):
// ONE settled gesture on the month pager is ONE month step.
//
// THE BUG THIS FILE PINS
// -----------------------
// The Варіант D rework resolved a month step from `PageView.onPageChanged`.
// That callback is NOT a settle callback: `page_view.dart` wires it to a
// `ScrollUpdateNotification` handler comparing `metrics.page.round()` against
// the last reported index, so it fires on every page-MIDPOINT CROSSING while
// the finger is still down. A month step SELECTS (the locked contract — see
// `bookings_month_calendar_panel.dart`'s `_resolveMonthPage`), and the host
// applies a selection through `_selectImmediate`, which explicitly CANCELS the
// 220ms rail debounce — so nothing downstream rate-limited it either.
//
// A single hesitant back-and-forth drag therefore emitted a whole burst of
// steps: one `GET /bookings/me` and one `effectiveSchedule` fetch apiece, a
// month label flickering between two values under the master's finger, and —
// when the drag ended back where it began — a net-zero month change that had
// still re-selected days the master never chose. The hand-rolled
// `onHorizontalDrag*` recogniser the pager replaced fired at most once per
// gesture, so this was a regression the rework introduced, and a correctness
// one as much as a performance one.
//
// The fix reads the pager's SETTLED page from a `ScrollEndNotification`
// instead. `ScrollPosition.beginActivity` dispatches `didEndScroll()` only on
// the transition from a scrolling activity to a non-scrolling one, and drag →
// ballistic is scrolling → scrolling, so exactly one such notification exists
// per gesture no matter how the finger wandered.
//
// MUTATION-PROBED (2026-08-14), against the PRE-FIX
// `bookings_month_calendar_panel.dart` (the `onPageChanged:
// _onMonthPageChanged` wiring, no `_monthPagerScrolling` guard, no content
// gate):
//   * test 1 — red on `steps`: `[1, -1, 1]`, not `[1]`.
//   * test 2 — red on `steps`: `[1, -1]`, not empty. The auditor's own
//     reproduction: two selections, two day-list fetches, zero net movement.
//   * test 3 — red on the mid-drag page reading: 603.0, i.e. the pager had
//     been teleported to the externally-selected month and the gesture killed
//     under the finger.
//   * test 4 — red on `find.byType(MonthCalendar)`: one full grid built while
//     the panel was collapsed.
//   * test 5 is the ONE test here that is green both before and after, by
//     design. It is not a bug reproduction — it is the standing guard on the
//     gate CHOICE: pre-fix there was no gate to strand anything, and the
//     obvious alternative gates (`Offstage`, `Visibility(visible: false)`)
//     would turn it red because both skip layout and leave
//     `PageController.page` null, which makes `didUpdateWidget` early-return
//     on a stale month. Verified by swapping the content gate for
//     `Offstage(offstage: !_gridContentMounted)` around the pager: red on
//     `pagerPage` ("the month pager has not been laid out"), reverted after.
//
// WHY A SYNTHETIC HOST. `_StepProbeHost` reproduces the ONE thing the real
// screen does with `onStepMonth` that matters here — `_stepMonth`'s "same
// day-of-month in the target month, clamped to its length", then a selection
// — without a repository, a fake backend, or a `ProviderScope` full of
// booking providers. The behaviour under test is entirely inside the panel;
// the host's only job is to close the two-way sync loop so `didUpdateWidget`
// runs for real.

import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_month_calendar_panel.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/month_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

/// Mirrors the real screen's own month-page geometry so a test can name an
/// absolute page index: the panel anchors its pager on `today`'s month at
/// index 600 (`_kMonthPageSpan`) and walks one index per calendar month.
const int _kMonthPageSpan = 600;

int _monthOrdinal(DateTime m) => m.year * 12 + (m.month - 1);

/// The page index the panel MUST be resting on for [day] to be selected.
int _pageForDay(DateTime today, DateTime day) =>
    _monthOrdinal(DateTime(day.year, day.month)) -
    _monthOrdinal(DateTime(today.year, today.month)) +
    _kMonthPageSpan;

class _StepProbeHost extends StatefulWidget {
  const _StepProbeHost({super.key, required this.today, required this.onStep});

  final DateTime today;

  /// Observes every `onStepMonth` the panel emits — the raw signal this file
  /// is about. Deliberately separate from [_StepProbeHostState.applyStep] so
  /// a test counts EMISSIONS, not net movement: the bug's signature is that
  /// several emissions can cancel out to no movement at all.
  final ValueChanged<int> onStep;

  @override
  State<_StepProbeHost> createState() => _StepProbeHostState();
}

class _StepProbeHostState extends State<_StepProbeHost> {
  late DateTime selectedDay = widget.today;
  late final PageController railController = PageController(
    initialPage: kBookingsDayRailWeekSpan,
  );

  @override
  void dispose() {
    railController.dispose();
    super.dispose();
  }

  /// Transcribed from `bookings_discovery_view.dart`'s `_stepMonth` — same
  /// day-of-month in the target month, clamped to that month's length.
  void applyStep(int delta) {
    widget.onStep(delta);
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
  }

  /// A selection arriving from OUTSIDE the pager — a rail tap, «Сьогодні», a
  /// deep link. Drives `didUpdateWidget`'s pull-IN half of the two-way sync.
  void selectExternally(DateTime day) => setState(() => selectedDay = day);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: BookingsMonthCalendarPanel(
            railController: railController,
            railFirstWeekStart: railDayAt(
              mondayOf(widget.today),
              -7 * kBookingsDayRailWeekSpan,
            ),
            weekCount: kBookingsDayRailWeekSpan * 2 + 1,
            today: widget.today,
            selectedDay: selectedDay,
            bookedDays: const <DateTime>{},
            onSelectRailDay: (DateTime _) {},
            onSelectDay: (DateTime _) {},
            onStepMonth: applyStep,
            timeline: const SizedBox.shrink(key: Key('timeline-stand-in')),
          ),
        ),
      ],
    );
  }
}

void main() {
  /// Mid-July, comfortably away from a month boundary so the clamped
  /// day-of-month arithmetic in `applyStep` never changes the day and every
  /// assertion below is about the MONTH alone.
  final DateTime today = DateTime(2026, 7, 15);

  Finder gridFinder() => find.byKey(const Key('bookings-month-calendar-grid'));

  /// The pager's live page — read straight off the real `PageController` the
  /// panel owns, so a test can see where a gesture actually landed rather
  /// than inferring it from the label.
  double pagerPage(WidgetTester tester) {
    final PageController? controller = tester
        .widget<PageView>(gridFinder())
        .controller;
    // The panel always supplies its own `_monthPage`; a null here would mean
    // the pager had been reconstructed without one, which is itself the
    // stale-page hazard these tests exist to rule out.
    expect(
      controller,
      isNotNull,
      reason: 'the month pager lost its controller',
    );
    final double? page = controller?.page;
    expect(page, isNotNull, reason: 'the month pager has not been laid out');
    return page ?? double.nan;
  }

  Future<_StepProbeHostState> pumpCollapsed(
    WidgetTester tester, {
    required ValueChanged<int> onStep,
  }) async {
    final GlobalKey<_StepProbeHostState> hostKey =
        GlobalKey<_StepProbeHostState>();
    await tester.pumpApp(
      _StepProbeHost(key: hostKey, today: today, onStep: onStep),
    );
    await tester.pumpAndSettle();
    return hostKey.currentState!;
  }

  Future<void> toggle(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('bookings-month-calendar-toggle')));
    await tester.pumpAndSettle();
  }

  /// Mounts the probe and OPENS the calendar. The month pager is unreachable
  /// while collapsed (`IgnorePointer(ignoring: t < 0.5)`), so every gesture
  /// test here starts from the expanded state.
  Future<_StepProbeHostState> pumpExpanded(
    WidgetTester tester, {
    required ValueChanged<int> onStep,
  }) async {
    final _StepProbeHostState host = await pumpCollapsed(
      tester,
      onStep: onStep,
    );
    await toggle(tester);
    return host;
  }

  /// Drives a CONTINUOUS drag: one pointer-down, a scripted list of
  /// horizontal deltas, one pointer-up. Negative dx pages FORWARD (content
  /// moves left, `pixels` and therefore `page` increase).
  ///
  /// Each move carries an explicit, monotonically advancing `timeStamp` and is
  /// followed by a `pump` of the same length — without that the velocity
  /// tracker sees zero elapsed time between samples and the release resolves
  /// against a meaningless velocity, which would make the settle target (and
  /// so every assertion) depend on `PageScrollPhysics` noise rather than on
  /// the code under test.
  Future<void> continuousDrag(
    WidgetTester tester, {
    required List<double> deltas,
    Duration step = const Duration(milliseconds: 40),
    Future<void> Function(int index)? afterMove,
    Duration? finalPause,
  }) async {
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(gridFinder()),
    );
    Duration stamp = Duration.zero;
    for (int i = 0; i < deltas.length; i++) {
      // The last leg may be slowed deliberately (see `finalPause`) so the
      // release carries a sub-tolerance velocity and `PageScrollPhysics`
      // settles to the nearest page rather than flinging to the next one.
      final Duration gap = (finalPause != null && i == deltas.length - 1)
          ? finalPause
          : step;
      stamp += gap;
      await gesture.moveBy(Offset(deltas[i], 0), timeStamp: stamp);
      // fixed-wait-ok: advancing the pointer-sample clock in lockstep with
      // the synthetic move timestamps, not waiting on a condition.
      await tester.pump(gap);
      if (afterMove != null) await afterMove(i);
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a continuous hesitant drag that ENDS one page forward emits exactly ONE '
    'month step, and the month lands where the gesture ended',
    (tester) async {
      final List<int> steps = <int>[];
      final _StepProbeHostState host = await pumpExpanded(
        tester,
        onStep: steps.add,
      );

      final double pageBefore = pagerPage(tester);
      expect(
        pageBefore,
        _pageForDay(today, today).toDouble(),
        reason: 'fixture guard: the pager did not open on today\'s month',
      );

      // Forward past the midpoint (+700px ≈ 0.875 page), back across it
      // (-500px → 0.25 page), then forward past it again (+500px → 0.875
      // page) — three midpoint crossings inside ONE uninterrupted gesture,
      // which is precisely what `onPageChanged` reported as three separate
      // month steps.
      await continuousDrag(
        tester,
        deltas: <double>[
          ...List<double>.filled(7, -100),
          ...List<double>.filled(5, 100),
          ...List<double>.filled(5, -100),
        ],
      );

      expect(
        steps,
        <int>[1],
        reason:
            'one settled gesture must resolve to exactly ONE month step. '
            'More than one entry here means the step is still being resolved '
            'from mid-drag page-midpoint crossings (PageView.onPageChanged) '
            'rather than from the settled position — every extra entry is a '
            'GET /bookings/me and an effectiveSchedule fetch for a month the '
            'master never stopped on',
      );
      expect(
        host.selectedDay,
        DateTime(2026, 8, 15),
        reason:
            'the month must land where the gesture ENDED — same '
            'day-of-month, one month forward',
      );
      // The pager and the selection must agree, or the panel is holding a
      // month the host does not know about.
      expect(pagerPage(tester), _pageForDay(today, host.selectedDay));
    },
  );

  testWidgets(
    'a continuous hesitant drag that ends back on its STARTING page emits no '
    'month step at all, and does not move the selection',
    (tester) async {
      final List<int> steps = <int>[];
      final _StepProbeHostState host = await pumpExpanded(
        tester,
        onStep: steps.add,
      );

      // Forward past the midpoint, then all the way back — the auditor's
      // reproduction, which measured `[1, -1, 1, -1]` and a net-zero month
      // change. The final leg is deliberately slow (a 300ms sample gap for a
      // 5px move ≈ 17px/s, well under the fling tolerance) so the release
      // settles to the nearest page instead of flinging onward.
      await continuousDrag(
        tester,
        deltas: <double>[
          ...List<double>.filled(7, -100),
          ...List<double>.filled(7, 100),
          5,
        ],
        finalPause: const Duration(milliseconds: 300),
      );

      expect(
        steps,
        isEmpty,
        reason:
            'a gesture that navigated nowhere must select nothing. Entries '
            'here are the mid-drag midpoint crossings the settle-resolution '
            'fix exists to stop — each one refetched the day list and '
            'flickered the month label for a move the master then undid',
      );
      expect(
        host.selectedDay,
        today,
        reason: 'the selection moved even though the month did not',
      );
      expect(pagerPage(tester), _pageForDay(today, today));
    },
  );

  testWidgets(
    'an external selection change arriving MID-DRAG does not cancel the '
    'gesture, and the pager is never left on a stale month',
    (tester) async {
      final List<int> steps = <int>[];
      final _StepProbeHostState host = await pumpExpanded(
        tester,
        onStep: steps.add,
      );

      // `PageController.jumpTo` opens with `goIdle()`, which kills whatever
      // activity is running — including a live drag. Before the guard,
      // `didUpdateWidget`'s resync fired on this external selection and the
      // pager teleported to October under the master's finger, after which
      // no further pointer movement did anything at all.
      final DateTime external = DateTime(2026, 10, 15);
      late double pageAtInterrupt;
      await continuousDrag(
        tester,
        deltas: List<double>.filled(7, -100),
        afterMove: (int index) async {
          if (index != 2) return;
          host.selectExternally(external);
          await tester.pump();
          pageAtInterrupt = pagerPage(tester);
        },
      );

      expect(
        pageAtInterrupt,
        lessThan(_pageForDay(today, external).toDouble()),
        reason:
            'the external selection yanked the pager to its own month while '
            'the drag was still live — jumpTo\'s goIdle() cancelled the '
            'master\'s gesture mid-stroke',
      );
      expect(
        pageAtInterrupt,
        greaterThan(_pageForDay(today, today).toDouble()),
        reason:
            'fixture guard: the drag had not moved the pager at all by the '
            'time the external selection landed, so the assertion above '
            'proves nothing',
      );

      // Standing down mid-drag cannot STRAND the pager, because the
      // push-OUT half of the sync repairs it at settle: the delta is computed
      // against the CURRENT month, so wherever the gesture landed becomes
      // the selection.
      expect(steps, hasLength(1));
      expect(
        pagerPage(tester),
        _pageForDay(today, host.selectedDay),
        reason:
            'the pager and the selection disagree after the gesture settled '
            '— the pager has been stranded on a month the host never '
            'selected',
      );
    },
  );

  // ── mobile-perf LOW (finding #3): the collapsed grid builds nothing ──────
  //
  // The gate deliberately sits on the per-page CONTENT, never on the
  // `PageView`. The two tests below pin both halves of that choice: the
  // expensive part really is gone at rest, AND the pager it hangs off stays
  // attached, which is what makes the `Offstage`/`Visibility` stranding
  // failure mode unreachable rather than merely unlikely.

  testWidgets(
    'the collapsed panel builds NO month grid, while the pager itself stays '
    'mounted and laid out',
    (tester) async {
      await pumpCollapsed(tester, onStep: (int _) {});

      expect(
        find.byType(MonthCalendar),
        findsNothing,
        reason:
            'the invisible collapsed grid is still being built — 31 keyed '
            '_DayCells, each an AnimatedContainer with its own State, '
            'AnimationController and Ticker, laid out on every panel rebuild '
            'for something Opacity(0) never paints',
      );
      // The gate must NOT have taken the pager down with it: `page` is what
      // `didUpdateWidget` reads to decide whether the grid needs resyncing,
      // and it is null for a `PageController` with no laid-out viewport.
      expect(
        pagerPage(tester),
        _pageForDay(today, today).toDouble(),
        reason:
            'the month pager reports no page while collapsed — the gate has '
            'detached its viewport (Offstage/Visibility semantics), which is '
            'exactly the configuration that strands it on a stale month',
      );

      await toggle(tester);
      expect(
        find.byType(MonthCalendar),
        findsOneWidget,
        reason: 'expanding must bring the real grid back',
      );
    },
  );

  testWidgets(
    'a month change that lands while the panel is COLLAPSED is still on '
    'screen when it reopens — the gate cannot strand the pager',
    (tester) async {
      final _StepProbeHostState host = await pumpCollapsed(
        tester,
        onStep: (int _) {},
      );

      // A rail tap / «Сьогодні» / deep link crossing a month boundary while
      // the grid is gated off. `didUpdateWidget` resyncs the pager through
      // `jumpToPage`, which only works because the controller still has
      // clients — the whole reason the gate is on the content.
      host.selectExternally(DateTime(2026, 11, 3));
      await tester.pumpAndSettle();

      expect(
        pagerPage(tester),
        _pageForDay(today, DateTime(2026, 11, 3)).toDouble(),
        reason:
            'the pager did not follow a selection made while collapsed — it '
            'is stranded on the pre-change month and the master will reopen '
            'the calendar onto the wrong grid',
      );

      await toggle(tester);
      expect(
        tester.widget<MonthCalendar>(find.byType(MonthCalendar)).visibleMonth,
        DateTime(2026, 11),
        reason: 'the reopened grid renders a month the selection does not name',
      );
    },
  );
}
