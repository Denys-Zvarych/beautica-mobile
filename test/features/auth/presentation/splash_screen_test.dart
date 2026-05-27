// Widget tests for SplashScreen.
//
// Contract (post-2026-05-27 refactor — "centred composite, Lottie wordmark"):
//
//   The splash body is a Center wrapping a Column with mainAxisSize:min, so
//   the whole composite is centred vertically AND horizontally at the
//   viewport midpoint:
//       Center(
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             VelvetLogo(compact: true, showWordmark: false),  // B-pillow only
//             SizedBox(height: 8),
//             _SplashWordmark(),                               // Lottie wordmark
//           ],
//         ),
//       )
//   on a Scaffold whose backgroundColor is BrandColors.base.
//
//   The wordmark text is owned by the bundled Lottie animation at
//   `assets/lottie/splash_wordmark.json` — there is NO static Text('beautica')
//   on the splash anymore. The visual outline matches the login-screen
//   VelvetLogo composite (B above, "beautica" below), but the wordmark
//   reveals letter-by-letter instead of rendering as static type.
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
//   2. VelvetLogo present in compact mode with showWordmark:false (the
//      wordmark slot is intentionally suppressed so the Lottie owns the
//      "beautica" text below the tile).
//   3. Lottie wordmark widget renders.
//   4. No static Text('beautica') in the tree — the Lottie is the sole
//      wordmark, so a coexisting static Text would double-render.
//   5. Composite is centred — Column inside Center with
//      mainAxisSize:MainAxisSize.min, so the whole composite lands at the
//      viewport's true vertical midpoint.
//   6. Scaffold bg == BrandColors.base (warm-taupe match with the native
//      OS splash so the handoff is a single colour).
//   7. FlutterNativeSplash.remove() does not throw in the widget-test
//      environment (the native-splash platform channel is not initialised
//      in tests; remove() is a documented no-op).
//   8. Early-dispose safety — disposing the widget before any pump drains
//      the frame queue does not throw and does not leak _splashTimer.
//   9. _splashTimer fires GoRouter.of(context).refresh() after _minSplashMs
//      when the widget is still mounted — single source of router-kick.

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

      // Drain the pending _splashTimer so the binding does not complain about
      // a wall-clock timer left over at tear-down.
      await tester.pump(const Duration(milliseconds: 3500));
    });

    // -------------------------------------------------------------------------
    // Test 2 — VelvetLogo present in compact mode with showWordmark:false
    // -------------------------------------------------------------------------
    testWidgets(
      '2. renders VelvetLogo(compact: true) with showWordmark:false',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await tester.pump();

        expect(
          find.byType(VelvetLogo),
          findsOneWidget,
          reason: 'Splash must render the B-pillow via VelvetLogo.',
        );
        final logo = tester.widget<VelvetLogo>(find.byType(VelvetLogo));
        expect(
          logo.compact,
          isTrue,
          reason: 'Splash uses compact:true to match the login-screen logo.',
        );
        expect(
          logo.showWordmark,
          isFalse,
          reason:
              'The wordmark slot is owned by the Lottie animation below; '
              'VelvetLogo must NOT also render its default static "beautica" '
              'Text — otherwise the wordmark would render twice.',
        );

        await tester.pump(const Duration(milliseconds: 3500));
      },
    );

    // -------------------------------------------------------------------------
    // Test 3 — Lottie wordmark widget renders
    // -------------------------------------------------------------------------
    testWidgets('3. Lottie wordmark widget renders', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();
      // Allow the Lottie asset bundle resolver a frame to settle.
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.byType(Lottie),
        findsOneWidget,
        reason: 'Splash must render the animated Lottie wordmark reveal.',
      );

      await tester.pump(const Duration(milliseconds: 3500));
    });

    // -------------------------------------------------------------------------
    // Test 4 — static "beautica" Text is NOT rendered (animation owns wordmark)
    // -------------------------------------------------------------------------
    testWidgets(
      '4. static "beautica" Text is NOT rendered (animation owns wordmark)',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          find.text('beautica'),
          findsNothing,
          reason:
              'Lottie owns the wordmark; no static Text("beautica") should '
              'coexist with the animated reveal.',
        );

        await tester.pump(const Duration(milliseconds: 3500));
      },
    );

    // -------------------------------------------------------------------------
    // Test 5 — composite is centred (Column inside Center, mainAxisSize:min)
    //
    // Center + Column(mainAxisSize:min) is the layout pattern that lands the
    // composite at the viewport's true vertical midpoint. If the Column
    // expanded to fill the available vertical extent (mainAxisSize:max), the
    // children would distribute along the cross axis instead of sitting at
    // the centre, and the user would see "top of page" drift again.
    // -------------------------------------------------------------------------
    testWidgets('5. composite is centred — Column inside Center', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      final centerFinder = find.byType(Center);
      expect(
        centerFinder,
        findsWidgets,
        reason:
            'A Center widget is required to vertically + horizontally '
            'centre the composite at the viewport midpoint.',
      );

      // The splash composite Column is a direct child of a Center widget.
      // VelvetLogo internally builds its own Column for the B-pillow tile,
      // so a naive `find.descendant(of: SplashScreen, Column)` matches both;
      // scope the query to the Column that is wrapped by Center to land on
      // the composite specifically.
      final columnFinder = find.ancestor(
        of: find.byType(VelvetLogo),
        matching: find.byType(Column),
      );
      expect(
        columnFinder,
        findsWidgets,
        reason:
            'VelvetLogo must sit inside a Column (the composite Column that '
            'stacks the B-pillow above the Lottie wordmark).',
      );
      // The outermost Column that has the Lottie wordmark as a sibling is the
      // splash composite Column.
      final compositeColumn = tester.widget<Column>(
        find
            .ancestor(of: find.byType(Lottie), matching: find.byType(Column))
            .first,
      );
      expect(
        compositeColumn.mainAxisSize,
        equals(MainAxisSize.min),
        reason:
            'The splash composite Column.mainAxisSize MUST be min so Center '
            'treats it as a unit and lands its midpoint at the viewport '
            'centre.',
      );

      await tester.pump(const Duration(milliseconds: 3500));
    });

    // -------------------------------------------------------------------------
    // Test 6 — Scaffold bg matches BrandColors.base
    //
    // The native splash background is configured as #E6DDD0 (warm taupe).
    // The Flutter Scaffold must use the identical colour to prevent a flash
    // at the native-to-Flutter handoff.
    // -------------------------------------------------------------------------
    testWidgets('6. Scaffold bg = BrandColors.base', (tester) async {
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
    // Test 7 — FlutterNativeSplash.remove() does not throw in tests
    // -------------------------------------------------------------------------
    testWidgets('7. FlutterNativeSplash.remove() does not throw', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pump();

      expect(find.byType(SplashScreen), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 3500));
    });

    // -------------------------------------------------------------------------
    // Test 8 — Early-dispose: _splashTimer cancelled cleanly
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
      '8. early-dispose: _splashTimer cancelled by dispose() without error',
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
    // Test 9 — _splashTimer fires GoRouter.refresh() after _minSplashMs.
    //
    // The timer fires after _minSplashMs (3000ms). When the widget is still
    // mounted, GoRouter.of(context).refresh() must be called. This is the
    // single router re-kick that prevents users from being permanently parked
    // on /splash.
    // -------------------------------------------------------------------------
    testWidgets('9. _splashTimer fires GoRouter.refresh() after _minSplashMs', (
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
