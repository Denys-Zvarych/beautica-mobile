// Regression — MasterProfileScreen must render NO back-chevron affordance,
// and must stay non-poppable when reached via `context.go(...)`.
//
// BUG THIS GUARDS
// ────────────────
// MasterProfileScreen is the INDEPENDENT_MASTER's tab-root/home screen —
// reached ONLY via `context.go(RouteNames.masterProfile)` (never `push`),
// from 6 call sites plus the role's redirect landing target. It is therefore
// always first in its Navigator stack (`isFirst == true`), with nothing below
// it to pop to.
//
// It previously rendered `ProfileScaffold(...)` with the default
// `showBack: true`, which wired a back-chevron button into `VelvetTopBar`
// whose `onBack` called `context.pop()`. Tapping it threw
// `GoError('There is nothing to pop')` — this was the root cause of the
// "swipe back on independent master profile doesn't work" complaint (the
// swipe GESTURE itself was already correctly disarmed by Flutter's `isFirst`
// check on `popGestureEnabled` — only the explicit chevron button was wired
// wrong).
//
// FIX
// ───
// `master_profile_screen.dart` now passes `showBack: false` to
// `ProfileScaffold`, so `VelvetTopBar` receives `onBack: null` and renders no
// chevron at all — see `ProfileScaffold.build()` (`onBack: showBack ? () =>
// context.pop() : null`) and `VelvetTopBar.build()` (`if (onBack != null) ...`).
//
// WHAT THIS FILE COVERS
// ──────────────────────
// 1. Widget test — pumps MasterProfileScreen the way it is actually reached
//    (as the sole/root route of a test GoRouter, mirroring
//    `master_profile_screen_refresh_test.dart`'s `_buildRouter()` pattern) and
//    asserts:
//      a. the trailing menu button (Key('btn-menu-master')) IS present.
//      b. no back-chevron icon (Icons.arrow_back_ios_new_rounded — the exact
//         `IconData` `VelvetTopBar` renders for `onBack`) is present anywhere
//         in the tree.
// 2. Router-level test — builds a 2-route GoRouter (an arbitrary "elsewhere"
//    stub screen representing one of the 6 real call sites + the real
//    `/master/profile` route), taps a button that calls
//    `context.go(RouteNames.masterProfile)` exactly like the real call sites
//    do, and asserts `router.canPop()` is `false` afterwards. This guards
//    against a future regression where the route becomes push-reachable, or
//    a back affordance is reintroduced further up the stack.
//
// Both tests would FAIL against the pre-fix code: with `showBack: true` (the
// old default), test 1b finds the chevron icon; `router.canPop()` in test 2
// would still read `false` (canPop() only reflects the router's own stack
// depth, not the button's wiring) — the regression that mattered for THAT
// test class was the button's `onBack` throwing `GoError` on tap, which is a
// runtime crash, not a `canPop()` state change. Test 1b is therefore the
// primary regression guard; test 2 pins the complementary router-shape
// invariant (this route must never become poppable) so a *different* future
// regression — the route becoming reachable via `push` — is also caught.

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
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Mocks / fakes — mirrors master_profile_screen_refresh_test.dart
// ─────────────────────────────────────────────────────────────────────────────

class _MockServiceRepository extends Mock implements ServiceRepository {}

const _stubUser = User(
  id: 'u-back-1',
  email: 'back@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Тест',
  lastName: 'Майстер',
);

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _stubUser, accessToken: 'tok');
}

const _profile = Master(
  id: 'u-back-1',
  firstName: 'Тест',
  lastName: 'Майстер',
  avgRating: 4.9,
  reviewCount: 5,
  type: MasterType.independentMaster,
);

/// Hand-written fake — see master_profile_screen_refresh_test.dart for why a
/// mocktail mock is avoided here (synchronous return, no fallback plumbing).
class _FakeMasterRepository implements MasterRepository {
  @override
  Future<Master> getMyProfile(String masterId) async => _profile;

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

_MockServiceRepository _emptyServiceRepo() {
  final repo = _MockServiceRepository();
  when(
    () => repo.listMyServices(),
  ).thenAnswer((_) async => const <MasterService>[]);
  when(() => repo.fetchApprovedCategories()).thenAnswer((_) async => const []);
  return repo;
}

List<Object> _overrides() => <Object>[
  authProvider.overrideWith(_StubAuthNotifier.new),
  masterRepositoryProvider.overrideWithValue(_FakeMasterRepository()),
  serviceRepositoryProvider.overrideWithValue(_emptyServiceRepo()),
  // mobile-qa M4 / project_approved_categories_provider_override_footgun:
  // the profile's _ProfileCategoriesSection watches approvedCategoriesProvider
  // directly (sourced from categoryRequestApiProvider → the real Dio), NOT
  // through serviceRepositoryProvider — overriding only the repo fake leaves
  // it hitting the real network under `flutter test`, leaking a connect
  // Timer and failing the pending-timers invariant at test teardown.
  approvedCategoriesProvider.overrideWith(
    (ref) async => const <ServiceCategoryOption>[],
  ),
];

void main() {
  group('MasterProfileScreen — no back affordance (tab-root screen)', () {
    // ── 1a/1b. Widget-level: menu button present, back-chevron absent ───────
    testWidgets(
      'renders btn-menu-master but NO back-chevron icon when pumped as the '
      'sole/root route',
      (tester) async {
        // Pumped exactly like the refresh test's harness: MasterProfileScreen
        // is the ONLY route registered, at the router's initialLocation — the
        // same shape it has in production (isFirst == true, nothing to pop to).
        final router = GoRouter(
          initialLocation: '/',
          routes: <RouteBase>[
            GoRoute(
              path: '/',
              pageBuilder: (context, state) =>
                  const NoTransitionPage<void>(child: MasterProfileScreen()),
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: _overrides().cast(),
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('uk'),
            ),
          ),
        );

        await tester.pump(); // start async providers
        await tester.pump(); // data emission from fakes
        // Settle the 1100 ms one-shot entrance AnimationController
        // (`_MasterProfileScreenState._controller`, forwarded exactly once
        // from `_startReveal()` when the data state first arrives — never
        // repeats) rather than guessing a fixed pump duration comfortably
        // above 1100 ms. `pumpAndSettle()` converges the instant the
        // controller completes, whatever that takes, and there is no other
        // ticking animation in the loaded tree to keep it spinning.
        await tester.pumpAndSettle();

        // (a) Trailing menu button must be present — the screen's only
        // top-bar action; proves ProfileScaffold still receives `trailing`.
        expect(
          find.byKey(const Key('btn-menu-master')),
          findsOneWidget,
          reason:
              'The trailing menu button (btn-menu-master) must always be '
              'present on MasterProfileScreen — its absence would mean '
              'ProfileScaffold lost its `trailing` wiring entirely.',
        );

        // (b) No back-chevron anywhere in the tree. Icons.arrow_back_ios_new_rounded
        // is the exact IconData VelvetTopBar renders for its back button
        // (see velvet_top_bar.dart) — it is only built when `onBack != null`.
        expect(
          find.byIcon(Icons.arrow_back_ios_new_rounded),
          findsNothing,
          reason:
              'MasterProfileScreen is always first in its Navigator stack '
              '(reached only via context.go(...), never push) — there is '
              'nothing to pop back to. A back-chevron here means '
              'ProfileScaffold reverted to its `showBack: true` default (or '
              'the explicit `showBack: false` was removed from '
              'master_profile_screen.dart), which wires VelvetTopBar\'s '
              'onBack to context.pop() and throws '
              "GoError('There is nothing to pop') when tapped — the exact "
              'bug this test guards against.',
        );
      },
    );

    // ── 2. Router-level: context.go(masterProfile) leaves canPop() false ────
    testWidgets('REGRESSION: after context.go(RouteNames.masterProfile) from a '
        'representative call site, the route is NOT poppable', (tester) async {
      // Two-route router: an arbitrary "elsewhere" stub screen (standing in
      // for one of the 6 real call sites — e.g. location_edit_screen.dart's
      // `context.go(RouteNames.masterProfile)` after a successful save) plus
      // the real production masterProfile route.
      final router = GoRouter(
        initialLocation: '/elsewhere',
        routes: <RouteBase>[
          GoRoute(
            path: '/elsewhere',
            builder: (context, state) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const Key('btn-go-master-profile'),
                  onPressed: () => context.go(RouteNames.masterProfile),
                  child: const Text('go to profile'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: RouteNames.masterProfile,
            builder: (context, state) => const MasterProfileScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides().cast(),
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
          ),
        ),
      );
      await tester.pump();

      // Sanity: we start off the profile route, on a poppable-irrelevant
      // stub, then navigate via context.go — exactly as the 6 real call
      // sites do (contacts_edit_screen.dart, location_edit_screen.dart,
      // working_hours_screen.dart, master_schedule_screen.dart,
      // settings_hub_screen.dart, and the role-redirect landing target).
      await tester.tap(find.byKey(const Key('btn-go-master-profile')));
      await tester.pump();
      await tester.pump(); // let the route swap settle
      // Settle the 1100 ms one-shot entrance AnimationController rather than
      // guessing a fixed pump duration above it — see the identical comment
      // in the first test in this file for why pumpAndSettle() is safe here
      // (no repeating animation in the loaded tree).
      await tester.pumpAndSettle();

      // The menu button confirms MasterProfileScreen is now on screen.
      expect(
        find.byKey(const Key('btn-menu-master')),
        findsOneWidget,
        reason: 'MasterProfileScreen must be rendered after context.go(...)',
      );

      expect(
        router.canPop(),
        isFalse,
        reason:
            'context.go(RouteNames.masterProfile) must REPLACE the stack, '
            'leaving canPop() false. If this ever becomes true, either the '
            'route was changed to be push-reachable, or a redirect chain '
            'has left a stale entry below it — both would resurrect the '
            'conditions for a back affordance to legitimately appear here, '
            'which MasterProfileScreen is not built to handle '
            '(showBack: false is hardcoded).',
      );
    });
  });
}
