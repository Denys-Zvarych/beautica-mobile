// END-TO-END integration coverage for the STAFF delete-account WIDENING
// (Step 2.7 Rule 3b).
//
// WHY THIS FILE EXISTS
// ---------------------
// Account self-deletion used to be reachable for CLIENT only
// (`client_delete_account_flow_test.dart` covers that journey end to end).
// This change widens `canSelfDeleteAccountProvider`
// (`auth_selectors.dart`) so SALON_ADMIN, SALON_MASTER and
// INDEPENDENT_MASTER can ALSO reach the shared «Акаунт» page's
// `row-delete-account` row, and drops SALON_ADMIN's own settings tune
// button (`admin_own_profile_screen.dart`) onto that page for the FIRST
// TIME — that route (`context.push(RouteNames.settings)` from the admin's
// «Профіль» tab) has never been exercised by any test, widget or
// integration, before this file.
//
// The widget tier (`mobile-dev`'s extension of
// `settings_screen_delete_account_row_test.dart` and
// `admin_own_profile_screen_test.dart`) already proves: the row-visibility
// truth table across all 5 roles, the role-aware confirm-copy selection in
// isolation, and a tap→`SettingsScreen` navigation assertion for the admin
// button against a synthetic router. What NEITHER widget file can reach —
// and what this file proves instead:
//   • the REAL post-login landing putting each role on its OWN home
//     (`/staff/profile`, `/master/profile`, the admin's «Профіль» shell
//     tab) and the REAL nav chrome (menu icon / tune button / settings-hub
//     row) pushing through to `/settings`, not a synthetic router with the
//     destination route hand-registered;
//   • the REAL `DELETE /api/v1/users/me` round trip through the fake
//     backend for EACH of these roles (a mocked-repository widget test
//     cannot prove the wire contract, only that a Dart method was called);
//   • the REAL session teardown (`AuthNotifier.logout`, secure-storage
//     wipe, redirect to `/login`) and the REAL auth-redirect guard bouncing
//     a deep link back into an authenticated route afterwards;
//   • that a SALON_OWNER — who could already reach the «Акаунт» page before
//     this change — genuinely never sees the widened row, against the REAL
//     gating provider, not a stubbed one.
//
// NO PATROL FLOW: nothing in this journey touches an OS permission dialog,
// a deep link / app link handed over by the platform, FCM or a local
// notification, a WebView, or a biometric prompt. Every route here
// (`/staff/settings`, `/master/menu`, `/salons/home`'s «Профіль» tab,
// `/salons/:id/manage/settings`, `/settings`) is an internal go_router path
// reached by an in-app tap. Stated explicitly (mobile-qa), not omitted.
//
// EXECUTION (ARCHITECTURE-mobile §12): integration_test/ is LOCAL-ONLY.
//   flutter test -d flutter-tester integration_test/staff_delete_account_flow_test.dart
// or via the aggregated entrypoints (all_tests.dart / all_tests_part1.dart).
//
// KEY-BASED NAVIGATION POLICY (enforced by AppHarness): all TAPS use
// key-based finders; role-specific dialog copy and the 422 message are
// asserted via `l10n.<key>` getters / an injected fixture string, never a
// Cyrillic literal typed into this file.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/features/master/presentation/salon_master_profile_screen.dart';
import 'package:beautica_mobile/features/master/presentation/settings_hub_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/admin_own_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_settings_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/features/settings/presentation/settings_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations_uk.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/fakes/fake_secure_storage.dart';
import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// `_adminUserJson.salonId` in `fake_backend.dart` — the salon a SALON_ADMIN
/// login lands on (`/salons/salon-admin-1/shell`). Only `GET
/// /api/v1/salons/salon-admin-1` is registered as a fake route (see that
/// file's constructor), so this id is not swappable.
const String _kAdminSalonId = 'salon-admin-1';

/// `SalonBottomNav.ownerAdminItems` — «Профіль» is destination 3, matching
/// `admin_own_profile_flow_test.dart`'s own `_navProfile` constant.
const String _kNavProfileTile = 'salon-nav-tile-3';

/// Only `salon-xyz` (besides `salon-admin-1`) has a registered `GET
/// /api/v1/salons/{id}` fake route — `salon-owner-1`, the DEFAULT
/// `FakeBackend.mySalons` entry, has none, so a `SalonManagementProfile
/// Screen`/`SalonSettingsScreen` push against it would hang on an
/// unmatched-route `DioException`. Mirrors `salon_management_profile_flow
/// _test.dart`'s identical `_kSalonId` / `_seedSalonXyzIntoMySalons`
/// fixture (duplicated here, not imported — both are private to their own
/// library).
const String _kOwnerSalonId = 'salon-xyz';

void _seedSalonXyzIntoMySalons(FakeBackend fb) {
  fb.mySalons.add(<String, dynamic>{
    'id': _kOwnerSalonId,
    'ownerId': 'user-owner-1',
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  final AppLocalizationsUk l10n = AppLocalizationsUk();

  // ── Per-role helpers to reach the shared «Акаунт» page (SettingsScreen) ──

  /// SALON_MASTER: /staff/profile -> tap `btn-menu-salon-master` ->
  /// /staff/settings (the shared `SettingsHubScreen`) -> tap `row-account`
  /// -> /settings.
  Future<GoRouter> openSalonMasterAccountPage(
    WidgetTester tester,
    FakeBackend fb,
    FakeSecureStorage storage,
  ) async {
    final GoRouter router = await AppHarness.boot(tester, fb, storage: storage);
    await AppHarness.loginAs(tester, fb, UserRole.salonMaster);
    await AppHarness.settle(tester);

    AppHarness.expectLocation(router, RouteNames.salonMasterProfile);
    expect(find.byType(SalonMasterProfileScreen), findsOneWidget);

    await AppHarness.tapVisible(
      tester,
      find.byKey(const Key('btn-menu-salon-master')),
    );
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.salonMasterSettings);
    expect(find.byType(SettingsHubScreen), findsOneWidget);

    await AppHarness.tapVisible(tester, find.byKey(const Key('row-account')));
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.settings);
    expect(find.byType(SettingsScreen), findsOneWidget);
    return router;
  }

  /// INDEPENDENT_MASTER: /master/profile -> tap `btn-menu-master` ->
  /// /master/menu (the shared `SettingsHubScreen`) -> tap `row-account` ->
  /// /settings.
  Future<GoRouter> openIndependentMasterAccountPage(
    WidgetTester tester,
    FakeBackend fb,
    FakeSecureStorage storage,
  ) async {
    final GoRouter router = await AppHarness.boot(tester, fb, storage: storage);
    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
    await AppHarness.settle(tester);

    AppHarness.expectLocation(router, RouteNames.masterProfile);
    expect(find.byType(MasterProfileScreen), findsOneWidget);

    await AppHarness.tapVisible(
      tester,
      find.byKey(const Key('btn-menu-master')),
    );
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.masterMenu);
    expect(find.byType(SettingsHubScreen), findsOneWidget);

    await AppHarness.tapVisible(tester, find.byKey(const Key('row-account')));
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.settings);
    expect(find.byType(SettingsScreen), findsOneWidget);
    return router;
  }

  /// SALON_ADMIN: /salons/home -> the salon shell's own «Профіль» tab
  /// (embedded `AdminOwnProfileScreen`) -> tap the trailing tune button
  /// (`btn-admin-own-profile-settings`) -> /settings. THE untested route
  /// before this change — see this file's header.
  Future<GoRouter> openAdminAccountPage(
    WidgetTester tester,
    FakeBackend fb,
    FakeSecureStorage storage,
  ) async {
    final GoRouter router = await AppHarness.boot(tester, fb, storage: storage);
    await AppHarness.loginAs(tester, fb, UserRole.salonAdmin);
    await AppHarness.settle(tester);

    AppHarness.expectLocation(router, RouteNames.salonShell(_kAdminSalonId));
    expect(find.byType(SalonShellScreen), findsOneWidget);

    await AppHarness.tapVisible(
      tester,
      find.byKey(const Key(_kNavProfileTile)),
    );
    await AppHarness.settle(tester);
    expect(
      find.byType(AdminOwnProfileScreen),
      findsOneWidget,
      reason: 'nav tile 3 must resolve to the real admin own-profile screen',
    );

    await AppHarness.tapVisible(
      tester,
      find.byKey(const Key('btn-admin-own-profile-settings')),
    );
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.settings);
    expect(
      find.byType(SettingsScreen),
      findsOneWidget,
      reason:
          'the trailing tune button must push the shared «Акаунт» page — '
          'this route had ZERO test coverage, widget or integration, '
          'before this change',
    );
    return router;
  }

  /// SALON_OWNER: /salons/salon-xyz/manage -> push .../manage/settings (the
  /// owner-only `SalonSettingsScreen`) -> tap its own `row-salon-general`
  /// row -> /settings, carrying `AccountSettingsExtras(showDeleteSalon:
  /// true)`. Mirrors `salon_management_profile_flow_test.dart`'s own
  /// navigation dance verbatim (same fixture, same route sequence) — this
  /// role already reached `/settings` before this change; only the
  /// delete-account row's ABSENCE is new coverage.
  Future<GoRouter> openOwnerAccountPage(
    WidgetTester tester,
    FakeBackend fb,
    FakeSecureStorage storage,
  ) async {
    final GoRouter router = await AppHarness.boot(tester, fb, storage: storage);
    await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
    // fixed-wait-ok: integration test, real async (login+landing); bounded pumpAndSettle is the recommended real-async settle.
    await tester.pumpAndSettle(const Duration(seconds: 1));

    router.go(RouteNames.salonManage(_kOwnerSalonId));
    // fixed-wait-ok: integration test, real async (route transition); bounded pumpAndSettle is the recommended real-async settle.
    await tester.pumpAndSettle(const Duration(seconds: 1));
    unawaited(router.push(RouteNames.salonManageSettings(_kOwnerSalonId)));
    // fixed-wait-ok: integration test, real async (route push); bounded pumpAndSettle is the recommended real-async settle.
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byType(SalonSettingsScreen), findsOneWidget);

    await AppHarness.tapVisible(
      tester,
      find.byKey(const Key('row-salon-general')),
    );
    await tester.pumpAndSettle();
    AppHarness.expectLocation(router, RouteNames.settings);
    expect(find.byType(SettingsScreen), findsOneWidget);
    return router;
  }

  /// Scrolls the delete-account row into view and taps it to raise the
  /// confirm dialog. Identical to `client_delete_account_flow_test.dart`'s
  /// own helper — the row and dialog are the SAME shared widgets for every
  /// role.
  Future<void> openDeleteAccountDialog(WidgetTester tester) async {
    expect(find.byKey(const Key('row-delete-account')), findsOneWidget);
    await AppHarness.tapVisible(
      tester,
      find.byKey(const Key('row-delete-account')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('btn-delete-account-confirm')),
      findsOneWidget,
      reason: 'the delete-account row must raise the confirm dialog',
    );
  }

  // ── Test 1 — SALON_MASTER: reach via salonMasterSettings, role-correct ──
  // ── copy, confirm, teardown, deep-link bounce.                        ──

  testWidgets('SALON_MASTER delete-account: reaches «Акаунт» via /staff/settings, '
      'sees the widened row, the CLIENTS\'-bookings copy renders (not the '
      'CLIENT string), confirms, DELETE /api/v1/users/me fires once, session '
      'tears down, lands on /login, and a deep-link back into '
      '/staff/profile is bounced', (tester) async {
    await mockNetworkImagesFor(() async {
      final fb = FakeBackend()..currentRole = UserRole.salonMaster;
      final storage = FakeSecureStorage();

      final router = await openSalonMasterAccountPage(tester, fb, storage);

      expect(
        await storage.readRefreshToken(),
        isNotNull,
        reason: 'login must persist a refresh token before this is exercised',
      );

      final int deleteCallsBefore = fb.deleteMyAccountCalls;
      final int logoutCallsBefore = fb.logoutCalls;

      await openDeleteAccountDialog(tester);

      // ── The role-correctness point of this whole change ──────────────
      expect(
        find.text(l10n.deleteAccountConfirmBodyMaster),
        findsOneWidget,
        reason:
            'a SALON_MASTER\'s upcoming bookings belong to their CLIENTS, '
            'not to them — the master copy must render',
      );
      expect(
        find.text(l10n.deleteAccountConfirmBody),
        findsNothing,
        reason:
            'the CLIENT-authored "your upcoming bookings" string would be '
            'factually wrong for this role and must NOT render',
      );

      await tester.tap(find.byKey(const Key('btn-delete-account-confirm')));
      // fixed-wait-ok: integration test, real async (delete + teardown + redirect); bounded pumpAndSettle is the recommended real-async settle.
      await tester.pumpAndSettle(const Duration(seconds: 2));

      AppHarness.expectLocation(router, RouteNames.login);
      expect(
        find.byKey(const ValueKey<String>('login_email')),
        findsOneWidget,
        reason: 'the login form must render after a successful account delete',
      );

      expect(fb.deleteMyAccountCalls, equals(deleteCallsBefore + 1));
      expect(
        fb.logoutCalls,
        equals(logoutCallsBefore + 1),
        reason:
            'delete-account must reuse the SAME session teardown as an '
            'explicit logout',
      );
      expect(
        await storage.readRefreshToken(),
        isNull,
        reason: 'a successful account delete must wipe the refresh token',
      );

      // Deep-link bounce: an authenticated SALON_MASTER route must not be
      // reachable for a deleted, unauthenticated session.
      router.go(RouteNames.salonMasterProfile);
      // fixed-wait-ok: integration test, real async (guard redirect to /login); bounded pumpAndSettle is the recommended real-async settle.
      await tester.pumpAndSettle(const Duration(seconds: 2));

      AppHarness.expectLocation(router, RouteNames.login);
      expect(
        find.byType(SalonMasterProfileScreen, skipOffstage: false),
        findsNothing,
        reason:
            'the deep-link must never resurrect the master\'s own profile '
            'for a deleted, unauthenticated account',
      );
      expect(await storage.readRefreshToken(), isNull);
    });
  }, timeout: const Timeout(Duration(seconds: 60)));

  // ── Test 2 — INDEPENDENT_MASTER: reach via masterMenu, confirm, ─────────
  // ── teardown, deep-link bounce.                                 ─────────

  testWidgets(
    'INDEPENDENT_MASTER delete-account: reaches «Акаунт» via /master/menu, '
    'confirms, DELETE /api/v1/users/me fires once, session tears down, '
    'lands on /login, and a deep-link back into /master/profile is bounced',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.independentMaster;
        final storage = FakeSecureStorage();

        final router = await openIndependentMasterAccountPage(
          tester,
          fb,
          storage,
        );

        expect(await storage.readRefreshToken(), isNotNull);

        final int deleteCallsBefore = fb.deleteMyAccountCalls;
        final int logoutCallsBefore = fb.logoutCalls;

        await openDeleteAccountDialog(tester);
        await tester.tap(find.byKey(const Key('btn-delete-account-confirm')));
        // fixed-wait-ok: integration test, real async (delete + teardown + redirect); bounded pumpAndSettle is the recommended real-async settle.
        await tester.pumpAndSettle(const Duration(seconds: 2));

        AppHarness.expectLocation(router, RouteNames.login);
        expect(
          find.byKey(const ValueKey<String>('login_email')),
          findsOneWidget,
        );
        expect(fb.deleteMyAccountCalls, equals(deleteCallsBefore + 1));
        expect(fb.logoutCalls, equals(logoutCallsBefore + 1));
        expect(await storage.readRefreshToken(), isNull);

        router.go(RouteNames.masterProfile);
        // fixed-wait-ok: integration test, real async (guard redirect to /login); bounded pumpAndSettle is the recommended real-async settle.
        await tester.pumpAndSettle(const Duration(seconds: 2));

        AppHarness.expectLocation(router, RouteNames.login);
        expect(
          find.byType(MasterProfileScreen, skipOffstage: false),
          findsNothing,
          reason:
              'the deep-link must never resurrect the master profile for a '
              'deleted, unauthenticated account',
        );
        expect(await storage.readRefreshToken(), isNull);
      });
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  // ── Test 3 — SALON_ADMIN: reach via the NEW tune-button route, ──────────
  // ── role-correct (bookings-free) copy, confirm, teardown, bounce. ───────

  testWidgets(
    'SALON_ADMIN delete-account: the NEW tune-button route reaches «Акаунт», '
    'the admin copy renders with NO bookings sentence (distinct from both '
    'the client and the master strings), confirms, DELETE '
    '/api/v1/users/me fires once, session tears down, lands on /login, and '
    'a deep-link back into the salon shell is bounced',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.salonAdmin;
        final storage = FakeSecureStorage();

        final router = await openAdminAccountPage(tester, fb, storage);

        expect(await storage.readRefreshToken(), isNotNull);

        final int deleteCallsBefore = fb.deleteMyAccountCalls;
        final int logoutCallsBefore = fb.logoutCalls;

        await openDeleteAccountDialog(tester);

        expect(
          find.text(l10n.deleteAccountConfirmBodyAdmin),
          findsOneWidget,
          reason:
              'an admin has no calendar of their own and performs no '
              'bookings — the admin copy must render',
        );
        expect(
          find.text(l10n.deleteAccountConfirmBody),
          findsNothing,
          reason: 'the CLIENT string must not render for an admin',
        );
        expect(
          find.text(l10n.deleteAccountConfirmBodyMaster),
          findsNothing,
          reason: 'the MASTER string must not render for an admin either',
        );

        await tester.tap(find.byKey(const Key('btn-delete-account-confirm')));
        // fixed-wait-ok: integration test, real async (delete + teardown + redirect); bounded pumpAndSettle is the recommended real-async settle.
        await tester.pumpAndSettle(const Duration(seconds: 2));

        AppHarness.expectLocation(router, RouteNames.login);
        expect(
          find.byKey(const ValueKey<String>('login_email')),
          findsOneWidget,
        );
        expect(fb.deleteMyAccountCalls, equals(deleteCallsBefore + 1));
        expect(fb.logoutCalls, equals(logoutCallsBefore + 1));
        expect(await storage.readRefreshToken(), isNull);

        router.go(RouteNames.salonHome);
        // fixed-wait-ok: integration test, real async (guard redirect to /login); bounded pumpAndSettle is the recommended real-async settle.
        await tester.pumpAndSettle(const Duration(seconds: 2));

        AppHarness.expectLocation(router, RouteNames.login);
        expect(
          find.byType(SalonShellScreen, skipOffstage: false),
          findsNothing,
          reason:
              'the deep-link must never resurrect the salon shell for a '
              'deleted, unauthenticated account',
        );
        expect(await storage.readRefreshToken(), isNull);
      });
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  // ── Test 4 — SALON_OWNER negative control: reaches «Акаунт» (already ────
  // ── could), the widened row stays ABSENT.                          ────

  testWidgets(
    'SALON_OWNER reaches «Акаунт» via the salon settings hub\'s «Загальне» '
    'row (unchanged reachability) and the delete-account row stays ABSENT '
    '— an owner owns a salon with staff beneath them and is excluded '
    'server-side',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.salonOwner;
        _seedSalonXyzIntoMySalons(fb);
        final storage = FakeSecureStorage();

        await openOwnerAccountPage(tester, fb, storage);

        // Positive control FIRST — proves the screen really rendered its
        // full, un-degraded row set (M14: a bare absence assertion could
        // otherwise pass just as well from a blank/error/loading screen).
        expect(
          find.byKey(const Key('row-change-password')),
          findsOneWidget,
          reason:
              'the screen must be genuinely rendered, not blank/loading — '
              'otherwise the delete-account absence below proves nothing',
        );
        expect(
          find.byKey(const Key('row-delete-salon')),
          findsOneWidget,
          reason:
              'confirms this really is the showDeleteSalon:true variant '
              'reached through the owner\'s own «Загальне» row, not some '
              'other degraded render of the same screen',
        );

        expect(
          find.byKey(const Key('row-delete-account')),
          findsNothing,
          reason:
              'canSelfDeleteAccountProvider must fail closed for '
              'SALON_OWNER — DELETE /api/v1/users/me 403s this role '
              'server-side',
        );
      });
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  // ── Test 5 — 422 booking-limit failure renders the backend's own ────────
  // ── message VERBATIM (role-agnostic wire behaviour, driven via SALON_ ───
  // ── MASTER so the role-widening path is what is under test).       ─────

  testWidgets('SALON_MASTER delete-account 422 (booking-limit) -> the backend '
      'message renders verbatim (not the generic fallback), stays on '
      '/settings, no teardown', (tester) async {
    await mockNetworkImagesFor(() async {
      const String marker =
          'FAKE-E2E-422-MASTER: спочатку передайте клієнтів №Q9 іншому '
          'майстру перед видаленням';
      // Constructor-time only (see `client_delete_account_flow_test.dart`'s
      // identical note) — cannot be set via cascade after construction.
      final fb = FakeBackend(
        deleteMyAccountFailureStatusCode: 422,
        deleteMyAccountFailureMessage: marker,
      )..currentRole = UserRole.salonMaster;
      final storage = FakeSecureStorage();

      final router = await openSalonMasterAccountPage(tester, fb, storage);

      final int logoutCallsBefore = fb.logoutCalls;

      await openDeleteAccountDialog(tester);
      await tester.tap(find.byKey(const Key('btn-delete-account-confirm')));
      // fixed-wait-ok: integration test, real async (failed DELETE + error snack); bounded pumpAndSettle is the recommended real-async settle.
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // The server's own, ROLE-SPECIFIC message reached the UI verbatim —
      // not the client-side `errUnknown` fallback, which would also
      // render for ANY failure regardless of what the backend actually
      // sent (the trap this assertion exists to rule out).
      expect(
        find.text(marker),
        findsOneWidget,
        reason: 'the backend 422 message must surface verbatim',
      );
      expect(find.text(l10n.errUnknown), findsNothing);

      AppHarness.expectLocation(router, RouteNames.settings);
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(
        fb.logoutCalls,
        equals(logoutCallsBefore),
        reason: 'a failed delete must NOT tear the session down',
      );
      expect(await storage.readRefreshToken(), isNotNull);
    });
  }, timeout: const Timeout(Duration(seconds: 60)));
}
