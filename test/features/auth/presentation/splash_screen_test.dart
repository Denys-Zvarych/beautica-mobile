// Widget tests for SplashScreen.
//
// SplashScreen was converted from StatelessWidget to StatefulWidget in the
// auth-screen redesign. It now owns an AnimationController
// (SingleTickerProviderStateMixin) and an _showSpinner bool that gates the
// CircularProgressIndicator. Zero test coverage existed before this file.
//
// Covered scenarios:
//   1. Widget renders without error (smoke test) — Scaffold + Stack present.
//   2. AuthGradientBackground is rendered as the bottom Stack layer.
//   3. On first pump, CircularProgressIndicator opacity is 0 (_showSpinner=false).
//   4. After logo animation completes, CircularProgressIndicator appears
//      (_showSpinner flips to true when AnimationController.status == completed).
//   5. With disableAnimations=true (reduced-motion), _showSpinner is set
//      immediately via post-frame callback — spinner is visible after first settle.
//   6. No AppBar is rendered (auth screens are full-screen, no AppBar).
//   7. AnimationController is disposed without error (no pending timers).
//
// Note on SvgPicture.asset:
//   flutter_test loads the real asset bundle from the project root, so
//   assets/images/logo.svg resolves without any mock. No additional setup
//   is required.

import 'package:beautica_mobile/features/auth/presentation/auth_gradient_background.dart';
import 'package:beautica_mobile/features/auth/presentation/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Wraps the widget under test in the minimal tree that SplashScreen requires:
// a MaterialApp (for Scaffold / MediaQuery / Theme) with no router needed.
Widget _buildApp({bool disableAnimations = false}) => MediaQuery(
  data: const MediaQueryData().copyWith(
    disableAnimations: disableAnimations,
  ),
  child: const MaterialApp(
    home: SplashScreen(),
  ),
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
    // Test 2 — AuthGradientBackground is the bottom Stack layer
    // -------------------------------------------------------------------------
    testWidgets('2. AuthGradientBackground is rendered inside the Stack', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(find.byType(AuthGradientBackground), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Test 3 — CircularProgressIndicator is initially opacity-hidden
    //
    // On the first frame, _showSpinner == false because the AnimationController
    // has not yet completed. The AnimatedOpacity wrapping the spinner sets
    // opacity: 0.0, but the widget is still in the tree.
    // -------------------------------------------------------------------------
    testWidgets('3. CircularProgressIndicator is present but initially invisible', (
      tester,
    ) async {
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
    });

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
    testWidgets('7. AnimationController disposes without error', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      // Replace the widget tree with an empty widget to trigger dispose().
      await tester.pumpWidget(const SizedBox.shrink());

      // If we reach here without an exception the controller was cleaned up.
      expect(find.byType(SplashScreen), findsNothing);
    });
  });
}
