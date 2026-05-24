// Widget tests for SplashScreen.
//
// SplashScreen was converted from StatelessWidget to StatefulWidget in the
// auth-screen redesign. It now owns an AnimationController
// (SingleTickerProviderStateMixin) and an _showSpinner bool that gates the
// CircularProgressIndicator. Zero test coverage existed before this file.
//
// Covered scenarios:
//   1. Widget renders without error (smoke test) — Scaffold + Stack present.
//   2. VelvetLogo is present in the tree (SVG→VelvetLogo migration regression).
//   3. On first pump, CircularProgressIndicator opacity is 0 (_showSpinner=false).
//   4. After logo animation completes, CircularProgressIndicator appears
//      (_showSpinner flips to true when AnimationController.status == completed).
//   5. With disableAnimations=true (reduced-motion), _showSpinner is set
//      immediately via post-frame callback — spinner is visible after first settle.
//   6. No AppBar is rendered (auth screens are full-screen, no AppBar).
//   7. AnimationController is disposed without error (no pending timers).
//   8. Phase 2.15 regression — _logoScale Tween is a no-op (begin == end == 1.0)
//      so there is zero geometry change at the native-splash handoff.
//   9. Phase 2.15 regression — Scaffold backgroundColor matches BrandColors.base
//      (#E6DDD0), which must match the native splash background to avoid a color
//      flash at handoff.
//  10. Phase 2.15 regression — FlutterNativeSplash.remove() does not throw in the
//      widget-test environment; the post-frame callback runs clean.
//
// Note on VelvetLogo:
//   VelvetLogo is a pure-Dart widget (no asset loading, no SVG, no external
//   file). flutter_test requires no asset bundle setup and no mock for it.
//
// Note on FlutterNativeSplash.remove() (Tests 1, 2, 8, 9, 10):
//   In the flutter_test environment the native-splash platform channel is not
//   initialised, so FlutterNativeSplash.remove() is a documented no-op — it
//   does not throw. Tests verify it remains a no-op by asserting no exception
//   escapes after the post-frame callback fires.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/presentation/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Wraps the widget under test in the minimal tree that SplashScreen requires:
// a MaterialApp (for Scaffold / MediaQuery / Theme) with no router needed.
Widget _buildApp({bool disableAnimations = false}) => MediaQuery(
  data: const MediaQueryData().copyWith(disableAnimations: disableAnimations),
  child: const MaterialApp(home: SplashScreen()),
);

void main() {
  group('SplashScreen', () {
    // -------------------------------------------------------------------------
    // Test 1 — smoke test: widget renders without error
    // -------------------------------------------------------------------------
    testWidgets('1. renders without error', (tester) async {
      await tester.pumpWidget(_buildApp());
      // Allow post-frame callbacks (initState deferred check) to run.
      await tester.pump();

      expect(find.byType(SplashScreen), findsOneWidget);
      // No exception thrown — rendering succeeded.
    });

    // -------------------------------------------------------------------------
    // Test 2 — VelvetLogo is rendered (SVG→VelvetLogo migration regression)
    //
    // Phase 2.15 removed the SvgPicture-based logo and replaced it with the
    // pure-Dart VelvetLogo widget. This test asserts the widget is present in
    // the tree so that a future reversion would be caught immediately.
    // -------------------------------------------------------------------------
    testWidgets('2. VelvetLogo widget is present in the tree', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(
        find.byType(VelvetLogo),
        findsOneWidget,
        reason:
            'SplashScreen must render exactly one VelvetLogo. '
            'A regression to SvgPicture or any other widget would fail this test.',
      );
      // Verify the full-size (non-compact) logo is used on the splash.
      expect(
        tester.widget<VelvetLogo>(find.byType(VelvetLogo)).compact,
        isFalse,
        reason: 'SplashScreen uses the full-size logo (compact: false).',
      );
    });

    // -------------------------------------------------------------------------
    // Test 3 — CircularProgressIndicator is initially opacity-hidden
    //
    // On the first frame, _showSpinner == false because the AnimationController
    // has not yet completed. The AnimatedOpacity wrapping the spinner sets
    // opacity: 0.0, but the widget is still in the tree.
    // -------------------------------------------------------------------------
    testWidgets(
      '3. CircularProgressIndicator is present but initially invisible',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        // Pump one frame to trigger the initState post-frame callback (which
        // calls _logoCtrl.forward()). The animation has NOT completed yet.
        await tester.pump();

        // The spinner widget must be in the tree (it is always rendered; only
        // its opacity changes).
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // The AnimatedOpacity wrapping the spinner must be at opacity 0.0 —
        // _showSpinner is still false at this point.
        final animatedOpacity = tester.widget<AnimatedOpacity>(
          find.ancestor(
            of: find.byType(CircularProgressIndicator),
            matching: find.byType(AnimatedOpacity),
          ),
        );
        expect(animatedOpacity.opacity, equals(0.0));
      },
    );

    // -------------------------------------------------------------------------
    // Test 4 — After animation completes, spinner becomes visible
    //
    // The AnimationController runs for 800 ms. After that, addStatusListener
    // fires, sets _showSpinner = true, and triggers a rebuild. The
    // AnimatedOpacity then transitions to opacity: 1.0. We advance the clock
    // by the controller duration + the AnimatedOpacity transition (200 ms).
    // -------------------------------------------------------------------------
    testWidgets(
      '4. CircularProgressIndicator becomes visible after logo animation completes',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        // Trigger the post-frame callback that starts the animation.
        await tester.pump();

        // Advance past the logo animation duration (800 ms).
        await tester.pump(const Duration(milliseconds: 800));

        // The status listener fires synchronously at frame boundary.
        // Pump one more frame to apply the setState rebuild.
        await tester.pump();

        // Advance through the AnimatedOpacity transition (200 ms).
        await tester.pump(const Duration(milliseconds: 200));

        final animatedOpacity = tester.widget<AnimatedOpacity>(
          find.ancestor(
            of: find.byType(CircularProgressIndicator),
            matching: find.byType(AnimatedOpacity),
          ),
        );
        expect(animatedOpacity.opacity, equals(1.0));
      },
    );

    // -------------------------------------------------------------------------
    // Test 5 — Reduced-motion: disableAnimations=true skips animation,
    //           spinner is visible after the AnimatedOpacity transition
    //
    // When MediaQuery.disableAnimations is true, initState's post-frame
    // callback sets _logoCtrl.value = 1.0 and immediately calls
    // setState(() => _showSpinner = true). The AnimatedOpacity widget then
    // transitions to opacity: 1.0 over its 200 ms duration.
    //
    // We cannot use pumpAndSettle here because the AnimatedOpacity implicit
    // animation keeps the engine busy beyond flutter_test's settle threshold.
    // Instead we advance the clock explicitly by 300 ms — enough to cover the
    // post-frame callback (1 frame) + the 200 ms AnimatedOpacity duration.
    // -------------------------------------------------------------------------
    testWidgets(
      '5. with disableAnimations=true spinner becomes visible after transition',
      (tester) async {
        await tester.pumpWidget(_buildApp(disableAnimations: true));
        // Trigger the post-frame callback that sets _logoCtrl.value=1.0 and
        // _showSpinner=true.
        await tester.pump();
        // Advance through the AnimatedOpacity transition (200 ms declared in
        // SplashScreen) plus a small margin.
        await tester.pump(const Duration(milliseconds: 300));

        // The AnimatedOpacity wrapping the spinner should now be at 1.0.
        final animatedOpacity = tester.widget<AnimatedOpacity>(
          find.ancestor(
            of: find.byType(CircularProgressIndicator),
            matching: find.byType(AnimatedOpacity),
          ),
        );
        expect(animatedOpacity.opacity, equals(1.0));
      },
    );

    // -------------------------------------------------------------------------
    // Test 6 — No AppBar rendered (full-screen design)
    // -------------------------------------------------------------------------
    testWidgets('6. no AppBar is rendered', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(find.byType(AppBar), findsNothing);
    });

    // -------------------------------------------------------------------------
    // Test 7 — AnimationController disposes cleanly (no pending-timer failures)
    //
    // If dispose() is missing or incorrect, flutter_test raises a
    // "A Timer is still pending" error at test teardown. Pumping the widget,
    // then disposing (via pumpWidget empty tree), must not throw.
    // -------------------------------------------------------------------------
    testWidgets('7. AnimationController disposes without error', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      // Replace the widget tree with an empty widget to trigger dispose().
      await tester.pumpWidget(const SizedBox.shrink());

      // If we reach here without an exception the controller was cleaned up.
      expect(find.byType(SplashScreen), findsNothing);
    });

    // -------------------------------------------------------------------------
    // Test 8 — Phase 2.15 regression: _logoScale Tween is a no-op (1.0→1.0)
    //
    // Option A of the native-splash handoff sets _logoScale begin = 1.0 so the
    // logo never changes size during the Flutter animation. This eliminates the
    // geometry jump at the handoff. Verify by reading the ScaleTransform value
    // at the very first frame (before the animation has moved), where the logo
    // Transform.scale must equal 1.0 regardless of animation progress.
    //
    // Because the Tween is begin:1.0 end:1.0, the scale must be 1.0 at every
    // animation value including 0.0 (start), 0.5 (mid), and 1.0 (end).
    // We assert the start frame (value=0) here, which is the critical moment
    // when the native splash dismisses and Flutter takes over.
    // -------------------------------------------------------------------------
    testWidgets(
      '8. Phase 2.15 — logo scale is 1.0 at animation start (no geometry jump at handoff)',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        // One frame to ensure the widget is laid out but before the post-frame
        // callback fires (so the animation controller is still at value 0.0).
        await tester.pump(Duration.zero);

        // Locate the Transform widget that applies _logoScale. It wraps a
        // VelvetLogo inside an AnimatedBuilder.
        final transformWidgets = tester.widgetList<Transform>(
          find.byType(Transform),
        );

        // At animation value 0.0 with a 1.0→1.0 Tween, every Transform scale
        // must be 1.0. An old begin=0.5 Tween would produce 0.5 here.
        for (final t in transformWidgets) {
          final matrix = t.transform;
          // m[0] and m[5] are the X and Y scale factors in a column-major
          // 4×4 transform matrix (Transform.scale sets them identically).
          final scaleX = matrix.getMaxScaleOnAxis();
          // Allow a floating-point epsilon.
          expect(
            scaleX,
            closeTo(1.0, 0.001),
            reason:
                'Logo scale must be 1.0 at animation start (Phase 2.15 Option A: '
                'begin changed from 0.5 to 1.0 to prevent geometry jump at '
                'native-splash handoff). Got $scaleX.',
          );
        }
      },
    );

    // -------------------------------------------------------------------------
    // Test 9 — Phase 2.15 regression: Scaffold backgroundColor == BrandColors.base
    //
    // The native splash background is configured as #E6DDD0 (warm taupe) in
    // pubspec.yaml flutter_native_splash.color. The Flutter Scaffold must use
    // the identical color (BrandColors.base = Color(0xFFE6DDD0)) to prevent a
    // background color flash at the handoff. If someone changes one without the
    // other this test fails immediately.
    // -------------------------------------------------------------------------
    testWidgets(
      '9. Phase 2.15 — Scaffold backgroundColor matches BrandColors.base (#E6DDD0)',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await tester.pump();

        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));

        expect(
          scaffold.backgroundColor,
          equals(BrandColors.base),
          reason:
              'Scaffold.backgroundColor must match the native splash color '
              '(BrandColors.base = #E6DDD0). A mismatch causes a visible color '
              'flash at the Phase 2.15 native-to-Flutter handoff.',
        );
      },
    );

    // -------------------------------------------------------------------------
    // Test 10 — Phase 2.15 regression: FlutterNativeSplash.remove() does not
    //            throw in the widget-test environment.
    //
    // The post-frame callback in initState calls FlutterNativeSplash.remove()
    // before checking disableAnimations. In the widget-test environment the
    // native-splash platform channel is not initialised; the package must
    // treat this as a no-op and not throw. If a future package upgrade changes
    // this contract, this test will fail and the team must add a try/catch or
    // guard around the call site.
    // -------------------------------------------------------------------------
    testWidgets(
      '10. Phase 2.15 — FlutterNativeSplash.remove() does not throw in test environment',
      (tester) async {
        // Pump the full widget. The post-frame callback fires on the second
        // pump(), calling FlutterNativeSplash.remove(). No exception must
        // propagate to the test harness.
        await tester.pumpWidget(_buildApp());
        await tester.pump(); // triggers addPostFrameCallback

        // If we reach this assertion without a test failure, remove() was a
        // silent no-op as required.
        expect(find.byType(SplashScreen), findsOneWidget);
      },
    );
  });
}
