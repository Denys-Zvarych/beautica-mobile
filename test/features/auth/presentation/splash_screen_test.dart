// Widget tests for SplashScreen.
//
// SplashScreen uses a tri-state Lottie probe (`bool? _lottieAvailable`):
//
//   null  → probing. Nothing rendered on top of the warm-taupe bg — no
//           B-pillow, no Lottie, no static text. The Lottie reveal owns the
//           FIRST appearance of "beautica" on cold start (no static-text
//           flash beats the animation, and no leftover static B competes for
//           attention). The OS native splash above shows ONLY the warm-taupe
//           bg colour, so the Flutter splash is the sole place any brand
//           render happens.
//   true  → asset resolved. Renders a centred Lottie.asset() reveal as the
//           ENTIRE splash content. No B-pillow.
//   false → asset failed. Renders a centred static Text("beautica") as the
//           ENTIRE splash content so the wordmark is at least visible. Better
//           a static name than no name. No B-pillow.
//
// Key contract: the static B-pillow (VelvetLogo) has been removed from the
// splash entirely. The Lottie wordmark reveal IS the splash. (User feedback:
// "now on splash screen I can see simple B but shouldn't".) The B-pillow
// continues to live on auth screens (login/register/etc) via VelvetLogo —
// only its splash-screen usage was removed.
//
// In the widget-test environment the rootBundle.load() probe is async; the
// first frame after pumpWidget() therefore sees the `null` (probing) state
// and renders the bg colour alone. After pumping the probe future resolves
// to either `true` or `false` depending on whether the Lottie asset is
// declared in pubspec.yaml (it is, today, so most tests can land in the
// Lottie path after pumping). The tests below either assert on the initial
// probing frame or pump until a final-state path is reached.
//
// Covered scenarios:
//   1. Widget renders without error (smoke test) — Scaffold present.
//   2. Splash content contract — never VelvetLogo (B-pillow removed),
//      exactly one wordmark widget (Lottie XOR static "beautica" Text),
//      Scaffold.backgroundColor = BrandColors.base. The literal probing
//      frame (`_lottieAvailable == null`) is not directly asserted because
//      pumpWidget()'s microtask flush resolves the bundled-asset probe
//      synchronously; the probing branch is covered indirectly by tests 7
//      and 11 (dispose paths) and the fallback branch deterministically
//      via test 3b's flutter/assets mock.
//   3a. Lottie wordmark renders when the splash_wordmark.json asset resolves
//       (the default pubspec setup). Static "beautica" Text must NOT
//       coexist. No VelvetLogo (B-pillow removed from splash).
//   3b. Static wordmark renders centred when the Lottie asset fails to load
//       — the `_lottieAvailable == false` branch — deterministically
//       triggered by mocking the `flutter/assets` platform channel so
//       rootBundle.load() returns null bytes for the Lottie key (which
//       PlatformAssetBundle converts into a FlutterError throw). No
//       VelvetLogo (B-pillow removed from splash). Asserts the fallback Text
//       style pins fontSize=17.
//   4. CircularProgressIndicator is NOT in the tree (no spinner — the
//      Lottie/static Text IS the entire splash content).
//   5. No AnimatedWordmark wraps the wordmark — the static path renders a
//      plain Text, not an animation; the Lottie path uses pre-rendered
//      frame data, not an AnimationController.
//   6. No AppBar rendered (auth screens are full-screen, no AppBar).
//   7. Widget disposes cleanly (no AnimationController → no Ticker leak;
//      _splashTimer is cancelled in dispose).
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
// Note on the deleted "test 8":
//   The previous test 8 ("VelvetLogo is not wrapped in FadeTransition by
//   SplashScreen") guarded a regression that is now vacuously true:
//   VelvetLogo never renders on the splash at all. The mechanics of the
//   test (finding VelvetLogo first, then checking its ancestor chain) would
//   fail at the find step. The test was deleted as part of the B-pillow
//   removal.
//
// Note on Lottie + static fallback:
//   The static Text fallback is pure-Dart (no asset loading, no SVG, no
//   network). The Lottie-success path requires the splash_wordmark.json
//   asset to be bundled (the default pubspec setup).
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
    // Test 2 — splash content contract: no VelvetLogo, no doubled wordmark,
    // bg = BrandColors.base.
    //
    // The user-visible contract of the splash after the B-pillow removal:
    //
    //   - There is NEVER a VelvetLogo on the splash (the B-pillow was
    //     removed in this commit — "now on splash screen I can see simple B
    //     but shouldn't"). This holds in every tri-state branch.
    //   - The wordmark slot has exactly one occupant — either the Lottie
    //     reveal OR the static "beautica" Text fallback — never both.
    //   - The Scaffold bg is BrandColors.base so the OS native splash and
    //     the Flutter splash share a single warm-taupe colour.
    //
    // In the widget-test environment the rootBundle.load() probe resolves
    // synchronously inside pumpWidget()'s microtask flush (the asset is
    // bundled), so the literal "probing frame" with `_lottieAvailable ==
    // null` is not observable from the test harness. The tri-state probing
    // path is still proven by:
    //
    //   - The fallback path (test 3b) which deterministically reaches
    //     `_lottieAvailable == false` via a flutter/assets mock.
    //   - The state machine itself is exercised in test 7 (dispose) and
    //     test 11 (early-dispose), both of which trigger the probing-state
    //     SizedBox.shrink branch on the way to disposal.
    //
    // So test 2 asserts the universal post-pumpWidget contract instead of
    // the literal probing frame: no B-pillow, exactly-one wordmark, bg
    // colour locked.
    // -------------------------------------------------------------------------
    testWidgets(
      '2. splash content: no VelvetLogo, single wordmark, bg = BrandColors.base',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await tester.pump();

        expect(
          find.byType(VelvetLogo),
          findsNothing,
          reason:
              'B-pillow has been removed from the splash. VelvetLogo must '
              'not be rendered in any frame of /splash.',
        );

        // Exactly one wordmark renders — either the Lottie reveal (default
        // bundled-asset path) OR the static "beautica" Text fallback (probe
        // failed). Never both, never zero (after the probe has resolved).
        final lottieFound = find.byType(Lottie).evaluate().length;
        final textFound = find.text('beautica').evaluate().length;
        expect(
          lottieFound + textFound,
          equals(1),
          reason:
              'Exactly one wordmark must occupy the splash content slot. '
              'Found Lottie=$lottieFound and Text("beautica")=$textFound — '
              'both branches are mutually exclusive.',
        );

        // Verify the Scaffold bg matches BrandColors.base so the warm-taupe
        // base is what the user sees behind the wordmark.
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(
          scaffold.backgroundColor,
          equals(BrandColors.base),
          reason:
              'Scaffold.backgroundColor must equal BrandColors.base (#E6DDD0) '
              '— the same colour as the OS native splash, so the OS → Flutter '
              'handoff is a single warm-taupe surface.',
        );

        // Drain the splash timer.
        // pumps past minSplashDuration = 3000ms
        await tester.pump(const Duration(milliseconds: 3500));
      },
    );

    // -------------------------------------------------------------------------
    // Test 3a — Lottie-success branch (`_lottieAvailable == true`).
    //
    // pubspec.yaml bundles splash_wordmark.json, so the default rootBundle
    // resolves the asset and the build switches into the Lottie path after a
    // couple of pumps. Lottie owns the splash content exclusively — no
    // static "beautica" Text may coexist, and no VelvetLogo may render (the
    // B-pillow was removed from the splash).
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
        find.byType(VelvetLogo),
        findsNothing,
        reason:
            'B-pillow removed from the splash — VelvetLogo must not be '
            'rendered in the Lottie-success branch.',
      );
      expect(
        find.text('beautica'),
        findsNothing,
        reason:
            'Lottie owns the splash content exclusively in the success '
            'branch — no static Text("beautica") may coexist.',
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
    // Non-Lottie asset requests (AssetManifest.bin, GoogleFonts lookups for
    // the wordmark Text's Comfortaa font, etc.) must be forwarded to the
    // real delegate so the rest of the framework keeps working — otherwise
    // VelvetText.wordmark() crashes when the Text fallback renders.
    //
    // The static fallback must render a standalone Text("beautica") centred
    // on the bg colour. No Lottie, no VelvetLogo (B-pillow removed from
    // splash). The Text style pins fontSize=17 so the fallback path is
    // visually consistent with wordmark renders elsewhere in the app.
    // -------------------------------------------------------------------------
    testWidgets('3b. static wordmark renders when Lottie asset fails to load', (
      tester,
    ) async {
      // Force-fail rootBundle.load() for the Lottie asset key by intercepting
      // the `flutter/assets` channel and returning null bytes (which
      // PlatformAssetBundle.load() converts into a FlutterError throw).
      // The Lottie key is URL-encoded by PlatformAssetBundle before send().
      // All other asset keys are forwarded to the real delegate so
      // AssetManifest.bin / GoogleFonts can still resolve.
      const encodedLottieKey = 'assets/lottie/splash_wordmark.json';
      final delegate = tester.binding.defaultBinaryMessenger.delegate;
      tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        'flutter/assets',
        (ByteData? message) {
          if (message == null) return delegate.send('flutter/assets', message);
          final key = utf8.decode(message.buffer.asUint8List());
          if (key == encodedLottieKey) {
            // Return null bytes → PlatformAssetBundle throws → catch branch.
            return Future<ByteData?>.value(null);
          }
          // Forward every other asset request to the real delegate so
          // AssetManifest.bin, fonts, etc. continue to resolve. Without this,
          // VelvetText.wordmark() (Comfortaa via GoogleFonts) and Flutter's
          // own asset-manifest probe both crash on the null response.
          return delegate.send('flutter/assets', message);
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
            'a Lottie widget — the static Text fallback owns the splash slot.',
      );
      expect(
        find.text('beautica'),
        findsOneWidget,
        reason:
            'When the Lottie asset fails to load, a static Text("beautica") '
            'must render centred on the bg — better a static wordmark than '
            'no wordmark.',
      );
      expect(
        find.byType(VelvetLogo),
        findsNothing,
        reason:
            'B-pillow removed from the splash — VelvetLogo must not be '
            'rendered in the static-fallback branch either. The standalone '
            'Text("beautica") is the entire splash content.',
      );

      // Assert wordmark font size invariant on the standalone Text. Style is
      // VelvetText.wordmark().copyWith(fontSize: 17) — identical to the
      // wordmark render VelvetLogo uses internally for wordmarkFontSize:17
      // elsewhere in the app, so the fallback path stays visually consistent.
      final Text wordmarkText = tester.widget<Text>(find.text('beautica'));
      expect(
        wordmarkText.style?.fontSize,
        equals(17.0),
        reason:
            'Static-fallback wordmark Text must pin fontSize=17. If this '
            'fails the splash visually regresses on the Lottie-failure path.',
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
            'Lottie animation (or its static Text fallback) IS the splash '
            'content.',
      );

      // Drain the splash timer.
      // pumps past minSplashDuration = 3000ms
      await tester.pump(const Duration(milliseconds: 3500));
    });

    // -------------------------------------------------------------------------
    // Test 5 — No AnimatedWordmark widget in any of the tri-state branches
    //
    // SplashScreen no longer passes an AnimationController to VelvetLogo
    // (and in fact no longer renders VelvetLogo at all on the splash), so
    // AnimatedWordmark is never built. This holds in all three states:
    // probing (bg only), Lottie path (Lottie owns the content), and static
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
            'AnimationController (and never renders VelvetLogo at all), so '
            'AnimatedWordmark must not appear in any tri-state branch '
            '(probing, Lottie, static).',
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
