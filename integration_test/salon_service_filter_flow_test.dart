// Salon-service → masters FILTER — E2E (fake-backed).
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ---------------------------------------
// The widget tier
// (test/features/salon/presentation/public_salon_profile_screen_test.dart)
// proves the filter UI in isolation with BOTH the salon repository AND
// `salonMasterServiceCoverageProvider` STUBBED — the coverage map is a
// hand-built literal, never the real per-master `GET /masters/{id}/services`
// fan-out. It cannot catch:
//   • the real user journey — open a salon profile → Послуги tab → tap a
//     service row → auto-jump to the Майстри tab with the roster narrowed;
//   • the provider→repository wiring of the coverage fan-out: tapping a
//     service actually FIRES `salonMasterServiceCoverageProvider`, which fans
//     `GET /masters/{id}/services` out over the WHOLE 8-master roster through
//     the real `publicServiceRepositoryProvider` → `HttpServiceRepository` →
//     generated `ServiceControllerApi` + built_value decode — a network
//     boundary the widget tier bypasses entirely;
//   • the reduction of each master's real `MasterServiceResponse` list to a
//     `serviceDefId` set, compared against the catalogue's `salon-svc-shared`
//     id, actually excluding the non-performers end to end.
//
// FIXTURE COHERENCE — reuses the SAME `salon-xyz` fixture the public salon
// profile flow already exercises (see fake_backend.dart's "Public salon
// profile fixtures" + the per-master coverage routes). Of the 8 roster
// masters, ONLY `master-ccc` covers `salon-svc-shared` (the NAILS category's
// service); `master-aaa`/`master-ddd`…`master-iii` cover it NOT — so filtering
// by that service must collapse the grid to exactly `master-ccc`.
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

  void expectLocation(GoRouter router, String expected) {
    final String current = router.routerDelegate.currentConfiguration.uri
        .toString();
    expect(
      current,
      startsWith(expected),
      reason: 'Expected router location to start with $expected, got $current',
    );
  }

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
        // fixed-wait-ok: settles the real async route-push + parallel salon
        // detail/masters-rail reads.
        await tester.pumpAndSettle(const Duration(seconds: 1));

        expectLocation(router, '/salons/salon-xyz');
        expect(find.byType(PublicSalonProfileScreen), findsOneWidget);
        expect(find.byKey(const Key('salon-profile-name')), findsOneWidget);

        // Coverage must NOT have been fetched yet — it fires only once a
        // service filter is selected, never on a plain profile visit.
        expect(
          fb.getSalonRosterMasterServicesCalls,
          0,
          reason:
              'the per-master coverage fan-out must not fire before a service '
              'is selected',
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
        // fixed-wait-ok: settles the tab jump + the real coverage fan-out
        // (`GET /masters/{id}/services` over the whole roster).
        await tester.pumpAndSettle(const Duration(seconds: 1));

        // ── The fan-out actually hit the network for the roster ──────────────
        expect(
          fb.getSalonRosterMasterServicesCalls,
          greaterThanOrEqualTo(1),
          reason:
              'selecting a service must fire the real per-master coverage '
              'fan-out',
        );
        expect(
          fb.requestedSalonRosterMasterIds,
          containsAll(<String>['master-ccc', 'master-ddd']),
          reason:
              'the bounded fan-out must reach every roster master, not just '
              'the first one',
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
