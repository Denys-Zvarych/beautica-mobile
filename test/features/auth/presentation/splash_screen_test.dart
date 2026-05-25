// Widget tests for SplashScreen.
//
// SplashScreen was converted from StatelessWidget to StatefulWidget in the
// auth-screen redesign. It now owns a `_showSpinner` bool that gates the
// CircularProgressIndicator, driven by a cancellable `Timer`.
// Zero test coverage existed before this file.
//
// Covered scenarios:
//   1. Widget renders without error (smoke test) — Scaffold + Stack present.
//   2. VelvetLogo is present in the tree (SVG→VelvetLogo migration regression).
//   3. On first pump, CircularProgressIndicator opacity is 0 (_showSpinner=false).
//   4. After 800ms timer fires, CircularProgressIndicator appears
//      (_showSpinner flips to true when the Timer callback runs).
//   5. With disableAnimations=true (reduced-motion), _showSpinner is set
//      immediately via post-frame callback — spinner is visible after first settle.
//   6. No AppBar is rendered (auth screens are full-screen, no AppBar).
//   7. Timer is cancelled on dispose (no pending-timer error).
//   8. VelvetLogo is not wrapped in FadeTransition (no-op fade removed in Batch 6).
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
    // On the first frame, _showSpinner == false because the Timer has not yet
    // fired. The AnimatedOpacity wrapping the spinner sets opacity: 0.0, but
    // the widget is still in the tree.
    // -------------------------------------------------------------------------
    testWidgets(
      '3. CircularProgressIndicator is present but initially invisible',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        // Pump one frame to trigger the initState post-frame callback (which
        // schedules the 800ms Timer). The Timer has NOT yet fired.
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
    // The Timer fires after 800 ms, sets _showSpinner = true, and triggers a
    // rebuild. The AnimatedOpacity then transitions to opacity: 1.0.
    // We advance the clock by the timer duration + the AnimatedOpacity (200 ms).
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
    // callback calls setState(() => _showSpinner = true) immediately
    // (no Timer is started). The AnimatedOpacity then transitions to
    // opacity: 1.0 over its 200 ms duration.
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
        // Trigger the post-frame callback that sets _showSpinner=true.
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
    // Test 7 — Timer is cancelled on dispose (no pending-timer error)
    //
    // If dispose() is missing or incorrect, flutter_test raises a
    // "A Timer is still pending" error at test teardown. Pumping the widget,
    // then disposing (via pumpWidget empty tree), must not throw.
    // -------------------------------------------------------------------------
    testWidgets('7. Timer is cancelled on dispose (no pending-timer error)', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      // Replace the widget tree with an empty widget to trigger dispose().
      await tester.pumpWidget(const SizedBox.shrink());

      // If we reach here without an exception the 800ms timer was cancelled in dispose().
      expect(find.byType(SplashScreen), findsNothing);
    });

    // -------------------------------------------------------------------------
    // Test 8 — Batch 6 regression: VelvetLogo is not wrapped in FadeTransition
    //
    // The FadeTransition that was wrapping VelvetLogo used a 1.0→1.0 Tween
    // (a no-op — opacity was always 1.0). It was removed in Batch 6 to eliminate
    // the per-tick SaveLayer and the AnimationController. This test asserts the
    // FadeTransition is absent so a future re-introduction would be caught.
    // -------------------------------------------------------------------------
    testWidgets(
      '8. VelvetLogo is not wrapped in FadeTransition (no-op fade removed in Batch 6)',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await tester.pump(Duration.zero);

        // VelvetLogo must be present.
        expect(find.byType(VelvetLogo), findsOneWidget);

        // The VelvetLogo is placed directly inside a Column → Align → Stack
        // (SplashScreen's body). Its immediate parent in SplashScreen's own
        // subtree must NOT be FadeTransition.
        //
        // Strategy: locate the Column that is a descendant of the Scaffold's
        // body (below the Scaffold, therefore below MaterialApp's routing
        // FadeTransitions). Then assert that no FadeTransition exists as a
        // descendant of that Column AND as an ancestor of VelvetLogo.
        //
        // We use find.byWidgetPredicate on Column to pick the one whose
        // children include VelvetLogo (the Column is mainAxisSize.min, which
        // distinguishes it from any outer Column the framework might inject).
        final logoColumnFinder = find.byWidgetPredicate(
          (widget) =>
              widget is Column && widget.mainAxisSize == MainAxisSize.min,
        );
        // There must be exactly one such Column on this screen.
        expect(logoColumnFinder, findsOneWidget);

        // No FadeTransition should be a descendant of that Column AND an
        // ancestor of VelvetLogo.
        expect(
          find.descendant(
            of: logoColumnFinder,
            matching: find.ancestor(
              of: find.byType(VelvetLogo),
              matching: find.byType(FadeTransition),
            ),
          ),
          findsNothing,
          reason:
              'VelvetLogo must not be wrapped in FadeTransition inside '
              "SplashScreen's Column after the Batch 6 no-op animation cleanup.",
        );
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
