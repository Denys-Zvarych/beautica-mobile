// Ref-counted app-switcher / data-leakage protection for PII-bearing screens.
//
// PRODUCT DECISION 2026-08-20 — SCREENSHOTS ARE ALLOWED. THIS MANAGER NO LONGER
// BLOCKS SCREEN CAPTURE ON ANY PLATFORM. DO NOT RE-ADD `preventScreenshotOn`.
// ---------------------------------------------------------------------------
// WHAT USED TO BE HERE. This file previously carried two security-audit findings
// as its rationale:
//   • SEC MEDIUM-1 — the reference count, added because a per-screen
//     `dispose() → preventScreenshotOff()` cleared FLAG_SECURE for the whole
//     single-Activity app while a lower PII screen was still visible.
//   • SEC MEDIUM-2 (2026-07-29) — an ANDROID TEARDOWN ASYMMETRY: `_enable()` was
//     symmetric but `_disable()` deliberately skipped `preventScreenshotOff()` on
//     Android, because `MainActivity.onCreate` set FLAG_SECURE app-wide and this
//     manager must never clear a baseline it did not set.
//
// WHY BOTH ARE REVERSED. Both findings were AUDIT-DRIVEN (MASVS-PLATFORM MS6 /
// mobile-security MS-4), never product decisions, and the product cost of
// app-wide capture-blocking was never weighed. Beautica is a beauty
// discovery/booking marketplace: sharing what you found IS the growth loop.
// Blocking capture stopped a user screenshotting their own booking confirmation,
// sharing a master's profile or a result photo, saving a price list, attaching a
// screenshot to a support request, or casting. The user weighed that on
// 2026-08-20 and chose sharing over capture-blocking.
//   → `MainActivity` no longer sets FLAG_SECURE, so there is no app-wide baseline
//     left for the Android teardown exemption to protect. SEC MEDIUM-2's premise
//     is gone and the asymmetry is removed: `_disable()` is symmetric again.
//   → Per-screen FLAG_SECURE is explicitly NOT wanted either, so the Android
//     screenshot toggle here is now a deliberate NO-OP.
//
// WHAT IS RETAINED. The task-switcher thumbnail is still blanked — a real leak to
// anyone picking up an unlocked phone, and blankable WITHOUT blocking the user's
// own captures. Android does it natively via
// `Activity.setRecentsScreenshotEnabled(false)` in `MainActivity`; iOS does it
// here via [ScreenProtector.protectDataLeakageWithBlur], which is the exact iOS
// equivalent and is the ONLY native call this manager still makes.
//
// WHY THE REFCOUNT SURVIVES. It still drives the iOS app-switcher blur on the
// 0↔1 boundary, and keeping it means re-enabling capture-blocking later is a
// one-line change rather than a re-architecture. `acquire()` / `release()` /
// `reset()` and every existing call site are UNCHANGED.
//
// TO A FUTURE SECURITY AUDITOR: re-filing MASVS-PLATFORM MS6 / MS-4 against this
// file, or "restoring symmetry" by re-adding `preventScreenshotOn/Off`, is a
// re-litigation of a settled product decision. It is WON'T FIX. Raise it with
// the user as a product question; do not re-land it in code.
//
// All native calls stay `!kDebugMode`-guarded and idempotent (the native toggle
// only fires on the 0↔1 boundary).
//
// PII screens call `ref.read(screenProtectionProvider).acquire()` in initState
// and `.release()` in dispose. Non-PII screens (settings hub, account page)
// must NOT acquire.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:screen_protector/screen_protector.dart';

part 'screen_protection.g.dart';

/// Reference-counted owner of the app-switcher / data-leakage guard.
///
/// Enables protection when the first PII route mounts and disables it only when
/// the last PII route unmounts. Idempotent and `!kDebugMode`-guarded.
///
/// Since the 2026-08-20 product decision (see the file header) this guard is the
/// iOS app-switcher snapshot blur ONLY — it never blocks screenshots, screen
/// recording or casting, on either platform.
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
  /// acquirer) cannot leave the app-switcher blur latched on across the auth
  /// boundary. Idempotent and `!kDebugMode`-guarded.
  void reset() {
    _count = 0;
    _disable();
  }

  void _enable() {
    if (kDebugMode) return;
    // DELIBERATELY NO `ScreenProtector.preventScreenshotOn()` — product decision
    // 2026-08-20 (file header). Screenshots, screen recording and casting are
    // allowed on both platforms; the Android toggle is a no-op by design.
    //
    // iOS app-switcher snapshot blur — the iOS equivalent of Android's
    // `setRecentsScreenshotEnabled(false)`, and the retained mitigation.
    // Self-guarded: the `screen_protector` platform channel can throw
    // (PlatformException / MissingPluginException) on real devices, and a
    // failed blur must never escape into a PII screen's initState.
    try {
      ScreenProtector.protectDataLeakageWithBlur();
    } catch (e) {
      log(
        'protectDataLeakageWithBlur failed (tolerated): ${e.runtimeType}',
        name: 'core.security.screen_protection',
        level: 900,
      );
    }
    log(
      'app-switcher blur enabled',
      name: 'core.security.screen_protection',
      level: 700,
    );
  }

  void _disable() {
    if (kDebugMode) return;
    // SYMMETRIC AGAIN ON BOTH PLATFORMS (reverses SEC MEDIUM-2, 2026-08-20).
    // The old `if (defaultTargetPlatform != TargetPlatform.android)` exemption
    // existed for ONE reason: `MainActivity.onCreate` set FLAG_SECURE app-wide,
    // so clearing it here would have torn down a baseline this manager never
    // set, leaving the process capturable for its whole remaining lifetime.
    // `MainActivity` no longer sets FLAG_SECURE (product decision — file
    // header), so that premise is gone. There is nothing left to exempt: this
    // manager never turns capture-blocking ON, so it has nothing to turn OFF.
    // `preventScreenshotOff()` is therefore not called at all, on any platform.
    //
    // Self-guarded: the `screen_protector` platform channel can throw on real
    // devices, and a failure must not escape into a logout-time reset() caller
    // and surface a false logout failure.
    try {
      ScreenProtector.protectDataLeakageWithBlurOff();
    } catch (e) {
      log(
        'protectDataLeakageWithBlurOff failed (tolerated): ${e.runtimeType}',
        name: 'core.security.screen_protection',
        level: 900,
      );
    }
    log(
      'app-switcher blur disabled',
      name: 'core.security.screen_protection',
      level: 700,
    );
  }
}

/// App-wide singleton manager. Kept alive so the reference count survives the
/// mount/unmount churn of individual PII routes.
@Riverpod(keepAlive: true)
ScreenProtectionManager screenProtection(Ref ref) => ScreenProtectionManager();
