// Widget tests for SplashScreen.
//
// SplashScreen uses a tri-state Lottie probe (`bool? _lottieAvailable`):
//
//   null  → probing. The B-pillow alone is centered; no wordmark renders.
//           The Lottie reveal owns the FIRST appearance of "beautica" on
//           cold start (no static-text flash beats the animation). The OS
//           native splash above shows ONLY the warm-taupe bg colour, so the
//           Flutter splash is the sole place the logo paints.
//   true  → asset resolved. Renders B-pillow + Lottie.asset() reveal below
//           it as a sibling Positioned (the pillow does NOT shift upward).
//   false → asset failed. Renders B-pillow + a plain Text("beautica") below
//           it as a sibling Positioned — same position as the Lottie path —
//           so the wordmark is at least visible. Better a static name than
//           no name.
//
// Critical layout invariant: in ALL three states, the B-pillow is rendered
// by a SINGLE [VelvetLogo] with `showWordmark:false`, centered via
// `Align(Alignment.center, ...)`. Its on-screen position is identical in
// every state — the wordmark sibling appears below it without reflowing the
// pillow. This guards the "B-pillow jumps upward when Lottie renders"
// regression that the earlier Column-based layout produced.
//
// In the widget-test environment the rootBundle.load() probe is async; the
// first frame after pumpWidget() therefore sees the `null` (probing) state
// and renders the B-only VelvetLogo. After pumping the probe future
// resolves to either `true` or `false` depending on whether the Lottie
// asset is declared in pubspec.yaml (it is, today, so most tests can land
// in the Lottie path after pumping). The tests below are written to be
// robust to all three states by either asserting on the initial probing
// frame or by tolerating both final paths.
//
// Covered scenarios:
//   1. Widget renders without error (smoke test) — Scaffold + Stack present.
//   2. VelvetLogo is present with compact=false, tileSize=92, markFontSize=42,
//      showWordmark=false — the B-pillow is rendered as a single SVG-less
//      composite, wordmark slot empty (the sibling Lottie / Text owns the
//      wordmark). Asserted in EVERY tri-state branch.
//   3a. Lottie wordmark renders when the splash_wordmark.json asset resolves
//      (the default pubspec setup). Static "beautica" Text must NOT coexist.
//   3b. Static wordmark renders below the B-pillow when the Lottie asset
//      fails to load — the `_lottieAvailable == false` branch —
//      deterministically triggered by mocking the `flutter/assets` platform
//      channel so rootBundle.load() returns null bytes for the Lottie key
//      (which PlatformAssetBundle converts into a FlutterError throw). The
//      VelvetLogo still has showWordmark:false in this branch; the wordmark
//      Text is a SIBLING widget in the Stack, positioned below the pillow.
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
//   flutter_test requires no asset bundle setup for the Lottie-success path.
//
//   The static-fallback branch (test 3b) is exercised by intercepting the
//   `flutter/assets` platform channel: when the mock handler returns null
//   bytes for the Lottie key, PlatformAssetBundle.load() throws FlutterError,
//   which lands in _checkLottieAsset()'s catch block. This is the only
//   deterministic way to reach the `_lottieAvailable == false` branch because
//   SplashScreen reads via rootBundle directly (not DefaultAssetBundle.of),
//   so wrapping the widget tree in a custom AssetBundle would not intercept
//   the call.
//
// Note on FlutterNativeSplash.remove() (Tests 1, 9, 10):
//   In the flutter_test environment the native-splash platform channel is
//   not initialised, so FlutterNativeSplash.remove() is a documented no-op.
//
// Note on ScreenProtector:
//   ScreenProtector was intentionally removed from SplashScreen — FLAG_SECURE
//   blacked out the splash on the emulator. The splash has no sensitive data;
//   FLAG_SECURE remains on all auth screens that show passwords/OTP/PII.

import 'dart:convert';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/presentation/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      // pumps past minSplashDuration = 3000ms
      await tester.pump(const Duration(milliseconds: 3500));
    });

    // -------------------------------------------------------------------------
    // Test 2 — VelvetLogo is present with the splash-specific size params
    //
    // The splash renders the logo at sizes chosen to match the Android 12 OS
    // native splash icon scale (~192 dp icon area), so the handoff from the
    // OS splash to the Flutter splash does not produce a visible jump:
    //   - compact: false   (default — unchanged)
    //   - tileSize: 92
    //   - markFontSize: 42
    //
    // wordmarkFontSize is intentionally NOT asserted: the initial frame
    // sees the tri-state probing state (`_lottieAvailable == null`), which
    // constructs VelvetLogo with showWordmark:false so the wordmark first
    // appears via the Lottie reveal. In that state the wordmark Text is
    // never built and wordmarkFontSize is dead. The remaining
    // tileSize/markFontSize checks cover the regression intent (splash uses
    // its custom sizing regardless of probe state).
    // -------------------------------------------------------------------------
    testWidgets('2. VelvetLogo present with splash-specific size params', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(
        find.byType(VelvetLogo),
        findsOneWidget,
        reason:
            'SplashScreen must render exactly one VelvetLogo in the initial '
            'probing frame (showWordmark:false, B pillow only).',
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
        reason:
            'Splash uses a 92 dp pillow — sized to match the Android 12 OS '
            'native splash icon area (~192 dp) so the OS→Flutter handoff '
            'shows no visible logo-size jump.',
      );
      expect(
        logo.markFontSize,
        equals(42.0),
        reason: 'Splash "B" glyph is 42 sp — proportional to the 92 dp pillow.',
      );
      expect(
        logo.showWordmark,
        isFalse,
        reason:
            'Initial probing frame must construct VelvetLogo with '
            'showWordmark:false so the static "beautica" text does not '
            'flash before the Lottie reveal. The wordmark must first '
            'appear via the Lottie animation, not via static text.',
      );

      // Drain the splash timer.
      // pumps past minSplashDuration = 3000ms
      await tester.pump(const Duration(milliseconds: 3500));
    });

    // -------------------------------------------------------------------------
    // Test 3a — Lottie-success branch (`_lottieAvailable == true`).
    //
    // pubspec.yaml bundles splash_wordmark.json, so the default rootBundle
    // resolves the asset and the build switches into the Lottie path after a
    // couple of pumps. Lottie owns the wordmark slot exclusively — no static
    // "beautica" Text may coexist (that would be a double-wordmark regression).
    // -------------------------------------------------------------------------
    testWidgets('3a. Lottie wordmark renders when asset resolves', (
      tester,
    ) async {
      // pubspec.yaml bundles the asset, so the default rootBundle succeeds.
      await tester.pumpWidget(_buildApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.byType(Lottie),
        findsOneWidget,
        reason:
            'When splash_wordmark.json is bundled (the default pubspec setup), '
            'the Lottie widget must render. If this fails, _lottieAssetPath '
            'may have drifted from the pubspec asset path.',
      );
      expect(
        find.text('beautica'),
        findsNothing,
        reason:
            'Lottie owns the wordmark slot exclusively in the success branch — '
            'no static Text("beautica") may coexist.',
      );

      // Drain the splash timer.
      // pumps past minSplashDuration = 3000ms
      await tester.pump(const Duration(milliseconds: 3500));
    });

    // -------------------------------------------------------------------------
    // Test 3b — Static-fallback branch (`_lottieAvailable == false`).
    //
    // SplashScreen._checkLottieAsset() calls `rootBundle.load(_lottieAssetPath)`
    // directly (not via DefaultAssetBundle.of(context)), so a wrapping
    // DefaultAssetBundle would NOT intercept the call. The only deterministic
    // way to make `rootBundle.load(...)` fail is to mock the `flutter/assets`
    // platform channel that PlatformAssetBundle.load() drives — when the
    // handler returns null bytes for the Lottie key, PlatformAssetBundle
    // throws FlutterError, which lands in _checkLottieAsset()'s catch block
    // and fires setState(_lottieAvailable = false).
    //
    // The static fallback must produce the full VelvetLogo composite with
    // showWordmark:true and wordmarkFontSize:17 — better a static wordmark
    // than no wordmark.
    // -------------------------------------------------------------------------
    testWidgets('3b. static wordmark renders when Lottie asset fails to load', (
      tester,
    ) async {
      // Force-fail rootBundle.load() for the Lottie asset key by intercepting
      // the `flutter/assets` channel and returning null bytes (which
      // PlatformAssetBundle.load() converts into a FlutterError throw).
      // The Lottie key is URL-encoded by PlatformAssetBundle before send().
      const encodedLottieKey = 'assets/lottie/splash_wordmark.json';
      tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        'flutter/assets',
        (ByteData? message) async {
          if (message == null) return null;
          final key = utf8.decode(message.buffer.asUint8List());
          if (key == encodedLottieKey) {
            // Return null bytes → PlatformAssetBundle throws → catch branch.
            return null;
          }
          // Any other asset request also returns null. SplashScreen does not
          // load any other assets via flutter/assets in this test path: the
          // Lottie widget is never constructed (probe fails), and VelvetLogo
          // is pure Dart. If a future change adds another asset load here,
          // this stub must be widened to defer non-Lottie keys.
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMessageHandler(
          'flutter/assets',
          null,
        );
      });

      await tester.pumpWidget(_buildApp());
      await tester.pump();
      // Let _checkLottieAsset's rootBundle.load() future fail and the catch
      // branch fire setState(_lottieAvailable = false).
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.byType(Lottie),
        findsNothing,
        reason:
            'When the Lottie asset fails to load, the splash must NOT render '
            'a Lottie widget — the static Text fallback owns the wordmark slot.',
      );
      expect(
        find.text('beautica'),
        findsOneWidget,
        reason:
            'When the Lottie asset fails to load, a static Text("beautica") '
            'must render — better a static wordmark than no wordmark.',
      );

      // The B-pillow is rendered as a single VelvetLogo with showWordmark:false
      // in EVERY tri-state branch (including this static-fallback branch). The
      // wordmark Text is a SIBLING widget in the splash Stack, not built by
      // VelvetLogo. This decouples the wordmark from the pillow's layout so
      // the pillow's on-screen position never shifts between states.
      final logo = tester.widget<VelvetLogo>(find.byType(VelvetLogo));
      expect(
        logo.showWordmark,
        isFalse,
        reason:
            'The splash B-pillow uses VelvetLogo(showWordmark:false) in every '
            'tri-state branch so the pillow is positioned identically when '
            'the wordmark sibling renders. The static-fallback wordmark is a '
            'sibling Text in the Stack, not a VelvetLogo-built child.',
      );

      // Verify the sibling Text uses the splash-specific wordmark font size
      // (17 sp). The Text style is VelvetText.wordmark().copyWith(fontSize:
      // 17) — identical to what VelvetLogo would have rendered internally
      // for wordmarkFontSize:17, so the fallback path is visually
      // indistinguishable from the legacy composite.
      final Text wordmarkText = tester.widget<Text>(find.text('beautica'));
      expect(
        wordmarkText.style?.fontSize,
        equals(17.0),
        reason:
            'Static-fallback wordmark Text must be 17 sp — proportional to '
            'the 92 dp pillow. If this fails the splash visually regresses '
            'on the Lottie-failure path.',
      );

      // Drain the splash timer.
      // pumps past minSplashDuration = 3000ms
      await tester.pump(const Duration(milliseconds: 3500));
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
      // pumps past minSplashDuration = 3000ms
      await tester.pump(const Duration(milliseconds: 3500));
    });

    // -------------------------------------------------------------------------
    // Test 5 — No AnimatedWordmark widget in any of the tri-state branches
    //
    // SplashScreen no longer passes an AnimationController to VelvetLogo, so
    // AnimatedWordmark is never built. This holds in all three states:
    // probing (B-only), Lottie path (Lottie owns the wordmark), and static
    // fallback (plain Text("beautica")). FadeTransition is NOT asserted
    // absent — it can appear inside unrelated Material widgets (tooltips,
    // page transitions) — we only guard the project-specific
    // AnimatedWordmark.
    // -------------------------------------------------------------------------
    testWidgets('5. no AnimatedWordmark is built in any tri-state branch', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(
        find.byType(AnimatedWordmark),
        findsNothing,
        reason:
            'SplashScreen never constructs a VelvetLogo with an '
            'AnimationController, so AnimatedWordmark must not appear in '
            'any tri-state branch (probing, Lottie, static).',
      );

      // Drain the splash timer.
      // pumps past minSplashDuration = 3000ms
      await tester.pump(const Duration(milliseconds: 3500));
    });

    // -------------------------------------------------------------------------
    // Test 6 — No AppBar rendered (full-screen design)
    // -------------------------------------------------------------------------
    testWidgets('6. no AppBar is rendered', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(find.byType(AppBar), findsNothing);

      // Drain the splash timer.
      // pumps past minSplashDuration = 3000ms
      await tester.pump(const Duration(milliseconds: 3500));
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
              widget.runtimeType == Align &&
              ((widget as Align).alignment as Alignment).y == 0.0,
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
        // pumps past minSplashDuration = 3000ms
        await tester.pump(const Duration(milliseconds: 3500));
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
        // pumps past minSplashDuration = 3000ms
        await tester.pump(const Duration(milliseconds: 3500));
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
        // pumps past minSplashDuration = 3000ms
        await tester.pump(const Duration(milliseconds: 3500));
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
    // The timer fires after _minSplashMs (3000ms). When the widget is still
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

        // Advance clock past _minSplashMs (3000 ms). The splash timer fires,
        // GoRouter.of(context).refresh() is called, triggering a redirect
        // re-evaluation. The counter must exceed countAfterBuild.
        // pumps past minSplashDuration = 3000ms
        await tester.pump(const Duration(milliseconds: 3500));
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
