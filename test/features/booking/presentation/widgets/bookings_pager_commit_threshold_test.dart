// mobile-qa (2026-08-14) — the low-threshold page-commit fix has NO test
// pinning the threshold itself. `LowThresholdPageScrollPhysics` lowers the
// position-only (paused-before-lift) commit fraction from stock
// `PageScrollPhysics`'s 0.5 to `kPageCommitFraction` (0.25) — see that
// class's doc for the full root cause (a mismatch between the fling branch's
// generous ±0.5-page nudge and the position-only branch's half-viewport
// requirement, which is what made the «Мої записи» month grid and week rail
// feel "strange, and not easy" to swipe).
//
// Every existing drag test either goes well PAST both thresholds (60% of
// width, matching `integration_test/support/pager_drag.dart`'s recipe) or
// never asserts a settle destination at all
// (`bookings_month_calendar_panel_rail_paging_test.dart`'s "MID-DRAG mounts
// two months" case calls `gesture.up()` with no assertion on where it
// lands). So a revert to stock `PageScrollPhysics` at either call site would
// leave the whole suite green. This file is the guard that closes that gap,
// for BOTH pagers the fix touched.
//
// WHY EVERY DRAG HERE PAUSES BEFORE `up()`
// -----------------------------------------
// The threshold this fix changed lives ENTIRELY in `_getTargetPixels`'s
// position-only branch — the one that only runs when release `velocity` is
// below `tolerance.velocity` (~7px/s). A `tester.fling(...)` or a drag
// released while still moving lands in the (unchanged) velocity branch
// instead and would prove nothing about this fix. Every drag below ends with
// a pump PAST `VelocityTracker`'s own 40ms "assume stopped" cutoff with NO
// further pointer sample before `up()`, so `getVelocityEstimate()`
// short-circuits to an EXACT-ZERO estimate (see `_pausedDrag`'s doc for why
// a trailing run of zero-delta samples was tried first and rejected — it
// produced a sign-reversed, not zero, velocity empirically) — landing the
// gesture in the branch this fix actually touched.
//
// DIRECTION COVERAGE — both ways, on purpose
// -----------------------------------------
// `LowThresholdPageScrollPhysics._getTargetPixels`'s position-only branch
// used to read `velocity`'s sign to pick a direction. At the exact
// `velocity == 0.0` every drag here produces, `0.0 >= 0` is always true, so
// the OLD code unconditionally applied the forward rule regardless of which
// way the finger actually moved — a backward drag past the threshold would
// spring back to where it started instead of committing. The fix reads
// `ScrollPosition.userScrollDirection` instead (set on every drag update,
// unaffected by the pause) — see `low_threshold_page_scroll_physics.dart`'s
// class doc for the full mapping. Every case below is mirrored in BOTH
// directions so a regression to the old `velocity >= 0` check goes red on
// the backward cases while the forward cases (which happened to work by
// accident, since `velocity >= 0` is also what forward wants) stay green.
//
// 8 real 40ms-spaced samples before the pause on every drag — never fewer:
// `integration_test/support/pager_drag.dart`'s "THE STEPS=4 REGRESSION" note
// records `PageController.page` FREEZING mid-drag with only 4 samples,
// independent of total distance, which would misreport a spring-back that
// never actually happened.
//
// HARNESS: mirrors `bookings_month_calendar_panel_rail_paging_test.dart`'s
// `_PanelHost` — a real `BookingsMonthCalendarPanel` (the actual production
// widget, not a stand-in), fed callbacks that record what fired. The month
// grid is reached by expanding the panel first (`_kPanelHandoffT` gates the
// grid's `IgnorePointer` at t=0.45 — see `bookings_month_calendar_panel.dart`);
// the rail is reached directly, collapsed, exactly as it renders by default.
// Both pagers start their `PageController` well clear of either page-index
// extreme (`_kMonthPageSpan` months / `kBookingsDayRailWeekSpan` weeks either
// side of the anchor), so a backward drag always has somewhere to land.

import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_month_calendar_panel.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/low_threshold_page_scroll_physics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

/// Mid-July 2026 — a Wednesday, mid-month, matching the sibling paging
/// test's fixture so both files exercise the same rail/grid geometry.
final DateTime _today = DateTime(2026, 7, 15);

const Key _railKey = Key('master-bookings-day-rail');
const Key _gridKey = Key('bookings-month-calendar-grid');
const Key _toggleKey = Key('bookings-month-calendar-toggle');

class _PanelHost extends StatefulWidget {
  const _PanelHost({required this.onStepMonth});

  final ValueChanged<int> onStepMonth;

  @override
  State<_PanelHost> createState() => _PanelHostState();
}

class _PanelHostState extends State<_PanelHost> {
  late DateTime selectedDay = _today;

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
      onSelectRailDay: (DateTime d) => setState(() => selectedDay = d),
      onSelectDay: (DateTime d) => setState(() => selectedDay = d),
      onStepMonth: (int delta) {
        widget.onStepMonth(delta);
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

/// A paused-before-lift drag of [fraction] of [pagerKey]'s own width, in the
/// direction [forward] indicates (`true` = pages towards a higher index,
/// `false` = towards a lower one). See the file header for why every drag
/// here pauses before `up()`, and for why both directions matter.
///
/// [expectReachedAboveThreshold] is a MID-DRAG fixture guard, checked right
/// after the directional moves (before the pause), comparing the ACTUAL
/// distance travelled (after the recognizer's own touch-slop, measured
/// empirically at ~27–40px on this pager's ~800px width, i.e. roughly 3–5
/// fractional points, not a fixed ratio of the requested fraction) against
/// [thresholdFraction]. A `fraction:` chosen too close to the threshold can
/// therefore land on the WRONG side of it once slop is subtracted, silently
/// testing something other than what the test name claims. This guard fails
/// LOUDLY with the actual reached figure instead of letting that happen
/// quietly — it is why the `kPageCommitFraction`-boundary call sites below
/// use 0.30/0.20 rather than a tighter 0.26/0.24.
///
/// Returns the settled `PageController.page` fraction actually reached
/// (before the pause/release), so callers can add extra guards of their own
/// (e.g. asserting a past-50% drag genuinely cleared 50%).
Future<double> _pausedDrag(
  WidgetTester tester,
  Key pagerKey, {
  required double fraction,
  required bool forward,
  required bool expectReachedAboveThreshold,
  double thresholdFraction = kPageCommitFraction,
}) async {
  final Finder finder = find.byKey(pagerKey);
  final double width = tester.getRect(finder).width;
  const int steps = 8;
  final double magnitude = (width * fraction) / steps;
  final double dx = forward ? -magnitude : magnitude;

  final TestGesture gesture = await tester.startGesture(
    tester.getCenter(finder),
  );
  Duration stamp = Duration.zero;
  for (int i = 0; i < steps; i++) {
    stamp += const Duration(milliseconds: 40);
    await gesture.moveBy(Offset(dx, 0), timeStamp: stamp);
    // fixed-wait-ok: advancing the pointer-sample clock in lockstep with the
    // synthetic move timestamps, not waiting on a condition.
    await tester.pump(const Duration(milliseconds: 40));
  }

  final double reachedPage = tester.widget<PageView>(finder).controller!.page!;
  // The pager always starts resting on an exact integer page, so whichever
  // direction it moved, the OTHER rounding function recovers that starting
  // page and the difference is the actual distance travelled.
  final double travelled = forward
      ? reachedPage - reachedPage.floorToDouble()
      : reachedPage.ceilToDouble() - reachedPage;
  expect(
    travelled > thresholdFraction,
    expectReachedAboveThreshold,
    reason:
        'fixture guard: requested fraction $fraction actually reached '
        '${travelled.toStringAsFixed(4)} of the viewport after touch-slop — '
        'that is on the ${travelled > thresholdFraction ? "OVER" : "UNDER"} '
        'side of the ${thresholdFraction.toStringAsFixed(2)} threshold when '
        'this test expected the '
        '${expectReachedAboveThreshold ? "OVER" : "UNDER"} side. The outcome '
        'assertion below would not be testing what this test\'s name claims.',
  );
  // The pause: let MORE than VelocityTracker's own 40ms
  // "_assumePointerMoveStoppedMilliseconds" window elapse with NO further
  // pointer sample before release. `VelocityTracker.getVelocityEstimate()`
  // short-circuits to an EXACT-ZERO estimate once more than 40ms has passed
  // since the last recorded sample (`velocity_tracker.dart`), rather than
  // extrapolating a residual — and, worse, potentially SIGN-REVERSED —
  // velocity from a quadratic least-squares fit over the deceleration. A
  // trailing run of zero-delta `moveBy` samples was tried first and produced
  // exactly that reversal empirically (both "over 25%" cases sprang back
  // instead of committing); waiting past the tracker's own cutoff instead of
  // feeding it more samples is what actually lands a clean zero. This relies
  // on the test binding's `debugSamplingClock` staying synchronised with
  // `FakeAsync`, which is exactly what `GestureBinding.samplingClock`'s own
  // doc states it does under test.
  // fixed-wait-ok: advancing past VelocityTracker's own 40ms
  // "assume stopped" cutoff, not waiting on a condition.
  await tester.pump(const Duration(milliseconds: 60));
  await gesture.up();
  await tester.pumpAndSettle();
  return reachedPage;
}

void main() {
  group('month grid — paused-release commit threshold', () {
    testWidgets(
      'a paused release just OVER 25% of the viewport commits to the next '
      'month',
      (tester) async {
        final List<int> steps = <int>[];
        await tester.pumpApp(_PanelHost(onStepMonth: steps.add));
        await tester.tap(find.byKey(_toggleKey));
        await tester.pumpAndSettle();

        await _pausedDrag(
          tester,
          _gridKey,
          fraction: 0.30,
          forward: true,
          expectReachedAboveThreshold: true,
        );

        expect(
          steps,
          <int>[1],
          reason:
              'a paused release past kPageCommitFraction (0.25) must commit '
              'to the next month — got $steps. If this reverted to stock '
              'PageScrollPhysics (0.5 threshold), a 27% drag would spring '
              'back instead and this list would be empty.',
        );
      },
    );

    testWidgets(
      'a paused release just UNDER 25% of the viewport springs back to the '
      'same month',
      (tester) async {
        final List<int> steps = <int>[];
        await tester.pumpApp(_PanelHost(onStepMonth: steps.add));
        await tester.tap(find.byKey(_toggleKey));
        await tester.pumpAndSettle();

        await _pausedDrag(
          tester,
          _gridKey,
          fraction: 0.20,
          forward: true,
          expectReachedAboveThreshold: false,
        );

        expect(
          steps,
          isEmpty,
          reason:
              'a paused release short of kPageCommitFraction (0.25) must '
              'spring back to the month it started on — got $steps.',
        );
      },
    );

    testWidgets(
      'a paused BACKWARD release just OVER 25% of the viewport commits to '
      'the previous month',
      (tester) async {
        // Pins the direction-asymmetry bug directly: at velocity == 0.0 the
        // old `velocity >= 0` direction check always took the forward arm,
        // so this exact drag used to spring back to the starting month
        // instead of committing to the previous one.
        final List<int> steps = <int>[];
        await tester.pumpApp(_PanelHost(onStepMonth: steps.add));
        await tester.tap(find.byKey(_toggleKey));
        await tester.pumpAndSettle();

        await _pausedDrag(
          tester,
          _gridKey,
          fraction: 0.30,
          forward: false,
          expectReachedAboveThreshold: true,
        );

        expect(
          steps,
          <int>[-1],
          reason:
              'a paused BACKWARD release past kPageCommitFraction (0.25) '
              'must commit to the previous month — got $steps. Before the '
              'fix, `velocity >= 0` at the exact zero this branch runs at '
              'always read "forward", so this drag sprang back to the '
              'starting month instead.',
        );
      },
    );

    testWidgets(
      'a paused BACKWARD release just UNDER 25% of the viewport springs '
      'back to the same month',
      (tester) async {
        final List<int> steps = <int>[];
        await tester.pumpApp(_PanelHost(onStepMonth: steps.add));
        await tester.tap(find.byKey(_toggleKey));
        await tester.pumpAndSettle();

        await _pausedDrag(
          tester,
          _gridKey,
          fraction: 0.20,
          forward: false,
          expectReachedAboveThreshold: false,
        );

        expect(
          steps,
          isEmpty,
          reason:
              'a paused BACKWARD release short of kPageCommitFraction (0.25) '
              'must spring back to the month it started on — got $steps.',
        );
      },
    );

    testWidgets(
      'a paused FORWARD release past 50% of the viewport still commits '
      'forward, not backward',
      (tester) async {
        // Pins the "past-50%" trap: a direction rule derived purely from the
        // fractional page (rather than the actual drag direction) reads a
        // >50% forward drag as an almost-committed backward excursion and
        // would wrongly spring back. Direction here comes from
        // `userScrollDirection`, never from `fraction`, so it must not.
        final List<int> steps = <int>[];
        await tester.pumpApp(_PanelHost(onStepMonth: steps.add));
        await tester.tap(find.byKey(_toggleKey));
        await tester.pumpAndSettle();

        await _pausedDrag(
          tester,
          _gridKey,
          fraction: 0.60,
          forward: true,
          expectReachedAboveThreshold: true,
          thresholdFraction: 0.5,
        );

        expect(
          steps,
          <int>[1],
          reason:
              'a paused release past 50% of the viewport, forward, must '
              'commit to the next month — got $steps.',
        );
      },
    );

    testWidgets(
      'a paused BACKWARD release past 50% of the viewport still commits '
      'backward, not forward',
      (tester) async {
        final List<int> steps = <int>[];
        await tester.pumpApp(_PanelHost(onStepMonth: steps.add));
        await tester.tap(find.byKey(_toggleKey));
        await tester.pumpAndSettle();

        await _pausedDrag(
          tester,
          _gridKey,
          fraction: 0.60,
          forward: false,
          expectReachedAboveThreshold: true,
          thresholdFraction: 0.5,
        );

        expect(
          steps,
          <int>[-1],
          reason:
              'a paused BACKWARD release past 50% of the viewport must '
              'commit to the previous month, not spring back or overshoot '
              'to the one after — got $steps.',
        );
      },
    );

    testWidgets(
      'the velocity (fling) branch is UNCHANGED — a fast flick well under '
      '25% still commits',
      (tester) async {
        // Confirms the fix is scoped to the position-only branch, per the
        // class doc's "velocity branch is intentionally untouched". A fling
        // covering far less distance than the position-only threshold must
        // still page, exactly as stock PageScrollPhysics always has.
        final List<int> steps = <int>[];
        await tester.pumpApp(_PanelHost(onStepMonth: steps.add));
        await tester.tap(find.byKey(_toggleKey));
        await tester.pumpAndSettle();

        final double width = tester.getRect(find.byKey(_gridKey)).width;
        expect(
          width * 0.1,
          lessThan(width * 0.25),
          reason:
              'fixture guard: the fling distance below must sit well '
              'under kPageCommitFraction for this test to mean anything',
        );
        await tester.fling(find.byKey(_gridKey), Offset(-width * 0.1, 0), 800);
        await tester.pumpAndSettle();

        expect(
          steps,
          <int>[1],
          reason:
              'a fast flick covering only 10% of the viewport must still '
              'commit via the velocity branch — that branch is untouched by '
              'this fix and must keep behaving exactly as stock '
              'PageScrollPhysics always has',
        );
      },
    );
  });

  group('day rail — paused-release commit threshold', () {
    /// The rail's own settled page, read off the mounted [BookingsDayRail].
    int settledRailPage(WidgetTester tester) => tester
        .widget<BookingsDayRail>(find.byType(BookingsDayRail))
        .controller
        .page!
        .round();

    testWidgets(
      'a paused release just OVER 25% of the viewport commits to the next '
      'week',
      (tester) async {
        await tester.pumpApp(_PanelHost(onStepMonth: (_) {}));
        final int startPage = settledRailPage(tester);

        await _pausedDrag(
          tester,
          _railKey,
          fraction: 0.30,
          forward: true,
          expectReachedAboveThreshold: true,
        );

        expect(
          settledRailPage(tester),
          startPage + 1,
          reason:
              'a paused release past kPageCommitFraction (0.25) must land '
              'the rail on the NEXT week. If this reverted to stock '
              'PageScrollPhysics (0.5 threshold), a 27% drag would spring '
              'back to page $startPage instead.',
        );
      },
    );

    testWidgets(
      'a paused release just UNDER 25% of the viewport springs back to the '
      'same week',
      (tester) async {
        await tester.pumpApp(_PanelHost(onStepMonth: (_) {}));
        final int startPage = settledRailPage(tester);

        await _pausedDrag(
          tester,
          _railKey,
          fraction: 0.20,
          forward: true,
          expectReachedAboveThreshold: false,
        );

        expect(
          settledRailPage(tester),
          startPage,
          reason:
              'a paused release short of kPageCommitFraction (0.25) must '
              'spring back to the week it started on.',
        );
      },
    );

    testWidgets(
      'a paused BACKWARD release just OVER 25% of the viewport commits to '
      'the previous week',
      (tester) async {
        // Pins the direction-asymmetry bug directly — see the matching
        // month-grid case above for the full explanation.
        await tester.pumpApp(_PanelHost(onStepMonth: (_) {}));
        final int startPage = settledRailPage(tester);

        await _pausedDrag(
          tester,
          _railKey,
          fraction: 0.30,
          forward: false,
          expectReachedAboveThreshold: true,
        );

        expect(
          settledRailPage(tester),
          startPage - 1,
          reason:
              'a paused BACKWARD release past kPageCommitFraction (0.25) '
              'must land the rail on the PREVIOUS week. Before the fix, '
              '`velocity >= 0` at the exact zero this branch runs at always '
              'read "forward", so this drag sprang back to page $startPage '
              'instead.',
        );
      },
    );

    testWidgets(
      'a paused BACKWARD release just UNDER 25% of the viewport springs '
      'back to the same week',
      (tester) async {
        await tester.pumpApp(_PanelHost(onStepMonth: (_) {}));
        final int startPage = settledRailPage(tester);

        await _pausedDrag(
          tester,
          _railKey,
          fraction: 0.20,
          forward: false,
          expectReachedAboveThreshold: false,
        );

        expect(
          settledRailPage(tester),
          startPage,
          reason:
              'a paused BACKWARD release short of kPageCommitFraction (0.25) '
              'must spring back to the week it started on.',
        );
      },
    );

    testWidgets(
      'a paused FORWARD release past 50% of the viewport still commits '
      'forward, not backward',
      (tester) async {
        // Pins the "past-50%" trap on the rail too — see the matching
        // month-grid case above for the full explanation.
        await tester.pumpApp(_PanelHost(onStepMonth: (_) {}));
        final int startPage = settledRailPage(tester);

        await _pausedDrag(
          tester,
          _railKey,
          fraction: 0.60,
          forward: true,
          expectReachedAboveThreshold: true,
          thresholdFraction: 0.5,
        );

        expect(
          settledRailPage(tester),
          startPage + 1,
          reason:
              'a paused release past 50% of the viewport, forward, must '
              'land the rail on the NEXT week.',
        );
      },
    );

    testWidgets(
      'a paused BACKWARD release past 50% of the viewport still commits '
      'backward, not forward',
      (tester) async {
        await tester.pumpApp(_PanelHost(onStepMonth: (_) {}));
        final int startPage = settledRailPage(tester);

        await _pausedDrag(
          tester,
          _railKey,
          fraction: 0.60,
          forward: false,
          expectReachedAboveThreshold: true,
          thresholdFraction: 0.5,
        );

        expect(
          settledRailPage(tester),
          startPage - 1,
          reason:
              'a paused BACKWARD release past 50% of the viewport must land '
              'the rail on the PREVIOUS week, not spring back or overshoot '
              'past it.',
        );
      },
    );
  });
}
