// END-TO-END integration test for cross-session cache correctness on «Мої
// записи» (Phase 076 jank audit, Step 2.7 Rule 3b).
//
// WHY THIS FILE EXISTS
// --------------------
// Phase 076 row 4 added a per-booking-id built-card cache inside
// `_BookingsTabViewState` so unchanged cards skip their rebuild. A cache that
// outlived the session would show client A's booking content to client B when
// the two share booking ids. No existing flow switched accounts on this
// surface, so disposal on logout was only argued, never executed.
//
// WHAT THIS FLOW PROVES
// ---------------------
//   1. Client A logs in → «Мої записи» renders A's two bookings (ids b1, b2,
//      service names SECRET-A-*).
//   2. Logout through the real hub (/client/menu → confirm) → /login.
//   3. The backend's dataset is swapped for client B's bookings reusing the SAME
//      ids b1, b2 with different content; B logs in and opens «Мої записи».
//   4. B sees ONLY B's content under the shared ids and none of A's — the
//      per-id cache never crossed the session boundary.
//
// NATIVE TIER: NONE NEEDED. Pure in-app widgets + HTTP (faked) — a fake-backed
// integration_test flow is the correct and sufficient tier (no permission,
// deep-link, FCM, biometric or WebView surface).
//
// Run ALONE (harness convention):
//   flutter test integration_test/client_session_switch_my_bookings_flow_test.dart -d flutter-tester

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
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

  // future-date-ok: far-future instant, deterministic on any runner clock/TZ — the partition classifier compares against the real device clock (see client_my_bookings_partition_flow_test.dart).
  final DateTime start = DateTime.utc(2035, 1, 1, 10);

  List<Map<String, dynamic>> datasetFor(FakeBackend fb, String tag) =>
      <Map<String, dynamic>>[
        for (final String id in <String>['b1', 'b2'])
          <String, dynamic>{
            ...fb.datasetBookingRow(
              id: id,
              status: 'CONFIRMED',
              startsAt: id == 'b1' ? start : start.add(const Duration(days: 1)),
            ),
            'serviceName': 'SECRET-$tag-$id',
          },
      ];

  Future<void> openBookings(WidgetTester tester, GoRouter router) async {
    await tester.tap(find.byKey(const Key('client-nav-tile-3')));
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.clientBookings);
    expect(find.byType(MyBookingsScreen), findsOneWidget);
  }

  Future<void> logoutViaHub(WidgetTester tester, GoRouter router) async {
    await tester.tap(find.byKey(const Key('client-nav-tile-0')));
    await AppHarness.settle(tester);
    await tester.tap(find.byKey(const Key('btn-menu-client')));
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.clientMenu);
    await tester.ensureVisible(find.byKey(const Key('row-logout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('row-logout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('btn-logout-confirm')));
    // fixed-wait-ok: integration test, real async (logout teardown+redirect); bounded pumpAndSettle is the recommended real-async settle.
    await tester.pumpAndSettle(const Duration(seconds: 2));
    AppHarness.expectLocation(router, RouteNames.login);
  }

  testWidgets(
    'CLIENT A logs out, CLIENT B logs in with overlapping booking ids → '
    '«Мої записи» shows only B\'s content (no per-id card cache leak)',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      fb.seedManyBookingsDataset(datasetFor(fb, 'A'));

      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await openBookings(tester, router);

      expect(find.byType(BookingCard), findsNWidgets(2));
      expect(find.text('SECRET-A-b1'), findsOneWidget);
      expect(find.text('SECRET-A-b2'), findsOneWidget);

      await logoutViaHub(tester, router);

      // Client B: the SAME ids, different content.
      fb.seedManyBookingsDataset(datasetFor(fb, 'B'));
      await AppHarness.loginAs(tester, fb, UserRole.client);
      await openBookings(tester, router);

      expect(
        find.byType(BookingCard),
        findsNWidgets(2),
        reason: 'anti-vacuity: B\'s two cards must render',
      );
      expect(find.text('SECRET-B-b1'), findsOneWidget);
      expect(find.text('SECRET-B-b2'), findsOneWidget);
      expect(
        find.textContaining('SECRET-A'),
        findsNothing,
        reason: 'client A\'s card content must never reach client B',
      );
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
