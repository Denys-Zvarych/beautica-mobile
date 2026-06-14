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
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';

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
    if (route is GoRoute && route.path == path) {
      return route;
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

      // SB-2 — /services/create
      test(
        'SB-2: RouteNames.serviceCreate (/services/create) uses builder: not pageBuilder:',
        () {
          final route = _findRoute(
            router.configuration.routes,
            RouteNames.serviceCreate,
          );
          expect(
            route,
            isNotNull,
            reason:
                'RouteNames.serviceCreate (${RouteNames.serviceCreate}) must be '
                'registered in appRouter',
          );
          expect(
            route!.builder,
            isNotNull,
            reason:
                '/services/create must use builder: for MaterialPage / '
                'swipe-back support',
          );
          expect(
            route.pageBuilder,
            isNull,
            reason:
                '/services/create must NOT use pageBuilder: — would suppress '
                'the swipe-back gesture',
          );
        },
      );

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

      // IA-2 — /verification
      test(
        'IA-2: RouteNames.verification (/verification) uses pageBuilder: not builder:',
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
            route!.pageBuilder,
            isNotNull,
            reason:
                '/verification is an auth-flow route that intentionally uses '
                '_instantPage (zero-duration CustomTransitionPage).',
          );
          expect(
            route.builder,
            isNull,
            reason:
                '/verification must NOT use builder: — it must stay as an '
                'instant pageBuilder: route',
          );
        },
      );

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
}
