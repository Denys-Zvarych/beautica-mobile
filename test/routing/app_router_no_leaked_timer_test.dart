// Phase 17.1 — flake-stabilization regression guard.
//
// The original flake: pumping the production `appRouterProvider` under an
// authenticated INDEPENDENT_MASTER session lands on `MasterProfileScreen`,
// whose REAL `HttpMasterRepository.getMyProfile` fires a live Dio request.
// Dio schedules a connection-timeout `Timer` that a bounded `pump` never
// drains, so the fake-async test binding's `!timersPending` tear-down
// invariant trips intermittently ("A Timer is still pending even after the
// widget tree was disposed.").
//
// The fix overrides the landed screen's data providers (master profile /
// repositories) with settled fakes in the router test container, so the
// redirect path resolves synchronously and schedules NO wall-clock timer.
//
// This guard asserts the invariant directly:
//   1. Mount the production `appRouterProvider` under an authenticated role.
//   2. Navigate to the protected, data-fetching `/master/profile` route.
//   3. Replace the whole widget tree with an empty `SizedBox` — this disposes
//      MasterProfileScreen and every provider it mounted.
//   4. Advance the fake clock far past any plausible Dio connection timeout.
//
// If someone reverts the provider overrides (or reintroduces a real network
// call on the redirect path), the leaked Dio timer survives disposal and the
// binding's `!timersPending` tear-down invariant fails this test — exactly the
// regression we are guarding against. With the overrides in place, no timer is
// ever scheduled, the tree disposes cleanly, and the test passes.
//
// Strategy mirrors the project-blessed pattern in
// `splash_screen_test.dart` (test 8, "early-dispose"): pumpWidget → replace
// tree → drain the clock → no framework assertion.
//
// Note: `test/` is excluded from the `no_raw_ui_strings` custom lint rule.
// Assertions here use the router's resolved URI (a value finder) and route
// constants — never raw Ukrainian text — so an l10n key move cannot mask a
// regression (mobile-qa M2).

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

const _fakeClientUser = User(
  id: 'c1',
  email: 'client@example.com',
  role: UserRole.client,
  firstName: 'Test',
  lastName: 'Client',
);

const _authenticatedClientSession = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _fakeClientUser, accessToken: 'token'),
);

void main() {
  group('appRouter redirect path leaks no pending timer', () {
    // Park the splash gate in the past so authRedirect does not pin the router
    // on /splash waiting for AppStartTime.minSplashDuration to elapse.
    setUp(
      () => AppStartTime.setStartForTest(
        DateTime.now().subtract(const Duration(seconds: 5)),
      ),
    );
    tearDown(AppStartTime.resetForTest);

    ProviderContainer makeAuthenticatedContainer() {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            () => _FixedAuthNotifier(_authenticatedSession),
          ),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
          // These are the overrides under test. Reverting any of them would
          // route MasterProfileScreen back to the real HttpMasterRepository →
          // real Dio request → leaked connection-timeout Timer → tear-down
          // `!timersPending` failure below.
          masterProfileProvider.overrideWith(_SettledMasterProfileNotifier.new),
          masterRepositoryProvider.overrideWith((_) => FakeMasterRepository()),
          serviceRepositoryProvider.overrideWith(
            (_) => FakeServiceRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    String currentLocation(GoRouter router) =>
        router.routerDelegate.currentConfiguration.uri.toString();

    testWidgets(
      'mounting appRouterProvider under an authenticated role and disposing the '
      'tree leaves zero pending timers',
      (tester) async {
        final container = makeAuthenticatedContainer();
        final router = container.read(appRouterProvider);
        addTearDown(router.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: _RouterApp(router: router),
          ),
        );
        // Bounded pump — real auth/profile screens animate, so do not
        // pumpAndSettle (it would never quiesce).
        await tester.pump();

        // Drive the protected, data-fetching route. This is the screen whose
        // real repository leaked the Dio timer.
        router.go(RouteNames.masterProfile);
        await tester.pump();

        // The production redirect must keep the authenticated user on the
        // protected route (value finder — not raw text).
        expect(currentLocation(router), equals(RouteNames.masterProfile));

        // Dispose the entire widget tree. A leaked Dio timer would survive this
        // and trip the binding's `!timersPending` invariant.
        await tester.pumpWidget(const SizedBox.shrink());

        // Drain the frame queue and advance the fake clock far past any Dio
        // connection-timeout timer. With the overrides in place no timer was
        // ever scheduled, so this is a clean no-op; without them, the leaked
        // timer's tear-down assertion fails the test.
        await tester.pump(const Duration(minutes: 5));
      },
    );
  });

  // Phase 14.1 addition: `/booking/new` used to render a fully static
  // `BookingNewPlaceholderScreen` (no data fetching at all). It now renders
  // `ServiceSelectorSheet`, which watches `publicMasterProfileProvider` —
  // exactly the same real-Dio-request shape that bit `/master/profile` above.
  // This guards the SAME regression on the new data-fetching entry point.
  group('appRouter /booking/new leaks no pending timer', () {
    setUp(
      () => AppStartTime.setStartForTest(
        DateTime.now().subtract(const Duration(seconds: 5)),
      ),
    );
    tearDown(AppStartTime.resetForTest);

    ProviderContainer makeAuthenticatedClientContainer() {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            () => _FixedAuthNotifier(_authenticatedClientSession),
          ),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
          // These are the overrides under test. Reverting either would route
          // ServiceSelectorSheet's publicMasterProfileProvider back to the
          // real HttpMasterRepository / HttpServiceRepository → real Dio
          // requests → leaked connection-timeout Timers → tear-down
          // `!timersPending` failure below.
          masterRepositoryProvider.overrideWith((_) => FakeMasterRepository()),
          publicServiceRepositoryProvider.overrideWith(
            (_) => FakeServiceRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    String currentLocation(GoRouter router) =>
        router.routerDelegate.currentConfiguration.uri.toString();

    testWidgets('mounting appRouterProvider under an authenticated CLIENT and '
        'navigating to /booking/new leaves zero pending timers on disposal', (
      tester,
    ) async {
      final container = makeAuthenticatedClientContainer();
      final router = container.read(appRouterProvider);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _RouterApp(router: router),
        ),
      );
      await tester.pump();

      router.go(RouteNames.bookingNew, extra: 'master-1');
      await tester.pump();

      expect(currentLocation(router), equals(RouteNames.bookingNew));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 5));
    });
  });
}

// ---------------------------------------------------------------------------
// Fixtures.
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

/// [MasterProfile] stub that resolves immediately to a fixed [Master] so the
/// authenticated-redirect guard can land on MasterProfileScreen without the
/// real repository firing a Dio request (which would leak a Timer).
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
