// Widget tests for SplashScreen.
//
// Contract (post-2026-05-27 refactor — "splash logo === login logo"):
//
//   The splash body is exactly:
//       Center(child: VelvetLogo(compact: true))
//   centred on a Scaffold whose backgroundColor is BrandColors.base. This is
//   the same widget literal that login_screen.dart line 196 renders, so the
//   cold-start visual is identical to what users see the moment /login
//   paints its first frame. There is NO Lottie animation, NO tri-state
//   asset probe, NO AnimationController, NO AnimatedWordmark, and NO
//   plain-Text fallback path — just the shared VelvetLogo composite.
//
// What survives from the old splash:
//   - FlutterNativeSplash.remove() in initState (idempotent no-op in tests).
//   - AppStartTime.record() in initState.
//   - _splashTimer (Timer) that fires GoRouter.of(context).refresh() after
//     _minSplashMs so we exit /splash on schedule when authProvider settled
//     synchronously before the first frame and the router otherwise stays
//     quiet.
//   - dispose() cancelling _splashTimer.
//
// Tests:
//   1. Smoke — widget renders without error.
//   2. VelvetLogo present in compact mode (compact:true verified on the
//      widget instance — same flag login_screen.dart:196 passes).
//   3. Wordmark "beautica" Text is rendered (VelvetLogo's default
//      showWordmark:true draws the full composite, B-pillow + wordmark).
//   4. No Lottie widget anywhere in the tree.
//   5. Scaffold bg == BrandColors.base (warm-taupe match with the native
//      OS splash so the handoff is a single colour).
//   6. FlutterNativeSplash.remove() does not throw in the widget-test
//      environment (the native-splash platform channel is not initialised
//      in tests; remove() is a documented no-op).
//   7. Early-dispose safety — disposing the widget before any pump drains
//      the frame queue does not throw and does not leak _splashTimer.
//   8. _splashTimer fires GoRouter.of(context).refresh() after _minSplashMs
//      when the widget is still mounted — single source of router-kick.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/presentation/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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

      // Drain the pending _splashTimer so the binding does not complain about
      // a wall-clock timer left over at tear-down.
      await tester.pump(const Duration(milliseconds: 3500));
    });

    // -------------------------------------------------------------------------
    // Test 2 — VelvetLogo present in compact mode (matches login_screen.dart)
    // -------------------------------------------------------------------------
    testWidgets('2. renders VelvetLogo(compact: true) centred', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(
        find.byType(VelvetLogo),
        findsOneWidget,
        reason: 'Splash must show the same VelvetLogo widget as login.',
      );
      final logo = tester.widget<VelvetLogo>(find.byType(VelvetLogo));
      expect(
        logo.compact,
        isTrue,
        reason: 'Splash uses compact:true to match login_screen.dart:196.',
      );

      await tester.pump(const Duration(milliseconds: 3500));
    });

    // -------------------------------------------------------------------------
    // Test 3 — wordmark "beautica" Text renders (VelvetLogo default composite)
    // -------------------------------------------------------------------------
    testWidgets('3. wordmark "beautica" Text renders', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(
        find.text('beautica'),
        findsOneWidget,
        reason:
            'VelvetLogo(compact: true) defaults to showWordmark:true, so '
            'the "beautica" Text must render below the B-pillow tile.',
      );

      await tester.pump(const Duration(milliseconds: 3500));
    });

    // -------------------------------------------------------------------------
    // Test 4 — no Lottie widget anywhere
    //
    // The Lottie reveal was removed — VelvetLogo is the sole content. Use a
    // type-name predicate instead of importing the Lottie package, since the
    // dependency may be removed from pubspec entirely.
    // -------------------------------------------------------------------------
    testWidgets('4. no Lottie widget on splash', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      final lottieDescendants = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'Lottie',
      );
      expect(
        lottieDescendants,
        findsNothing,
        reason: 'Lottie reveal was removed — VelvetLogo is the sole content.',
      );

      await tester.pump(const Duration(milliseconds: 3500));
    });

    // -------------------------------------------------------------------------
    // Test 5 — Scaffold bg matches BrandColors.base
    //
    // The native splash background is configured as #E6DDD0 (warm taupe).
    // The Flutter Scaffold must use the identical colour to prevent a flash
    // at the native-to-Flutter handoff.
    // -------------------------------------------------------------------------
    testWidgets('5. Scaffold bg = BrandColors.base', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(
        scaffold.backgroundColor,
        equals(BrandColors.base),
        reason:
            'Scaffold.backgroundColor must match the native splash colour '
            '(BrandColors.base = #E6DDD0).',
      );

      await tester.pump(const Duration(milliseconds: 3500));
    });

    // -------------------------------------------------------------------------
    // Test 6 — FlutterNativeSplash.remove() does not throw in tests
    // -------------------------------------------------------------------------
    testWidgets('6. FlutterNativeSplash.remove() does not throw', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(find.byType(SplashScreen), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 3500));
    });

    // -------------------------------------------------------------------------
    // Test 7 — Early-dispose: _splashTimer cancelled cleanly
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
      '7. early-dispose: _splashTimer cancelled by dispose() without error',
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
    // Test 8 — _splashTimer fires GoRouter.refresh() after _minSplashMs.
    //
    // The timer fires after _minSplashMs (3000ms). When the widget is still
    // mounted, GoRouter.of(context).refresh() must be called. This is the
    // single router re-kick that prevents users from being permanently parked
    // on /splash.
    // -------------------------------------------------------------------------
    testWidgets('8. _splashTimer fires GoRouter.refresh() after _minSplashMs', (
      tester,
    ) async {
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
          GoRoute(
            path: '/splash',
            builder: (context, state) => const SplashScreen(),
          ),
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(body: Text('home')),
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
    });
  });
}
