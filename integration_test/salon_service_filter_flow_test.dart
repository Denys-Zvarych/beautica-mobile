// Salon-service → masters FILTER — E2E (fake-backed).
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ---------------------------------------
// The widget tier
// (test/features/salon/presentation/public_salon_profile_screen_test.dart)
// proves the filter UI in isolation with BOTH the salon repository AND
// `salonMasterServiceCoverageProvider` STUBBED — the coverage map is a
// hand-built literal, never the real
// `GET /salons/{salonId}/services/{serviceDefId}/masters` call (Phase 23.x
// bookable-masters rewire). It cannot catch:
//   • the real user journey — open a salon profile → Послуги tab → tap a
//     service row → auto-jump to the Майстри tab with the roster narrowed;
//   • the provider→repository wiring: tapping a service actually FIRES
//     `salonMasterServiceCoverageProvider`, which calls the real
//     `salonRepositoryProvider` → `HttpSalonRepository.getBookableMasters` →
//     generated `SalonControllerApi` + built_value decode — a network
//     boundary the widget tier bypasses entirely;
//   • that a master the endpoint simply OMITS from its response (server-side
//     active/assigned/schedule-usable filtering) is excluded end to end, not
//     just filtered client-side against a hand-built coverage map.
//
// FIXTURE COHERENCE — reuses the SAME `salon-xyz` fixture the public salon
// profile flow already exercises (see fake_backend.dart's "Public salon
// profile fixtures" + the bookable-masters routes). Of the 8 roster masters,
// ONLY `master-ccc` is returned by
// `GET /salons/salon-xyz/services/salon-svc-shared/masters` (the NAILS
// category's service); every other roster master (`master-aaa`, `master-ddd`
// …`master-iii`) is simply never in that response — so filtering by that
// service must collapse the grid to exactly `master-ccc`.
//
// KEY POLICY: navigation/interaction taps are key-based (salon-tab-N,
// salon-service-row-<id>, salon-masters-filter-clear, salon-master-card-<id>).
// Raw find.text(...) is used only for content assertions on fixture data
// (the service name embedded in the filter chip).

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/salon/presentation/public_salon_profile_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'CLIENT opens a salon profile → Послуги → taps a service → the Майстри tab '
    'narrows to only the performing master (real coverage fan-out) → clearing '
    'the filter restores the full roster',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.client;
        final GoRouter router = await AppHarness.boot(tester, fb);

        // ── Log in as CLIENT and reach the public salon profile ──────────────
        await AppHarness.loginAs(tester, fb, UserRole.client);
        // fixed-wait-ok: settles the real async login/route-transition step.
        await tester.pumpAndSettle(const Duration(seconds: 1));

        unawaited(router.push(RouteNames.salonPublicProfile('salon-xyz')));
        // fixed-wait-ok: settles the route-push + parallel masters-rail reads.
        await tester.pumpAndSettle(const Duration(seconds: 1));

        AppHarness.expectLocation(router, '/salons/salon-xyz');
        expect(find.byType(PublicSalonProfileScreen), findsOneWidget);
        expect(find.byKey(const Key('salon-profile-name')), findsOneWidget);

        // Coverage must NOT have been fetched yet — it fires only once a
        // service filter is selected, never on a plain profile visit.
        expect(
          fb.getBookableMastersCalls,
          0,
          reason:
              'getBookableMasters must not fire before a service is selected',
        );

        // ── Послуги tab → tap the NAILS service (salon-svc-shared) ───────────
        await tester.tap(find.byKey(const Key('salon-tab-2')));
        await tester.pumpAndSettle();

        // NAILS is the first category → expanded on load → its row is visible.
        final Finder serviceRow = find.byKey(
          const Key('salon-service-row-salon-svc-shared'),
        );
        expect(serviceRow, findsOneWidget);

        await tester.tap(serviceRow);
        // fixed-wait-ok: settles the tab jump + the real coverage-fetch call.
        await tester.pumpAndSettle(const Duration(seconds: 1));

        // ── The call actually hit the network, exactly once, for the ONE
        // service the client selected — never once per roster master. ──────
        expect(
          fb.getBookableMastersCalls,
          1,
          reason:
              'selecting ONE service must fire exactly ONE real '
              'getBookableMasters call — the roster\'s size (8 masters) is '
              'irrelevant to the call count under the Phase 23.x rewire',
        );
        expect(
          fb.requestedBookableMastersServiceDefIds,
          <String>{'salon-svc-shared'},
          reason: 'the ONE call must be keyed on the selected serviceDefId',
        );

        // ── The grid is narrowed to ONLY the performing master ───────────────
        expect(
          find.byKey(const Key('salon-master-card-master-ccc')),
          findsOneWidget,
          reason:
              'master-ccc is the only roster master that performs '
              'salon-svc-shared → it must be the only card shown',
        );
        expect(
          find.byKey(const Key('salon-master-card-master-aaa')),
          findsNothing,
          reason:
              'master-aaa does not perform salon-svc-shared → must be hidden '
              'while the filter is active',
        );
        expect(
          find.byKey(const Key('salon-master-card-master-ddd')),
          findsNothing,
          reason:
              'master-ddd performs only the EXCLUSIVE service → must be hidden '
              'under the shared-service filter',
        );

        // ── The active-filter chip names the selected service ────────────────
        final Finder chip = find.byKey(const Key('salon-masters-filter-chip'));
        expect(chip, findsOneWidget);
        // i18n-finder-ok: the service name is backend catalogue fixture data.
        expect(
          find.descendant(
            of: chip,
            matching: find.textContaining('Манікюр класичний'),
          ),
          findsOneWidget,
          reason: 'the chip must name the service the grid is filtered by',
        );

        // ── Clear the filter → the full roster returns ───────────────────────
        await tester.tap(find.byKey(const Key('salon-masters-filter-clear')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('salon-masters-filter-chip')),
          findsNothing,
          reason: 'clearing the filter dismisses the chip',
        );
        expect(
          find.byKey(const Key('salon-master-card-master-aaa')),
          findsOneWidget,
          reason:
              'the previously-hidden master-aaa returns once the filter is '
              'cleared (full roster, capped to the first 6)',
        );
        expect(
          find.byKey(const Key('salon-master-card-master-ccc')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
