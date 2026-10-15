// Phase 412 — E2E: a category-request decision in the «Сповіщення» feed.
//
// WHY THIS FILE EXISTS
// --------------------
// The widget tier proves the copy, the role routing and the tap in isolation
// with scripted repositories. This proves the REAL journey: the backend serves
// a catalogue-decision row with a `SERVICE_CATALOG` target, the REAL
// `HttpNotificationRepository` + generated client decode it (new enum values,
// new target kind, `categoryName` / `decisionReason`), the user taps the bell
// on the real header, taps the row and lands on the screen where their ROLE
// manages services, and the row is marked read on the server:
//
//  1. INDEPENDENT_MASTER, `CATEGORY_REQUEST_APPROVED` -> «Послуги» (`/services`).
//  2. INDEPENDENT_MASTER, `SERVICE_TYPE_SUGGESTION_REJECTED` with a reason ->
//     the feed row carries the «Причина: …» line.
//  3. SALON_OWNER -> the owner master-mode «Послуги» (`/owner/master/services`).
//  4. SALON_ADMIN -> their OWN bound salon's shell on «Команда».
//
// Fixtures anchor to [kFixedNow] (the one injected clock). KEY POLICY: every tap
// and find is key- or type-based; copy is asserted through `l10n`.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/notifications/presentation/notification_copy.dart';
import 'package:beautica_mobile/features/notifications/presentation/notification_navigation.dart'
    show resetNotificationNavigationStateForTest;
import 'package:beautica_mobile/features/notifications/presentation/notifications_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/salon_bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

const Key _masterBell = Key('master_profile_bell_button');

/// The owner / admin salon-shell cover bell.
const Key _coverBell = Key('salon-manage-notifications');

/// The SALON_ADMIN persona's own salon (`_adminUserJson.salonId`).
const String _kAdminSalonId = 'salon-admin-1';

/// The owner's own master row in their primary salon (owner master mode).
const String _kOwnerMasterRowId = 'master-row-owner-1';

/// Bottom-nav destination of «Команда» (`SalonBottomNav.ownerAdminItems`).
const int _navTeam = 2;

/// Fixture DATA: the admin's free-text reject reason (not UI copy).
const String _kReason = 'Такий тип уже існує в каталозі';

Finder _tile(String id) => find.byKey(Key('notification-tile-$id'));

/// Seeds one approved-category decision row for the role about to log in.
String _seedApproved(FakeBackend fb) => fb.seedNotification(
  type: 'CATEGORY_REQUEST_APPROVED',
  targetKind: 'SERVICE_CATALOG',
  categoryName: 'Nails',
);

/// Boots, logs in as [role] and opens the feed through [bell].
Future<GoRouter> _openFeed(
  WidgetTester tester,
  FakeBackend fb,
  UserRole role,
  Key bell,
) async {
  final GoRouter router = await AppHarness.boot(tester, fb);
  await AppHarness.loginAs(tester, fb, role);
  await AppHarness.settle(tester);
  await tester.tap(find.byKey(bell));
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.notifications);
  expect(find.byType(NotificationsScreen), findsOneWidget);
  return router;
}

Future<void> _tapRow(WidgetTester tester, FakeBackend fb, String id) async {
  expect(_tile(id), findsOneWidget, reason: 'the new wire type decoded');
  expect(fb.notificationMarkedReadIds, isEmpty);
  await tester.tap(_tile(id));
  await AppHarness.settle(tester);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(() {
    resetNotificationNavigationStateForTest();
    AppHarness.tearDownHarness();
  });

  testWidgets('INDEPENDENT_MASTER: bell -> feed shows the approved-category '
      'row -> tap opens «Послуги» and marks the row read', (tester) async {
    final fb = FakeBackend()..currentRole = UserRole.independentMaster;
    final String id = _seedApproved(fb);
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.masterProfile);

    await tester.tap(find.byKey(_masterBell));
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.notifications);
    expect(find.byType(NotificationsScreen), findsOneWidget);

    await _tapRow(tester, fb, id);

    expect(find.byType(ServicesListScreen), findsOneWidget);
    expect(fb.notificationMarkedReadIds, <String>[id]);
  });

  testWidgets('INDEPENDENT_MASTER: a rejected service-type row WITH a reason '
      'shows the sentence and the «Причина: …» line in the feed', (
    tester,
  ) async {
    final fb = FakeBackend()..currentRole = UserRole.independentMaster;
    // `serviceName` (the service-type name) is the fake's default `Service 1`.
    final String id = fb.seedNotification(
      type: 'SERVICE_TYPE_SUGGESTION_REJECTED',
      targetKind: 'SERVICE_CATALOG',
      categoryName: 'Nails',
      decisionReason: _kReason,
    );
    await _openFeed(tester, fb, UserRole.independentMaster, _masterBell);
    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(NotificationsScreen)),
    );
    final String sentence = l10n.notificationBodyServiceTypeRejected(
      NotificationCopy.sanitize('Service 1')!,
      NotificationCopy.sanitize('Nails')!,
    );
    final String reasonLine = l10n.notificationDecisionReason(
      NotificationCopy.sanitize(_kReason)!,
    );

    final Finder tile = _tile(id);
    expect(tile, findsOneWidget, reason: 'the new wire type decoded');
    expect(
      find.descendant(
        of: tile,
        matching: find.text(l10n.notificationTitleServiceTypeRejected),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tile, matching: find.text('$sentence\n$reasonLine')),
      findsOneWidget,
      reason: 'decisionReason decoded off the wire and rendered as line 2',
    );
  });

  testWidgets('SALON_OWNER: tap an approved-category row -> the owner '
      'master-mode «Послуги» (/owner/master/services)', (tester) async {
    await mockNetworkImagesFor(() async {
      // The owner is ALWAYS a master: give them their own master row in
      // their primary salon, as the owner master-mode flows do.
      final fb =
          FakeBackend(
              masterRowId: _kOwnerMasterRowId,
              masterSalonId: FakeBackend.kOwnerSalonId,
              wireOwnRowServices: true,
            )
            ..currentRole = UserRole.salonOwner
            ..hasMasterProfile = true;
      final String id = _seedApproved(fb);
      final GoRouter router = await _openFeed(
        tester,
        fb,
        UserRole.salonOwner,
        _coverBell,
      );

      await _tapRow(tester, fb, id);

      // The push lands ON TOP of the salon shell, whose `configuration.uri`
      // keeps reporting the shell; the leaf-chain resolver reads the screen.
      AppHarness.expectShellLocation(router, RouteNames.ownerMasterServices);
      expect(find.byType(ServicesListScreen), findsOneWidget);
      expect(fb.notificationMarkedReadIds, <String>[id]);
    });
  });

  testWidgets('SALON_ADMIN: tap an approved-category row -> their OWN bound '
      "salon's shell on «Команда»", (tester) async {
    await mockNetworkImagesFor(() async {
      final fb = FakeBackend()..currentRole = UserRole.salonAdmin;
      final String id = _seedApproved(fb);
      final GoRouter router = await _openFeed(
        tester,
        fb,
        UserRole.salonAdmin,
        _coverBell,
      );

      await _tapRow(tester, fb, id);

      expect(
        AppHarness.location(router),
        RouteNames.salonShell(_kAdminSalonId, openTeam: true),
      );
      expect(find.byType(SalonShellScreen), findsOneWidget);
      expect(
        tester
            .widget<SalonBottomNav>(
              find.byKey(const Key('salon-shell-bottom-nav')),
            )
            .currentIndex,
        _navTeam,
        reason: 'shell opened on «Команда»',
      );
      expect(fb.notificationMarkedReadIds, <String>[id]);
    });
  });
}
