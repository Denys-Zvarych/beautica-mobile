// mobile-qa re-audit (cycle 2, 2026-09-05) — `resolvedSession()`'s
// stale-value rejection, pinned at the THREE call sites whose behaviour the
// Phase 21.16 fix pass changed as COLLATERAL.
//
// WHAT CHANGED, AND WHY IT WAS UNCOVERED
// ---------------------------------------------------------------------------
// `app_router.dart:236` introduced one shared helper:
//
//     AuthSession? resolvedSession() {
//       final AsyncValue<AuthSession> auth = ref.read(authProvider);
//       return auth is AsyncData<AuthSession> ? auth.value : null;
//     }
//
// and rewired FOUR guards onto it. `salonAdminOnlyGuard` is new in Phase
// 21.16; the other three — `clientOnlyGuard` (`/masters/*`, `/salons/:id`,
// the `/booking/*` family), `mySalonsGuard` (`/salons/mine`,
// `/profile/owner`) and `salonHomeGuard` (`/salons/home`) — were SHIPPED
// guards that previously read a bare `ref.read(authProvider).value`. Their
// behaviour was changed by a sweep, not by a phase.
//
// Riverpod's `copyWithPrevious` keeps a settled `AsyncData`'s value attached
// to a LATER `AsyncError` (and to a mid-retry `AsyncLoading`), so `.value` can
// still be the PREVIOUS account's session for a frame after a same-device
// account switch — user A logs out, user B logs in, `/users/me` refetch fails,
// no app restart. A role gate reading that value decides with the wrong role,
// which is the exact inverse of its intent. The helper rejects it.
//
// MEASURED, not assumed (2026-09-05): with `resolvedSession()`'s body reverted
// to `return ref.read(authProvider).value;`, the ENTIRE `test/routing/` suite
// — 415 tests — stayed GREEN. Every existing guard test feeds the router
// either an `AsyncData` or a value-less `AsyncLoading`, and for both of those
// the buggy read and the fixed read return the IDENTICAL thing. The sweep was
// therefore completely unpinned: a mistake in it could not have been caught.
// This file is what makes it catchable.
//
// SHAPE OF EVERY TEST HERE
// ---------------------------------------------------------------------------
//   1. Settle `authProvider` to `AsyncData(Authenticated(INDEPENDENT_MASTER))`
//      — the "previous account" snapshot. Without a settled value to carry,
//      the error below would have a null `.value` and the two reads would
//      agree again, defanging the whole file.
//   2. Drive the PRODUCTION transition (`state = AsyncError(e, st)`, the same
//      assignment `AuthNotifier` makes on a failed refresh) and let Riverpod's
//      own `asyncTransition` do the carry-forward. This is not a simulation of
//      the bug shape; it IS the bug shape.
//   3. Assert the shape BEFORE navigating — terminal `AsyncError` (never just
//      `hasError`, which a mid-retry `AsyncLoading` also satisfies), a
//      non-null `Authenticated` `.value`, and a role the guard under test
//      BOUNCES.
//   4. Navigate, and assert the RESOLVED PAGE TYPE.
//
// WHY THE STALE ROLE IS ALWAYS INDEPENDENT_MASTER
// ---------------------------------------------------------------------------
// It is the one role every one of these three guards rejects, so the buggy
// `.value` read and the fixed read land on visibly DIFFERENT pages in all
// three cases: the bug bounces to `roleHomePath(independentMaster)` ==
// `/master/profile`, the fix admits. Had the carried-forward session been a
// role the guard admits, both reads would produce the same observable outcome
// for different (one wrong, one right) reasons and no router assertion could
// tell them apart — the same trap `salon_manage_route_guard_test.dart`'s own
// stale-value group documents for `mySalonsProvider`.
//
// `router.go` (not `context.push`) throughout, deliberately: these tests
// assert a redirect DECISION and a resolved page type, not a nav-move
// detection keyed off `GoRouterState.fullPath` — which is the case that needs
// `push`. Every shipped guard test in this directory drives `go` for the same
// reason.
//
// MUTATION-VERIFIED (2026-09-05) — reverting `resolvedSession()` to
// `return ref.read(authProvider).value;` turns ALL THREE tests RED
// (`MasterProfileScreen` renders in place of each admitted destination);
// restoring it turns them GREEN.

import 'dart:async';

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/features/master/presentation/public_master_profile_screen.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/presentation/my_salons_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_home_resolver_screen.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_master_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import '../helpers/fakes/fake_service_repository.dart';

const String _kMasterId = 'master-stale-1';

/// The PREVIOUS account. INDEPENDENT_MASTER is the role every guard under test
/// bounces — see this file's header for why that is load-bearing.
const User _previousAccount = User(
  id: 'u-master-prev',
  email: 'previous@beautica.test',
  role: UserRole.independentMaster,
  firstName: 'Попередній',
  lastName: 'Акаунт',
);

/// Settles to an [Authenticated] session for [user], then lets the test body
/// drive a REAL post-settle transition.
///
/// A notifier whose `build()` is an `async` body that RETURNS cannot express
/// this shape: Riverpod overwrites whatever `state` it assigned with an
/// `AsyncData` on the next microtask. The `AsyncError`-carrying-a-stale-value
/// shape can only be produced the way production produces it — by assigning
/// `state` AFTER the build has settled, which is what `AuthNotifier` does when
/// a token refresh / `/users/me` re-read fails.
///
/// Mirrors `test/features/auth/presentation/auth_selectors_test.dart`'s
/// notifier of the same name — same mechanism, one layer up (the router guard
/// instead of the role selector).
class _TransitionableAuthNotifier extends AuthNotifier {
  _TransitionableAuthNotifier(this.user);

  final User user;

  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: user, accessToken: 'token');

  /// The SAME `state = AsyncError(e, st)` assignment production
  /// `AuthNotifier` makes. Riverpod's own `asyncTransition` (`onError`,
  /// `seamless: false`) carries the previously settled `.value` FORWARD onto
  /// the resulting `AsyncError`.
  void forceError(Object error) {
    state = AsyncError<AuthSession>(error, StackTrace.current);
  }
}

/// Zero salons on purpose. `/salons/mine` then renders its empty state (no
/// shell, no per-salon reads) — a light, fully overridden screen rather than
/// the salon shell. It ALSO makes the `/salons/home` case safe to assert
/// negatively: were the resolver ever to dispatch on the stale session again,
/// its owner arm's zero-salons fallback is the hub, so this override keeps
/// that regression landing on an overridden page instead of a live read.
class _EmptyMySalons extends MySalons {
  @override
  Future<List<Salon>> build() async => const <Salon>[];
}

/// Settles the `/master/profile` BOUNCE destination — the page that renders in
/// place of every admitted one when the fix is reverted — without a real
/// `GET /masters/me`.
class _SettledMasterProfile extends MasterProfile {
  @override
  Future<Master> build() async => const Master(
    id: 'master-row-1',
    firstName: 'Тест',
    lastName: 'Майстер',
    avgRating: 0,
    reviewCount: 0,
    type: MasterType.independentMaster,
  );
}

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
  group('resolvedSession() — an AsyncError carrying a stale AsyncData session '
      'is UNRESOLVED, never a role', () {
    setUp(
      () => AppStartTime.setStartForTest(
        DateTime.now().subtract(const Duration(seconds: 5)),
      ),
    );
    tearDown(AppStartTime.resetForTest);

    late _TransitionableAuthNotifier notifier;

    /// `Object`, not `Override`: Riverpod 3.x does not export `Override` from
    /// `flutter_riverpod`, so the list is built loosely and `.cast()` at the
    /// container boundary infers the target — the same dodge
    /// `test/helpers/pump_app.dart` documents.
    ProviderContainer makeContainer() {
      notifier = _TransitionableAuthNotifier(_previousAccount);
      final container = ProviderContainer(
        // No retry curve: an AsyncError must stay terminal for the frame under
        // test rather than immediately re-entering AsyncLoading.
        retry: (_, _) => null,
        overrides: <Object>[
          authProvider.overrideWith(() => notifier),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
          // ── admitted destinations ──────────────────────────────────────
          mySalonsProvider.overrideWith(_EmptyMySalons.new),
          // `/masters/:masterId` only has to MOUNT far enough for the router
          // to resolve its page — no data assertion here, so a never-settling
          // future keeps every repository and Dio call out of the test.
          publicMasterProfileProvider(_kMasterId).overrideWith(
            (Ref ref) => Completer<PublicMasterProfileData>().future,
          ),
          // ── the BOUNCE destination (/master/profile) ───────────────────
          // Settled so that the REVERTED code fails on the assertion rather
          // than on a live Dio connect-timeout Timer outliving the test.
          masterProfileProvider.overrideWith(_SettledMasterProfile.new),
          masterRepositoryProvider.overrideWith((_) => FakeMasterRepository()),
          serviceRepositoryProvider.overrideWith(
            (_) => FakeServiceRepository(),
          ),
          // MasterProfileScreen's categories section bypasses
          // `serviceRepositoryProvider` and builds on the real authenticated
          // Dio, so it needs its own settle.
          approvedCategoriesProvider.overrideWith(
            (ref) async => const <ServiceCategoryOption>[],
          ),
        ].cast(),
      );
      addTearDown(container.dispose);
      return container;
    }

    /// Mounts the REAL router, settles the session to `AsyncData`, then drives
    /// the production `state = AsyncError(...)` transition and PROVES the
    /// resulting shape is the one under test before handing the router back.
    Future<GoRouter> pumpRouterOnStaleSession(WidgetTester tester) async {
      final ProviderContainer container = makeContainer();
      final GoRouter router = container.read(appRouterProvider);
      addTearDown(router.dispose);

      await container.read(authProvider.future);
      expect(container.read(authProvider), isA<AsyncData<AuthSession>>());

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _RouterApp(router: router),
        ),
      );
      await tester.pumpAndSettle();

      notifier.forceError(const ServerFailure());
      await tester.pumpAndSettle();

      final AsyncValue<AuthSession> stale = container.read(authProvider);
      expect(
        stale,
        isA<AsyncError<AuthSession>>(),
        reason:
            'the terminal error SUBTYPE, not merely `hasError` — a mid-retry '
            'AsyncLoading reports hasError == true too, so a hasError-only '
            'check could not say which state this is.',
      );
      expect(
        stale.value,
        isA<Authenticated>(),
        reason:
            'copyWithPrevious must retain the settled session on `.value`. '
            'This IS the shape resolvedSession() exists to reject; if it were '
            'null every guard below would admit for a DIFFERENT reason and '
            'this whole file would pin nothing.',
      );
      expect(
        (stale.value! as Authenticated).user.role,
        UserRole.independentMaster,
        reason:
            'and the carried-forward role must be one the guards BOUNCE, or '
            'the buggy `.value` read would admit too and no test here could '
            'go red under mutation.',
      );

      return router;
    }

    testWidgets('clientOnlyGuard — /masters/:masterId is ADMITTED, not '
        'bounced on the previous account\'s INDEPENDENT_MASTER role', (
      tester,
    ) async {
      final GoRouter router = await pumpRouterOnStaleSession(tester);

      router.go(RouteNames.masterPublicProfile(_kMasterId));
      // fixed-wait-ok (pump-bounded): the admitted destination is pinned to a
      // never-completing future, so it renders `SkeletonShimmerScope`'s
      // REPEATING shimmer and `pumpAndSettle` can never return (measured: it
      // times out). Pump until the page mounts instead of guessing a duration
      // — bounded, so the reverted code (which never mounts it at all) still
      // fails fast on the assertion below rather than hanging.
      for (
        int i = 0;
        i < 20 && find.byType(PublicMasterProfileScreen).evaluate().isEmpty;
        i++
      ) {
        // fixed-wait-ok: one 50 ms step of the bounded loop above — the
        // step itself is arbitrary; the LOOP is the wait.
        await tester.pump(const Duration(milliseconds: 50));
      }
      // fixed-wait-ok: run the OUTGOING page transition to completion. `go`
      // keeps the previous route mounted for the length of its exit
      // animation, so without advancing past it the `MasterProfileScreen`
      // deny-assertion below would report the landing page mid-exit and fail
      // for a reason that has nothing to do with the guard.
      await tester.pump(const Duration(milliseconds: 600));

      expect(
        find.byType(PublicMasterProfileScreen),
        findsOneWidget,
        reason:
            'the resolved PAGE TYPE. An unresolved session is not a role: the '
            'guard must wave the frame through and let the settled '
            're-evaluation decide.',
      );
      expect(
        find.byType(MasterProfileScreen),
        findsNothing,
        reason:
            'this is where a bare `.value` read lands — it reads the previous '
            'account\'s INDEPENDENT_MASTER as current and bounces to '
            'roleHomePath(independentMaster).',
      );
    });

    testWidgets('mySalonsGuard — /salons/mine is ADMITTED, not bounced on the '
        'previous account\'s INDEPENDENT_MASTER role', (tester) async {
      final GoRouter router = await pumpRouterOnStaleSession(tester);

      router.go(RouteNames.mySalons);
      await tester.pumpAndSettle();

      expect(
        find.byType(MySalonsScreen),
        findsOneWidget,
        reason:
            'the OWNER hub\'s own screen type, never merely a matching '
            'location string — `/salons/mine` is a literal declared before '
            'the dynamic `/salons/:salonId`, which would absorb the path and '
            'go on reporting the same URI (see '
            'my_salons_route_shadowing_test.dart).',
      );
      expect(find.byType(MasterProfileScreen), findsNothing);
    });

    testWidgets('salonHomeGuard — /salons/home is ADMITTED, not bounced on the '
        'previous account\'s INDEPENDENT_MASTER role', (tester) async {
      final GoRouter router = await pumpRouterOnStaleSession(tester);

      router.go(RouteNames.salonHome);

      // Asserted BEFORE any pump: go_router runs `redirect:` synchronously
      // inside `go`, so a bounce is already visible here — and this is the
      // assertion that is about the GUARD alone, independent of what
      // SalonHomeResolverScreen does afterwards.
      expect(
        // This test only ever calls `.go`, never `context.push`, so no
        // ImperativeRouteMatch is on the stack and the raw read reports the
        // real post-redirect location. It pins the ABSENCE of a redirect,
        // which no route shadowing can manufacture.
        // router-location-ok: `.go` only — see just above.
        router.routerDelegate.currentConfiguration.uri.toString(),
        RouteNames.salonHome,
        reason:
            'the guard must NOT have redirected — a bare `.value` read would '
            'already show /master/profile at this point.',
      );

      // fixed-wait-ok (pump-bounded): `SalonHomeResolverScreen` HOLDS its
      // loading skeleton
      // on an unresolved session (see the assertions below), and
      // `SkeletonShimmerScope`'s shimmer repeats forever — `pumpAndSettle` can
      // never return. Bounded pumps instead, and generously: the resolver
      // forwards from a POST-FRAME callback, so anything shorter could report
      // "did not forward" simply by not having pumped the frame that would.
      for (int i = 0; i < 20; i++) {
        // fixed-wait-ok: one 50 ms step of the bounded loop above — the
        // step itself is arbitrary; the LOOP is the wait.
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(
        find.byType(MasterProfileScreen),
        findsNothing,
        reason:
            'and the admitted frame must not end up on the bounce landing '
            'either — the guard admitting is not licence for anything '
            'downstream to route on roleHomePath(independentMaster).',
      );
      // mobile-qa MEDIUM (cycle 2, 2026-09-05) — this assertion INVERTED.
      //
      // It used to demand `MySalonsScreen`, on the reasoning that an admitted
      // frame should reach "a real destination rather than a blank page". That
      // reasoning was wrong, and the guard change in this same phase is what
      // made it dangerous: `salonHomeGuard` now deliberately admits an
      // unresolved session, so whatever the resolver does next runs on the
      // PREVIOUS account's role. Reaching the hub here meant the resolver had
      // read the stale session and DISPATCHED on it — harmless for this
      // fixture's INDEPENDENT_MASTER (it lands on the owner arm and finds zero
      // salons), but the same code path takes a stale SALON_ADMIN straight
      // into `session.user.salonId`'s shell, i.e. another account's salon.
      //
      // The resolver now applies the same concrete-subtype gate the guard does
      // and holds its skeleton until the session settles, so "no forward at
      // all" is the correct outcome, and a forward — to EITHER destination —
      // is the regression. Pinned directly in
      // `test/features/salon/presentation/salon_home_resolver_screen_test.dart`
      // with the SALON_ADMIN role that makes the leak observable.
      expect(
        find.byType(MySalonsScreen),
        findsNothing,
        reason:
            'the resolver must not dispatch on a stale session at all — '
            'reaching the hub means it read the previous account\'s role and '
            'took its owner arm.',
      );
      expect(
        find.byType(SalonHomeResolverScreen),
        findsOneWidget,
        reason:
            'it holds, rather than crashing or rendering blank — the '
            'positive half of "no forward", so an exception during build '
            'cannot pass as a passing test.',
      );
      expect(
        // router-location-ok: `.go` only, as above.
        router.routerDelegate.currentConfiguration.uri.toString(),
        RouteNames.salonHome,
        reason:
            'and it is STILL the admitted location after the post-frame '
            'callback window — no forward was scheduled.',
      );
    });
  });
}
