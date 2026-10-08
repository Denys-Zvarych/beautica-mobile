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
// master mode, and both exits from «Профіль» — the «‹ Салон» pill AND the
// system back — must land back on B. Decision 2026-10-08: only «Профіль»
// carries «‹ Салон»; «Послуги»/«Графік»/«Записи» show the plain arrow, and
// their arrow AND system back return to the previous page (nothing to pop →
// the master-mode «Профіль»), never straight to the salon. A `go(mySalons)` or a first-salon fallback would land
// on A or the hub and fail.
//
// Phase 384 (24.1g) — master mode is entered through the REAL UI entry in
// every flow below: the salon shell's «Профіль» nav tile (`salon-nav-tile-3`),
// which for an OWNER leaves the shell for `/owner/master/profile`
// (`_enterMasterMode`). The dedicated 384 flow tours all four master-mode
// tiles from salon B and returns to B with both «‹ Салон» and system back
// (via «Профіль» — a non-profile tab's arrow/system back lands there first),
// while «Послуги» still targets the PRIMARY salon's (A's) own master row.
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
// Phase 383 (24.1f) — the «Записи» tab: profile → tile 1 → ONLY the owner's
// own-row booking (the FakeBackend's dataset holds an owner-row booking AND
// another master's, and answers `GET /bookings/me?asMaster=true` with the
// owner-row one only) → day change + filter keep `asMaster=true` → tap →
// `/salon/bookings/:id` detail → back → «Архів» (own-row only) → back →
// the plain arrow → master-mode «Профіль» → «‹ Салон» lands on the salon
// shell. Every `/bookings/me` and
// `/booked-days` read is pinned to `asMaster=true`.
//
// Phase 383 (decision 2026-10-07) — «Записи» (+): the independent master's
// walk-in chain mounted under `/owner/master/bookings/new` (guest → own-row
// service → slot → confirm). The POST must land on `/masters/{ownerRow}/
// bookings` (the FakeBackend route is keyed on the owner row), «Готово»
// returns to the owner's «Записи» where the booking is listed, and after
// arrow → «Профіль» → «‹ Салон» the same booking is on the salon «Записи» board
// (`mirrorWalkInToSalonBoard`, the backend stamping the owner's salon_id).
//
// NO PATROL FLOW: no OS dialog, permission, notification or WebView is
// involved; system back is driven through `WidgetsBinding.handlePopRoute`,
// the same entry point the Android back / predictive-back dispatch calls.

import 'dart:convert';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/slot_chip.dart';
import 'package:beautica_mobile/features/booking/presentation/walk_in_service_step_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/walk_in_guest_step_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/slot_picker_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_create_booking_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_success_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_archive_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/features/salon/application/salon_shell_provider.dart';
import 'package:beautica_mobile/features/salon/presentation/my_salons_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/owner_own_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_management_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/features/schedule/presentation/master_schedule_screen.dart';
import 'package:beautica_mobile/features/schedule/presentation/weekly_template_editor_screen.dart';
import 'package:beautica_mobile/features/schedule/presentation/widgets/schedule_widgets.dart'
    hide SlotChip;
import 'package:beautica_mobile/features/services/presentation/service_setup_screen.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/salon_bottom_nav.dart';
import 'package:beautica_mobile/shared/widgets/velvet_bottom_nav_bar.dart';
import 'package:beautica_mobile/shared/widgets/velvet_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/fakes/fake_secure_storage.dart';
import '../test/helpers/overflow_guard.dart';
import '../test/helpers/pump_app.dart';
import 'support/app_harness.dart';
import 'support/fake_backend.dart' show kWalkInBookingId;

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

/// Phase 384 — enters master mode the way the owner does: from the salon
/// shell they are standing in, tap «Профіль» (`salon-nav-tile-3`). Asserts
/// the mount: own profile, the independent-master nav and the «‹ Салон» pill.
Future<void> _enterMasterMode(WidgetTester tester, GoRouter router) async {
  expect(
    find.byType(SalonShellScreen),
    findsOneWidget,
    reason: 'the real entry starts from the salon shell',
  );
  await _tapWhenReady(tester, find.byKey(const Key('salon-nav-tile-3')));
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
/// The app's UA strings, read off the mounted master-mode nav bar.
AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(VelvetBottomNavBar)));

void _expectBackOnSalonB(GoRouter router) {
  AppHarness.expectLocation(router, RouteNames.salonShell(_kSalonB));
  expect(find.byType(SalonShellScreen), findsOneWidget);
  expect(find.byType(VelvetBottomNavBar), findsNothing);
  expect(find.byKey(_masterModeBack), findsNothing);
}

/// Phase 384 — the salon shell's bottom-nav highlight (a NAV index).
int _salonNavIndex(WidgetTester tester) => tester
    .widget<SalonBottomNav>(find.byKey(const Key('salon-shell-bottom-nav')))
    .currentIndex;

/// Phase 384 — taps master-mode tile [index] and asserts it lands on [path]
/// with that tile active (the route-builder's `VelvetBottomNavBar`).
Future<void> _tapMasterTile(
  WidgetTester tester,
  GoRouter router,
  int index,
  String path,
) async {
  await _tapWhenReady(tester, find.byKey(Key('master-nav-tile-$index')));
  await AppHarness.pumpUntilCondition(
    tester,
    () => AppHarness.location(router) == path,
    description: 'master-mode tile $index to land on $path',
    timeout: const Duration(seconds: 20),
  );
  // Drain the tab transition — mid-fade both tabs' bars are mounted.
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, path);
  expect(
    tester
        .widget<VelvetBottomNavBar>(find.byType(VelvetBottomNavBar))
        .activeIndex,
    index,
    reason: 'tile $index must be the active one on $path',
  );
  expect(find.byType(SalonShellScreen), findsNothing);
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

  testWidgets('Phase 384 — SALON_OWNER in salon B: shell «Профіль» → master '
      'mode; every tile lands on /owner/master/* with that tile active; '
      '«‹ Салон» and SYSTEM BACK from «Профіль» both return to B, while the '
      'arrow / SYSTEM BACK on «Послуги»/«Графік» land on «Профіль»; «Послуги» '
      'still targets the PRIMARY salon\'s own master row', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb =
          FakeBackend(
              masterRowId: _kOwnerMasterRowId,
              masterSalonId: _kSalonA,
              wireOwnRowServices: true,
              wireOwnRowSchedule: true,
            )
            ..currentRole = UserRole.salonOwner
            ..hasMasterProfile = true;
      _seedSalonB(fb);
      final FakeSecureStorage storage = FakeSecureStorage();
      final GoRouter router = await _enterSalonB(tester, fb, storage);

      // ── 1. Salon B shell → «Профіль» (the real entry) ───────────────────
      await _enterMasterMode(tester, router);
      expect(
        tester
            .widget<VelvetBottomNavBar>(find.byType(VelvetBottomNavBar))
            .activeIndex,
        3,
        reason: 'master mode opens on its «Профіль» tile',
      );

      // ── 2. Every tile → its /owner/master/* route, tile active ──────────
      await _tapMasterTile(tester, router, 0, RouteNames.ownerMasterServices);
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.ownRowServicesGetCalls >= 1,
        description:
            'the «Послуги» list GET to hit the PRIMARY salon (A) own-row '
            'route even though the owner entered from salon B',
        timeout: const Duration(seconds: 20),
      );
      expect(find.byType(ServicesListScreen), findsOneWidget);

      await _tapMasterTile(tester, router, 1, RouteNames.ownerMasterBookings);
      expect(find.byType(MasterBookingsScreen), findsOneWidget);

      await _tapMasterTile(tester, router, 2, RouteNames.ownerMasterSchedule);
      expect(find.byType(MasterScheduleScreen), findsOneWidget);

      await _tapMasterTile(tester, router, 3, RouteNames.ownerMasterProfile);
      expect(find.byType(OwnerOwnProfileScreen), findsOneWidget);

      // ── 3. «‹ Салон» → salon B (last-visited), on «Салон» ──────────────
      await AppHarness.tapVisible(tester, find.byKey(_masterModeBack));
      await AppHarness.settle(tester);
      _expectBackOnSalonB(router);
      expect(
        _salonNavIndex(tester),
        0,
        reason:
            'a fresh shell visit opens on «Салон» — the owner\'s «Профіль» '
            'tap never wrote nav 3 into salonShellProvider',
      );
      expect(await _storedSalonId(storage), _kSalonB);

      // ── 4. Re-enter; «Графік»'s plain ARROW → master-mode «Профіль» ─────
      // Decision 2026-10-08 — no «Салон» label off the profile tab.
      await _enterMasterMode(tester, router);
      await _tapMasterTile(tester, router, 2, RouteNames.ownerMasterSchedule);
      expect(find.text(_l10n(tester).ownerMasterModeBack), findsNothing);
      await AppHarness.tapVisible(
        tester,
        find.byKey(MasterScheduleScreen.backKey),
      );
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.ownerMasterProfile);
      expect(find.byType(OwnerOwnProfileScreen), findsOneWidget);
      expect(find.byType(SalonShellScreen), findsNothing);

      // ── 5. SYSTEM BACK on «Послуги» → «Профіль», NOT the salon ──────────
      await _tapMasterTile(tester, router, 0, RouteNames.ownerMasterServices);
      expect(find.text(_l10n(tester).ownerMasterModeBack), findsNothing);
      await tester.binding.handlePopRoute();
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.ownerMasterProfile);
      expect(find.byType(SalonShellScreen), findsNothing);

      // ── 6. SYSTEM BACK on «Графік» → «Профіль»; again → salon B ─────────
      await _tapMasterTile(tester, router, 2, RouteNames.ownerMasterSchedule);
      await tester.binding.handlePopRoute();
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.ownerMasterProfile);
      await tester.binding.handlePopRoute();
      await AppHarness.settle(tester);
      _expectBackOnSalonB(router);
      expect(_salonNavIndex(tester), 0);
    });
  });

  testWidgets('Phase 384 (mobile-qa) — owner parked on «Команда» → «Профіль» '
      '→ «‹ Салон»: the shell re-opens on «Салон» (nav 0, «Про салон» '
      'sub-tab), NOT on the tab the owner left from', (tester) async {
    // Product-accepted landing (2026-10-07): a return from master mode is a
    // FRESH shell visit — `salonShellProvider` / `salonManageTabProvider` are
    // autoDispose and die with the shell route. The section-3 assertion of
    // the test above starts from nav 0, so it cannot tell "reset to 0" from
    // "left untouched"; parking on «Команда» first makes it load-bearing.
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.salonOwner
        ..hasMasterProfile = true;
      _seedSalonB(fb);
      final FakeSecureStorage storage = FakeSecureStorage();
      final GoRouter router = await _enterSalonB(tester, fb, storage);

      await _tapWhenReady(
        tester,
        find.byKey(const Key('salon-nav-tile-$kSalonTeamNavTab')),
      );
      await AppHarness.settle(tester);
      expect(_salonNavIndex(tester), kSalonTeamNavTab);

      await _enterMasterMode(tester, router);
      await AppHarness.tapVisible(tester, find.byKey(_masterModeBack));
      await AppHarness.settle(tester);

      _expectBackOnSalonB(router);
      expect(
        _salonNavIndex(tester),
        0,
        reason:
            'the shell re-opens on «Салон», not on «Команда» where the '
            'owner left from (salon_shell_screen.dart:18-21 / :388-391 '
            'comments claim otherwise — the accepted behaviour is nav 0)',
      );
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(SalonShellScreen)),
      );
      expect(
        container.read(salonManageTabProvider(_kSalonB)),
        0,
        reason:
            'nav 0 must pair with the «Про салон» sub-tab — a stale «Команда» '
            'sub-tab under a «Салон» highlight is the TAB SYNC desync',
      );
    });
  });

  // Phase 384 perf MEDIUM — `salonManagementProfileProvider`'s timed
  // keepAlive (mirroring `publicSalonProfileProvider`) keeps the salon
  // profile cached across the master-mode trip, so «‹ Салон» neither
  // refetches `GET /salons/{id}` + `GET /salons/{id}/staff` nor paints a
  // CircularProgressIndicator frame.
  testWidgets(
    'SPEC (Phase 384 perf MEDIUM) — «‹ Салон» within the keepAlive window '
    'does NOT refetch the salon profile / staff and paints NO loading frame',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final FakeBackend fb = FakeBackend()
          ..currentRole = UserRole.salonOwner
          ..hasMasterProfile = true;
        // Salon A (`kOwnerSalonId`): the only owner salon whose
        // `GET /salons/{id}` + `/staff` routes the fake backend registers
        // and counts per id.
        final GoRouter router = await AppHarness.boot(
          tester,
          fb,
          storage: FakeSecureStorage(),
        );
        await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
        await AppHarness.settle(tester);
        AppHarness.expectLocation(router, RouteNames.salonShell(_kSalonA));
        expect(
          find.descendant(
            of: find.byType(SalonManagementProfileScreen),
            matching: find.byType(ErrorState),
          ),
          findsNothing,
          reason: 'precondition: salon A\'s management profile loaded',
        );
        expect(
          fb.getSalonStaffCallsById[_kSalonA] ?? 0,
          greaterThanOrEqualTo(1),
          reason: 'precondition: the shell loaded salon A\'s roster',
        );

        await _enterMasterMode(tester, router);
        // Snapshot AFTER master mode settled: whatever master mode itself
        // reads is already counted, so any increment below is the return.
        final int salonGetsBefore = fb.getSalonByIdCalls;
        final int staffGetsBefore = fb.getSalonStaffCallsById[_kSalonA] ?? 0;

        await tester.ensureVisible(find.byKey(_masterModeBack));
        await tester.tap(find.byKey(_masterModeBack));
        bool sawLoadingFrame = false;
        for (int frame = 0; frame < 120; frame++) {
          // fixed-wait-ok: frame-by-frame scan of the return transition — a
          // settle would skip the one loading frame this test exists to see.
          await tester.pump(const Duration(milliseconds: 16));
          final Finder spinner = find.descendant(
            of: find.byType(SalonManagementProfileScreen),
            matching: find.byType(CircularProgressIndicator),
          );
          if (spinner.evaluate().isNotEmpty) sawLoadingFrame = true;
        }
        await AppHarness.settle(tester);

        AppHarness.expectLocation(router, RouteNames.salonShell(_kSalonA));
        expect(find.byType(SalonShellScreen), findsOneWidget);
        expect(
          sawLoadingFrame,
          isFalse,
          reason: 'the cached salon profile must paint on the first frame',
        );
        expect(
          fb.getSalonByIdCalls,
          salonGetsBefore,
          reason: 'no GET /salons/{id} refetch inside the keepAlive window',
        );
        expect(
          fb.getSalonStaffCallsById[_kSalonA] ?? 0,
          staffGetsBefore,
          reason: 'no GET /salons/{id}/staff refetch inside the window',
        );
      });
    },
  );

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
      // Decision 2026-10-08 — the schedule tab shows the plain arrow; the
      // «‹ Салон» pill lives on «Профіль» only.
      expect(find.byKey(MasterScheduleScreen.backKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(VelvetTopBar),
          matching: find.text(l10n.ownerMasterModeBack),
        ),
        findsNothing,
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

  testWidgets('SALON_OWNER: «Записи» tile → ONLY the own-row booking (never '
      'another master\'s); day + filter changes keep asMaster=true; detail '
      'on /salon/bookings/:id and back; «Архів» own-only and back; «‹ Салон» '
      '→ salon shell', (tester) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb =
          FakeBackend(
              masterRowId: _kOwnerMasterRowId,
              masterSalonId: _kSalonA,
              wireOwnRowSchedule: true,
            )
            ..currentRole = UserRole.salonOwner
            ..hasMasterProfile = true;
      // The owner row works every day, so no «no working hours» state hides
      // the timeline whatever weekday kFixedNow lands on.
      fb.ownRowWeeklySchedule.add(<String, dynamic>{
        'id': 'own-weekly-1',
        'validFrom': '2026-01-01',
        'validTo': null,
        'days': <Map<String, dynamic>>[
          for (int dow = 1; dow <= 7; dow++)
            <String, dynamic>{
              'dayOfWeek': dow,
              'intervals': <Map<String, dynamic>>[
                <String, dynamic>{'startTime': '08:00', 'endTime': '20:00'},
              ],
            },
        ],
      });
      // Kyiv "today" under the injected kFixedNow (12:00Z) — both rows on it
      // and both already ended (so both are also archive HISTORY).
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        <String, dynamic>{
          ...fb.datasetBookingRow(
            id: 'booking-1',
            status: 'CONFIRMED',
            startsAt: DateTime.utc(
              kFixedNow.year,
              kFixedNow.month,
              kFixedNow.day,
              7,
            ),
          ),
          'masterId': _kOwnerMasterRowId,
          'masterType': 'SALON_OWNER',
        },
        <String, dynamic>{
          ...fb.datasetBookingRow(
            id: 'booking-other-master',
            status: 'CONFIRMED',
            startsAt: DateTime.utc(
              kFixedNow.year,
              kFixedNow.month,
              kFixedNow.day,
              9,
            ),
          ),
          'masterId': 'master-other-1',
          'masterType': 'SALON_MASTER',
        },
      ]);
      fb.ownerMasterRowBookingIds = <String>{'booking-1'};

      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        storage: FakeSecureStorage(),
      );
      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.settle(tester);
      await _enterMasterMode(tester, router);

      // ── 1. Profile → «Записи» (tile 1) ──────────────────────────────────
      // Only reads made FROM master mode are pinned below.
      fb.myBookingsAsMasterFlags.clear();
      fb.bookedDaysAsMasterFlags.clear();
      await _tapWhenReady(tester, find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(MasterBookingsScreen),
        timeout: const Duration(seconds: 20),
      );
      AppHarness.expectLocation(router, RouteNames.ownerMasterBookings);
      final Finder ownCard = find.byKey(
        const Key('master-booking-card-booking-1'),
      );
      await AppHarness.pumpUntilFound(
        tester,
        ownCard,
        timeout: const Duration(seconds: 20),
      );
      await AppHarness.settle(tester);
      expect(
        find.byKey(const Key('master-booking-card-booking-other-master')),
        findsNothing,
        reason: 'another master\'s booking must never reach master mode',
      );
      final VelvetBottomNavBar bar = tester.widget<VelvetBottomNavBar>(
        find.byType(VelvetBottomNavBar),
      );
      expect(bar.activeIndex, 1);
      expect(bar.bookingsRoute, RouteNames.ownerMasterBookings);
      expect(bar.servicesRoute, RouteNames.ownerMasterServices);
      expect(bar.scheduleRoute, RouteNames.ownerMasterSchedule);
      expect(bar.profileRoute, RouteNames.ownerMasterProfile);
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(MasterBookingsScreen)),
      );
      final Finder back = find.byKey(const Key('bookings-discovery-back'));
      // Decision 2026-10-08 — plain arrow, no «Салон» label off «Профіль».
      expect(back, findsOneWidget);
      expect(
        find.descendant(
          of: back,
          matching: find.text(l10n.ownerMasterModeBack),
        ),
        findsNothing,
      );

      // ── 3. Tap → owner-admitted /salon/bookings/:id detail → back ───────
      await _tapWhenReady(tester, ownCard);
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(BookingDetailScreen),
        timeout: const Duration(seconds: 20),
      );
      await AppHarness.settle(tester);
      expect(
        router.routerDelegate.currentConfiguration.last.matchedLocation,
        RouteNames.salonStaffBookingDetail('booking-1'),
      );
      // Phase 383 QA — the list's detail push carries the salon id on
      // `extra`, so a write from detail also drops the salon board dots.
      // MUTATION: removed `detailExtra: salonId` from the owner mount →
      // `salonId` was null, this assertion went red. Restored.
      expect(
        tester
            .widget<BookingDetailScreen>(find.byType(BookingDetailScreen))
            .salonId,
        _kSalonA,
      );
      await tester.binding.handlePopRoute();
      await AppHarness.pumpUntilGone(
        tester,
        find.byType(BookingDetailScreen),
        timeout: const Duration(seconds: 20),
      );
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.ownerMasterBookings);
      expect(ownCard, findsOneWidget);

      // ── 4. «Архів» — own-row history only → back ───────────────────────
      await _tapWhenReady(
        tester,
        find.byKey(const Key('master-bookings-open-archive')),
      );
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(MasterArchiveScreen),
        timeout: const Duration(seconds: 20),
      );
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('master-booking-card-booking-1')),
        timeout: const Duration(seconds: 20),
      );
      await AppHarness.settle(tester);
      expect(
        router.routerDelegate.currentConfiguration.last.matchedLocation,
        RouteNames.ownerMasterBookingsArchive,
      );
      expect(
        find.byKey(const Key('master-booking-card-booking-other-master')),
        findsNothing,
        reason: 'the owner archive is own-row only',
      );
      await _tapWhenReady(tester, find.byKey(const Key('master-archive-back')));
      await AppHarness.pumpUntilGone(
        tester,
        find.byType(MasterArchiveScreen),
        timeout: const Duration(seconds: 20),
      );
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.ownerMasterBookings);

      // ── 4b. Day change + filter keep the own-row scope ───────────────────
      // The day before Kyiv "today" — kFixedNow is a Sunday, so it is on the
      // same visible Mon..Sun rail week.
      await _tapWhenReady(
        tester,
        find.byKey(dayChipKey(railDayAt(kyivToday(() => kFixedNow), -1))),
      );
      final int beforeDay = fb.getMyBookingsCalls;
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.getMyBookingsCalls > beforeDay,
        description: 'the rail tap to re-fetch the day (after its debounce)',
        timeout: const Duration(seconds: 20),
      );
      await AppHarness.settle(tester);
      await _tapWhenReady(
        tester,
        find.byKey(const Key('master-bookings-filter-button')),
      );
      await AppHarness.settle(tester);
      await _tapWhenReady(
        tester,
        find.byKey(const Key('master-bookings-filter-status-cancelled')),
      );
      await AppHarness.settle(tester);
      final int beforeFilter = fb.getMyBookingsCalls;
      await _tapWhenReady(
        tester,
        find.byKey(const Key('master-bookings-filter-apply')),
      );
      await AppHarness.pumpUntilCondition(
        tester,
        () => fb.getMyBookingsCalls > beforeFilter,
        description: 'the filter apply to re-fetch',
        timeout: const Duration(seconds: 20),
      );
      await AppHarness.settle(tester);
      // Every read in master mode was the own-row scope.
      expect(fb.myBookingsAsMasterFlags, isNotEmpty);
      expect(
        fb.myBookingsAsMasterFlags,
        everyElement(isTrue),
        reason: 'no GET /bookings/me may drop asMaster=true in master mode',
      );
      expect(fb.bookedDaysAsMasterFlags, isNotEmpty);
      expect(fb.bookedDaysAsMasterFlags, everyElement(isTrue));

      // ── 5. Arrow → master-mode «Профіль» → «‹ Салон» → salon shell ─────
      await _tapWhenReady(tester, back);
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.ownerMasterProfile);
      expect(find.byType(SalonShellScreen), findsNothing);
      await _tapWhenReady(tester, find.byKey(_masterModeBack));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.salonShell(_kSalonA));
      expect(find.byType(SalonShellScreen), findsOneWidget);
      expect(find.byType(MasterBookingsScreen), findsNothing);
    });
  });

  // Phase 383 QA (INFO security/correctness) — FAILING-FIRST spec. The
  // owner «Записи» list pushes `/salon/bookings/:id` with `extra: salonId`
  // (pinned above), but `/owner/master/bookings/archive` builds
  // `MasterArchiveScreen` whose `_openDetail` pushes with NO `extra` — so a
  // decline/complete from a detail opened via «Архів» never drops the salon
  // board's dots / day lists. Observed RED before the fix (salonId == null).
  testWidgets(
    'SALON_OWNER: «Архів» → detail carries the owner salon id (same contract '
    'as the «Записи» list push)',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final FakeBackend fb =
            FakeBackend(
                masterRowId: _kOwnerMasterRowId,
                masterSalonId: _kSalonA,
                wireOwnRowSchedule: true,
              )
              ..currentRole = UserRole.salonOwner
              ..hasMasterProfile = true;
        fb.seedManyBookingsDataset(<Map<String, dynamic>>[
          <String, dynamic>{
            ...fb.datasetBookingRow(
              id: 'booking-1',
              status: 'CONFIRMED',
              startsAt: DateTime.utc(
                kFixedNow.year,
                kFixedNow.month,
                kFixedNow.day,
                7,
              ),
            ),
            'masterId': _kOwnerMasterRowId,
            'masterType': 'SALON_OWNER',
          },
        ]);
        fb.ownerMasterRowBookingIds = <String>{'booking-1'};

        final GoRouter router = await AppHarness.boot(
          tester,
          fb,
          storage: FakeSecureStorage(),
        );
        await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
        await AppHarness.settle(tester);
        await _enterMasterMode(tester, router);

        await _tapWhenReady(tester, find.byKey(const Key('master-nav-tile-1')));
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(MasterBookingsScreen),
          timeout: const Duration(seconds: 20),
        );
        await AppHarness.settle(tester);
        await _tapWhenReady(
          tester,
          find.byKey(const Key('master-bookings-open-archive')),
        );
        final Finder archiveCard = find.descendant(
          of: find.byType(MasterArchiveScreen),
          matching: find.byKey(const Key('master-booking-card-booking-1')),
        );
        await AppHarness.pumpUntilFound(
          tester,
          archiveCard,
          timeout: const Duration(seconds: 20),
        );
        await AppHarness.settle(tester);

        await _tapWhenReady(tester, archiveCard);
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(BookingDetailScreen),
          timeout: const Duration(seconds: 20),
        );
        await AppHarness.settle(tester);

        expect(
          router.routerDelegate.currentConfiguration.last.matchedLocation,
          RouteNames.salonStaffBookingDetail('booking-1'),
        );
        expect(
          tester
              .widget<BookingDetailScreen>(find.byType(BookingDetailScreen))
              .salonId,
          _kSalonA,
          reason:
              'a write from an archive-opened detail must drop the salon '
              'board dots too',
        );
      });
    },
  );

  // Phase 383 (decision 2026-10-07) — «Записи» (+) books the owner's OWN
  // master row through the independent master's walk-in chain (no master-pick
  // step), and the booking also lands on the salon «Записи» board.
  testWidgets('SALON_OWNER: «Записи» (+) → guest → own-row service → slot → '
      'confirm POSTs /masters/{ownerRow}/bookings; listed in own «Записи» '
      '(asMaster) and on the salon board after arrow → «Профіль» → «‹ Салон»', (
    tester,
  ) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb =
          FakeBackend(
              masterRowId: _kOwnerMasterRowId,
              masterSalonId: _kSalonA,
              wireOwnRowSchedule: true,
              wireOwnRowServices: true,
            )
            ..currentRole = UserRole.salonOwner
            ..hasMasterProfile = true
            ..mirrorWalkInToSalonBoard = true;
      fb.ownRowServices.add(_seededOwnRow());
      fb.ownRowWeeklySchedule.add(<String, dynamic>{
        'id': 'own-weekly-1',
        'validFrom': '2026-01-01',
        'validTo': null,
        'days': <Map<String, dynamic>>[
          for (int dow = 1; dow <= 7; dow++)
            <String, dynamic>{
              'dayOfWeek': dow,
              'intervals': <Map<String, dynamic>>[
                <String, dynamic>{'startTime': '08:00', 'endTime': '20:00'},
              ],
            },
        ],
      });
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[]);
      fb.ownerMasterRowBookingIds = <String>{};

      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        storage: FakeSecureStorage(),
      );
      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.settle(tester);
      await _enterMasterMode(tester, router);

      // ── 1. «Записи» → (+) ───────────────────────────────────────────────
      await _tapWhenReady(tester, find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(MasterBookingsScreen),
        timeout: const Duration(seconds: 20),
      );
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.ownerMasterBookings);
      final int independentServiceReads = fb.getServicesCalls;
      fb.myBookingsAsMasterFlags.clear();

      await _tapWhenReady(tester, find.byKey(const Key('master-bookings-add')));
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(WalkInGuestStepScreen),
        timeout: const Duration(seconds: 20),
      );
      await AppHarness.settle(tester);
      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.ownerMasterBookingNew,
      );
      expect(find.byType(SalonCreateBookingScreen), findsNothing);

      // ── 2. Guest → «Далі» ───────────────────────────────────────────────
      await tester.enterText(
        find.byKey(const Key('master-create-booking-first-name')),
        'Ірина',
      );
      await tester.enterText(
        find.byKey(const Key('master-create-booking-last-name')),
        'Шевченко',
      );
      await tester.enterText(
        find.byKey(const Key('master-create-booking-phone')),
        '0501234567',
      );
      await tester.pump();
      await _tapWhenReady(
        tester,
        find.byKey(const Key('master-create-booking-client-next')),
      );
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(WalkInServiceStepScreen),
        timeout: const Duration(seconds: 20),
      );
      await AppHarness.settle(tester);
      AppHarness.expectNestedPushLocation(
        router,
        RouteNames.ownerMasterBookingNewServices,
      );
      expect(
        find.byType(SalonCreateBookingScreen),
        findsNothing,
        reason: 'no master-pick step: the owner books their OWN row',
      );

      // ── 3. Own-row service → date → slot → confirm ──────────────────────
      final Finder serviceCard = find.byKey(
        const Key('mcb_service_card_$_kOwnAssignId'),
      );
      await AppHarness.pumpUntilFound(
        tester,
        serviceCard,
        timeout: const Duration(seconds: 20),
      );
      await _tapWhenReady(tester, serviceCard);
      await AppHarness.settle(tester);
      await _tapWhenReady(tester, find.byKey(const Key('booking-summary-cta')));
      await AppHarness.settle(tester);

      final DateTime today = kyivToday(() => kFixedNow);
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(Key('booking-calendar-day-${today.day}')),
        timeout: const Duration(seconds: 20),
      );
      await tester.tapCalendarDay(today.day);
      await AppHarness.settle(tester);
      await _tapWhenReady(tester, find.byKey(const Key('booking-summary-cta')));
      await AppHarness.settle(tester);
      expect(find.byType(SlotTimeScreen), findsOneWidget);
      final Finder availableChip = find
          .byWidgetPredicate((Widget w) => w is SlotChip && w.available)
          .first;
      await _tapWhenReady(tester, availableChip);
      await AppHarness.settle(tester);
      await _tapWhenReady(tester, find.byKey(const Key('booking-summary-cta')));
      await AppHarness.settle(tester);
      expect(find.byType(BookingConfirmScreen), findsOneWidget);

      await _tapWhenReady(
        tester,
        find.byKey(const Key('booking-confirm-submit-cta')),
      );
      await AppHarness.settle(tester);

      // The route is keyed on the OWNER ROW (`/masters/{ownerRow}/bookings`):
      // a POST to any other master id is an unmatched route and fails.
      expect(fb.createStaffBookingCalls, 1);
      expect(fb.lastStaffBookingRequestBody?['masterServiceIds'], <String>[
        _kOwnAssignId,
      ]);

      // ── 4. «Готово» → the owner's own «Записи», booking listed ──────────
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(BookingSuccessScreen),
        timeout: const Duration(seconds: 20),
      );
      await _tapWhenReady(
        tester,
        find.byKey(const Key('booking-success-home-cta')),
      );
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(MasterBookingsScreen),
        timeout: const Duration(seconds: 20),
      );
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.ownerMasterBookings);
      expect(find.byType(WalkInGuestStepScreen), findsNothing);
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('master-booking-card-$kWalkInBookingId')),
        timeout: const Duration(seconds: 20),
      );
      expect(fb.myBookingsAsMasterFlags, isNotEmpty);
      expect(fb.myBookingsAsMasterFlags, everyElement(isTrue));
      expect(
        fb.getServicesCalls,
        independentServiceReads,
        reason:
            'the owner chain must never list /independent-masters/me/'
            'services',
      );

      // ── 5. Arrow → «Профіль» → «‹ Салон» → salon «Записи» board ─────────
      await _tapWhenReady(
        tester,
        find.byKey(const Key('bookings-discovery-back')),
      );
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.ownerMasterProfile);
      await _tapWhenReady(tester, find.byKey(_masterModeBack));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.salonShell(_kSalonA));
      await _tapWhenReady(tester, find.byKey(const Key('salon-nav-tile-1')));
      await AppHarness.pumpUntilFound(
        tester,
        find.byType(SalonBookingsScreen),
        timeout: const Duration(seconds: 20),
      );
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const ValueKey<String>('timeline-card-$kWalkInBookingId')),
        timeout: const Duration(seconds: 20),
      );
      expect(fb.getSalonBookingsCalls, greaterThan(0));
    });
  });

  // Fit-whole-title: on the owner's master-mode «Мій профіль» the title must
  // never ellipsise beside the «‹ Салон» pill + bell/tune icons. At 320 dp the
  // pill collapses to the chevron (back key still present, label gone); at
  // 414 dp there is room and the label stays.
  testWidgets('SALON_OWNER: master-mode «Профіль» title is NOT truncated at '
      '320 dp (pill collapses to the chevron, still returns to the salon); at '
      '414 dp the «Салон» label shows', (tester) async {
    await mockNetworkImagesFor(() async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final FakeBackend fb = FakeBackend()
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

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(OwnerOwnProfileScreen)),
      );
      final String backLabel = l10n.ownerMasterModeBack;
      final Finder title = find.descendant(
        of: find.byType(VelvetTopBar),
        matching: find.text(l10n.ownerOwnProfileTitle),
      );
      Finder label() => find.descendant(
        of: find.byKey(_masterModeBack),
        matching: find.text(backLabel),
      );

      // ── 320 dp: whole title, chevron only ───────────────────────────────
      expect(title, findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
        isFalse,
        reason: 'the whole title must fit at 320 dp (fitWholeTitle)',
      );
      expect(label(), findsNothing, reason: 'pill collapsed to the chevron');
      expect(find.byKey(_masterModeBack), findsOneWidget);

      await AppHarness.tapVisible(tester, find.byKey(_masterModeBack));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.salonShell(_kSalonA));
      expect(find.byType(SalonShellScreen), findsOneWidget);

      // ── 414 dp: room for the label ──────────────────────────────────────
      tester.view.physicalSize = const Size(414, 800);
      await AppHarness.settle(tester);
      await _enterMasterMode(tester, router);
      expect(label(), findsOneWidget, reason: 'label shows when it clears');
      expect(
        tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
        isFalse,
      );
    });
  });
}
