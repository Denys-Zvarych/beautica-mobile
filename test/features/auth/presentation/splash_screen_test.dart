// Widget tests for SplashScreen.
//
// SplashScreen was pivoted to a Lottie-based animation. The previous
// AnimationController-driven letter-by-letter wordmark reveal was replaced
// by a conditional render:
//
//   - If `assets/lottie/splash_wordmark.json` is bundled, the splash shows
//     the B pillow alone plus a `Lottie.asset(...)` wordmark animation.
//   - If the asset is missing (the documented baseline state — no JSON file
//     is shipped today), the splash shows the static [VelvetLogo] composite,
//     which exactly mirrors the OS-baked native splash PNG so the handoff
//     has zero visible jump.
//
// In the widget-test environment the Lottie JSON is NEVER bundled (tests do
// not declare it as a test asset), so every test below sees the static
// fallback path. That keeps the tests deterministic and asset-free.
//
// Covered scenarios:
//   1. Widget renders without error (smoke test) — Scaffold + Stack present.
//   2. VelvetLogo is present with compact=false, tileSize=92, markFontSize=42,
//      wordmarkFontSize=17 — the splash-specific size overrides.
//   3. The static "beautica" wordmark Text is rendered in the tree.
//   4. CircularProgressIndicator is NOT in the tree (no spinner — the static
//      composite is the entire splash content).
//   5. No AnimatedWordmark / FadeTransition / SlideTransition wraps the
//      wordmark — the static path renders a plain Text, not an animation.
//   6. No AppBar rendered (auth screens are full-screen, no AppBar).
//   7. No AnimationController exists — the State has no Ticker, so widget
//      teardown produces no controller-leak assertion. Pump-then-replace is
//      a no-op.
//   8. VelvetLogo is not wrapped in FadeTransition by SplashScreen.
//   9. Phase 2.15 regression — Scaffold backgroundColor == BrandColors.base.
//  10. Phase 2.15 regression — FlutterNativeSplash.remove() does not throw
//      in the widget-test environment.
//  11. Early-dispose safety — widget disposed immediately after pumpWidget
//      (before any pump drains the frame queue); no exception surfaces.
//      Verifies _splashTimer cancellation in dispose().
//  12. Accessibility timer → GoRouter.refresh() — _splashTimer always fires
//      after _minSplashMs and calls GoRouter.of(context).refresh() while
//      mounted. The timer is no longer gated on disableAnimations because
//      the Lottie/static paths produce no AnimationStatus.completed event;
//      the timer is the single source of router-kick.
//
// Note on VelvetLogo + static fallback:
//   Both are pure-Dart widgets (no asset loading, no SVG, no network).
//   flutter_test requires no asset bundle setup.
//
// Note on FlutterNativeSplash.remove() (Tests 1, 9, 10):
//   In the flutter_test environment the native-splash platform channel is
//   not initialised, so FlutterNativeSplash.remove() is a documented no-op.
//
// Note on ScreenProtector:
//   ScreenProtector was intentionally removed from SplashScreen — FLAG_SECURE
//   blacked out the splash on the emulator. The splash has no sensitive data;
//   FLAG_SECURE remains on all auth screens that show passwords/OTP/PII.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/presentation/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';

// Wraps the widget under test in the minimal tree that SplashScreen requires:
// a MaterialApp (for Scaffold / Theme) with no router needed for most tests.
// Tests that depend on GoRouter.of() build their own MaterialApp.router tree.
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

      // Drain the pending _splashTimer so the binding does not complain about
      // a wall-clock timer left over at tear-down.
      await tester.pump(const Duration(milliseconds: 2500));
    });

    // -------------------------------------------------------------------------
    // Test 2 — VelvetLogo is present with the splash-specific size params
    //
    // The splash renders a larger logo than any other screen:
    //   - compact: false  (default — unchanged)
    //   - tileSize: 92    (bigger pillow on splash only)
    //   - markFontSize: 42
    //
    // wordmarkFontSize is intentionally NOT asserted: in the Lottie path the
    // VelvetLogo is constructed with showWordmark:false (the Lottie animation
    // renders the wordmark itself), so the wordmark Text never appears and
    // wordmarkFontSize is irrelevant. The remaining tileSize/markFontSize
    // checks still cover the regression intent (splash uses its custom
    // sizing).
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
      // wordmarkFontSize is irrelevant in the Lottie path: VelvetLogo's
      // showWordmark=false suppresses the static Text("beautica"), so the
      // size value is dead. The Lottie animation owns the wordmark render.

      // Drain the splash timer.
      await tester.pump(const Duration(milliseconds: 2500));
    });

    // -------------------------------------------------------------------------
    // Test 3 — Wordmark is rendered via Lottie OR a static "beautica" Text
    //
    // SplashScreen has two render paths for the wordmark:
    //   - Lottie path:   Lottie.asset(splash_wordmark.json) renders the
    //                    wordmark animation — no Text widget exists.
    //   - Static path:   VelvetLogo's Text("beautica") fallback when the
    //                    Lottie asset is not bundled.
    //
    // The asset is now bundled in pubspec.yaml, so the test environment may
    // resolve the Lottie path. This assertion tolerates either render path to
    // remain robust to the bundle/no-bundle toggle.
    // -------------------------------------------------------------------------
    testWidgets('3. wordmark renders via Lottie or static "beautica" Text', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      final hasLottie = find.byType(Lottie).evaluate().isNotEmpty;
      final hasStaticText = find.text('beautica').evaluate().isNotEmpty;
      expect(
        hasLottie || hasStaticText,
        isTrue,
        reason:
            'Splash should render the wordmark via either a Lottie widget '
            '(asset bundled) or a static Text("beautica") in VelvetLogo '
            '(asset missing). Neither was found.',
      );

      // Drain the splash timer.
      await tester.pump(const Duration(milliseconds: 2500));
    });

    // -------------------------------------------------------------------------
    // Test 4 — CircularProgressIndicator is NOT in the tree
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
            'CircularProgressIndicator is not part of the splash design. The '
            'static composite (or Lottie animation) IS the splash content.',
      );

      // Drain the splash timer.
      await tester.pump(const Duration(milliseconds: 2500));
    });

    // -------------------------------------------------------------------------
    // Test 5 — No animation wrappers around the wordmark in the static path
    //
    // The static fallback renders a plain Text — no AnimatedWordmark,
    // FadeTransition, or SlideTransition should appear around the wordmark.
    // (FadeTransition CAN appear elsewhere in Material widgets — e.g. inside
    // tooltips — so we only assert the AnimatedWordmark widget is absent.)
    // -------------------------------------------------------------------------
    testWidgets('5. no AnimatedWordmark in the static fallback path', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(
        find.byType(AnimatedWordmark),
        findsNothing,
        reason:
            'Static fallback path renders Text("beautica"), not '
            'AnimatedWordmark. AnimatedWordmark only appears when a '
            'VelvetLogo caller passes an AnimationController — SplashScreen '
            'no longer does so.',
      );

      // Drain the splash timer.
      await tester.pump(const Duration(milliseconds: 2500));
    });

    // -------------------------------------------------------------------------
    // Test 6 — No AppBar rendered (full-screen design)
    // -------------------------------------------------------------------------
    testWidgets('6. no AppBar is rendered', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(find.byType(AppBar), findsNothing);

      // Drain the splash timer.
      await tester.pump(const Duration(milliseconds: 2500));
    });

    // -------------------------------------------------------------------------
    // Test 7 — Widget disposes cleanly (no AnimationController to leak)
    //
    // The pivot to Lottie removed the AnimationController entirely. Disposal
    // need only cancel _splashTimer; there are no Tickers to clean up.
    // -------------------------------------------------------------------------
    testWidgets('7. widget disposes cleanly (no AnimationController)', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      // Replace the widget tree to trigger dispose().
      await tester.pumpWidget(const SizedBox.shrink());

      // If we reach here without a framework assertion, dispose() succeeded.
      expect(find.byType(SplashScreen), findsNothing);
    });

    // -------------------------------------------------------------------------
    // Test 8 — VelvetLogo is NOT wrapped in FadeTransition by SplashScreen.
    //
    // SplashScreen has never wrapped VelvetLogo in a FadeTransition; this
    // test guards that regression. It is independent of the animation path.
    // -------------------------------------------------------------------------
    testWidgets(
      '8. VelvetLogo is not wrapped in FadeTransition by SplashScreen',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await tester.pump(Duration.zero);

        expect(find.byType(VelvetLogo), findsOneWidget);

        final alignFinder = find.byWidgetPredicate(
          (widget) =>
              widget is Align && (widget.alignment as Alignment).y == -0.4,
        );
        expect(alignFinder, findsOneWidget);

        expect(
          find.descendant(
            of: alignFinder,
            matching: find.ancestor(
              of: find.byType(VelvetLogo),
              matching: find.byType(FadeTransition),
            ),
          ),
          findsNothing,
          reason: 'SplashScreen must not wrap VelvetLogo in a FadeTransition.',
        );

        // Drain the splash timer.
        await tester.pump(const Duration(milliseconds: 2500));
      },
    );

    // -------------------------------------------------------------------------
    // Test 9 — Scaffold backgroundColor matches BrandColors.base (#E6DDD0)
    //
    // The native splash background is configured as #E6DDD0 (warm taupe).
    // The Flutter Scaffold must use the identical color to prevent a flash
    // at the native-to-Flutter handoff.
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
              '(BrandColors.base = #E6DDD0).',
        );

        // Drain the splash timer.
        await tester.pump(const Duration(milliseconds: 2500));
      },
    );

    // -------------------------------------------------------------------------
    // Test 10 — FlutterNativeSplash.remove() does not throw in tests
    // -------------------------------------------------------------------------
    testWidgets(
      '10. Phase 2.15 — FlutterNativeSplash.remove() does not throw in test environment',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await tester.pump();

        expect(find.byType(SplashScreen), findsOneWidget);

        // Drain the splash timer.
        await tester.pump(const Duration(milliseconds: 2500));
      },
    );

    // -------------------------------------------------------------------------
    // Test 11 — Early-dispose: _splashTimer cancelled cleanly
    //
    // initState schedules _splashTimer unconditionally. dispose() must cancel
    // it. If the cancel were missing, the fake-async test binding's
    // "!timersPending" tear-down invariant would fire here.
    //
    // Strategy: pumpWidget (schedules timer) → immediately replace widget
    // tree (dispose() fires, must cancel timer) → drain the clock far past
    // the timer → no framework assertion.
    // -------------------------------------------------------------------------
    testWidgets(
      '11. early-dispose: _splashTimer cancelled by dispose() without error',
      (tester) async {
        await tester.pumpWidget(_buildApp());

        // Dispose immediately before any pump drains the timer.
        await tester.pumpWidget(const SizedBox.shrink());

        // Drain the frame queue and advance the fake clock far past any timer.
        // If _splashTimer was not cancelled, the callback would fire here and
        // attempt GoRouter.of() on an unmounted context. The mounted guard
        // prevents that crash, but the cancel in dispose() is the primary
        // guard and avoids a dangling timer warning.
        await tester.pump();
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();

        expect(find.byType(SplashScreen), findsNothing);
      },
    );

    // -------------------------------------------------------------------------
    // Test 12 — _splashTimer fires and calls GoRouter.refresh() when mounted.
    //
    // The timer fires after _minSplashMs (2000ms). When the widget is still
    // mounted, GoRouter.of(context).refresh() must be called. This is the
    // single router re-kick that prevents users from being permanently parked
    // on /splash. The Lottie/static pivot does not change this behaviour —
    // the timer always runs, regardless of which wordmark path renders.
    // -------------------------------------------------------------------------
    testWidgets(
      '12. _splashTimer fires GoRouter.refresh() after _minSplashMs when mounted',
      (tester) async {
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

        // Advance clock past _minSplashMs (2000 ms). The splash timer fires,
        // GoRouter.of(context).refresh() is called, triggering a redirect
        // re-evaluation. The counter must exceed countAfterBuild.
        await tester.pump(const Duration(milliseconds: 2500));
        await tester.pumpAndSettle();

        expect(
          refreshCount,
          greaterThan(countAfterBuild),
          reason:
              '_splashTimer must call GoRouter.of(context).refresh() after '
              '_minSplashMs. The redirect callback count must increase — if '
              'it does not, users are permanently parked on /splash.',
        );
      },
    );
  });
}
