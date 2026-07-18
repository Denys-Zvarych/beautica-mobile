// Phase 7.2/7.6 — the master booking routes.
//
// Drives a REAL `GoRouter` and navigates with `context.push`, never
// `router.go`. That distinction is the point of this file, not a style
// preference: `go` produces an ordinary route match whose pattern shows up in
// `currentConfiguration.fullPath`, while `push` produces an
// `ImperativeRouteMatch` that go_router DROPS from `fullPath` — so a pushed
// `/master/bookings/:id` reads as its parent `/master/bookings`. A
// nav-detection test written with `go` passes against code that is broken
// under `push`; that exact trap once shipped a broken nav-bar hide.
//
// So these tests assert the pushed leaf through `matches`, and pin that the
// master routes are NOT the client's.

import 'dart:async';

import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

class _Probe extends StatelessWidget {
  const _Probe(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(label))); // no key: text IS the probe
}

/// The nesting under test, mirroring `app_router.dart`'s registration.
GoRouter _router() => GoRouter(
  initialLocation: RouteNames.masterBookings,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.masterBookings,
      builder: (_, _) => const _Probe('master-list'),
      routes: <RouteBase>[
        GoRoute(
          path: ':bookingId',
          builder: (BuildContext c, GoRouterState s) =>
              _Probe('master-detail:${s.pathParameters['bookingId']}'),
        ),
      ],
    ),
    GoRoute(
      path: RouteNames.clientBookings,
      builder: (_, _) => const _Probe('client-list'),
      routes: <RouteBase>[
        GoRoute(
          path: ':bookingId',
          builder: (BuildContext c, GoRouterState s) =>
              _Probe('client-detail:${s.pathParameters['bookingId']}'),
        ),
      ],
    ),
  ],
);

/// The leaf route pattern actually matched, read the way nav-detection has to
/// read it under a `push` — through `matches`, because `fullPath` collapses an
/// `ImperativeRouteMatch` to its parent.
String? _leafFullPath(GoRouter router) {
  final RouteMatchList config = router.routerDelegate.currentConfiguration;
  final RouteMatchBase leaf = config.matches.last;
  // An imperative (pushed) match carries its own nested RouteMatchList, whose
  // `fullPath` IS the leaf pattern — this is the read that nav-detection code
  // must use, since the outer `config.fullPath` has already collapsed to the
  // parent.
  return leaf is ImperativeRouteMatch ? leaf.matches.fullPath : config.fullPath;
}

void main() {
  group('route names', () {
    test('the master routes are NOT the client routes', () {
      // `/bookings` lives under the CLIENT shell branch and its guard.
      // Reusing it would put a master inside the client shell.
      expect(RouteNames.masterBookings, '/master/bookings');
      expect(RouteNames.masterBookings, isNot(RouteNames.clientBookings));
      expect(RouteNames.masterBookingDetail('b1'), '/master/bookings/b1');
      expect(
        RouteNames.masterBookingDetail('b1'),
        isNot(RouteNames.bookingDetail('b1')),
      );
    });

    test('the detail route is a CHILD of the list route', () {
      expect(
        RouteNames.masterBookingDetail('b1'),
        startsWith('${RouteNames.masterBookings}/'),
      );
    });

    test('the booking id is percent-encoded', () {
      expect(
        RouteNames.masterBookingDetail('a/b c'),
        '/master/bookings/a%2Fb%20c',
      );
    });
  });

  group('push navigation', () {
    testWidgets('context.push reaches the master detail with its id', (
      tester,
    ) async {
      final GoRouter router = _router();
      await tester.pumpRoutedApp(router);
      await tester.pumpAndSettle();
      expect(find.text('master-list'), findsOne);

      final BuildContext ctx = tester.element(find.text('master-list'));
      // `push`, NOT `go` — see the file header.
      unawaited(ctx.push(RouteNames.masterBookingDetail('b1')));
      await tester.pumpAndSettle();

      expect(find.text('master-detail:b1'), findsOne);
    });

    testWidgets(
      'a PUSHED detail collapses out of fullPath — the documented go_router '
      'gotcha, pinned so nav-detection code keeps reading `matches`',
      (tester) async {
        final GoRouter router = _router();
        await tester.pumpRoutedApp(router);
        await tester.pumpAndSettle();

        final BuildContext ctx = tester.element(find.text('master-list'));
        unawaited(ctx.push(RouteNames.masterBookingDetail('b1')));
        await tester.pumpAndSettle();

        // THE TRAP: fullPath reports the PARENT, not the pushed leaf.
        expect(
          router.routerDelegate.currentConfiguration.fullPath,
          RouteNames.masterBookings,
          reason:
              'If this ever reports the leaf, go_router changed its '
              'ImperativeRouteMatch handling and the `matches`-based '
              'nav-detection workaround can be simplified.',
        );
        // Read correctly — through the imperative match's OWN nested
        // RouteMatchList — the leaf is the fully-qualified detail pattern.
        expect(_leafFullPath(router), '/master/bookings/:bookingId');
      },
    );

    testWidgets('popping the detail returns to the master list', (
      tester,
    ) async {
      final GoRouter router = _router();
      await tester.pumpRoutedApp(router);
      await tester.pumpAndSettle();

      final BuildContext ctx = tester.element(find.text('master-list'));
      unawaited(ctx.push(RouteNames.masterBookingDetail('b1')));
      await tester.pumpAndSettle();
      expect(find.text('master-detail:b1'), findsOne);

      tester.element(find.text('master-detail:b1')).pop();
      await tester.pumpAndSettle();

      expect(find.text('master-list'), findsOne);
      expect(find.text('master-detail:b1'), findsNothing);
    });

    testWidgets(
      'the master detail route does NOT resolve to the client detail screen',
      (tester) async {
        final GoRouter router = _router();
        await tester.pumpRoutedApp(router);
        await tester.pumpAndSettle();

        final BuildContext ctx = tester.element(find.text('master-list'));
        unawaited(ctx.push(RouteNames.masterBookingDetail('b1')));
        await tester.pumpAndSettle();

        expect(find.text('master-detail:b1'), findsOne);
        expect(find.text('client-detail:b1'), findsNothing);
      },
    );
  });
}
