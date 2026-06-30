// Phase 13.5 — E2E: CLIENT public master-profile journey + the role guard.
//
// WHY THIS FILE EXISTS
// --------------------
// The widget tier (test/features/master/presentation/public_master_profile_screen_test.dart)
// proves PublicMasterProfileScreen in isolation with the
// publicMasterProfileProvider family STUBBED. Neither it nor the notifier unit
// test exercises the REAL journey: a CLIENT logging in, navigating to
// `/masters/:masterId` (the search/favourites card push target), the route
// guard ADMITTING the CLIENT, the real publicMasterProfileProvider firing BOTH
// real repositories (masterRepository.getMasterById +
// publicServiceRepository.getMasterServices) against the backend, the identity
// card + services-count rendering from that response, the favourite heart
// POSTing a favorite, and the «Записатись» CTA pushing the booking-new route.
//
// It also pins the CLIENT-ONLY route guard end to end: an INDEPENDENT_MASTER who
// reaches `/masters/:masterId` is REDIRECTED to /master/profile (clientOnlyGuard
// → roleHomePath), and the public-detail endpoint is therefore never touched.
//
// CLIENT 403-DECOUPLING REGRESSION (mirrors client_search_flow): the public
// profile must source the master through the public `GET /masters/{id}` path
// (counted as [getPublicMasterCalls]) and NEVER the master-only `GET /masters/me`
// (counted as [getMasterCalls]) — the latter 403s for a CLIENT and triggers
// Riverpod's retry storm. Both flows assert `fb.getMasterCalls == 0`.
//
// This boots the REAL app via AppHarness (FakeBackend socket, FakeSecureStorage,
// fixed clock, overflow guard) and drives the whole flow against the fake
// backend's seeded `master-aaa` public detail + two-service list.
//
// KEY POLICY: navigation taps are key-based (public-master-favorite-toggle,
// public-master-book-cta). Raw find.text(...) is used only for content
// assertions (the master's name is backend data). See
// integration_test/support/app_harness.dart.
//
// LOCAL-EMULATOR CAVEAT: the shared client integration harness drives the real
// VM-service websocket and may not run green from the VirtualBox VM without the
// host-only adapter UP (see MEMORY: "Integration tests need host-only adapter to
// drive"). This flow is authored + `flutter analyze`-clean; confirm the green run
// on CI / a directly-driven emulator.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/master/presentation/public_master_profile_screen.dart';
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

  void expectLocation(GoRouter router, String expected) {
    final String current = router.routerDelegate.currentConfiguration.uri
        .toString();
    expect(
      current,
      startsWith(expected),
      reason: 'Expected router location to start with $expected, got $current',
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Flow A — CLIENT: profile renders → favourite toggles → «Записатись» pushes.
  // ──────────────────────────────────────────────────────────────────────────
  testWidgets(
    'CLIENT opens a master public profile → it renders the name/role/services, '
    'the favourite heart POSTs a favorite, and «Записатись» pushes /booking/new',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);

      // ── Log in as CLIENT → land on the client shell at /home ──────────────
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expectLocation(router, RouteNames.clientHome);

      // ── Navigate to /masters/master-aaa (the search/favourites card target) ─
      // MasterResultCard now wires onTap → context.push(masterPublicProfile)
      // (the TODO(13.5) is resolved). We still drive the SAME destination via
      // router.push directly here rather than tapping a rendered card: reaching a
      // real card would require driving the discovery filters + paged search
      // results off the fake backend first, which is non-deterministic and
      // orthogonal to what this flow pins. The push exercises the identical
      // route + clientOnlyGuard + publicMasterProfile provider stack the card
      // uses, so the journey under test is unchanged.
      unawaited(router.push(RouteNames.masterPublicProfile('master-aaa')));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expectLocation(router, '/masters/master-aaa');
      expect(
        find.byType(PublicMasterProfileScreen),
        findsOneWidget,
        reason: 'the CLIENT guard must ADMIT a CLIENT to the public profile',
      );

      // ── The real provider fired BOTH public reads (NOT /masters/me) ───────
      expect(
        fb.getPublicMasterCalls,
        greaterThanOrEqualTo(1),
        reason: 'the profile must resolve via the public GET /masters/{id}',
      );
      expect(
        fb.getPublicMasterServicesCalls,
        greaterThanOrEqualTo(1),
        reason: 'the services count must come from GET /masters/{id}/services',
      );
      expect(fb.lastGetPublicMasterId, 'master-aaa');

      // ── Identity card + role + services-count rendered from the response ──
      expect(
        find.byKey(const Key('public-master-profile-name')),
        findsOneWidget,
      );
      expect(find.text('Софія Бондар'), findsOneWidget);
      final Text servicesValue = tester.widget<Text>(
        find.byKey(const Key('public-master-profile-services-value')),
      );
      expect(
        servicesValue.data,
        '${FakeBackend.publicMasterServicesCount}',
        reason: 'the services-count stat must reflect the seeded list length',
      );

      // This is the read-only client view — no master edit/menu button.
      expect(find.byKey(const Key('btn-menu-master')), findsNothing);

      // ── Tap the favourite heart → optimistic flip → POST /favorites ───────
      expect(fb.addFavoriteCalls, 0);
      await tester.tap(find.byKey(const Key('public-master-favorite-toggle')));
      await tester.pumpAndSettle();

      expect(
        fb.addFavoriteCalls,
        1,
        reason: 'tapping the empty heart must POST exactly one favorite',
      );
      expect(fb.lastAddFavoriteBody?['targetType'], 'MASTER');
      expect(fb.lastAddFavoriteBody?['targetId'], 'master-aaa');

      // ── Tap «Записатись» → push the booking-new route ─────────────────────
      final Finder cta = find.byKey(const Key('public-master-book-cta'));
      expect(cta, findsOneWidget);
      await tester.tap(cta);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expectLocation(router, RouteNames.bookingNew);

      // ── 403-decoupling regression — never touched GET /masters/me ─────────
      expect(
        fb.getMasterCalls,
        0,
        reason:
            'the CLIENT public-profile journey must not hit GET /masters/me '
            '(403 decoupling — the public path is GET /masters/{id})',
      );
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  // ──────────────────────────────────────────────────────────────────────────
  // Flow B — INDEPENDENT_MASTER hitting the CLIENT-only profile route is
  // REDIRECTED to its own home (/master/profile); the public profile never
  // mounts and the public-detail endpoint is never hit.
  //
  // This pins the production [clientOnlyGuard] redirect end to end — a refactor
  // that drops the guard would silently let a master view the client-facing
  // profile, and this flow would catch it (the public route would mount).
  // ──────────────────────────────────────────────────────────────────────────
  testWidgets(
    'INDEPENDENT_MASTER reaching /masters/:id is redirected to /master/profile '
    '(CLIENT-only route guard)',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expectLocation(router, RouteNames.masterProfile);

      // Attempt to reach the CLIENT-facing public profile.
      unawaited(router.push(RouteNames.masterPublicProfile('master-aaa')));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // clientOnlyGuard → roleHomePath(independentMaster) → /master/profile.
      expectLocation(router, RouteNames.masterProfile);
      expect(
        find.byType(PublicMasterProfileScreen),
        findsNothing,
        reason: 'a non-CLIENT must never mount the public master profile',
      );
      expect(
        fb.getPublicMasterCalls,
        0,
        reason: 'the redirect must fire BEFORE the public detail is fetched',
      );
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
