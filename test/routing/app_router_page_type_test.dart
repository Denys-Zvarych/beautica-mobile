// Regression guard for the left-edge swipe-back gesture router contract.
//
// The interactive swipe-back gesture (installed by `CupertinoPageTransitionsBuilder`
// in `velvetTheme()`) only fires on routes that use `builder:` (which go_router
// wraps in a `MaterialPage`). Routes that use `pageBuilder:` supply their own
// `Page` object — specifically `_instantPage` (a `CustomTransitionPage` with
// zero-duration) — which OVERRIDES the theme-level builder and therefore does
// NOT get the back-gesture.
//
// The 5 poppable routes were converted from `pageBuilder: _instantPage(...)` to
// `builder:` in app_router.dart. If any of them reverts to `pageBuilder:`, the
// swipe-back silently dies on that route. This test catches that regression.
//
// Strategy: read the production `appRouterProvider` from a `ProviderContainer`
// with auth stubbed to an authenticated session, traverse `GoRouter.routes` to
// locate each route by its path, then assert whether `GoRoute.builder` is set
// (MaterialPage route — gesture enabled) or `GoRoute.pageBuilder` is set
// (CustomTransitionPage / instant route — gesture suppressed).
//
// This is a structural test of the production `app_router.dart` configuration —
// it does NOT pump a widget tree and does NOT exercise any screen widget code.
//
// Layer: Unit (GoRouter value inspection — no pumpWidget).

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/master_schedule_screen.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _fakeUser = User(
  id: 'u1',
  email: 'test@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Тест',
  lastName: 'Майстер',
);

const _authenticatedSession = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _fakeUser, accessToken: 'token'),
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Stubs `authProvider` to a settled, authenticated session so the production
/// `appRouterProvider` can be read without live network/storage calls.
class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);

  final AsyncValue<AuthSession> _fixed;

  @override
  Future<AuthSession> build() async {
    state = _fixed;
    return _fixed.value ?? const AuthSession.unauthenticated();
  }
}

/// Creates a [ProviderContainer] with the minimum overrides needed to read
/// [appRouterProvider] without real network or storage I/O.
ProviderContainer _makeContainer() {
  final container = ProviderContainer(
    retry: beauticaProviderRetry,
    overrides: [
      authProvider.overrideWith(
        () => _FixedAuthNotifier(_authenticatedSession),
      ),
      authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
      secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Recursively searches [routes] for a [GoRoute] whose `path` equals [path].
/// Returns `null` if not found.
GoRoute? _findRoute(List<RouteBase> routes, String path) {
  for (final route in routes) {
    if (route is GoRoute) {
      if (route.path == path) return route;
      // Recurse into a GoRoute's own nested sub-routes (e.g. /search → results)
      // — the registered path of a nested route is its RELATIVE segment.
      final found = _findRoute(route.routes, path);
      if (found != null) return found;
    }
    // Recurse into ShellRoute / StatefulShellRoute sub-routes.
    if (route is ShellRoute) {
      final found = _findRoute(route.routes, path);
      if (found != null) return found;
    }
    if (route is StatefulShellRoute) {
      for (final branch in route.branches) {
        final found = _findRoute(branch.routes, path);
        if (found != null) return found;
      }
    }
  }
  return null;
}

/// Never-invoked stand-ins for a `GoRoute.builder`'s `(BuildContext, state)`
/// signature — Phase 309's `RouteNames.salonMasterSchedule` registration
/// (`builder: (context, state) => const MasterScheduleScreen()`) reads
/// neither argument, so a `Fake` that would throw if any member were
/// actually called is sufficient to invoke the closure and inspect its
/// RETURN VALUE's runtime type — without pumping a widget tree.
class _NeverUsedBuildContext extends Fake implements BuildContext {}

/// [RouteNames.masterSchedule]'s builder additionally reads
/// `state.uri.queryParameters['date']` (its optional pre-select param) — so,
/// unlike a bare `Fake`, this stub answers `.uri` with an empty query string
/// rather than throwing, so the fake exercises the "no date param" branch
/// (`initialDate == null`) rather than crashing before returning a widget.
class _NeverUsedGoRouterState extends Fake implements GoRouterState {
  @override
  Uri get uri => Uri.parse('/schedule');
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // Poppable routes — must use `builder:` (MaterialPage) so the theme's
  // CupertinoPageTransitionsBuilder installs the back-gesture detector.
  // -------------------------------------------------------------------------
  group(
    'app_router poppable routes use builder: (MaterialPage) — swipe-back enabled',
    () {
      late GoRouter router;

      setUp(() {
        router = _makeContainer().read(appRouterProvider);
      });

      // SB-1 — /services
      test(
        'SB-1: RouteNames.services (/services) uses builder: not pageBuilder:',
        () {
          final route = _findRoute(
            router.configuration.routes,
            RouteNames.services,
          );
          expect(
            route,
            isNotNull,
            reason:
                'RouteNames.services (${RouteNames.services}) must be '
                'registered in appRouter',
          );
          expect(
            route!.builder,
            isNotNull,
            reason:
                '/services must use builder: so go_router wraps it in a '
                'MaterialPage — the only page type that honors the theme\'s '
                'CupertinoPageTransitionsBuilder and installs the swipe-back gesture',
          );
          expect(
            route.pageBuilder,
            isNull,
            reason:
                '/services must NOT use pageBuilder: — a CustomTransitionPage '
                'returned by _instantPage() overrides the theme builder and '
                'suppresses the swipe-back gesture',
          );
        },
      );

      // SB-2 — /services/create was RETIRED (2026-08-04). The single-create
      // form (ServiceCreateScreen) was deleted and both "add services" entry
      // points collapsed onto /services/setup, so the route and the
      // RouteNames.serviceCreate constant are gone. The swipe-back guarantee
      // this case protected did not need re-homing: SB-3 below already pins
      // exactly the same contract on /services/setup, which is now the sole
      // pushed add-service leaf.
      //
      // SB-3 — /services/setup
      test(
        'SB-3: RouteNames.serviceSetup (/services/setup) uses builder: not pageBuilder:',
        () {
          final route = _findRoute(
            router.configuration.routes,
            RouteNames.serviceSetup,
          );
          expect(
            route,
            isNotNull,
            reason:
                'RouteNames.serviceSetup (${RouteNames.serviceSetup}) must be '
                'registered in appRouter',
          );
          expect(
            route!.builder,
            isNotNull,
            reason:
                '/services/setup must use builder: for MaterialPage / '
                'swipe-back support',
          );
          expect(
            route.pageBuilder,
            isNull,
            reason:
                '/services/setup must NOT use pageBuilder: — would suppress '
                'the swipe-back gesture',
          );
        },
      );

      // SB-4 — /services/:id/edit
      // RouteNames.serviceEdit is a function (returns a path with the id
      // substituted). The registered path in app_router.dart is '/services/:id/edit'.
      test('SB-4: /services/:id/edit uses builder: not pageBuilder:', () {
        const serviceEditPath = '/services/:id/edit';
        final route = _findRoute(router.configuration.routes, serviceEditPath);
        expect(
          route,
          isNotNull,
          reason: '$serviceEditPath must be registered in appRouter',
        );
        expect(
          route!.builder,
          isNotNull,
          reason:
              '/services/:id/edit must use builder: for MaterialPage / '
              'swipe-back support',
        );
        expect(
          route.pageBuilder,
          isNull,
          reason:
              '/services/:id/edit must NOT use pageBuilder: — would suppress '
              'the swipe-back gesture',
        );
      });

      // SB-5 — /schedule/weekly
      test(
        'SB-5: RouteNames.scheduleWeeklyEditor (/schedule/weekly) uses builder: not pageBuilder:',
        () {
          final route = _findRoute(
            router.configuration.routes,
            RouteNames.scheduleWeeklyEditor,
          );
          expect(
            route,
            isNotNull,
            reason:
                'RouteNames.scheduleWeeklyEditor (${RouteNames.scheduleWeeklyEditor}) '
                'must be registered in appRouter',
          );
          expect(
            route!.builder,
            isNotNull,
            reason:
                '/schedule/weekly must use builder: for MaterialPage / '
                'swipe-back support',
          );
          expect(
            route.pageBuilder,
            isNull,
            reason:
                '/schedule/weekly must NOT use pageBuilder: — would suppress '
                'the swipe-back gesture',
          );
        },
      );

      // SB-6 — the master settings hub + the three section edit pages.
      //
      // The monolithic /master/edit was replaced by a settings hub
      // (RouteNames.masterMenu) and three section pages (masterEditPersonal /
      // masterEditContacts / masterEditLocation). All four are pushed from the
      // profile / hub, so each must use `builder:` so the theme's
      // CupertinoPageTransitionsBuilder installs the left-edge swipe-back
      // gesture. If any reverts to `pageBuilder:`, the swipe-back gesture
      // silently dies on that drill-down.
      const Map<String, String> hubRoutes = <String, String>{
        'masterMenu (/master/menu)': RouteNames.masterMenu,
        'masterEditPersonal (/master/edit/personal)':
            RouteNames.masterEditPersonal,
        'masterEditContacts (/master/edit/contacts)':
            RouteNames.masterEditContacts,
        'masterEditLocation (/master/edit/location)':
            RouteNames.masterEditLocation,
      };

      hubRoutes.forEach((String label, String path) {
        test('SB-6: RouteNames.$label uses builder: not pageBuilder:', () {
          final route = _findRoute(router.configuration.routes, path);
          expect(
            route,
            isNotNull,
            reason: 'RouteNames.$label ($path) must be registered in appRouter',
          );
          expect(
            route!.builder,
            isNotNull,
            reason:
                '$path must use builder: so go_router wraps it in a '
                'MaterialPage — the only page type that honors the theme\'s '
                'CupertinoPageTransitionsBuilder and installs the swipe-back '
                'gesture when pushed from the profile / hub',
          );
          expect(
            route.pageBuilder,
            isNull,
            reason:
                '$path must NOT use pageBuilder: — a CustomTransitionPage '
                'returned by _instantPage() overrides the theme builder and '
                'suppresses the left-edge swipe-back gesture',
          );
        });
      });

      // SB-7 — /verification. Reached via `context.push` from the login
      // screen's EMAIL_NOT_VERIFIED banner action, so it needs `builder:`
      // (MaterialPage) for the left-edge swipe-back gesture — same
      // mobile-debugger fix as /salons/:salonId and /masters/:masterId.
      // register_step_3_screen.dart also reaches this route via `context.go`,
      // which replaces the whole stack regardless of page type, so that call
      // site is unaffected by this contract.
      test(
        'SB-7: RouteNames.verification (/verification) uses builder: not pageBuilder:',
        () {
          final route = _findRoute(
            router.configuration.routes,
            RouteNames.verification,
          );
          expect(
            route,
            isNotNull,
            reason:
                'RouteNames.verification (${RouteNames.verification}) must be '
                'registered in appRouter',
          );
          expect(
            route!.builder,
            isNotNull,
            reason:
                '/verification must use builder: so go_router wraps it in a '
                'MaterialPage — the only page type that honors the theme\'s '
                'CupertinoPageTransitionsBuilder and installs the swipe-back '
                'gesture when pushed from the login screen\'s unverified banner',
          );
          expect(
            route.pageBuilder,
            isNull,
            reason:
                '/verification must NOT use pageBuilder: — a CustomTransitionPage '
                'returned by _instantPage() overrides the theme builder and '
                'suppresses the swipe-back gesture',
          );
        },
      );

      // SB-8 — /register-role. Reached via `context.push` from the login
      // screen's "Зареєструватись" link, so it needs `builder:` (MaterialPage)
      // for the left-edge swipe-back gesture — same mobile-debugger fix as
      // /salons/:salonId and /masters/:masterId. `context.go(RouteNames.registerRole)`
      // elsewhere (back-links inside the register wizard) is unaffected by this
      // contract, since `.go` replaces the stack regardless of page type.
      test(
        'SB-8: RouteNames.registerRole (/register-role) uses builder: not pageBuilder:',
        () {
          final route = _findRoute(
            router.configuration.routes,
            RouteNames.registerRole,
          );
          expect(
            route,
            isNotNull,
            reason:
                'RouteNames.registerRole (${RouteNames.registerRole}) must be '
                'registered in appRouter',
          );
          expect(
            route!.builder,
            isNotNull,
            reason:
                '/register-role must use builder: so go_router wraps it in a '
                'MaterialPage — the only page type that honors the theme\'s '
                'CupertinoPageTransitionsBuilder and installs the swipe-back '
                'gesture when pushed from the login screen\'s registration link',
          );
          expect(
            route.pageBuilder,
            isNull,
            reason:
                '/register-role must NOT use pageBuilder: — a CustomTransitionPage '
                'returned by _instantPage() overrides the theme builder and '
                'suppresses the swipe-back gesture',
          );
        },
      );

      // SB-9 — /forgot-password. Reached via `context.push` from the login
      // screen's "Забули пароль?" link, so it needs `builder:` (MaterialPage)
      // for the left-edge swipe-back gesture — same mobile-debugger fix as
      // /salons/:salonId and /masters/:masterId.
      test(
        'SB-9: RouteNames.forgotPassword (/forgot-password) uses builder: not pageBuilder:',
        () {
          final route = _findRoute(
            router.configuration.routes,
            RouteNames.forgotPassword,
          );
          expect(
            route,
            isNotNull,
            reason:
                'RouteNames.forgotPassword (${RouteNames.forgotPassword}) must be '
                'registered in appRouter',
          );
          expect(
            route!.builder,
            isNotNull,
            reason:
                '/forgot-password must use builder: so go_router wraps it in a '
                'MaterialPage — the only page type that honors the theme\'s '
                'CupertinoPageTransitionsBuilder and installs the swipe-back '
                'gesture when pushed from the login screen\'s "Забули пароль?" link',
          );
          expect(
            route.pageBuilder,
            isNull,
            reason:
                '/forgot-password must NOT use pageBuilder: — a CustomTransitionPage '
                'returned by _instantPage() overrides the theme builder and '
                'suppresses the swipe-back gesture',
          );
        },
      );

      // SB-10 — /schedule. The profile bottom-nav "Календар" tile reaches this
      // route via `context.push`, so it needs `builder:` (MaterialPage) for the
      // left-edge swipe-back gesture — same mobile-debugger fix as
      // /salons/:salonId and /masters/:masterId. `context.go(RouteNames.masterSchedule)`
      // elsewhere (the weekly editor's save/cancel returns) is unaffected by
      // this contract, since `.go` replaces the stack regardless of page type.
      test(
        'SB-10: RouteNames.masterSchedule (/schedule) uses builder: not pageBuilder:',
        () {
          final route = _findRoute(
            router.configuration.routes,
            RouteNames.masterSchedule,
          );
          expect(
            route,
            isNotNull,
            reason:
                'RouteNames.masterSchedule (${RouteNames.masterSchedule}) must '
                'be registered in appRouter',
          );
          expect(
            route!.builder,
            isNotNull,
            reason:
                '/schedule must use builder: so go_router wraps it in a '
                'MaterialPage — the only page type that honors the theme\'s '
                'CupertinoPageTransitionsBuilder and installs the swipe-back '
                'gesture when pushed from the profile bottom-nav "Календар" tile',
          );
          expect(
            route.pageBuilder,
            isNull,
            reason:
                '/schedule must NOT use pageBuilder: — a CustomTransitionPage '
                'returned by _instantPage() overrides the theme builder and '
                'suppresses the swipe-back gesture',
          );
        },
      );
    },
  );

  // -------------------------------------------------------------------------
  // CLIENT pushed pages — must use `builder:` (MaterialPage) so the theme's
  // CupertinoPageTransitionsBuilder installs the left-edge swipe-back gesture.
  //
  // R4 (back-navigation fix, debugger-flagged gap): the original group only
  // guarded the MASTER pushed routes. Every CLIENT route that is `context.push`-
  // ed onto a branch navigator (settings hub + its three section edit pages, the
  // search-results list, the support form, the rating screen, and the shared
  // settings screen) relies on the SAME builder:/MaterialPage contract for its
  // edge swipe-back. A future copy-paste reverting any of them to
  // `pageBuilder: _instantPage(...)` would silently kill swipe-back on that
  // drill-down — exactly the regression this group catches. The five CLIENT
  // tab-ROOTS are deliberately `_instantPage` (covered by the separate
  // instant-roots group below); they are not in this set.
  // -------------------------------------------------------------------------
  group(
    'app_router CLIENT pushed pages use builder: (MaterialPage) — swipe-back enabled',
    () {
      late GoRouter router;

      setUp(() {
        router = _makeContainer().read(appRouterProvider);
      });

      // clientSearchResults is registered as the RELATIVE nested path 'results'
      // under /search (RouteNames.clientSearch), so it is located by that
      // segment, not by the absolute RouteNames.clientSearchResults string.
      const String clientSearchResultsRelative = 'results';

      const Map<String, String> clientPushedRoutes = <String, String>{
        'clientMenu (/client/menu)': RouteNames.clientMenu,
        'clientEditPersonal (/client/edit/personal)':
            RouteNames.clientEditPersonal,
        'clientEditContacts (/client/edit/contacts)':
            RouteNames.clientEditContacts,
        'clientEditLocation (/client/edit/location)':
            RouteNames.clientEditLocation,
        'clientSearchResults (/search/results, nested path \'results\')':
            clientSearchResultsRelative,
        'contactSupport (/support/contact)': RouteNames.contactSupport,
        'myRating (/rating)': RouteNames.myRating,
        'settings (/settings)': RouteNames.settings,
      };

      clientPushedRoutes.forEach((String label, String path) {
        test('CB-1: RouteNames.$label uses builder: not pageBuilder:', () {
          final route = _findRoute(router.configuration.routes, path);
          expect(
            route,
            isNotNull,
            reason: 'RouteNames.$label ($path) must be registered in appRouter',
          );
          expect(
            route!.builder,
            isNotNull,
            reason:
                '$path is a CLIENT pushed page — it must use builder: so '
                'go_router wraps it in a MaterialPage, the only page type that '
                'honors the theme\'s CupertinoPageTransitionsBuilder and '
                'installs the left-edge swipe-back gesture on push.',
          );
          expect(
            route.pageBuilder,
            isNull,
            reason:
                '$path must NOT use pageBuilder: — a CustomTransitionPage '
                'returned by _instantPage() overrides the theme builder and '
                'silently suppresses the swipe-back gesture on this CLIENT '
                'drill-down (the R4 regression this guard exists to catch).',
          );
        });
      });
    },
  );

  // -------------------------------------------------------------------------
  // CLIENT tab-ROOTS — must use `pageBuilder:` (_instantPage). These are the
  // five StatefulShellRoute branch roots; they are switched via goBranch (never
  // pushed), so there is nothing to pop and no swipe-back is expected. They
  // intentionally use the zero-duration _instantPage (instant forward paint +
  // the secondaryAnimation parallax reveal). If a branch root is converted to
  // builder:, it gains an unwanted slide-in on every tab hop. This group pins
  // the tab-root vs pushed-page distinction (R4).
  // -------------------------------------------------------------------------
  group(
    'app_router CLIENT tab-roots use pageBuilder: (_instantPage) — branch hops, no gesture',
    () {
      late GoRouter router;

      setUp(() {
        router = _makeContainer().read(appRouterProvider);
      });

      const Map<String, String> clientTabRoots = <String, String>{
        'clientHome (/home)': RouteNames.clientHome,
        'clientFavorites (/favorites)': RouteNames.clientFavorites,
        'clientSearch (/search)': RouteNames.clientSearch,
        'clientBookings (/bookings)': RouteNames.clientBookings,
        'clientPassport (/passport)': RouteNames.clientPassport,
      };

      clientTabRoots.forEach((String label, String path) {
        test('CT-1: RouteNames.$label uses pageBuilder: not builder:', () {
          final route = _findRoute(router.configuration.routes, path);
          expect(
            route,
            isNotNull,
            reason: 'RouteNames.$label ($path) must be registered in appRouter',
          );
          expect(
            route!.pageBuilder,
            isNotNull,
            reason:
                '$path is a CLIENT tab-root — it must stay on pageBuilder: '
                '(_instantPage): branch roots are switched via goBranch, so they '
                'want the zero-duration instant paint, not a MaterialPage slide.',
          );
          expect(
            route.builder,
            isNull,
            reason:
                '$path must NOT use builder: — converting a branch root to a '
                'MaterialPage adds an unwanted slide-in on every tab hop.',
          );
        });
      });
    },
  );

  // -------------------------------------------------------------------------
  // Auth-flow instant routes — must use `pageBuilder:` (CustomTransitionPage)
  // so they keep zero-duration transitions. These routes do NOT pop (users
  // navigate with context.go(), not context.push()), so no swipe-back gesture
  // is expected or desired.
  //
  // If someone accidentally converts an auth route to `builder:`, the
  // auth flow gains an unintended slide animation and the swipe-back gesture
  // becomes reachable on a stack that was designed as a flat flow. This test
  // catches that regression in the other direction.
  // -------------------------------------------------------------------------
  group(
    'app_router auth-flow instant routes use pageBuilder: (CustomTransitionPage) — no gesture',
    () {
      late GoRouter router;

      setUp(() {
        router = _makeContainer().read(appRouterProvider);
      });

      // IA-1 — /login
      test(
        'IA-1: RouteNames.login (/login) uses pageBuilder: not builder:',
        () {
          final route = _findRoute(
            router.configuration.routes,
            RouteNames.login,
          );
          expect(
            route,
            isNotNull,
            reason:
                'RouteNames.login (${RouteNames.login}) must be registered in '
                'appRouter',
          );
          expect(
            route!.pageBuilder,
            isNotNull,
            reason:
                '/login is an auth-flow route that intentionally uses '
                '_instantPage (zero-duration CustomTransitionPage). Converting '
                'it to builder: would add an unintended slide animation.',
          );
          expect(
            route.builder,
            isNull,
            reason:
                '/login must NOT use builder: — it must stay as an instant '
                'pageBuilder: route',
          );
        },
      );

      // IA-2 — /verification was RETIRED from this group by the mobile-debugger
      // swipe-back fix: the login screen's EMAIL_NOT_VERIFIED banner action
      // reaches /verification via `context.push` (not just the register-step-3
      // `context.go` this group's premise assumed), so it now needs `builder:`
      // for the left-edge swipe-back gesture. See SB-7 in the poppable-routes
      // group above for its replacement assertion.
      //
      // IA-3 — /splash
      test(
        'IA-3: RouteNames.splash (/splash) uses pageBuilder: not builder:',
        () {
          final route = _findRoute(
            router.configuration.routes,
            RouteNames.splash,
          );
          expect(
            route,
            isNotNull,
            reason:
                'RouteNames.splash (${RouteNames.splash}) must be registered '
                'in appRouter',
          );
          expect(
            route!.pageBuilder,
            isNotNull,
            reason:
                '/splash is an auth-flow route that intentionally uses '
                '_instantPage (zero-duration CustomTransitionPage).',
          );
          expect(
            route.builder,
            isNull,
            reason:
                '/splash must NOT use builder: — it must stay as an instant '
                'pageBuilder: route',
          );
        },
      );
    },
  );

  // -------------------------------------------------------------------------
  // Retired route — the orphaned /master/working-hours editor (WorkingHoursScreen)
  // was removed from app_router.dart in Phase 6.2. It had zero production
  // navigation and no Android App-Link, but was still deep-link-reachable. The
  // WorkingHoursScreen widget and the RouteNames.workingHours constant are kept
  // (the constant is reused by auth_redirect_test.dart as a representative
  // /master/* path), so a future refactor could silently re-register the route
  // by copy-paste. This guard fails if /master/working-hours ever resolves
  // again. Canonical working-hours editing is /schedule -> /schedule/weekly
  // (scheduleWeeklyEditor / WeeklyTemplateEditorScreen).
  // -------------------------------------------------------------------------
  group('app_router retired routes — /master/working-hours is not registered', () {
    late GoRouter router;

    setUp(() {
      router = _makeContainer().read(appRouterProvider);
    });

    // RR-1 — the production router must NOT register /master/working-hours.
    // Deep-linking there must fall through to go_router's unknown-route
    // handling instead of resolving WorkingHoursScreen.
    test(
      'RR-1: RouteNames.workingHours (/master/working-hours) is NOT registered',
      () {
        final route = _findRoute(
          router.configuration.routes,
          RouteNames.workingHours,
        );
        expect(
          route,
          isNull,
          reason:
              'The orphaned /master/working-hours editor (WorkingHoursScreen) '
              'was retired in Phase 6.2 — it wrote the deprecated `working_hours` '
              'table and had no production navigation. It must NOT be '
              're-registered in appRouter. Canonical working-hours editing is '
              '/schedule -> /schedule/weekly (RouteNames.scheduleWeeklyEditor).',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Phase 309 — RouteNames.salonMasterSchedule (/staff/schedule) is
  // registered as a top-level flat route (a VelvetBottomNavBar nav-tile
  // precondition — Phase 310 D1) and resolves to the SAME MasterScheduleScreen
  // class as RouteNames.masterSchedule (/schedule) — pinned by the resolved
  // page TYPE, not merely the route string, per this track's mutation check
  // #1: renaming the registered path away from the RouteNames constant (e.g.
  // hardcoding '/staff/schedule2') must turn BOTH assertions below red — the
  // `_findRoute` lookup (keyed on the constant) and the built widget's type.
  // -------------------------------------------------------------------------
  group(
    'app_router Phase 309 — /staff/schedule resolves MasterScheduleScreen',
    () {
      late GoRouter router;

      setUp(() {
        router = _makeContainer().read(appRouterProvider);
      });

      test('PT-1: RouteNames.salonMasterSchedule is registered as a TOP-LEVEL '
          'route and builds a MasterScheduleScreen', () {
        final route = _findRoute(
          router.configuration.routes,
          RouteNames.salonMasterSchedule,
        );
        expect(
          route,
          isNotNull,
          reason:
              'RouteNames.salonMasterSchedule '
              '(${RouteNames.salonMasterSchedule}) must be registered in '
              'appRouter',
        );
        expect(
          route!.builder,
          isNotNull,
          reason: '/staff/schedule must use builder: (MaterialPage)',
        );
        expect(route.pageBuilder, isNull);

        final Widget built = route.builder!(
          _NeverUsedBuildContext(),
          _NeverUsedGoRouterState(),
        );
        expect(
          built,
          isA<MasterScheduleScreen>(),
          reason:
              'Phase 309 D1: /staff/schedule reuses MasterScheduleScreen '
              'VERBATIM — a different widget type here means the route was '
              'forked rather than reused',
        );
      });

      test('PT-2: RouteNames.masterSchedule (/schedule) ALSO builds a '
          'MasterScheduleScreen — both routes share one widget tree', () {
        final route = _findRoute(
          router.configuration.routes,
          RouteNames.masterSchedule,
        );
        expect(route, isNotNull);
        final Widget built = route!.builder!(
          _NeverUsedBuildContext(),
          _NeverUsedGoRouterState(),
        );
        expect(built, isA<MasterScheduleScreen>());
      });
    },
  );
}
