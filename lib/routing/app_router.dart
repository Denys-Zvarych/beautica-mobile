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
import '../features/discovery/domain/search_filters.dart';
import '../features/discovery/presentation/search_filters_screen.dart';
import '../features/master/presentation/contacts_edit_screen.dart';
import '../features/master/presentation/location_edit_screen.dart';
import '../features/master/presentation/master_profile_screen.dart';
import '../features/master/presentation/personal_info_edit_screen.dart';
import '../features/master/presentation/settings_hub_screen.dart';
import '../features/services/presentation/service_create_screen.dart';
import '../features/services/presentation/service_edit_screen.dart';
import '../features/services/presentation/service_setup_screen.dart';
import '../features/services/presentation/services_list_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/home/presentation/client_contacts_edit_screen.dart';
import '../features/home/presentation/client_location_edit_screen.dart';
import '../features/home/presentation/client_personal_info_edit_screen.dart';
import '../features/home/presentation/client_settings_hub_screen.dart';
import '../features/home/presentation/home_hub_screen.dart';
import '../features/passport/presentation/passport_screen.dart';
import '../features/rating/presentation/my_rating_screen.dart';
import '../features/shell/presentation/branch_placeholders.dart';
import '../features/shell/presentation/client_shell.dart';
import '../features/support/presentation/contact_support_screen.dart';
import '../features/schedule/presentation/master_schedule_screen.dart';
import '../features/schedule/presentation/schedule_editor_stubs.dart';
import '../features/schedule/presentation/weekly_template_editor_screen.dart';
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

// ---------------------------------------------------------------------------
// CLIENT shell branch indices (locked — must match the [StatefulShellBranch]
// order in the [StatefulShellRoute.indexedStack] below). These are the single
// source of truth for "which tab is which index": the shell hops branches via
// `navigationShell.goBranch(<index>)`, the bottom nav fills the tile whose
// `index == navigationShell.currentIndex`, and in-page tiles that target a tab
// must hop the SAME index (never `context.push`, which stacks on the current
// branch and leaves the nav selection out of sync).
const int kClientHomeBranch = 0;
const int kClientFavoritesBranch = 1;
const int kClientSearchBranch = 2;
const int kClientBookingsBranch = 3;
const int kClientPassportBranch = 4;

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
      // RegisterFlowShell and acquire the app-wide screenshot guard via the
      // ref-counted ScreenProtectionManager (email + reset token are PII).
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
        // covered by the shell's screenshot guard. It instead acquires the
        // app-wide ScreenProtectionManager in VerificationScreen.initState and
        // releases it in dispose (the manager is internally !kDebugMode-guarded
        // and ref-counts a single native toggle). The three wizard steps
        // (role-selection self-acquires; /register, /register/step-2,
        // /register/step-3 are inside the shell) are covered by
        // RegisterFlowShell. Net effect: every PII-collecting auth route holds
        // the shared guard — no gap, no desync.
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
      // Phase 13.1 — CLIENT 5-tab StatefulShellRoute. Each branch is an
      // independent navigator with its own stack, so hopping tabs via
      // `goBranch` (in [ClientShell._onTap]) never grows the parent nav stack
      // — the fix for the prior `context.push`-retains-shell growth note. The
      // five branches, in index order:
      //   0 — Головна  /home     (CLIENT post-login landing)
      //   1 — Улюблені /favorites
      //   2 — Пошук    /search   (the elevated center disc)
      //   3 — Записи   /bookings
      //   4 — BEAUTY PASSPORT /passport
      // CLIENT-only gating lives in [authRedirect] (the `/home`,`/favorites`,
      // `/search`,`/bookings`,`/passport` prefixes redirect any non-CLIENT
      // role to the home shell), mirroring the `/master/*` and `/services`
      // gates that fence INDEPENDENT_MASTER in. The MASTER shell keeps its own
      // standalone routes + 4-tile VelvetBottomNavBar (unchanged).
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            ClientShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              // Phase 13.7 — real HomeHubScreen replaces the placeholder.
              GoRoute(
                path: RouteNames.clientHome,
                pageBuilder: (context, state) =>
                    _instantPage(state, const HomeHubScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.clientFavorites,
                pageBuilder: (context, state) => _instantPage(
                  state,
                  const ClientFavoritesPlaceholderScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              // Phase 13.3 — real ClientSearchScreen replaces the placeholder.
              GoRoute(
                path: RouteNames.clientSearch,
                pageBuilder: (context, state) =>
                    _instantPage(state, const ClientSearchScreen()),
                routes: [
                  // /search/results — pushed from the Пошук CTA with the
                  // assembled SearchFilters in `extra`. Nested under the search
                  // branch so it pushes onto that branch's navigator (swipe-back
                  // returns to the still-populated filters). Placeholder until
                  // the real paged results list ships in a later 13.x phase.
                  GoRoute(
                    path: 'results',
                    builder: (context, state) =>
                        ClientSearchResultsPlaceholderScreen(
                          filters: state.extra as SearchFilters?,
                        ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.clientBookings,
                pageBuilder: (context, state) => _instantPage(
                  state,
                  const ClientBookingsPlaceholderScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              // Phase 13.8 — real PassportScreen replaces the placeholder.
              GoRoute(
                path: RouteNames.clientPassport,
                pageBuilder: (context, state) =>
                    _instantPage(state, const PassportScreen()),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: RouteNames.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
      // Support / contact-us («Напишіть нам»). Pushed from the settings hub's
      // "Допомога" row. MaterialPage (builder:) so the swipe-back gesture works.
      GoRoute(
        path: RouteNames.contactSupport,
        builder: (context, state) => const ContactSupportScreen(),
      ),
      // Phase 13.7 (revised) — CLIENT's aggregate rating screen.
      // Backend GET /clients/me/rating is not yet shipped; the screen shows the
      // empty state. Client comments are never shown (two-sided ratings only).
      GoRoute(
        path: RouteNames.myRating,
        builder: (context, state) => const MyRatingScreen(),
      ),
      // Phase 4.2 — Master profile (read-only).
      GoRoute(
        path: RouteNames.masterProfile,
        pageBuilder: (context, state) =>
            _instantPage(state, const MasterProfileScreen()),
      ),
      // Master profile settings hub + per-section edit pages. These replace the
      // retired monolithic /master/edit form. All auth-guarded (Phase 2.9
      // redirect guard covers non-login routes when session is null). MaterialPage
      // (builder:) so the theme's CupertinoPageTransitionsBuilder installs the
      // left-edge swipe-back gesture on each push.
      GoRoute(
        path: RouteNames.masterMenu,
        builder: (context, state) => const SettingsHubScreen(),
      ),
      GoRoute(
        path: RouteNames.masterEditPersonal,
        builder: (context, state) => const PersonalInfoEditScreen(),
      ),
      GoRoute(
        path: RouteNames.masterEditContacts,
        builder: (context, state) => const ContactsEditScreen(),
      ),
      GoRoute(
        path: RouteNames.masterEditLocation,
        builder: (context, state) => const LocationEditScreen(),
      ),
      // CLIENT settings hub + per-section edit pages. Mirror the master
      // /master/menu + /master/edit/* block above but for the CLIENT role.
      // Pushed from the home-hub burger icon; all three edit pages PATCH
      // /users/me via ClientProfileRepository. Role-gated to CLIENT in
      // [authRedirect] (the /client/* prefix). MaterialPage (builder:) so the
      // theme's CupertinoPageTransitionsBuilder installs the swipe-back gesture.
      GoRoute(
        path: RouteNames.clientMenu,
        builder: (context, state) => const ClientSettingsHubScreen(),
      ),
      GoRoute(
        path: RouteNames.clientEditPersonal,
        builder: (context, state) => const ClientPersonalInfoEditScreen(),
      ),
      GoRoute(
        path: RouteNames.clientEditContacts,
        builder: (context, state) => const ClientContactsEditScreen(),
      ),
      GoRoute(
        path: RouteNames.clientEditLocation,
        builder: (context, state) => const ClientLocationEditScreen(),
      ),
      // Phase 5.2 — Service catalogue (INDEPENDENT_MASTER).
      // Phase 6.x — `expandCategory` query param: when present, the matching
      // category section is pre-expanded and all others start collapsed. Passed
      // from profile category cards via context.push('/services?expandCategory=SLUG').
      // Uses MaterialPage (builder:) so the theme's CupertinoPageTransitionsBuilder
      // installs the left-edge swipe-back gesture on push entries.
      GoRoute(
        path: RouteNames.services,
        builder: (context, state) {
          final raw = state.uri.queryParameters['expandCategory']
              ?.trim()
              .toUpperCase();
          final expandCategory = (raw != null && isValidCategorySlug(raw))
              ? raw
              : null;
          return ServicesListScreen(initialExpandCategory: expandCategory);
        },
      ),
      // Phase 5.3 — Service create form (INDEPENDENT_MASTER).
      // Uses MaterialPage so swipe-back works on the push stack.
      GoRoute(
        path: RouteNames.serviceCreate,
        builder: (context, state) => const ServiceCreateScreen(),
      ),
      // First-time service setup (INDEPENDENT_MASTER) — the one-pass empty-state
      // menu builder reached from the services-list empty state.
      // Uses MaterialPage so swipe-back works on the push stack.
      GoRoute(
        path: RouteNames.serviceSetup,
        builder: (context, state) => const ServiceSetupScreen(),
      ),
      // Phase 5.4 — Service edit form (INDEPENDENT_MASTER).
      // Parameterised route — extracts `id` from the path. An empty id
      // redirects to /services defensively; this keeps the guard resilient to
      // programmatic pushes with a missing segment.
      // Uses MaterialPage so swipe-back works on the push stack.
      GoRoute(
        path: '/services/:id/edit',
        redirect: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          if (id.isEmpty) return RouteNames.services;
          return null;
        },
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return ServiceEditScreen(id: id);
        },
      ),
      // Phase 6.2 — the legacy `/master/working-hours` editor route
      // (WorkingHoursScreen) was retired: it wrote the deprecated `working_hours`
      // table (no longer bookable) and nothing in the app navigates to it. The
      // Календар tile lands on [masterSchedule] and the weekly-template edit path
      // is [scheduleWeeklyEditor] (WeeklyTemplateEditorScreen). The route was
      // orphaned but still deep-link-reachable, so it is removed here to drop a
      // dead surface. The WorkingHoursScreen widget itself is kept (its existing
      // widget tests pump it directly); the [RouteNames.workingHours] constant is
      // also retained because the SEC role-gate regression tests in
      // auth_redirect_test.dart use it as a representative `/master/*` location.
      // Phase 15.2 — Master schedule («Графік роботи»), the Календар tile's
      // destination. Auth-guarded by the global redirect.
      GoRoute(
        path: RouteNames.masterSchedule,
        pageBuilder: (context, state) =>
            _instantPage(state, const MasterScheduleScreen()),
      ),
      // Phase 15.5 — the REAL weekly-template editor («Робочі дні та години»),
      // graduating the Phase 15.2 [WeeklyTemplateEditorStubScreen] at the same
      // path. It saves via [WeeklyScheduleNotifier] → POST/PUT/DELETE
      // /masters/{id}/weekly-schedules — the Phase 15.5 data path the calendar's
      // effective-schedule read actually resolves against — and invalidates
      // [effectiveScheduleProvider] on success so the calendar repaints. This
      // replaces the dead-end route to the deprecated /master/working-hours
      // editor (which wrote the legacy `working_hours` table, no longer bookable).
      // Uses MaterialPage so the left-edge swipe-back gesture works when pushed
      // from MasterScheduleScreen.
      GoRoute(
        path: RouteNames.scheduleWeeklyEditor,
        builder: (context, state) => const WeeklyTemplateEditorScreen(),
      ),
      // Phase 15.4 — the per-date override surface graduated to the modal
      // [DayHoursSheet] (opened by the day pencil on `master_schedule_screen`),
      // so this route is no longer a UI destination. It is kept registered
      // (dead but auth-guarded) ONLY because the Phase 15.2 schedule-screen
      // widget test still references `PerDateOverrideStubScreen` at this path;
      // mobile-qa retires both when it authors the 15.4 sheet tests.
      GoRoute(
        path: RouteNames.scheduleDayOverride,
        pageBuilder: (context, state) =>
            _instantPage(state, const PerDateOverrideStubScreen()),
      ),
      // Phase 15.5 — the copy/propagate range surface graduated to the modal
      // [ApplyScheduleSheet] («Період дії графіка»), opened from the weekly
      // editor's tappable active-window card. So this route is no longer a
      // standalone destination: it now lands on the weekly editor (which hosts
      // the apply sheet) instead of the retired `SchedulePropagateStubScreen`,
      // mirroring how the 15.4 override route folded into the day sheet. Kept
      // registered (auth-guarded) for any external/deep-link entry.
      GoRoute(
        path: RouteNames.schedulePropagate,
        pageBuilder: (context, state) =>
            _instantPage(state, const WeeklyTemplateEditorScreen()),
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
