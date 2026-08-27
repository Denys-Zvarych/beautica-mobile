// Phase 21.2 QA follow-up — route-guard tests for `salonManageGuard`
// (`app_router.dart:221`), gating `/salons/:salonId/manage` and
// `/salons/:salonId/manage/settings`.
//
// WHY THIS FILE EXISTS
// ---------------------
// Before this file, `salonManageGuard` could be deleted outright, or its role
// check inverted, and every existing test stayed green:
//   • `test/routing/navigation_links_test.dart` (NL-R01) only asserts the two
//     paths resolve via `router.configuration.findMatch(...)` — that call
//     never invokes `redirect`, so it cannot observe a guard at all.
//   • NL-R01c is a constant<->map CARDINALITY ledger, not a behavioural test.
//   • `salon_management_profile_screen_test.dart` /
//     `salon_settings_screen_test.dart` each build their OWN private
//     `GoRouter` (no `redirect:` wired on either route) — the production
//     guard is never in play.
//
// MECHANISM (reused, not invented — REUSE-FIRST): mirrors
// `booking_route_guard_test.dart`'s proven shape — mount the REAL
// `appRouterProvider` via a `ProviderContainer` + `UncontrolledProviderScope`,
// drive `router.go(...)` directly, and assert the RESOLVED location plus the
// mounted widget TYPE. This is the only way to actually exercise
// `salonManageGuard`, which (like `clientOnlyGuard`) is a closure defined
// INSIDE `appRouterProvider` and wired as each route's own `redirect:` —
// there is no pure-function seam to call directly (see that file's header for
// the full rationale, which applies identically here).
//
// REDIRECT TARGETS COVERED (per `role_landing_dispatch_guard_test.dart` +
// `role_landing_chrome_matrix.dart`):
//   • SALON_OWNER            → ADMITTED unconditionally (roleHomePath is
//     irrelevant). NOT ownership-bound yet — an owner can own MANY salons, so
//     a single session `User.salonId` cannot authorize them; the
//     authoritative check needs `GET /salons/mine` (Phase 21.1, unbuilt). See
//     `salonManageGuard`'s own TODO(phase-21.1) in `app_router.dart`.
//   • SALON_ADMIN on their OWN `User.salonId` → ADMITTED.
//   • SALON_ADMIN on a DIFFERENT `salonId`    → roleHomePath = RouteNames.home
//     (mobile-security MEDIUM follow-up, 2026-08-27 — an admin could
//     previously open ANY salon's manage surface).
//   • CLIENT       → roleHomePath = RouteNames.clientHome (real chrome —
//     HomeHubScreen — needs its 5 data providers settled, same overrides
//     `role_landing_chrome_test.dart` uses, or a Riverpod retry Timer
//     outlives the test).
//   • SALON_MASTER → roleHomePath = RouteNames.home ('/', the bare
//     no-chrome placeholder) — needs NO extra overrides.
//   • unauthenticated → the GLOBAL `authRedirect` prefix gate (not
//     `salonManageGuard`) sends it to `/login`, alongside whatever
//     `salonManageGuard` itself would have done.

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/rating/application/my_rating_notifier.dart';
import 'package:beautica_mobile/features/rating/domain/client_rating.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_management_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_settings_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const String _kSalonId = 'salon-guard-1';

const _kSalon = Salon(id: _kSalonId, name: 'Guard Test Salon');

/// [SalonManagementProfile] stub that resolves immediately so the ADMITTED
/// cases mount `SalonManagementProfileScreen` without the real
/// `salonRepositoryProvider` firing a Dio request (same leaked-timer
/// avoidance `booking_route_guard_test.dart` documents for its own
/// data-fetching overrides).
class _SettledSalonManagementProfile extends SalonManagementProfile {
  @override
  Future<SalonManagementProfileData> build(String salonId) async =>
      (_kSalon, const <SalonMasterSummary>[]);
}

const _ownerUser = User(
  id: 'owner-1',
  email: 'owner@example.com',
  role: UserRole.salonOwner,
  firstName: 'Owner',
  lastName: 'User',
);
const _ownerSession = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _ownerUser, accessToken: 'token'),
);

const _adminUser = User(
  id: 'admin-1',
  email: 'admin@example.com',
  role: UserRole.salonAdmin,
  firstName: 'Admin',
  lastName: 'User',
  // Matches [_kSalonId] — the "own salon" case. [salonManageGuard] now binds
  // SALON_ADMIN to an exact `User.salonId` match (mobile-security MEDIUM
  // follow-up, 2026-08-27).
  salonId: _kSalonId,
);
const _adminSession = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _adminUser, accessToken: 'token'),
);

/// A SALON_ADMIN whose `salonId` does NOT match [_kSalonId] — the "someone
/// else's salon" case the MEDIUM finding was about.
const _otherSalonAdminUser = User(
  id: 'admin-2',
  email: 'other-admin@example.com',
  role: UserRole.salonAdmin,
  firstName: 'Other',
  lastName: 'Admin',
  salonId: 'salon-guard-2',
);
const _otherSalonAdminSession = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _otherSalonAdminUser, accessToken: 'token'),
);

const _clientUser = User(
  id: 'client-1',
  email: 'client@example.com',
  role: UserRole.client,
  firstName: 'Client',
  lastName: 'User',
);
const _clientSession = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _clientUser, accessToken: 'token'),
);

const _salonMasterUser = User(
  id: 'salon-master-1',
  email: 'salonmaster@example.com',
  role: UserRole.salonMaster,
  firstName: 'Salon',
  lastName: 'Master',
);
const _salonMasterSession = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _salonMasterUser, accessToken: 'token'),
);

const _unauthenticatedSession = AsyncData<AuthSession>(
  AuthSession.unauthenticated(),
);

/// [AuthNotifier] stub that immediately settles to a fixed [AsyncValue] —
/// mirrors `booking_route_guard_test.dart`'s `_FixedAuthNotifier`.
class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);

  final AsyncValue<AuthSession> _fixed;

  @override
  Future<AuthSession> build() async {
    state = _fixed;
    return _fixed.value ?? const AuthSession.unauthenticated();
  }
}

/// [MaterialApp.router] wrapper for the real [appRouterProvider] with l10n
/// delegates — mirrors `booking_route_guard_test.dart`'s `_RouterApp`.
class _RouterApp extends StatelessWidget {
  const _RouterApp({required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('uk', 'UA'),
  );
}

void main() {
  group('salonManageGuard (Phase 21.2)', () {
    // Park the splash gate in the past so authRedirect does not pin the
    // router on /splash waiting for AppStartTime.minSplashDuration to elapse.
    setUp(
      () => AppStartTime.setStartForTest(
        DateTime.now().subtract(const Duration(seconds: 5)),
      ),
    );
    tearDown(AppStartTime.resetForTest);

    ProviderContainer makeContainer(AsyncValue<AuthSession> session) {
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          authProvider.overrideWith(() => _FixedAuthNotifier(session)),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
          // Settles the ADMITTED-case screen's data fetch synchronously — see
          // [_SettledSalonManagementProfile]'s doc.
          salonManagementProfileProvider(
            _kSalonId,
          ).overrideWith(_SettledSalonManagementProfile.new),
          // Settles the CLIENT redirect target (RouteNames.clientHome →
          // HomeHubScreen's 5 data providers) synchronously — same
          // leaked-Timer avoidance `role_landing_chrome_test.dart` documents
          // in full for these exact 5 overrides. SALON_MASTER's redirect
          // target (RouteNames.home, the bare `/` placeholder) needs none of
          // these — it renders no data at all.
          clientProfileProvider.overrideWith(
            (ref) async => const ClientProfileSummary(
              firstName: 'Test',
              lastName: 'Client',
              city: '',
              phone: '',
              clientRating: null,
              memberSinceYear: 2026,
            ),
          ),
          nextAppointmentProvider.overrideWith((ref) async => null),
          favoriteMastersProvider.overrideWith(
            (ref) async => const <FavoriteMasterItem>[],
          ),
          beautyTimelineProvider.overrideWith(
            (ref) async => const <TimelineEntry>[],
          ),
          myRatingProvider.overrideWith((ref) async => const ClientRating()),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    // Every navigation in this file is `router.go(...)`, never
    // `context.push`/`GoRouter.push` — the `ImperativeRouteMatch` exclusion
    // this raw read is normally fragile against never applies here. Mirrors
    // `booking_route_guard_test.dart`'s identical `locationOf` helper
    // (grandfathered; this file is new).
    String locationOf(GoRouter router) {
      // router-location-ok: only router.go(...) is used in this file.
      return router.routerDelegate.currentConfiguration.uri.toString();
    }

    Future<GoRouter> pumpRouterAs(
      WidgetTester tester,
      AsyncValue<AuthSession> session,
    ) async {
      final container = makeContainer(session);
      final router = container.read(appRouterProvider);
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _RouterApp(router: router),
        ),
      );
      // Safe here (unlike the bare leaked-timer guard file, which only takes
      // a bounded `pump`): every landed screen's data is settled
      // synchronously via the overrides above, so there is no unbounded
      // shimmer/animation to wait on.
      await tester.pumpAndSettle();
      return router;
    }

    group('/salons/:salonId/manage', () {
      testWidgets('SALON_OWNER is ADMITTED', (tester) async {
        final router = await pumpRouterAs(tester, _ownerSession);

        router.go(RouteNames.salonManage(_kSalonId));
        await tester.pumpAndSettle();

        expect(locationOf(router), equals('/salons/$_kSalonId/manage'));
        expect(find.byType(SalonManagementProfileScreen), findsOneWidget);
      });

      testWidgets('SALON_ADMIN is ADMITTED on their OWN salonId', (
        tester,
      ) async {
        final router = await pumpRouterAs(tester, _adminSession);

        router.go(RouteNames.salonManage(_kSalonId));
        await tester.pumpAndSettle();

        expect(locationOf(router), equals('/salons/$_kSalonId/manage'));
        expect(find.byType(SalonManagementProfileScreen), findsOneWidget);
      });

      testWidgets(
        'SALON_ADMIN is redirected to roleHomePath on a DIFFERENT salonId, '
        'never admitted',
        (tester) async {
          final router = await pumpRouterAs(tester, _otherSalonAdminSession);

          router.go(RouteNames.salonManage(_kSalonId));
          await tester.pumpAndSettle();

          expect(locationOf(router), equals(RouteNames.home));
          expect(find.byType(SalonManagementProfileScreen), findsNothing);
        },
      );

      testWidgets(
        'CLIENT is redirected to roleHomePath (RouteNames.clientHome), never '
        'admitted',
        (tester) async {
          final router = await pumpRouterAs(tester, _clientSession);

          router.go(RouteNames.salonManage(_kSalonId));
          await tester.pumpAndSettle();

          expect(locationOf(router), equals(RouteNames.clientHome));
          expect(find.byType(SalonManagementProfileScreen), findsNothing);
        },
      );

      testWidgets(
        'SALON_MASTER is redirected to roleHomePath (RouteNames.home), never '
        'admitted',
        (tester) async {
          final router = await pumpRouterAs(tester, _salonMasterSession);

          router.go(RouteNames.salonManage(_kSalonId));
          await tester.pumpAndSettle();

          expect(locationOf(router), equals(RouteNames.home));
          expect(find.byType(SalonManagementProfileScreen), findsNothing);
        },
      );

      testWidgets(
        'unauthenticated is redirected to /login by the global authRedirect '
        'gate',
        (tester) async {
          final router = await pumpRouterAs(tester, _unauthenticatedSession);

          router.go(RouteNames.salonManage(_kSalonId));
          await tester.pumpAndSettle();

          expect(locationOf(router), equals(RouteNames.login));
          expect(find.byType(SalonManagementProfileScreen), findsNothing);
        },
      );
    });

    group('/salons/:salonId/manage/settings', () {
      testWidgets('SALON_OWNER is ADMITTED', (tester) async {
        final router = await pumpRouterAs(tester, _ownerSession);

        router.go(RouteNames.salonManageSettings(_kSalonId));
        await tester.pumpAndSettle();

        expect(
          locationOf(router),
          equals('/salons/$_kSalonId/manage/settings'),
        );
        expect(find.byType(SalonSettingsScreen), findsOneWidget);
      });

      testWidgets('SALON_ADMIN is ADMITTED on their OWN salonId', (
        tester,
      ) async {
        final router = await pumpRouterAs(tester, _adminSession);

        router.go(RouteNames.salonManageSettings(_kSalonId));
        await tester.pumpAndSettle();

        expect(
          locationOf(router),
          equals('/salons/$_kSalonId/manage/settings'),
        );
        expect(find.byType(SalonSettingsScreen), findsOneWidget);
      });

      testWidgets(
        'SALON_ADMIN is redirected to roleHomePath on a DIFFERENT salonId, '
        'never admitted',
        (tester) async {
          final router = await pumpRouterAs(tester, _otherSalonAdminSession);

          router.go(RouteNames.salonManageSettings(_kSalonId));
          await tester.pumpAndSettle();

          expect(locationOf(router), equals(RouteNames.home));
          expect(find.byType(SalonSettingsScreen), findsNothing);
        },
      );

      testWidgets(
        'CLIENT is redirected to roleHomePath (RouteNames.clientHome), never '
        'admitted',
        (tester) async {
          final router = await pumpRouterAs(tester, _clientSession);

          router.go(RouteNames.salonManageSettings(_kSalonId));
          await tester.pumpAndSettle();

          expect(locationOf(router), equals(RouteNames.clientHome));
          expect(find.byType(SalonSettingsScreen), findsNothing);
        },
      );

      testWidgets(
        'SALON_MASTER is redirected to roleHomePath (RouteNames.home), never '
        'admitted',
        (tester) async {
          final router = await pumpRouterAs(tester, _salonMasterSession);

          router.go(RouteNames.salonManageSettings(_kSalonId));
          await tester.pumpAndSettle();

          expect(locationOf(router), equals(RouteNames.home));
          expect(find.byType(SalonSettingsScreen), findsNothing);
        },
      );

      testWidgets(
        'unauthenticated is redirected to /login by the global authRedirect '
        'gate',
        (tester) async {
          final router = await pumpRouterAs(tester, _unauthenticatedSession);

          router.go(RouteNames.salonManageSettings(_kSalonId));
          await tester.pumpAndSettle();

          expect(locationOf(router), equals(RouteNames.login));
          expect(find.byType(SalonSettingsScreen), findsNothing);
        },
      );
    });
  });
}
