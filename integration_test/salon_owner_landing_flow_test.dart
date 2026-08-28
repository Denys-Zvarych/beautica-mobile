// Phase 21.1 — E2E: SALON_OWNER lands on the My Salons Hub, not the
// `_Placeholder('home')` stub.
//
// WHY THIS FILE EXISTS
// ---------------------
// `role_home.dart`'s `roleHomePath(UserRole.salonOwner)` used to fall through
// the `_ => RouteNames.home` wildcard and land a freshly-authenticated
// SALON_OWNER on a bare `_Placeholder('home')` — the phase doc's own "this
// phase also owns the owner's LANDING" note. Both landing call sites
// (post-registration `done_screen.dart`'s `done_to_app` CTA, and fresh-login
// `auth_redirect.dart`) share that one `roleHomePath` source of truth, so
// pinning both here, end to end against the REAL router + a REAL (fake)
// login round trip, is what actually proves the phase shipped — a unit test
// on `role_home.dart` alone cannot see either call site wire the pure
// function in correctly.
//
// `integration_test/auth_login_flow_test.dart`'s own SALON_OWNER case
// already asserts location + page type for the fresh-login path (fixed
// alongside this file — it previously pinned the OLD `/` placeholder and
// went red the moment `role_home.dart` shipped the fix). This file is the
// DEDICATED regression pin the phase doc's Step 7 calls for, and additionally
// covers the post-registration `done_to_app` CTA path, which
// `auth_login_flow_test.dart` does not touch.
//
// POST-REGISTRATION COVERAGE, PRAGMATICALLY SCOPED
// --------------------------------------------------
// `DoneScreen` (`lib/features/auth/presentation/done_screen.dart`) only reads
// `currentUserProvider` — it requires an authenticated session, but has no
// dependency on HOW that session was reached (the full registration wizard
// vs. a plain login). Driving the entire multi-step SALON_OWNER registration
// wizard (role → step1 → step2 → step3 → OTP → done) just to reach the exact
// same authenticated-SALON_OWNER precondition `AppHarness.loginAs` already
// gives us would re-test the wizard's OWN spine (already covered by
// `register_flow_test.dart`) rather than this phase's landing fix. So Test 2
// below logs in (reaching the identical "authenticated SALON_OWNER" state a
// completed wizard would leave), navigates to `RouteNames.done` directly
// (exactly where the wizard's OTP-verify step lands), and taps the SAME
// `done_to_app` CTA a real post-registration user taps — exercising the real
// `roleHomePath` call site `done_screen.dart` owns, without re-driving steps
// this phase does not touch.
//
// All taps are key-based — no raw Ukrainian find.text() tap drivers.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// The default single-primary salon FakeBackend seeds `GET /salons/mine`
/// with (`fake_backend.dart`'s `mySalons` fixture) — the id the resolver
/// (`SalonHomeResolverScreen`) must forward the owner to.
const String _primarySalonId = 'salon-owner-1';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'fresh login: SALON_OWNER lands on the Salon Shell (via the /salons/home '
    'resolver), never the / placeholder',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.salonOwner;
      final GoRouter router = await AppHarness.boot(tester, fb);

      expect(
        find.byKey(const ValueKey<String>('login_email')),
        findsOneWidget,
        reason: 'cold start with no stored token must show the login form',
      );

      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);

      final String landed = AppHarness.location(router);
      expect(
        landed,
        equals(RouteNames.salonShell(_primarySalonId)),
        reason:
            'SALON_OWNER must land exactly on '
            '${RouteNames.salonShell(_primarySalonId)} — got $landed. '
            'roleHomePath (RouteNames.salonHome, Phase 21.8) forwards, via '
            'SalonHomeResolverScreen, to the primary salon\'s shell.',
      );
      expect(
        landed,
        isNot(equals(RouteNames.home)),
        reason:
            'the pre-Phase-21.1 regression: SALON_OWNER falling through to '
            'the bare _Placeholder(\'home\') at "/"',
      );
      expect(
        find.byType(SalonShellScreen),
        findsOneWidget,
        reason:
            'the resolved PAGE TYPE must be the real shell, not merely a '
            'matching location string (see the route-shadowing sibling test '
            'for why the string alone is not proof)',
      );
      expect(fb.loginCalls, equals(1));
    },
  );

  testWidgets(
    'post-registration: tapping the Done screen CTA as a SALON_OWNER lands '
    'on the Salon Shell (via the /salons/home resolver)',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.salonOwner;
      final GoRouter router = await AppHarness.boot(tester, fb);

      // Reach the identical "authenticated SALON_OWNER" precondition a
      // completed registration wizard leaves behind — see file header for
      // why re-driving the whole wizard spine is out of scope here.
      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.settle(tester);

      router.go(RouteNames.done);
      await tester.pumpAndSettle();
      AppHarness.expectLocation(router, RouteNames.done);

      await tester.tap(find.byKey(const ValueKey<String>('done_to_app')));
      await tester.pumpAndSettle();

      final String landed = AppHarness.location(router);
      expect(
        landed,
        equals(RouteNames.salonShell(_primarySalonId)),
        reason:
            'the done_to_app CTA (done_screen.dart) must route a SALON_OWNER '
            'through roleHomePath to RouteNames.salonHome, which forwards to '
            '${RouteNames.salonShell(_primarySalonId)} — got $landed',
      );
      expect(
        find.byType(SalonShellScreen),
        findsOneWidget,
        reason: 'resolved page type must be the real shell, not a stub',
      );
    },
  );
}
