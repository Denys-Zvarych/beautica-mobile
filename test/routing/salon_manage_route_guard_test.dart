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
//   • SALON_OWNER            → ADMITTED unconditionally when `mySalonsProvider`
//     has not resolved yet (the documented cold-deep-link fallback — see the
//     dedicated group below), OWNERSHIP-BOUND once it has (Phase 21.1 QA
//     follow-up — `salonManageGuard`'s `TODO(phase-21.1)` is now CLOSED:
//     `GET /salons/mine` exists and the guard's owner arm reads
//     `mySalonsProvider`'s resolved value).
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

import 'dart:async';

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
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
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/presentation/my_salons_screen.dart';
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

/// A SECOND salon `_kSalonId`'s owner does NOT own — for the ownership-bound
/// redirect group below (Phase 21.1 QA follow-up).
const String _kOtherOwnedSalonId = 'salon-guard-other-owned';

/// [MySalons] stub that resolves IMMEDIATELY to [salons] — mirrors
/// `salon_bookings_route_shadowing_test.dart`'s `_SettledMySalons`, but
/// parameterised so the ownership-bound cases below can control WHICH
/// salons the owner is resolved to own.
class _ResolvedMySalons extends MySalons {
  _ResolvedMySalons(this.salons);

  final List<Salon> salons;

  @override
  Future<List<Salon>> build() async => salons;
}

/// [MySalons] stub that NEVER resolves — pins the guard's documented
/// "not resolved yet -> ADMIT" fallback deliberately, rather than relying on
/// the accidental unresolved-by-omission shape every OTHER test in this file
/// gets from not overriding `mySalonsProvider` at all.
class _NeverResolvingMySalons extends MySalons {
  @override
  Future<List<Salon>> build() => Completer<List<Salon>>().future;
}

/// [MySalons] stub that resolves ONLY once [complete] is called — lets the
/// `_bounceIfNotOwned` test admit a cold deep link (mySalonsProvider still
/// unresolved when the route's `redirect:` runs, same as production), THEN
/// resolve to a list that excludes the mounted salon, observing the SCREEN's
/// own `ref.listen` bounce fire — closing the residual window the guard's
/// synchronous-redirect fallback leaves open.
class _DeferredMySalons extends MySalons {
  final Completer<List<Salon>> _completer = Completer<List<Salon>>();

  @override
  Future<List<Salon>> build() => _completer.future;

  void resolve(List<Salon> salons) => _completer.complete(salons);
}

/// [MySalons] stub that resolves to [previousSalons] on its FIRST build, then
/// THROWS on every subsequent rebuild — reproducing, without a second
/// `authProvider` emission, the exact state shape a real cross-account
/// refresh failure leaves behind (`my_salons_notifier_test.dart`'s
/// `_ControllableAuthNotifier`-driven "Owner A resolved, then session
/// drops"/"flips to Owner B" cascade IS the natural mechanism; this stub
/// constructs the same STATE directly since the crux under test here is
/// purely the shape `AsyncError(...).copyWithPrevious(AsyncData(...))`, not
/// how it arose): Riverpod's own `copyWithPrevious` keeps [previousSalons]
/// attached to `.value` on the resulting `AsyncError`. mobile-security
/// MEDIUM follow-up (2026-08-28) — see the guard's own comment in
/// `app_router.dart` for the full exploit narrative this pins.
class _StaleErrorMySalons extends MySalons {
  _StaleErrorMySalons(this.previousSalons);

  final List<Salon> previousSalons;
  int _buildCount = 0;

  @override
  Future<List<Salon>> build() async {
    _buildCount++;
    if (_buildCount == 1) return previousSalons;
    throw const NetworkFailure();
  }
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

    ProviderContainer makeContainer(
      AsyncValue<AuthSession> session, {
      // Phase 21.1 QA follow-up — optionally overrides `mySalonsProvider`
      // (a `@Riverpod(keepAlive: true)` CLASS provider) so the
      // ownership-bound SALON_OWNER cases can control what the guard (and,
      // for the bounce group, the screen) resolves the owner's salon list
      // to. `null` (every pre-existing test in this file) leaves it
      // UNOVERRIDDEN — the guard's `ref.read(mySalonsProvider).value` then
      // reads a genuinely un-initialized provider, exercising the SAME
      // "not resolved yet -> ADMIT" fallback the dedicated group below pins
      // deliberately (see `_NeverResolvingMySalons`'s own doc for why an
      // explicit stub is still worth having).
      MySalons Function()? mySalonsOverride,
    }) {
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          authProvider.overrideWith(() => _FixedAuthNotifier(session)),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
          if (mySalonsOverride != null)
            mySalonsProvider.overrideWith(mySalonsOverride),
          // Settles the ADMITTED-case screen's data fetch synchronously — see
          // [_SettledSalonManagementProfile]'s doc.
          salonManagementProfileProvider(
            _kSalonId,
          ).overrideWith(_SettledSalonManagementProfile.new),
          salonManagementProfileProvider(
            _kOtherOwnedSalonId,
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
      AsyncValue<AuthSession> session, {
      MySalons Function()? mySalonsOverride,
      // Phase 21.1 QA follow-up — an authenticated SALON_OWNER's global
      // splash->authenticated redirect now lands on RouteNames.mySalons
      // (role_home.dart) BEFORE this helper's caller ever calls
      // `router.go(...)`. When [mySalonsOverride] leaves `mySalonsProvider`
      // UNRESOLVED (the ownership-binding "not resolved yet" case, and both
      // `_bounceIfNotOwned` cases below), that transient MySalonsScreen
      // mount renders `_HubSkeleton` -> `SkeletonShimmerScope`, whose
      // `AnimationController` is `..repeat(reverse: true)` and never
      // settles — `pumpAndSettle()` on THIS initial mount would hang
      // forever. Pass `initialSettle: false` for those cases (a single
      // bounded `pump()` instead, mirroring
      // `salon_bookings_route_shadowing_test.dart`'s own precedent for the
      // identical transient-mount trap) — safe because the very next
      // `router.go(...)` in the test body navigates AWAY from
      // MySalonsScreen, disposing its shimmer controller before any
      // subsequent `pumpAndSettle()`.
      bool initialSettle = true,
    }) async {
      final container = makeContainer(
        session,
        mySalonsOverride: mySalonsOverride,
      );
      final router = container.read(appRouterProvider);
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _RouterApp(router: router),
        ),
      );
      if (initialSettle) {
        // Safe here (unlike the bare leaked-timer guard file, which only
        // takes a bounded `pump`): every landed screen's data is settled
        // synchronously via the overrides above, so there is no unbounded
        // shimmer/animation to wait on.
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
      }
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

    // -------------------------------------------------------------------
    // Phase 21.1 QA follow-up — the guard's SALON_OWNER arm is no longer
    // role-only: it now reads `mySalonsProvider`'s RESOLVED value and binds
    // the owner to the salons they actually own, closing the
    // `TODO(phase-21.1)` the Phase 21.2 arm left behind. Three cases:
    // resolved+owned -> ADMIT, resolved+NOT owned -> redirect,
    // unresolved -> ADMIT (the documented cold-deep-link fallback).
    //
    // MUTATION-VERIFIED (mobile-qa, 2026-08-28) — commenting out the
    // ownership `if (salons != null && !salons.any(...))` check in
    // `salonManageGuard` (`app_router.dart`) turns the "resolved+NOT owned"
    // case below RED (it stays admitted instead of redirecting) while the
    // OTHER two cases in this group stay green — restoring the check turns
    // it back GREEN with a clean `git diff`. See the QA report for the
    // exact commands run.
    // -------------------------------------------------------------------
    group('SALON_OWNER ownership binding (Phase 21.1 QA follow-up)', () {
      testWidgets(
        'mySalonsProvider RESOLVED and the route salonId IS in the list -> '
        'ADMITTED',
        (tester) async {
          final router = await pumpRouterAs(
            tester,
            _ownerSession,
            mySalonsOverride: () => _ResolvedMySalons(const <Salon>[
              _kSalon,
              Salon(id: _kOtherOwnedSalonId, name: 'Second Owned Salon'),
            ]),
          );

          router.go(RouteNames.salonManage(_kSalonId));
          await tester.pumpAndSettle();

          expect(locationOf(router), equals('/salons/$_kSalonId/manage'));
          expect(find.byType(SalonManagementProfileScreen), findsOneWidget);
        },
      );

      testWidgets(
        'mySalonsProvider RESOLVED and the route salonId is NOT in the list '
        '-> redirected to roleHomePath, never admitted',
        (tester) async {
          final router = await pumpRouterAs(
            tester,
            _ownerSession,
            mySalonsOverride: () => _ResolvedMySalons(const <Salon>[
              Salon(id: _kOtherOwnedSalonId, name: 'Second Owned Salon'),
            ]),
          );

          // `_kSalonId` is NOT in the resolved list above.
          router.go(RouteNames.salonManage(_kSalonId));
          await tester.pumpAndSettle();

          expect(locationOf(router), equals(RouteNames.mySalons));
          expect(find.byType(SalonManagementProfileScreen), findsNothing);
        },
      );

      testWidgets('mySalonsProvider still UNRESOLVED -> ADMITTED (documented '
          'cold-deep-link fallback — a redirect: callback must never await '
          'the network)', (tester) async {
        final router = await pumpRouterAs(
          tester,
          _ownerSession,
          mySalonsOverride: _NeverResolvingMySalons.new,
          initialSettle: false,
        );

        router.go(RouteNames.salonManage(_kSalonId));
        await tester.pumpAndSettle();

        expect(locationOf(router), equals('/salons/$_kSalonId/manage'));
        expect(find.byType(SalonManagementProfileScreen), findsOneWidget);
      });
    });

    // -------------------------------------------------------------------
    // Phase 21.1 QA follow-up — `SalonManagementProfileScreen._bounceIfNotOwned`
    // closes the guard's own "unresolved -> ADMIT" window: once
    // `mySalonsProvider` resolves to a list that excludes the mounted
    // `salonId`, the screen itself bounces the owner to `roleHomePath`
    // (`RouteNames.mySalons`) via `ref.listen`. This is the ONLY mechanism
    // that closes that window — the guard's own `redirect:` never re-runs on
    // its own after the initial navigation.
    // -------------------------------------------------------------------
    group('_bounceIfNotOwned (Phase 21.1 QA follow-up, closes the guard '
        'window)', () {
      testWidgets(
        'cold deep link is admitted (mySalonsProvider unresolved), then '
        'bounces to RouteNames.mySalons once it resolves EXCLUDING the '
        'mounted salonId',
        (tester) async {
          final deferred = _DeferredMySalons();
          final container = makeContainer(
            _ownerSession,
            mySalonsOverride: () => deferred,
          );
          final router = container.read(appRouterProvider);
          addTearDown(router.dispose);

          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: _RouterApp(router: router),
            ),
          );
          // Bounded pump, NOT pumpAndSettle — mySalonsProvider is still
          // unresolved at this point, so the transient MySalonsScreen
          // landing renders SkeletonShimmerScope's never-settling repeating
          // shimmer (see pumpRouterAs's own `initialSettle` doc for the full
          // rationale). The router.go(...) below navigates away from it
          // before any subsequent pumpAndSettle.
          await tester.pump();

          router.go(RouteNames.salonManage(_kSalonId));
          await tester.pumpAndSettle();

          // Admitted while unresolved — the guard's documented fallback.
          expect(locationOf(router), equals('/salons/$_kSalonId/manage'));
          expect(find.byType(SalonManagementProfileScreen), findsOneWidget);

          // Now resolve mySalonsProvider to a list that does NOT include
          // the mounted salonId — the screen's own ref.listen must bounce.
          deferred.resolve(const <Salon>[
            Salon(id: _kOtherOwnedSalonId, name: 'Second Owned Salon'),
          ]);
          await tester.pumpAndSettle();

          expect(
            locationOf(router),
            equals(RouteNames.mySalons),
            reason:
                '_bounceIfNotOwned must fire once mySalonsProvider resolves '
                'and the owner turns out not to own this salon',
          );
          expect(find.byType(SalonManagementProfileScreen), findsNothing);
          expect(find.byType(MySalonsScreen), findsOneWidget);
        },
      );

      testWidgets(
        'resolves INCLUDING the mounted salonId -> stays put, no bounce',
        (tester) async {
          final deferred = _DeferredMySalons();
          final container = makeContainer(
            _ownerSession,
            mySalonsOverride: () => deferred,
          );
          final router = container.read(appRouterProvider);
          addTearDown(router.dispose);

          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: _RouterApp(router: router),
            ),
          );
          // Bounded pump, NOT pumpAndSettle — mySalonsProvider is still
          // unresolved at this point, so the transient MySalonsScreen
          // landing renders SkeletonShimmerScope's never-settling repeating
          // shimmer (see pumpRouterAs's own `initialSettle` doc for the full
          // rationale). The router.go(...) below navigates away from it
          // before any subsequent pumpAndSettle.
          await tester.pump();

          router.go(RouteNames.salonManage(_kSalonId));
          await tester.pumpAndSettle();

          deferred.resolve(const <Salon>[_kSalon]);
          await tester.pumpAndSettle();

          expect(locationOf(router), equals('/salons/$_kSalonId/manage'));
          expect(find.byType(SalonManagementProfileScreen), findsOneWidget);
        },
      );
    });

    // -------------------------------------------------------------------
    // mobile-security MEDIUM follow-up (2026-08-28) — `salonManageGuard`'s
    // SALON_OWNER arm used to trust `ref.read(mySalonsProvider).value`
    // regardless of whether the STATE it came from was genuinely resolved.
    // Riverpod's `copyWithPrevious` keeps the previous `AsyncData`'s `.value`
    // attached to a LATER `AsyncError` (e.g. right after a cross-account
    // login on the same device — owner A logs out, owner B logs in, no app
    // restart — while `mySalonsProvider` refetches and fails). A `.value`
    // read alone cannot distinguish that stale-but-present value from a
    // genuinely resolved one, so the guard's ownership check could fire
    // against DATA FROM A DIFFERENT ACCOUNT.
    //
    // This group pins the fix: the guard now only trusts `.value` when the
    // state is the concrete `AsyncData` subtype. An `AsyncError` — even one
    // whose `.value` still carries a stale list — must fall through to the
    // SAME "not resolved yet -> ADMIT" fallback a genuine cold deep link
    // gets, never to the ownership-bound branch.
    //
    // Why the mismatched-list shape (not a matching one) is what actually
    // PROVES the fix: when the stale `.value` happens to CONTAIN the route's
    // salonId, both the old (`.value`-trusting) and new (`AsyncData`-gated)
    // code land on the same observable outcome — ADMIT — just for different
    // (one wrong, one right) reasons a router-outcome assertion cannot tell
    // apart. The old bug is only OBSERVABLE, and therefore only
    // mutation-provable, when the stale `.value` does NOT contain the
    // route's salonId: the old code reads that as "resolved AND not owned"
    // and wrongly REDIRECTS a legitimate owner away from their own salon
    // based on another account's leftover cache; the fixed code correctly
    // reads the AsyncError as unresolved and ADMITS, exactly like a cold
    // deep link.
    //
    // MUTATION-VERIFIED (2026-08-28) — reverting `app_router.dart`'s
    // `AsyncData<List<Salon>>` type-gate back to a bare `.value` read turns
    // this test RED (it redirects to `RouteNames.mySalons` instead of
    // admitting); restoring the gate turns it back GREEN with a clean `git
    // diff`.
    group('SALON_OWNER ownership binding does not trust a stale .value '
        '(mobile-security MEDIUM follow-up)', () {
      testWidgets('AsyncError with a previous .value that does NOT contain the '
          'route salonId is treated as UNRESOLVED -> ADMITTED, never as '
          'resolved-and-not-owned', (tester) async {
        final stale = _StaleErrorMySalons(const <Salon>[
          Salon(id: _kOtherOwnedSalonId, name: 'Second Owned Salon'),
        ]);
        final container = makeContainer(
          _ownerSession,
          mySalonsOverride: () => stale,
        );
        final router = container.read(appRouterProvider);
        addTearDown(router.dispose);

        // Resolve the FIRST build to AsyncData — the "owner A" snapshot.
        final List<Salon> firstResolved = await container.read(
          mySalonsProvider.future,
        );
        expect(
          firstResolved,
          equals(const <Salon>[
            Salon(id: _kOtherOwnedSalonId, name: 'Second Owned Salon'),
          ]),
        );
        expect(container.read(mySalonsProvider), isA<AsyncData<List<Salon>>>());

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: _RouterApp(router: router),
          ),
        );
        await tester.pumpAndSettle();

        // Force a rebuild that THROWS — Riverpod's own `copyWithPrevious`
        // keeps the just-resolved (mismatched) list attached to the
        // resulting AsyncError's `.value`, exactly the shape a real
        // cross-account refresh failure leaves behind.
        container.invalidate(mySalonsProvider);
        await tester.pump();
        await tester.pump();

        final AsyncValue<List<Salon>> midState = container.read(
          mySalonsProvider,
        );
        expect(
          midState,
          isA<AsyncError<List<Salon>>>(),
          reason:
              'the rebuild must actually fail for this test to exercise '
              'the AsyncError-with-stale-.value shape',
        );
        expect(
          midState.value,
          isNotNull,
          reason:
              'copyWithPrevious must retain the stale list on .value — '
              'this IS the exploitable shape the fix guards against',
        );
        expect(
          midState.value!.any((Salon s) => s.id == _kSalonId),
          isFalse,
          reason:
              'the stale snapshot deliberately does NOT contain the '
              'route salonId — this is the mismatched case that makes '
              'the old bug OBSERVABLE (see group doc)',
        );

        router.go(RouteNames.salonManage(_kSalonId));
        await tester.pumpAndSettle();

        expect(
          locationOf(router),
          equals('/salons/$_kSalonId/manage'),
          reason:
              'an AsyncError state must be treated as UNRESOLVED — same '
              'as a cold deep link — never as a resolved-and-not-owned '
              'redirect target sourced from a stale, possibly '
              'cross-account, cached value',
        );
        expect(find.byType(SalonManagementProfileScreen), findsOneWidget);
      });
    });
  });
}
