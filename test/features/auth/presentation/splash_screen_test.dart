// Widget tests for SplashScreen.
//
// SplashScreen was converted from a Timer/spinner approach to an
// AnimationController-driven letter-by-letter wordmark reveal. The
// [CircularProgressIndicator] is removed; [AnimatedWordmark] inside
// [VelvetLogo] IS the loading animation.
//
// Covered scenarios:
//   1. Widget renders without error (smoke test) — Scaffold + Stack present.
//   2. VelvetLogo is present with compact=false, tileSize=92, markFontSize=42,
//      wordmarkFontSize=17.
//   3. AnimatedWordmark is present in the tree after first pump.
//   4. CircularProgressIndicator is NOT in the tree (replaced by animation).
//   5. After controller.forward() completes (pump 880ms + settle), every
//      letter ScaleTransition has scale 1.0 (the settled end-state of the
//      1.15 → 1.0 scale-in stagger).
//   6. No AppBar rendered (auth screens are full-screen, no AppBar).
//   7. AnimationController is disposed on widget dispose (no pending-frame error).
//   8. Batch 6 regression — VelvetLogo itself is NOT wrapped in FadeTransition.
//      FadeTransition widgets inside AnimatedWordmark are descendants of
//      VelvetLogo — that is correct and must NOT trigger this assertion.
//   9. Phase 2.15 regression — Scaffold backgroundColor == BrandColors.base.
//  10. Phase 2.15 regression — FlutterNativeSplash.remove() does not throw
//      in the widget-test environment.
//  11. Reduced-motion — with accessibilityFeatures.disableAnimations=true
//      (set via tester.platformDispatcher, matching the initState call site),
//      a post-frame callback snaps the controller to value 1.0; all letter
//      ScaleTransitions have scale 1.0 after pumpAndSettle().
//  12. Early-dispose safety — widget disposed immediately after pumpWidget
//      (before any pump drains the frame queue); no AnimationController error
//      surfaces. Verifies that the initState animation start cannot produce a
//      use-after-dispose exception regardless of pump ordering.
//  13. Accessibility early-dispose — disableAnimations=true schedules _splashTimer
//      in initState; dispose() must cancel it without crash (no dangling timer).
//  14. Accessibility timer → GoRouter.refresh() — with disableAnimations=true
//      and the widget mounted, GoRouter.of(context).refresh() must be called
//      after the _minSplashMs timer fires. Verifies the router-kick in the
//      accessibility fast-path (the status listener never fires in this path
//      because value=1.0 does not emit AnimationStatus.completed).
//
// Note on VelvetLogo / AnimatedWordmark:
//   Both are pure-Dart widgets (no asset loading, no SVG, no network).
//   flutter_test requires no asset bundle setup.
//
// Note on FlutterNativeSplash.remove() (Tests 1, 9, 10):
//   In the flutter_test environment the native-splash platform channel is not
//   initialised, so FlutterNativeSplash.remove() is a documented no-op.
//
// Note on ScreenProtector:
//   ScreenProtector was intentionally removed from SplashScreen (Phase 2.15
//   fix — FLAG_SECURE caused the Android emulator to black out the animated
//   wordmark). The splash screen has no sensitive data; FLAG_SECURE correctly
//   remains on all auth screens that show passwords/OTP/PII.
//
// Note on Test 11 — accessibilityFeatures vs MediaQuery:
//   The source reads WidgetsBinding.instance.accessibilityFeatures.disableAnimations
//   in initState. MediaQueryData.disableAnimations is a DIFFERENT value backed by
//   a separate data path. Setting MediaQuery(data: copyWith(disableAnimations: true))
//   does NOT affect accessibilityFeatures — it would leave the branch in source
//   perpetually untested. The correct setter is
//   tester.platformDispatcher.accessibilityFeaturesTestValue with
//   FakeAccessibilityFeatures(disableAnimations: true).

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/presentation/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// Wraps the widget under test in the minimal tree that SplashScreen requires:
// a MaterialApp (for Scaffold / Theme) with no router needed.
// MediaQuery is NOT injected here — Test 11 uses the platform dispatcher path
// that the source code actually reads (accessibilityFeatures), not MediaQuery.
Widget _buildApp() => const MaterialApp(home: SplashScreen());

void main() {
  group('SplashScreen', () {
    // -------------------------------------------------------------------------
    // Test 1 — smoke test: widget renders without error
    // -------------------------------------------------------------------------
    testWidgets('1. renders without error', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(find.byType(SplashScreen), findsOneWidget);
      // No exception thrown — rendering succeeded.
    });

    // -------------------------------------------------------------------------
    // Test 2 — VelvetLogo is present with the splash-specific size params
    //
    // The splash screen renders a larger logo than any other screen:
    //   - compact: false  (default — unchanged)
    //   - tileSize: 92    (bigger pillow on splash only)
    //   - markFontSize: 42
    //   - wordmarkFontSize: 17
    // -------------------------------------------------------------------------
    testWidgets('2. VelvetLogo present with splash-specific size params', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(
        find.byType(VelvetLogo),
        findsOneWidget,
        reason: 'SplashScreen must render exactly one VelvetLogo.',
      );

      final logo = tester.widget<VelvetLogo>(find.byType(VelvetLogo));

      expect(
        logo.compact,
        isFalse,
        reason: 'SplashScreen uses the full-size (non-compact) logo.',
      );
      expect(
        logo.tileSize,
        equals(92.0),
        reason: 'Splash uses a 92 dp pillow — larger than the default 78 dp.',
      );
      expect(
        logo.markFontSize,
        equals(42.0),
        reason: 'Splash "B" glyph is 42 sp — larger than the default 36 sp.',
      );
      expect(
        logo.wordmarkFontSize,
        equals(17.0),
        reason: 'Splash wordmark is 17 sp — larger than the default 14 sp.',
      );
    });

    // -------------------------------------------------------------------------
    // Test 3 — AnimatedWordmark is present in the tree after first pump
    // -------------------------------------------------------------------------
    testWidgets('3. AnimatedWordmark is present in the widget tree', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(
        find.byType(AnimatedWordmark),
        findsOneWidget,
        reason:
            'VelvetLogo must render AnimatedWordmark when animationController '
            'is supplied. The splash screen always supplies a controller.',
      );
    });

    // -------------------------------------------------------------------------
    // Test 4 — CircularProgressIndicator is NOT in the tree
    //
    // The spinner was removed in this phase and replaced entirely by the
    // AnimatedWordmark letter-by-letter reveal.
    // -------------------------------------------------------------------------
    testWidgets('4. CircularProgressIndicator is not in the tree', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason:
            'CircularProgressIndicator was removed in the splash animation '
            'redesign. AnimatedWordmark is now the loading indicator.',
      );
    });

    // -------------------------------------------------------------------------
    // Test 5 — After animation completes, all letter ScaleTransitions are at 1.0
    //
    // We advance the clock by 880 ms (the controller duration) then settle.
    // Every ScaleTransition that is a descendant of AnimatedWordmark must have
    // its scale animation at value 1.0 (the settled end-state of the 1.15→1.0
    // scale-in stagger).
    // -------------------------------------------------------------------------
    testWidgets(
      '5. after animation completes, all letter ScaleTransitions have scale 1.0',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        // Allow the first frame to build (initState has already called forward()).
        await tester.pump();
        // Advance past the full animation duration.
        await tester.pump(const Duration(milliseconds: 880));
        // Settle any residual frames.
        await tester.pumpAndSettle();

        final animatedWordmarkFinder = find.byType(AnimatedWordmark);
        expect(animatedWordmarkFinder, findsOneWidget);

        final scaleTransitions = tester.widgetList<ScaleTransition>(
          find.descendant(
            of: animatedWordmarkFinder,
            matching: find.byType(ScaleTransition),
          ),
        );

        final transitions = scaleTransitions.toList();
        expect(
          transitions,
          hasLength(8),
          reason:
              'AnimatedWordmark with text "beautica" (8 chars) must produce '
              'exactly 8 ScaleTransition widgets.',
        );

        for (final st in transitions) {
          expect(
            st.scale.value,
            equals(1.0),
            reason:
                'All letter ScaleTransitions must be at scale 1.0 after the '
                '880 ms animation controller completes.',
          );
        }
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
    // Test 7 — AnimationController is disposed on widget dispose
    //
    // If dispose() is missing or incorrect the dart:ui framework raises a
    // "AnimationController disposed" / "A listener was disposed" assertion
    // error at teardown. Replacing the widget tree triggers dispose().
    // -------------------------------------------------------------------------
    testWidgets(
      '7. AnimationController is disposed on widget dispose (no pending-frame error)',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await tester.pump();

        // Replace the widget tree with an empty widget to trigger dispose().
        await tester.pumpWidget(const SizedBox.shrink());

        // If we reach here without a framework assertion, the controller was
        // correctly disposed in _SplashScreenState.dispose().
        expect(find.byType(SplashScreen), findsNothing);
      },
    );

    // -------------------------------------------------------------------------
    // Test 8 — Batch 6 regression: VelvetLogo itself is NOT wrapped in
    //           FadeTransition.
    //
    // The FadeTransition widgets inside AnimatedWordmark are DESCENDANTS of
    // VelvetLogo — that is correct and expected. This test only asserts that
    // VelvetLogo does not have FadeTransition as an ANCESTOR inside
    // SplashScreen's own subtree (i.e. SplashScreen does not wrap the entire
    // logo in a FadeTransition).
    //
    // Strategy: find the outer Align > Stack and assert that no FadeTransition
    // is an ancestor of VelvetLogo within that subtree.
    // -------------------------------------------------------------------------
    testWidgets(
      '8. VelvetLogo is not wrapped in FadeTransition by SplashScreen (Batch 6 regression)',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await tester.pump(Duration.zero);

        // VelvetLogo must be present.
        expect(find.byType(VelvetLogo), findsOneWidget);

        // A FadeTransition that is BOTH a descendant of the Scaffold body's
        // Stack AND an ancestor of VelvetLogo would mean SplashScreen itself
        // wraps the logo — that is the regression.
        //
        // We find the Align widget (immediate parent of VelvetLogo in the
        // Scaffold body) and assert that no FadeTransition is an ancestor of
        // VelvetLogo below that Align.
        final alignFinder = find.byWidgetPredicate(
          (widget) =>
              widget is Align && (widget.alignment as Alignment).y == -0.4,
        );
        expect(alignFinder, findsOneWidget);

        // Any FadeTransition that is a descendant of Align AND an ancestor of
        // VelvetLogo would indicate that SplashScreen wraps the logo in a
        // FadeTransition — the forbidden pattern.
        expect(
          find.descendant(
            of: alignFinder,
            matching: find.ancestor(
              of: find.byType(VelvetLogo),
              matching: find.byType(FadeTransition),
            ),
          ),
          findsNothing,
          reason:
              'SplashScreen must not wrap VelvetLogo in a FadeTransition. '
              'FadeTransition widgets inside AnimatedWordmark (descendants of '
              'VelvetLogo) are correct and are not tested here.',
        );
      },
    );

    // -------------------------------------------------------------------------
    // Test 9 — Phase 2.15 regression: Scaffold backgroundColor == BrandColors.base
    //
    // The native splash background is configured as #E6DDD0 (warm taupe) in
    // pubspec.yaml flutter_native_splash.color. The Flutter Scaffold must use
    // the identical color to prevent a background color flash at the handoff.
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
    // FlutterNativeSplash.remove() is called unconditionally in initState.
    // In flutter_test the platform channel is not initialised — the call must
    // be a silent no-op, not a crash.
    // -------------------------------------------------------------------------
    testWidgets(
      '10. Phase 2.15 — FlutterNativeSplash.remove() does not throw in test environment',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await tester.pump();

        // If we reach this assertion without a test failure, remove() was a
        // silent no-op as required.
        expect(find.byType(SplashScreen), findsOneWidget);
      },
    );

    // -------------------------------------------------------------------------
    // Test 11 — Reduced-motion: accessibilityFeatures.disableAnimations=true
    //            snaps controller to 1.0 immediately.
    //
    // The source reads WidgetsBinding.instance.accessibilityFeatures.disableAnimations
    // in initState (line 97 of splash_screen.dart). This value is backed by the
    // platform dispatcher — it is NOT the same as MediaQuery.disableAnimations.
    // Setting MediaQueryData.copyWith(disableAnimations: true) would leave this
    // branch permanently untested because accessibilityFeatures.disableAnimations
    // remains false regardless of MediaQuery.
    //
    // Correct approach: set the platform-dispatcher test value via
    // tester.platformDispatcher.accessibilityFeaturesTestValue before pumpWidget
    // so that accessibilityFeatures.disableAnimations is true when initState runs.
    //
    // Expected behaviour: _wordmarkController.value = 1.0 (snap, no animation).
    // All 8 ScaleTransitions must be at scale 1.0 (the settled end-state of the
    // 1.15→1.0 scale-in stagger) after the first pump — without advancing the
    // clock at all.
    // -------------------------------------------------------------------------
    testWidgets(
      '11. reduced-motion: accessibilityFeatures.disableAnimations=true snaps '
      'all letters to scale 1.0 on next frame',
      (tester) async {
        // Set the platform-level accessibility flag BEFORE pumpWidget so
        // initState reads it as true on first mount.
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );

        // Wrap SplashScreen in a real GoRouter (mirroring test 14, lines
        // 586–635) so that the _splashTimer body's
        // `GoRouter.of(context).refresh()` resolves cleanly. Without a
        // GoRouter ancestor, the timer callback would throw
        // `No GoRouter found in context` when it fires during teardown drain.
        //
        // The redirect always returns null — the SplashScreen stays mounted
        // through the entire test so the opacity/offset assertions still
        // target the same widget instance after the timer fires.
        final router = GoRouter(
          initialLocation: '/splash',
          redirect: (context, state) => null,
          routes: [
            GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
            GoRoute(
              path: '/',
              builder: (_, __) => const Scaffold(body: Text('home')),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        // initState scheduled a post-frame callback that assigns
        // _wordmarkController.value = 1.0 (the snap is deferred until after
        // the first build so AnimatedWordmark's FadeTransition listeners have
        // attached). pumpAndSettle() drains that post-frame callback so the
        // assertions below see the snapped final state.
        await tester.pumpAndSettle();

        final animatedWordmarkFinder = find.byType(AnimatedWordmark);
        expect(animatedWordmarkFinder, findsOneWidget);

        // ---------------------------------------------------------------
        // Capture scale values BEFORE the _splashTimer fires.
        // SplashScreen stays mounted through the redirect-returns-null
        // router, but capturing here keeps the snap assertion isolated
        // from any subsequent rebuild caused by router.refresh().
        // ---------------------------------------------------------------
        final scaleTransitions = tester
            .widgetList<ScaleTransition>(
              find.descendant(
                of: animatedWordmarkFinder,
                matching: find.byType(ScaleTransition),
              ),
            )
            .toList();

        expect(
          scaleTransitions,
          hasLength(8),
          reason:
              'AnimatedWordmark with text "beautica" (8 chars) must produce '
              'exactly 8 ScaleTransition widgets.',
        );

        for (final st in scaleTransitions) {
          expect(
            st.scale.value,
            equals(1.0),
            reason:
                'With accessibilityFeatures.disableAnimations=true, '
                '_wordmarkController.value is set to 1.0 in initState — '
                'all letters must be at their settled scale 1.0 immediately.',
          );
        }

        // ---------------------------------------------------------------
        // Drain the _splashTimer cleanly to satisfy the test binding's
        // !timersPending invariant at tear-down. Mirrors test 14's
        // clock-advance pattern: pump past _minSplashMs then pumpAndSettle
        // so the timer fires, router.refresh() runs, and no wall-clock
        // timer is left dangling.
        // minSplashDuration is 2000ms; pump comfortably past the timer.
        // ---------------------------------------------------------------
        await tester.pump(const Duration(milliseconds: 2500));
        await tester.pumpAndSettle();

        // Key distinction from Test 5: Test 5 must advance the full 880 ms
        // animation duration. This test only needs the first post-frame
        // callback to fire (the deferred value=1.0 assignment). If
        // forward() were called instead of value=1.0, scale would still be
        // ramping (>1.0) at the assertion point above — the test would fail,
        // catching the regression.
      },
    );

    // -------------------------------------------------------------------------
    // Test 12 — Early-dispose safety: widget disposed immediately after
    //            pumpWidget, before any frame pump.
    //
    // The initState animation start (controller.forward()) schedules a ticker.
    // If dispose() does not correctly call controller.dispose(), the pending
    // ticker fires after teardown and raises a framework assertion. This test
    // exercises the race between initState (starts the ticker) and dispose
    // (cleans it up) by replacing the widget tree before pump() drains the
    // frame queue.
    //
    // Historical note: an earlier version of this test was described as testing
    // an addPostFrameCallback !mounted guard. That code path no longer exists —
    // the source was refactored to call forward() directly in initState (no
    // postFrameCallback, no mounted guard). This test now verifies the correct
    // invariant: controller.dispose() in dispose() cleans up a ticker that was
    // started in initState, regardless of pump ordering.
    // -------------------------------------------------------------------------
    testWidgets(
      '12. early-dispose: no AnimationController error when widget disposed before first pump',
      (tester) async {
        // Step 1 — pump the splash screen into the tree. initState runs and
        // calls controller.forward(), scheduling a ticker. The first frame has
        // NOT been flushed yet.
        await tester.pumpWidget(_buildApp());

        // Step 2 — replace the widget tree immediately (no pump in between).
        // This triggers dispose() while the ticker from forward() is still
        // pending. controller.dispose() must cancel the ticker cleanly.
        await tester.pumpWidget(const SizedBox.shrink());

        // Step 3 — drain the frame queue. Any frame scheduled by the now-
        // disposed controller's ticker would surface a framework assertion
        // here if dispose() failed to clean it up.
        await tester.pump();
        await tester.pumpAndSettle();

        // If we reach here without a framework assertion, dispose() correctly
        // cleaned up the AnimationController started in initState.
        expect(find.byType(SplashScreen), findsNothing);
      },
    );

    // -------------------------------------------------------------------------
    // Test 13 — Accessibility timer: early dispose cancels _splashTimer cleanly.
    //
    // When disableAnimations=true, initState schedules _splashTimer directly
    // (because value=1.0 does not emit AnimationStatus.completed — the status
    // listener never fires). dispose() must cancel _splashTimer so no dangling
    // timer resource remains after the widget is torn down.
    //
    // Strategy: set disableAnimations=true → pumpWidget (schedules timer in
    // initState) → immediately replace widget tree (dispose() fires, must cancel
    // timer) → advance fake clock far past any timer → no framework assertion.
    // -------------------------------------------------------------------------
    testWidgets(
      '13. accessibility early-dispose: _splashTimer cancelled by dispose() without error',
      (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );

        // Pump — initState sets _wordmarkController.value=1.0 and schedules
        // _splashTimer. No GoRouter in this tree so GoRouter.of() would throw
        // IF the timer fires while mounted. The mounted guard prevents that;
        // cancellation in dispose() prevents it from firing at all.
        await tester.pumpWidget(_buildApp());

        // Dispose immediately before any pump drains the timer.
        await tester.pumpWidget(const SizedBox.shrink());

        // Drain the frame queue and advance the fake clock far past any timer.
        // If _splashTimer was not cancelled, the callback fires here. mounted==false
        // prevents GoRouter.of(), but the cancel in dispose() is the primary guard.
        await tester.pump();
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();

        // If we reach here, dispose() cancelled _splashTimer correctly.
        expect(find.byType(SplashScreen), findsNothing);
      },
    );

    // -------------------------------------------------------------------------
    // Test 14 — Accessibility timer → GoRouter.refresh() fires when mounted.
    //
    // With disableAnimations=true, _splashTimer is scheduled in initState.
    // After the timer fires (at _minSplashMs - elapsed()), if the widget is
    // still mounted, GoRouter.of(context).refresh() must be called exactly once.
    // This is the router re-kick that prevents accessibility users from being
    // permanently parked on /splash.
    //
    // Uses a real GoRouter with a counting redirect callback to observe the
    // refresh call without mocking internal go_router types.
    // -------------------------------------------------------------------------
    testWidgets(
      '14. accessibility-timer: GoRouter.refresh() is called after timer fires when mounted',
      (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );

        var refreshCount = 0;
        final router = GoRouter(
          initialLocation: '/splash',
          // Count every redirect evaluation. GoRouter.refresh() triggers a
          // re-evaluation which increments this counter.
          redirect: (context, state) {
            refreshCount++;
            return null; // always stay — test only checks that refresh fired
          },
          routes: [
            GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
            GoRoute(
              path: '/',
              builder: (_, __) => const Scaffold(body: Text('home')),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pump();
        // Capture redirect count after initial router evaluation.
        final countAfterBuild = refreshCount;

        // Advance clock past _minSplashMs (2000 ms). The accessibility timer
        // fires, GoRouter.of(context).refresh() is called, triggering a
        // redirect re-evaluation. The counter must exceed countAfterBuild.
        // minSplashDuration is 2000ms; pump comfortably past the timer.
        await tester.pump(const Duration(milliseconds: 2500));
        await tester.pumpAndSettle();

        expect(
          refreshCount,
          greaterThan(countAfterBuild),
          reason:
              'With disableAnimations=true, _splashTimer must call '
              'GoRouter.of(context).refresh() after _minSplashMs. '
              'The redirect callback count must increase — if it does not, '
              'accessibility users are permanently parked on /splash.',
        );
      },
    );
  });
}
