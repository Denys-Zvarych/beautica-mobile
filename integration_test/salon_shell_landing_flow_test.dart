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

import 'dart:convert';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/salon/presentation/my_salons_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/fakes/fake_secure_storage.dart';
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
      // Phase 287 D4 — an explicit storage instance so this flow also proves
      // an ADMIN's shell entry is recorded too, not only an owner's.
      final storage = FakeSecureStorage();
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        storage: storage,
      );

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

      // Phase 287 D4 — an admin's shell entry must be recorded too.
      final String? rawLastSalon = await storage.readLastSalon();
      expect(
        rawLastSalon,
        isNotNull,
        reason:
            'Phase 287 D4 — an admin opening their shell must durably '
            'record the salon, unconditionally, exactly like an owner',
      );
      final Map<String, dynamic> lastSalon =
          jsonDecode(rawLastSalon!) as Map<String, dynamic>;
      expect(lastSalon['salonId'], equals(_adminSalonId));
      expect(lastSalon['userId'], equals('user-admin-1'));
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

  testWidgets(
    'mobile-security INFO-1 — a GET /salons/mine row missing cityId fails '
    'deserialization gracefully: My Salons hub renders an ErrorState with a '
    'working retry, never a crash',
    (tester) async {
      // `SalonResponse.cityId`/`.oblastId` are non-null on the wire as of
      // backend `ec22d91` (`salons.city_id` DB-level NOT NULL) — the
      // generated `SalonResponse.g.dart` deserializer calls
      // `BuiltValueNullFieldError.checkNotNull` on `cityId`, so a row that
      // omits it (a genuinely malformed/legacy backend response — the kind
      // this diff's own non-nullable flip is supposed to make unreachable in
      // practice, but the CLIENT must still degrade gracefully if it isn't)
      // throws mid-build. `BuiltValueNullFieldError extends Error`, which
      // Riverpod's `ProviderContainer.defaultRetry` (consulted by
      // `beauticaProviderRetry` for any non-`Failure` error) refuses to
      // retry at all — this surfaces as a TERMINAL `AsyncError` on the very
      // first attempt, no `AsyncLoading(retrying: true)` window to race.
      final fb = FakeBackend()
        ..currentRole = UserRole.salonOwner
        ..mySalons = <Map<String, dynamic>>[
          <String, dynamic>{
            'id': _ownerPrimarySalonId,
            'ownerId': 'user-owner-1',
            'name': 'Салон Оксани',
            'city': 'Київ',
            // 'cityId' DELIBERATELY OMITTED — the malformed-payload fixture
            // this test exists to pin. 'oblastId' still present so this
            // isolates the cityId-specific null-field throw.
            'oblastId': 'oblast-kyiv',
            'street': 'Хрещатик',
            'buildingNo': '10',
            'isActive': true,
            'isPrimary': true,
          },
        ];
      final GoRouter router = await AppHarness.boot(tester, fb);

      await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
      await AppHarness.settle(tester);

      // `mySalonsProvider` is `keepAlive: true` — the post-login landing
      // (`SalonHomeResolverScreen`, its OWN identical `ErrorState` branch)
      // already forced the first (and, per the no-retry reasoning above,
      // ONLY) `GET /salons/mine` attempt. Navigating to the hub explicitly
      // (mobile-security's named pin, `my_salons_screen.dart:178-183`) reads
      // the SAME already-resolved `AsyncError` — no second network call.
      router.go(RouteNames.mySalons);
      await AppHarness.settle(tester);

      expect(
        tester.takeException(),
        isNull,
        reason:
            'a missing cityId must never crash the app — mobile-security '
            'INFO-1 traced this statically; this proves it at runtime.',
      );
      expect(find.byType(MySalonsScreen), findsOneWidget);
      expect(
        find.byType(ErrorState),
        findsOneWidget,
        reason:
            'BuiltValueNullFieldError (a non-Failure Error) must still '
            'route through the error: branch as UnknownFailure, rendering '
            'the generic ErrorState — never an indefinite spinner and '
            'never a red-screen crash.',
      );
      final Finder retryButton = find.byKey(
        const Key('error_state_retry_button'),
      );
      expect(
        retryButton,
        findsOneWidget,
        reason:
            'the retry affordance must be present, not just a bare '
            'error message the viewer cannot act on.',
      );

      final int callsBeforeRetry = fb.getMySalonsCalls;
      await tester.tap(retryButton);
      await AppHarness.settle(tester);

      expect(
        fb.getMySalonsCalls,
        greaterThan(callsBeforeRetry),
        reason:
            'tapping retry must actually re-invoke GET /salons/mine '
            '(ref.invalidate(mySalonsProvider)), not just repaint the same '
            'stale error.',
      );
      expect(
        tester.takeException(),
        isNull,
        reason:
            'the retry attempt (same corrupted payload) must ALSO fail '
            'gracefully, not crash.',
      );
      expect(
        find.byType(ErrorState),
        findsOneWidget,
        reason:
            'the corrupted payload is still corrupted — retry must land '
            'back on the SAME graceful ErrorState, not a blank/loading '
            'screen stuck forever.',
      );
    },
  );
}
