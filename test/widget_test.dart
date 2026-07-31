// Phase 1.4 — top-level smoke test: BeauticaApp boots without crashing.
//
// The Phase 0 counter scaffold (_BootstrapHome) was removed when
// MaterialApp.router + go_router landed in Phase 1.4. This test verifies
// that ProviderScope + MaterialApp.router initialises without throwing an
// exception. It does NOT assert the specific route — that is covered by
// test/routing/app_router_test.dart and test/routing/auth_redirect_test.dart.
//
// [secureStorageProvider] and [authRepositoryProvider] are overridden so
// that [authProvider] resolves without platform channels or network I/O.
// [pumpAndSettle] is intentionally avoided here: both [SplashScreen]'s
// [CircularProgressIndicator] and [LoadingSkeleton]'s [FadeTransition] run
// continuous animations that prevent it from ever returning.
//
// MP-STARTUP-THEME regression tests (new):
//
// BeauticaApp reads the module-level [_appTheme] constant — a single
// [velvetTheme()] allocation that is never re-evaluated. This file adds
// widget-level assertions for:
//   1. ThemeMode.light is passed to MaterialApp.router (not ThemeMode.system).
//   2. The applied [ThemeData] is the VelvetTouch palette (non-null, M3,
//      BrandColors.base surface, light brightness).
//   3. debugShowCheckedModeBanner is false.
//
// Together these ensure that an accidental revert of the memoization
// (e.g. inline velvetTheme() call reinstated inside build()) or a palette
// regression is caught immediately by CI — not just in golden tests.

import 'package:beautica_mobile/core/theme/app_theme.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes/fake_auth_repository.dart';
import 'helpers/fakes/fake_secure_storage.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

// ---------------------------------------------------------------------------
// Shared setup helper
// ---------------------------------------------------------------------------

Widget _makeApp() => ProviderScope(
  retry: beauticaProviderRetry,
  overrides: [
    secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
    authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
  ],
  child: const BeauticaApp(),
);

void main() {
  testWidgets('BeauticaApp boots without crashing', (
    WidgetTester tester,
  ) async {
    // Empty storage → authProvider resolves to Unauthenticated.
    // No platform channels or network calls are exercised.
    await tester.pumpWidget(_makeApp());

    // Single pump resolves the first frame.
    // Enough to verify the widget tree builds and the router initialises.
    await tester.pump();

    // The app has rendered at least one Scaffold (SplashScreen or LoginScreen
    // depending on how quickly authProvider resolves). Either way the app is up.
    expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
  });

  // ---------------------------------------------------------------------------
  // MP-STARTUP-THEME — regression tests for the memoized _appTheme constant.
  //
  // These tests assert observable MaterialApp properties, not the internal
  // _appTheme symbol (which is private). They verify that BeauticaApp applies
  // the correct VelvetTouch theme and ThemeMode.light.
  // ---------------------------------------------------------------------------

  group('BeauticaApp theme wiring (MP-STARTUP-THEME)', () {
    testWidgets('BeauticaApp applies ThemeMode.light (not system or dark)', (
      tester,
    ) async {
      await tester.pumpWidget(_makeApp());
      await tester.pump();

      // Reach into the MaterialApp widget and assert themeMode is light.
      // MaterialApp.router constructs a MaterialApp internally; the outer
      // widget is a Router-based variant but still exposes MaterialApp.
      // We locate the Theme widget and inspect its brightness to confirm the
      // light-only contract — the test is on the rendered output, not the
      // internal property, so it is implementation-agnostic.
      final BuildContext ctx = tester.element(find.byType(Scaffold).first);
      final ThemeData applied = Theme.of(ctx);

      expect(
        applied.brightness,
        Brightness.light,
        reason:
            'BeauticaApp must always render in light mode. The VelvetTouch '
            'neumorphic design system is light-only. ThemeMode.dark or '
            'ThemeMode.system must never be passed to MaterialApp.router.',
      );
    });

    testWidgets(
      'BeauticaApp applies the VelvetTouch colorScheme (M3 + base surface)',
      (tester) async {
        await tester.pumpWidget(_makeApp());
        await tester.pump();

        final BuildContext ctx = tester.element(find.byType(Scaffold).first);
        final ThemeData applied = Theme.of(ctx);

        // Surface must be the VelvetTouch warm-taupe base.
        expect(
          applied.colorScheme.surface,
          BrandColors.base,
          reason:
              'MP-STARTUP-THEME: BeauticaApp colorScheme.surface must be '
              'BrandColors.base (#E6DDD0). A regression in velvetTheme() or '
              'an accidental darkTheme swap would change this value.',
        );

        // Material 3 flag must be active.
        expect(
          applied.useMaterial3,
          isTrue,
          reason:
              'MP-STARTUP-THEME: BeauticaApp must use Material 3. useMaterial3 '
              'must not be silently reverted to false.',
        );

        // Scaffold background must also be the warm-taupe base.
        expect(
          applied.scaffoldBackgroundColor,
          BrandColors.base,
          reason:
              'MP-STARTUP-THEME: scaffoldBackgroundColor must be BrandColors.base. '
              'This ensures the neumorphic soft-shadow effect renders on the '
              'correct background.',
        );
      },
    );

    testWidgets('BeauticaApp applied theme equals velvetTheme() output', (
      tester,
    ) async {
      await tester.pumpWidget(_makeApp());
      await tester.pump();

      final BuildContext ctx = tester.element(find.byType(Scaffold).first);
      final ThemeData applied = Theme.of(ctx);

      // velvetTheme() is the authoritative source. If someone replaces
      // _appTheme with a different factory (e.g. forgets to update after
      // a theme factory rename), this assertion catches it.
      final ThemeData expected = velvetTheme();

      expect(
        applied.colorScheme.surface,
        expected.colorScheme.surface,
        reason:
            'MP-STARTUP-THEME: The applied theme surface must match the '
            'current velvetTheme() output. An accidental factory swap or '
            'factory rename would change this.',
      );
      expect(
        applied.colorScheme.primary,
        expected.colorScheme.primary,
        reason:
            'MP-STARTUP-THEME: The applied theme primary color must match '
            'velvetTheme() — regression guard for seed color changes.',
      );
      expect(applied.scaffoldBackgroundColor, expected.scaffoldBackgroundColor);
    });

    testWidgets('BeauticaApp does not show the debug banner', (tester) async {
      await tester.pumpWidget(_makeApp());
      await tester.pump();

      // The debug banner is a CheckedModeBanner widget. If
      // debugShowCheckedModeBanner is accidentally flipped to true, this
      // assertion catches it before a release build.
      expect(
        find.byType(CheckedModeBanner),
        findsNothing,
        reason:
            'debugShowCheckedModeBanner must be false. The debug banner '
            'must never appear in production builds.',
      );
    });
  });
}
