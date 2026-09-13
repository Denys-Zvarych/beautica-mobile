// Phase 322 — E2E: the SALON_ADMIN mirror of phase 318's owner journey
// (`salon_owner_set_master_services_flow_test.dart`), driven by a REAL tap
// chain, not a deep link.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — user-flow coverage)
// -----------------------------------------------------------
// Phase 322's D1/D4 predicate (`canManageSalonProvider`,
// `lib/features/salon/application/salon_manage_capability.dart`) and its
// widget-level wiring (`_SalonManageServicesListRoute`/
// `_SalonManageServiceEditRoute` in `app_router.dart`) are already pinned at
// the unit tier (`test/features/salon/application/
// salon_manage_capability_test.dart`'s five-row role matrix) and the
// route-type tier (`test/routing/salon_manage_staff_services_route_test.dart`,
// which already drives an admin session through `ServicesListScreen`'s TYPE
// resolution). Neither proves the REAL journey: a genuine SALON_ADMIN login
// -> the real «Персонал» tab -> a real roster card -> the real
// `ManagementActionCard` («Послуги», Phase 325 restyle of the row phase 318
// added) -> a real push into the REAL `ServicesListScreen`/
// `ServiceSetupScreen` pair -> a real bulk POST -> a real unassign DELETE,
// all against the admin's OWN salon (`salon-admin-1`) — and the negative
// mirror phase 322's D4 exists for: an admin of a DIFFERENT salon deep-
// linking the identical route is bounced, not merely rendered read-only.
//
// WHAT THE REQUIRED CASES PIN, AND WHY THEY CANNOT PASS VACUOUSLY
// -----------------------------------------------------------------
//  1. THE READ REACHES THE RIGHT WIRE, ADMIN-SCOPED. Tapping «Послуги» on
//     `master-admin-target` (roster `userId` `user-master-under-admin`,
//     DIFFERENT from its `masters` row id, mirroring the owner flow's
//     `master-removable` pairing — `project_fixture_values_can_defang_
//     assertions`) must land on `ServicesListScreen` with a GET that carried
//     the master ROW id against `salon-admin-1`, the SAME salon-scoped shape
//     the owner flow proves, never the independent-master path.
//  2. THE FAB REACHES THE SALON BULK PATH, ADMIN-SCOPED — same endpoint
//     family phase 318 asserts (`/salons/{s}/masters/{m}/services/bulk`),
//     bound to the admin's own salon.
//  3. THE UNASSIGN REACHES THE SAME WIRE — unassigning the PRE-SEEDED
//     `salon-admin-def-1` (not the row this test just added) proves the
//     DELETE path removes a genuinely pre-existing row, mirroring the
//     owner flow's backlog-802 rigor.
//  4. D4 — THE BOUNCE. An admin of `salon-xyz` (a DIFFERENT salon from
//     their own `salon-admin-1`) deep-linking
//     `/salons/salon-xyz/manage/staff/.../services` must be bounced by
//     `salonManageGuard`'s admin arm before `ServicesListScreen` ever
//     mounts — a role-only gate would ADMIT this, which is exactly the
//     catastrophic-wrongness D4 exists to catch.
//  5. THE EMPTY-CATALOGUE CARD (mobile-qa, 2026-09-12 — closes the Phase
//     325 QA-pass INFO row). `master-admin-target`'s PUBLIC per-master
//     services read (`fake_backend.dart`'s
//     `/api/v1/masters/master-admin-target/services`) is fixture-empty —
//     the one roster member either salon-services E2E file reaches with a
//     genuinely empty catalogue (the owner flow's `master-removable` seeds
//     two rows from the start). Asserted BEFORE this test's own bulk-create
//     step below runs, so it pins the pristine zero-service render, not a
//     post-mutation coincidence: the «Послуги» `ManagementActionCard.value`
//     must equal `l10n.staffProfileServicesEmpty` («Ще немає»), never
//     `l10n.staffProfileServicesCount(0)` — the exact fork
//     `salon_staff_profile_screen.dart`'s own D3 comment documents and the
//     widget tier already mutation-proves in isolation
//     (`salon_staff_profile_screen_test.dart`), but which no E2E had
//     exercised end to end until now.
//
// FIXTURE — `salon-admin-1` / `master-admin-target`: the SALON_ADMIN
// persona's OWN salon and its Phase 312-seeded master row
// (`FakeBackend.salonAdminOneStaff`). The salon-scoped services wire for
// this pair (`_wireSalonAdminMasterServices`/`_wireSalonAdminMasterServices
// Bulk`, `_salonAdminMasterServices`) is a phase-322 addition to
// `fake_backend.dart`, kept fully SEPARATE from the owner flow's
// `salon-xyz`/`master-removable` counters and fixture list — a role-only
// (not salon-scoped) gate would still coincidentally hit ONE of the two
// pairs, so the two must never share state or this file's assertions could
// pass for the wrong reason.
//
// `salon_staff_settings_admin_gate_flow_test.dart` (existing, UNEDITED by
// this phase) already proves the locked invite-but-not-remove asymmetry for
// this exact persona/salon pair — this file never touches admin-removal.
//
// TIMING: never bare `pumpAndSettle()` on this screen family — same
// staggered-`RevealTransition` hazard `salon_owner_set_master_services_flow_
// test.dart`'s own header records. Every wait here is
// `AppHarness.pumpUntilFound`/`pumpUntilCondition` (bounded, real
// wall-clock) or a bounded fixed-count pump loop, mirroring that file.
//
// KEY POLICY: navigation taps use key-based finders only. No
// `find.text(cyrillic)` anywhere in this file (`forbid_cyrillic_finder.sh`).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/management_action_card.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_staff_profile_screen.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// The SALON_ADMIN persona's own salon (`FakeBackend._adminUserJson.salonId`
/// — do not re-derive the persona; it already exists in `fake_backend.dart`).
const String _kSalonId = 'salon-admin-1';

/// `FakeBackend.salonAdminOneStaff`'s master row — the roster entry's
/// `userId` (what the `:memberId` path segment carries) and its `masters`
/// ROW id, deliberately different (see file header, case 1).
const String _kMemberUserId = 'user-master-under-admin';
const String _kMasterRowId = 'master-admin-target';

const String _kSalonServicesUri =
    '/api/v1/salons/$_kSalonId/masters/$_kMasterRowId/services';
const String _kSalonBulkUri = '$_kSalonServicesUri/bulk';

/// A NAILS-category service type, free of ownership exclusion — same type
/// id the owner flow test reuses for the identical reason.
const String _kFreeTypeId = 'type-nails-gel';

/// A salon the acting admin does NOT belong to — `salon-xyz`'s own
/// `masterRemovable` roster is never touched by this file; the bounce fires
/// before any roster read.
const String _kOtherSalonId = 'salon-xyz';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  /// Bounded lockstep pump standing in for `pumpAndSettle`/`AppHarness.settle`
  /// on this screen family — see file header TIMING note.
  Future<void> lockstepPump(
    WidgetTester tester, {
    int times = 3,
    Duration step = const Duration(milliseconds: 300),
  }) async {
    for (var i = 0; i < times; i++) {
      // fixed-wait-ok: bounded lockstep pump — see file header TIMING note.
      await tester.pump(step);
    }
  }

  Future<void> tapWhenReady(WidgetTester tester, Finder finder) async {
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

  testWidgets(
    'SALON_ADMIN: roster -> «Послуги» -> the real salon-scoped list -> FAB '
    'add -> unassign the pre-seeded row (admin parity with the owner '
    'journey)',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.salonAdmin;

        await AppHarness.boot(tester, fb);
        await AppHarness.loginAs(tester, fb, UserRole.salonAdmin);

        // An admin belongs to exactly ONE salon (their own) — login lands
        // directly on its shell, no explicit `router.go` needed (unlike the
        // owner arm, which may own several salons).
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(SalonShellScreen),
          timeout: const Duration(seconds: 20),
        );
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(const Key('salon-nav-tile-2')),
          timeout: const Duration(seconds: 20),
        );

        // ── «Персонал» tab -> the real roster grid ──────────────────────
        await tapWhenReady(tester, find.byKey(const Key('salon-nav-tile-2')));

        final Finder masterCard = find.byKey(
          const Key('salon-manage-staff-card-$_kMemberUserId'),
        );
        // `AppHarness.revealRosterCard` is the single shared way to locate a
        // roster card in the lazily-inflated `SliverGrid.builder`: it gates on
        // the grid having LOADED, then drags only when the target cell was
        // never built. This target sits in row 0 by fixture shape, so it
        // no-ops and this path behaves exactly as before.
        await AppHarness.revealRosterCard(tester, masterCard);
        await tapWhenReady(tester, masterCard);

        await AppHarness.pumpUntilFound(
          tester,
          find.byType(SalonStaffProfileScreen),
          timeout: const Duration(seconds: 20),
        );

        // ── 1. THE PHASE 318 ROW -> the real salon-scoped list, ADMIN-SCOPED
        final Finder servicesRow = find.byKey(
          const Key('salon-staff-profile-services-row'),
        );
        await AppHarness.pumpUntilFound(
          tester,
          servicesRow,
          timeout: const Duration(seconds: 20),
        );

        // ── 0. THE EMPTY-CATALOGUE FORK (closes the Phase 325 QA INFO row,
        // see file header case 5). `master-admin-target` has zero services
        // on the PUBLIC read at this point in the journey — assert the D3
        // fork renders «Ще немає», never a "0 послуг" count, BEFORE the
        // bulk-create step below adds anything.
        final AppLocalizations emptyL10n = AppLocalizations.of(
          tester.element(find.byType(SalonStaffProfileScreen)),
        );
        final ManagementActionCard emptyServicesCard = tester
            .widget<ManagementActionCard>(servicesRow);
        expect(
          emptyServicesCard.value,
          emptyL10n.staffProfileServicesEmpty,
          reason:
              'a master with zero active services must render '
              'staffProfileServicesEmpty («Ще немає»), not a count',
        );
        expect(
          emptyServicesCard.value,
          isNot(emptyL10n.staffProfileServicesCount(0)),
          reason:
              'D3 explicitly forbids staffProfileServicesCount(0) for an '
              'empty catalogue — see salon_staff_profile_screen.dart\'s own '
              'doc comment',
        );

        // Drain the staggered RevealTransitions off this screen's animation
        // controller — see file header TIMING note.
        await lockstepPump(tester);
        await tapWhenReady(tester, servicesRow);

        await AppHarness.pumpUntilFound(
          tester,
          find.byType(ServicesListScreen),
          timeout: const Duration(seconds: 20),
        );

        expect(
          fb.getSalonAdminMasterServicesCalls,
          greaterThanOrEqualTo(1),
          reason:
              'the tap must reach the ADMIN-SCOPED salon-target read, not '
              'merely render an empty/loading screen',
        );
        expect(
          fb.lastSalonAdminMasterServicesPath,
          _kSalonServicesUri,
          reason:
              'the master ROW id must be on the wire against the admin\'s '
              'OWN salon, never the roster userId and never the owner '
              'flow\'s salon-xyz/master-removable pair',
        );
        expect(
          fb.getSalonMasterServicesCalls,
          0,
          reason:
              'the owner-scoped counter must stay untouched — a role-only '
              '(not salon-scoped) gate could coincidentally hit that pair '
              'instead and this assertion is what would catch it',
        );

        final Finder nails = find.byKey(const Key('category_section_NAILS'));
        await AppHarness.pumpUntilFound(
          tester,
          nails,
          timeout: const Duration(seconds: 20),
        );
        final Finder seededCard = find.byKey(
          const Key('service_card_salon-admin-assign-1'),
        );
        if (seededCard.evaluate().isEmpty) {
          await tapWhenReady(tester, nails);
        }
        await AppHarness.pumpUntilFound(
          tester,
          seededCard,
          timeout: const Duration(seconds: 20),
        );
        expect(seededCard, findsOneWidget);

        // ── 2. FAB -> ServiceSetupScreen -> pick a type -> submit ────────
        final Finder fab = find.byKey(const Key('btn-create-service'));
        await AppHarness.pumpUntilFound(
          tester,
          fab,
          timeout: const Duration(seconds: 20),
        );
        await tapWhenReady(tester, fab);
        await lockstepPump(tester);

        final Finder setupClose = find.byKey(const Key('btn-setup-close'));
        await AppHarness.pumpUntilFound(
          tester,
          setupClose,
          timeout: const Duration(seconds: 20),
        );

        final Finder nailsChip = find.byKey(
          const ValueKey<String>('cat_NAILS'),
        );
        await AppHarness.pumpUntilFound(
          tester,
          nailsChip,
          timeout: const Duration(seconds: 20),
        );
        await tapWhenReady(tester, nailsChip);

        final Finder freeRow = find.byKey(const Key('setup_row_$_kFreeTypeId'));
        await AppHarness.pumpUntilFound(
          tester,
          freeRow,
          timeout: const Duration(seconds: 20),
        );
        final Finder freeToggle = find.byKey(
          const Key('setup_row_toggle_$_kFreeTypeId'),
        );
        await AppHarness.pumpUntilFound(
          tester,
          freeToggle,
          timeout: const Duration(seconds: 20),
        );
        await tapWhenReady(tester, freeToggle);

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
          durationField,
          timeout: const Duration(seconds: 20),
        );
        await AppHarness.pumpUntilFound(
          tester,
          priceField,
          timeout: const Duration(seconds: 20),
        );
        await tester.enterText(durationField, '50');
        await tester.pump();
        await tester.enterText(priceField, '420');
        await tester.pump();

        final Finder saveBtn = find.byKey(const Key('btn-setup-save'));
        await tapWhenReady(tester, saveBtn);

        // DIAGNOSE AT THE CAUSE — the POST reaching the wire before its path.
        await AppHarness.pumpUntilCondition(
          tester,
          () => fb.salonAdminBulkCreateCalls >= 1,
          description:
              'the admin-scoped salon bulk POST to reach the fake backend '
              '— if it never does, the save was blocked client-side',
          timeout: const Duration(seconds: 20),
        );
        expect(
          fb.lastSalonAdminBulkPath,
          _kSalonBulkUri,
          reason:
              'phase 322 mirrors phase 315 D2 — a SalonMasterTarget must '
              'dispatch bulkCreate to /salons/{s}/masters/{m}/services/bulk '
              'against the admin\'s OWN salon',
        );
        expect(
          fb.salonBulkCreateCalls,
          0,
          reason:
              'the OWNER-scoped bulk counter must stay untouched — same '
              'anti-vacuity reasoning as the GET assertion above',
        );
        expect(
          fb.bulkCreateCalls,
          0,
          reason:
              'the independent-master bulk endpoint must NEVER fire for a '
              'salon-scoped save',
        );

        await AppHarness.pumpUntilGone(
          tester,
          find.byKey(const Key('btn-setup-close')),
          timeout: const Duration(seconds: 20),
        );
        final Finder newCard = find.byKey(
          const Key('service_card_salon-admin-assign-bulk-1'),
        );
        await AppHarness.pumpUntilFound(
          tester,
          newCard,
          timeout: const Duration(seconds: 20),
        );
        expect(newCard, findsOneWidget);

        // ── 3. Unassign the PRE-SEEDED row (not the one just added) ──────
        // Proves the DELETE path removes a genuinely pre-existing row, not
        // merely the row this test happened to create moments earlier
        // (`project_fixture_values_can_defang_assertions`).
        await tapWhenReady(tester, seededCard);
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(const Key('service-edit-form-salon-admin-assign-1')),
          timeout: const Duration(seconds: 20),
        );

        await tapWhenReady(tester, find.byKey(const Key('btn-delete-service')));
        await AppHarness.pumpUntilFound(
          tester,
          find.byKey(const Key('delete-service-dialog')),
          timeout: const Duration(seconds: 20),
        );
        final int unassignCallsBefore = fb.unassignAdminServiceCalls;
        await tapWhenReady(
          tester,
          find.byKey(const Key('btn-confirm-delete-service')),
        );
        await AppHarness.pumpUntilCondition(
          tester,
          () => fb.unassignAdminServiceCalls > unassignCallsBefore,
          description:
              'the admin-scoped unassign DELETE to reach the fake '
              'backend',
          timeout: const Duration(seconds: 20),
        );
        expect(fb.lastUnassignedAdminServiceDefId, 'salon-admin-def-1');
        expect(
          fb.unassignServiceCalls,
          0,
          reason:
              'the OWNER-scoped unassign counter must stay untouched — same '
              'anti-vacuity reasoning as the GET/bulk assertions above',
        );
      });
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  // ── D4: an admin of a DIFFERENT salon is a bounce, not a widening ──────

  testWidgets(
    'D4 — a SALON_ADMIN deep-linking a DIFFERENT salon\'s staff-services '
    'route is bounced before ServicesListScreen ever mounts',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend()..currentRole = UserRole.salonAdmin;

        final GoRouter router = await AppHarness.boot(tester, fb);
        await AppHarness.loginAs(tester, fb, UserRole.salonAdmin);
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(SalonShellScreen),
          timeout: const Duration(seconds: 20),
        );

        // The admin's own salonId is `salon-admin-1` — deep-link to a
        // DIFFERENT salon's staff-services route. `_kOtherSalonId` needs no
        // real roster data: `salonManageGuard`'s admin arm bounces on the
        // `User.salonId` mismatch before any roster/service read fires.
        router.go(
          RouteNames.salonManageStaffServices(_kOtherSalonId, 'any-member'),
        );
        await lockstepPump(tester);
        // fixed-wait-ok: settles the real async redirect/route-transition
        // step — same idiom `salon_staff_settings_admin_gate_flow_test.dart`
        // uses for its own real login/route transitions.
        await tester.pumpAndSettle(const Duration(seconds: 1));

        expect(
          find.byType(ServicesListScreen),
          findsNothing,
          reason:
              'D4 — the bounce must fire before ServicesListScreen ever '
              'mounts; a role-only gate would ADMIT this deep link',
        );
        expect(
          AppHarness.location(router),
          isNot(
            equals('/salons/$_kOtherSalonId/manage/staff/any-member/services'),
          ),
          reason:
              'the router must have redirected away from the requested '
              'route entirely',
        );
        expect(
          fb.getSalonMasterServicesCalls,
          0,
          reason:
              'no salon-scoped service read may fire for a bounced '
              'navigation',
        );
        expect(fb.getSalonAdminMasterServicesCalls, 0);
      });
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
