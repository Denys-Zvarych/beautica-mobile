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
//
// mobile-qa (My Rating stretch-card regression) — `height` knob:
//   await tester.pumpApp(MyWidget(), height: 2400);
// pumps the widget under an exaggeratedly TALL viewport so an
// Expanded/tight-constraint layout bug that stretches an opaque card to fill
// the remaining height becomes an unmissable `tester.getSize(...)` outlier
// instead of silently fitting inside the default 600dp test surface. Combine
// with `width` when both dimensions need control; `width` alone still implies
// height 2400 (unchanged legacy behaviour) for existing call sites.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'overflow_guard.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

/// Extension on [WidgetTester] that wraps [widget] in a minimal
/// [ProviderScope] + [MaterialApp] with l10n configured for tests.
extension PumpApp on WidgetTester {
  // ignore: avoid_returning_null_for_void
  Future<void> pumpApp(
    Widget widget, {
    List<Object> overrides = const [],
    Locale locale = const Locale('uk'),
    double? width,
    double? height,
    double? textScaleFactor,
    // Riverpod failed-build retry policy for the ProviderScope.
    //
    // Defaults to [beauticaProviderRetry] — THE SAME predicate `main.dart`
    // installs on the production root scope — so a test resolves error paths
    // identically to the app. It used to default to `null`, which meant
    // `ProviderContainer.defaultRetry`: Riverpod's blanket 10-attempt / ~38 s
    // backoff, applied to every `Failure` because a `Failure` is neither an
    // `Error` nor a `ProviderException`. That is PRECISELY the behaviour
    // production removed, so the whole widget suite was validating a policy
    // the app no longer has — a transient fake-backend error got retried away
    // in test and surfaced to a real user in production. Same boot-order skew
    // `core/network/beautica_serializers.dart` refuses to accept for
    // serializers, same remedy: make the value explicit at construction rather
    // than dependent on who booted.
    //
    // Pass `(_, _) => null` to disable retry ENTIRELY — stricter than
    // production, and still legitimate for a test asserting an exact failed-
    // fetch call count or a NetworkFailure/5xx error surface, where even the
    // production policy's genuine retry would inflate the count or park the
    // element in AsyncLoading through pumpAndSettle.
    Duration? Function(int retryCount, Object error)? retry =
        beauticaProviderRetry,
  }) async {
    installOverflowGuard();
    // Stress width: constrain the whole surface to [width] logical px (default
    // 800) at a 1.0 device-pixel-ratio, so the pumped tree lays out at a
    // narrow-phone width without wrapping the widget in a SingleChildScrollView
    // (which would conflict with a Scaffold `home`). The tall default height
    // (2400) keeps a column from reporting a *vertical* overflow that would mask
    // the horizontal one under test. `height` is a separate knob (default 2400
    // when only `width` is given, unchanged legacy behaviour) for tests that
    // want an exaggeratedly tall viewport WITHOUT also constraining width — see
    // the stretched-card regression note above. Reset in a tearDown.
    if (width != null || height != null) {
      view.physicalSize = Size(width ?? 800, height ?? 2400);
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
    // Same knob as [pumpApp]'s `retry`, same default — [beauticaProviderRetry],
    // the production predicate (see [pumpApp] for why the old `null` default
    // was a false-green). Pass `(_, _) => null` when a test asserts an EXACT
    // failed-fetch call count (even the production policy retries a
    // NetworkFailure/5xx, which would inflate the count non-deterministically
    // mid-`await pumpAndSettle`).
    Duration? Function(int retryCount, Object error)? retry =
        beauticaProviderRetry,
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

/// Taps a `booking-calendar-day-<day>` grid cell safely.
///
/// `MonthCalendar` lives inside a `SingleChildScrollView` on the booking
/// slot-picker screens (see `slot_picker_screen.dart`). On the default
/// 800×600 flutter_test surface, the surrounding chrome (top bar + master
/// strip) can leave less viewport height than the 5-row grid needs, so a day
/// in the last row or two of the month is scrolled out of view. A blind
/// `tester.tap(find.byKey(...))` on such a cell doesn't throw — the finder
/// still resolves and `tap()` still computes a center point — it just lands
/// on whatever widget is actually visible at that offset (e.g. the bottom
/// summary bar), silently swallowing the tap and cascading into a confusing
/// downstream assertion failure. Real users simply scroll; this helper does
/// the same via [WidgetTester.ensureVisible] before tapping. Any full-screen
/// test that taps a `booking-calendar-day-*` key *expecting the tap to
/// register* should go through this instead of a blind
/// `tester.tap(find.byKey(...))`.
///
/// Does NOT apply to tests asserting a cell is inert (no `GestureDetector`,
/// e.g. a disabled/out-of-range day) via `expect(fake.callCount, 0)`. Those
/// must keep calling `tester.tap(cell, warnIfMissed: false)` directly. They
/// are proving the *absence* of a handler, not working around scroll
/// clipping — routing them through this helper would still pass
/// `expect(callCount, 0)` whether the cell correctly has no handler or the
/// tap was silently swallowed by scroll clipping, which is exactly the
/// false-pass this helper exists to prevent for the enabled-cell case.
extension TapCalendarDay on WidgetTester {
  Future<void> tapCalendarDay(int day) async {
    final Finder finder = find.byKey(Key('booking-calendar-day-$day'));
    await ensureVisible(finder);
    await pumpAndSettle();
    await tap(finder);
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
