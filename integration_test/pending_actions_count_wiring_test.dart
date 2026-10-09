// Phase 393 (24.7a) — E2E wire-up proof for `pendingBookingActionsCountProvider`
// (Step 2.7 Rule 3b). No badge UI exists yet (395); this pins the whole data
// path — provider -> repository -> generated client -> Dio -> FakeBackend — so
// 395 builds on a verified count.
//
// The expected values come from the fake's OWN computation over its seeded
// rows (`computedMePendingActionsCount` / `computedSalonPendingActionsCount`,
// the same two backend-357 legs), plus an independent literal so a fake that
// computes 0 for everything cannot satisfy the test.
//
// Run ALONE: `flutter test integration_test/pending_actions_count_wiring_test.dart
// -d flutter-tester`.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/application/pending_booking_actions_count.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_bookings_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    'INDEPENDENT_MASTER on «Записи»: the .me(asMaster: false) count equals the '
    "fake's computed count, via exactly one request",
    (tester) async {
      await mockNetworkImagesFor(() async {
        final FakeBackend fb = FakeBackend();
        // 2 ended CONFIRMED + 1 COMPLETED the provider may rate = 3; the
        // in-slot CONFIRMED, the already-reviewed COMPLETED and the guest
        // COMPLETED must not count.
        final DateTime now = fb.serverNow;
        fb.seedManyBookingsDataset(<Map<String, dynamic>>[
          fb.datasetBookingRow(
            id: 'ended-1',
            status: 'CONFIRMED',
            startsAt: now.subtract(const Duration(days: 3)),
          ),
          fb.datasetBookingRow(
            id: 'ended-2',
            status: 'CONFIRMED',
            startsAt: now.subtract(const Duration(days: 2)),
          ),
          fb.datasetBookingRow(
            id: 'in-slot',
            status: 'CONFIRMED',
            startsAt: now.subtract(const Duration(minutes: 10)),
          ),
          fb.datasetBookingRow(
            id: 'to-rate',
            status: 'COMPLETED',
            startsAt: now.subtract(const Duration(days: 1)),
            providerCanReviewClient: true,
          ),
          fb.datasetBookingRow(
            id: 'reviewed',
            status: 'COMPLETED',
            startsAt: now.subtract(const Duration(days: 1)),
          ),
          <String, dynamic>{
            ...fb.datasetBookingRow(
              id: 'guest',
              status: 'COMPLETED',
              startsAt: now.subtract(const Duration(days: 1)),
              providerCanReviewClient: true,
            ),
            'clientId': null,
          },
        ]);

        final GoRouter router = await AppHarness.boot(tester, fb);
        await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
        await tester.tap(find.byKey(const Key('master-nav-tile-1')));
        await AppHarness.settle(tester);
        AppHarness.expectLocation(router, RouteNames.masterBookings);
        expect(find.byType(MasterBookingsScreen), findsOneWidget);

        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(MasterBookingsScreen)),
        );
        // Hold a listener: the provider is autoDispose and now cancels its
        // request on dispose, so an un-listened read would abort itself.
        final sub = container.listen(
          pendingBookingActionsCountProvider(
            const PendingActionsScope.me(asMaster: false),
          ),
          (_, _) {},
        );
        addTearDown(sub.close);
        final int count = await container.read(
          pendingBookingActionsCountProvider(
            const PendingActionsScope.me(asMaster: false),
          ).future,
        );

        expect(count, fb.computedMePendingActionsCount(asMaster: false));
        expect(count, 3, reason: 'independent of the fake own computation');
        expect(fb.getPendingActionsCountCalls, 1);
      });
    },
  );

  testWidgets(
    'SALON_OWNER on the board: the .salon(id) count equals the fake\'s '
    'computed count, via exactly one request',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final FakeBackend fb = FakeBackend()..currentRole = UserRole.salonOwner;
        final DateTime now = fb.serverNow;
        fb.salonBoardBookings = <Map<String, dynamic>>[
          fb.salonBoardBookingRow(
            id: 'ended',
            masterId: 'master-aaa',
            masterFirstName: 'Софія',
            masterLastName: 'Бондар',
            startsAt: now.subtract(const Duration(days: 1)),
          ),
          fb.salonBoardBookingRow(
            id: 'upcoming',
            masterId: 'master-aaa',
            masterFirstName: 'Софія',
            masterLastName: 'Бондар',
            startsAt: now.add(const Duration(days: 1)),
          ),
        ];
        fb.salonArchiveBookings = <Map<String, dynamic>>[
          fb.salonBoardBookingRow(
            id: 'to-rate',
            masterId: 'master-aaa',
            masterFirstName: 'Софія',
            masterLastName: 'Бондар',
            startsAt: now.subtract(const Duration(days: 2)),
            status: 'COMPLETED',
            providerCanReviewClient: true,
          ),
        ];

        await AppHarness.boot(tester, fb);
        await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
        final Finder bookingsTab = find.byKey(const Key('salon-nav-tile-1'));
        await AppHarness.pumpUntilFound(
          tester,
          bookingsTab.hitTestable(),
          timeout: const Duration(seconds: 20),
        );
        await tester.tap(bookingsTab);
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(SalonBookingsScreen),
          timeout: const Duration(seconds: 20),
        );

        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(SalonBookingsScreen)),
        );
        // Hold a listener: the provider is autoDispose and now cancels its
        // request on dispose, so an un-listened read would abort itself.
        final sub = container.listen(
          pendingBookingActionsCountProvider(
            const PendingActionsScope.salon(FakeBackend.kOwnerSalonId),
          ),
          (_, _) {},
        );
        addTearDown(sub.close);
        final int count = await container.read(
          pendingBookingActionsCountProvider(
            const PendingActionsScope.salon(FakeBackend.kOwnerSalonId),
          ).future,
        );

        expect(count, fb.computedSalonPendingActionsCount());
        expect(count, 2, reason: 'independent of the fake own computation');
        expect(fb.getPendingActionsCountCalls, 1);
      });
    },
  );
}
