// Shared test helper — pumps a MaterialApp with l10n + Riverpod ProviderScope.
//
// Usage:
//   await tester.pumpApp(
//     MyWidget(),
//     overrides: [myProvider.overrideWithValue(fakeValue)],
//   );
//
// The UK locale is used by default because UA is the primary language.
// Pass locale: const Locale('en') to test English strings.
//
// Phase 17.2 — stress knobs:
//   await tester.pumpApp(MyWidget(), width: 320, textScaleFactor: 2.0);
// pumps the widget at a constrained logical width and an overridden text scale
// so narrow-phone / large-font overflows are reproduced. The overflow guard is
// installed here too, so any RenderFlex overflow at the stress size fails the
// test automatically (no manual assertion needed).

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'overflow_guard.dart';

/// Extension on [WidgetTester] that wraps [widget] in a minimal
/// [ProviderScope] + [MaterialApp] with l10n configured for tests.
extension PumpApp on WidgetTester {
  // ignore: avoid_returning_null_for_void
  Future<void> pumpApp(
    Widget widget, {
    List<Object> overrides = const [],
    Locale locale = const Locale('uk'),
    double? width,
    double? textScaleFactor,
    // Optional Riverpod failed-build retry policy for the ProviderScope. Default
    // null = Riverpod's default exponential-backoff retry (unchanged behaviour).
    // Pass `(_, _) => null` to DISABLE retry so an AsyncError stays put through
    // pumpAndSettle (and leaves no pending backoff Timer at test end).
    Duration? Function(int retryCount, Object error)? retry,
  }) async {
    installOverflowGuard();
    // Stress width: constrain the whole surface to [width] logical px (default
    // 800) at a 1.0 device-pixel-ratio, so the pumped tree lays out at a
    // narrow-phone width without wrapping the widget in a SingleChildScrollView
    // (which would conflict with a Scaffold `home`). The tall default height
    // (2400) keeps a column from reporting a *vertical* overflow that would mask
    // the horizontal one under test. Reset in a tearDown.
    if (width != null) {
      view.physicalSize = Size(width, 2400);
      view.devicePixelRatio = 1.0;
      addTearDown(view.resetPhysicalSize);
      addTearDown(view.resetDevicePixelRatio);
    }
    await pumpWidget(
      ProviderScope(
        // ProviderScope.overrides accepts List<Override>; we cast so callers
        // can pass a plain list without importing the internal Override type.
        // ignore: avoid_dynamic_calls
        overrides: overrides.cast(),
        retry: retry,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: _stress(widget, textScaleFactor: textScaleFactor),
        ),
      ),
    );
  }

  /// Pumps the widget inside a router context (required for go_router calls
  /// like context.go() and context.push() inside the widget under test).
  Future<void> pumpRoutedApp(
    GoRouter router, {
    List<Object> overrides = const [],
    Locale locale = const Locale('uk'),
    // Same knob as [pumpApp]'s `retry` — default null keeps Riverpod's
    // default exponential-backoff retry. Pass `(_, _) => null` when a test
    // asserts an EXACT failed-fetch call count (a retry firing mid-`await
    // pumpAndSettle` would otherwise inflate the count non-deterministically).
    Duration? Function(int retryCount, Object error)? retry,
  }) async {
    installOverflowGuard();
    await pumpWidget(
      ProviderScope(
        overrides: overrides.cast(),
        retry: retry,
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
        ),
      ),
    );
  }
}

/// Pump-until-condition helpers (2026-06-24 fixed-wait gate — see
/// `scripts/forbid_fixed_wait.sh`). A hard-coded `pump(const Duration(...))`
/// is a guess at how long some async/animated work takes: too short is flaky
/// on a slow CI runner, too long slows the whole suite. These pump in small
/// steps and stop the INSTANT the awaited condition is true, so the test
/// waits exactly as long as the real work takes — no more, no less.
extension PumpUntil on WidgetTester {
  /// Pumps in [interval] steps until [finder] matches at least one widget, or
  /// [timeout] of virtual time has elapsed — then asserts the finder matches
  /// (surfacing a clear timeout failure instead of a silent false pass).
  Future<void> pumpUntilFound(
    Finder finder, {
    Duration timeout = const Duration(seconds: 10),
    Duration interval = const Duration(milliseconds: 100),
  }) async {
    final int maxTicks = (timeout.inMicroseconds / interval.inMicroseconds)
        .ceil();
    for (int i = 0; i < maxTicks; i++) {
      if (finder.evaluate().isNotEmpty) return;
      await pump(interval);
    }
    expect(
      finder,
      findsWidgets,
      reason: 'pumpUntilFound timed out after $timeout waiting for $finder',
    );
  }

  /// Inverse of [pumpUntilFound] — pumps until [finder] matches nothing (e.g.
  /// waiting out a SnackBar's own auto-dismiss timer instead of guessing its
  /// duration).
  Future<void> pumpUntilGone(
    Finder finder, {
    Duration timeout = const Duration(seconds: 10),
    Duration interval = const Duration(milliseconds: 100),
  }) async {
    final int maxTicks = (timeout.inMicroseconds / interval.inMicroseconds)
        .ceil();
    for (int i = 0; i < maxTicks; i++) {
      if (finder.evaluate().isEmpty) return;
      await pump(interval);
    }
    expect(
      finder,
      findsNothing,
      reason:
          'pumpUntilGone timed out after $timeout waiting for $finder '
          'to disappear',
    );
  }
}

/// Applies the [PumpApp.pumpApp] `textScaleFactor` knob.
///
/// When [textScaleFactor] is given, overrides the ambient [MediaQuery] text
/// scaler with `TextScaler.linear(textScaleFactor)` so large-font layouts are
/// exercised (1.3 / 2.0). The surface WIDTH is applied separately via
/// `tester.view.physicalSize` in [PumpApp.pumpApp] (not here) so a Scaffold
/// `home` is never placed inside a scroll view. Passing null returns [child]
/// unchanged so existing call sites keep their previous behaviour.
Widget _stress(Widget child, {double? textScaleFactor}) {
  if (textScaleFactor == null) return child;
  return Builder(
    builder: (BuildContext context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScaleFactor)),
      child: child,
    ),
  );
}
