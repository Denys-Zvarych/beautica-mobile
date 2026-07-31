// Phase 17.5 — patrol NATIVE-ONLY flow: deep link → screen.
//
// PURPOSE
// -------
// Exercises a surface that integration_test CANNOT reach: an OS-level deep-link
// (App Link) intent routed by Android into the running Flutter app. We fire a
// real `ACTION_VIEW` intent via `$.platform.mobile.openUrl(...)` and assert the
// app's go_router resolves it to the matching screen.
//
// WHY /invite/accept
// ------------------
// The invite-accept App Link is the ONLY approved App Link surface declared in
// AndroidManifest.xml (autoVerify intent-filter, host = production Railway
// domain, pathPrefix = /invite/accept). It is the only deep-link target that
// is:
//   • reachable WITHOUT an authenticated session — authRedirect treats
//     /invite/accept as an `isAtUnauthOnlyRoute`, so a cold-start (no stored
//     token) user is NOT bounced to /login; the screen renders as-is.
//   • backend-free on MOUNT — the screen-container key renders on the first
//     frame, independent of the token-validation network call. A fake token
//     lands on loading→error and never reaches the `data` form, which is
//     exactly why we assert the screen-container key ('accept_invite_screen'),
//     not the form key.
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

import '../../test/helpers/pump_app.dart';
import '../support/e2e_boot_policy.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

// The App Link host is locked to the production Railway domain in
// AndroidManifest.xml's autoVerify intent-filter (pathPrefix /invite/accept). A
// `token` query param is carried through to the accept-invite screen; a fake
// value never validates (it settles loading→error), but the screen-container
// key mounts on the first frame regardless — which is what this test asserts.
const String _kInviteAcceptDeepLink =
    'https://beautica-backend-production.up.railway.app'
    '/invite/accept?token=patrol-e2e-smoke-token';

void main() {
  patrolTest(
    'deep link to invite-accept route opens the accept-invite screen',
    ($) async {
      // ── SHARED BOOT POLICY ────────────────────────────────────────────────
      //
      // This flow does NOT use PatrolHarness (it drives the real app, not the
      // fake-backend tree), so before 2026-07-31 it was the one patrol entry
      // point that bypassed even the patrol harness's own mirrored setup —
      // booting with the overflow guard off, the off-screen-tap guard off, the
      // text-input mock unregistered, no timezone database, and an unprimed
      // splash gate.
      //
      // "Uses a different tree" is not a reason to boot under different rules.
      // Applying the shared policy here costs nothing this flow needs (it types
      // no text, so the mock is inert; it asserts a screen-container key, which
      // the splash priming only reaches sooner) and closes the last unguarded
      // boot path. `addTearDown` undoes the splash-gate priming — this file has
      // no PatrolHarness.tearDownHarness to do it.
      applyE2eBootPolicy($.tester);
      addTearDown(resetE2eBootPolicy);

      // Launch the REAL app tree. Under patrol native instrumentation the
      // platform channels main() touches (FlutterNativeSplash, SystemChrome,
      // cert-pinning) ARE available, but we pump BeauticaApp directly to keep
      // the test focused on routing and skip main()'s one-shot startup work.
      await $.pumpWidgetAndSettle(
        const ProviderScope(retry: beauticaProviderRetry, child: BeauticaApp()),
      );

      // Cold start with no stored token settles to /login (the unauthenticated
      // home). Sanity-check we are NOT already on accept-invite so the
      // assertion after openUrl proves the deep link did the navigation.
      expect(
        find.byKey(const ValueKey<String>('accept_invite_screen')),
        findsNothing,
        reason: 'Precondition: accept-invite screen must not be shown yet',
      );

      // Fire the OS-level App Link intent. Android routes it to MainActivity
      // (singleTop) → Flutter deep-link handler → go_router /invite/accept.
      // `$.platform.mobile.openUrl` is the non-deprecated successor to the old
      // `$.native.openUrl` (NativeAutomator is being phased out in patrol 4.x).
      await $.platform.mobile.openUrl(_kInviteAcceptDeepLink);

      // POLL — do NOT use pumpAndSettle here. `openUrl` returns as soon as the
      // intent is FIRED; Android then has to deliver it to MainActivity, hand
      // it to the Flutter engine, and let go_router rebuild. pumpAndSettle
      // settles the CURRENT tree, which is already idle, so it returns almost
      // immediately and the assertion runs before the link has landed. That is
      // exactly how this test failed on 2026-07-22: `openUrl` reported ✅ and
      // the whole test was over in 2s with the screen key not found.
      //
      // pumpUntilFound polls in 100ms steps and returns the instant the widget
      // appears, so a healthy run costs only the real round-trip.
      //
      // KNOW THIS FAILURE MODE: if App Link approval is lost, the URL opens in
      // a BROWSER instead of the app. The app is then backgrounded, the Flutter
      // engine stops producing frames, and `pump()` BLOCKS FOREVER waiting for
      // one — so this does not fail after the timeout below, it HANGS. The
      // timeout is only checked between pumps, and control never returns from
      // the pump. Observed 2026-07-22 when the workflow's re-approval loop had
      // been slowed from 1s to 5s: the loop lost the race against patrol's
      // reinstall, and the job sat until the 900s `timeout` in pr-validate.yml
      // killed it. If this test ever hangs again, check that loop's cadence
      // FIRST — it is load-bearing for this test specifically.
      //
      // We poll the SCREEN-CONTAINER key ('accept_invite_screen'), which the
      // KeyedSubtree in AcceptInviteScreen.build() renders on the loading frame
      // — NOT the 'invite_accept' form key, which only appears in the `data`
      // state a fake token never reaches. The mount-key IS the whole gate; no
      // secondary wait on the invalid-invite banner (that would reintroduce a
      // network-completion dependency).
      await $.tester.pumpUntilFound(
        find.byKey(const ValueKey<String>('accept_invite_screen')),
        timeout: const Duration(seconds: 30),
      );

      // Destination assertion: the accept-invite screen container is now
      // mounted. Keys are locale-invariant (no Ukrainian find.text), per the
      // integration-test navigation policy.
      expect(
        find.byKey(const ValueKey<String>('accept_invite_screen')),
        findsOneWidget,
        reason: 'Deep link must land on the accept-invite screen',
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
