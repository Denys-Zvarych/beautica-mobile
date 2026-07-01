// Phase 1.4 — smoke test for the go_router routing skeleton.
// Phase 2.9 — Updated: authRedirect now takes (AsyncValue<AuthSession>, state).
//             Test router uses redirect: (_, __) => null so auth logic is not
//             exercised here — that is covered by auth_redirect_test.dart.
//
// Creates a [GoRouter] directly (not via the Riverpod provider) to keep the
// test dependency-free. Validates that:
//   1. The router resolves the initial location to the splash placeholder.
//   2. `router.go(RouteNames.login)` switches the view to the login placeholder.
//   3. The redirect is a no-op for this test (null always) — routing skeleton.
//
// Note: `test/` is excluded from the `no_raw_ui_strings` custom lint rule —
// raw string literals in test find expressions are acceptable here.

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
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

void main() {
  group('appRouter smoke tests', () {
    late GoRouter router;

    setUp(() {
      router = GoRouter(
        initialLocation: RouteNames.splash,
        // Auth redirect logic is tested in auth_redirect_test.dart.
        // This test exercises the routing skeleton only — no redirects.
        redirect: (context, state) => null,
        routes: [
          GoRoute(
            path: RouteNames.splash,
            builder: (context, s) => const _Placeholder('splash'),
          ),
          GoRoute(
            path: RouteNames.login,
            builder: (context, s) => const _Placeholder('login'),
          ),
          GoRoute(
            path: RouteNames.register,
            builder: (context, s) => const _Placeholder('register'),
          ),
          GoRoute(
            path: RouteNames.home,
            builder: (context, s) => const _Placeholder('home'),
          ),
          GoRoute(
            path: RouteNames.settings,
            builder: (context, s) => const _Placeholder('settings'),
          ),
        ],
      );
    });

    tearDown(() => router.dispose());

    testWidgets('initial route shows splash placeholder', (tester) async {
      await tester.pumpWidget(_TestApp(router: router));
      await tester.pumpAndSettle();

      expect(find.text('splash'), findsOneWidget);
    });

    testWidgets('go(login) navigates to login placeholder', (tester) async {
      await tester.pumpWidget(_TestApp(router: router));
      await tester.pumpAndSettle();

      router.go(RouteNames.login);
      await tester.pumpAndSettle();

      expect(find.text('login'), findsOneWidget);
    });

    testWidgets('all routes resolve without unexpected redirects', (
      tester,
    ) async {
      await tester.pumpWidget(_TestApp(router: router));
      await tester.pumpAndSettle();

      // Navigate to every route and confirm no unexpected redirect occurs.
      for (final path in [
        RouteNames.login,
        RouteNames.register,
        RouteNames.home,
        RouteNames.splash,
        RouteNames.settings,
      ]) {
        router.go(path);
        await tester.pumpAndSettle();
        // The placeholder label is the last segment of the path (e.g. 'login').
        // RouteNames.home == '/' — label derivation assumes this; update if the constant changes.
        final label = path == RouteNames.home ? 'home' : path.substring(1);
        expect(find.text(label), findsOneWidget);
      }
    });
  });

  // -------------------------------------------------------------------------
  // HIGH-2 — REAL appRouter redirect wiring.
  //
  // The smoke group above wires `redirect: (_, __) => null`, so the production
  // `appRouter` redirect (which calls `authRedirect(ref.read(authProvider), …)`
  // and listens via `AuthRefreshNotifier`) is never exercised. This group pumps
  // the REAL `appRouterProvider` (read from a ProviderScope-overridden
  // container) with `authProvider` stubbed to a settled session, then asserts
  // that navigating to a protected route honours the production guard.
  //
  // We assert on the router's resolved URI rather than on rendered text — the
  // real auth screens (LoginScreen/SplashScreen) run repeating animations, so
  // `pumpAndSettle` would never quiesce; a bounded `pump` plus the
  // currentConfiguration URI is the deterministic signal.
  // -------------------------------------------------------------------------
  group('appRouter real redirect wiring', () {
    // Park the splash gate in the past so authRedirect does not pin the router
    // on /splash waiting for AppStartTime.minSplashDuration to elapse.
    setUp(
      () => AppStartTime.setStartForTest(
        DateTime.now().subtract(const Duration(seconds: 5)),
      ),
    );
    tearDown(AppStartTime.resetForTest);

    ProviderContainer makeContainer(AsyncValue<AuthSession> session) {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _FixedAuthNotifier(session)),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
          // The authenticated-redirect test lands on MasterProfileScreen, which
          // (without these) would call the REAL HttpMasterRepository — a live
          // Dio request that schedules a Timer never drained by a bounded
          // `pump`, intermittently tripping '!timersPending'. Override the
          // landed screen's data providers with settled fakes so the screen
          // resolves synchronously and schedules no wall-clock timer.
          masterProfileProvider.overrideWith(_SettledMasterProfileNotifier.new),
          masterRepositoryProvider.overrideWith((_) => FakeMasterRepository()),
          serviceRepositoryProvider.overrideWith(
            (_) => FakeServiceRepository(),
          ),
          // MasterProfileScreen's categories section watches
          // `approvedCategoriesProvider`, which builds via the REAL
          // authenticated Dio (it bypasses serviceRepositoryProvider). Settle
          // it with an empty list so no 15s connect-timeout Timer outlives the
          // bounded `pump`.
          approvedCategoriesProvider.overrideWith(
            (ref) async => const <ServiceCategoryOption>[],
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    String currentLocation(GoRouter router) =>
        router.routerDelegate.currentConfiguration.uri.toString();

    testWidgets('unauthenticated user reaching a protected route lands on '
        '/login', (tester) async {
      final container = makeContainer(_unauthenticatedSession);
      final router = container.read(appRouterProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _RouterApp(router: router),
        ),
      );
      // Bounded pump — real auth screens animate, so do not pumpAndSettle.
      await tester.pump();

      // Attempt to reach a protected route; the production redirect must bounce
      // an unauthenticated user to /login.
      router.go(RouteNames.settings);
      await tester.pump();

      expect(currentLocation(router), equals(RouteNames.login));
    });

    testWidgets('authenticated user reaches the protected route', (
      tester,
    ) async {
      final container = makeContainer(_authenticatedSession);
      final router = container.read(appRouterProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _RouterApp(router: router),
        ),
      );
      await tester.pump();

      router.go(RouteNames.settings);
      await tester.pump();

      expect(currentLocation(router), equals(RouteNames.settings));
    });
  });
}

// ---------------------------------------------------------------------------
// Fixtures for the real-redirect-wiring group.
// ---------------------------------------------------------------------------

const _fakeUser = User(
  id: 'u1',
  email: 'test@example.com',
  role: UserRole.independentMaster,
  firstName: 'Test',
  lastName: 'User',
);

const _authenticatedSession = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _fakeUser, accessToken: 'token'),
);

const _unauthenticatedSession = AsyncData<AuthSession>(
  AuthSession.unauthenticated(),
);

/// [MasterProfile] stub that resolves immediately to a fixed [Master] so the
/// authenticated-redirect test can land on MasterProfileScreen without the real
/// repository firing a Dio request (which would leak a Timer).
class _SettledMasterProfileNotifier extends MasterProfile {
  @override
  Future<Master> build() async => const Master(
    id: 'u1',
    firstName: 'Test',
    lastName: 'User',
    avgRating: 0,
    reviewCount: 0,
    type: MasterType.independentMaster,
  );
}

/// [AuthNotifier] stub that immediately settles to a fixed [AsyncValue].
/// Mirrors the `_FixedAuthNotifier` used across the auth test suite.
class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);

  final AsyncValue<AuthSession> _fixed;

  @override
  Future<AuthSession> build() async {
    state = _fixed;
    return _fixed.value ?? const AuthSession.unauthenticated();
  }
}

/// [MaterialApp.router] wrapper for the real [appRouter] with l10n delegates.
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

/// Minimal [MaterialApp.router] wrapper that supplies l10n delegates needed
/// by [onGenerateTitle] and any widget under test that calls [AppLocalizations.of].
class _TestApp extends StatelessWidget {
  const _TestApp({required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('uk', 'UA'),
  );
}

/// Mirror of the private [_Placeholder] in `app_router.dart` — needed because
/// the private class cannot be imported in tests.  Both render `Text(label)`.
class _Placeholder extends StatelessWidget {
  const _Placeholder(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(label)));
}
