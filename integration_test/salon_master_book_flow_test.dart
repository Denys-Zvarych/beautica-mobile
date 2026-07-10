// Salon master card «book» → MASTER-SCOPED service selection — E2E (fake-backed).
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — bugfix on a real user flow)
// --------------------------------------------------------------------
// THE BUG: on a salon's public-profile «Майстри» tab there was no way to book a
// specific master and see only THAT master's services — the only booking entry
// point was the salon-wide footer CTA (`salon-book-cta`), which opens the full
// salon catalogue. The fix (Option 1) added a corner «book» button to each
// salon master card that pushes `RouteNames.bookingNew` with the master's bare
// `masterId` String → the already-correct MASTER-SCOPED `ServiceSelectorSheet`,
// which loads `publicMasterProfileProvider(masterId)` → `getMasterServices` and
// shows ONLY that master's services.
//
// The widget tier
// (test/features/salon/presentation/public_salon_profile_screen_test.dart —
// "master card BOOK button pushes RouteNames.bookingNew …") proves the card
// fires the RIGHT route with the RIGHT `extra`, but with a hand-rolled trap
// router — it never renders the real `ServiceSelectorSheet` nor hits the
// `getMasterServices` network boundary. It therefore cannot catch the CORE
// regression: that the destination is MASTER-scoped, not salon-wide. That is
// exactly what this flow proves end to end:
//   • drive the real journey — CLIENT logs in → opens the salon profile →
//     «Майстри» tab → taps a master card's corner book button;
//   • the real app router resolves `RouteNames.bookingNew` → the real
//     `ServiceSelectorSheet(masterId)`;
//   • the real `publicMasterProfileProvider(master-ccc)` fires `GET
//     /masters/master-ccc` + `GET /masters/master-ccc/services` in parallel
//     over the pinned Dio → built_value decode — a boundary the widget tier
//     bypasses entirely;
//   • the rendered catalogue is MASTER-scoped: `master-ccc` performs a STRICT
//     SUBSET of the salon catalogue, so its exclusive-service category must be
//     absent.
//
// FIXTURE COHERENCE — reuses the SAME `salon-xyz` fixture the public-salon and
// salon-service-filter flows already exercise. The salon CATALOGUE has two
// categories/services: NAILS→`salon-svc-shared` («Манікюр класичний») and
// BROWS→`salon-svc-exclusive` («Корекція брів»). Of the 8 roster masters,
// `master-ccc` performs ONLY `salon-svc-shared` (a strict subset of the
// catalogue). So booking `master-ccc` must render the NAILS category (its one
// service) and MUST NOT render the BROWS category (the exclusive service that
// belongs to `master-ddd`, not `master-ccc`) — the crisp master-scoped-vs-
// full-catalogue proof. `master-ccc` gained a PUBLIC detail route in
// fake_backend.dart ([_publicMasterCccDetailEnvelope]) so the parallel `.wait`
// resolves instead of erroring.
//
// KEY POLICY: navigation/interaction taps are key-based (salon-tab-N,
// salon-master-card-book-<id>, booking_category_<CAT>,
// booking_service_tile_<assignmentId>). Raw find.text(...) is used only for
// content assertions on fixture data (the service names in the catalogue).

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/service_selector_sheet.dart';
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
    'CLIENT opens a salon profile → Майстри → taps a master card BOOK button → '
    'the MASTER-SCOPED service selector shows ONLY that master\'s services '
    '(strict subset of the salon catalogue), NOT the full salon catalogue',
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
        expect(find.byKey(const Key('salon-profile-name')), findsOneWidget);

        // ── «Майстри» tab → the roster grid renders master-ccc's card ────────
        await tester.tap(find.byKey(const Key('salon-tab-1')));
        await tester.pumpAndSettle();

        final Finder bookButton = find.byKey(
          const Key('salon-master-card-book-master-ccc'),
        );
        expect(
          bookButton,
          findsOneWidget,
          reason:
              'master-ccc (roster index 1) sits inside the initial 6-card cap '
              'and its card must carry a corner book button',
        );

        // ── Tap the corner BOOK button → MASTER-SCOPED booking route ─────────
        await tester.tap(bookButton);
        // fixed-wait-ok: settles the real route push + the parallel
        // publicMasterProfileProvider(master-ccc) reads (detail + services).
        await tester.pumpAndSettle(const Duration(seconds: 1));

        expectLocation(router, RouteNames.bookingNew);
        expect(
          find.byType(ServiceSelectorSheet),
          findsOneWidget,
          reason:
              'the book button must land on the master-scoped '
              'ServiceSelectorSheet, not the salon-wide booking flow',
        );

        // ── CORE PROOF: the catalogue is MASTER-scoped, not salon-wide ───────
        // master-ccc performs ONLY salon-svc-shared (NAILS) — a strict subset
        // of the salon catalogue {NAILS: salon-svc-shared, BROWS:
        // salon-svc-exclusive}. Category sections are always in the tree
        // (independent of expand state), so this proof needs no expansion:
        expect(
          find.byKey(const Key('booking_category_NAILS')),
          findsOneWidget,
          reason:
              'master-ccc performs the NAILS service (salon-svc-shared) → its '
              'category must render',
        );
        expect(
          find.byKey(const Key('booking_category_BROWS')),
          findsNothing,
          reason:
              'salon-svc-exclusive (BROWS) belongs to master-ddd, NOT '
              'master-ccc — if the sheet showed the FULL salon catalogue (the '
              'bug), this category would be present. Its ABSENCE proves the '
              'booking flow is master-scoped.',
        );

        // ── Expand NAILS → the shared service tile actually renders ──────────
        await tester.tap(find.byKey(const Key('booking_category_NAILS')));
        await tester.pumpAndSettle();

        // Tile key = booking_service_tile_<MasterService.id>, where the id is
        // the ASSIGNMENT id the fixture mints (`assign-<master>-<serviceDef>`).
        expect(
          find.byKey(
            const Key(
              'booking_service_tile_assign-master-ccc-salon-svc-shared',
            ),
          ),
          findsOneWidget,
          reason:
              'master-ccc\'s single service (salon-svc-shared) must render as '
              'a selectable tile once its category is expanded',
        );
        // i18n-finder-ok: the service name is backend catalogue fixture data.
        expect(find.text('Манікюр класичний'), findsOneWidget);

        // The exclusive service is NEVER present anywhere in this master's
        // catalogue (no BROWS section exists to hold it).
        // i18n-finder-ok: the excluded service name is backend fixture data.
        expect(
          find.text('Корекція брів'),
          findsNothing,
          reason:
              'the salon\'s EXCLUSIVE service (master-ddd\'s) must never appear '
              'in master-ccc\'s master-scoped booking catalogue',
        );

        expect(tester.takeException(), isNull);
      });
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
