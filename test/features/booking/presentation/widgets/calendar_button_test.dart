// QA (track 14.x booking) — press-feel guard for the shared [CalendarButton]
// pill (change #2).
//
// The pill (still used by both success screens + the home hub) gained a
// tactile depress: a `RepaintBoundary` isolating the press repaints, wrapping
// an `AnimatedScale` that springs to 0.97 over 120 ms `easeOut` while
// `_pressed`, back to 1.0 on release — mirroring the canonical
// `NeumorphicButton` depress. This suite pins that feedback so a refactor
// cannot silently drop it:
//   • the `AnimatedScale` exists, isolated behind a `RepaintBoundary`, and is
//     configured 0.97 / 120 ms / easeOut;
//   • a held gesture drives the scale target to 0.97, releasing returns it to
//     1.0 (and fires the `onTap`).
//
// Finders are type/key-first; copy is never asserted here (this is a geometry
// / interaction test, not a content one).

import 'package:beautica_mobile/features/booking/presentation/widgets/calendar_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

void main() {
  Finder scaleOf() => find.descendant(
    of: find.byType(CalendarButton),
    matching: find.byType(AnimatedScale),
  );

  Future<void> pumpButton(WidgetTester tester, VoidCallback onTap) async {
    await tester.pumpApp(
      Scaffold(
        body: Center(child: CalendarButton(onTap: onTap)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a RepaintBoundary-isolated AnimatedScale drives the depress (0.97 / 120ms '
    '/ easeOut) and sits at 1.0 at rest',
    (tester) async {
      await pumpButton(tester, () {});

      // The AnimatedScale is isolated behind a RepaintBoundary (repaint
      // isolation — the Phase 2.17 P1-2 fix carried over from NeumorphicButton).
      expect(
        find.descendant(of: find.byType(RepaintBoundary), matching: scaleOf()),
        findsOneWidget,
      );

      final AnimatedScale rest = tester.widget<AnimatedScale>(scaleOf());
      expect(rest.scale, 1.0, reason: 'un-pressed → full size');
      expect(rest.duration, const Duration(milliseconds: 120));
      expect(rest.curve, Curves.easeOut);
    },
  );

  testWidgets(
    'holding the button drives the scale target to 0.97; releasing returns it '
    'to 1.0 and fires onTap',
    (tester) async {
      int taps = 0;
      await pumpButton(tester, () => taps++);

      // Press and HOLD — onTapDown flips `_pressed`, so the AnimatedScale
      // target becomes 0.97.
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byType(CalendarButton)),
      );
      await tester.pump(); // let the tap-down fire + rebuild
      expect(
        tester.widget<AnimatedScale>(scaleOf()).scale,
        0.97,
        reason: 'held → depressed to 0.97',
      );
      expect(taps, 0, reason: 'onTap fires on release, not on press');

      // Release — `_pressed` clears (target back to 1.0) and onTap fires.
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        tester.widget<AnimatedScale>(scaleOf()).scale,
        1.0,
        reason: 'released → springs back to full size',
      );
      expect(taps, 1, reason: 'releasing fired onTap once');
    },
  );
}
