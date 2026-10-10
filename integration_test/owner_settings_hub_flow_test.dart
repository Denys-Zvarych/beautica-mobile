// Phase 137 (21.15) — E2E: the SALON_OWNER's settings hub, through the REAL
// router, the REAL `mySalonsGuard` on `/profile/owner/settings`, the REAL
// `GET/PATCH /users/me` and the REAL logout round trip.
//
// Journey (master mode is where the owner lives): salon shell -> «Профіль»
// (`/owner/master/profile`) -> tune -> the hub (EXACTLY four rows: personal,
// account, help, logout — no contacts, no location, no toggle) ->
// «Особисті дані» -> change the first name -> save -> back on
// `/owner/master/profile` WITH the master-mode nav and the new name -> tune ->
// «Акаунт» shows «Змінити пароль» -> back -> tune -> «Вийти» -> confirm ->
// `/login`.
//
// Layer: Integration (FakeBackend over the real Dio stack, headless).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/home/presentation/client_personal_info_edit_screen.dart';
import 'package:beautica_mobile/features/master/presentation/personal_info_edit_screen.dart';
import 'package:beautica_mobile/features/master/presentation/settings_hub_screen.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/settings_row.dart';
import 'package:beautica_mobile/features/salon/presentation/owner_own_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/velvet_bottom_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/velvet_snack_matchers.dart';
import 'support/app_harness.dart';

/// `FakeBackend.mySalons`'s default single salon — the owner's post-login
/// landing.
const String _kOwnerSalonId = 'salon-owner-1';

/// `SalonBottomNav.ownerAdminItems` — «Профіль» is destination 3 (an owner
/// leaves the shell for master mode).
const Key _navProfile = Key('salon-nav-tile-3');

const Key _tune = Key('btn-owner-own-profile-settings');

String? _textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data;

/// Boots, signs the owner in and enters master mode via the shell «Профіль».
Future<GoRouter> _enterMasterMode(WidgetTester tester, FakeBackend fb) async {
  final GoRouter router = await AppHarness.boot(tester, fb);
  await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.salonShell(_kOwnerSalonId));
  expect(find.byType(SalonShellScreen), findsOneWidget);

  await AppHarness.tapVisible(tester, find.byKey(_navProfile));
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.ownerMasterProfile);
  expect(find.byType(OwnerOwnProfileScreen), findsOneWidget);
  expect(find.byType(VelvetBottomNavBar), findsOneWidget);
  return router;
}

Future<void> _openHub(WidgetTester tester, GoRouter router) async {
  await AppHarness.tapVisible(tester, find.byKey(_tune));
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.ownerSettings);
  expect(find.byType(SettingsHubScreen), findsOneWidget);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'SALON_OWNER: master-mode tune -> hub (4 rows) -> edit personal -> back in '
    'master mode with the new name -> account -> logout',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.salonOwner;
        final GoRouter router = await _enterMasterMode(tester, fb);

        // --- hub shape -------------------------------------------------
        await _openHub(tester, router);
        expect(find.byType(SettingsRow), findsNWidgets(4));
        for (final String k in <String>[
          'row-personal',
          'row-account',
          'row-help',
          'row-logout',
        ]) {
          expect(find.byKey(Key(k)), findsOneWidget, reason: k);
        }
        expect(find.byKey(const Key('row-contacts')), findsNothing);
        expect(find.byKey(const Key('row-location')), findsNothing);
        expect(find.byType(SettingsToggleRow), findsNothing);

        // --- edit personal data ---------------------------------------
        await tester.tap(find.byKey(const Key('row-personal')));
        await AppHarness.settle(tester);
        AppHarness.expectLocation(router, RouteNames.ownerEditPersonal);
        // Phase 399 — the MASTER editor (name + label + bio), not the client
        // one.
        expect(find.byType(PersonalInfoEditScreen), findsOneWidget);
        expect(find.byType(ClientPersonalInfoEditScreen), findsNothing);

        final Finder firstNameField = find.descendant(
          of: find.byKey(const Key('field-firstName')),
          matching: find.byType(TextField),
        );
        expect(
          tester.widget<TextField>(firstNameField).controller?.text,
          fb.masterFirstName,
          reason: 'pre-populated from the REAL /masters/me read',
        );
        await tester.tap(firstNameField);
        await AppHarness.settle(tester);
        await tester.enterText(firstNameField, 'Марта');
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('field-professionalTitle')),
            matching: find.byType(TextField),
          ),
          'Візажист-стиліст',
        );
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('field-bio')),
            matching: find.byType(TextField),
          ),
          'Біографія власниці 399.',
        );
        await tester.pump();

        final int patchesBefore = fb.patchProfileCalls;
        final int getMeBefore = fb.getMeCalls;
        final int servicesBefore = fb.getPublicMasterServicesCalls;
        await tester.tap(find.byKey(const Key('btn-save-personal')));
        await AppHarness.settle(tester);
        expect(fb.patchProfileCalls, patchesBefore + 1);
        expect(fb.ownerFirstName, 'Марта');
        expect(fb.masterProfessionalTitle, 'Візажист-стиліст');
        expect(fb.masterBio, 'Біографія власниці 399.');
        // Redundant-fetch pin (mobile-perf LOW, 2026-10): `go(doneRoute)`
        // lands on the ALREADY-MOUNTED master-mode profile page, so the only
        // network cost of a save is the identity refresh (`refreshUser` +
        // the invalidated `clientEditProfileProvider`: 2x GET /users/me) and
        // the one owner-profile loader re-run it triggers (1x services).
        // Any extra fetch (a cold-mounted profile) would exceed these.
        expect(fb.getMeCalls - getMeBefore, lessThanOrEqualTo(2));
        expect(
          fb.getPublicMasterServicesCalls - servicesBefore,
          lessThanOrEqualTo(1),
        );

        // --- back in master mode, not on /profile/owner ----------------
        AppHarness.expectLocation(router, RouteNames.ownerMasterProfile);
        expect(find.byType(OwnerOwnProfileScreen), findsOneWidget);
        expect(
          find.byType(VelvetBottomNavBar),
          findsOneWidget,
          reason: 'master-mode nav survives the save (no fall-out)',
        );
        await pumpPastVelvetSnack(tester);
        expect(
          _textOf(tester, 'owner-own-profile-name'),
          'Марта ${fb.ownerLastName}',
          reason: 'the new name shows without a restart',
        );
        expect(
          _textOf(tester, 'owner-own-profile-professional-title'),
          'Візажист-стиліст',
          reason: 'the saved label shows on the master-mode profile',
        );

        // --- account row ------------------------------------------------
        await _openHub(tester, router);
        await tester.tap(find.byKey(const Key('row-account')));
        await AppHarness.settle(tester);
        AppHarness.expectLocation(router, RouteNames.settings);
        expect(find.byKey(const Key('row-change-password')), findsOneWidget);
        await tester.tap(find.byKey(const Key('btn-back-account')));
        await AppHarness.settle(tester);
        expect(find.byType(SettingsHubScreen), findsOneWidget);

        // --- logout -----------------------------------------------------
        final int logoutsBefore = fb.logoutCalls;
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('row-logout')),
        );
        await AppHarness.settle(tester);
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('btn-logout-confirm')),
        );
        // fixed-wait-ok: integration test, real async (logout + teardown +
        // redirect); bounded pumpAndSettle is the recommended settle.
        await tester.pumpAndSettle(const Duration(seconds: 2));

        AppHarness.expectLocation(router, RouteNames.login);
        expect(
          find.byKey(const ValueKey<String>('login_email')),
          findsOneWidget,
        );
        expect(fb.logoutCalls, logoutsBefore + 1);
      });
    },
  );

  testWidgets(
    'SALON_OWNER: back from «Особисті дані» without saving returns to the hub',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.salonOwner;
        final GoRouter router = await _enterMasterMode(tester, fb);
        await _openHub(tester, router);

        await tester.tap(find.byKey(const Key('row-personal')));
        await AppHarness.settle(tester);
        AppHarness.expectLocation(router, RouteNames.ownerEditPersonal);
        expect(find.byType(PersonalInfoEditScreen), findsOneWidget);

        final int patchesBefore = fb.patchProfileCalls;
        await tester.tap(find.byKey(const Key('btn-back-personal')));
        await AppHarness.settle(tester);

        AppHarness.expectLocation(router, RouteNames.ownerSettings);
        expect(find.byType(SettingsHubScreen), findsOneWidget);
        expect(fb.patchProfileCalls, patchesBefore);
      });
    },
  );
}
