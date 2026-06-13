// Ref-counted screenshot / data-leakage protection for PII-bearing screens.
//
// SEC MEDIUM-1: a per-screen `dispose() → preventScreenshotOff()` clears
// FLAG_SECURE for the whole single-Activity app. If two PII screens are ever
// stacked and the upper pops, protection would be torn down while the lower
// PII screen is still visible. This manager makes protection durable by
// reference-counting acquirers:
//   • count 0 → 1: enable screenshot protection (Android FLAG_SECURE / iOS)
//                   AND blur the iOS app-switcher snapshot (SEC MEDIUM-2).
//   • count 1 → 0: disable both.
//
// SEC MEDIUM-2: [ScreenProtector.preventScreenshotOn] does NOT obscure the iOS
// app-switcher snapshot, so [protectDataLeakageWithBlur] is enabled alongside
// it (and torn down with [protectDataLeakageWithBlurOff]).
//
// All native calls are `!kDebugMode`-guarded (protection off in debug so the
// emulator / devtools can still capture frames) and idempotent (the native
// toggle only fires on the 0↔1 boundary).
//
// PII screens call `ref.read(screenProtectionProvider).acquire()` in initState
// and `.release()` in dispose. Non-PII screens (settings hub, account page)
// must NOT acquire.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:screen_protector/screen_protector.dart';

part 'screen_protection.g.dart';

/// Reference-counted owner of the app-wide screenshot / data-leakage guard.
///
/// Enables protection when the first PII route mounts and disables it only
/// when the last PII route unmounts. Idempotent and `!kDebugMode`-guarded.
class ScreenProtectionManager {
  ScreenProtectionManager();

  int _count = 0;

  /// Number of PII screens currently holding protection. Exposed for tests.
  @visibleForTesting
  int get acquirerCount => _count;

  /// Register a PII screen. Enables native protection on the 0→1 transition.
  void acquire() {
    _count++;
    if (_count == 1) _enable();
  }

  /// Release a PII screen. Disables native protection on the 1→0 transition.
  ///
  /// Defensive against double-release: never drives the count below zero, so a
  /// stray extra `release()` cannot disable protection while screens are live.
  void release() {
    if (_count == 0) return;
    _count--;
    if (_count == 0) _disable();
  }

  /// Force-resets the manager to a clean state: zeroes the reference count and
  /// unconditionally tears down native protection.
  ///
  /// Logout calls this after wiping the session/storage so a PII screen that
  /// was never disposed (e.g. a logout triggered from a dialog above a live
  /// acquirer) cannot leave [FLAG_SECURE] / the app-switcher blur latched on
  /// across the auth boundary. Idempotent and `!kDebugMode`-guarded.
  void reset() {
    _count = 0;
    _disable();
  }

  void _enable() {
    if (kDebugMode) return;
    // Android FLAG_SECURE + iOS screenshot/recents block.
    ScreenProtector.preventScreenshotOn();
    // iOS app-switcher snapshot blur (preventScreenshot alone does not cover it).
    ScreenProtector.protectDataLeakageWithBlur();
    log(
      'screenshot protection enabled',
      name: 'core.security.screen_protection',
      level: 700,
    );
  }

  void _disable() {
    if (kDebugMode) return;
    ScreenProtector.preventScreenshotOff();
    ScreenProtector.protectDataLeakageWithBlurOff();
    log(
      'screenshot protection disabled',
      name: 'core.security.screen_protection',
      level: 700,
    );
  }
}

/// App-wide singleton manager. Kept alive so the reference count survives the
/// mount/unmount churn of individual PII routes.
@Riverpod(keepAlive: true)
ScreenProtectionManager screenProtection(Ref ref) => ScreenProtectionManager();
