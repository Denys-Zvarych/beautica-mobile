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

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/domain/register_result.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/state/register_draft_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fakes/fake_secure_storage.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

const _verificationRequired = RegisterResult.verificationRequired(
  email: 'a@b.com',
);

const _authenticated = RegisterResult.authenticated(
  user: User(id: 'u1', email: 'a@b.com', role: UserRole.client),
  tokens: AuthTokens(accessToken: 'acc', refreshToken: 'ref'),
);

/// Stubs `registerIndependentMaster` to return [result] and wires the
/// production router. Returns the live [GoRouter] + the auth mock.
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
    overrides: [
      authRepositoryProvider.overrideWith((_) => authRepo),
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

  final router = container.read(appRouterProvider);
  router.go(RouteNames.registerStep3);

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

  final skip = find.byKey(const Key('btn-skip-step3'));
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

  testWidgets(
    'CLIENT skip (verification-required) → real guard → /verification',
    (tester) async {
      final (router, _) = await _pumpClientSkip(
        tester,
        result: _verificationRequired,
      );
      expect(_currentLocation(router), RouteNames.verification);
      expect(_currentLocation(router), isNot(RouteNames.login));
      expect(_currentLocation(router), isNot(RouteNames.home));
    },
  );

  testWidgets(
    'CLIENT skip (auto-login authenticated) → real guard → /verification (not /home)',
    (tester) async {
      // Regression: an Authenticated-but-unverified session at /verification
      // must NOT be bounced to /home.
      final (router, _) = await _pumpClientSkip(tester, result: _authenticated);
      expect(_currentLocation(router), RouteNames.verification);
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
