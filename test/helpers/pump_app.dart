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
import 'package:flutter/gestures.dart';
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
  /// waiting out a snack's own auto-dismiss timer instead of guessing its
  /// duration). For a [VelvetSnack] specifically, prefer
  /// `pumpPastVelvetSnack` (`test/helpers/velvet_snack_matchers.dart`) — it
  /// pumps the exact lifecycle duration rather than polling, and drains the
  /// dwell `Timer` the leak check requires.
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
/// the same via [WidgetTester.ensureVisible] before tapping — but only when
/// the cell is genuinely out of reach (see the reveal semantics below). Any full-screen
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
/// Since 2026-08-04 that separation is ENFORCED, not merely documented: this
/// helper `fail()`s outright when the resolved cell has no `GestureDetector`
/// descendant (see the inline comment on the check for the defect it caught).
extension TapCalendarDay on WidgetTester {
  /// [within] scopes the cell lookup to one ancestor's subtree — needed when
  /// more than one `booking-calendar-day-<day>` key can be simultaneously
  /// mounted (e.g. the salon booking flow's multi-slide `PageView`, where
  /// mobile-perf's current±1 keep-alive bound can leave two slides' calendars
  /// mounted at once with the SAME day number). `skipOffstage: false` mirrors
  /// the flows' own `withinSlide` helpers so a kept-alive-but-scrolled-off
  /// slide's cell is still reachable. Omitted (the default, every pre-
  /// existing caller), the lookup is unscoped exactly as before.
  /// SEMANTICS OF THE REVEAL (settled by experiment, 2026-09-01 — there is ONE
  /// behaviour here, no opt-in flag). The [ensureVisible] fires ONLY when a
  /// `tap()` at the cell's centre would not currently land on the cell; a cell
  /// that is already hittable is tapped where it stands, untouched.
  ///
  /// It has to be conditional because [ensureVisible] walks EVERY ancestor
  /// `Scrollable`, not just the vertical one this helper is about. Inside
  /// `BookingsMonthCalendarPanel`'s expanded grid that includes the horizontal
  /// MONTH pager — and that pager runs `pageSnapping: false` with
  /// `LowThresholdPageScrollPhysics` (commit fraction 0.25), so even the small
  /// nudge needed to align a mid-row cell to the viewport's leading edge
  /// COMMITS a page turn. A committed page turn there is not cosmetic: the
  /// pager's settle handler SELECTS that month (`_resolveMonthPage` →
  /// `_stepMonth` → `_selectImmediate`), so an unconditional reveal silently
  /// changes the selection before the tap lands and the tap then hits the NEXT
  /// month's cell of the same number. Measured on 1 October 2026 (a Thursday,
  /// column 4 of the grid): the reveal moved the pager a whole page and the
  /// resulting fetch was for 1 NOVEMBER, with the cell fully visible the whole
  /// time. A helper that silently mutates the state under test is a landmine,
  /// so not-mutating-it is the default rather than an opt-in.
  ///
  /// And it has to be a HIT TEST, not a bounds check: on the slot-picker
  /// screens a last-row cell sits inside the 800×600 surface yet is painted
  /// over by the bottom summary bar. "Rect is on screen" calls that visible,
  /// [_wouldTapLandOnCell] calls it obscured, and only the latter agrees with
  /// the `tap()` that follows — the bounds-check version of this predicate
  /// broke `slot_picker_test.dart`'s guaranteed-LAST-row test, which is
  /// precisely the clipping case the reveal exists for.
  Future<void> tapCalendarDay(int day, {Finder? within}) async {
    final Finder cellKey = find.byKey(Key('booking-calendar-day-$day'));
    final Finder finder = within == null
        ? cellKey
        : find.descendant(of: within, matching: cellKey, skipOffstage: false);
    if (!_wouldTapLandOnCell(this, finder)) {
      await ensureVisible(finder);
    }
    await pumpAndSettle();

    // HANDLER PRESENCE CHECK — the blind spot `warnIfMissed` cannot cover.
    //
    // `MonthCalendar._DayCell` renders an UNAVAILABLE day (past, outside the
    // range, or reported non-working) as a bare `Semantics` with NO
    // `GestureDetector` child at all — `_classify` sets `onTap: null` and the
    // `info.onTap == null` branch returns the label-only subtree
    // (`month_calendar.dart`). Tapping it is not a miss: the hit test lands
    // cleanly on the `SingleChildScrollView` behind the cell, so
    // `WidgetController.hitTestWarningShouldBeFatal` — which
    // `integration_test/support/e2e_boot_policy.dart` DOES arm for the E2E
    // tier — stays silent. The tap simply does nothing.
    //
    // That is exactly how the 2026-08-04 defect stayed green: an E2E read the
    // HOST clock (`DateTime.now()`) to choose the day while the app ran on the
    // injected clock pinned to `kFixedNow` (2026-06-14), so on any real-world
    // day-of-month below 14 it tapped a PAST cell. No slots fetch fired and
    // the only symptom was a downstream `expect(fake.getMasterSlotsCalls, …)`
    // reading 0 — a failure that names the fetch, not the cause, and that is
    // invisible for the other ~13 days of the month.
    //
    // Asserting the handler is present BEFORE tapping converts that into an
    // immediate, self-explaining failure at the point of breakage. It is one
    // extra descendant lookup on an already-resolved finder, so it stays
    // always-on rather than being gated behind a debug flag.
    if (find
        .descendant(of: finder, matching: find.byType(GestureDetector))
        .evaluate()
        .isEmpty) {
      fail(
        'calendar cell $day is not tappable — check the app\'s injected '
        'clock, not DateTime.now(). MonthCalendar renders an unavailable day '
        '(past / out of range / non-working) with NO GestureDetector, so this '
        'tap would land on the scroll view behind the cell and silently '
        'no-op. The usual cause is a test that picked the day from the HOST '
        'clock while the app under test runs on the injected clock '
        '(kFixedNow); derive the day with kyivToday(() => kFixedNow) instead. '
        'The other causes are a working-days fixture that does not cover the '
        'app\'s current month, and a genuinely disabled day. If you MEANT to '
        'prove the cell is inert, do not use this helper — call '
        'tester.tap(finder, warnIfMissed: false) directly, as this helper\'s '
        'own doc comment requires.',
      );
    }

    await tap(finder);
  }
}

/// True when a `tap()` at [finder]'s centre would land ON [finder] itself.
///
/// This is deliberately the SAME question `WidgetController.tap` asks
/// (`_getElementPoint` → hit test → `warnIfMissed`), not the weaker "is the
/// cell's rect inside the screen rect". A calendar cell can sit fully within
/// the 800×600 surface and still be untappable because the slot-picker's
/// bottom summary bar paints over it — screen-bounds containment says
/// "visible", the hit test says "obscured", and only the hit test matches
/// what the subsequent `tap()` will do. Returns `false` for a finder that
/// does not resolve to exactly one element, so the caller falls back to
/// [WidgetTester.ensureVisible] (which enforces the same single-match rule).
bool _wouldTapLandOnCell(WidgetTester tester, Finder finder) {
  if (finder.evaluate().length != 1) return false;
  final RenderObject? box = finder.evaluate().single.renderObject;
  if (box is! RenderBox) return false;
  final Offset centre = box.localToGlobal(box.size.center(Offset.zero));
  final Rect surface =
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
  if (!surface.contains(centre)) return false;
  return tester
      .hitTestOnBinding(centre)
      .path
      .any((HitTestEntry<HitTestTarget> e) => identical(e.target, box));
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
