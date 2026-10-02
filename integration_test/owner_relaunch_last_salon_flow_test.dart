// Phase 288 — E2E: a SALON_OWNER reopens on the salon they were last viewing.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ----------------------------------------
// `SalonHomeResolverScreen` now resolves the owner landing as: the stored
// last-visited salon (same user AND still in `GET /salons/mine`) -> the first
// salon -> the «Мої салони» hub. The widget tier
// (`salon_home_resolver_screen_test.dart`) pins each branch against stubbed
// providers; only this file proves the WRITER (`SalonShellScreen`), the slot
// (`FakeSecureStorage`, which honours `StorageKeys.deviceScoped` exactly as
// the real `deleteAll()` does), the logout wipe and the READER line up across
// a real app relaunch.
//
// RELAUNCH MODEL
// --------------
// A "relaunch" unmounts the whole app (`pumpWidget(SizedBox.shrink())`, which
// disposes the old `ProviderScope` and every cached provider, including the
// keepAlive router) and boots a fresh `ProviderScope` over the SAME
// `FakeSecureStorage` and `FakeBackend` instances — tokens and the
// last-salon slot survive, exactly as on a real process kill. The session is
// restored from the stored refresh token; `loginCalls` must not move.
//
// SALONS
// ------
// A = `salon-owner-1` (the default fixture, FIRST in server order; its
// `isPrimary` is cleared here and C carries it instead). B = `salon-xyz` —
// the only id with a wired owner shell, a `GET /salons/{id}` route and a
// `DELETE` handler that drops the row from `mySalons` (`fake_backend.dart`).
// C = a third salon, `isPrimary: true`, so "first remaining" is chosen from a
// genuine list and can never be confused with "the primary". B is never
// `salons.first`, so every "lands on B" assertion is non-vacuous.
//
// Behaviour only — nothing here pins the ORDER in which the resolver reads
// `mySalonsProvider` and `lastVisitedSalonProvider`.
//
// NO PATROL FLOW: no OS dialog, deep link, notification, WebView or
// biometric is involved.

import 'dart:async';
import 'dart:convert';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/salon/presentation/my_salons_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_settings_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/fakes/fake_secure_storage.dart';
import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

const String _kOwnerUserId = 'user-owner-1';
const String _kSalonA = 'salon-owner-1';
const String _kSalonB = 'salon-xyz';
const String _kSalonC = 'salon-relaunch-c';

/// Appends B and C after the default A so server order is A, B, C, and moves
/// `isPrimary` from A to C — so "lands on A" can only mean "first in server
/// order", never "the primary" (Phase 288 retires the isPrimary pick).
void _seedSalonsBAndC(FakeBackend fb) {
  fb.mySalons.single['isPrimary'] = false;
  fb.mySalons.addAll(<Map<String, dynamic>>[
    <String, dynamic>{
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
    },
    <String, dynamic>{
      'id': _kSalonC,
      'ownerId': _kOwnerUserId,
      'name': 'Салон «Третій»',
      'city': 'Київ',
      'cityId': 'city-kyiv',
      'oblastId': 'oblast-kyiv',
      'street': 'вул. Січових Стрільців',
      'buildingNo': '3',
      'isActive': true,
      'isPrimary': true,
    },
  ]);
}

/// Decodes the last-salon slot, or `null` when it is empty.
Future<Map<String, dynamic>?> _readSlot(FakeSecureStorage storage) async {
  final String? raw = await storage.readLastSalon();
  return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
}

/// Cold start + login; asserts the owner lands on A's shell.
Future<GoRouter> _bootAndLogin(
  WidgetTester tester,
  FakeBackend fb,
  FakeSecureStorage storage,
) async {
  final GoRouter router = await AppHarness.boot(tester, fb, storage: storage);
  await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.salonShell(_kSalonA));
  return router;
}

/// Hub -> tap B's card -> B's shell; waits for the post-frame slot write.
Future<void> _openSalonBFromHub(
  WidgetTester tester,
  GoRouter router,
  FakeSecureStorage storage,
) async {
  router.go(RouteNames.mySalons);
  await AppHarness.settle(tester);
  expect(find.byType(MySalonsScreen), findsOneWidget);

  final Finder cardB = find.byKey(
    const ValueKey<String>('my_salons_card_$_kSalonB'),
  );
  expect(cardB, findsOneWidget);
  await AppHarness.tapVisible(tester, cardB);
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.salonShell(_kSalonB));
  expect(find.byType(SalonShellScreen), findsOneWidget);

  // The writer is post-frame + unawaited (Phase 287 D2): poll the slot
  // (bounded) rather than assume one settle covered the write.
  for (int i = 0; i < 50; i++) {
    if ((await _readSlot(storage))?['salonId'] == _kSalonB) break;
    // fixed-wait-ok: bounded poll step (<=5 s) on an async storage read,
    // the same step pumpUntilCondition uses; it exits as soon as B lands.
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(
    await _readSlot(storage),
    equals(<String, dynamic>{'userId': _kOwnerUserId, 'salonId': _kSalonB}),
  );
}

/// Kills the app (unmounts the scope) and cold-starts it over the SAME
/// storage and backend. Does NOT log in — the stored refresh token must.
Future<GoRouter> _relaunch(
  WidgetTester tester,
  FakeBackend fb,
  FakeSecureStorage storage,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await AppHarness.settle(tester);
  final GoRouter router = await AppHarness.boot(tester, fb, storage: storage);
  await AppHarness.settle(tester);
  return router;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'owner_relaunch_reopensLastVisitedSalon: owner views B, relaunches, lands '
    'on B',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.salonOwner;
      _seedSalonsBAndC(fb);
      final storage = FakeSecureStorage();

      GoRouter router = await _bootAndLogin(tester, fb, storage);
      await _openSalonBFromHub(tester, router, storage);
      final int loginsBefore = fb.loginCalls;

      router = await _relaunch(tester, fb, storage);

      AppHarness.expectLocation(router, RouteNames.salonShell(_kSalonB));
      final SalonShellScreen shell = tester.widget<SalonShellScreen>(
        find.byType(SalonShellScreen),
      );
      expect(
        shell.salonId,
        _kSalonB,
        reason: 'the relaunch must reopen the salon the owner last viewed',
      );
      expect(
        fb.loginCalls,
        loginsBefore,
        reason: 'a relaunch restores the session; it never re-logs in',
      );
    },
  );

  testWidgets(
    'owner_relaunch_afterDeletingRecordedSalon_opensFirstRemaining: B '
    'deleted, relaunch lands on A',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.salonOwner;
      _seedSalonsBAndC(fb);
      final storage = FakeSecureStorage();

      GoRouter router = await _bootAndLogin(tester, fb, storage);
      await _openSalonBFromHub(tester, router, storage);

      // Delete B through the real swipe -> confirm -> DELETE flow.
      router.go(RouteNames.mySalons);
      await AppHarness.settle(tester);
      final Finder dismissibleB = find.byKey(
        const ValueKey<String>('my_salons_dismissible_$_kSalonB'),
      );
      expect(dismissibleB, findsOneWidget);
      await tester.fling(dismissibleB, const Offset(-500, 0), 1000);
      await AppHarness.settle(tester);
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('btn-confirm-delete-salon')),
      );
      await AppHarness.settle(tester);

      expect(fb.deleteSalonCalls, 1);
      expect(
        fb.mySalons.map((Map<String, dynamic> s) => s['id']),
        isNot(contains(_kSalonB)),
        reason: 'the fake DELETE handler drops B from GET /salons/mine',
      );
      AppHarness.expectLocation(router, RouteNames.mySalons);
      // Non-vacuity: the slot must still name B, or the relaunch below would
      // land on A for the wrong reason (nothing stored) instead of proving
      // the resolver's list-membership self-heal.
      expect((await _readSlot(storage))?['salonId'], _kSalonB);

      router = await _relaunch(tester, fb, storage);

      AppHarness.expectLocation(router, RouteNames.salonShell(_kSalonA));
      expect(
        tester.widget<SalonShellScreen>(find.byType(SalonShellScreen)).salonId,
        _kSalonA,
        reason: 'a stale pointer to a deleted salon falls back to the first',
      );
    },
  );

  testWidgets(
    'owner_signOutThenSignIn_opensFirstSalon: sign out from B, sign back in, '
    'lands on A not B (D6)',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.salonOwner;
      _seedSalonsBAndC(fb);
      final storage = FakeSecureStorage();

      final GoRouter router = await _bootAndLogin(tester, fb, storage);
      await _openSalonBFromHub(tester, router, storage);

      // Owner settings hub for B -> «Вийти» -> confirm (real logout()).
      router.go(RouteNames.salonManage(_kSalonB));
      await AppHarness.settle(tester);
      unawaited(router.push(RouteNames.salonManageSettings(_kSalonB)));
      await AppHarness.settle(tester);
      expect(find.byType(SalonSettingsScreen), findsOneWidget);

      final int logoutsBefore = fb.logoutCalls;
      await AppHarness.tapVisible(tester, find.byKey(const Key('row-logout')));
      await AppHarness.settle(tester);
      await AppHarness.tapVisible(
        tester,
        find.byKey(const Key('btn-logout-confirm')),
      );
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const ValueKey<String>('login_email')),
      );
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.login);
      expect(fb.logoutCalls, logoutsBefore + 1);

      // Captured now, asserted AFTER the landing so the landing assertion is
      // the one a regression trips first (mutation-proof target).
      final Map<String, dynamic>? slotAfterLogout = await _readSlot(storage);

      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.settle(tester);

      AppHarness.expectLocation(router, RouteNames.salonShell(_kSalonA));
      expect(
        tester.widget<SalonShellScreen>(find.byType(SalonShellScreen)).salonId,
        _kSalonA,
        reason:
            'an explicit sign-out forgets the salon: the next login lands on '
            'the first salon, never the one viewed before signing out',
      );
      expect(
        slotAfterLogout,
        isNull,
        reason: 'logout (deleteAll) must wipe StorageKeys.lastSalon',
      );
    },
  );

  testWidgets(
    'owner_relaunch_afterDeletingAllSalons_landsOnHubWithAddCta: pointer set, '
    'all salons gone, relaunch lands on «Мої салони»',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.salonOwner;
      _seedSalonsBAndC(fb);
      final storage = FakeSecureStorage();

      final GoRouter first = await _bootAndLogin(tester, fb, storage);
      await _openSalonBFromHub(tester, first, storage);

      // Every salon gone server-side (the fake has no DELETE for A/C; the
      // end state, an empty GET /salons/mine, is what the resolver reads).
      fb.mySalons.clear();

      final GoRouter router = await _relaunch(tester, fb, storage);

      AppHarness.expectLocation(router, RouteNames.mySalons);
      expect(find.byType(MySalonsScreen), findsOneWidget);
      expect(find.byType(SalonShellScreen), findsNothing);
      expect(find.byKey(const Key('my_salons_add_cta')), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('my_salons_card_$_kSalonB')),
        findsNothing,
      );
    },
  );
}
