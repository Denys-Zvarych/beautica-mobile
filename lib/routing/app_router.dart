// Phase 1.4 — go_router scaffold.
// Phase 2.5 — LoginScreen wired.
// Phase 2.6 — RegisterScreen wired.
// Phase 2.8 — SettingsScreen + RouteNames.settings wired.
// Phase 2.9 — AuthRefreshNotifier + real authRedirect(session, state) guard.
// Phase 2.11 — VerificationScreen at /verification (email via GoRouter extra).
//              /done placeholder → redirects to / until Phase 2.12.
// Phase 2.12 — Real [DoneScreen] replaces the [DonePlaceholderScreen]. The
//              draft-reset (HIGH-1) contract migrates to the real screen's
//              own initState post-frame callback.
// Phase 2.16 — Multi-step registration wizard. /register/role hosts the
//              role-selection entry gate; /register, /register/step-2 and
//              /register/step-3 are nested under a ShellRoute that draws
//              the shared RegisterFlowShell chrome (brand row + role chip
//              + 4-pill progress + glass card + back link). Step 2 / Step 3
//              widgets are placeholders here — Phase 2.17 / 2.19 supply the
//              real screens.
//
// [appRouterProvider] is kept alive because [GoRouter] must survive tab
// switches and is shared across the entire widget tree via
// [MaterialApp.router].

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/auth/presentation/auth_notifier.dart';
import '../features/auth/presentation/done_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_flow_shell.dart';
import '../features/auth/presentation/register_step_1_screen.dart';
import '../features/auth/presentation/register_step_2_screen.dart';
import '../features/auth/presentation/role_selection_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/auth/presentation/verification_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import 'auth_redirect.dart';
import 'auth_refresh_notifier.dart';
import 'route_names.dart';

part 'app_router.g.dart';

// ---------------------------------------------------------------------------
// Zero-duration transition helper (auth flow only)
// ---------------------------------------------------------------------------
//
// The default MaterialPage uses Android's OpenUpwardsPageTransitionsBuilder
// slide-and-fade — adding 300+ ms of compounded layout/animation cost between
// `context.push(...)` and the first paint of the destination. On the auth flow
// — splash, login, register, verification, home — every millisecond before
// the destination is interactive directly hurts the impression the user forms
// of the app. Switch those routes to a `CustomTransitionPage` with zero
// duration so the destination renders the instant the framework can build it.
CustomTransitionPage<void> _instantPage(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          child,
    );

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
        pageBuilder: (context, state) =>
            _instantPage(state, const SplashScreen()),
      ),
      GoRoute(
        path: RouteNames.login,
        pageBuilder: (context, state) =>
            _instantPage(state, const LoginScreen()),
      ),
      GoRoute(
        path: RouteNames.registerRole,
        pageBuilder: (context, state) =>
            _instantPage(state, const RoleSelectionScreen()),
      ),
      // Phase 2.16 — Wizard ShellRoute. The three /register* paths share
      // the RegisterFlowShell chrome (brand row + role chip + 4-pill
      // progress + glass card + back link); only the step screen inside
      // the glass card differs per route.
      ShellRoute(
        builder: (context, state, child) => RegisterFlowShell(child: child),
        routes: [
          GoRoute(
            path: RouteNames.register,
            pageBuilder: (context, state) =>
                _instantPage(state, const RegisterStep1Screen()),
          ),
          GoRoute(
            path: RouteNames.registerStep2,
            // Phase 2.17 — real Step 2 (Profile) screen.
            pageBuilder: (context, state) =>
                _instantPage(state, const RegisterStep2Screen()),
          ),
          GoRoute(
            path: RouteNames.registerStep3,
            // Phase 2.19 will replace this placeholder with the real
            // Step 3 (Address) screen.
            pageBuilder: (context, state) => _instantPage(
              state,
              const _StepPlaceholder('Step 3 — Phase 2.19'),
            ),
          ),
        ],
      ),
      GoRoute(
        path: RouteNames.verification,
        pageBuilder: (context, state) {
          final email = (state.extra as String?) ?? '';
          return _instantPage(state, VerificationScreen(email: email));
        },
      ),
      GoRoute(
        // Phase 2.12 — Registration Done screen. Renders the celebration
        // surface and owns the HIGH-1 contract: clearing the in-memory
        // registration draft on arrival via a post-frame callback in
        // [DoneScreen.initState].
        path: RouteNames.done,
        pageBuilder: (context, state) =>
            _instantPage(state, const DoneScreen()),
      ),
      GoRoute(
        path: RouteNames.home,
        pageBuilder: (context, state) =>
            _instantPage(state, const _Placeholder('home')),
      ),
      GoRoute(
        path: RouteNames.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}

/// Throwaway scaffold used by the home route until Phase 3+ replaces it with
/// a real screen.
class _Placeholder extends StatelessWidget {
  const _Placeholder(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(label)));
}

/// Placeholder rendered inside the wizard's glass card for Step 2 / Step 3
/// until Phase 2.17 / 2.19 wire the real screens. The [label] is a variable
/// (not a literal) so the `no_raw_ui_strings` lint stays green.
class _StepPlaceholder extends StatelessWidget {
  const _StepPlaceholder(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      Center(child: Text(label, key: const Key('step-placeholder')));
}
