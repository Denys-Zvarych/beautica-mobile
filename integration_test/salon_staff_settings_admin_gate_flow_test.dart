// Phase 308 LOW closure (mobile-qa, 2026-09-05) — the D3 owner-only gate on
// `StaffSettingsScreen`'s admin-remove row, proven for a GENUINELY
// AUTHENTICATED SALON_ADMIN session, not a provider override.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ----------------------------------------
// `test/features/salon/presentation/staff_settings_screen_test.dart` already
// pins `canManageStaff` at the WIDGET tier by overriding the `isOwner`
// selector directly. That proves the `if (canManageStaff)` branch itself is
// wired correctly, but it structurally CANNOT prove the gate holds for a
// real signed-in SALON_ADMIN: overriding the selector IS the thing under
// test, so a regression anywhere upstream of it — `authProvider`'s emitted
// role, `isSalonOwner`'s `Authenticated` cast,
// `auth_selectors.g.dart`'s provider wiring, or the real
// `salonManageGuard`/`salonStaffMemberProfileProvider` chain that resolves
// `member` in the first place — would leave every widget-tier assertion
// green while a real admin session saw something different. Phase 308's own
// audit filed this gap as a LOW rather than building it inline, because
// closing it means widening `FakeBackend`'s shared salon-admin-1 fixture —
// this file's own header documents the isolation choice that avoided that
// ripple (see [FakeBackend.salonAdminOneStaff]'s doc).
//
// SCOPE — ONE real chain, both directions:
//   1. NEGATIVE — a real SALON_ADMIN login -> the real Персонал tab -> a
//      real co-admin's card -> the real settings page: `row-admin-remove`
//      and its hairline must be ABSENT, while the sibling rows
//      (move-to-salon, convert-to-master) remain PRESENT — the sibling-row
//      assertion is the M14 guard: if the whole page had failed to render,
//      the "row absent" assertion would pass for the wrong reason.
//   2. POSITIVE CONTROL — the SAME co-admin, the SAME settings page, but a
//      real SALON_OWNER of `salon-admin-1` instead: `row-admin-remove` and
//      the hairline must be PRESENT, and tapping the row must open the real
//      confirmation dialog (proving the row is genuinely wired, not merely
//      present-but-dead). The write itself (the DELETE) is already E2E-
//      pinned end-to-end against `salon-xyz`/`admin-zzz` in
//      `salon_staff_settings_flow_test.dart` ITEM 1 — re-proving the wire
//      round trip here would duplicate that file's own headline assertion,
//      so this positive control stops at "the dialog opens".
//
// FIXTURE — `salon-admin-1`, the SALON_ADMIN persona's OWN salon
// (`FakeBackend._adminUserJson.salonId`), and its ISOLATED
// `salonAdminOneStaff` roster (one co-admin, `admin-peer-1`, DISTINCT from
// the logged-in admin's own id `user-admin-1` — see that field's own doc for
// why a PEER, not a self-row, isolates the "not the owner" gate from the
// "cannot remove yourself" gate). Never `salon-xyz`'s own `salonStaff`
// roster — widening that would ripple into the pre-existing exact-roster
// assertions three sibling integration files already carry (Phase 307's own
// precedent for exactly this ripple).
//
// NO PATROL FLOW: pure screen / route / provider / GET surface, same as
// `salon_staff_settings_flow_test.dart`'s own header states for its reason.
//
// FINDERS: widget Keys and fixture proper nouns only — never a Cyrillic UI
// string (`forbid_cyrillic_finder.sh`).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/salon/presentation/staff_settings_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_staff_profile_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

const String _kSalonId = 'salon-admin-1';

/// [FakeBackend.salonAdminOneStaff]'s sole seeded row — the CO-admin whose
/// settings page both tests below open. Never the acting admin's own id
/// (`user-admin-1`) — see that fixture's own doc.
const String _kCoAdminId = 'admin-peer-1';

/// Seeds `salon-admin-1` into the SALON_OWNER persona's `mySalons` list so
/// `salonManageGuard`'s owner arm (bound to `mySalonsProvider`) admits the
/// owner test below onto a salon that is not their own default primary
/// (`salon-owner-1`) — mirrors `salon_staff_settings_flow_test.dart`'s own
/// `_seedSalonXyzIntoMySalons` precedent for the identical reason.
void _seedAdminSalonIntoMySalons(FakeBackend fb) {
  fb.mySalons.add(<String, dynamic>{
    'id': _kSalonId,
    'ownerId': 'user-owner-1',
    'name': 'Салон Адміністратора',
    'city': 'Київ',
    'cityId': 'city-kyiv',
    'oblastId': 'oblast-kyiv',
    'street': 'вул. Січових Стрільців',
    'buildingNo': '7',
    'isActive': true,
    'isPrimary': false,
  });
}

/// Logs [role] in for real and walks the REAL UI path
/// `/manage` -> «Персонал» -> the co-admin's card -> the `tune_rounded`
/// action, landing on [StaffSettingsScreen] for `admin-peer-1`.
///
/// [role] must be [UserRole.salonAdmin] or [UserRole.salonOwner] — the two
/// roles `salonManageGuard` admits onto `/manage` at all.
Future<GoRouter> _openCoAdminSettingsAs(
  WidgetTester tester,
  FakeBackend fb,
  UserRole role,
) async {
  final GoRouter router = await AppHarness.boot(tester, fb);

  await AppHarness.loginAs(tester, fb, role);
  // fixed-wait-ok: settles the real async login/route-transition step.
  await tester.pumpAndSettle(const Duration(seconds: 1));

  router.go(RouteNames.salonManage(_kSalonId));
  // fixed-wait-ok: settles the real async route-transition step.
  await tester.pumpAndSettle(const Duration(seconds: 1));

  final AppLocalizations l10n = await AppLocalizations.delegate.load(
    const Locale('uk'),
  );
  await tester.tap(find.text(l10n.salonManageTabStaff));
  await tester.pumpAndSettle();

  final Finder coAdminCard = find.byKey(
    const Key('salon-manage-staff-card-$_kCoAdminId'),
  );
  await tester.ensureVisible(coAdminCard);
  await tester.pumpAndSettle();
  await tester.tap(coAdminCard);
  await tester.pumpAndSettle();
  expect(find.byType(SalonStaffProfileScreen), findsOneWidget);

  await AppHarness.tapVisible(
    tester,
    find.byKey(const Key('btn-admin-settings')),
  );
  await AppHarness.settle(tester);

  expect(find.byType(StaffSettingsScreen), findsOneWidget);
  AppHarness.expectLocation(
    router,
    '/salons/$_kSalonId/manage/staff/$_kCoAdminId/settings',
  );
  return router;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'a genuinely-authenticated SALON_ADMIN viewing a co-admin\'s settings '
    'sees no remove row and no terminal hairline (D3, real session)',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.salonAdmin;

        final GoRouter router = await _openCoAdminSettingsAs(
          tester,
          fb,
          UserRole.salonAdmin,
        );

        // Sanity: the page resolved a real roster entry over the real wire —
        // if this were absent, "no remove row" would be satisfied by the
        // page failing to load at all rather than by the D3 gate.
        expect(find.byKey(const Key('admin-settings-context')), findsOneWidget);

        // THE GATE — the terminal destructive row and its hairline are both
        // absent. `canManageStaff` (`isOwner && member?.userId !=
        // currentUserId`) is false here because a SALON_ADMIN is never
        // `isOwner`, regardless of whose row this is.
        expect(find.byKey(const Key('row-admin-remove')), findsNothing);
        expect(find.byKey(const Key('admin-settings-divider')), findsNothing);

        // M14 GUARD — the sibling rows the admin branch always draws must
        // still be present. Without this, the two `findsNothing` assertions
        // above would also pass on a page that failed to render at all.
        expect(
          find.byKey(const Key('row-admin-move-salon')),
          findsOneWidget,
          reason:
              'the admin branch\'s OTHER rows must still render — otherwise '
              'the remove-row absence could be satisfied by a blank page',
        );
        expect(
          find.byKey(const Key('row-admin-convert-to-master')),
          findsOneWidget,
        );

        // Still parked on the settings page — no guard bounced the viewer
        // away, which would be a different (and differently visible) way to
        // fail this test.
        expect(
          AppHarness.location(router),
          equals('/salons/$_kSalonId/manage/staff/$_kCoAdminId/settings'),
        );
      });
    },
  );

  testWidgets(
    'POSITIVE CONTROL — the same co-admin\'s settings page DOES show a live '
    'remove row for a genuine SALON_OWNER of that salon',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.salonOwner;
        _seedAdminSalonIntoMySalons(fb);

        await _openCoAdminSettingsAs(tester, fb, UserRole.salonOwner);

        expect(find.byKey(const Key('admin-settings-context')), findsOneWidget);
        expect(find.byKey(const Key('row-admin-remove')), findsOneWidget);
        expect(find.byKey(const Key('admin-settings-divider')), findsOneWidget);

        // Prove the row is genuinely LIVE, not present-but-dead: tapping it
        // must open the real confirmation dialog. Not confirmed any further
        // — the DELETE round trip itself is already E2E-pinned against
        // `salon-xyz`/`admin-zzz` in `salon_staff_settings_flow_test.dart`
        // ITEM 1, and `salon-admin-1` has no DELETE handler wired (this
        // fixture exists to prove the row RENDERS, not to re-prove the write
        // a sibling file already covers).
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('row-admin-remove')),
        );
        await AppHarness.settle(tester);
        expect(find.byKey(const Key('remove-admin-dialog')), findsOneWidget);
      });
    },
  );
}
