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

import '../features/auth/presentation/accept_invite_screen.dart';
import '../features/auth/presentation/auth_notifier.dart';
import '../features/auth/presentation/done_screen.dart';
import '../features/auth/presentation/forgot_password_request_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/reset_password_screen.dart';
import '../features/auth/presentation/register_flow_shell.dart';
import '../features/auth/presentation/register_step_1_screen.dart';
import '../features/auth/presentation/register_step_2_screen.dart';
import '../features/auth/presentation/register_step_3_screen.dart';
import '../features/auth/presentation/role_selection_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/auth/presentation/verification_screen.dart';
import '../features/master/presentation/master_edit_screen.dart';
import '../features/master/presentation/master_profile_screen.dart';
import '../features/services/presentation/service_create_screen.dart';
import '../features/services/presentation/service_edit_screen.dart';
import '../features/services/presentation/services_list_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/calendar/presentation/working_hours_screen.dart';
import '../features/services/domain/category_slug.dart';
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
      // Phase 2.20 — accept-invite deep link. The single-use token arrives as
      // the `token` query parameter from the emailed link. A missing/empty
      // token still loads the screen — the backend's 400/404 on validation
      // then renders the invalid-invite state via AsyncError.
      GoRoute(
        path: RouteNames.acceptInvite,
        pageBuilder: (context, state) {
          final token = state.uri.queryParameters['token'] ?? '';
          return _instantPage(state, AcceptInviteScreen(token: token));
        },
      ),
      GoRoute(
        path: RouteNames.registerRole,
        pageBuilder: (context, state) =>
            _instantPage(state, const RoleSelectionScreen()),
      ),
      // Phase 2.13 — forgot-password flow. Both routes render outside the
      // RegisterFlowShell and apply their own ScreenProtector lifecycle
      // (email + reset token are PII).
      GoRoute(
        path: RouteNames.forgotPassword,
        pageBuilder: (context, state) =>
            _instantPage(state, const ForgotPasswordRequestScreen()),
      ),
      GoRoute(
        // The single-use reset token arrives as the `token` query parameter
        // from the emailed deep link (`/reset-password?token=...`). It is
        // never typed by the user. A missing/empty token still loads the
        // screen — the first reset attempt then surfaces the invalid-link
        // state via the backend's generic 400.
        path: RouteNames.resetPassword,
        pageBuilder: (context, state) {
          final token = state.uri.queryParameters['token'] ?? '';
          return _instantPage(state, ResetPasswordScreen(token: token));
        },
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
            // Phase 2.19 — real Step 3 (Address / Locality) screen.
            pageBuilder: (context, state) =>
                _instantPage(state, const RegisterStep3Screen()),
          ),
        ],
      ),
      GoRoute(
        // Phase 2.19 MEDIUM-2 (screenshot/FLAG_SECURE PII coverage):
        // /verification renders OUTSIDE the RegisterFlowShell, so it is NOT
        // covered by the shell's ScreenProtector lifecycle. It instead applies
        // its own ScreenProtector.preventScreenshotOn/Off() in
        // VerificationScreen.initState/dispose (both !kDebugMode-guarded). The
        // three wizard steps (role-selection self-protects; /register,
        // /register/step-2, /register/step-3 are inside the shell) are covered
        // by RegisterFlowShell. Net effect: every PII-collecting auth route has
        // screenshot suppression — no gap, no double-application.
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
      // Phase 4.2 — Master profile (read-only).
      GoRoute(
        path: RouteNames.masterProfile,
        pageBuilder: (context, state) =>
            _instantPage(state, const MasterProfileScreen()),
      ),
      // Phase 4.3 — Master profile edit form. Auth-guarded (Phase 2.9 redirect
      // guard already covers all non-login routes when session is null).
      GoRoute(
        path: RouteNames.masterEdit,
        pageBuilder: (context, state) =>
            _instantPage(state, const MasterEditScreen()),
      ),
      // Phase 5.2 — Service catalogue (INDEPENDENT_MASTER).
      // Phase 6.x — `expandCategory` query param: when present, the matching
      // category section is pre-expanded and all others start collapsed. Passed
      // from profile category cards via context.push('/services?expandCategory=SLUG').
      GoRoute(
        path: RouteNames.services,
        pageBuilder: (context, state) {
          final raw = state.uri.queryParameters['expandCategory']
              ?.trim()
              .toUpperCase();
          final expandCategory = (raw != null && isValidCategorySlug(raw))
              ? raw
              : null;
          return _instantPage(
            state,
            ServicesListScreen(initialExpandCategory: expandCategory),
          );
        },
      ),
      // Phase 5.3 — Service create form (INDEPENDENT_MASTER).
      GoRoute(
        path: RouteNames.serviceCreate,
        pageBuilder: (context, state) =>
            _instantPage(state, const ServiceCreateScreen()),
      ),
      // Phase 5.4 — Service edit form (INDEPENDENT_MASTER).
      // Parameterised route — extracts `id` from the path. An empty id
      // redirects to /services defensively; this keeps the guard resilient to
      // programmatic pushes with a missing segment.
      GoRoute(
        path: '/services/:id/edit',
        redirect: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          if (id.isEmpty) return RouteNames.services;
          return null;
        },
        pageBuilder: (context, state) {
          final id = state.pathParameters['id']!;
          return _instantPage(state, ServiceEditScreen(id: id));
        },
      ),
      // Phase 6.2 — Working hours editor (INDEPENDENT_MASTER).
      GoRoute(
        path: RouteNames.workingHours,
        pageBuilder: (context, state) =>
            _instantPage(state, const WorkingHoursScreen()),
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
