// Router-tier chrome guard — the durable net for the f929caf bug class.
//
// For EACH role in the matrix, this boots the REAL `appRouterProvider` under an
// authenticated session of that role, drives the router through the real
// redirect to the role's landing destination, and asserts that the role's
// EXPECTED navigation chrome actually rendered (`findsOneWidget`) — or, for the
// intentional "coming soon" no-chrome rows, that NO bottom bar rendered.
//
// WHY THIS WOULD HAVE CAUGHT THE ORIGINAL BUG
// -------------------------------------------
// The defect: a CLIENT was delivered to `/` (the bare placeholder) instead of
// `/home` (ClientShell). The CLIENT row asserts, after the real redirect,
// `find.byType(ClientBottomNav)` is findsOneWidget. On the buggy dispatch the
// router would have settled on `/` → the `_Placeholder` scaffold, where
// ClientBottomNav is ABSENT → `findsOneWidget` fails. Unlike the old route-string
// tests, this asserts the CHROME the user actually sees, not just a path. The
// master row is the symmetric guard for INDEPENDENT_MASTER → VelvetBottomNavBar.
//
// This is the natural generalization of app_router_no_leaked_timer_test.dart
// (which only landed the INDEPENDENT_MASTER `/master/profile` case): the same
// production-router harness, now parametrised over every role + asserting chrome.
//
// Note: `test/` is excluded from the no_raw_ui_strings lint. Every assertion
// keys off route constants and widget TYPES — never raw Ukrainian text (mobile-
// qa M2). All pumps are BOUNDED (the real auth/profile screens animate, so
// pumpAndSettle would never quiesce — same constraint as the leaked-timer test).

import 'dart:async';

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/profile_avatar.dart';
import 'package:beautica_mobile/features/rating/application/my_rating_notifier.dart';
import 'package:beautica_mobile/features/rating/domain/client_rating.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/shell/presentation/client_shell.dart';
import 'package:beautica_mobile/features/shell/presentation/widgets/client_bottom_nav.dart';
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
import 'role_landing_chrome_matrix.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

void main() {
  group('each role lands on a screen that shows its expected nav chrome', () {
    // Park the splash gate in the past so authRedirect does not pin the router
    // on /splash waiting for the minimum splash duration to elapse.
    setUp(
      () => AppStartTime.setStartForTest(
        DateTime.now().subtract(const Duration(seconds: 5)),
      ),
    );
    tearDown(AppStartTime.resetForTest);

    test('matrix covers every UserRole exactly once', () {
      assertMatrixCoversAllRoles();
    });

    // ── One router-tier test per matrix row (data-driven, no copy-paste) ────
    for (final row in roleLandingMatrix) {
      testWidgets(
        row.hasChrome
            ? '${row.role.name} lands on ${row.expectedLandingPath} showing '
                  '${row.chromeDescription}'
            : '${row.role.name} lands on ${row.expectedLandingPath} with no '
                  'bottom bar (intentional coming-soon)',
        (tester) async {
          final container = _authedContainer(row.role);
          final router = container.read(appRouterProvider);
          addTearDown(router.dispose);

          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: _RouterApp(router: router),
            ),
          );
          // Bounded pump — the real auth/profile screens animate; pumpAndSettle
          // would never quiesce. A few frames let the redirect resolve and the
          // landing screen build.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          if (row.locationIsTransient) {
            // Phase 21.8 — the resolver row (SALON_OWNER/SALON_ADMIN) lands
            // on `expectedLandingPath` (roleHomePath's own contract — still
            // pinned below) and then, from its own postFrame callback, moves
            // ON to the real chrome-bearing shell once its data resolves.
            // Give that one extra hop room to complete before asserting
            // chrome, then assert the FINAL location is no longer the
            // transient stopover.
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 100));
            expect(
              _currentLocation(router),
              isNot(equals(row.expectedLandingPath)),
              reason:
                  '${row.role.name} is declared `locationIsTransient` (the '
                  'resolver at ${row.expectedLandingPath} forwards onward) '
                  'but the router never left it — the postFrame navigation '
                  'to the real shell did not fire.',
            );
          } else {
            // The production redirect must deliver the role to the matrix's
            // declared landing path (value finder — not raw text).
            expect(
              _currentLocation(router),
              equals(row.expectedLandingPath),
              reason:
                  '${row.role.name} must land on ${row.expectedLandingPath}; '
                  'the live redirect sent it to ${_currentLocation(router)}. '
                  'A wrong path here is the f929caf dispatch bug.',
            );
          }

          if (row.hasChrome) {
            // THE durable assertion: the role's nav chrome actually rendered.
            // On the original bug a CLIENT would have settled on "/" (the
            // placeholder) where ClientBottomNav is absent → this fails.
            expect(
              row.chromeFinder!,
              findsOneWidget,
              reason:
                  '${row.role.name} landed on ${row.expectedLandingPath} but '
                  '${row.chromeDescription} did not render. The navigation '
                  'never delivered the user to the screen that HOSTS the bar — '
                  'this is exactly the f929caf class of bug (element exists, '
                  'user never reaches it).',
            );
          } else {
            // Intentional no-chrome landing. Assert NEITHER known bottom bar is
            // present. Reason on record: ${row.comingSoonReason}. A future
            // change that gives this role a shell flips the matrix row → this
            // branch stops running and the chrome branch above starts asserting.
            expect(
              find.byType(ClientBottomNav),
              findsNothing,
              reason:
                  '${row.role.name} is coming-soon (no chrome by design) but a '
                  'ClientBottomNav rendered. ${row.comingSoonReason}',
            );
            expect(
              find.byType(VelvetBottomNavBar),
              findsNothing,
              reason:
                  '${row.role.name} is coming-soon (no chrome by design) but a '
                  'VelvetBottomNavBar rendered. ${row.comingSoonReason}',
            );
            // And the chrome-bearing shells must not have mounted at all.
            expect(find.byType(ClientShell), findsNothing);
          }
        },
      );
    }
  });

  // ---------------------------------------------------------------------
  // mobile-qa gap-closure (2026-08-28) — the H1b double-mount hazard.
  //
  // The SALON_OWNER/SALON_ADMIN row above (`_kLandingSalonId` in BOTH the
  // owner's `mySalonsProvider` fixture and the admin's `User.salonId`)
  // proves the shell mounts `SalonManagementProfileScreen(embedded: true)`
  // TWICE (Салон + Команда) without crashing — but it CANNOT prove the H1b
  // fix (`if (widget.embedded) return;` at the top of that screen's own
  // `_bounceIfNotOwned`) is load-bearing: `salons.any(...)` is already TRUE
  // for that fixture, so every listener — the shell's own, and either
  // embedded instance's, guarded or not — reaches the exact same `return;`
  // and NEVER calls `context.go` at all. A test that cannot observe the
  // guarded code path prove nothing about it (mobile-qa M14).
  //
  // This group drives the mismatched case instead (mySalonsProvider
  // resolves EXCLUDING the shell's own salonId, so the bounce ACTUALLY
  // fires) and counts real `GoRouter.go(...)` calls via a spy subclass —
  // NOT via final location or `NavigatorObserver.didPush` count, both of
  // which were measured to read as 1 in EITHER case: go_router coalesces
  // multiple synchronous `go()` calls to the same destination into a single
  // Navigator push, so "did the router still land in the right place" is
  // silently blind to the extra calls. Only counting the calls THEMSELVES
  // (not their downstream effect) distinguishes guard-present from
  // guard-absent.
  group('H1b double-mount hazard — the shell owns exactly ONE ownership '
      'listener for both embedded tabs', () {
    setUp(
      () => AppStartTime.setStartForTest(
        DateTime.now().subtract(const Duration(seconds: 5)),
      ),
    );
    tearDown(AppStartTime.resetForTest);

    testWidgets(
      'mySalonsProvider resolves EXCLUDING the shell\'s salonId, after BOTH '
      'embedded tabs (Салон + Команда) have been visited -> GoRouter.go is '
      'called exactly ONCE, not twice (or three times)',
      (tester) async {
        final deferred = _H1bDeferredMySalons();
        final container = ProviderContainer(
          retry: (_, _) => null,
          overrides: [
            authProvider.overrideWith(
              () => _FixedAuthNotifier(_h1bOwnerSession),
            ),
            authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
            secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
            mySalonsProvider.overrideWith(() => deferred),
            salonManagementProfileProvider(
              _kH1bSalonId,
            ).overrideWith(_H1bSettledSalonManagementProfile.new),
          ],
        );
        addTearDown(container.dispose);

        final router = _SpyGoRouter(
          initialLocation: RouteNames.salonShell(_kH1bSalonId),
          routes: <RouteBase>[
            GoRoute(
              path: '/salons/:salonId/shell',
              builder: (context, state) =>
                  SalonShellScreen(salonId: state.pathParameters['salonId']!),
            ),
            // roleHomePath(salonOwner) — the bounce target. A trivial marker
            // is enough; this group asserts on CALL COUNT, not on what the
            // destination renders.
            GoRoute(
              path: RouteNames.salonHome,
              builder: (context, state) =>
                  const Scaffold(key: Key('h1b-bounce-target')),
            ),
          ],
        );
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
        await tester.pump(const Duration(milliseconds: 100));

        // Visit BOTH embedded tabs BEFORE mySalonsProvider resolves, so both
        // `SalonManagementProfileScreen` instances (Салон + Команда) are
        // alive simultaneously in the real `IndexedStack` — the actual H1b
        // double-mount precondition (a fixture that never visits Команда
        // only ever has ONE embedded instance alive, which cannot exercise
        // the double-listener hazard regardless of the guard).
        await tester.tap(find.byKey(const Key('salon-nav-tile-2')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.byKey(const Key('salon-nav-tile-0')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // NOW resolve mySalonsProvider to a list that EXCLUDES the shell's
        // own salonId — every listener that reaches its `context.go` call
        // actually fires one.
        deferred.resolve(const <Salon>[
          Salon(id: 'a-different-salon', name: 'Different'),
        ]);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(
          router.goCount,
          equals(1),
          reason:
              'exactly ONE listener (the shell\'s own) must call '
              'GoRouter.go — two or three means the embedded screen\'s own '
              '`_bounceIfNotOwned` fired too (the H1b hazard: `if '
              '(widget.embedded) return;` missing or bypassed).',
        );
      },
    );
  });
}

// ---------------------------------------------------------------------------
// H1b group harness — deliberately SEPARATE fixtures from
// `_authedContainer`'s (that harness's salon id is always IN the owner's
// list, which is exactly what makes its own H1b coverage vacuous — see the
// group doc above).
// ---------------------------------------------------------------------------

const String _kH1bSalonId = 'h1b-probe-salon';

const _h1bOwnerUser = User(
  id: 'h1b-owner-1',
  email: 'h1b-owner@example.com',
  role: UserRole.salonOwner,
  firstName: 'Test',
  lastName: 'Owner',
);

const AsyncData<AuthSession> _h1bOwnerSession = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _h1bOwnerUser, accessToken: 'token'),
);

/// [MySalons] stub that resolves only once [resolve] is called — lets the
/// test visit both embedded tabs (with the shell's salonId still "owned" by
/// default, since nothing has resolved yet) BEFORE the mismatched list
/// arrives and the bounce actually fires.
class _H1bDeferredMySalons extends MySalons {
  final Completer<List<Salon>> _completer = Completer<List<Salon>>();

  @override
  Future<List<Salon>> build() => _completer.future;

  void resolve(List<Salon> salons) => _completer.complete(salons);
}

/// [SalonManagementProfile] stub that resolves immediately — settles BOTH
/// embedded tabs (same family key, `_kH1bSalonId`) off the real Dio stack.
class _H1bSettledSalonManagementProfile extends SalonManagementProfile {
  @override
  Future<SalonManagementProfileData> build(String salonId) async => (
    const Salon(id: _kH1bSalonId, name: 'H1b Probe Salon'),
    const <SalonStaffMember>[],
  );
}

/// [GoRouter] subclass that counts real `go(...)` calls. Necessary because
/// go_router coalesces multiple synchronous `go()` calls to the SAME
/// destination into a single Navigator push (measured directly — see the
/// group doc above) — final location and `NavigatorObserver.didPush` count
/// are both blind to the extra calls this hazard produces. `GoRouter`'s
/// plain unnamed constructor is a FACTORY (cannot be `super()`-called from a
/// subclass), so this goes through the generative `GoRouter.routingConfig`
/// constructor instead, backed by a plain `ValueNotifier` (a
/// `ValueListenable`) rather than the package-private `_ConstantRoutingConfig`
/// the factory itself uses internally.
class _SpyGoRouter extends GoRouter {
  _SpyGoRouter({
    required List<RouteBase> routes,
    required String initialLocation,
  }) : super.routingConfig(
         routingConfig: ValueNotifier<RoutingConfig>(
           RoutingConfig(routes: routes),
         ),
         initialLocation: initialLocation,
       );

  int goCount = 0;

  @override
  void go(String location, {Object? extra}) {
    goCount++;
    super.go(location, extra: extra);
  }
}

// ---------------------------------------------------------------------------
// Harness (generalised from app_router_no_leaked_timer_test.dart).
// ---------------------------------------------------------------------------

/// Builds a ProviderContainer with an authenticated session for [role] and the
/// settled fakes that keep the landed screen off the real Dio stack (so the
/// master-profile landing resolves synchronously and schedules no wall-clock
/// timer — same overrides the leaked-timer guard relies on).
ProviderContainer _authedContainer(UserRole role) {
  final container = ProviderContainer(
    retry: beauticaProviderRetry,
    overrides: [
      authProvider.overrideWith(() => _FixedAuthNotifier(_sessionFor(role))),
      authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
      secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
      // Settle the master-profile data path (used only by the master row).
      masterProfileProvider.overrideWith(_SettledMasterProfileNotifier.new),
      masterRepositoryProvider.overrideWith((_) => FakeMasterRepository()),
      serviceRepositoryProvider.overrideWith((_) => FakeServiceRepository()),
      // MasterProfileScreen's categories section watches
      // `approvedCategoriesProvider`, which builds via the REAL authenticated
      // Dio (it bypasses serviceRepositoryProvider). Settle it with an empty
      // list so no 15s connect-timeout Timer outlives the bounded `pump`.
      approvedCategoriesProvider.overrideWith(
        (ref) async => const <ServiceCategoryOption>[],
      ),
      // Settle the CLIENT Home-Hub data path (used only by the client row).
      //
      // HomeHubScreen watches five async providers. clientProfileProvider
      // derives from clientEditProfileProvider, which fires a REAL GET /users/me
      // on the authenticated Dio. Under this harness that request never resolves,
      // so Riverpod 3.x schedules a ~200ms `triggerRetry` Timer that outlives the
      // bounded `pump(100ms)` → `!timersPending`. Override every home-hub data
      // provider with a settled fake so none enters the error→retry path and no
      // wall-clock Timer is scheduled (same settle approach as
      // masterProfileProvider / approvedCategoriesProvider above; NO
      // `pump(Duration)` wait-out hack — mobile-qa M6).
      clientProfileProvider.overrideWith(
        (ref) async => const ClientProfileSummary(
          firstName: 'Test',
          lastName: 'Client',
          city: '',
          phone: '',
          clientRating: null,
          memberSinceYear: 2026,
        ),
      ),
      nextAppointmentProvider.overrideWith((ref) async => null),
      favoriteMastersProvider.overrideWith(
        (ref) async => const <FavoriteMasterItem>[],
      ),
      beautyTimelineProvider.overrideWith(
        (ref) async => const <TimelineEntry>[],
      ),
      // `_StatPillsRow` (home_hub_screen.dart) watches `myRatingProvider` — the
      // fifth home-hub data provider, added after this harness was written.
      // Its REAL build (`my_rating_notifier.dart`) starts a 5-minute
      // `ref.keepAlive()` TTL `Timer` unconditionally at build time — cancelled
      // correctly via `ref.onDispose` on provider disposal, but disposal only
      // happens when `container.dispose()` runs (`addTearDown`, AFTER this
      // test's body returns), which is AFTER `TestWidgetsFlutterBinding`'s
      // `!timersPending` invariant check. So a genuine, unavoidable-by-
      // production-code-changes 5-minute Timer is still pending at that check
      // no matter how fast the underlying future resolves — same shape as the
      // Dio-timeout leaks `app_router_no_leaked_timer_test.dart` documents.
      // Settling with an override (bypassing `myRating`'s build body, and thus
      // the Timer, entirely) is the SAME project-blessed fix that file's header
      // comment prescribes, matching the pattern already applied to the other
      // four home-hub providers above.
      myRatingProvider.overrideWith((ref) async => const ClientRating()),
      // Phase 21.8 — SALON_OWNER's row now lands on SalonHomeResolverScreen
      // (RouteNames.salonHome), which watches mySalonsProvider to pick the
      // primary salon and forward to its shell. Settle it synchronously,
      // with one PRIMARY salon at `_kLandingSalonId`, so the resolver has
      // something to forward to and does not schedule a real Dio timeout
      // Timer — mirrors every settled provider above for the exact same
      // leaked-timer reason.
      mySalonsProvider.overrideWith(_SettledMySalons.new),
      // The shell's Салон + Команда tabs both mount
      // `SalonManagementProfileScreen(salonId: _kLandingSalonId, embedded:
      // true)`, which watches this REAL family provider. Settle the ONE
      // instance keyed by `_kLandingSalonId` — used by BOTH the
      // SALON_OWNER row (its resolved primary salon) and the SALON_ADMIN
      // row (`session.user.salonId`, given the same fixed id below) — so
      // neither leaves a real Dio call pending.
      salonManagementProfileProvider(
        _kLandingSalonId,
      ).overrideWith(_SettledSalonManagementProfile.new),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

AsyncData<AuthSession> _sessionFor(UserRole role) => AsyncData<AuthSession>(
  AuthSession.authenticated(user: _userFor(role), accessToken: 'token'),
);

User _userFor(UserRole role) => User(
  id: 'u-${role.name}',
  email: '${role.name}@example.com',
  role: role,
  firstName: 'Test',
  lastName: role.name,
  // Phase 21.8 — SALON_ADMIN's landing (`SalonHomeResolverScreen`) reads
  // `session.user.salonId` SYNCHRONOUSLY (no provider). Every other role
  // ignores this field, so setting it unconditionally is harmless.
  salonId: role == UserRole.salonAdmin ? _kLandingSalonId : null,
);

String _currentLocation(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

/// [MasterProfile] stub that resolves immediately so the master landing builds
/// without the real repository firing a Dio request.
class _SettledMasterProfileNotifier extends MasterProfile {
  @override
  Future<Master> build() async => const Master(
    id: 'u-independentMaster',
    firstName: 'Test',
    lastName: 'Master',
    avgRating: 0,
    reviewCount: 0,
    type: MasterType.independentMaster,
  );
}

/// Phase 21.8 — the fixed salon id both the SALON_OWNER row's (settled,
/// single-primary) `mySalonsProvider` fixture AND the SALON_ADMIN row's
/// `User.salonId` resolve to, so ONE `salonManagementProfileProvider`
/// override (below) covers the shell's Салон/Команда tabs for both roles.
const String _kLandingSalonId = 'salon-landing-test';

/// [MySalons] stub that resolves immediately to a single PRIMARY salon —
/// mirrors `_SettledMasterProfileNotifier` above. `mySalonsProvider` is now
/// `@Riverpod(keepAlive: true)` (mobile-perf HIGH follow-up, 2026-08-28), so
/// the plain `mySalonsProvider.overrideWith((ref) async => ...)` function
/// override this file previously used no longer type-checks — a
/// keepAlive-class provider's `overrideWith` takes a notifier FACTORY, not a
/// build function.
///
/// Phase 21.8 — was an empty list (the SALON_OWNER row used to land on the
/// My Salons hub itself, which renders fine with zero salons). It now lands
/// on `SalonHomeResolverScreen`, which needs at least one salon to forward
/// to — an empty list would send it to the hub instead, and the row's
/// declared chrome (`SalonBottomNav`) would never render.
class _SettledMySalons extends MySalons {
  @override
  Future<List<Salon>> build() async => const <Salon>[
    Salon(id: _kLandingSalonId, name: 'Test Salon', isPrimary: true),
  ];
}

/// [SalonManagementProfile] stub that resolves immediately — settles the
/// Salon Shell's embedded Салон/Команда tabs (`_kLandingSalonId`) off the
/// real Dio stack, mirroring `_SettledMasterProfileNotifier`'s own reasoning.
class _SettledSalonManagementProfile extends SalonManagementProfile {
  @override
  Future<SalonManagementProfileData> build(String salonId) async => (
    const Salon(id: _kLandingSalonId, name: 'Test Salon'),
    const <SalonStaffMember>[],
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
