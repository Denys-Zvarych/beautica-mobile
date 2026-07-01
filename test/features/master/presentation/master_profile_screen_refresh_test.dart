// Regression tests — pull-to-refresh on MasterProfileScreen.
//
// WHAT THIS FILE COVERS
// ─────────────────────
// MasterProfileScreen wires ProfileScaffold with an [onRefresh] callback that
// invalidates BOTH:
//   • `masterProfileProvider`  — the master's own profile.
//   • `servicesListProvider`   — the live service list shown on the profile.
// then awaits `masterProfileProvider.future`.
//
// These tests confirm the wiring is correct: a pull-down fling causes the
// master profile repository to be re-queried. They guard against someone
// removing an invalidation call or breaking the AppRefreshIndicator wire in
// ProfileScaffold.
//
// STRATEGY
// ────────
// • The REAL `masterProfileProvider` (MasterProfile AsyncNotifier) is NOT
//   stubbed — if we stub `build()` to a static value the `refresh()` method
//   short-circuits before ever calling `masterRepositoryProvider`. We need the
//   genuine notifier so the full invalidation + re-fetch chain runs.
// • `masterRepositoryProvider` is overridden with a counting fake that returns
//   a fixed profile and records how many times `getMyProfile` was called.
//   A count > baseline proves the re-fetch fired.
// • `serviceRepositoryProvider` is a mocktail mock configured to return an
//   empty list — the profile screen watches servicesListProvider which in turn
//   reads serviceRepositoryProvider. We must override it to avoid real I/O.
// • `authProvider` is stubbed to return a fixed Authenticated session.
// • Finders use source Key constants — never raw localised strings (M2).
// • `pumpAndSettle` is NOT used after the pull gesture because
//   masterProfileProvider is keepAlive: true. A Riverpod-internal disposal
//   link behaves like an always-pending async operation in the widget tree,
//   preventing settlement. Bounded pumps are used with inline comments (M6).

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/domain/master_update.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Mocks
// ─────────────────────────────────────────────────────────────────────────────

class _MockServiceRepository extends Mock implements ServiceRepository {}

// ─────────────────────────────────────────────────────────────────────────────
// Stub auth
// ─────────────────────────────────────────────────────────────────────────────

const _stubUser = User(
  id: 'u-refresh-1',
  email: 'refresh@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Тест',
  lastName: 'Майстер',
);

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _stubUser, accessToken: 'tok');
}

// ─────────────────────────────────────────────────────────────────────────────
// Counting fake MasterRepository
// ─────────────────────────────────────────────────────────────────────────────

const _profile = Master(
  id: 'u-refresh-1',
  firstName: 'Тест',
  lastName: 'Майстер',
  avgRating: 4.9,
  reviewCount: 5,
  type: MasterType.independentMaster,
);

/// A fake [MasterRepository] that returns a fixed profile and counts calls.
/// Implemented as a hand-written fake (not a mocktail mock) so `getMyProfile`
/// can be synchronous — no `registerFallbackValue` plumbing needed, and the
/// call count is trivially stable across any ordering.
class _CountingFakeMasterRepository implements MasterRepository {
  int getMyProfileCallCount = 0;

  @override
  Future<Master> getMyProfile(String masterId) async {
    getMyProfileCallCount++;
    return _profile;
  }

  @override
  Future<Master> getMasterById(String masterId) async => _profile;

  @override
  Future<void> updateMyProfile(MasterUpdate update) async {}

  @override
  Future<void> updateLocality({
    required String cityId,
    String? districtId,
    required String street,
    required String buildingNo,
    String? locationNote,
  }) async {}
}

// ─────────────────────────────────────────────────────────────────────────────
// Router — MasterProfileScreen uses context.go() so it needs GoRouter
// ─────────────────────────────────────────────────────────────────────────────

GoRouter _buildRouter() => GoRouter(
  initialLocation: '/',
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      pageBuilder: (context, state) =>
          const NoTransitionPage<void>(child: MasterProfileScreen()),
    ),
  ],
);

// ─────────────────────────────────────────────────────────────────────────────
// Test harness helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Returns a configured [_MockServiceRepository] that resolves every list
/// method to an empty response — enough for the profile screen to paint its
/// services section without real network I/O.
_MockServiceRepository _emptyServiceRepo() {
  final repo = _MockServiceRepository();
  when(
    () => repo.listMyServices(),
  ).thenAnswer((_) async => const <MasterService>[]);
  when(() => repo.fetchApprovedCategories()).thenAnswer((_) async => const []);
  return repo;
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('MasterProfileScreen — pull-to-refresh', () {
    // ── 1. Initial load calls getMyProfile at least once ────────────────────
    testWidgets('getMyProfile is called at least once on initial load', (
      tester,
    ) async {
      final fakeRepo = _CountingFakeMasterRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Object>[
            authProvider.overrideWith(_StubAuthNotifier.new),
            masterRepositoryProvider.overrideWithValue(fakeRepo),
            serviceRepositoryProvider.overrideWithValue(_emptyServiceRepo()),
          ].cast(),
          child: MaterialApp.router(
            routerConfig: _buildRouter(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
          ),
        ),
      );

      await tester.pump(); // start async providers
      await tester.pump(); // data emission from fakes
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        fakeRepo.getMyProfileCallCount,
        greaterThanOrEqualTo(1),
        reason: 'Profile must be fetched from the repository on initial load',
      );
    });

    // ── 2. Pull-to-refresh re-fetches the master profile ────────────────────
    //
    // Approach:
    //   a. Pump until loaded state (master-profile-name key visible).
    //   b. Record baseline call count.
    //   c. Fling down on the scaffold body's Scrollable to trigger the
    //      AppRefreshIndicator wrapped by ProfileScaffold.
    //   d. Pump through the refresh cycle (fake is synchronous).
    //   e. Assert call count grew by at least 1.
    //
    // NOT using pumpAndSettle after the fling:
    //   masterProfileProvider is `keepAlive: true` — it registers a Riverpod
    //   disposal link that resembles an ever-pending timer, making
    //   pumpAndSettle() hang indefinitely. Bounded pumps are used instead,
    //   each annotated with its purpose (mobile-qa M6 exception).
    testWidgets(
      'REGRESSION: pull-to-refresh invalidates masterProfileProvider and '
      're-fetches the profile from the repository',
      (tester) async {
        final fakeRepo = _CountingFakeMasterRepository();

        await tester.pumpWidget(
          ProviderScope(
            overrides: <Object>[
              authProvider.overrideWith(_StubAuthNotifier.new),
              masterRepositoryProvider.overrideWithValue(fakeRepo),
              serviceRepositoryProvider.overrideWithValue(_emptyServiceRepo()),
            ].cast(),
            child: MaterialApp.router(
              routerConfig: _buildRouter(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('uk'),
            ),
          ),
        );

        // — Settle to loaded state —
        await tester.pump(); // start async providers
        await tester.pump(); // fake futures resolve → AsyncData
        // MasterProfileScreen has a 1100 ms entrance AnimationController.
        // Advance past it so the body content is fully laid out and the
        // SingleChildScrollView (inside ProfileScaffold) is scrollable.
        await tester.pump(const Duration(milliseconds: 1200));

        // Confirm we are in the loaded state.
        expect(
          find.byKey(const Key('master-profile-name')),
          findsOneWidget,
          reason: 'Profile must be in loaded state before the refresh gesture',
        );

        // Baseline.
        final int baselineCount = fakeRepo.getMyProfileCallCount;

        // — Trigger pull-to-refresh —
        // ProfileScaffold uses _buildScrollable() → AppRefreshIndicator wrapping
        // a SingleChildScrollView. We locate the Scrollable inside the
        // MaterialApp body so we don't accidentally drag on the route overlay.
        final scrollableFinder = find.descendant(
          of: find.byType(Scaffold),
          matching: find.byType(Scrollable),
        );
        expect(
          scrollableFinder,
          findsWidgets,
          reason: 'A Scrollable must exist inside the loaded profile scaffold',
        );

        await tester.fling(scrollableFinder.first, const Offset(0, 400), 800);
        // Pump 1: RefreshIndicator intercepts the gesture, calls onRefresh.
        await tester.pump();
        // Pump 2: onRefresh runs (invalidate + await masterProfileProvider.future).
        // The fake resolves synchronously so the future completes here.
        await tester.pump();
        // Pump 3: Riverpod notifier state transitions + keepAlive link setup.
        await tester.pump(const Duration(milliseconds: 50));
        // Pump 4: Material RefreshIndicator 250 ms dismiss animation.
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          fakeRepo.getMyProfileCallCount,
          greaterThan(baselineCount),
          reason:
              'pull-to-refresh must invalidate masterProfileProvider and '
              're-fetch getMyProfile. '
              'If this assertion fails, the onRefresh callback is missing the '
              'ref.invalidate(masterProfileProvider) call OR ProfileScaffold '
              'is not wired to AppRefreshIndicator when onRefresh is provided.',
        );
      },
    );

    // ── 3. AppRefreshIndicator (RefreshIndicator) present in loaded state ───
    testWidgets('RefreshIndicator is present in the loaded state layout', (
      tester,
    ) async {
      final fakeRepo = _CountingFakeMasterRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Object>[
            authProvider.overrideWith(_StubAuthNotifier.new),
            masterRepositoryProvider.overrideWithValue(fakeRepo),
            serviceRepositoryProvider.overrideWithValue(_emptyServiceRepo()),
          ].cast(),
          child: MaterialApp.router(
            routerConfig: _buildRouter(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));

      expect(
        find.byType(RefreshIndicator),
        findsOneWidget,
        reason:
            'ProfileScaffold must include a RefreshIndicator (AppRefreshIndicator) '
            'in the loaded state when onRefresh is wired',
      );
    });
  });
}
