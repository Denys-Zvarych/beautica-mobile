// mobile-security LOW (Phase 351 audit-fix cycle 1) — regression guard for
// the deleted `/master/received-reviews` route («Мої відгуки», the old
// `RouteNames.masterReceivedReviews` / `MasterReceivedReviewsScreen`, D11).
//
// Before this fix, `/master/received-reviews` had no registered `GoRoute` at
// all — a stale bookmark / deep link / push notification carrying that path
// fell through to go_router's generic not-found page. `app_router.dart` now
// registers a `redirect:`-only `GoRoute` for the exact legacy literal,
// targeting `RouteNames.masterProfile` — the screen the deleted route's
// content now lives on inline (its «Відгуки» tab).
//
// This drives the navigation through the REAL `appRouterProvider` (not a
// hand-rolled test router), mirroring `master_public_profile_swipe_back_test
// .dart`'s pattern: `masterProfileProvider` is pinned to a never-completing
// future so `MasterProfileScreen` mounts (proving we landed on the RIGHT
// screen, not the not-found page) without needing full repository wiring.
//
// Two roles are exercised because the redirect's target re-enters the
// top-level `authRedirect` gate (`/master/*` is INDEPENDENT_MASTER-only, see
// `auth_redirect.dart:293`) — the redirect must not grant a non-
// INDEPENDENT_MASTER access `/master/*` never gave it:
//   • INDEPENDENT_MASTER — lands on `RouteNames.masterProfile` (the own
//     profile screen, «Відгуки» tab now inline).
//   • CLIENT — the top-level `/master/*` role gate fires FIRST (before our
//     route-level redirect is even reached) and bounces to the CLIENT's own
//     role home, never to `masterProfile` and never to the not-found page.
//
// MUTATION CHECK (how this test fails pre-fix): with the redirect `GoRoute`
// removed, `router.go('/master/received-reviews')` resolves to go_router's
// default not-found match — `find.byType(MasterProfileScreen)` finds nothing
// and the resolved location stays `/master/received-reviews` instead of
// `RouteNames.masterProfile`. Manually confirmed by commenting out the new
// `GoRoute` in `app_router.dart`; restored immediately, not committed.
//
// Layer: Widget (drives a real `GoRouter.go` through the production
// `appRouterProvider` + inspects the resolved location / mounted screen).

import 'dart:async';

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/role_home.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import '../helpers/test_container.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

/// The exact legacy literal — deliberately NOT a `RouteNames` constant (the
/// old `RouteNames.masterReceivedReviews` was deleted in the same phase; see
/// `app_router.dart`'s doc on the new redirect-only `GoRoute` for why no new
/// constant/deep-link scheme is invented for it).
const String _kLegacyPath = '/master/received-reviews';

const User _fakeIndependentMaster = User(
  id: 'master-1',
  email: 'master@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Олена',
  lastName: 'Ковальчук',
);

const User _fakeClient = User(
  id: 'client-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Клієнт',
  lastName: 'Тест',
);

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._user);

  final User _user;

  @override
  Future<AuthSession> build() async {
    final AuthSession session = AuthSession.authenticated(
      user: _user,
      accessToken: 'test-token',
    );
    state = AsyncData<AuthSession>(session);
    return session;
  }
}

/// Stub [MasterProfile] notifier whose [build] never resolves — this test
/// only asserts WHICH screen/route resolved, never the master profile's own
/// data states (already covered by `master_profile_screen_test.dart`).
class _NeverResolvingMasterProfile extends MasterProfile {
  @override
  Future<Master> build() => Completer<Master>().future;
}

/// Pumps frames (never `pumpAndSettle`) until [isSettled] reports true, or
/// [maxPumps] is exhausted. Both destinations this test can land on
/// (`MasterProfileScreen`'s loading skeleton, the CLIENT home shell) mount a
/// `SkeletonShimmerScope`-style INFINITE `AnimationController.repeat(...)` —
/// `pumpAndSettle` would never quiesce against it (the same constraint
/// `role_landing_chrome_test.dart` documents), so every settle in this file
/// is this bounded poll instead.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() isSettled, {
  int maxPumps = 30,
}) async {
  for (int i = 0; i < maxPumps && !isSettled(); i++) {
    await tester.pump();
  }
}

Future<GoRouter> _pumpRouterApp(
  WidgetTester tester, {
  required User user,
}) async {
  final ProviderContainer container = makeTestContainer(
    retry: beauticaProviderRetry,
    overrides: <Object>[
      authProvider.overrideWith(() => _FixedAuthNotifier(user)),
      authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
      secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
      // Pinned to AsyncLoading — this test only asserts WHICH screen/route
      // resolved, never the master profile's own data states (already
      // covered by `master_profile_screen_test.dart`).
      masterProfileProvider.overrideWith(_NeverResolvingMasterProfile.new),
    ],
  );

  final GoRouter router = container.read(appRouterProvider);
  addTearDown(router.dispose);

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
  await tester.pump();

  return router;
}

// This file only ever drives navigation with `router.go(...)` (a REPLACE,
// never a push), so the ImperativeRouteMatch exclusion `currentConfiguration
// .uri` is documented to have (see `forbid_naive_router_location.sh`'s
// header) never bites — `context.push`/`GoRouter.push` never occur here.
String _resolvedLocation(GoRouter router) {
  // router-location-ok: go()-only navigation in this file, never a push.
  return router.routerDelegate.currentConfiguration.uri.toString();
}

void main() {
  testWidgets('INDEPENDENT_MASTER: /master/received-reviews redirects to '
      'RouteNames.masterProfile, not the not-found page', (tester) async {
    final GoRouter router = await _pumpRouterApp(
      tester,
      user: _fakeIndependentMaster,
    );

    router.go(_kLegacyPath);
    // The router's CONFIGURATION (the URI `_resolvedLocation` reads) resolves
    // the redirect chain before the actual `MasterProfileScreen` widget is
    // mounted — go_router's page-transition builder still needs a few more
    // frames to build and animate it in. Poll for the widget itself, not
    // just the location, so this loop only exits once both are true.
    await _pumpUntil(
      tester,
      () =>
          _resolvedLocation(router) == RouteNames.masterProfile &&
          find.byType(MasterProfileScreen).evaluate().isNotEmpty,
    );

    expect(
      _resolvedLocation(router),
      RouteNames.masterProfile,
      reason:
          'the legacy path must land on the master\'s own profile — the '
          'screen the deleted "Мої відгуки" route\'s content now lives on '
          'inline (its «Відгуки» tab)',
    );
    expect(
      find.byType(MasterProfileScreen),
      findsOneWidget,
      reason:
          'must mount the real profile screen, not go_router\'s generic '
          'not-found page',
    );
  });

  testWidgets(
    'CLIENT: /master/received-reviews never lands on masterProfile or the '
    'not-found page — the top-level /master/* role gate still applies',
    (tester) async {
      final GoRouter router = await _pumpRouterApp(tester, user: _fakeClient);
      final String expectedClientHome = roleHomePath(UserRole.client);

      router.go(_kLegacyPath);
      await _pumpUntil(
        tester,
        () => _resolvedLocation(router) == expectedClientHome,
      );

      final String resolved = _resolvedLocation(router);
      expect(
        resolved,
        isNot(_kLegacyPath),
        reason: 'must not stay on the unregistered legacy literal',
      );
      expect(
        resolved,
        isNot(RouteNames.masterProfile),
        reason:
            'a CLIENT must never reach the INDEPENDENT_MASTER-only profile '
            'screen — the redirect must not widen /master/*\'s existing '
            'role gate',
      );
      expect(
        resolved,
        expectedClientHome,
        reason:
            'the top-level /master/* role gate (auth_redirect.dart) bounces '
            'a non-INDEPENDENT_MASTER to its own role home before our '
            'route-level redirect is even reached',
      );
      expect(find.byType(MasterProfileScreen), findsNothing);
    },
  );
}
