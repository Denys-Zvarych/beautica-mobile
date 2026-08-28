// Phase 21.8 QA follow-up — E2E: the shared SALON_OWNER/SALON_ADMIN landing
// resolves to the Salon Shell for BOTH roles, and the owner's zero-salon edge
// case still lands on the My Salons hub.
//
// SCOPE, DELIBERATELY NARROWED (REUSE-FIRST — no duplicate assertions)
// ----------------------------------------------------------------------
// `salon_owner_landing_flow_test.dart` already E2E-pins, against the SAME
// real router + FakeBackend:
//   • fresh SALON_OWNER login -> RouteNames.salonShell(primarySalonId),
//     find.byType(SalonShellScreen).
//   • post-registration `done_to_app` CTA -> the same shell.
// Re-asserting those here would fork the same scenario across two files —
// exactly what REUSE-FIRST forbids. This file covers the TWO shell-landing
// paths that sibling file does NOT touch:
//   1. SALON_ADMIN login -> the shell, via `session.user.salonId`
//      (`SalonHomeResolverScreen`'s synchronous admin arm) — NEVER through
//      `GET /salons/mine`, which an admin has no use for.
//   2. SALON_OWNER with ZERO salons -> the My Salons hub (`/salons/mine`),
//      not a shell with no salonId to scope to.
//
// Until this file, FakeBackend had no SALON_ADMIN persona at all
// (`userJsonForRole` fell through to `_masterUserJson`) — no E2E flow could
// reach the admin arm. Added a dedicated `_adminUserJson` fixture
// (`fake_backend.dart`) with a `salonId` DISTINCT from `mySalons`' own
// `salon-owner-1`, specifically so a regression that made the admin landing
// depend on `mySalonsProvider` would be observable here (a shared id would
// mask exactly that class of bug).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/salon/presentation/my_salons_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// [FakeBackend.mySalons]'s default single-primary salon id — asserted BELOW
/// to be irrelevant to the admin landing (see file header).
const String _ownerPrimarySalonId = 'salon-owner-1';

/// Matches `fake_backend.dart`'s `_adminUserJson.salonId` — deliberately a
/// DIFFERENT id than [_ownerPrimarySalonId].
const String _adminSalonId = 'salon-admin-1';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'SALON_ADMIN logs in -> lands on the Salon Shell for their OWN salon, '
    'never on /salons/mine, and never calls GET /salons/mine',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.salonAdmin;
      final GoRouter router = await AppHarness.boot(tester, fb);

      expect(
        find.byKey(const ValueKey<String>('login_email')),
        findsOneWidget,
        reason: 'cold start with no stored token must show the login form',
      );

      await AppHarness.loginAs(tester, fb, UserRole.salonAdmin);
      await AppHarness.settle(tester);

      final String landed = AppHarness.location(router);
      expect(
        landed,
        equals(RouteNames.salonShell(_adminSalonId)),
        reason:
            'SALON_ADMIN must land exactly on '
            '${RouteNames.salonShell(_adminSalonId)} (their own '
            '`session.user.salonId`) — got $landed.',
      );
      expect(
        landed,
        isNot(equals(RouteNames.mySalons)),
        reason:
            'SALON_ADMIN has no use for the My Salons hub — that surface is '
            'SALON_OWNER-only (mySalonsGuard).',
      );
      expect(
        landed,
        isNot(equals(RouteNames.salonShell(_ownerPrimarySalonId))),
        reason:
            'the admin landing must resolve from `session.user.salonId`, '
            'never from the owner fixture\'s primary salon — a shared id '
            'between the two fixtures would mask a regression that made '
            'the admin arm depend on `mySalonsProvider`.',
      );
      expect(
        find.byType(SalonShellScreen),
        findsOneWidget,
        reason:
            'the resolved PAGE TYPE must be the real shell, not merely a '
            'matching location string.',
      );
      expect(
        fb.getMySalonsCalls,
        equals(0),
        reason:
            'SalonHomeResolverScreen\'s admin arm reads `session.user.salonId` '
            'SYNCHRONOUSLY — it must never fire GET /salons/mine at all.',
      );
      expect(fb.loginCalls, equals(1));
    },
  );

  testWidgets(
    'SALON_OWNER with ZERO salons logs in -> lands on the My Salons hub, '
    'never a shell with no salonId to scope to',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.salonOwner
        ..mySalons = <Map<String, dynamic>>[];
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.settle(tester);

      final String landed = AppHarness.location(router);
      expect(
        landed,
        equals(RouteNames.mySalons),
        reason:
            'a SALON_OWNER who owns no salon yet must land on the My Salons '
            'hub (its own «+ Додати салон» CTA), not a shell scoped to no '
            'salon at all — got $landed.',
      );
      expect(find.byType(MySalonsScreen), findsOneWidget);
      expect(find.byType(SalonShellScreen), findsNothing);
    },
  );
}
