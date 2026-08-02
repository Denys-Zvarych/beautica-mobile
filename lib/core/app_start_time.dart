// Phase 2.15+ — Minimum splash duration gate.
//
// Records the wall-clock instant at which main() begins executing. The auth
// redirect guard reads [elapsed()] to enforce a guaranteed minimum visible
// duration for the animated splash screen so the wordmark reveal always plays
// to completion before go_router navigates away.
//
// Usage — call [record()] once, before [runApp], in main():
//   AppStartTime.record();
//
// The guard in auth_redirect.dart calls [elapsed()] to check whether the
// minimum splash duration has passed. Until it has, any redirect out of
// /splash is suppressed (the user stays parked on the splash route).
//
// Pure Dart — no Flutter / widget-tree dependencies.

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Captures the application start time to enforce a minimum splash duration.
///
/// [record()] must be called once before [runApp()]. [elapsed()] is safe to
/// call from any isolate or context after that.
abstract final class AppStartTime {
  static DateTime? _start;

  /// Guaranteed minimum time the animated splash wordmark is visible.
  ///
  /// 880 ms Lottie reveal + ~1.5 s of static visible end-state so the user
  /// has time to perceive the animation completing on Android 12 cold start.
  /// (The Lottie widget starts a small moment after Flutter takes over from
  /// the OS splash — asset load + mount latency — so a 2000 ms gate left the
  /// animation getting cut off mid-reveal. 3000 ms covers the worst case
  /// with margin.) Referenced by both [auth_redirect.dart] and
  /// [splash_screen.dart].
  ///
  /// Single source of truth — do not duplicate this constant.
  static const Duration minSplashDuration = Duration(milliseconds: 3000);

  /// Record the current time as the application start instant.
  ///
  /// Idempotent — subsequent calls after the first are silently ignored so
  /// hot-restart cycles in debug mode do not reset the gate mid-session.
  static void record() {
    // The splash gate measures a wall-clock elapsed DURATION, not a calendar
    // day; there is no Kyiv day to derive here.
    // instant-ok: absolute-instant capture
    _start ??= DateTime.now();
  }

  /// Duration since [record()] was called.
  ///
  /// Returns [Duration.zero] if [record()] has never been called (defensive
  /// fallback — avoids parking on /splash indefinitely if the call is missed).
  static Duration elapsed() {
    final start = _start;
    if (start == null) return Duration.zero;
    // instant-ok: absolute-instant comparison, start is a captured wall-clock instant
    return DateTime.now().difference(start);
  }

  /// Reset [_start] to null.
  ///
  /// **Test-only** — never call in production code. Allows deterministic
  /// ordering of [elapsed]-before-[record] tests without relying on fresh
  /// isolate execution.
  @visibleForTesting
  static void resetForTest() => _start = null;

  /// Set [_start] to a fixed instant in the past so [elapsed] returns a
  /// deterministic value greater than the supplied offset.
  ///
  /// **Test-only** — never call in production code. Used by the redirect
  /// guard tests to advance past [minSplashDuration] without sleeping on a
  /// real wall clock.
  @visibleForTesting
  static void setStartForTest(DateTime start) => _start = start;
}
