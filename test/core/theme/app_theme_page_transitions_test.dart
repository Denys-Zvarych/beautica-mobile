// Regression guard for the left-edge swipe-back gesture theme contract.
//
// When `velvetTheme()` sets `pageTransitionsTheme`, every platform must be
// wired to `CupertinoPageTransitionsBuilder`. The Cupertino builder is what
// installs `_CupertinoBackGestureDetector` on `MaterialPage`-based routes,
// enabling the interactive left-edge swipe-to-pop gesture on Android.
//
// If `pageTransitionsTheme` is removed from `velvetTheme()` — or any platform
// reverts to a non-Cupertino builder — the swipe gesture silently disappears
// on that platform. This test catches that regression immediately.
//
// Layer: Widget test (testWidgets initializes Flutter bindings, which
// google_fonts requires — even though no widget is pumped here, velvetTheme()
// calls GoogleFonts.nunitoTextTheme() which needs the bindings initialized.
// The assertions are against the ThemeData value only; no pumpWidget is used.)

import 'package:beautica_mobile/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('velvetTheme pageTransitionsTheme — swipe-back gesture contract', () {
    // -----------------------------------------------------------------------
    // Android is the primary target platform for this codebase. Losing the
    // Cupertino builder on Android silently kills the swipe gesture for all
    // users — the highest-severity regression.
    // -----------------------------------------------------------------------
    testWidgets('Android platform uses CupertinoPageTransitionsBuilder', (
      tester,
    ) async {
      final theme = velvetTheme();
      final builder =
          theme.pageTransitionsTheme.builders[TargetPlatform.android];
      expect(
        builder,
        isNotNull,
        reason:
            'pageTransitionsTheme must have an explicit entry for Android; '
            'falling back to the Material default suppresses the back gesture',
      );
      expect(
        builder,
        isA<CupertinoPageTransitionsBuilder>(),
        reason:
            'Android must use CupertinoPageTransitionsBuilder to install '
            '_CupertinoBackGestureDetector on MaterialPage routes',
      );
    });

    // -----------------------------------------------------------------------
    // iOS ships the Cupertino gesture natively, but the builder must still be
    // explicitly present so the theme contract is consistent and the gesture
    // is never accidentally disabled by a future theme refactor.
    // -----------------------------------------------------------------------
    testWidgets('iOS platform uses CupertinoPageTransitionsBuilder', (
      tester,
    ) async {
      final theme = velvetTheme();
      final builder = theme.pageTransitionsTheme.builders[TargetPlatform.iOS];
      expect(
        builder,
        isNotNull,
        reason: 'pageTransitionsTheme must have an explicit entry for iOS',
      );
      expect(
        builder,
        isA<CupertinoPageTransitionsBuilder>(),
        reason: 'iOS must use CupertinoPageTransitionsBuilder',
      );
    });

    testWidgets('macOS platform uses CupertinoPageTransitionsBuilder', (
      tester,
    ) async {
      final theme = velvetTheme();
      final builder = theme.pageTransitionsTheme.builders[TargetPlatform.macOS];
      expect(
        builder,
        isNotNull,
        reason: 'pageTransitionsTheme must have an explicit entry for macOS',
      );
      expect(
        builder,
        isA<CupertinoPageTransitionsBuilder>(),
        reason: 'macOS must use CupertinoPageTransitionsBuilder',
      );
    });

    testWidgets('Linux platform uses CupertinoPageTransitionsBuilder', (
      tester,
    ) async {
      final theme = velvetTheme();
      final builder = theme.pageTransitionsTheme.builders[TargetPlatform.linux];
      expect(
        builder,
        isNotNull,
        reason: 'pageTransitionsTheme must have an explicit entry for Linux',
      );
      expect(
        builder,
        isA<CupertinoPageTransitionsBuilder>(),
        reason: 'Linux must use CupertinoPageTransitionsBuilder',
      );
    });

    testWidgets('Windows platform uses CupertinoPageTransitionsBuilder', (
      tester,
    ) async {
      final theme = velvetTheme();
      final builder =
          theme.pageTransitionsTheme.builders[TargetPlatform.windows];
      expect(
        builder,
        isNotNull,
        reason: 'pageTransitionsTheme must have an explicit entry for Windows',
      );
      expect(
        builder,
        isA<CupertinoPageTransitionsBuilder>(),
        reason: 'Windows must use CupertinoPageTransitionsBuilder',
      );
    });

    // -----------------------------------------------------------------------
    // Completeness guard: all 5 platforms must be covered. If a new
    // TargetPlatform is added to Flutter in a future SDK upgrade, this test
    // will not fail automatically — but the individual platform tests above
    // guarantee that no existing platform regresses silently.
    // -----------------------------------------------------------------------
    testWidgets(
      'all five target platforms are covered in pageTransitionsTheme',
      (tester) async {
        final builders = velvetTheme().pageTransitionsTheme.builders;
        for (final platform in const [
          TargetPlatform.android,
          TargetPlatform.iOS,
          TargetPlatform.macOS,
          TargetPlatform.linux,
          TargetPlatform.windows,
        ]) {
          expect(
            builders.containsKey(platform),
            isTrue,
            reason:
                'pageTransitionsTheme is missing an entry for '
                '${platform.name} — the swipe-back gesture will fall back to '
                'the Material default and stop working on that platform',
          );
          expect(
            builders[platform],
            isA<CupertinoPageTransitionsBuilder>(),
            reason: '${platform.name} must use CupertinoPageTransitionsBuilder',
          );
        }
      },
    );
  });
}
