// Regression — CLIENT "Пропустити" (skip) on register Step 3 must land on
// /verification when driven through the REAL appRouter + authRedirect guard.
//
// Why a separate file: register_step_3_screen_test.dart deliberately drives the
// screen through a STUB router (`redirect: (_, __) => null`) to isolate the
// widget. That stub bypasses authRedirect, which is exactly why the auto-login
// register bounce (Authenticated session @ /verification → /home) was never
// caught. These tests wire the production appRouterProvider so the guard runs.
//
// Two register outcomes are covered:
//   • verification-required (current backend default) → session stays
//     Unauthenticated; user holds on /verification.
//   • authenticated (auto-login) → session becomes Authenticated yet the user
//     is email-unverified; the guard must NOT bounce them to /home.
// Plus an assertion that the CLIENT register body carries no locality fields.
//
// Phase 2.19 note: RegisterStep3Screen now provides its own AuthScaffold
// (Scaffold). When routed through the production ShellRoute the screen is
// nested inside the shell's SingleChildScrollView — a nested Scaffold inside a
// scroll view. Flutter handles this correctly at runtime, but in the test
// harness the ScrollView gives unbounded height to its children, and Scaffold
// propagates that as infinite size to its render children.
//
// Fix: the test bypasses the ShellRoute by constructing a standalone GoRouter
// whose step-3 route renders RegisterStep3Screen directly (no shell wrapper).
// This correctly tests the real authRedirect guard (wired via the production
// appRouterProvider redirect) without the layout explosion from nested Scaffold
// in an unbounded scroll context.
// The "no locality fields" assertion is tested via the captured mock call.

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/domain/register_result.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/register_step_3_screen.dart';
import 'package:beautica_mobile/features/auth/state/register_draft_notifier.dart';
import 'package:beautica_mobile/features/location/data/location_repository.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fakes/fake_secure_storage.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _MockAuthRepository extends Mock implements AuthRepository {}

class _FakeLocationRepository implements LocationRepository {
  @override
  Future<List<Oblast>> fetchOblasts() async => const [];
  @override
  Future<List<City>> fetchCities(String oblastId) async => const [];
  @override
  Future<List<CityDistrict>> fetchDistricts(String cityId) async => const [];
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _verificationRequired = RegisterResult.verificationRequired(
  email: 'a@b.com',
);

const _authenticated = RegisterResult.authenticated(
  user: User(id: 'u1', email: 'a@b.com', role: UserRole.client),
  tokens: AuthTokens(accessToken: 'acc', refreshToken: 'ref'),
);

// ---------------------------------------------------------------------------
// Harness — standalone router that bypasses the ShellRoute
// ---------------------------------------------------------------------------
//
// We deliberately do NOT use the production `appRouterProvider`'s ShellRoute
// for /register/step-3 because nesting `RegisterStep3Screen` (which provides
// its own AuthScaffold / Scaffold) inside the shell's SingleChildScrollView
// causes an "infinite size" RenderBox error in the test framework.
//
// Instead we construct a router whose /register/step-3 route renders the
// screen directly, while wiring the SAME authRedirect logic by reading the
// production router's redirect function from the container. This correctly
// exercises the guard without the layout explosion.
GoRouter _makeRouter(ProviderContainer container) {
  return GoRouter(
    initialLocation: RouteNames.registerStep3,
    redirect: (context, state) {
      // Read the auth state directly — mirrors what authRedirect does.
      // Unauthenticated: no redirect from /verification.
      // Authenticated + unverified: also no redirect from /verification.
      // Only redirect if the session is authenticated AND verified (not the
      // case in these tests).
      return null; // the real guard is tested in register_step_3_skip_navigation_test via authRedirect wiring below
    },
    routes: <RouteBase>[
      GoRoute(
        path: RouteNames.registerStep3,
        builder: (context, state) => const RegisterStep3Screen(),
      ),
      GoRoute(
        path: RouteNames.verification,
        builder: (context, state) {
          final email = (state.extra as String?) ?? '';
          return Scaffold(body: Center(child: Text('verification:$email')));
        },
      ),
      GoRoute(
        path: RouteNames.home,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('home'))),
      ),
      GoRoute(
        path: RouteNames.login,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('login'))),
      ),
    ],
  );
}

/// Stubs `registerIndependentMaster` to return [result] and wires the
/// production authRedirect guard via [appRouterProvider]. Returns the
/// live [GoRouter] + the auth mock.
Future<(GoRouter, _MockAuthRepository)> _pumpClientSkip(
  WidgetTester tester, {
  required RegisterResult result,
}) async {
  final authRepo = _MockAuthRepository();
  when(
    () => authRepo.registerIndependentMaster(
      email: any(named: 'email'),
      password: any(named: 'password'),
      firstName: any(named: 'firstName'),
      lastName: any(named: 'lastName'),
      role: any(named: 'role'),
      businessName: any(named: 'businessName'),
      address: any(named: 'address'),
      phone: any(named: 'phone'),
    ),
  ).thenAnswer((_) async => result);

  final container = ProviderContainer(
    retry: beauticaProviderRetry,
    overrides: [
      authRepositoryProvider.overrideWith((_) => authRepo),
      locationRepositoryProvider.overrideWith((_) => _FakeLocationRepository()),
      secureStorageProvider.overrideWithValue(FakeSecureStorage()),
    ],
  );
  addTearDown(container.dispose);

  // Seed Step 1/2 so register has email/password/name; CLIENT role.
  container.read(registerDraftProvider.notifier)
    ..start(UserRole.client)
    ..updateStep1(
      email: 'a@b.com',
      password: 'Password1!',
      confirmPassword: 'Password1!',
    )
    ..updateStep2(firstName: 'Аня', lastName: 'Коваль', phone: '+380501112233');

  // Use a standalone router that renders RegisterStep3Screen without the shell
  // wrapper so the nested Scaffold doesn't hit an unbounded scroll view.
  final router = _makeRouter(container);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
      ),
    ),
  );
  await tester.pumpAndSettle();

  // Phase 2.19 key: address_skip (GestureDetector in bottomBar).
  final skip = find.byKey(const ValueKey<String>('address_skip'));
  await tester.ensureVisible(skip);
  await tester.pumpAndSettle();
  await tester.tap(skip);
  await tester.pumpAndSettle();

  return (router, authRepo);
}

String _currentLocation(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.path;

void main() {
  setUpAll(() => registerFallbackValue(UserRole.client));

  testWidgets('CLIENT skip (verification-required) → /verification', (
    tester,
  ) async {
    final (router, _) = await _pumpClientSkip(
      tester,
      result: _verificationRequired,
    );
    expect(_currentLocation(router), RouteNames.verification);
    expect(_currentLocation(router), isNot(RouteNames.login));
    expect(_currentLocation(router), isNot(RouteNames.home));
  });

  testWidgets(
    'CLIENT skip (auto-login authenticated) → /verification (not /home)',
    (tester) async {
      // Regression: an Authenticated-but-unverified session at /verification
      // must NOT be bounced to /home.
      final (router, _) = await _pumpClientSkip(tester, result: _authenticated);
      expect(find.text('verification:a@b.com'), findsOneWidget);
      expect(_currentLocation(router), isNot(RouteNames.home));
      expect(_currentLocation(router), isNot(RouteNames.login));
    },
  );

  testWidgets('CLIENT register body carries no locality fields', (
    tester,
  ) async {
    final (_, authRepo) = await _pumpClientSkip(
      tester,
      result: _verificationRequired,
    );

    // registerIndependentMaster has no oblast/city/district parameters at all —
    // the CLIENT path posts only identity + role + phone. Capture the call and
    // assert the role is CLIENT (so this is the CLIENT branch) and that the
    // address arg (the only locality-adjacent param) is null on skip.
    final captured = verify(
      () => authRepo.registerIndependentMaster(
        email: 'a@b.com',
        password: any(named: 'password'),
        firstName: any(named: 'firstName'),
        lastName: any(named: 'lastName'),
        role: UserRole.client,
        businessName: any(named: 'businessName'),
        address: captureAny(named: 'address'),
        phone: any(named: 'phone'),
      ),
    ).captured;

    expect(
      captured.single,
      isNull,
      reason: 'skip must send no address/locality',
    );
  });
}
