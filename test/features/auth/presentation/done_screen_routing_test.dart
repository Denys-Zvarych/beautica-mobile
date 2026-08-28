// Regression tests for role-aware CTA routing in DoneScreen (Site A of the
// CLIENT-routing bug — Step 2.7 Rule 3).
//
// THE BUG: the primary CTA (`done_to_app`) hardcoded RouteNames.home ('/') for
// every non-master role, so a CLIENT finishing registration landed on the
// no-bottom-bar "Скоро…" placeholder at '/' instead of the real 5-tab
// ClientShell at '/home' (RouteNames.clientHome). The fix routes the CTA
// through the shared roleHomePath() helper:
//   - INDEPENDENT_MASTER → [RouteNames.masterProfile]
//   - CLIENT             → [RouteNames.clientHome] ('/home', the client shell)
//   - all other roles    → [RouteNames.home] ('/', the "coming soon" shell)
//
// Covered cases:
//   R1. INDEPENDENT_MASTER → /master/profile (regression guard)
//   R2. CLIENT             → /home (clientHome) — the bug this file now pins
//   R3. SALON_OWNER        → /salons/home (Phase 21.8 Salon Shell landing,
//                            the shared resolver stopover) — was
//                            /salons/mine (Phase 21.1 My Salons Hub) before
//                            Phase 21.8 gave SALON_OWNER a real bottom-nav
//                            shell; guards against a future regression
//                            collapsing it back.
//
// Infrastructure: UncontrolledProviderScope + ProviderContainer mirrors the
// pattern in done_screen_test.dart. A dedicated GoRouter stub registers /home,
// /master/profile, /home (clientHome) AND /salons/mine so each role's CTA
// target can land and be asserted by a distinct sentinel marker.

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/done_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _independentMaster = User(
  id: 'im-1',
  email: 'master@beautica.test',
  role: UserRole.independentMaster,
  firstName: 'Марко',
  lastName: 'Гончар',
);

const _client = User(
  id: 'cl-1',
  email: 'client@beautica.test',
  role: UserRole.client,
  firstName: 'Анна',
  lastName: 'Коваль',
);

const _salonOwner = User(
  id: 'so-1',
  email: 'owner@salon.test',
  role: UserRole.salonOwner,
  firstName: 'Олена',
  lastName: 'Бойко',
);

const _testTokens = AuthTokens(
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
);

// ---------------------------------------------------------------------------
// Router factory
//
// Includes stubs for all three destinations so context.go() can resolve the
// route. Sentinel text constants allow assertions without coupling to l10n.
// ---------------------------------------------------------------------------

const _homeMarker = 'stub-home-route';
const _clientHomeMarker = 'stub-client-home-route';
const _masterProfileMarker = 'stub-master-profile-route';
const _salonHomeMarker = 'stub-salon-home-route';

GoRouter _makeFullRouter() => GoRouter(
  initialLocation: RouteNames.done,
  redirect: (context, state) => null,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.done,
      builder: (context, state) => const DoneScreen(),
    ),
    GoRoute(
      path: RouteNames.home,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text(_homeMarker))),
    ),
    // Phase 13.1 — the CLIENT shell landing. A distinct marker from /home so a
    // CLIENT landing on '/' (the bug) vs '/home' (the fix) is unambiguous.
    GoRoute(
      path: RouteNames.clientHome,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text(_clientHomeMarker))),
    ),
    GoRoute(
      path: RouteNames.masterProfile,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text(_masterProfileMarker))),
    ),
    // Phase 21.8 — the shared SALON_OWNER/SALON_ADMIN landing (Salon Shell
    // resolver stopover).
    GoRoute(
      path: RouteNames.salonHome,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text(_salonHomeMarker))),
    ),
  ],
);

// ---------------------------------------------------------------------------
// Pump helper
// ---------------------------------------------------------------------------

/// Pumps [DoneScreen] inside a [UncontrolledProviderScope] backed by a
/// [ProviderContainer] whose auth repository is seeded to resolve
/// [authenticatedUser] as the current user.
///
/// Returns the container so callers can dispose it explicitly if needed;
/// [addTearDown] is always registered inside this helper.
Future<ProviderContainer> _pumpDoneScreen(
  WidgetTester tester, {
  required User authenticatedUser,
  required GoRouter router,
}) async {
  final storage = FakeSecureStorage();
  await storage.writeRefreshToken('seeded-refresh-token');

  final repo = FakeAuthRepository()
    ..refreshResult = _testTokens
    ..meResult = authenticatedUser;

  final container = ProviderContainer(
    retry: beauticaProviderRetry,
    overrides: [
      secureStorageProvider.overrideWith((_) => storage),
      authRepositoryProvider.overrideWith((_) => repo),
    ],
  );
  addTearDown(container.dispose);

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

  // Drain AuthNotifier cold-start restore + DoneScreen post-frame callback.
  await tester.pumpAndSettle();

  return container;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('DoneScreen — role-aware CTA routing', () {
    // -----------------------------------------------------------------------
    // R1 — INDEPENDENT_MASTER routes to /master/profile
    //
    // Regression guard: before this fix the CTA always called
    // context.go(RouteNames.home). After the fix, INDEPENDENT_MASTER must
    // land on /master/profile. This is the highest-priority case because it
    // gates the master's first-use onboarding flow.
    // -----------------------------------------------------------------------
    testWidgets('R1. INDEPENDENT_MASTER: tapping done_to_app navigates to '
        'RouteNames.masterProfile (/master/profile)', (tester) async {
      final router = _makeFullRouter();
      addTearDown(router.dispose);

      await _pumpDoneScreen(
        tester,
        authenticatedUser: _independentMaster,
        router: router,
      );

      // DoneScreen is on screen; master profile stub is not yet visible.
      expect(find.text(_masterProfileMarker), findsNothing);
      expect(find.text(_homeMarker), findsNothing);

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('done_to_app')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('done_to_app')));
      await tester.pumpAndSettle();

      expect(
        find.text(_masterProfileMarker),
        findsOneWidget,
        reason:
            'INDEPENDENT_MASTER must be routed to RouteNames.masterProfile '
            'after tapping the primary CTA — not to /home',
      );
      expect(
        find.text(_homeMarker),
        findsNothing,
        reason:
            'INDEPENDENT_MASTER must NOT land on /home — the home route '
            'is reserved for client and non-master roles',
      );
    });

    // -----------------------------------------------------------------------
    // R2 — CLIENT routes to /home (clientHome), the 5-tab client shell.
    //
    // THE REGRESSION (Site A): before the fix the CTA hardcoded
    // RouteNames.home ('/'), dropping a freshly-registered CLIENT on the
    // no-bottom-bar "Скоро…" placeholder instead of the real ClientShell at
    // '/home'. After the fix the CTA dispatches through roleHomePath(client) →
    // RouteNames.clientHome. This test reproduces the bug: it asserts the CTA
    // lands on the clientHome stub and explicitly NOT on the '/' home stub.
    // -----------------------------------------------------------------------
    testWidgets(
      'R2. CLIENT: tapping done_to_app navigates to RouteNames.clientHome '
      '(/home), NOT RouteNames.home (/)',
      (tester) async {
        final router = _makeFullRouter();
        addTearDown(router.dispose);

        await _pumpDoneScreen(
          tester,
          authenticatedUser: _client,
          router: router,
        );

        expect(find.text(_clientHomeMarker), findsNothing);
        expect(find.text(_homeMarker), findsNothing);
        expect(find.text(_masterProfileMarker), findsNothing);

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('done_to_app')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey<String>('done_to_app')));
        await tester.pumpAndSettle();

        expect(
          find.text(_clientHomeMarker),
          findsOneWidget,
          reason:
              'CLIENT must be routed to RouteNames.clientHome (/home — the '
              '5-tab client shell) after tapping the primary CTA',
        );
        expect(
          find.text(_homeMarker),
          findsNothing,
          reason:
              'CLIENT must NOT land on RouteNames.home (/) — that no-bottom-bar '
              '"Скоро…" placeholder is exactly the routing bug under guard',
        );
        expect(
          find.text(_masterProfileMarker),
          findsNothing,
          reason: 'CLIENT must NOT be sent to /master/profile',
        );
      },
    );

    // -----------------------------------------------------------------------
    // R3 — SALON_OWNER routes to /salons/home (Phase 21.8 Salon Shell landing)
    //
    // roleHomePath has a dedicated `UserRole.salonOwner => RouteNames
    // .salonHome` arm (Phase 21.8) — SALON_OWNER no longer falls through the
    // `_ => RouteNames.home` wildcard the way it did before that phase. This
    // test pins the CURRENT landing and guards against a future regression
    // that collapses SALON_OWNER back onto the wildcard (or onto
    // /master/profile).
    // -----------------------------------------------------------------------
    testWidgets('R3. SALON_OWNER: tapping done_to_app navigates to '
        'RouteNames.salonHome (/salons/home)', (tester) async {
      final router = _makeFullRouter();
      addTearDown(router.dispose);

      await _pumpDoneScreen(
        tester,
        authenticatedUser: _salonOwner,
        router: router,
      );

      expect(find.text(_salonHomeMarker), findsNothing);
      expect(find.text(_homeMarker), findsNothing);
      expect(find.text(_masterProfileMarker), findsNothing);

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('done_to_app')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('done_to_app')));
      await tester.pumpAndSettle();

      expect(
        find.text(_salonHomeMarker),
        findsOneWidget,
        reason:
            'SALON_OWNER must land on RouteNames.salonHome (the Phase 21.8 '
            'Salon Shell landing) — not the bare /home wildcard placeholder',
      );
      expect(
        find.text(_homeMarker),
        findsNothing,
        reason:
            'SALON_OWNER must NOT fall through to the wildcard '
            'RouteNames.home — that was the pre-Phase-21.1 placeholder',
      );
      expect(
        find.text(_masterProfileMarker),
        findsNothing,
        reason: 'SALON_OWNER must NOT be routed to /master/profile',
      );
    });
  });
}
