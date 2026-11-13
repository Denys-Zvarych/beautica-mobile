// Phase 489 — E2E: a SALON_OWNER deletes their last salon, then deletes the
// account from the empty «Мої салони» hub.
//
// Path: login (owner) -> «Мої салони» -> swipe-delete the ONLY salon -> empty
// hub -> settings button (`my_salons_settings_button`, shown only on the
// empty hub) -> Owner Settings Hub -> «Акаунт» -> «Видалити акаунт» (now
// offered: `canSelfDeleteAccountProvider` sees a settled EMPTY salon list) ->
// owner-specific confirm body -> confirm -> exactly one
// `DELETE /api/v1/users/me` -> session wiped -> login screen.
//
// The last-salon setup mirrors `swipe_to_delete_salon_flow_test.dart`'s
// second test: FakeBackend's `DELETE /api/v1/salons/{id}` handler only serves
// `salon-xyz`, so the default primary salon is removed from `mySalons` after
// login and `salon-xyz` becomes the owner's only salon.
//
// Second test (user decision 2026-11-12): after the delete, the SAME email
// registers again as a SALON_OWNER and the new account sees NONE of the old
// data — no old salon, no old name, no old avatar. FakeBackend's opt-in
// `modelOwnerAccountLifecycle` wipes the old server state on the 204 and
// issues a NEW owner identity on verify-email. Owner signup creates its salon
// post-OTP (verification_screen.dart `_saveProviderProfile` → POST /salons),
// so the re-registered hub holds exactly that ONE new salon — "empty of old
// data", not literally empty.
//
// NO PATROL FLOW: no OS permission, deep link, notification or WebView.

import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_selectors.dart';
import 'package:beautica_mobile/features/master/presentation/settings_hub_screen.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/presentation/my_salons_screen.dart';
import 'package:beautica_mobile/features/settings/presentation/settings_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/fakes/fake_secure_storage.dart';
import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';
import 'support/e2e_boot_policy.dart';

/// The default primary salon FakeBackend seeds `GET /salons/mine` with.
const String _primarySalonId = 'salon-owner-1';

/// The only id FakeBackend's `DELETE /api/v1/salons/{id}` handler serves.
const String _deletableSalonId = 'salon-xyz';

/// Seeds `salon-xyz` — same fixture shape as
/// `swipe_to_delete_salon_flow_test.dart`'s private `_seedDeletableSalon`.
void _seedDeletableSalon(FakeBackend fb) {
  fb.mySalons.add(<String, dynamic>{
    'id': _deletableSalonId,
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

  testWidgets(
    'SALON_OWNER deletes the last salon -> empty hub -> settings -> «Акаунт» '
    '-> «Видалити акаунт» -> confirm -> one DELETE /users/me -> login',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.salonOwner;
        _seedDeletableSalon(fb);
        final storage = FakeSecureStorage();
        final GoRouter router = await AppHarness.boot(
          tester,
          fb,
          storage: storage,
        );

        await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
        await AppHarness.settle(tester);
        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(E2eHarnessApp)),
        );

        await _trimHubToOneSalon(tester, fb, router, container);
        await _swipeDeleteTheLastSalon(tester, fb, router, container);
        await _openAccountFromEmptyHub(tester, router);
        await _confirmDeleteAccountLandsOnLogin(tester, fb, router, storage);
      });
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  testWidgets(
    'SALON_OWNER deletes the account -> registers again with the SAME email '
    '-> sees only the new salon, new name, no old avatar',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()
          ..currentRole = UserRole.salonOwner
          ..modelOwnerAccountLifecycle = true
          ..mediaAvatarUrl = _oldAvatarUrl;
        _seedDeletableSalon(fb);
        final storage = FakeSecureStorage();
        final GoRouter router = await AppHarness.boot(
          tester,
          fb,
          storage: storage,
        );
        await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
        await AppHarness.settle(tester);
        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(E2eHarnessApp)),
        );

        await _deleteLastSalonThenAccount(tester, fb, router, container);
        expect(fb.ownerAccountDeleted, isTrue);
        AppHarness.expectLocation(router, RouteNames.login);

        await _registerOwnerAgain(tester, router);
        expect(fb.createSalonCalls, 1);
        await tester.tap(find.byKey(const ValueKey<String>('done_to_app')));
        await AppHarness.settle(tester);

        await _expectOnlyTheNewAccountsData(tester, fb, router, container);
      });
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}

/// «Мої салони» trimmed to ONE salon (see this file's header); the top bar
/// keeps no settings button while a salon is listed.
Future<void> _trimHubToOneSalon(
  WidgetTester tester,
  FakeBackend fb,
  GoRouter router,
  ProviderContainer container,
) async {
  router.go(RouteNames.mySalons);
  await tester.pumpAndSettle();
  AppHarness.expectLocation(router, RouteNames.mySalons);

  fb.mySalons.removeWhere(
    (Map<String, dynamic> s) => s['id'] == _primarySalonId,
  );
  container.invalidate(mySalonsProvider);
  await tester.pumpAndSettle();
  final List<Salon> before = await container.read(mySalonsProvider.future);
  expect(before, hasLength(1));
  expect(
    find.byKey(const Key('my_salons_settings_button')),
    findsNothing,
    reason: 'a hub with a salon keeps its top bar unchanged',
  );
}

/// Swipe-deletes the last salon; the hub stays and its list settles empty.
Future<void> _swipeDeleteTheLastSalon(
  WidgetTester tester,
  FakeBackend fb,
  GoRouter router,
  ProviderContainer container,
) async {
  await tester.fling(
    find.byKey(
      const ValueKey<String>('my_salons_dismissible_$_deletableSalonId'),
    ),
    const Offset(-500, 0),
    1000,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('btn-confirm-delete-salon')));
  await tester.pumpAndSettle();
  expect(fb.deleteSalonCalls, 1);
  AppHarness.expectLocation(router, RouteNames.mySalons);
  expect(find.byType(MySalonsScreen), findsOneWidget);
  expect(await container.read(mySalonsProvider.future), isEmpty);
}

/// Empty hub → settings button → Owner Settings Hub → «Акаунт».
Future<void> _openAccountFromEmptyHub(
  WidgetTester tester,
  GoRouter router,
) async {
  await AppHarness.tapVisible(
    tester,
    find.byKey(const Key('my_salons_settings_button')),
  );
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.ownerSettings);
  expect(find.byType(SettingsHubScreen), findsOneWidget);

  await AppHarness.tapVisible(tester, find.byKey(const Key('row-account')));
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.settings);
  expect(find.byType(SettingsScreen), findsOneWidget);
}

/// «Видалити акаунт» → owner confirm body → confirm → exactly one
/// `DELETE /users/me` → login, stored session wiped.
Future<void> _confirmDeleteAccountLandsOnLogin(
  WidgetTester tester,
  FakeBackend fb,
  GoRouter router,
  FakeSecureStorage storage,
) async {
  expect(find.byKey(const Key('row-delete-account')), findsOneWidget);
  await AppHarness.tapVisible(
    tester,
    find.byKey(const Key('row-delete-account')),
  );
  await tester.pumpAndSettle();

  final l10n = lookupAppLocalizations(const Locale('uk'));
  expect(find.text(l10n.deleteAccountConfirmBodyOwner), findsOneWidget);
  expect(find.text(l10n.deleteAccountConfirmBody), findsNothing);
  expect(fb.deleteMyAccountCalls, 0);
  expect(await storage.readRefreshToken(), isNotNull);

  await tester.tap(find.byKey(const Key('btn-delete-account-confirm')));
  // fixed-wait-ok: integration test, real async (delete + teardown + redirect); bounded pumpAndSettle is the recommended real-async settle.
  await tester.pumpAndSettle(const Duration(seconds: 2));

  expect(
    fb.deleteMyAccountCalls,
    1,
    reason: 'exactly one DELETE /api/v1/users/me must reach the wire',
  );
  AppHarness.expectLocation(router, RouteNames.login);
  expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);
  expect(
    await storage.readRefreshToken(),
    isNull,
    reason: 'the normal logout sweep must wipe the stored session',
  );
}

const String _oldAvatarUrl = 'https://cdn.beautica.test/old-owner-avatar.jpg';
const String _sameEmail = 'owner@beautica.ua';
const String _newSalonName = 'Нова Студія Лілія';
const String _newFirstName = 'Марта';

/// Login → «Мої салони» trimmed to one salon → swipe-delete it → empty hub →
/// settings → «Акаунт» → «Видалити акаунт» → confirm → login. Also pins the
/// pre-condition that the OLD session really carried the old avatar.
Future<void> _deleteLastSalonThenAccount(
  WidgetTester tester,
  FakeBackend fb,
  GoRouter router,
  ProviderContainer container,
) async {
  // Pre-condition (M14): the OLD session really carried the old avatar and
  // name, so the post-re-register "absent" asserts are not vacuous.
  expect(container.read(currentUserProvider)?.avatarUrl, _oldAvatarUrl);
  expect(container.read(currentUserProvider)?.id, 'user-owner-1');

  router.go(RouteNames.mySalons);
  await tester.pumpAndSettle();
  fb.mySalons.removeWhere(
    (Map<String, dynamic> s) => s['id'] == _primarySalonId,
  );
  container.invalidate(mySalonsProvider);
  await tester.pumpAndSettle();
  expect(await container.read(mySalonsProvider.future), hasLength(1));

  await tester.fling(
    find.byKey(
      const ValueKey<String>('my_salons_dismissible_$_deletableSalonId'),
    ),
    const Offset(-500, 0),
    1000,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('btn-confirm-delete-salon')));
  await tester.pumpAndSettle();

  await AppHarness.tapVisible(
    tester,
    find.byKey(const Key('my_salons_settings_button')),
  );
  await AppHarness.settle(tester);
  await AppHarness.tapVisible(tester, find.byKey(const Key('row-account')));
  await AppHarness.settle(tester);
  await AppHarness.tapVisible(
    tester,
    find.byKey(const Key('row-delete-account')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('btn-delete-account-confirm')));
  // fixed-wait-ok: integration test, real async (delete + teardown + redirect); bounded pumpAndSettle is the recommended real-async settle.
  await tester.pumpAndSettle(const Duration(seconds: 2));
  expect(fb.deleteMyAccountCalls, 1);
}

/// /register/role → SALON_OWNER → step 1 with the SAME email → step 2 (new
/// name + new salon name) → step 3 (city + address) → OTP → /done.
Future<void> _registerOwnerAgain(WidgetTester tester, GoRouter router) async {
  router.go(RouteNames.registerRole);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey<String>('role_salon_owner')));
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey<String>('role_continue')));
  await tester.pumpAndSettle();

  await _enter(tester, 'step1_email', _sameEmail);
  await _enter(tester, 'step1_password', 'Secret1234');
  await _enter(tester, 'step1_confirm', 'Secret1234');
  await AppHarness.tapVisible(
    tester,
    find.byKey(const ValueKey<String>('step1_terms_checkbox')),
  );
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey<String>('step1_submit')));
  await tester.pumpAndSettle();
  AppHarness.expectLocation(router, RouteNames.registerStep2);

  await _enter(tester, 'step2_first_name', _newFirstName);
  await _enter(tester, 'step2_last_name', 'Нова');
  await _enter(tester, 'step2_phone', '+380503333333');
  await _enter(tester, 'step2_salon_name', _newSalonName);
  await AppHarness.tapVisible(
    tester,
    find.byKey(const ValueKey<String>('step2_submit')),
  );
  await tester.pumpAndSettle();
  AppHarness.expectLocation(router, RouteNames.registerStep3);

  await AppHarness.pickSettlement(tester, 'city-kyiv');
  await _enter(tester, 'address_street', 'вул. Нова');
  await _enter(tester, 'address_building', '7');
  await AppHarness.tapVisible(
    tester,
    find.byKey(const ValueKey<String>('address_submit')),
  );
  await tester.pumpAndSettle();
  AppHarness.expectLocation(router, RouteNames.verification);

  await _enter(tester, 'verify_code_input', '123456');
  await tester.tap(find.byKey(const ValueKey<String>('verify_submit')));
  await AppHarness.pumpUntilCondition(
    tester,
    () => AppHarness.location(router) == RouteNames.done,
    description: 'post-OTP POST /salons + nav to /done',
  );
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  final Finder f = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(f);
  await tester.enterText(f, text);
  await tester.pump();
}

/// The re-registered session: new identity, no old avatar, and the hub lists
/// ONLY the salon created at signup — none of the deleted account's salons.
Future<void> _expectOnlyTheNewAccountsData(
  WidgetTester tester,
  FakeBackend fb,
  GoRouter router,
  ProviderContainer container,
) async {
  final User? user = container.read(currentUserProvider);
  expect(user?.id, 'user-owner-2', reason: 'a NEW account, not the old id');
  expect(user?.email, _sameEmail);
  expect(user?.firstName, _newFirstName);
  expect(user?.avatarUrl, isNull, reason: 'old avatar must not carry over');

  router.go(RouteNames.mySalons);
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.mySalons);
  final List<Salon> salons = await container.read(mySalonsProvider.future);
  expect(salons.map((Salon s) => s.name), <String>[_newSalonName]);
  expect(
    find.byKey(const ValueKey<String>('my_salons_dismissible_salon-created-1')),
    findsOneWidget,
  );
  for (final String oldId in <String>[_primarySalonId, _deletableSalonId]) {
    expect(
      find.byKey(ValueKey<String>('my_salons_dismissible_$oldId')),
      findsNothing,
      reason: 'old salon $oldId must not reappear',
    );
  }
  expect(fb.mediaAvatarUrl, isNull);
}
