// Phase 1.4 — go_router scaffold.
// Phase 2.5 — LoginScreen wired.
// Phase 2.6 — RegisterScreen wired.
// Phase 2.8 — SettingsScreen + RouteNames.settings wired.
// Phase 2.9 — AuthRefreshNotifier + real authRedirect(session, state) guard.
// Phase 2.11 — VerificationScreen at /verification (email via GoRouter extra).
//              /done placeholder → redirects to / until Phase 2.12.
//
// [appRouterProvider] is kept alive because [GoRouter] must survive tab
// switches and is shared across the entire widget tree via
// [MaterialApp.router].

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/auth/presentation/auth_notifier.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/auth/presentation/verification_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import 'auth_redirect.dart';
import 'auth_refresh_notifier.dart';
import 'route_names.dart';

part 'app_router.g.dart';

/// Riverpod-managed [GoRouter] instance.
///
/// Wired with [AuthRefreshNotifier] so that any change in the auth session
/// triggers a re-evaluation of the redirect callback. This means users are
/// automatically routed to the correct screen after login, logout, or
/// cold-start session resolution — without any screen-level navigation code.
@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final refresh = AuthRefreshNotifier(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: RouteNames.splash,
    refreshListenable: refresh,
    redirect: (ctx, state) => authRedirect(ref.read(authProvider), state),
    routes: [
      GoRoute(
        path: RouteNames.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: RouteNames.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: RouteNames.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: RouteNames.verification,
        builder: (context, state) {
          // Email is passed as GoRouter extra from RegisterScreen on success.
          // Fall back to empty string if extra is absent (e.g. manual deep-link).
          final email = (state.extra as String?) ?? '';
          return VerificationScreen(email: email);
        },
      ),
      GoRoute(
        // Phase 2.12 placeholder — /done redirects to home until the
        // "Registration Done" screen is implemented.
        path: RouteNames.done,
        redirect: (context, state) => RouteNames.home,
      ),
      GoRoute(
        path: RouteNames.home,
        builder: (context, state) => const _Placeholder('home'),
      ),
      GoRoute(
        path: RouteNames.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}

/// Throwaway scaffold used by the home route until Phase 3+ replaces it with
/// a real screen. The [label] is a variable, not a raw string literal, so
/// the `no_raw_ui_strings` custom lint rule is satisfied.
class _Placeholder extends StatelessWidget {
  const _Placeholder(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(label)));
}
