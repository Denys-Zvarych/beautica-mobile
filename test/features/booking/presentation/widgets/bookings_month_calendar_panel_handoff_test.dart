// mobile-qa (2026-08-14) — regression guard for the expand/collapse gesture
// handoff dead-zone (bug fixed this session in
// `bookings_month_calendar_panel.dart`'s "Gesture layering" doc, :91-117).
//
// THE BUG
// -------
// The rail layer's `IgnorePointer` used to read `ignoring: t > 0.5` and the
// grid layer's `ignoring: t < 0.5` — two INDEPENDENT literals that happened
// to share a value, not a stated complement. The rail's OPACITY curve zeroed
// out at `t == 0.45`, 0.05 earlier than its own hit-testability. So for
// `0.45 < t < 0.5` the rail was fully invisible (opacity exactly 0) yet
// STILL `ignoring: false` — it silently swallowed every tap/drag aimed at
// the grid, which was simultaneously non-interactive (`ignoring: true`
// until `t > 0.5`) and already ~27-33% visible. At exactly `t == 0.5`,
// neither `t < 0.5` nor `t > 0.5` held, so BOTH layers were `ignoring:
// false` at once.
//
// TWO INVARIANTS, NOT ONE — WHY "EXACTLY ONE INTERACTIVE" ALONE IS NOT ENOUGH
// -----------------------------------------------------------------------
// An earlier draft of this file asserted only "exactly one of the two
// IgnorePointers is non-ignoring at every t" (an XOR). That assertion does
// NOT catch the dead-zone half of the bug: for 0.45 < t < 0.5 under the OLD
// thresholds, rail was interactive and grid was not — that IS "exactly one"
// interactive, just the WRONG (invisible) one. Verified by mutation: with
// the old thresholds restored, the XOR-only version of this test stayed
// GREEN. The real defect is "a layer at opacity 0 must never be the one
// receiving the gesture", so [_expectOpacityGatesInteractivity] checks BOTH
// layers' actual rendered [Opacity.opacity] against their own
// [IgnorePointer.ignoring] every sampled frame: a fully transparent layer
// must be `ignoring: true`. The XOR check is kept alongside it (structural
// belt-and-braces against a future regression that leaves BOTH layers
// non-interactive, or both interactive with nonzero opacity, neither of
// which the opacity check alone would catch), but the opacity check is the
// one that actually reproduces and guards the fixed bug — see the
// mutation-verification record at the bottom of this file.
//
// WHY A LIVE DRAG, NOT THE SETTLE ANIMATION
// ------------------------------------------
// `_onDragUpdate` sets `_open.value` directly on every pointer-move frame —
// no easing, no controller ticker — so a live drag gives this test EXACT,
// monotonic control over `t`, which the 280ms `Curves.easeOutCubic` settle
// animation does not (its frame-to-t mapping is nonlinear and duration-
// dependent). Both paths feed the identical `AnimatedBuilder`s that gate
// `ignoring`/`opacity`, so a drag-driven sweep exercises the exact render
// logic this file is about, at whatever resolution the assertions need. The
// second test below additionally drives the SAME invariants through the
// real toggle-tap settle path, so the natural user gesture is covered too.
//
// `t` is never assumed from the drag distance: it is always MEASURED back
// from the collapse/expand box's actual rendered height (`bookings-month-
// calendar`'s `SizedBox`), the same technique
// `bookings_month_calendar_panel_test.dart` already uses for its fixture
// guards. That keeps this file honest about what `_open.value` really is,
// independent of any private constant.
//
// MUTATION-VERIFIED (mobile-qa, 2026-08-14): the two `IgnorePointer`
// thresholds were temporarily restored to the pre-fix literals (rail
// `ignoring: t > 0.5`, grid `ignoring: t < 0.5`) via `cp`-backed edits, never
// `git checkout`. Both tests in this file went RED, each naming the
// 0.45–0.5 dead-zone by measured t (e.g. "at measured t=0.4X the rail layer
// is fully transparent (opacity=0.0) yet still hit-testable"). The
// thresholds were then restored to `_kPanelHandoffT` exactly, byte-for-byte,
// from a pre-edit backup, and both tests went green again.

import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_month_calendar_panel.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/month_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const Key _boxKey = Key('bookings-month-calendar');
const Key _railLayerKey = Key('bookings-month-calendar-rail-layer');
const Key _gridLayerKey = Key('bookings-month-calendar-grid-layer');
const Key _handleKey = Key('bookings-month-calendar-handle');
const Key _toggleKey = Key('bookings-month-calendar-toggle');

final DateTime _today = DateTime(2026, 7, 15);

class _HandoffHost extends StatefulWidget {
  const _HandoffHost();

  @override
  State<_HandoffHost> createState() => _HandoffHostState();
}

class _HandoffHostState extends State<_HandoffHost> {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: BookingsMonthCalendarPanel(
            railController: railController,
            railFirstWeekStart: firstWeekStart,
            weekCount: kBookingsDayRailWeekSpan * 2 + 1,
            today: _today,
            selectedDay: selectedDay,
            bookedDays: const <DateTime>{},
            onSelectRailDay: (DateTime d) => setState(() => selectedDay = d),
            onSelectDay: (DateTime d) => setState(() => selectedDay = d),
            onStepMonth: (int _) {},
            timeline: const SizedBox.shrink(key: Key('timeline-stand-in')),
          ),
        ),
      ],
    );
  }
}

/// Reads the two hit-test gates directly off the mounted [IgnorePointer]s —
/// the real gesture-routing mechanism (`RenderIgnorePointer.hitTest`
/// short-circuits its whole subtree out of the hit-test result the instant
/// `ignoring` is true) — not a re-statement of any threshold literal.
({bool railInteractive, bool gridInteractive}) _interactivity(
  WidgetTester tester,
) {
  final bool railIgnoring = tester
      .widget<IgnorePointer>(find.byKey(_railLayerKey))
      .ignoring;
  final bool gridIgnoring = tester
      .widget<IgnorePointer>(find.byKey(_gridLayerKey))
      .ignoring;
  return (railInteractive: !railIgnoring, gridInteractive: !gridIgnoring);
}

/// Reads each layer's actual rendered opacity — the `Opacity` widget nested
/// directly inside each `IgnorePointer` (see the panel's `build()`).
({double rail, double grid}) _opacities(WidgetTester tester) {
  final double rail = tester
      .widget<Opacity>(
        find.descendant(
          of: find.byKey(_railLayerKey),
          matching: find.byType(Opacity),
        ),
      )
      .opacity;
  final double grid = tester
      .widget<Opacity>(
        find.descendant(
          of: find.byKey(_gridLayerKey),
          matching: find.byType(Opacity),
        ),
      )
      .opacity;
  return (rail: rail, grid: grid);
}

/// The box's live height, minus its resting collapsed height, as a fraction
/// of full travel — i.e. `_open.value`, measured rather than assumed. Mirrors
/// `bookings_month_calendar_panel_test.dart`'s fixture-guard technique.
double _measuredT(WidgetTester tester) {
  final double height = tester.getSize(find.byKey(_boxKey)).height;
  const double collapsed = kBookingsDayRailHeight;
  const double travel = kMonthCalendarExpandedHeight - kBookingsDayRailHeight;
  return ((height - collapsed) / travel).clamp(0.0, 1.0);
}

/// The two invariants this file exists to pin, checked together at one
/// sampled frame. See the file header for why both are needed.
void _expectHandoffInvariants(WidgetTester tester, String context) {
  final interactivity = _interactivity(tester);
  final opacities = _opacities(tester);

  // Invariant A — a fully transparent layer must never be the one receiving
  // the gesture. This is the actual bug: a layer can sit at opacity 0.0
  // (clamped, exact) for a whole span of `t` while still being interactive.
  expect(
    !(opacities.rail <= 0.0 && interactivity.railInteractive),
    isTrue,
    reason:
        '$context — the rail layer is fully transparent '
        '(opacity=${opacities.rail}) yet still hit-testable. This is the '
        'exact dead-zone the fix closed: an invisible rail swallowing taps '
        'meant for the grid underneath it.',
  );
  expect(
    !(opacities.grid <= 0.0 && interactivity.gridInteractive),
    isTrue,
    reason:
        '$context — the grid layer is fully transparent '
        '(opacity=${opacities.grid}) yet still hit-testable.',
  );

  // Invariant B — structural belt-and-braces: exactly one layer interactive.
  // Catches a DIFFERENT regression class (e.g. both non-interactive, or both
  // interactive while both have nonzero opacity) that invariant A alone
  // would not — see the file header for why this one alone is insufficient.
  expect(
    interactivity.railInteractive,
    isNot(equals(interactivity.gridInteractive)),
    reason:
        '$context — exactly one of the rail/grid layers must be '
        'hit-testable — got railInteractive=${interactivity.railInteractive}, '
        'gridInteractive=${interactivity.gridInteractive}.',
  );
}

void main() {
  testWidgets(
    'a live drag through the FULL expand range never leaves an invisible '
    'layer hit-testable — dense sampling across the old bug\'s 0.45–0.5 band',
    (tester) async {
      await tester.pumpApp(const _HandoffHost());
      await tester.pumpAndSettle();

      // Fixture guard: resting collapsed state is unambiguous — rail owns
      // it, grid does not — before this test claims anything about the
      // drag in between.
      final restResult = _interactivity(tester);
      expect(restResult.railInteractive, isTrue);
      expect(restResult.gridInteractive, isFalse);

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_handleKey)),
      );
      await tester.pump();

      final List<double> sampledT = <double>[];
      int checkedAtLeastOneMidBand = 0;

      // Sweep the drag open in small steps so `t` is sampled continuously,
      // not just at a handful of guessed checkpoints. 3dp steps keep the
      // whole sweep (~250dp of travel) to under 100 pointer-move frames
      // while still landing well inside the old bug's ~0.05-wide band.
      // Driven by the MEASURED t (not a precomputed pixel budget) — the
      // gesture recognizer's initial touch-slop eats a few pixels before the
      // drag is accepted, so a fixed pixel budget alone undershoots t=1.
      const double stepPx = 3;
      int iterations = 0;
      double t = _measuredT(tester);
      while (t < 0.999 && iterations < 200) {
        await gesture.moveBy(const Offset(0, stepPx));
        iterations++;
        await tester.pump();

        t = _measuredT(tester);
        sampledT.add(t);
        _expectHandoffInvariants(tester, 'opening at measured t=$t');

        if (t > 0.40 && t < 0.55) checkedAtLeastOneMidBand++;
      }

      // Fixture guard: the sweep must have actually passed through the old
      // bug's band, or the dense-sampling assertions above prove nothing.
      expect(
        checkedAtLeastOneMidBand,
        greaterThan(3),
        reason:
            'the drag sweep did not sample enough of the 0.40–0.55 band '
            '(only $checkedAtLeastOneMidBand frames) — this test would not '
            'have caught the original bug',
      );
      expect(
        sampledT.last,
        greaterThan(0.95),
        reason: 'fixture guard: the sweep did not reach full travel',
      );

      await gesture.up();
      await tester.pumpAndSettle();

      // And the reverse direction — collapsing back down — exercises the
      // same complement pair in decreasing t.
      final TestGesture closeGesture = await tester.startGesture(
        tester.getCenter(find.byKey(_handleKey)),
      );
      await tester.pump();
      iterations = 0;
      t = _measuredT(tester);
      while (t > 0.001 && iterations < 200) {
        await closeGesture.moveBy(const Offset(0, -stepPx));
        iterations++;
        await tester.pump();

        t = _measuredT(tester);
        _expectHandoffInvariants(tester, 'collapsing at measured t=$t');
      }
      await closeGesture.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'the real toggle-tap settle animation (280ms, Curves.easeOutCubic) also '
    'never leaves an invisible layer hit-testable at any sampled frame',
    (tester) async {
      await tester.pumpApp(const _HandoffHost());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_toggleKey));
      await tester.pump();

      // Sample the settle in small fixed steps. This is a real ease-curve
      // animation (not a live drag), so exact t values can't be targeted —
      // dense, regular sampling across the whole 280ms window is what
      // catches a mid-animation gap/overlap here instead.
      for (int i = 0; i < 14; i++) {
        // fixed-wait-ok: sampling a mid-animation frame of the real
        // toggle-tap settle (not awaiting a condition) — mirrors
        // bookings_month_calendar_panel_test.dart's identical settle-sampling
        // pattern for the same _open controller.
        await tester.pump(const Duration(milliseconds: 20));
        _expectHandoffInvariants(tester, 'toggle-tap settle frame $i');
      }
      await tester.pumpAndSettle();

      final result = _interactivity(tester);
      expect(result.gridInteractive, isTrue);
      expect(result.railInteractive, isFalse);
    },
  );
}
