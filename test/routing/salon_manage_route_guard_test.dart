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
import 'package:beautica_mobile/features/salon/application/salon_staff_member_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/presentation/my_salons_screen.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_management_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_settings_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_staff_profile_screen.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
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
      (_kSalon, const <SalonStaffMember>[]);
}

// mobile-security LOW follow-up (2026-08-29) — `/salons/:salonId/manage/
// staff/:memberId` (Phase 21.5) reused `salonManageGuard` VERBATIM but had
// ZERO route-guard test coverage of its own: the ONE route in this app that
// reaches the unmasked-staff-PII endpoint (`GET /salons/{salonId}/staff`,
// phone numbers included) was never proven to actually admit/reject the same
// way `/manage` and `/manage/settings` do. See this file's own header doc —
// before ANY guard test existed, the guard could be deleted and every OTHER
// test in the suite stayed green.
const String _kMemberId = 'staff-guard-member-1';

const _kStaffMember = SalonStaffMember(
  userId: _kMemberId,
  masterId: 'master-row-guard-1',
  role: SalonStaffRole.master,
  firstName: 'Guard',
  lastName: 'Member',
);

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
          // Phase 21.8 — `_otherSalonAdminSession`'s roleHomePath now
          // forwards (via the Salon Shell resolver) to THEIR OWN salon
          // (`salon-guard-2`, `_otherSalonAdminUser.salonId`), mounting the
          // shell's embedded Салон/Команда tabs. Settle it the same way, or
          // that transient landing hits the real Dio-backed
          // `salonRepositoryProvider`.
          salonManagementProfileProvider(
            'salon-guard-2',
          ).overrideWith(_SettledSalonManagementProfile.new),
          // Settles `/manage/staff/:memberId`'s own data source
          // (`salonStaffMemberProfileProvider`, a plain FutureProvider
          // family — not a class provider, so `.overrideWith((ref) async =>
          // ...)`, unlike the class-provider overrides above) synchronously,
          // for the SAME leaked-Dio-request-avoidance reason.
          salonStaffMemberProfileProvider(_kSalonId, _kMemberId).overrideWith(
            (ref) async => (_kStaffMember, const <MasterService>[]),
          ),
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

          // Phase 21.8 — roleHomePath(salonAdmin) now resolves to the shared
          // Salon Shell landing, which forwards the admin to THEIR OWN salon
          // (`salon-guard-2`, [_otherSalonAdminUser]'s `User.salonId`) — never
          // the requested `_kSalonId`.
          expect(
            locationOf(router),
            equals(RouteNames.salonShell('salon-guard-2')),
          );
          expect(
            find.byWidgetPredicate(
              (Widget w) =>
                  w is SalonManagementProfileScreen && w.salonId == _kSalonId,
            ),
            findsNothing,
            reason: 'the unrequested salonId must never be admitted',
          );
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

    // -------------------------------------------------------------------
    // mobile-security LOW follow-up (2026-08-29) — `/salons/:salonId/manage/
    // staff/:memberId` reuses `salonManageGuard` VERBATIM (see
    // `app_router.dart`'s own Phase 21.5 comment on that `GoRoute`), so its
    // ownership-binding behaviour is already fully proven by the `/manage`
    // group above and the dedicated ownership-binding groups further below
    // — this group only confirms the SAME guard is actually WIRED onto this
    // leaf, asserting on the resolved page TYPE (not just the URL), per
    // this codebase's documented go_router trap: declaration order alone
    // can make a literal route win, and a dynamic sibling absorbing the
    // path would leave the URL assertion green while the WRONG screen
    // mounted.
    // -------------------------------------------------------------------
    group('/salons/:salonId/manage/staff/:memberId (Phase 21.5)', () {
      testWidgets('SALON_OWNER is ADMITTED', (tester) async {
        final router = await pumpRouterAs(tester, _ownerSession);

        router.go(RouteNames.salonManageStaffMember(_kSalonId, _kMemberId));
        await tester.pumpAndSettle();

        expect(
          locationOf(router),
          equals('/salons/$_kSalonId/manage/staff/$_kMemberId'),
        );
        expect(
          find.byWidgetPredicate(
            (Widget w) =>
                w is SalonStaffProfileScreen &&
                w.salonId == _kSalonId &&
                w.memberId == _kMemberId,
          ),
          findsOneWidget,
        );
      });

      testWidgets('SALON_ADMIN is ADMITTED on their OWN salonId', (
        tester,
      ) async {
        final router = await pumpRouterAs(tester, _adminSession);

        router.go(RouteNames.salonManageStaffMember(_kSalonId, _kMemberId));
        await tester.pumpAndSettle();

        expect(
          locationOf(router),
          equals('/salons/$_kSalonId/manage/staff/$_kMemberId'),
        );
        expect(
          find.byWidgetPredicate(
            (Widget w) =>
                w is SalonStaffProfileScreen &&
                w.salonId == _kSalonId &&
                w.memberId == _kMemberId,
          ),
          findsOneWidget,
        );
      });

      testWidgets(
        'SALON_ADMIN is redirected to roleHomePath on a DIFFERENT salonId, '
        'never admitted',
        (tester) async {
          final router = await pumpRouterAs(tester, _otherSalonAdminSession);

          router.go(RouteNames.salonManageStaffMember(_kSalonId, _kMemberId));
          await tester.pumpAndSettle();

          // Phase 21.8 — see the identical `/manage` case above.
          expect(
            locationOf(router),
            equals(RouteNames.salonShell('salon-guard-2')),
          );
          expect(
            find.byWidgetPredicate(
              (Widget w) =>
                  w is SalonStaffProfileScreen && w.salonId == _kSalonId,
            ),
            findsNothing,
            reason: 'the unrequested salonId must never be admitted',
          );
        },
      );

      testWidgets(
        'CLIENT is redirected to roleHomePath (RouteNames.clientHome), never '
        'admitted',
        (tester) async {
          final router = await pumpRouterAs(tester, _clientSession);

          router.go(RouteNames.salonManageStaffMember(_kSalonId, _kMemberId));
          await tester.pumpAndSettle();

          expect(locationOf(router), equals(RouteNames.clientHome));
          expect(find.byType(SalonStaffProfileScreen), findsNothing);
        },
      );

      testWidgets(
        'SALON_MASTER is redirected to roleHomePath (RouteNames.home), never '
        'admitted',
        (tester) async {
          final router = await pumpRouterAs(tester, _salonMasterSession);

          router.go(RouteNames.salonManageStaffMember(_kSalonId, _kMemberId));
          await tester.pumpAndSettle();

          expect(locationOf(router), equals(RouteNames.home));
          expect(find.byType(SalonStaffProfileScreen), findsNothing);
        },
      );

      testWidgets(
        'unauthenticated is redirected to /login by the global authRedirect '
        'gate',
        (tester) async {
          final router = await pumpRouterAs(tester, _unauthenticatedSession);

          router.go(RouteNames.salonManageStaffMember(_kSalonId, _kMemberId));
          await tester.pumpAndSettle();

          expect(locationOf(router), equals(RouteNames.login));
          expect(find.byType(SalonStaffProfileScreen), findsNothing);
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

          // Phase 21.8 — see the identical `/manage` case above.
          expect(
            locationOf(router),
            equals(RouteNames.salonShell('salon-guard-2')),
          );
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
    // mobile-qa gap-closure (2026-08-28) — `/salons/:salonId/shell`
    // (Phase 21.8) had NO route-guard coverage at all: `salonManageGuard` is
    // reused VERBATIM for this route (see `app_router.dart`'s own comment on
    // that `GoRoute`), so its ownership-binding behaviour is already proven
    // by every group above — this one just confirms the SAME guard is
    // actually WIRED onto `/shell`, asserting on `SalonShellScreen` (not
    // `SalonManagementProfileScreen`, which the shell also mounts internally
    // for its Салон tab — asserting on the wrong type here would pass for
    // the wrong reason).
    // -------------------------------------------------------------------
    group('/salons/:salonId/shell (Phase 21.8 — reuses salonManageGuard)', () {
      testWidgets('SALON_OWNER is ADMITTED on a salon they own', (
        tester,
      ) async {
        final router = await pumpRouterAs(
          tester,
          _ownerSession,
          mySalonsOverride: () => _ResolvedMySalons(const <Salon>[_kSalon]),
        );

        router.go(RouteNames.salonShell(_kSalonId));
        await tester.pumpAndSettle();

        expect(locationOf(router), equals('/salons/$_kSalonId/shell'));
        expect(find.byType(SalonShellScreen), findsOneWidget);
      });

      testWidgets(
        'SALON_OWNER is redirected away from a salon they do NOT own, '
        'never admitted',
        (tester) async {
          final router = await pumpRouterAs(
            tester,
            _ownerSession,
            mySalonsOverride: () => _ResolvedMySalons(const <Salon>[
              Salon(id: _kOtherOwnedSalonId, name: 'Second Owned Salon'),
            ]),
          );

          // `_kSalonId` is NOT in the resolved list above.
          router.go(RouteNames.salonShell(_kSalonId));
          await tester.pumpAndSettle();

          expect(
            locationOf(router),
            equals(RouteNames.salonShell(_kOtherOwnedSalonId)),
            reason:
                'roleHomePath(salonOwner) forwards, via the Salon Home '
                'resolver, to a salon the owner actually owns — never the '
                'requested, unowned $_kSalonId',
          );
          expect(
            find.byWidgetPredicate(
              (Widget w) => w is SalonShellScreen && w.salonId == _kSalonId,
            ),
            findsNothing,
            reason: 'the unowned salonId must never be admitted',
          );
        },
      );

      testWidgets('SALON_ADMIN is ADMITTED on their OWN salonId', (
        tester,
      ) async {
        final router = await pumpRouterAs(tester, _adminSession);

        router.go(RouteNames.salonShell(_kSalonId));
        await tester.pumpAndSettle();

        expect(locationOf(router), equals('/salons/$_kSalonId/shell'));
        expect(find.byType(SalonShellScreen), findsOneWidget);
      });

      testWidgets('SALON_ADMIN is redirected to their OWN salon on a DIFFERENT '
          'salonId, never admitted to the requested one', (tester) async {
        final router = await pumpRouterAs(tester, _otherSalonAdminSession);

        router.go(RouteNames.salonShell(_kSalonId));
        await tester.pumpAndSettle();

        expect(
          locationOf(router),
          equals(RouteNames.salonShell('salon-guard-2')),
        );
        expect(
          find.byWidgetPredicate(
            (Widget w) => w is SalonShellScreen && w.salonId == _kSalonId,
          ),
          findsNothing,
          reason: 'the unrequested salonId must never be admitted',
        );
      });
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

          // Phase 21.8 — roleHomePath(salonOwner) now resolves through the
          // Salon Shell landing (a transient resolver), which forwards to
          // the salon the owner actually owns (`_kOtherOwnedSalonId`, the
          // list's only entry) — never the requested, unowned `_kSalonId`.
          expect(
            locationOf(router),
            equals(RouteNames.salonShell(_kOtherOwnedSalonId)),
          );
          expect(
            find.byWidgetPredicate(
              (Widget w) =>
                  w is SalonManagementProfileScreen && w.salonId == _kSalonId,
            ),
            findsNothing,
            reason: 'the unowned salonId must never be admitted',
          );
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

          // Phase 21.8 — `_bounceIfNotOwned` still calls
          // `context.go(roleHomePath(role))`, but that now resolves to the
          // Salon Shell landing, which forwards to the salon the owner
          // actually owns (`_kOtherOwnedSalonId`) rather than the old
          // `RouteNames.mySalons` hub.
          expect(
            locationOf(router),
            equals(RouteNames.salonShell(_kOtherOwnedSalonId)),
            reason:
                '_bounceIfNotOwned must fire once mySalonsProvider resolves '
                'and the owner turns out not to own this salon',
          );
          expect(
            find.byWidgetPredicate(
              (Widget w) =>
                  w is SalonManagementProfileScreen && w.salonId == _kSalonId,
            ),
            findsNothing,
          );
          expect(find.byType(MySalonsScreen), findsNothing);
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
        //
        // Phase 21.8 — the initial landing now goes THROUGH the Salon Shell
        // resolver, which (unlike the old direct `MySalonsScreen` landing)
        // does not stay mounted watching `mySalonsProvider` once it has
        // forwarded onward — its embedded `SalonManagementProfileScreen`
        // children skip `_bounceIfNotOwned` (H1b) entirely, so nothing in
        // the mounted tree watches `mySalonsProvider` any more. With no
        // active widget watcher, bare `tester.pump()`s no longer drive the
        // invalidated rebuild forward (pre-Phase-21.8, `MySalonsScreen`'s own
        // `ref.watch` did). Await the provider's own `.future` instead — this
        // reads (and thus drives) the CURRENT rebuild directly, regardless of
        // whether anything is watching it.
        container.invalidate(mySalonsProvider);
        await container.read(mySalonsProvider.future).catchError((_) {
          return const <Salon>[];
        });
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
