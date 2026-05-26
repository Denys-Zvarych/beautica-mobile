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
//      letter FadeTransition has opacity 1.0.
//   6. No AppBar rendered (auth screens are full-screen, no AppBar).
//   7. AnimationController is disposed on widget dispose (no pending-frame
//      error; replaces the old "Timer cancelled" test).
//   8. Batch 6 regression — VelvetLogo itself is NOT wrapped in FadeTransition.
//      FadeTransition widgets inside AnimatedWordmark are descendants of
//      VelvetLogo — that is correct and must NOT trigger this assertion.
//   9. Phase 2.15 regression — Scaffold backgroundColor == BrandColors.base.
//  10. Phase 2.15 regression — FlutterNativeSplash.remove() does not throw
//      in the widget-test environment.
//  11. Reduced-motion — with disableAnimations=true, controller snaps to
//      value 1.0 after first pump; all letter FadeTransitions have opacity 1.0.
//
// Note on VelvetLogo / AnimatedWordmark:
//   Both are pure-Dart widgets (no asset loading, no SVG, no network).
//   flutter_test requires no asset bundle setup.
//
// Note on FlutterNativeSplash.remove() (Tests 1, 9, 10):
//   In the flutter_test environment the native-splash platform channel is not
//   initialised, so FlutterNativeSplash.remove() is a documented no-op.

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
    // Test 5 — After animation completes, all letter FadeTransitions are at 1.0
    //
    // We advance the clock by 880 ms (the controller duration) then settle.
    // Every FadeTransition that is a descendant of AnimatedWordmark must have
    // its opacity animation at value 1.0.
    // -------------------------------------------------------------------------
    testWidgets(
      '5. after animation completes, all letter FadeTransitions have opacity 1.0',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        // Trigger the post-frame callback that calls controller.forward().
        await tester.pump();
        // Advance past the full animation duration.
        await tester.pump(const Duration(milliseconds: 880));
        // Settle any residual frames.
        await tester.pumpAndSettle();

        final animatedWordmarkFinder = find.byType(AnimatedWordmark);
        expect(animatedWordmarkFinder, findsOneWidget);

        final fadeTransitions = tester.widgetList<FadeTransition>(
          find.descendant(
            of: animatedWordmarkFinder,
            matching: find.byType(FadeTransition),
          ),
        );

        final transitions = fadeTransitions.toList();
        expect(
          transitions,
          hasLength(8),
          reason:
              'AnimatedWordmark with text "beautica" (8 chars) must produce '
              'exactly 8 FadeTransition widgets.',
        );

        for (final ft in transitions) {
          expect(
            ft.opacity.value,
            equals(1.0),
            reason:
                'All letter FadeTransitions must be at opacity 1.0 after the '
                '880 ms animation controller completes.',
          );
        }

        // SlideTransition check — all positions must be Offset.zero after the
        // animation completes (each letter has slid fully into its final position).
        final slideTransitions = tester
            .widgetList<SlideTransition>(
              find.descendant(
                of: animatedWordmarkFinder,
                matching: find.byType(SlideTransition),
              ),
            )
            .toList();
        expect(
          slideTransitions,
          hasLength(8),
          reason:
              'AnimatedWordmark with text "beautica" (8 chars) must produce '
              'exactly 8 SlideTransition widgets.',
        );
        for (final st in slideTransitions) {
          expect(
            st.position.value,
            equals(Offset.zero),
            reason:
                'All letter SlideTransitions must be at Offset.zero after the '
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
    // -------------------------------------------------------------------------
    testWidgets(
      '10. Phase 2.15 — FlutterNativeSplash.remove() does not throw in test environment',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await tester.pump(); // triggers addPostFrameCallback

        // If we reach this assertion without a test failure, remove() was a
        // silent no-op as required.
        expect(find.byType(SplashScreen), findsOneWidget);
      },
    );

    // -------------------------------------------------------------------------
    // Test 11 — Reduced-motion: disableAnimations=true snaps controller to 1.0
    //
    // When MediaQuery.disableAnimations is true, initState's post-frame
    // callback sets _wordmarkController.value = 1.0 (skip animation).
    // All letter FadeTransitions must be at opacity 1.0 after the first settle.
    // -------------------------------------------------------------------------
    testWidgets(
      '11. reduced-motion: disableAnimations=true snaps all letters to opacity 1.0',
      (tester) async {
        await tester.pumpWidget(_buildApp(disableAnimations: true));
        // Trigger the post-frame callback that snaps the controller to 1.0.
        await tester.pump();
        // Settle any residual frames triggered by the value change.
        await tester.pumpAndSettle();

        final animatedWordmarkFinder = find.byType(AnimatedWordmark);
        expect(animatedWordmarkFinder, findsOneWidget);

        final fadeTransitions = tester.widgetList<FadeTransition>(
          find.descendant(
            of: animatedWordmarkFinder,
            matching: find.byType(FadeTransition),
          ),
        );

        final transitions = fadeTransitions.toList();
        expect(
          transitions,
          hasLength(8),
          reason:
              'AnimatedWordmark with text "beautica" (8 chars) must produce '
              'exactly 8 FadeTransition widgets.',
        );

        for (final ft in transitions) {
          expect(
            ft.opacity.value,
            equals(1.0),
            reason:
                'With disableAnimations=true, controller.value is snapped to '
                '1.0 — all letters must be fully visible immediately.',
          );
        }

        // SlideTransition check — all positions must be Offset.zero after the
        // controller snaps to 1.0 in reduced-motion mode.
        final slideTransitions = tester
            .widgetList<SlideTransition>(
              find.descendant(
                of: animatedWordmarkFinder,
                matching: find.byType(SlideTransition),
              ),
            )
            .toList();
        expect(
          slideTransitions,
          hasLength(8),
          reason:
              'AnimatedWordmark with text "beautica" (8 chars) must produce '
              'exactly 8 SlideTransition widgets.',
        );
        for (final st in slideTransitions) {
          expect(
            st.position.value,
            equals(Offset.zero),
            reason:
                'With disableAnimations=true, all letter SlideTransitions must '
                'be at Offset.zero after the controller snaps to 1.0.',
          );
        }
      },
    );
  });
}
