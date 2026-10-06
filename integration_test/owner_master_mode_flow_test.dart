// Phase 379 (24.1b) — E2E: the SALON_OWNER's «master mode» «Профіль» tab at
// `RouteNames.ownerMasterProfile`, through the REAL router, the REAL
// `/owner/master/*` prefix gate and the REAL `GET /users/me` +
// `GET /masters/me` + `GET /masters/{id}/services` reads.
//
// WHAT THE WIDGET TIER CANNOT REACH
// ---------------------------------
// `owner_own_profile_screen_test.dart` drives the real `appRouterProvider`
// but overrides `ownerOwnProfileProvider` and `mySalonsProvider` wholesale,
// so its «‹ Салон» destination is a single stubbed salon. Here the exit runs
// the real `/salons/home` resolver over a real stored last-visited pointer:
// with TWO salons, the owner opens salon B (not the server-first A), enters
// master mode, and both exits — the «‹ Салон» pill AND the system back —
// must land back on B. A `go(mySalons)` or a first-salon fallback would land
// on A or the hub and fail.
//
// Not reachable from the UI yet (phase 384 adds the salon-shell entry), so
// master mode is entered with `router.go`, exactly as a deep link would.
//
// NO PATROL FLOW: no OS dialog, permission, notification or WebView is
// involved; system back is driven through `WidgetsBinding.handlePopRoute`,
// the same entry point the Android back / predictive-back dispatch calls.

import 'dart:convert';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/salon/presentation/my_salons_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/owner_own_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/velvet_bottom_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/fakes/fake_secure_storage.dart';
import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

const String _kOwnerUserId = 'user-owner-1';
const String _kSalonA = 'salon-owner-1';
const String _kSalonB = 'salon-master-mode-b';

const Key _masterModeBack = Key('owner-master-mode-back');

/// Appends salon B after the default A (server order A, B) so "returns to B"
/// can only mean "the last-visited salon", never "the first one".
void _seedSalonB(FakeBackend fb) {
  fb.mySalons.add(<String, dynamic>{
    'id': _kSalonB,
    'ownerId': _kOwnerUserId,
    'name': 'Студія Краси «Камелія»',
    'city': 'Київ',
    'cityId': 'city-kyiv',
    'oblastId': 'oblast-kyiv',
    'street': 'вул. Хрещатик',
    'buildingNo': '12',
    'isActive': true,
    'isPrimary': false,
  });
}

Future<String?> _storedSalonId(FakeSecureStorage storage) async {
  final String? raw = await storage.readLastSalon();
  if (raw == null) return null;
  return (jsonDecode(raw) as Map<String, dynamic>)['salonId'] as String?;
}

/// Login → A's shell → hub → B's shell (B becomes the last-visited salon).
Future<GoRouter> _enterSalonB(
  WidgetTester tester,
  FakeBackend fb,
  FakeSecureStorage storage,
) async {
  final GoRouter router = await AppHarness.boot(tester, fb, storage: storage);
  await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.salonShell(_kSalonA));

  router.go(RouteNames.mySalons);
  await AppHarness.settle(tester);
  expect(find.byType(MySalonsScreen), findsOneWidget);
  await AppHarness.tapVisible(
    tester,
    find.byKey(const ValueKey<String>('my_salons_card_$_kSalonB')),
  );
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.salonShell(_kSalonB));

  // The last-salon writer is post-frame + unawaited (Phase 287 D2): poll the
  // slot (bounded) rather than assume one settle covered the write.
  for (int i = 0; i < 50; i++) {
    if (await _storedSalonId(storage) == _kSalonB) break;
    // fixed-wait-ok: bounded poll step (<=5 s) on an async storage read; it
    // exits as soon as B lands.
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(await _storedSalonId(storage), _kSalonB);
  return router;
}

/// `router.go`s into master mode and asserts the mount: own profile, the
/// independent-master nav and the «‹ Салон» pill.
Future<void> _enterMasterMode(WidgetTester tester, GoRouter router) async {
  router.go(RouteNames.ownerMasterProfile);
  await AppHarness.settle(tester);

  AppHarness.expectLocation(router, RouteNames.ownerMasterProfile);
  expect(find.byType(OwnerOwnProfileScreen), findsOneWidget);
  expect(find.byType(ErrorState), findsNothing);
  expect(find.byType(VelvetBottomNavBar), findsOneWidget);
  expect(find.byKey(_masterModeBack), findsOneWidget);
  expect(
    find.byKey(const Key('owner-own-profile-stats')),
    findsOneWidget,
    reason: 'the owner-as-master section loaded over the wire',
  );
}

/// Asserts the owner is back on salon B's shell and master mode is gone.
void _expectBackOnSalonB(GoRouter router) {
  AppHarness.expectLocation(router, RouteNames.salonShell(_kSalonB));
  expect(find.byType(SalonShellScreen), findsOneWidget);
  expect(find.byType(VelvetBottomNavBar), findsNothing);
  expect(find.byKey(_masterModeBack), findsNothing);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets('SALON_OWNER: master-mode profile renders nav + «‹ Салон»; the '
      'pill returns to the LAST-VISITED salon shell', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.salonOwner
        ..hasMasterProfile = true;
      _seedSalonB(fb);
      final FakeSecureStorage storage = FakeSecureStorage();
      final GoRouter router = await _enterSalonB(tester, fb, storage);

      await _enterMasterMode(tester, router);
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(OwnerOwnProfileScreen)),
      );
      expect(
        find.descendant(
          of: find.byKey(_masterModeBack),
          matching: find.text(l10n.ownerMasterModeBack),
        ),
        findsOneWidget,
      );

      await AppHarness.tapVisible(tester, find.byKey(_masterModeBack));
      await AppHarness.settle(tester);

      _expectBackOnSalonB(router);
    });
  });

  testWidgets('SALON_OWNER: SYSTEM BACK on the master-mode profile does the '
      'same as «‹ Салон» — last-visited salon shell, never an app exit', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      final List<String> exits = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'SystemNavigator.pop') exits.add(call.method);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.salonOwner
        ..hasMasterProfile = true;
      _seedSalonB(fb);
      final FakeSecureStorage storage = FakeSecureStorage();
      final GoRouter router = await _enterSalonB(tester, fb, storage);

      await _enterMasterMode(tester, router);

      await tester.binding.handlePopRoute();
      await AppHarness.settle(tester);

      expect(exits, isEmpty, reason: 'system back must not exit the app');
      _expectBackOnSalonB(router);
    });
  });
}
