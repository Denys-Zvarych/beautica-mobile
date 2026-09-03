// Phase 285 QA follow-up — widget tests for `runDeleteSalonFlow`
// (`lib/features/salon/presentation/delete_salon_flow.dart`).
//
// WHY THIS FILE EXISTS
// ---------------------
// The production fix (commit `1190685c`) replaced the flow's post-delete
// `context.go('/')` — the bare `RouteNames.home` literal, which resolves to
// the debug `_Placeholder('home')` route (`app_router.dart:593`) — with
// `context.go(roleHomePath(session.user.role))`. Before this file NOTHING
// exercised the flow's own navigation decision directly: the only existing
// coverage was `integration_test/salon_management_profile_flow_test.dart`'s
// owner journey, which proves the end-to-end wiring but not the flow
// function's decision table in isolation (admin branch, unauthenticated
// branch, failure/dismiss branches).
//
// LANDING SUPERSEDED (2026-09-03) — `roleHomePath(session.user.role)` above
// is now HISTORICAL: every delete entry point lands on
// `RouteNames.mySalons` («Мої салони») instead, with no per-caller/per-role
// branch (locked product decision — see `delete_salon_flow.dart`'s current
// header). `should_navigateToMySalons_when_ownerDeletesSalon`/
// `..._whenAdminDeletesSalon` below assert the `my-salons-stub` route, not
// `SalonHomeResolverScreen`.
//
// TWO DEVIATIONS FROM THE PHASE DOC, BOTH DELIBERATE (mobile-qa, 2026-09-02):
//
// Problem A — `_Placeholder` is a PRIVATE class declared inside
// `app_router.dart` (`_Placeholder('home')` at line ~1693), so
// `find.byType(_Placeholder)` cannot compile from this file, and the
// production widget is NOT made public just to satisfy a test (REUSE-FIRST /
// no-scope-creep). Fix: this file's own local router registers a stub at
// `RouteNames.home` (`_PlaceholderStub`) that renders the IDENTICAL shape
// `_Placeholder` does — `Scaffold(body: Center(child: Text('home')))` — and
// every "never renders the placeholder" assertion below checks for THAT
// stub's key. This is meaningful, not decorative: under the mutation check
// (reverting the fix to the `'/'` literal) this file's own router resolves
// `'/'` to this exact stub and the assertion goes red — see the mutation
// results recorded in the phase doc's `## Status` section.
//
// Problem B — a `SALON_ADMIN` cannot reach `runDeleteSalonFlow` through the
// UI at all: `settings_screen.dart`'s `_showDeleteSalonRow` requires
// `isOwner` (`showDeleteSalon && salonId != null && isOwner`, verified
// `settings_screen.dart:187-195`), and `salon_settings_screen.dart`'s ONLY
// caller passes `showDeleteSalon: isOwner` (`salon_settings_screen.dart:186`)
// — never true for an admin. `runDeleteSalonFlow` itself has no such gate
// (authorization is server-side, matching every other repository call in
// this codebase — see the function's own header doc), so
// `should_navigateToSalonHome_when_adminDeletesSalon` calls the PUBLIC
// top-level function directly with an admin session, exactly as an admin
// session would look if a future caller ever wired the row up for them. This
// is not "faking reachability" — `runDeleteSalonFlow` is deliberately
// role-agnostic and this is the documented, supported way to exercise it.
//
// Layer: Widget. Local `GoRouter` (`pumpRoutedApp`), no full `app_router.dart`
// mount — mirrors `salon_home_resolver_screen_test.dart`'s and
// `salon_manage_route_guard_test.dart`'s own minimal-stub-route shape.
// Finders use Keys — never Cyrillic literals (M2 / `forbid_cyrillic_finder`).

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/salon/presentation/delete_salon_flow.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_home_resolver_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_salon_repository.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/velvet_snack_matchers.dart';

const String _kSalonId = 'salon-285-1';
const Key _kRunButtonKey = Key('btn-run-delete-salon-flow');
const Key _kHarnessKey = Key('harness-screen');
const Key _kPlaceholderKey = Key('debug-home-placeholder-stub');

const Salon _kStubSalon = Salon(id: _kSalonId, name: 'QA Salon 285');

User _owner() => const User(
  id: 'owner-285',
  email: 'owner-285@beautica.ua',
  role: UserRole.salonOwner,
  firstName: 'Оксана',
  lastName: 'Власниця',
);

User _admin() => const User(
  id: 'admin-285',
  email: 'admin-285@beautica.ua',
  role: UserRole.salonAdmin,
  firstName: 'Ірина',
  lastName: 'Адміністраторка',
  salonId: 'salon-admin-owns-285',
);

class _AuthenticatedAs extends AuthNotifier {
  _AuthenticatedAs(this.user);
  final User user;

  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: user, accessToken: 'tok-285');
}

class _UnauthenticatedNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.unauthenticated();
}

/// [SalonManagementProfile] stub that resolves immediately, bypassing the
/// real `salonRepositoryProvider.getSalonById`/`.getSalonStaff` fetch pair —
/// this file only exercises `deleteSalon()` (inherited, unmodified), never
/// `build()`'s own data. Mirrors `salon_manage_route_guard_test.dart`'s
/// `_SettledSalonManagementProfile` shape.
class _SettledSalonManagementProfile extends SalonManagementProfile {
  @override
  Future<SalonManagementProfileData> build(String salonId) async =>
      (_kStubSalon, const <SalonStaffMember>[]);
}

/// Renders EXACTLY what `app_router.dart`'s private `_Placeholder('home')`
/// does (`Scaffold(body: Center(child: Text(label)))`) — see this file's
/// header doc, Problem A, for why a stand-in is required instead of
/// `find.byType(_Placeholder)`.
class _PlaceholderStub extends StatelessWidget {
  const _PlaceholderStub();

  @override
  Widget build(BuildContext context) => const Scaffold(
    key: _kPlaceholderKey,
    body: Center(child: Text('home')),
  );
}

/// Minimal harness: one button whose `onPressed` invokes
/// `runDeleteSalonFlow` directly for [salonId] — the shared function under
/// test, not a screen that wires it behind role-gated UI (see Problem B).
class _HarnessScreen extends ConsumerWidget {
  const _HarnessScreen({required this.salonId, required this.onLoadingChange});

  final String salonId;
  final ValueChanged<bool> onLoadingChange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Warms `authProvider` on this widget's own build so the setup
    // `pumpAndSettle()` genuinely waits for it to resolve before any test
    // taps the button. A bare `ref.read` inside the button handler would be
    // the FIRST read of the provider in the whole test (nothing else in
    // this minimal harness ever watches auth), and reading a fresh provider
    // returns `AsyncLoading` synchronously — `pumpAndSettle()` does not wait
    // for a bare unwatched Future to resolve, since nothing in the tree asks
    // for a frame when it completes. `runDeleteSalonFlow`'s own
    // `session is Authenticated` check would then always see `AsyncLoading`
    // (`.value == null`) and fall through to the `RouteNames.login` branch —
    // a pure test-harness race, not a production one (every real screen
    // reaching this flow sits behind router chrome that already watches
    // `authProvider`, so it is always warm by the time a user can tap
    // delete). Mirrors how every real caller of `runDeleteSalonFlow`
    // (`settings_screen.dart`, `salon_settings_screen.dart`) is itself a
    // `ConsumerWidget`/`ConsumerStatefulWidget` already watching auth-derived
    // state.
    ref.watch(authProvider);
    return Scaffold(
      key: _kHarnessKey,
      body: Center(
        child: ElevatedButton(
          key: _kRunButtonKey,
          onPressed: () => runDeleteSalonFlow(
            context: context,
            ref: ref,
            salonId: salonId,
            setLoading: onLoadingChange,
          ),
          child: const Text('run'),
        ),
      ),
    );
  }
}

GoRouter _router(List<bool> loadingCalls) => GoRouter(
  initialLocation: '/harness',
  routes: <RouteBase>[
    GoRoute(
      path: '/harness',
      builder: (context, state) =>
          _HarnessScreen(salonId: _kSalonId, onLoadingChange: loadingCalls.add),
    ),
    // The debug placeholder stand-in — see Problem A.
    GoRoute(
      path: RouteNames.home,
      builder: (context, state) => const _PlaceholderStub(),
    ),
    GoRoute(
      path: RouteNames.salonHome,
      builder: (context, state) => const SalonHomeResolverScreen(),
    ),
    // Reachable only if `SalonHomeResolverScreen` itself forwards onward
    // (out of THIS phase's scope — D2) during a late `pumpPastVelvetSnack`.
    // Registered defensively so that forward never throws a "no route
    // found" mid-teardown.
    GoRoute(
      path: '/salons/:salonId/shell',
      builder: (context, state) => Scaffold(
        key: Key('shell-stub-${state.pathParameters['salonId']}'),
        body: const SizedBox(),
      ),
    ),
    GoRoute(
      path: RouteNames.mySalons,
      builder: (context, state) =>
          const Scaffold(key: Key('my-salons-stub'), body: SizedBox()),
    ),
    GoRoute(
      path: RouteNames.login,
      builder: (context, state) =>
          const Scaffold(key: Key('login-stub'), body: SizedBox()),
    ),
  ],
);

/// Mutable box so a `build()` call count survives `mySalonsProvider` being
/// recreated by `container.invalidate` — mirrors
/// `salon_management_profile_notifier_test.dart`'s own `_CallCounter`/
/// `_CountingMySalons` shape (kept local, not promoted/shared: this file is
/// the only place that needs a bare rebuild-count pin on `mySalonsProvider`
/// from OUTSIDE the notifier itself).
class _MySalonsCallCounter {
  int value = 0;
}

/// [MySalons] stub that increments [counter] on every `build()` — the
/// regression pin below asserts on [counter], not on the resolved list.
class _CountingMySalons extends MySalons {
  _CountingMySalons(this.counter);

  final _MySalonsCallCounter counter;

  @override
  Future<List<Salon>> build() async {
    counter.value++;
    return const <Salon>[_kStubSalon];
  }
}

List<Object> _overrides({
  required AuthNotifier Function() authNotifier,
  required FakeSalonRepository repo,
}) => <Object>[
  authProvider.overrideWith(authNotifier),
  salonRepositoryProvider.overrideWithValue(repo),
  salonManagementProfileProvider(
    _kSalonId,
  ).overrideWith(_SettledSalonManagementProfile.new),
];

void main() {
  group('runDeleteSalonFlow — post-delete landing', () {
    testWidgets('should_navigateToMySalons_when_ownerDeletesSalon', (
      tester,
    ) async {
      final repo = FakeSalonRepository(salon: _kStubSalon);
      final loadingCalls = <bool>[];
      await tester.pumpRoutedApp(
        _router(loadingCalls),
        overrides: _overrides(
          authNotifier: () => _AuthenticatedAs(_owner()),
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_kRunButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-confirm-delete-salon')));
      await tester.pumpAndSettle();

      // Every delete entry point lands on «Мої салони», never the
      // auth-derived role home — pin the stub's Key, not a path string.
      expect(find.byKey(const Key('my-salons-stub')), findsOneWidget);
      expect(find.byType(SalonHomeResolverScreen), findsNothing);
      expect(find.byKey(_kPlaceholderKey), findsNothing);
      expect(repo.deleteCalls, 1);

      await pumpPastVelvetSnack(tester);
    });

    testWidgets('should_navigateToMySalons_when_adminDeletesSalon', (
      tester,
    ) async {
      final repo = FakeSalonRepository(salon: _kStubSalon);
      final loadingCalls = <bool>[];
      await tester.pumpRoutedApp(
        _router(loadingCalls),
        overrides: _overrides(
          authNotifier: () => _AuthenticatedAs(_admin()),
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_kRunButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-confirm-delete-salon')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('my-salons-stub')), findsOneWidget);
      expect(find.byType(SalonHomeResolverScreen), findsNothing);
      expect(find.byKey(_kPlaceholderKey), findsNothing);
      expect(repo.deleteCalls, 1);

      await pumpPastVelvetSnack(tester);
    });

    testWidgets('should_neverRenderPlaceholder_when_deleteSucceeds', (
      tester,
    ) async {
      // The bug's own regression pin — independent of case 1's TYPE
      // assertion so it survives any future refactor of that finder (per
      // the phase doc: "must outlive any refactor of case 1").
      final repo = FakeSalonRepository(salon: _kStubSalon);
      final loadingCalls = <bool>[];
      await tester.pumpRoutedApp(
        _router(loadingCalls),
        overrides: _overrides(
          authNotifier: () => _AuthenticatedAs(_owner()),
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_kRunButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-confirm-delete-salon')));
      // Let the FULL forward chain (including whatever
      // `SalonHomeResolverScreen` does next — out of this phase's scope)
      // play out; the placeholder must never appear at ANY point in it.
      await tester.pumpAndSettle();

      expect(find.byKey(_kPlaceholderKey), findsNothing);
      expect(find.text('home'), findsNothing);

      await pumpPastVelvetSnack(tester);
    });

    testWidgets('should_navigateToLogin_when_sessionIsNotAuthenticated', (
      tester,
    ) async {
      final repo = FakeSalonRepository(salon: _kStubSalon);
      final loadingCalls = <bool>[];
      await tester.pumpRoutedApp(
        _router(loadingCalls),
        overrides: _overrides(
          authNotifier: _UnauthenticatedNotifier.new,
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_kRunButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-confirm-delete-salon')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login-stub')), findsOneWidget);
      expect(find.byKey(_kPlaceholderKey), findsNothing);
      expect(find.byType(SalonHomeResolverScreen), findsNothing);
      expect(repo.deleteCalls, 1);

      await pumpPastVelvetSnack(tester);
    });

    testWidgets('should_stayOnScreen_when_deleteFails', (tester) async {
      final repo = FakeSalonRepository(salon: _kStubSalon)
        ..deleteError = const NetworkFailure();
      final loadingCalls = <bool>[];
      await tester.pumpRoutedApp(
        _router(loadingCalls),
        overrides: _overrides(
          authNotifier: () => _AuthenticatedAs(_owner()),
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_kRunButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-confirm-delete-salon')));
      await tester.pump();
      await pumpVelvetSnackIn(tester);

      expect(find.byKey(_kHarnessKey), findsOneWidget);
      expect(find.byKey(_kPlaceholderKey), findsNothing);
      expect(find.byType(SalonHomeResolverScreen), findsNothing);
      expect(find.byKey(const Key('login-stub')), findsNothing);
      expectVelvetSnack(
        lookupAppLocalizations(const Locale('uk')).errNetwork,
        variant: VelvetSnackVariant.error,
      );
      expect(loadingCalls, <bool>[true, false]);

      await pumpPastVelvetSnack(tester);
    });

    testWidgets('should_notNavigate_when_dialogIsDismissed', (tester) async {
      final repo = FakeSalonRepository(salon: _kStubSalon);
      final loadingCalls = <bool>[];
      await tester.pumpRoutedApp(
        _router(loadingCalls),
        overrides: _overrides(
          authNotifier: () => _AuthenticatedAs(_owner()),
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_kRunButtonKey));
      await tester.pumpAndSettle();
      // Cancel — hits the identical `confirmed != true` branch a barrier-tap
      // dismissal (`confirmed == null`) would.
      await tester.tap(find.byKey(const Key('btn-cancel-delete-salon')));
      await tester.pumpAndSettle();

      expect(find.byKey(_kHarnessKey), findsOneWidget);
      expect(find.byKey(const Key('delete-salon-dialog')), findsNothing);
      expect(find.byKey(_kPlaceholderKey), findsNothing);
      expect(repo.deleteCalls, 0);
      expect(loadingCalls, isEmpty);
    });
  });

  group('runDeleteSalonFlow — invalidation survives caller unmount', () {
    // mobile-security MEDIUM / mobile-perf LOW regression pin
    // (swipe-to-delete audit, 2026-09-03) — a NARROWER re-run of the exact
    // bug `delete_salon_flow.dart`'s own header doc already fixed once: the
    // prior fix invalidated `mySalonsProvider` through THIS function's own
    // `WidgetRef`, gated behind the same `context.mounted` check the
    // success snack/navigation use. If the caller's widget unmounts WHILE
    // `deleteSalon()` is still awaited (the user navigates away mid-delete,
    // simulated below via a direct `router.go` — NOT through
    // `runDeleteSalonFlow`, which is still suspended on the gated await),
    // that check (`if (!context.mounted) return;`) would return BEFORE the
    // invalidate line is ever reached, even though the DELETE had already
    // succeeded server-side. See `delete_salon_flow.dart`'s current header
    // doc for the fix: a `ProviderContainer` is captured via
    // `ProviderScope.containerOf(context, listen: false)` BEFORE the await,
    // while `context` is provably mounted, and invalidated through
    // unconditionally on success — independent of the caller's widget
    // lifecycle by the time the await resolves.
    testWidgets(
      'a delete that SUCCEEDS while the caller unmounts mid-await still '
      'invalidates mySalonsProvider',
      (tester) async {
        final repo = FakeSalonRepository(salon: _kStubSalon)
          ..deleteSalonGate = Completer<void>();
        final counter = _MySalonsCallCounter();
        final loadingCalls = <bool>[];
        final GoRouter router = _router(loadingCalls);
        addTearDown(router.dispose);

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            ..._overrides(
              authNotifier: () => _AuthenticatedAs(_owner()),
              repo: repo,
            ),
            mySalonsProvider.overrideWith(() => _CountingMySalons(counter)),
          ],
        );
        await tester.pumpAndSettle();

        // A raw handle on the app's own `ProviderContainer`, taken off a
        // context (`MaterialApp`) that outlives every route swap below —
        // NOT the same handle `runDeleteSalonFlow` itself captures off
        // `_HarnessScreen`'s context, but the same underlying container
        // (one `ProviderScope` for the whole pumped tree).
        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(MaterialApp)),
          listen: false,
        );

        // Pre-warm `mySalonsProvider` — mirrors the real «Мої салони» hub,
        // which has already loaded its list (one `build()`) before the
        // owner ever gets to swipe a row. Nothing in this minimal harness
        // watches `mySalonsProvider` on its own (unlike the real hub), so
        // without this read `container.invalidate` below would have no
        // existing element to mark dirty, and the regression this test
        // pins would go unnoticed for the wrong reason.
        await container.read(mySalonsProvider.future);
        expect(counter.value, 1, reason: 'pre-warmed baseline build');

        await tester.tap(find.byKey(_kRunButtonKey));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('btn-confirm-delete-salon')));
        // Advance only up to the gated `deleteSalon()` await — the DELETE
        // is genuinely in flight; nothing has invalidated mySalonsProvider
        // yet.
        await tester.pump();

        expect(repo.deleteCalls, 1, reason: 'the delete call is in flight');
        expect(
          counter.value,
          1,
          reason: 'mySalonsProvider must not have rebuilt yet',
        );

        // Navigate the CALLER away mid-await — unmounts `_HarnessScreen`
        // (and its `BuildContext`/`WidgetRef`) exactly as a user leaving
        // «Мої салони» mid-delete would. `runDeleteSalonFlow` itself is
        // still suspended on the gated `deleteSalon()` await below and
        // plays no part in this navigation.
        router.go(RouteNames.login);
        await tester.pumpAndSettle();
        expect(
          find.byKey(_kHarnessKey),
          findsNothing,
          reason: 'the caller must have genuinely unmounted',
        );

        // Unblock the DELETE — it succeeds server-side AFTER the caller is
        // already gone.
        repo.deleteSalonGate!.complete();
        await tester.pumpAndSettle();

        // Reading `mySalonsProvider` again is what the real hub's `build()`
        // does the next time it (re)mounts — an INVALIDATED keepAlive
        // provider only actually re-runs `build()` on its next read, it
        // does not eagerly rebuild itself with zero watchers. A second
        // `counter.value` bump here means `container.invalidate` genuinely
        // fired during the flow above.
        await container.read(mySalonsProvider.future);
        expect(
          counter.value,
          2,
          reason:
              'a successful delete must invalidate mySalonsProvider even '
              'when the caller unmounted mid-await — the container captured '
              'up front must not depend on the caller still being mounted',
        );
      },
    );
  });
}
