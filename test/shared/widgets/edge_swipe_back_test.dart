// Widget tests for the [EdgeSwipeBack] left-edge swipe-back affordance
// (lib/shared/widgets/edge_swipe_back.dart).
//
// EdgeSwipeBack overlays a NARROW (20px) translucent GestureDetector strip on
// the LEFT edge of its [child]. A committed RIGHTWARD edge drag fires
// [onSwipeBack]; the strip is what keeps the gesture off the tabs' own
// horizontal scrollers (search filter rail, calendars) — a touch that starts
// mid-content never even hit-tests the detector.
//
// These tests pin the three invariants a regression would silently break:
//   • STRIP CONFINEMENT — a drag that STARTS mid-screen (outside the 20px strip)
//     must NOT fire, otherwise the gesture would steal in-tab horizontal scrolls.
//   • RIGHTWARD-ONLY — a leftward drag must NOT fire ("back" is rightward).
//   • THRESHOLDS — a rightward drag SHORT of both the 48px distance AND the
//     400px/s velocity thresholds must NOT fire; one past the distance threshold
//     fires EXACTLY once.
// Plus the `enabled` gating: false ⇒ the `Key('edge-swipe-back')` detector is
// absent (child still rendered), true ⇒ it is mounted.
//
// GESTURE MECHANICS: `tester.dragFrom` synthesises a NON-fling drag — its
// pointer moves carry no simulated time delta, so `primaryVelocity` resolves to
// ~0. That lets each drag isolate the DISTANCE path from the VELOCITY path: a
// 200px rightward `dragFrom` commits on distance alone; a 30px one falls short
// on BOTH. The start `Offset` (x=5 inside the strip vs x=400 mid-screen) selects
// whether the strip is hit at all.

import 'package:beautica_mobile/shared/widgets/edge_swipe_back.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The overlaid detector's stable test key (production: edge_swipe_back.dart).
  const Key detectorKey = Key('edge-swipe-back');
  // A key on the wrapped child so we can assert it renders in BOTH enabled
  // states (the widget promises [child] always occupies the stable children[0]
  // slot regardless of [enabled]).
  const Key childKey = Key('swipe-child');

  // Pumps a full-screen EdgeSwipeBack wired to [onSwipeBack]. The child is a
  // plain SizedBox.expand with NO gesture handlers of its own, so the ONLY thing
  // that can fire the callback is the edge strip — a callback firing therefore
  // proves the strip (not the child) handled the drag.
  Future<void> pumpEdgeSwipe(
    WidgetTester tester, {
    required bool enabled,
    required VoidCallback onSwipeBack,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EdgeSwipeBack(
            enabled: enabled,
            onSwipeBack: onSwipeBack,
            child: const SizedBox.expand(
              key: childKey,
              child: ColoredBox(color: Color(0xFF000000)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // Default test surface is 800x600 → the strip is x∈[0,20], full height. y=300
  // is vertically centred inside the strip for every drag below.
  const double midY = 300;

  group('EdgeSwipeBack — gesture commit contract', () {
    testWidgets(
      'a rightward edge drag past the distance threshold fires onSwipeBack '
      'exactly once',
      (tester) async {
        int calls = 0;
        await pumpEdgeSwipe(tester, enabled: true, onSwipeBack: () => calls++);

        // Start INSIDE the 20px strip (x=5) and drag 200px rightward — well past
        // the 48px distance threshold. dragFrom velocity ≈ 0, so this commits on
        // DISTANCE alone.
        await tester.dragFrom(const Offset(5, midY), const Offset(200, 0));
        await tester.pump();

        expect(
          calls,
          1,
          reason:
              'a committed rightward edge drag must fire onSwipeBack exactly '
              'once',
        );
      },
    );

    testWidgets(
      'a drag that STARTS mid-screen (outside the 20px strip) does NOT fire — '
      'strip confinement',
      (tester) async {
        int calls = 0;
        await pumpEdgeSwipe(tester, enabled: true, onSwipeBack: () => calls++);

        // Same 200px rightward travel — but STARTED at x=400, far outside the
        // 20px strip. The translucent detector is not under the pointer-down, so
        // the drag hits only the (handler-less) child. This is the invariant
        // that stops the gesture stealing in-tab horizontal scrolls.
        await tester.dragFrom(const Offset(400, midY), const Offset(200, 0));
        await tester.pump();

        expect(
          calls,
          0,
          reason:
              'a drag starting outside the 20px edge strip must never reach the '
              'swipe-back detector',
        );
      },
    );

    testWidgets('a LEFTWARD edge drag does NOT fire — rightward-only', (
      tester,
    ) async {
      int calls = 0;
      await pumpEdgeSwipe(tester, enabled: true, onSwipeBack: () => calls++);

      // Pointer-down INSIDE the strip (x=10) then drag 100px LEFTWARD. The
      // recognizer accepts (horizontal slop exceeded) but net dx is negative, so
      // neither the (rightward) distance nor (rightward) velocity threshold is
      // met.
      await tester.dragFrom(const Offset(10, midY), const Offset(-100, 0));
      await tester.pump();

      expect(
        calls,
        0,
        reason: 'a leftward drag is not a back gesture — it must never fire',
      );
    });

    testWidgets(
      'a rightward edge drag SHORT of the distance AND velocity thresholds does '
      'NOT fire',
      (tester) async {
        int calls = 0;
        await pumpEdgeSwipe(tester, enabled: true, onSwipeBack: () => calls++);

        // Start inside the strip (x=5) but travel only 30px — under the 48px
        // distance threshold. dragFrom velocity ≈ 0 (< 400px/s), so BOTH escape
        // hatches miss and the gesture must not commit.
        await tester.dragFrom(const Offset(5, midY), const Offset(30, 0));
        await tester.pump();

        expect(
          calls,
          0,
          reason:
              'a drag below both the 48px distance and 400px/s velocity '
              'thresholds must not commit',
        );
      },
    );
  });

  group('EdgeSwipeBack — enabled gating', () {
    testWidgets(
      'enabled:false — the detector is ABSENT and no drag can fire, but the '
      'child still renders',
      (tester) async {
        int calls = 0;
        await pumpEdgeSwipe(tester, enabled: false, onSwipeBack: () => calls++);

        // The strip is omitted from the Stack when disabled...
        expect(
          find.byKey(detectorKey),
          findsNothing,
          reason: 'enabled:false must not mount the edge-swipe detector',
        );
        // ...but the child is still rendered (stable children[0] slot).
        expect(
          find.byKey(childKey),
          findsOneWidget,
          reason: 'the wrapped child must render even when the strip is off',
        );

        // A rightward edge drag at the same start point now hits only the
        // child — the callback can never fire.
        await tester.dragFrom(const Offset(5, midY), const Offset(200, 0));
        await tester.pump();
        expect(
          calls,
          0,
          reason: 'with the detector unmounted no gesture can fire onSwipeBack',
        );
      },
    );

    testWidgets('enabled:true — the detector is present', (tester) async {
      await pumpEdgeSwipe(tester, enabled: true, onSwipeBack: () {});

      expect(
        find.byKey(detectorKey),
        findsOneWidget,
        reason: 'enabled:true must mount exactly one edge-swipe detector',
      );
      expect(find.byKey(childKey), findsOneWidget);
    });
  });
}
