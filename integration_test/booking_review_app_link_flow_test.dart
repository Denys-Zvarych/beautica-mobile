// 2026-11-14 — booking / review App Link → go_router (docs/specs/website.md
// WEB-12/13, docs/specs/reviews.md).
//
// WHY THIS FILE EXISTS
// --------------------
// AndroidManifest.xml now claims `https://${appLinkHost}/bookings/…` with an
// autoVerify intent-filter (pinned by
// test/android/manifest_deeplink_contract_test.dart), so the emailed review CTA
// `https://beautica.app/bookings/{id}/review` is handed to the RUNNING app. The
// Android embedding (MainActivity `singleTop` → onNewIntent, with
// `flutter_deeplinking_enabled=true`) delivers it as a `pushRouteInformation`
// call on the `flutter/navigation` channel. This file sends that exact platform
// message into the real router tree and asserts where go_router + authRedirect
// land it:
//
//   • signed-in CLIENT → «Відгук про майстра» (LeaveReviewScreen) for the
//     linked booking, both for the full https URL and for a path-only route;
//   • signed-out visitor → /login (the CLIENT-only `/bookings` gate holds; the
//     review screen never renders for an anonymous session).
//
// The OS-level intent hop itself (Android → MainActivity) is native-only and
// covered by the patrol tier (integration_test/patrol/deep_link_patrol_test.dart
// pattern); this file is the fast, emulator-free routing half.
//
// KEY POLICY (AppHarness): taps are key-based; screens are asserted by type.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/presentation/leave_review_screen.dart';
import 'package:beautica_mobile/routing/app_link_replay.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/fakes/fake_secure_storage.dart';
import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';
import 'support/e2e_boot_policy.dart';

/// The emailed review CTA, as NotificationService builds it (prod host).
const String _kReviewAppLink = 'https://beautica.app/bookings/booking-1/review';

/// Delivers [location] exactly as the Android embedding does for an App Link
/// reaching a running `singleTop` MainActivity: a `pushRouteInformation` call
/// on the `flutter/navigation` channel.
Future<void> _deliverAppLink(WidgetTester tester, String location) async {
  final ByteData message = SystemChannels.navigation.codec.encodeMethodCall(
    MethodCall('pushRouteInformation', <String, Object?>{
      'location': location,
      'state': null,
    }),
  );
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    message,
    (_) {},
  );
  await AppHarness.settle(tester);
}

/// Emulates a COLD start from [link]: the Android embedding hands the App Link
/// URL to Flutter as the initial route (`defaultRouteName`), which go_router
/// prefers over its `initialLocation`.
void _coldStartFrom(WidgetTester tester, String link) {
  tester.binding.platformDispatcher.defaultRouteNameTestValue = link;
  addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  FakeBackend reviewableBooking() => FakeBackend()
    ..currentRole = UserRole.client
    ..bookingStatus = 'COMPLETED'
    ..bookingCanReview = true;

  for (final (String label, String link) in <(String, String)>[
    ('full https App Link URL', _kReviewAppLink),
    ('path-only route', RouteNames.bookingReview('booking-1')),
  ]) {
    testWidgets('signed-in CLIENT: a /bookings/{id}/review App Link ($label) '
        'opens the leave-review screen for that booking', (tester) async {
      final FakeBackend fb = reviewableBooking();
      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.client);
      AppHarness.expectLocation(router, RouteNames.clientHome);
      expect(find.byType(LeaveReviewScreen), findsNothing);

      await _deliverAppLink(tester, link);

      expect(
        find.byType(LeaveReviewScreen),
        findsOneWidget,
        reason: 'the App Link must land on «Відгук про майстра»',
      );
      final LeaveReviewScreen screen = tester.widget<LeaveReviewScreen>(
        find.byType(LeaveReviewScreen),
      );
      expect(screen.bookingId, 'booking-1');
      // go_router keeps the full App Link URI (scheme + host) as the location
      // but MATCHES on its path — the same path authRedirect's
      // `state.matchedLocation` gates on.
      expect(
        Uri.parse(AppHarness.nestedPushLocation(router)).path,
        RouteNames.bookingReview('booking-1'),
      );
      expect(
        find.byKey(const Key('leave-review-submit')),
        findsOneWidget,
        reason: 'a reviewable booking renders the review form',
      );
    });
  }

  testWidgets('signed-out visitor: a /bookings/{id}/review App Link is gated '
      'to /login and never renders the review screen', (tester) async {
    final FakeBackend fb = reviewableBooking();
    final GoRouter router = await AppHarness.boot(tester, fb);
    expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);

    await _deliverAppLink(tester, _kReviewAppLink);

    expect(find.byType(LeaveReviewScreen), findsNothing);
    AppHarness.expectLocation(router, RouteNames.login);
    expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);
  });

  testWidgets('signed-in INDEPENDENT_MASTER: the full-URL App Link still hits '
      'the CLIENT-only /bookings gate (bounced home, no review screen)', (
    tester,
  ) async {
    final FakeBackend fb = reviewableBooking()
      ..currentRole = UserRole.independentMaster;
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
    AppHarness.expectLocation(router, RouteNames.masterProfile);

    await _deliverAppLink(tester, _kReviewAppLink);

    expect(find.byType(LeaveReviewScreen), findsNothing);
    AppHarness.expectLocation(router, RouteNames.masterProfile);
  });

  // ── COLD START — the dominant email-tap case. The session is still
  // restoring when go_router sees the link, so authRedirect parks it on
  // /splash (/login when signed out); app_link_replay.dart holds it and opens
  // it once a signed-in session has settled.

  testWidgets('COLD START, stored CLIENT session: the review App Link lands on '
      'the leave-review screen once the session restores', (tester) async {
    _coldStartFrom(tester, _kReviewAppLink);
    final FakeBackend fb = reviewableBooking();
    final FakeSecureStorage storage = FakeSecureStorage();
    await storage.writeRefreshToken('fake-refresh-token');

    final GoRouter router = await AppHarness.boot(tester, fb, storage: storage);
    await AppHarness.pumpUntilFound(tester, find.byType(LeaveReviewScreen));

    expect(
      tester
          .widget<LeaveReviewScreen>(find.byType(LeaveReviewScreen))
          .bookingId,
      'booking-1',
    );
    expect(
      Uri.parse(AppHarness.nestedPushLocation(router)).path,
      RouteNames.bookingReview('booking-1'),
    );
  });

  testWidgets('COLD START signed out: the review App Link is gated to /login, '
      'then signing in as CLIENT opens it', (tester) async {
    _coldStartFrom(tester, _kReviewAppLink);
    final FakeBackend fb = reviewableBooking();
    final GoRouter router = await AppHarness.boot(tester, fb);
    AppHarness.expectLocation(router, RouteNames.login);
    expect(find.byType(LeaveReviewScreen), findsNothing);

    await AppHarness.loginAs(tester, fb, UserRole.client);
    await AppHarness.pumpUntilFound(tester, find.byType(LeaveReviewScreen));

    expect(
      Uri.parse(AppHarness.nestedPushLocation(router)).path,
      RouteNames.bookingReview('booking-1'),
    );
  });

  testWidgets('COLD START, stored INDEPENDENT_MASTER session: the CLIENT-only '
      'link is dropped — master home, and it never replays later', (
    tester,
  ) async {
    _coldStartFrom(tester, _kReviewAppLink);
    final FakeBackend fb = reviewableBooking()
      ..currentRole = UserRole.independentMaster;
    final FakeSecureStorage storage = FakeSecureStorage();
    await storage.writeRefreshToken('fake-refresh-token');

    final GoRouter router = await AppHarness.boot(tester, fb, storage: storage);
    await AppHarness.pumpUntilCondition(
      tester,
      () => AppHarness.location(router).startsWith(RouteNames.masterProfile),
      description: 'the master lands on their own home',
    );
    await AppHarness.settle(tester);

    AppHarness.expectLocation(router, RouteNames.masterProfile);
    expect(find.byType(LeaveReviewScreen), findsNothing);
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(E2eHarnessApp)),
    );
    expect(
      container.read(pendingAppLinkProvider).peek,
      isNull,
      reason: 'a link the role cannot open is consumed and dropped',
    );
  });

  // ── HOLD LIFECYCLE — warm links, sign-out clear, TTL, invalid ids.

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(E2eHarnessApp)));

  testWidgets('WARM signed out: the review App Link is held, then replayed '
      'when the owning CLIENT signs in', (tester) async {
    final FakeBackend fb = reviewableBooking();
    final GoRouter router = await AppHarness.boot(tester, fb);

    await _deliverAppLink(tester, _kReviewAppLink);
    AppHarness.expectLocation(router, RouteNames.login);
    expect(containerOf(tester).read(pendingAppLinkProvider).peek, isNotNull);

    await AppHarness.loginAs(tester, fb, UserRole.client);
    await AppHarness.pumpUntilFound(tester, find.byType(LeaveReviewScreen));

    expect(
      tester
          .widget<LeaveReviewScreen>(find.byType(LeaveReviewScreen))
          .bookingId,
      'booking-1',
    );
    expect(containerOf(tester).read(pendingAppLinkProvider).peek, isNull);
  });

  testWidgets('sign-out while on the review link, then signing in again: the '
      'link does NOT replay (lands on the client home)', (tester) async {
    final FakeBackend fb = reviewableBooking();
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.client);
    await _deliverAppLink(tester, _kReviewAppLink);
    expect(find.byType(LeaveReviewScreen), findsOneWidget);

    await containerOf(tester).read(authProvider.notifier).logout();
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.login);
    expect(
      containerOf(tester).read(pendingAppLinkProvider).peek,
      isNull,
      reason: 'sign-out clears any held link, incl. the post-redirect re-hold',
    );

    await AppHarness.loginAs(tester, fb, UserRole.client);
    await AppHarness.settle(tester);

    expect(find.byType(LeaveReviewScreen), findsNothing);
    AppHarness.expectLocation(router, RouteNames.clientHome);
  });

  testWidgets('a link held longer than the 10-minute TTL does not replay '
      'after sign-in', (tester) async {
    DateTime now = kFixedNow;
    final FakeBackend fb = reviewableBooking();
    final GoRouter router = await AppHarness.boot(tester, fb, clock: () => now);
    await _deliverAppLink(tester, _kReviewAppLink);
    expect(
      containerOf(tester).read(pendingAppLinkProvider).peek,
      RouteNames.bookingReview('booking-1'),
    );

    now = now.add(kAppLinkHoldTtl + const Duration(seconds: 1));
    await AppHarness.loginAs(tester, fb, UserRole.client);
    await AppHarness.settle(tester);

    expect(find.byType(LeaveReviewScreen), findsNothing);
    AppHarness.expectLocation(router, RouteNames.clientHome);
  });

  testWidgets('WARM signed-in CLIENT: a traversal id `/bookings/..%2F..%2Fx` '
      'renders the not-found state and calls no booking endpoint', (
    tester,
  ) async {
    final FakeBackend fb = reviewableBooking();
    await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.client);
    final int detailCallsBefore = fb.getBookingDetailCalls;

    await _deliverAppLink(tester, 'https://beautica.app/bookings/..%2F..%2Fx');

    expect(find.byKey(const Key('booking_id_invalid_error')), findsOneWidget);
    expect(find.byType(LeaveReviewScreen), findsNothing);
    expect(fb.getBookingDetailCalls, detailCallsBefore);
  });
}
