// Tap-target guard for `HubFilledButton`
// (`lib/features/home/presentation/widgets/hub_widgets.dart`).
//
// mobile-security finding (HIGH, PRE-EXISTING): `_kCompactButtonHeight`
// (38dp) was this button's ENTIRE tap target, not just its painted height —
// below both the Android 48dp and iOS 44pt tap-target floor (WCAG 2.5.5 /
// Material / HIG). Affects all six `HubFilledButton` / `HubEmptyState` call
// sites app-wide.
//
// THE FIX
// -------
// `_HubFilledButtonState.build` wraps the painted 38dp pill in
// `Padding(vertical: _kTapPad)` (5dp each side) inside a `GestureDetector`
// set to `HitTestBehavior.opaque`, growing the widget's INTERACTIVE box to
// 48dp tall without touching the pill's own rendered size, gradient, or
// horizontal padding. See that method's doc comment for why `ConstrainedBox`
// and `Align` were tried and rejected (they either re-inflate the pill via
// `BoxConstraints.enforce`, or fight the `Align` already inside `Container`
// that other call sites, e.g. `wishlist_row.dart`'s `IntrinsicWidth`, are
// already relying on).
//
// WHAT THIS FILE PROVES
// ----------------------
// A widget-tree measurement of a `SizedBox`'s declared height proves the
// TREE, not the actual hit-testable area — Flutter's own hit-testing is a
// separate pass that can silently disagree with layout (a sibling stealing
// the region, a `deferToChild` `GestureDetector` never registering a hit
// over bare `Padding`). So this test does not just measure rects: it taps a
// real point strictly INSIDE the expanded region but OUTSIDE the painted
// pill and asserts `onTap` actually fires there.
//
// MUTATION PROOF (repo's own idiom): run with `hub_widgets.dart`'s
// `Padding(vertical: _kTapPad)` wrapper removed (reverting to the bare pill
// as the `GestureDetector`'s direct child) — the height assertion below
// fails first (~38dp, not >=48dp), and even forcing the height check to pass
// artificially, the hit-test at `outerRect.top + 2` would land 3dp ABOVE the
// pill's actual top edge with nothing there to catch it, so the tap assertion
// fails too. Restoring the wrapper makes both pass again.
//
// Layer: Widget. No providers — `HubFilledButton` is a `StatefulWidget` with
// no Riverpod dependency.

import 'package:beautica_mobile/features/home/presentation/widgets/hub_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

/// Android's 48dp / iOS's 44pt tap-target floor (WCAG 2.5.5, Material, HIG)
/// — the larger of the two, mirroring `hub_widgets.dart`'s own
/// `_kMinTapExtent`. Not imported directly: that constant is private to
/// `_HubFilledButtonState`, and re-deriving the floor here from the public
/// spec (not from the implementation) is what makes this a genuine
/// regression guard rather than a tautology.
const double _kPlatformMinTapExtent = 48;

void main() {
  testWidgets(
    'the interactive area is at least 48dp on both axes, and a tap in the '
    'invisible margin above the painted pill still fires onTap',
    (tester) async {
      var taps = 0;
      await tester.pumpApp(
        Center(
          child: HubFilledButton(label: 'Записатись', onTap: () => taps++),
        ),
      );
      await tester.pumpAndSettle();

      final Rect outerRect = tester.getRect(find.byType(HubFilledButton));
      final Rect pillRect = tester.getRect(
        find.descendant(
          of: find.byType(HubFilledButton),
          matching: find.byType(Container),
        ),
      );

      // The measurement half of the proof.
      expect(
        outerRect.height,
        greaterThanOrEqualTo(_kPlatformMinTapExtent),
        reason:
            'the interactive box measured ${outerRect.height}dp tall — '
            'below the 48dp platform floor. The painted pill itself must '
            'stay _kCompactButtonHeight (38dp); only the invisible margin '
            'around it should have grown.',
      );
      expect(
        outerRect.width,
        greaterThanOrEqualTo(_kPlatformMinTapExtent),
        reason:
            'the interactive box measured ${outerRect.width}dp wide — '
            'below the 48dp platform floor.',
      );

      // The painted pill must be UNCHANGED (38dp) — this fix grows the
      // invisible margin around it, not the button itself.
      expect(
        pillRect.height,
        moreOrLessEquals(38, epsilon: 0.5),
        reason:
            'the painted pill grew — this finding is about the tap '
            'TARGET, not the visible button; VelvetTouch\'s compact pill '
            'must render exactly as before',
      );

      // Sanity: the probe point below must genuinely sit above the painted
      // pill, or a subsequent tap there would prove nothing.
      final Offset aboveThePill = Offset(
        outerRect.center.dx,
        outerRect.top + 2,
      );
      expect(
        aboveThePill.dy,
        lessThan(pillRect.top),
        reason:
            'the probe point must sit strictly above the painted pill '
            '(pill top: ${pillRect.top}, probe: ${aboveThePill.dy}) or the '
            'tap below is not actually testing the expanded margin',
      );

      // The load-bearing half of the proof: hit-test, not tree inspection.
      await tester.tapAt(aboveThePill);
      await tester.pump();

      expect(
        taps,
        1,
        reason:
            'a tap 2dp below the interactive box\'s top edge — strictly '
            'outside the painted 38dp pill, strictly inside the 48dp '
            'accessibility floor — must still fire onTap. A widget-tree '
            'height measurement alone cannot prove this: it only proves '
            'the SizedBox/Padding exists, not that Flutter\'s hit-testing '
            'actually routes a tap there to this button rather than to '
            'nothing (or a sibling) underneath it.',
      );
    },
  );

  testWidgets(
    'a tap in the invisible margin BELOW the painted pill also fires onTap',
    (tester) async {
      // The margin is symmetric (top AND bottom) — one side proving out
      // does not prove the other; `_kTapPad` could regress to being applied
      // only on one edge (e.g. an `EdgeInsets.only(top:)` typo) and the test
      // above would not catch it.
      var taps = 0;
      await tester.pumpApp(
        Center(
          child: HubFilledButton(label: 'Записатись', onTap: () => taps++),
        ),
      );
      await tester.pumpAndSettle();

      final Rect outerRect = tester.getRect(find.byType(HubFilledButton));
      final Rect pillRect = tester.getRect(
        find.descendant(
          of: find.byType(HubFilledButton),
          matching: find.byType(Container),
        ),
      );

      final Offset belowThePill = Offset(
        outerRect.center.dx,
        outerRect.bottom - 2,
      );
      expect(
        belowThePill.dy,
        greaterThan(pillRect.bottom),
        reason:
            'the probe point must sit strictly below the painted pill '
            '(pill bottom: ${pillRect.bottom}, probe: ${belowThePill.dy})',
      );

      await tester.tapAt(belowThePill);
      await tester.pump();

      expect(
        taps,
        1,
        reason:
            'a tap 2dp above the interactive box\'s bottom edge — strictly '
            'below the painted pill — must also fire onTap',
      );
    },
  );
}
