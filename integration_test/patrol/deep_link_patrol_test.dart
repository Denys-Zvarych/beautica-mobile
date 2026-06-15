// Phase 17.5 — patrol NATIVE-ONLY flow: deep link → screen.
//
// PURPOSE
// -------
// Exercises a surface that integration_test CANNOT reach: an OS-level deep-link
// (App Link) intent routed by Android into the running Flutter app. We fire a
// real `ACTION_VIEW` intent via `$.platform.mobile.openUrl(...)` and assert the
// app's go_router resolves it to the matching screen.
//
// WHY /reset-password
// -------------------
// The reset-password App Link is already declared in AndroidManifest.xml
// (autoVerify intent-filter, host = production Railway domain,
// pathPrefix = /reset-password) for the Phase 2.13 forgot-password flow. It is
// the only deep-link target that is:
//   • reachable WITHOUT an authenticated session — authRedirect treats
//     /reset-password as an `isAtUnauthOnlyRoute`, so a cold-start (no stored
//     token) user is NOT bounced to /login; the screen renders as-is.
//   • backend-free on render — the screen only POSTs when the user submits, so
//     no live backend is needed to assert the destination mounts.
// That makes it a fully deterministic, runnable native deep-link assertion
// today — no Firebase, no backend, no auth fixtures.
//
// RUNTIME GATE
// ------------
// This test CANNOT run under `flutter test` (no native instrumentation) and
// CANNOT run on the Ubuntu dev VM (no local emulator). The real gate is the CI
// patrol emulator job. Run locally against a connected emulator with:
//   dart pub global activate patrol_cli   # once
//   patrol test --target integration_test/patrol/deep_link_patrol_test.dart
// See integration_test/patrol/README.md.

import 'package:beautica_mobile/main.dart' show BeauticaApp;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

// The App Link host is locked to the production Railway domain in
// AndroidManifest.xml's autoVerify intent-filter. A `token` query param is
// required by ResetPasswordScreen; any non-empty value renders the form (the
// token is only validated server-side on submit).
const String _kResetPasswordDeepLink =
    'https://beautica-backend-production.up.railway.app'
    '/reset-password?token=patrol-e2e-smoke-token';

void main() {
  patrolTest(
    'deep link to reset-password route opens the reset-password screen',
    ($) async {
      // Launch the REAL app tree. Under patrol native instrumentation the
      // platform channels main() touches (FlutterNativeSplash, SystemChrome,
      // cert-pinning) ARE available, but we pump BeauticaApp directly to keep
      // the test focused on routing and skip main()'s one-shot startup work.
      await $.pumpWidgetAndSettle(const ProviderScope(child: BeauticaApp()));

      // Cold start with no stored token settles to /login (the unauthenticated
      // home). Sanity-check we are NOT already on reset-password so the
      // assertion after openUrl proves the deep link did the navigation.
      expect(
        find.byKey(const ValueKey<String>('reset_submit')),
        findsNothing,
        reason: 'Precondition: reset-password screen must not be shown yet',
      );

      // Fire the OS-level App Link intent. Android routes it to MainActivity
      // (singleTop) → Flutter deep-link handler → go_router /reset-password.
      // `$.platform.mobile.openUrl` is the non-deprecated successor to the old
      // `$.native.openUrl` (NativeAutomator is being phased out in patrol 4.x).
      await $.platform.mobile.openUrl(_kResetPasswordDeepLink);

      // Let the intent propagate into the Flutter engine and the router settle.
      await $.pumpAndSettle();

      // Destination assertion: the reset-password form is now mounted. Keys are
      // locale-invariant (no Ukrainian find.text), per the integration-test
      // navigation policy.
      expect(
        find.byKey(const ValueKey<String>('reset_submit')),
        findsOneWidget,
        reason: 'Deep link must land on the reset-password screen',
      );
      expect(
        find.byKey(const ValueKey<String>('reset_password')),
        findsOneWidget,
      );
    },
  );

  // ── FCM tap-through + notification-permission prompt (DEFERRED) ────────────
  //
  // These two native flows tie directly to Firebase Cloud Messaging, which is
  // DEFERRED in this project: FIREBASE_ENABLED=false on Railway, firebase_core /
  // firebase_messaging are NOT in pubspec, auto-init is disabled in
  // AndroidManifest.xml, and there is no Firebase.initializeApp() call. There is
  // no notification to tap and no permission the app requests, so a real
  // assertion is impossible today.
  //
  // They are SCAFFOLDED as skip-marked (rather than omitted) so the intended
  // native coverage is visible and wired the moment Phase 8.x FCM lands — flip
  // the skip to null, add the firebase deps, and fill the body.

  // patrolTest's `skip` is a bool (no reason string, unlike test()), so the
  // deferral reason is carried in the test description + this comment:
  //   SKIP REASON: Firebase push deferred — FIREBASE_ENABLED=false; enable when
  //   Phase 8.x FCM lands.
  patrolTest(
    'FCM notification tap opens the booking deep link '
    '(SKIPPED: Firebase push deferred — FIREBASE_ENABLED=false; '
    'enable when Phase 8.x FCM lands)',
    skip: true,
    ($) async {
      // TODO(phase-8.x): post a notification via $.platform.mobile.* and tap
      // it, then assert the booking-detail screen renders. Requires
      // firebase_messaging wired + FIREBASE_ENABLED=true.
    },
  );

  patrolTest(
    'POST_NOTIFICATIONS permission prompt is granted on first FCM init '
    '(SKIPPED: Firebase push deferred — FIREBASE_ENABLED=false; '
    'enable when Phase 8.x FCM lands)',
    skip: true,
    ($) async {
      // TODO(phase-8.x): trigger the Android 13+ POST_NOTIFICATIONS runtime
      // prompt on FCM init and grant it via the permission-dialog selectors.
      // Requires firebase_messaging wired.
    },
  );
}
