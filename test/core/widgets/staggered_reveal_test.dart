// Phase 236 — the promoted public [StaggeredReveal].
//
// The widget was lifted out of `home_hub_screen.dart` unchanged, so the
// behaviour these cases pin is the behaviour the hub already shipped. They
// exist here because the two former call sites now share ONE implementation and
// nothing else asserts it directly: `home_hub_reveal_lifecycle_test.dart`
// covers the memoization/disposal half through the hub screen, and the
// placeholders had no coverage of their own at all.

import 'package:beautica_mobile/core/widgets/staggered_reveal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

/// Builds a body with three slots on non-overlapping, ascending intervals.
Widget _threeSlots() {
  return StaggeredReveal(
    builder: (BuildContext context, RevealFn reveal) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          reveal(
            start: 0.0,
            end: 0.2,
            child: const SizedBox(key: Key('slot-a'), height: 20, width: 20),
          ),
          reveal(
            start: 0.4,
            end: 0.6,
            child: const SizedBox(key: Key('slot-b'), height: 20, width: 20),
          ),
          reveal(
            start: 0.8,
            end: 1.0,
            child: const SizedBox(key: Key('slot-c'), height: 20, width: 20),
          ),
        ],
      );
    },
  );
}

Animation<double> _animationOf(WidgetTester tester, String slotKey) {
  final FadeTransition fade = tester.widget<FadeTransition>(
    find
        .ancestor(
          of: find.byKey(Key(slotKey)),
          matching: find.byType(FadeTransition),
        )
        .first,
  );
  return fade.opacity;
}

double _opacityOf(WidgetTester tester, String slotKey) =>
    _animationOf(tester, slotKey).value;

void main() {
  testWidgets('reveals in interval order', (WidgetTester tester) async {
    await tester.pumpApp(_threeSlots());
    // The controller starts from a post-frame callback, so one more pump is
    // needed before it is running.
    await tester.pump();

    // At ~25% of the 1000ms entrance: slot A's interval (0.0-0.2) is complete,
    // B's (0.4-0.6) has not opened, C's (0.8-1.0) is nowhere near.
    // Pumping until a condition would defeat the purpose: the property under
    // test is WHEN each slot reveals, not THAT it eventually does.
    // t=0.25 IS the assertion: slot A's interval has closed, B's has not.
    // fixed-wait-ok: an exact point on the entrance timeline, not a wait.
    await tester.pump(const Duration(milliseconds: 250));
    final double a1 = _opacityOf(tester, 'slot-a');
    final double b1 = _opacityOf(tester, 'slot-b');
    final double c1 = _opacityOf(tester, 'slot-c');

    expect(a1, 1.0, reason: 'slot A finishes at t=0.2');
    expect(b1, 0.0, reason: 'slot B has not started at t=0.25');
    expect(c1, 0.0, reason: 'slot C has not started at t=0.25');

    // At ~70%: B is done too, C still closed.
    // fixed-wait-ok: same reason — a specific point on the timeline.
    await tester.pump(const Duration(milliseconds: 450));
    expect(_opacityOf(tester, 'slot-b'), 1.0);
    expect(_opacityOf(tester, 'slot-c'), 0.0);

    // Settled: everything visible.
    // fixed-wait-ok: carries the controller past its 1000ms end.
    await tester.pump(const Duration(milliseconds: 400));
    expect(_opacityOf(tester, 'slot-a'), 1.0);
    expect(_opacityOf(tester, 'slot-b'), 1.0);
    expect(_opacityOf(tester, 'slot-c'), 1.0);
  });

  testWidgets('slides up as it fades, and lands at zero offset', (
    WidgetTester tester,
  ) async {
    await tester.pumpApp(_threeSlots());
    await tester.pump();
    // The point at which slot C's slide offset must still be at full distance,
    // i.e. before its 0.8-1.0 interval opens.
    // fixed-wait-ok: t=0.25 is the assertion, not a wait for work to finish.
    await tester.pump(const Duration(milliseconds: 250));

    final SlideTransition slideC = tester.widget<SlideTransition>(
      find
          .ancestor(
            of: find.byKey(const Key('slot-c')),
            matching: find.byType(SlideTransition),
          )
          .first,
    );
    expect(
      slideC.position.value,
      const Offset(0, StaggeredReveal.slideFraction),
      reason: 'an unopened slot sits its full slide distance below',
    );

    // fixed-wait-ok: past the controller's 1000ms end, so the slide has landed.
    await tester.pump(const Duration(milliseconds: 900));
    expect(slideC.position.value, Offset.zero);
  });

  testWidgets('an off-screen (TickerMode false) subtree does not start', (
    WidgetTester tester,
  ) async {
    // The IndexedStack case: the client shell builds every branch at mount, so
    // without the gate FOUR off-screen 1s controllers are set running inside
    // the post-login frame budget.
    //
    // ASSERTING OPACITY HERE WOULD BE A TEST THAT CANNOT FAIL, and neither
    // does a frame-callback count. A muted ticker holds the controller at 0.0
    // AND schedules no tick whether or not `forward()` was ever called, so both
    // readings are identical on the gated and the ungated widget — both were
    // tried and both stayed green under the mutation.
    //
    // What DOES differ is the controller's STATUS. `AnimationController.forward()`
    // sets `AnimationStatus.forward` immediately, muted ticker or not, and
    // `CurvedAnimation` delegates `status` straight to its parent. A gated
    // widget has never called `forward()`, so its animation is still `dismissed`.
    await tester.pumpApp(TickerMode(enabled: false, child: _threeSlots()));
    await tester.pump();

    expect(
      _animationOf(tester, 'slot-a').status,
      AnimationStatus.dismissed,
      reason:
          'a hidden branch already started its entrance — the TickerMode gate '
          'is gone and every off-screen branch now animates at mount',
    );
    expect(_opacityOf(tester, 'slot-a'), 0.0);
  });

  testWidgets('and it plays in full the first time the branch is shown', (
    WidgetTester tester,
  ) async {
    // The other half of the gate: deferring must not LOSE the entrance.
    Widget host(bool visible) =>
        TickerMode(enabled: visible, child: _threeSlots());

    await tester.pumpApp(host(false));
    // A full entrance's worth of time must elapse with NOTHING happening.
    // fixed-wait-ok: the assertion is an ABSENCE — nothing to pump until.
    await tester.pump(const Duration(milliseconds: 900));
    expect(_opacityOf(tester, 'slot-c'), 0.0);

    // Tab switched to: TickerMode flips true, didChangeDependencies fires.
    await tester.pumpApp(host(true));
    await tester.pump();
    // fixed-wait-ok: past the controller's 1000ms end.
    await tester.pump(const Duration(milliseconds: 1100));

    expect(_opacityOf(tester, 'slot-a'), 1.0);
    expect(_opacityOf(tester, 'slot-c'), 1.0);
  });

  testWidgets('content is visible immediately when animations are disabled', (
    WidgetTester tester,
  ) async {
    // Reduced motion / a muted ticker means there may be no ticks at all. The
    // whole body is wrapped in reveal(), so without the short-circuit the page
    // would render permanently blank.
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: _threeSlots(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(_opacityOf(tester, 'slot-a'), 1.0);
    expect(_opacityOf(tester, 'slot-c'), 1.0);
  });
}
