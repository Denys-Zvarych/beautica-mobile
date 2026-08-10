// Tap-target guard for [WishlistHeartButton]
// (`lib/features/wishlist/presentation/widgets/wishlist_heart_button.dart`).
//
// mobile-security finding (MEDIUM): the painted 32×32dp heart was its ENTIRE
// tap target — below both the Android 48dp and iOS 44pt tap-target floor
// (WCAG 2.5.5 / Material / HIG). Affects both shipped call sites,
// `wishlist_row.dart` and `wishlist_compact_card.dart`.
//
// THE FIX
// -------
// `_WishlistHeartButtonState.build` wraps the painted 32×32 `SizedBox` in
// `Padding(all: _kTapPad)` (8dp every side) inside a `GestureDetector` set to
// `HitTestBehavior.opaque`, growing the widget's INTERACTIVE box to 48×48
// without touching the heart's own rendered size, glyph, or colour. Unlike
// `hub_filled_button_tap_target_test.dart`'s pill (short on one axis only),
// this heart is a square short on BOTH axes, so the pad is symmetric on both
// and this file checks all four edges, not just top/bottom.
//
// WHAT THIS FILE PROVES
// ----------------------
// A widget-tree measurement of a rect only proves the TREE, not the actual
// hit-testable area — Flutter's hit-testing is a separate pass that can
// silently disagree with layout. So beyond measuring both boxes, this test
// taps four real points strictly INSIDE the expanded region but OUTSIDE the
// painted heart — one per edge — and asserts `onTap` still fires each time.
//
// MUTATION PROOF (repo's own idiom): run with `wishlist_heart_button.dart`'s
// `Padding(all: _kTapPad)` wrapper removed (reverting to the bare `SizedBox`
// as the `GestureDetector`'s direct child) — the size assertions below fail
// first (32dp, not >=48dp on either axis), and even forcing those to pass
// artificially, every edge tap would land outside the painted 32dp box with
// nothing there to catch it, so all four tap assertions fail too. Restoring
// the wrapper makes every assertion pass again (see this session's RED/GREEN
// transcript in the handoff notes).
//
// Layer: Widget. No providers — [WishlistHeartButton] is a `StatefulWidget`
// with no Riverpod dependency.

import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_heart_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

/// Android's 48dp / iOS's 44pt tap-target floor (WCAG 2.5.5, Material, HIG)
/// — the larger of the two, mirroring `wishlist_heart_button.dart`'s own
/// `_kMinTapExtent`. Not imported directly: that constant is private to the
/// widget file, and re-deriving the floor here from the public spec (not
/// from the implementation) is what makes this a genuine regression guard
/// rather than a tautology — same reasoning as
/// `hub_filled_button_tap_target_test.dart`'s `_kPlatformMinTapExtent`.
const double _kPlatformMinTapExtent = 48;

/// The heart's documented painted size — `WishlistHeartButton.target`,
/// re-stated rather than imported for the same reason as the floor above:
/// the assertion below is that the PAINTED size did not move, so it must not
/// be derived from the same constant the implementation uses to draw it.
const double _kPaintedHeart = 32;

void main() {
  Future<int> pumpHeart(WidgetTester tester) async {
    var taps = 0;
    await tester.pumpApp(
      Center(child: WishlistHeartButton(onTap: () => taps++)),
    );
    await tester.pumpAndSettle();
    return taps;
  }

  ({Rect outer, Rect painted}) rects(WidgetTester tester) => (
    outer: tester.getRect(find.byType(WishlistHeartButton)),
    // `Icon` renders its own internal `SizedBox` (20dp, the glyph), so a
    // bare `find.byType(SizedBox)` here is ambiguous — pin on the WIDTH to
    // land on the 32dp target box specifically, not just "a SizedBox".
    painted: tester.getRect(
      find.descendant(
        of: find.byType(WishlistHeartButton),
        matching: find.byWidgetPredicate(
          (Widget w) => w is SizedBox && w.width == _kPaintedHeart,
        ),
      ),
    ),
  );

  testWidgets(
    'the interactive box is at least 48dp on both axes and the painted '
    'heart stays 32dp',
    (tester) async {
      await pumpHeart(tester);
      final (outer: Rect outerRect, painted: Rect paintedRect) = rects(tester);

      expect(
        outerRect.height,
        greaterThanOrEqualTo(_kPlatformMinTapExtent),
        reason:
            'the interactive box measured ${outerRect.height}dp tall — '
            'below the 48dp platform floor.',
      );
      expect(
        outerRect.width,
        greaterThanOrEqualTo(_kPlatformMinTapExtent),
        reason:
            'the interactive box measured ${outerRect.width}dp wide — '
            'below the 48dp platform floor.',
      );

      // The painted heart must be UNCHANGED (32dp) — this fix grows the
      // invisible margin around it, not the heart itself.
      expect(
        paintedRect.height,
        moreOrLessEquals(_kPaintedHeart, epsilon: 0.5),
        reason:
            'the painted heart grew — this finding is about the tap TARGET, '
            'not the visible icon; it must render exactly as before',
      );
      expect(paintedRect.width, moreOrLessEquals(_kPaintedHeart, epsilon: 0.5));
    },
  );

  group('a tap strictly inside the invisible margin still fires onTap', () {
    testWidgets('above the painted heart', (tester) async {
      var taps = 0;
      await tester.pumpApp(
        Center(child: WishlistHeartButton(onTap: () => taps++)),
      );
      await tester.pumpAndSettle();
      final (outer: Rect outerRect, painted: Rect paintedRect) = rects(tester);

      final Offset probe = Offset(outerRect.center.dx, outerRect.top + 2);
      expect(
        probe.dy,
        lessThan(paintedRect.top),
        reason:
            'the probe must sit strictly above the painted heart (heart '
            'top: ${paintedRect.top}, probe: ${probe.dy}) or this proves '
            'nothing',
      );

      await tester.tapAt(probe);
      await tester.pumpAndSettle();
      expect(taps, 1, reason: 'a tap above the painted heart must fire onTap');
    });

    testWidgets('below the painted heart', (tester) async {
      var taps = 0;
      await tester.pumpApp(
        Center(child: WishlistHeartButton(onTap: () => taps++)),
      );
      await tester.pumpAndSettle();
      final (outer: Rect outerRect, painted: Rect paintedRect) = rects(tester);

      final Offset probe = Offset(outerRect.center.dx, outerRect.bottom - 2);
      expect(
        probe.dy,
        greaterThan(paintedRect.bottom),
        reason:
            'the probe must sit strictly below the painted heart (heart '
            'bottom: ${paintedRect.bottom}, probe: ${probe.dy}) or this '
            'proves nothing',
      );

      await tester.tapAt(probe);
      await tester.pumpAndSettle();
      expect(taps, 1, reason: 'a tap below the painted heart must fire onTap');
    });

    testWidgets('left of the painted heart', (tester) async {
      var taps = 0;
      await tester.pumpApp(
        Center(child: WishlistHeartButton(onTap: () => taps++)),
      );
      await tester.pumpAndSettle();
      final (outer: Rect outerRect, painted: Rect paintedRect) = rects(tester);

      final Offset probe = Offset(outerRect.left + 2, outerRect.center.dy);
      expect(
        probe.dx,
        lessThan(paintedRect.left),
        reason:
            'the probe must sit strictly left of the painted heart (heart '
            'left: ${paintedRect.left}, probe: ${probe.dx}) or this proves '
            'nothing',
      );

      await tester.tapAt(probe);
      await tester.pumpAndSettle();
      expect(
        taps,
        1,
        reason: 'a tap left of the painted heart must fire onTap',
      );
    });

    testWidgets('right of the painted heart', (tester) async {
      var taps = 0;
      await tester.pumpApp(
        Center(child: WishlistHeartButton(onTap: () => taps++)),
      );
      await tester.pumpAndSettle();
      final (outer: Rect outerRect, painted: Rect paintedRect) = rects(tester);

      final Offset probe = Offset(outerRect.right - 2, outerRect.center.dy);
      expect(
        probe.dx,
        greaterThan(paintedRect.right),
        reason:
            'the probe must sit strictly right of the painted heart (heart '
            'right: ${paintedRect.right}, probe: ${probe.dx}) or this '
            'proves nothing',
      );

      await tester.tapAt(probe);
      await tester.pumpAndSettle();
      expect(
        taps,
        1,
        reason: 'a tap right of the painted heart must fire onTap',
      );
    });
  });
}
