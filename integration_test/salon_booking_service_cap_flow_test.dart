// Phase 420 (mobile-qa Rule 3b) — E2E: the client SALON booking flow caps the
// visit selection at `maxServicesPerVisit` (10).
//
// WHY THIS FILE EXISTS
// --------------------
// Before phase 420 the salon catalogue let a client tick an 11th service;
// every day's availability call was then rejected by the backend
// (`MAX_SERVICES_PER_VISIT` = 10) and the client could never book.
// `salon_service_selection_screen_test.dart` proves the cap with the catalogue
// provider stubbed. It cannot prove that:
//   • the cap holds against the REAL catalogue fetch
//     (`GET /salons/salon-xyz/services`) reached over the real route chain;
//   • «Далі» hands the master-assignment step exactly the 10 kept ids — the
//     masters step issues ONE `GET …/services/{id}/masters` call per selected
//     service, so the call log is a wire-level record of the selection.
//
// FIXTURE: the shared `salon-xyz` fixture plus
// `FakeBackend.seedSalonCatalogOverflow(10)` — ten extra NAILS services
// (`salon-svc-cap-0..9`), each bookable by `master-ccc`. NAILS is expanded by
// default, so all 12 NAILS tiles are reachable without expanding a category.
//
// KEY POLICY: every tap is key-based (client-nav-search-center,
// search_show_masters_cta, salon_card_salon-xyz, salon-book-cta,
// salon_booking_service_tile_<id>, booking-summary-cta). `find.text` is used
// only to assert the localised warning copy via `expectVelvetSnack`.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/data/slot_repository.dart'
    show maxServicesPerVisit;
import 'package:beautica_mobile/features/booking/presentation/salon_master_selection_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_service_selection_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/velvet_snack_matchers.dart';
import 'support/app_harness.dart';

Finder _tile(String id) => find.byKey(Key('salon_booking_service_tile_$id'));

Finder _checked(String id) => find.descendant(
  of: _tile(id),
  matching: find.byKey(const ValueKey<bool>(true)),
);

/// Drives the same real UI chain `salon_booking_flow_test.dart` proves:
/// discovery → results → salon card → «Записатись» → service selection.
Future<void> _openSalonServiceSelection(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('client-nav-search-center')));
  await AppHarness.settle(tester);
  await tester.tap(find.byKey(const Key('search_show_masters_cta')));
  await tester.pump();
  for (
    int i = 0;
    i < 30 && find.byKey(const Key('results_list')).evaluate().isEmpty;
    i++
  ) {
    await tester.pump();
  }
  expect(find.byKey(const Key('results_list')), findsOneWidget);

  // Drain the shared fixture's forced second results page (see
  // salon_booking_flow_test.dart) so later settles converge.
  final ScrollPosition position = tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('results_list')),
          matching: find.byType(Scrollable),
        ),
      )
      .position;
  position.jumpTo(position.pixels + 1);
  position.jumpTo(position.maxScrollExtent);
  await AppHarness.settle(tester);

  await tester.tap(find.byKey(const Key('salon_card_salon-xyz')));
  await AppHarness.settle(tester);
  await tester.tap(find.byKey(const Key('salon-book-cta')));
  await AppHarness.settle(tester);
  expect(find.byType(SalonServiceSelectionScreen), findsOneWidget);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'CLIENT salon booking: tapping an 11th service shows the cap warning and '
    'is refused; «Далі» reaches the masters step with exactly 10 services',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.client;
        fb.seedSalonCatalogOverflow(10);
        final GoRouter router = await AppHarness.boot(tester, fb);
        await AppHarness.loginAs(tester, fb, UserRole.client);
        await AppHarness.settle(tester);

        await _openSalonServiceSelection(tester);

        // Fill the selection to the cap: the shared service + cap-0..8.
        final List<String> kept = <String>[
          'salon-svc-shared',
          for (int i = 0; i < maxServicesPerVisit - 1; i++) 'salon-svc-cap-$i',
        ];
        for (final String id in kept) {
          await AppHarness.tapVisible(tester, _tile(id));
          await AppHarness.settle(tester);
        }
        expect(find.byType(VelvetSnack), findsNothing);

        // The 11th add is refused with the cap warning.
        const String overflowId = 'salon-svc-cap-9';
        await AppHarness.tapVisible(tester, _tile(overflowId));
        await pumpVelvetSnackIn(tester);
        expectVelvetSnack(
          AppLocalizations.of(
            tester.element(find.byType(SalonServiceSelectionScreen)),
          ).bookingMaxServicesReached(maxServicesPerVisit),
          variant: VelvetSnackVariant.warning,
        );
        await pumpPastVelvetSnack(tester);
        expect(_checked(overflowId), findsNothing);
        for (final String id in kept) {
          expect(_checked(id), findsOneWidget, reason: '$id must stay checked');
        }

        // «Далі» → masters step, which queries coverage once per selected
        // service: the call log IS the selection that crossed the step.
        final int callsBefore = fb.getBookableMastersCalls;
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('booking-summary-cta')),
        );
        await AppHarness.settle(tester);

        AppHarness.expectShellLocation(router, RouteNames.salonBookingMasters);
        expect(find.byType(SalonMasterSelectionScreen), findsOneWidget);
        expect(fb.getBookableMastersCalls - callsBefore, maxServicesPerVisit);
        expect(fb.requestedBookableMastersServiceDefIds, kept.toSet());
        expect(
          fb.requestedBookableMastersServiceDefIds,
          isNot(contains(overflowId)),
        );
        expect(
          find.byKey(const Key('salon_booking_master_row_master-ccc')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    },
  );
}
