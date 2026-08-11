// Regression — `/salons/:salonId` AND `/masters/:masterId` must stay on a
// plain `builder:` (default MaterialPage-shaped) route, never
// `pageBuilder: _instantPage`.
//
// WHY THIS TEST EXISTS
// ---------------------
// `_instantPage` builds a `CustomTransitionPage` whose OWN `transitionsBuilder`
// completely bypasses `Theme.of(context).pageTransitionsTheme` — the
// `CupertinoPageTransitionsBuilder` wired for every platform in
// `app_theme.dart` that installs Flutter's `_CupertinoBackGestureDetector`
// (the widget actually responsible for the full-width, left-edge
// drag-to-dismiss swipe-back gesture used everywhere else in this app). A
// prior debugging pass fixed `/salons/:salonId` from `pageBuilder: (context,
// state) => _instantPage(state, ...)` to a plain `builder: (context, state)
// => PublicSalonProfileScreen(...)` for exactly this reason — see
// `app_router.dart`'s route registration comment for the full investigation.
// A follow-up pass gave `/masters/:masterId` the identical treatment (it
// carried the exact same defect and was flagged but deferred at the time of
// the salon fix).
//
// The interactive edge-swipe gesture itself is NOT observable from a widget
// test (confirmed by the debugger who fixed this — it depends on real
// platform gesture-recognizer arbitration, not just the transition
// animation). This test instead pins the STRUCTURAL cause directly: it walks
// the real `appRouterProvider`'s route tree (no widget pump needed) and
// asserts the `/salons/:salonId` `GoRoute` has `pageBuilder == null` (i.e. it
// is registered via `builder:`, which go_router pages with the default
// Material-shaped page that carries the app theme's page-transition builder).
// A future regression back to `pageBuilder: _instantPage(...)` would set
// `pageBuilder` non-null again and fail this test immediately, without ever
// needing to simulate the gesture.

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

/// [AuthNotifier] stub that settles immediately to `unauthenticated` — this
/// test never navigates or asserts on auth-gated behaviour, it only needs
/// `appRouterProvider` to CONSTRUCT without touching the real Dio/secure-
/// storage stack (constructing the router eagerly subscribes to
/// [authProvider] via `AuthRefreshNotifier`; see that class's doc comment).
class _FixedAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async {
    state = const AsyncData<AuthSession>(AuthSession.unauthenticated());
    return const AuthSession.unauthenticated();
  }
}

/// Recursively finds the first [GoRoute] (at any nesting depth) whose path
/// matches [path].
GoRoute? _findRoute(List<RouteBase> routes, String path) {
  for (final RouteBase route in routes) {
    if (route is GoRoute && route.path == path) return route;
    final GoRoute? nested = _findRoute(route.routes, path);
    if (nested != null) return nested;
  }
  return null;
}

void main() {
  testWidgets('/salons/:salonId is registered via builder: (plain page), '
      'NOT pageBuilder: _instantPage (CustomTransitionPage) — '
      'CustomTransitionPage bypasses the CupertinoPageTransitionsBuilder that '
      'installs the left-edge swipe-back gesture', (tester) async {
    final container = ProviderContainer(
      retry: beauticaProviderRetry,
      overrides: [
        authProvider.overrideWith(_FixedAuthNotifier.new),
        authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
        secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
      ],
    );
    addTearDown(container.dispose);

    final GoRouter router = container.read(appRouterProvider);
    addTearDown(router.dispose);

    final GoRoute? route = _findRoute(
      router.configuration.routes,
      '/salons/:salonId',
    );

    expect(
      route,
      isNotNull,
      reason: 'Expected a registered GoRoute for /salons/:salonId',
    );
    expect(
      route!.pageBuilder,
      isNull,
      reason:
          'A non-null pageBuilder means this route is built via a custom '
          'Page (e.g. _instantPage → CustomTransitionPage), which bypasses '
          "the theme's CupertinoPageTransitionsBuilder and silently kills "
          'the left-edge swipe-back gesture on this route again.',
    );
    expect(
      route.builder,
      isNotNull,
      reason:
          'Expected the plain builder: form so go_router pages this route '
          'with the default (Material-shaped) Page that carries the '
          "app theme's page-transition builder.",
    );

    // Same assertion for the sibling /masters/:masterId route — it received
    // the identical `builder:` fix in a follow-up pass (was previously left
    // on `_instantPage`, deferred out of scope of the original salon fix).
    final GoRoute? masterRoute = _findRoute(
      router.configuration.routes,
      '/masters/:masterId',
    );
    expect(
      masterRoute,
      isNotNull,
      reason: 'Expected a registered GoRoute for /masters/:masterId',
    );
    expect(
      masterRoute!.pageBuilder,
      isNull,
      reason:
          'A non-null pageBuilder means this route is built via a custom '
          'Page (e.g. _instantPage → CustomTransitionPage), which bypasses '
          "the theme's CupertinoPageTransitionsBuilder and silently kills "
          'the left-edge swipe-back gesture on this route again.',
    );
    expect(
      masterRoute.builder,
      isNotNull,
      reason:
          'Expected the plain builder: form so go_router pages this route '
          'with the default (Material-shaped) Page that carries the '
          "app theme's page-transition builder.",
    );
  });

  test('RouteNames.salonPublicProfile matches the tested path shape', () {
    expect(RouteNames.salonPublicProfile('abc'), '/salons/abc');
  });

  test(
    'RouteNames.salonPublicProfile builds a BARE path — no query params',
    () {
      // The `serviceId:` overload that appended `?serviceId=…&tab=masters` was
      // deleted along with the screen-side deep-link seed it fed: the salon-arm
      // wish-list CTA (its only producer) now opens the salon booking flow's
      // step-2 master picker instead. The path-segment encoding this route has
      // always done stays pinned — ids are backend UUIDs today, but nothing
      // pins that.
      //
      // ⚠️ SCOPE — READ BEFORE RELYING ON THIS AS A DELETION GUARD.
      // The `contains('?')` assertion below does NOT catch the deep link
      // coming back, and must not be described as if it does. Mutation-
      // verified: with `RouteNames.salonPublicProfile(String, {String?
      // serviceId})` restored verbatim from before the deletion, BOTH
      // assertions here stay GREEN — the no-arg call still returns a bare
      // path, exactly as it did while the overload existed. What this pins is
      // only "the DEFAULT call shape emits no query", which was already true
      // before the change.
      //
      // The behavioural guard — that a URL carrying `?serviceId=…&tab=masters`
      // is INERT, and that entry auto-selects no tab and no service filter —
      // lives in `salon_profile_no_deep_link_seed_test.dart`, which drives the
      // real `/salons/:salonId` builder closure and IS shown red under that
      // same restore.
      expect(RouteNames.salonPublicProfile('a b'), '/salons/a%20b');
      expect(RouteNames.salonPublicProfile('abc').contains('?'), isFalse);
    },
  );
}
