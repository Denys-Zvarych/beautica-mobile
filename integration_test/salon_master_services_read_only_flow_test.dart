// Phase 321 — E2E: the SALON_MASTER's real «Послуги» journey.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ----------------------------------------
// Direct sibling of `salon_master_schedule_nav_flow_test.dart` (phase
// 309-311's equivalent flow for the «Графік» tile) — same rationale, same
// shape, for the «Послуги» tile phase 321 closes. The dense unit/widget
// coverage for this track (`salon_master_bottom_nav_redirect_test.dart`,
// `app_router_page_type_test.dart`'s PT-3, `auth_redirect_test.dart`'s
// `/staff/*` matrix, `salon_master_own_services_route_test.dart`'s D3 target
// resolution) all prove their slice against a hand-built router/container.
// None of that tier drives:
//   • the REAL post-login landing dispatch (`roleHomePath`) putting a
//     SALON_MASTER on `/staff/profile` in the first place;
//   • the REAL `VelvetBottomNavBar` on `SalonMasterProfileScreen`, built with
//     its phase 321 `servicesRoute` override, through a REAL tap;
//   • the REAL `auth_redirect.dart` gate admitting `/staff/services` and
//     leaving `/services` closed, both resolved by the ACTUAL redirect
//     callback wired into `appRouter`;
//   • the REAL `masterProfileProvider` → `GET /masters/me` →
//     `serviceRepositoryProvider` → `GET /salons/{s}/masters/{m}/services`
//     chain against a real (fake) HTTP backend;
//   • that the read-only rendering and the fully-writable INDEPENDENT_MASTER
//     rendering are the SAME widget tree reached through the SAME real
//     navigation stack.
//
// FIXTURE REUSE (REUSE-FIRST): this flow does NOT seed a new salon/master
// pair. It reuses the EXACT `salon-xyz` / `master-removable` fixture phase
// 317/318's `salon_master_services_target_flow_test.dart` already wires
// (`FakeBackend._wireSalonMasterServices`, `_salonMasterServices` — a
// catalogue DISJOINT from the INDEPENDENT_MASTER's own `_services`), by
// constructing `FakeBackend(masterRowId: 'master-removable', masterSalonId:
// 'salon-xyz')`. `masterSalonId` is a NEW additive, nullable constructor
// param (default `null`) this phase adds to `fake_backend.dart` — see that
// field's doc: `GET /masters/me`'s envelope had NO `salon` object at all
// before this phase (`MasterMapper.fromDto` reads `Master.salonId` off a
// NESTED `dto.salon?.id`, a different wire shape than `GET /users/me`'s flat
// `salonId` the SALON_MASTER persona deliberately omits for an unrelated
// reason). Every existing flow keeps the exact same body — the key is
// omitted, not merely null, when unset.
//
// DISJOINT CATALOGUE, BOTH DIRECTIONS: `_salonMasterServices` shares no id,
// name or price with `_services` (the INDEPENDENT_MASTER's own menu), so a
// wrong-target render is assertable rather than indistinguishable — this
// file pins the salon card PRESENT and the operator's own card ABSENT (and
// vice versa in the CONTROL case).
//
// NO PATROL FLOW: a pure screen / route / provider / GET journey — Step 2.7
// Rule 3b's `integration_test/patrol/` requirement does not apply.
//
// FINDERS: widget Keys and widget TYPES only — never a Cyrillic UI string
// (`forbid_cyrillic_finder.sh`). `find.byType(ServicesListScreen)` (not a
// route-string assertion alone) pins the resolved page, per the go_router
// literal-before-dynamic-shadowing trap this repo has been bitten by before.

import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/features/master/presentation/salon_master_profile_screen.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// The salon whose roster carries the driven SALON_MASTER's own row —
/// reused from `_wireSalonMasterServices`'s fixed fixture.
const String _kSalonId = 'salon-xyz';

/// The `masters` ROW id `GET /masters/me` must report for this flow's
/// SALON_MASTER session, paired with [_kSalonId] via `masterSalonId` —
/// deliberately the SAME id `_wireSalonMasterServices` already wires, so no
/// new backend fixture is added (REUSE-FIRST).
const String _kMasterRowId = 'master-removable';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'SALON_MASTER taps «Послуги» from /staff/profile, lands on the REAL '
    'read-only services list loaded from the salon path, with zero write '
    'affordances, then returns to /staff/profile',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend(
          masterRowId: _kMasterRowId,
          masterSalonId: _kSalonId,
        );
        final GoRouter router = await AppHarness.boot(tester, fb);
        await AppHarness.loginAs(tester, fb, UserRole.salonMaster);
        await AppHarness.settle(tester);

        // ── Landing ──────────────────────────────────────────────────────
        expect(find.byType(SalonMasterProfileScreen), findsOneWidget);
        AppHarness.expectLocation(router, RouteNames.salonMasterProfile);

        // ── Tap the REAL «Послуги» nav tile ─────────────────────────────
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('master-nav-tile-0')),
        );

        // Never `pumpAndSettle` — the list screen runs staggered card
        // entrance animations, so "no frames scheduled" is never observed.
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(ServicesListScreen),
          timeout: const Duration(seconds: 20),
        );

        // Pin the resolved page TYPE, not the route string — a string
        // assertion alone passes under go_router's literal-before-dynamic
        // shadowing even if a different page happened to build.
        expect(find.byType(ServicesListScreen), findsOneWidget);
        AppHarness.expectLocation(router, RouteNames.salonMasterServices);

        // No error state — the real wire calls succeeded and resolved a
        // salonId/masterId pair.
        expect(
          find.byKey(const Key('salon_master_own_services_error')),
          findsNothing,
        );

        // The data came over the REAL salon-scoped wire, not a canned
        // widget-tier fixture.
        expect(
          fb.getSalonMasterServicesCalls,
          greaterThanOrEqualTo(1),
          reason:
              'the screen must resolve through /salons/{s}/masters/{m}'
              '/services, over a real round trip',
        );
        expect(
          fb.lastSalonMasterServicesPath,
          '/api/v1/salons/$_kSalonId/masters/$_kMasterRowId/services',
        );

        // ── Content renders: the salon-target catalogue is visible ──────
        // Sections start collapsed — expand NAILS to reach the card.
        final Finder nails = find.byKey(const Key('category_section_NAILS'));
        await AppHarness.pumpUntilFound(
          tester,
          nails,
          timeout: const Duration(seconds: 20),
        );
        await AppHarness.tapVisible(tester, nails);
        final Finder salonCard = find.byKey(
          const Key('service_card_salon-assign-1'),
        );
        await AppHarness.pumpUntilFound(
          tester,
          salonCard,
          timeout: const Duration(seconds: 20),
        );
        expect(
          salonCard,
          findsOneWidget,
          reason: 'the salon-target catalogue must render, not just resolve',
        );

        // ── Zero write affordances ───────────────────────────────────────
        expect(
          find.byKey(const Key('btn-create-service')),
          findsNothing,
          reason: 'phase 320 D1 — writable: false hides the FAB',
        );
        expect(
          find.descendant(
            of: salonCard,
            matching: find.byType(GestureDetector),
          ),
          findsNothing,
          reason: 'writable: false must pass a null onEdit — non-tappable',
        );

        // ── Tap «Профіль» returns to /staff/profile ──────────────────────
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('master-nav-tile-3')),
        );
        await AppHarness.settle(tester);

        expect(find.byType(SalonMasterProfileScreen), findsOneWidget);
        expect(find.byType(ServicesListScreen), findsNothing);
        AppHarness.expectLocation(router, RouteNames.salonMasterProfile);
      });
    },
  );

  testWidgets(
    'CONTROL — INDEPENDENT_MASTER\'s identical journey still lands on '
    '/services with every write affordance PRESENT, over the ROOT endpoint',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend();
        final GoRouter router = await AppHarness.boot(tester, fb);
        await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
        await AppHarness.settle(tester);

        expect(find.byType(MasterProfileScreen), findsOneWidget);
        AppHarness.expectLocation(router, RouteNames.masterProfile);

        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('master-nav-tile-0')),
        );
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(ServicesListScreen),
          timeout: const Duration(seconds: 20),
        );

        expect(find.byType(ServicesListScreen), findsOneWidget);
        AppHarness.expectLocation(router, RouteNames.services);

        expect(
          find.byKey(const Key('btn-create-service')),
          findsOneWidget,
          reason:
              'an INDEPENDENT_MASTER retains the FAB — unaffected by '
              'phase 321',
        );
        expect(
          fb.getSalonMasterServicesCalls,
          0,
          reason: 'must never take the salon-scoped path',
        );
      });
    },
  );
}
