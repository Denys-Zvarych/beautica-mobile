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
// Phase 380 (24.1c) — the «Послуги» tab: profile → tile 0 → the owner's OWN
// master-row catalogue (empty) → «Додати послугу» → setup → save → back on
// the list with the new card. The FakeBackend wires ONLY the owner's own
// `/salons/{A}/masters/{ownerRow}/services` pair, and the flow asserts the
// bulk POST lands there and the INDEPENDENT_MASTER `/masters/me/services`
// bulk endpoint never fires.
//
// Phase 380 (mobile-qa, security audit) — the owner EDITS and then DELETES
// a seeded own-row service: the band PATCH and the unassign DELETE must both
// land on `/salons/{primary}/masters/{ownerRow}/services/{defId}` (keyed on
// the DEFINITION id), and neither INDEPENDENT_MASTER write endpoint fires.
//
// Phase 381 (24.1d) — the «Графік» tab: profile → tile 2 → the owner's OWN
// master-row schedule (empty) → «Додати години» → the weekly editor (a ROOT
// push, so SYSTEM BACK returns to «Графік», not the salon) → Monday
// 10:00–18:00 + a validity window → save → back on the calendar with Monday
// working. The FakeBackend wires ONLY `/masters/{ownerRow}/…` schedule
// routes (`wireOwnRowSchedule`); the flow pins the POST there and that no
// hard-wired (`/masters/me`, `user-master-1`, …) schedule route is touched.
//
// NO PATROL FLOW: no OS dialog, permission, notification or WebView is
// involved; system back is driven through `WidgetsBinding.handlePopRoute`,
// the same entry point the Android back / predictive-back dispatch calls.

import 'dart:convert';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/salon/presentation/my_salons_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/owner_own_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/features/schedule/presentation/master_schedule_screen.dart';
import 'package:beautica_mobile/features/schedule/presentation/weekly_template_editor_screen.dart';
import 'package:beautica_mobile/features/schedule/presentation/widgets/schedule_widgets.dart';
import 'package:beautica_mobile/features/services/presentation/service_setup_screen.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/velvet_bottom_nav_bar.dart';
import 'package:beautica_mobile/shared/widgets/velvet_top_bar.dart';
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

/// Phase 380 — the owner's `masters` ROW id, deliberately distinct from the
/// session userId so a target built off the wrong id cannot hit the wired
/// path.
const String _kOwnerMasterRowId = 'master-row-owner-1';

/// A NAILS-category service type the setup screen renders selectable
/// (same fixture `salon_owner_set_master_services_flow_test.dart` uses).
const String _kFreeTypeId = 'type-nails-gel';

/// Phase 380 (mobile-qa) — the seeded own-row service the edit/delete flow
/// drives. Assignment id and definition id deliberately differ so a write
/// keyed on the wrong one misses the wired route.
const String _kOwnAssignId = 'own-assign-1';
const String _kOwnDefId = 'own-def-1';

Map<String, dynamic> _seededOwnRow() => <String, dynamic>{
  'id': _kOwnAssignId,
  'masterId': _kOwnerMasterRowId,
  'isActive': true,
  'priceType': 'FIXED',
  'priceMin': 400,
  'priceMax': null,
  'priceDisplay': '400 ₴',
  'effectiveDurationMinutes': 60,
  'serviceDefinition': <String, dynamic>{
    'id': _kOwnDefId,
    'name': 'Манікюр класичний',
    'description': null,
    'category': 'NAILS',
    'baseDurationMinutes': 60,
    'bufferMinutesAfter': 0,
    'isActive': true,
    'priceType': 'FIXED',
    'priceMin': 400,
    'priceMax': null,
    'priceDisplay': '400 ₴',
    'photoUrl': null,
  },
};

/// Pumps until the NAILS section exists, expands it if [card] is not yet
/// visible, and waits for [card].
Future<void> _revealCard(WidgetTester tester, Finder card) async {
  final Finder nailsSection = find.byKey(const Key('category_section_NAILS'));
  await AppHarness.pumpUntilFound(
    tester,
    nailsSection,
    timeout: const Duration(seconds: 20),
  );
  if (card.evaluate().isEmpty) await _tapWhenReady(tester, nailsSection);
  await AppHarness.pumpUntilFound(
    tester,
    card,
    timeout: const Duration(seconds: 20),
  );
}

/// Readiness-gated tap (bounded), the same recipe the salon services flows
/// use — never a bare tap on a not-yet-hit-testable widget.
Future<void> _tapWhenReady(WidgetTester tester, Finder finder) async {
  try {
    await tester.ensureVisible(finder);
  } catch (_) {
    // Not yet laid out — pumpUntilFound below still gates on readiness.
  }
  await AppHarness.pumpUntilFound(
    tester,
    finder.hitTestable(),
    timeout: const Duration(seconds: 20),
  );
  await tester.tap(finder);
  await tester.pump();
}

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

  testWidgets('SALON_OWNER: «Послуги» tile → own-row empty catalogue → add a '
      'service via setup → back on the list with it; the bulk POST targets '
      '/salons/{primary}/masters/{ownerRow}/services', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb =
          FakeBackend(
              masterRowId: _kOwnerMasterRowId,
              masterSalonId: _kSalonA,
              wireOwnRowServices: true,
            )
            ..currentRole = UserRole.salonOwner
            ..hasMasterProfile = true;
      final FakeSecureStorage storage = FakeSecureStorage();
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        storage: storage,
      );
      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.salonShell(_kSalonA));

      await _enterMasterMode(tester, router);

      // ── 1. Profile → «Послуги» (tile 0) ─────────────────────────────────
      await _tapWhenReady(tester, find.byKey(const Key('master-nav-tile-0')));
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(ServicesListScreen),
        timeout: const Duration(seconds: 20),
      );
      AppHarness.expectLocation(router, RouteNames.ownerMasterServices);
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.ownRowServicesGetCalls >= 1,
        description: 'the own-row list GET to reach the fake backend',
        timeout: const Duration(seconds: 20),
      );
      // Drain the tab transition — mid-fade both tabs' bars are mounted.
      await AppHarness.settle(tester);
      expect(find.byType(OwnerOwnProfileScreen), findsNothing);
      expect(find.byKey(ServicesListScreen.backKey), findsOneWidget);
      expect(find.byType(VelvetBottomNavBar), findsOneWidget);

      // ── 2. Empty state → «Додати послугу» → setup ───────────────────────
      final Finder emptyCta = find.byKey(const Key('btn-create-service-empty'));
      await AppHarness.pumpUntilFound(
        tester,
        emptyCta,
        timeout: const Duration(seconds: 20),
      );
      await _tapWhenReady(tester, emptyCta);
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(ServiceSetupScreen),
        timeout: const Duration(seconds: 20),
      );
      // A push grafted INSIDE the owner ShellRoute (the setup leaf needs its
      // service-target scope) — read through the nested-push resolver.
      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.ownerMasterServiceSetup,
      );

      final Finder nailsChip = find.byKey(const ValueKey<String>('cat_NAILS'));
      await AppHarness.pumpUntilFound(
        tester,
        nailsChip,
        timeout: const Duration(seconds: 20),
      );
      await _tapWhenReady(tester, nailsChip);

      final Finder freeRow = find.byKey(const Key('setup_row_$_kFreeTypeId'));
      await AppHarness.pumpUntilFound(
        tester,
        freeRow,
        timeout: const Duration(seconds: 20),
      );
      await _tapWhenReady(
        tester,
        find.byKey(const Key('setup_row_toggle_$_kFreeTypeId')),
      );

      final Finder durationField = find.descendant(
        of: freeRow,
        matching: find.byKey(const Key('service-setup-duration')),
      );
      final Finder priceField = find.descendant(
        of: freeRow,
        matching: find.byKey(const Key('pricing-fixed-amount')),
      );
      await AppHarness.pumpUntilFound(
        tester,
        priceField,
        timeout: const Duration(seconds: 20),
      );
      await tester.enterText(durationField, '45');
      await tester.pump();
      await tester.enterText(priceField, '350');
      await tester.pump();

      await _tapWhenReady(tester, find.byKey(const Key('btn-setup-save')));

      // ── 3. The POST lands on the owner's OWN row ────────────────────────
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.ownRowBulkCreateCalls >= 1,
        description:
            'the own-row bulk POST to reach the fake backend — if it never '
            'does, the save was blocked client-side or went elsewhere',
        timeout: const Duration(seconds: 20),
      );
      expect(
        fb.lastOwnRowBulkPath,
        '/api/v1/salons/$_kSalonA/masters/$_kOwnerMasterRowId/services/bulk',
      );
      expect(
        fb.bulkCreateCalls,
        0,
        reason:
            'the INDEPENDENT_MASTER /masters/me bulk endpoint must never '
            'fire for the owner\'s master-mode save',
      );

      // ── 4. Back on the list WITH the new card ───────────────────────────
      await AppHarness.pumpUntilGone(
        tester,
        find.byType(ServiceSetupScreen),
        timeout: const Duration(seconds: 20),
      );
      AppHarness.expectLocation(router, RouteNames.ownerMasterServices);
      final Finder nailsSection = find.byKey(
        const Key('category_section_NAILS'),
      );
      await AppHarness.pumpUntilFound(
        tester,
        nailsSection,
        timeout: const Duration(seconds: 20),
      );
      final Finder newCard = find.byKey(
        const Key('service_card_own-row-assign-bulk-1'),
      );
      if (newCard.evaluate().isEmpty) {
        await _tapWhenReady(tester, nailsSection);
      }
      await AppHarness.pumpUntilFound(
        tester,
        newCard,
        timeout: const Duration(seconds: 20),
      );
      expect(newCard, findsOneWidget);
      expect(find.byKey(const Key('btn-create-service')), findsOneWidget);
    });
  });

  testWidgets('SALON_OWNER: edit then delete an OWN-row service — the band '
      'PATCH and the unassign DELETE both hit '
      '/salons/{primary}/masters/{ownerRow}/services/{defId}; no '
      'INDEPENDENT_MASTER write fires', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb =
          FakeBackend(
              masterRowId: _kOwnerMasterRowId,
              masterSalonId: _kSalonA,
              wireOwnRowServices: true,
              ownRowServicesSeed: <Map<String, dynamic>>[_seededOwnRow()],
            )
            ..currentRole = UserRole.salonOwner
            ..hasMasterProfile = true;
      const String ownRowPath =
          '/api/v1/salons/$_kSalonA/masters/$_kOwnerMasterRowId/services/'
          '$_kOwnDefId';
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        storage: FakeSecureStorage(),
      );
      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.settle(tester);
      await _enterMasterMode(tester, router);

      // ── 1. «Послуги» → the seeded card → edit form ───────────────────────
      await _tapWhenReady(tester, find.byKey(const Key('master-nav-tile-0')));
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(ServicesListScreen),
        timeout: const Duration(seconds: 20),
      );
      await AppHarness.settle(tester);
      final Finder card = find.byKey(const Key('service_card_$_kOwnAssignId'));
      await _revealCard(tester, card);
      await _tapWhenReady(tester, card);
      final Finder editForm = find.byKey(
        const Key('service-edit-form-$_kOwnAssignId'),
      );
      await AppHarness.pumpUntilFound(
        tester,
        editForm,
        timeout: const Duration(seconds: 20),
      );

      // ── 2. 400 → 550 ₴, save → band PATCH on the OWN row ────────────────
      final Finder priceField = find.descendant(
        of: find.byKey(const Key('pricing-fixed-amount')),
        matching: find.byType(TextField),
      );
      await AppHarness.pumpUntilFound(
        tester,
        priceField,
        timeout: const Duration(seconds: 20),
      );
      await tester.ensureVisible(priceField);
      await tester.pump();
      await tester.enterText(priceField, '550');
      await tester.pump();
      await _tapWhenReady(tester, find.byKey(const Key('btn-submit-service')));
      await AppHarness.pumpUntilGone(
        tester,
        editForm,
        timeout: const Duration(seconds: 20),
      );

      expect(
        fb.ownRowBandPatchCalls,
        1,
        reason: 'the price edit must go to the owner\'s OWN row band',
      );
      expect(fb.lastOwnRowBandPatchPath, ownRowPath);
      expect(fb.lastOwnRowBandPatchBody?['price'], 550);
      expect(
        fb.patchServiceCalls,
        0,
        reason: 'the INDEPENDENT_MASTER /masters/me PATCH must never fire',
      );
      AppHarness.expectLocation(router, RouteNames.ownerMasterServices);

      // ── 3. Card again → delete → confirm → unassign DELETE on own row ───
      await _revealCard(tester, card);
      await _tapWhenReady(tester, card);
      await AppHarness.pumpUntilFound(
        tester,
        editForm,
        timeout: const Duration(seconds: 20),
      );
      await _tapWhenReady(tester, find.byKey(const Key('btn-delete-service')));
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('delete-service-dialog')),
        timeout: const Duration(seconds: 20),
      );
      await _tapWhenReady(
        tester,
        find.byKey(const Key('btn-confirm-delete-service')),
      );
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.ownRowUnassignCalls >= 1,
        description:
            'the own-row unassign DELETE to reach the fake backend — if it '
            'never does, the delete went to another endpoint',
        timeout: const Duration(seconds: 20),
      );
      expect(fb.ownRowUnassignCalls, 1);
      expect(fb.lastOwnRowUnassignPath, ownRowPath);
      expect(
        fb.deleteServiceCalls,
        0,
        reason:
            'the INDEPENDENT_MASTER DELETE /services/{defId} (deactivate the '
            'whole definition) must never fire for the owner\'s own row',
      );

      // ── 4. Back on the list, card gone, empty state ─────────────────────
      await AppHarness.pumpUntilGone(
        tester,
        editForm,
        timeout: const Duration(seconds: 20),
      );
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('btn-create-service-empty')),
        timeout: const Duration(seconds: 20),
      );
      expect(card, findsNothing);
      AppHarness.expectLocation(router, RouteNames.ownerMasterServices);
    });
  });
  testWidgets('SALON_OWNER: «Графік» tile → own-row empty schedule → weekly '
      'editor (system back returns to «Графік») → Monday 10:00–18:00 → save '
      '→ calendar shows Monday working; the POST targets '
      '/masters/{ownerRow}/weekly-schedules only', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb =
          FakeBackend(
              masterRowId: _kOwnerMasterRowId,
              masterSalonId: _kSalonA,
              wireOwnRowSchedule: true,
            )
            ..currentRole = UserRole.salonOwner
            ..hasMasterProfile = true;
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        storage: FakeSecureStorage(),
      );
      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.settle(tester);
      await _enterMasterMode(tester, router);

      // ── 1. Profile → «Графік» (tile 2) ──────────────────────────────────
      await _tapWhenReady(tester, find.byKey(const Key('master-nav-tile-2')));
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(MasterScheduleScreen),
        timeout: const Duration(seconds: 20),
      );
      AppHarness.expectLocation(router, RouteNames.ownerMasterSchedule);
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.ownRowScheduleGetCalls >= 1,
        description: 'the own-row weekly GET to reach the fake backend',
        timeout: const Duration(seconds: 20),
      );
      await AppHarness.settle(tester);
      expect(find.byType(OwnerOwnProfileScreen), findsNothing);
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(MasterScheduleScreen)),
      );
      expect(
        find.descendant(
          of: find.byType(VelvetTopBar),
          matching: find.text(l10n.ownerMasterModeBack),
        ),
        findsOneWidget,
        reason: 'the «‹ Салон» pill is the schedule tab\'s top-left exit',
      );
      final VelvetBottomNavBar bar = tester.widget<VelvetBottomNavBar>(
        find.byType(VelvetBottomNavBar),
      );
      expect(bar.activeIndex, 2);
      expect(bar.scheduleRoute, RouteNames.ownerMasterSchedule);
      expect(bar.servicesRoute, RouteNames.ownerMasterServices);
      expect(bar.profileRoute, RouteNames.ownerMasterProfile);

      // ── 2. Empty + editable → «Додати години» → weekly editor ───────────
      final Finder addHours = find.byKey(const Key('no-schedule-add-hours'));
      await AppHarness.pumpUntilFound(
        tester,
        addHours,
        timeout: const Duration(seconds: 20),
      );
      expect(find.byKey(const Key('schedule-weekly-card')), findsNothing);
      await _tapWhenReady(tester, addHours);
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(WeeklyTemplateEditorScreen),
        timeout: const Duration(seconds: 20),
      );

      // SYSTEM BACK from the editor pops to «Графік» — never the salon.
      await tester.binding.handlePopRoute();
      await AppHarness.pumpUntilGone(
        tester,
        find.byType(WeeklyTemplateEditorScreen),
        timeout: const Duration(seconds: 20),
      );
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.ownerMasterSchedule);
      expect(find.byType(MasterScheduleScreen), findsOneWidget);
      expect(find.byType(SalonShellScreen), findsNothing);

      await _tapWhenReady(tester, addHours);
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(WeeklyTemplateEditorScreen),
        timeout: const Duration(seconds: 20),
      );
      await AppHarness.settle(tester);

      // ── 3. Monday ON (seeds 09:00–18:00) → start +1 h = 10:00 ───────────
      await _tapWhenReady(tester, find.byKey(const Key('weekly-toggle-1')));
      await AppHarness.settle(tester);
      final Finder mondayStart = find.byKey(
        const Key('weekly-day-1-work-start'),
      );
      await _tapWhenReady(tester, mondayStart);
      await AppHarness.settle(tester);
      final Finder wheels = find.byType(ListWheelScrollView);
      expect(wheels, findsNWidgets(2), reason: 'hours + minutes wheels');
      // One wheel item extent (46 px, the picker's fixed extent) = one hour.
      await tester.drag(wheels.at(0), const Offset(0, -46));
      await AppHarness.settle(tester);
      await _tapWhenReady(
        tester,
        find.byKey(const Key('btn-velvet-time-picker-confirm')),
      );
      await AppHarness.settle(tester);
      expect(
        tester
            .widget<Text>(
              find
                  .descendant(of: mondayStart, matching: find.byType(Text))
                  .first,
            )
            .data,
        '10:00',
      );

      // First create REQUIRES a validity window (staged, not persisted).
      final Finder windowCard = find.byKey(
        const Key('weekly-active-window-card'),
      );
      await tester.scrollUntilVisible(
        windowCard,
        -120,
        scrollable: find.byType(Scrollable).first,
      );
      await AppHarness.settle(tester);
      await _tapWhenReady(tester, windowCard);
      await AppHarness.settle(tester);
      await _tapWhenReady(tester, find.byKey(const Key('preset-this-month')));
      await AppHarness.settle(tester);
      await _tapWhenReady(tester, find.byKey(const Key('btn-apply-schedule')));
      await AppHarness.settle(tester);
      expect(fb.ownRowSchedulePostCalls, 0, reason: 'staging never persists');

      // ── 4. Save → the POST lands on the OWN row ─────────────────────────
      await _tapWhenReady(
        tester,
        find.byKey(const Key('btn-save-weekly-template')),
      );
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.ownRowSchedulePostCalls >= 1,
        description:
            'the own-row weekly POST to reach the fake backend — if it never '
            'does, the save was blocked client-side or went elsewhere',
        timeout: const Duration(seconds: 20),
      );
      expect(fb.ownRowSchedulePostCalls, 1);
      expect(
        fb.lastOwnRowSchedulePostPath,
        '/api/v1/masters/$_kOwnerMasterRowId/weekly-schedules',
      );
      final Map<String, dynamic> monday =
          (fb.lastOwnRowWeeklyDays ?? <dynamic>[])
              .cast<Map<String, dynamic>>()
              .firstWhere((Map<String, dynamic> d) => d['dayOfWeek'] == 1);
      final List<dynamic> mondayIntervals =
          monday['intervals'] as List<dynamic>;
      expect(mondayIntervals, hasLength(1));
      expect(
        (mondayIntervals.single as Map<String, dynamic>)['startTime'],
        startsWith('10:00'),
      );
      expect(
        (mondayIntervals.single as Map<String, dynamic>)['endTime'],
        startsWith('18:00'),
      );
      expect(
        fb.postScheduleCalls + fb.putScheduleCalls + fb.getScheduleCalls,
        0,
        reason:
            'no hard-wired schedule route (/masters/me, user-master-1, …) '
            'may be touched by the owner\'s own-row schedule',
      );

      // ── 5. Back on «Графік» with Monday WORKING ─────────────────────────
      await AppHarness.pumpUntilGone(
        tester,
        find.byType(WeeklyTemplateEditorScreen),
        timeout: const Duration(seconds: 20),
      );
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.ownerMasterSchedule);
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('schedule-weekly-card')),
        timeout: const Duration(seconds: 20),
      );
      // The strip is Monday-first (cell 0 = Monday of the visible week).
      // Indexed by POSITION, not by day-of-month: `MasterScheduleScreen` mounts
      // without an injected clock here (production mount), so the visible week
      // follows the host clock, while the editor's window preset follows the
      // app's `kFixedNow` — the fake's derived effective schedule ignores the
      // validity window, so the weekday verdict is clock-independent.
      final List<WeekStripDay> week = tester
          .widgetList<WeekStripDay>(find.byType(WeekStripDay))
          .toList();
      expect(week, hasLength(7));
      expect(week[0].working, isTrue, reason: 'Monday now works');
      for (int i = 1; i < 7; i++) {
        expect(week[i].working, isFalse, reason: 'weekday ${i + 1} stays off');
      }
    });
  });
}
