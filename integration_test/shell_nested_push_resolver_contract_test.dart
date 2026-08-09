// Mobile-qa (2026-07-31 debug chain) — the AppHarness LOCATION-RESOLVER
// contract for a `context.push` onto a route nested inside a
// [StatefulShellBranch].
//
// WHY THIS FILE EXISTS
// --------------------
// `AppHarness` ships THREE location resolvers, and picking the wrong one is a
// SILENT false-pass, not an error:
//
//   location(router)            — plain routes, and top-level imperative pushes
//   shellLocation(router)       — a branch ROOT inside a StatefulShellRoute
//   nestedPushLocation(router)  — a `context.push`ed LEAF inside a branch
//
// `/bookings/:bookingId` is the third shape: a child `GoRoute` declared inside
// the CLIENT shell's Записи branch (`app_router.dart`), reached by
// `MyBookingsScreen`'s `context.push(RouteNames.bookingDetail(id))`
// (`my_bookings_screen.dart:93`).
//
// For that shape `location()` is DEAD CODE. Its only special case is "the
// TOP-LEVEL match IS an `ImperativeRouteMatch`", but `RouteMatchList.push`
// (go_router `match.dart`, `_createNewMatchUntilIncompatible`) RECURSES INTO
// the already-active `ShellRouteMatch` instead of appending a new top-level
// entry. So `matches.last` stays a `ShellRouteMatch`, the unwrap never fires,
// and `location()` silently falls back to the stale pre-push
// `configuration.uri` — the BRANCH ROOT `/bookings`. It does not throw. It
// returns a plausible-looking wrong answer, and `expectLocation(router,
// '/bookings')` passes while the screen on top is actually the detail.
//
// Four call sites in this repo had exactly that bug.
//
// THE TEST TRAP THIS FILE IS BUILT TO AVOID
// -----------------------------------------
// Driving with `router.go(...)` instead of `context.push(...)` makes this
// whole test FALSE-PASS: `go` REPLACES the branch location and updates
// `configuration.uri`, so `location()` returns the full path and the two
// resolvers appear to agree. The divergence this file pins EXISTS ONLY UNDER
// `push`. Every drive below therefore goes through the production
// `context.push` (via a real `BookingCard` tap), and the `go` behaviour is
// asserted SEPARATELY and explicitly as the documented contrast — so anyone
// who later "simplifies" the drive to `go` will see the contrast test
// contradict the push test rather than get a quiet green.
//
// WHAT A FUTURE REFACTOR BREAKS HERE
// ----------------------------------
// Any "simplification" that collapses `nestedPushLocation` into `location`
// (they look redundant — that is the trap) fails on the `nestedPushLocation`
// assertion. Any change that makes `location()` start resolving shell-nested
// pushes fails on the `location()` assertion, which is deliberately pinned to
// the STALE branch root: that staleness is not a bug being enshrined, it is
// the precise, load-bearing reason the second resolver has to exist.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/my_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  /// CLIENT login → Записи tab → tap the seeded `BookingCard`, which runs the
  /// PRODUCTION `context.push(RouteNames.bookingDetail('booking-1'))`.
  ///
  /// Deliberately NOT `router.go` — see this file's header. The returned
  /// router is positioned on the pushed, shell-nested leaf.
  Future<GoRouter> pushBookingDetail(WidgetTester tester) async {
    final fb = FakeBackend()..currentRole = UserRole.client;
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.client);
    await AppHarness.settle(tester);

    await tester.tap(find.byKey(const Key('client-nav-tile-3')));
    await AppHarness.settle(tester);
    expect(find.byType(MyBookingsScreen), findsOneWidget);
    expect(
      find.byType(BookingCard),
      findsOneWidget,
      reason: 'the fixture must seed exactly one booking to tap',
    );

    await tester.tap(find.byType(BookingCard));
    await AppHarness.settle(tester);
    return router;
  }

  group('AppHarness resolver contract — context.push onto a shell-nested '
      'leaf (/bookings/:bookingId)', () {
    testWidgets(
      'location() reports the stale BRANCH ROOT while nestedPushLocation() '
      'reports the pushed LEAF — the two must never be conflated',
      (tester) async {
        final GoRouter router = await pushBookingDetail(tester);

        // Ground truth, independent of either resolver: the detail screen is
        // the one actually on top. Without this the assertions below could
        // both be "right" about a navigation that never happened.
        expect(
          find.byType(BookingDetailScreen),
          findsOneWidget,
          reason:
              'non-vacuity: the push must genuinely have landed on the '
              'detail screen, otherwise this test proves nothing about how '
              'the resolvers report it',
        );

        // ── The whole point. ────────────────────────────────────────────────
        expect(
          AppHarness.location(router),
          RouteNames.clientBookings,
          reason:
              'location() CANNOT see a shell-nested push: '
              'RouteMatchList.push recurses into the active ShellRouteMatch, '
              'so matches.last is never an ImperativeRouteMatch and the '
              'unwrap never fires — it falls back to the stale pre-push '
              'configuration.uri. If this now returns the full leaf path, '
              'location() gained shell-nested resolution: re-verify every '
              'expectNestedPushLocation call site before deleting the second '
              'resolver.',
        );
        expect(
          AppHarness.nestedPushLocation(router),
          RouteNames.bookingDetail('booking-1'),
          reason:
              'nestedPushLocation() drills through ShellRouteMatch.matches '
              'to the nested ImperativeRouteMatch and reads its own freshly '
              'matched RouteMatchList.uri — the only resolver that sees this '
              'shape. If this fails, every shell-nested navigation assertion '
              'in the suite is blind.',
        );

        // Stated as an inequality too, so a future refactor that makes both
        // resolvers return the SAME value fails loudly here even if someone
        // "fixes" one of the two expectations above to match the other.
        expect(
          AppHarness.location(router),
          isNot(AppHarness.nestedPushLocation(router)),
          reason:
              'these two resolvers MUST diverge on this route shape; if '
              'they agree, one of them changed behaviour and the reason for '
              'having both has silently evaporated',
        );
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      'shellLocation() is ALSO stale here — it reads matchedLocation, which '
      'ShellRouteMatch.copyWith never updates on push',
      (tester) async {
        final GoRouter router = await pushBookingDetail(tester);
        expect(find.byType(BookingDetailScreen), findsOneWidget);

        // Documents why the SECOND-most-plausible wrong choice is also wrong:
        // a reader who knows the route is "in a shell" reaches for
        // shellLocation and gets the same stale branch root.
        expect(
          AppHarness.shellLocation(router),
          RouteNames.clientBookings,
          reason:
              'shellLocation() reads matches.last.matchedLocation; '
              'ShellRouteMatch.copyWith (what push uses to graft the leaf in) '
              'never updates matchedLocation, so it stays the branch root. '
              'Neither location() nor shellLocation() resolves a nested push.',
        );
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      'CONTRAST (the test trap): driving the SAME route with router.go makes '
      'location() report the full path — which is exactly why this contract '
      'must be driven with context.push',
      (tester) async {
        final fb = FakeBackend()..currentRole = UserRole.client;
        final GoRouter router = await AppHarness.boot(tester, fb);
        await AppHarness.loginAs(tester, fb, UserRole.client);
        await AppHarness.settle(tester);

        // `go`, NOT `push` — the drive this contract must never use.
        router.go(RouteNames.bookingDetail('booking-1'));
        await AppHarness.settle(tester);

        expect(
          AppHarness.location(router),
          RouteNames.bookingDetail('booking-1'),
          reason:
              'go() REPLACES the branch location and updates '
              'configuration.uri, so the naive resolver looks correct. A '
              'go-driven nav test therefore proves NOTHING about the pushed '
              'shape production actually uses — this assertion exists so that '
              'contrast is pinned in the suite rather than rediscovered.',
        );
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  });
}
