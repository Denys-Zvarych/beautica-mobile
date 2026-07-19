// Regression pin for `AppHarness.location`'s push-safe resolution — see
// `integration_test/support/app_harness.dart`'s own doc comment on
// `location()` and `scripts/forbid_naive_router_location.sh` for the bug
// this test exists to catch.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// -----------------------------------------
// The failing assertion the bug actually produced
// (`master_bookings_flow_test.dart` / `logout_flow_test.dart` reporting the
// PRE-push location after a real `context.push`) can only be OBSERVED on a
// driven emulator — this sandboxed session has none (the documented
// host-only-adapter limitation, backlog #179/#191). This file pins the exact
// behavioural difference at the tier that DOES run here: a plain
// `flutter test` against a hand-built `GoRouter` shaped like the real bug
// (`/master/profile` → push → `/master/bookings`, mirroring
// `master_bookings_flow_test.dart`'s own shell → nav-tile → detail push),
// asserting `AppHarness.location` resolves the PUSHED location while a raw
// `currentConfiguration.uri` read reports the stale PRE-push one — the exact
// contrast that would have caught the bug before it shipped (twice: the
// `ab34c0a` nav-bar-hide regression, and the "btn-menu-master not
// navigating" backlog MEDIUM, which was never a real navigation regression).
//
// MUTATION-VERIFIED: reverting `AppHarness.location`'s body to
// `return router.routerDelegate.currentConfiguration.uri.toString();` turns
// the "THE FIX" expectation below red (`/master/profile` != `/master/bookings`
// — `Expected: '/master/bookings' Actual: '/master/profile'`), confirming
// this test actually exercises the helper's push-handling branch and isn't a
// tautology. Reverted immediately after confirming; not committed.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../integration_test/support/app_harness.dart';
import '../helpers/pump_app.dart';

class _Probe extends StatelessWidget {
  const _Probe(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(label))); // no key: text IS the probe
}

/// Mirrors `master_bookings_flow_test.dart`'s real shape: a profile "home"
/// and a bookings screen reached by `push` (not `go`) — the exact topology
/// that produces an `ImperativeRouteMatch`.
GoRouter _router() => GoRouter(
  initialLocation: '/master/profile',
  routes: <RouteBase>[
    GoRoute(
      path: '/master/profile',
      builder: (_, _) => const _Probe('profile'),
    ),
    GoRoute(
      path: '/master/bookings',
      builder: (_, _) => const _Probe('bookings'),
    ),
  ],
);

void main() {
  testWidgets('AppHarness.location resolves the PUSHED location; a raw '
      'currentConfiguration.uri read stays stuck on the pre-push location', (
    tester,
  ) async {
    final GoRouter router = _router();
    await tester.pumpRoutedApp(router);
    await tester.pumpAndSettle();

    expect(find.text('profile'), findsOneWidget);
    expect(AppHarness.location(router), '/master/profile');

    // `push`, NOT `go` — this is the match kind go_router excludes from
    // `.uri`/`.fullPath` (see `location()`'s doc comment).
    unawaited(router.push('/master/bookings'));
    await tester.pumpAndSettle();
    expect(find.text('bookings'), findsOneWidget);

    // THE BUG: a raw read stays on the PRE-push location forever, even
    // though the push above visibly succeeded (the probe swapped).
    expect(
      // router-location-ok: deliberately demonstrating the raw-read trap
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/master/profile',
      reason:
          'go_router deliberately excludes ImperativeRouteMatch from '
          '.uri — this is the exact raw read master_bookings_flow_test.dart '
          'and logout_flow_test.dart both shipped with',
    );

    // THE FIX: AppHarness.location resolves through the push.
    expect(
      AppHarness.location(router),
      '/master/bookings',
      reason:
          'AppHarness.location must resolve the ImperativeRouteMatch '
          'produced by push, not the stale declarative uri',
    );

    // The convenience assertion wrapper must agree.
    AppHarness.expectLocation(router, '/master/bookings');
  });
}
