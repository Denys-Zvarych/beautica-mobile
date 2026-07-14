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
import '../features/auth/presentation/reset_otp_verification_screen.dart';
import '../features/auth/presentation/reset_password_screen.dart';
import '../features/auth/presentation/register_flow_shell.dart';
import '../features/auth/presentation/register_step_1_screen.dart';
import '../features/auth/presentation/register_step_2_screen.dart';
import '../features/auth/presentation/register_step_3_screen.dart';
import '../features/auth/presentation/role_selection_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/auth/presentation/verification_screen.dart';
import '../features/auth/domain/auth_session.dart';
import '../features/auth/domain/reset_password_args.dart';
import '../features/auth/domain/user_role.dart';
import '../features/booking/domain/booking_confirm_args.dart';
import '../features/booking/domain/booking_slot_picker_args.dart';
import '../features/booking/domain/booking_success_args.dart';
import '../features/booking/domain/salon_booking_args.dart';
import '../features/booking/domain/salon_booking_confirm_args.dart';
import '../features/booking/presentation/booking_confirm_screen.dart';
import '../features/booking/presentation/booking_success_screen.dart';
import '../features/booking/presentation/salon_booking_coming_soon_screen.dart';
import '../features/booking/presentation/salon_booking_confirm_screen.dart';
import '../features/booking/presentation/salon_booking_success_screen.dart';
import '../features/booking/presentation/salon_master_selection_screen.dart';
import '../features/booking/presentation/salon_service_selection_screen.dart';
import '../features/booking/presentation/salon_time_screen.dart';
import '../features/booking/presentation/service_selector_sheet.dart';
import '../features/booking/presentation/slot_picker_screen.dart';
import '../features/discovery/domain/search_filters.dart';
import '../features/discovery/presentation/search_filters_screen.dart';
import '../features/discovery/presentation/search_results_screen.dart';
import '../features/master/presentation/contacts_edit_screen.dart';
import '../features/master/presentation/location_edit_screen.dart';
import '../features/master/presentation/master_profile_screen.dart';
import '../features/master/presentation/personal_info_edit_screen.dart';
import '../features/master/presentation/public_master_profile_screen.dart';
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
import '../features/salon/presentation/public_salon_profile_screen.dart';
import '../features/shell/presentation/branch_placeholders.dart';
import '../features/shell/presentation/client_shell.dart';
import '../features/support/presentation/contact_support_screen.dart';
import '../features/schedule/presentation/master_schedule_screen.dart';
import '../features/schedule/presentation/schedule_editor_stubs.dart';
import '../features/schedule/presentation/weekly_template_editor_screen.dart';
import '../features/services/domain/category_slug.dart';
import 'auth_redirect.dart';
import 'auth_refresh_notifier.dart';
import 'role_home.dart';
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
// Secondary-only parallax tween (iOS-style: the revealed page eases ~1/3 screen
// to the LEFT as the route above slides in/out). `Animatable.chain` keeps the
// curve in the tween itself, so we drive it straight off `secondaryAnimation`
// with no `CurvedAnimation` object to dispose — no leaked ticker (see
// app_router_no_leaked_timer_test).
final Animatable<Offset> _instantPageSecondaryParallax = Tween<Offset>(
  begin: Offset.zero,
  end: const Offset(-1.0 / 3.0, 0),
).chain(CurveTween(curve: Curves.fastEaseInToSlowEaseOut));

// PRIMARY (forward/entry) transition stays INSTANT — `transitionDuration:
// Duration.zero` pins `animation` at 1.0, so the destination paints the instant
// the framework can build it (the invariant this helper exists for). We
// deliberately ignore `animation` here: the page's own entry has no motion.
//
// SECONDARY transition is now honoured: when a route is pushed ON TOP of this
// page (e.g. /search/results over the search tab root), `secondaryAnimation`
// drives a SlideTransition so the revealed page underneath parallaxes instead of
// sitting static / flashing through during the swipe-back of the page above. At
// rest (`secondaryAnimation` == 0) the offset is `Offset.zero`, so the page is
// untransformed and the instant-forward-paint is unchanged. No gesture detector
// is added (the page above owns its own swipe-back); this is purely the revealed
// page's reveal motion.
CustomTransitionPage<void> _instantPage(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          SlideTransition(
            position: secondaryAnimation.drive(_instantPageSecondaryParallax),
            child: child,
          ),
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

/// One [GlobalKey] per CLIENT branch, indexed by the branch constants above.
///
/// Each key is handed to the matching `StatefulShellBranch(navigatorKey: ...)`
/// below, which pins it to that branch's inner [Navigator]. [ClientShell] reads
/// `.currentState` off the ACTIVE branch's key so the edge-swipe / system-back
/// [ShellBackDispatcher] can pop a pushed detail page (e.g. `/search/results`)
/// off that branch's OWN stack — returning to the PREVIOUS page — instead of
/// jumping to the Home tab. The platform back button already pops the branch
/// first (Flutter dispatches to the innermost Navigator); these keys let the
/// left-edge swipe, which is mounted OUTSIDE the branch navigators, do the same.
final List<GlobalKey<NavigatorState>> clientBranchNavigatorKeys =
    <GlobalKey<NavigatorState>>[
      GlobalKey<NavigatorState>(debugLabel: 'clientHomeBranch'),
      GlobalKey<NavigatorState>(debugLabel: 'clientFavoritesBranch'),
      GlobalKey<NavigatorState>(debugLabel: 'clientSearchBranch'),
      GlobalKey<NavigatorState>(debugLabel: 'clientBookingsBranch'),
      GlobalKey<NavigatorState>(debugLabel: 'clientPassportBranch'),
    ];

@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final refresh = AuthRefreshNotifier(ref);
  ref.onDispose(refresh.dispose);

  // Per-route CLIENT gate for the public discovery surfaces that are NOT covered
  // by the prefix gates in [authRedirect] (they sit on /masters/* and /booking/*
  // rather than a client-shell branch). An authenticated non-CLIENT role that
  // reaches one of these is bounced to its own landing — INDEPENDENT_MASTER back
  // to /master/profile, every other role to the home shell. Unauthenticated
  // access is still handled by the global [authRedirect] (→ /login), which runs
  // alongside this route-level redirect.
  String? clientOnlyGuard(BuildContext context, GoRouterState state) {
    final session = ref.read(authProvider).value;
    if (session is Authenticated && session.user.role != UserRole.client) {
      return roleHomePath(session.user.role);
    }
    return null;
  }

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
      // mobile-debugger fix (same latent bug as `/salons/:salonId` and
      // `/masters/:masterId`): pushed from the login screen's "Зареєструватись"
      // link via `context.push`, so it needs the theme's
      // CupertinoPageTransitionsBuilder-installed left-edge swipe-back gesture,
      // which only `builder:` (MaterialPage) honors — `pageBuilder: _instantPage`
      // silently suppressed it. `context.go(RouteNames.registerRole)` elsewhere
      // (back-links inside the register wizard) is unaffected by this — `.go`
      // replaces the stack regardless of page type.
      GoRoute(
        path: RouteNames.registerRole,
        builder: (context, state) => const RoleSelectionScreen(),
      ),
      // Phase 2.13 — forgot-password flow. Both routes render outside the
      // RegisterFlowShell and acquire the app-wide screenshot guard via the
      // ref-counted ScreenProtectionManager (email + reset token are PII).
      //
      // mobile-debugger fix (same latent bug as `/salons/:salonId` and
      // `/masters/:masterId`): pushed from the login screen's "Забули пароль?"
      // link via `context.push`, so it needs `builder:` (MaterialPage) for the
      // theme's CupertinoPageTransitionsBuilder to install the left-edge
      // swipe-back gesture — `pageBuilder: _instantPage` silently suppressed it.
      GoRoute(
        path: RouteNames.forgotPassword,
        builder: (context, state) => const ForgotPasswordRequestScreen(),
      ),
      // Beautica OTP task Phase B3 — generalized password-reset OTP screen,
      // unauthenticated (forgot-password) entry point. Pushed from
      // [ForgotPasswordRequestScreen] with the submitted email (a bare
      // `String`) in `extra`. A missing/empty extra still loads the screen
      // with an empty display email (masking degrades gracefully) rather
      // than crashing on a bad cast — mirrors the `/verification` route's
      // own missing-extra tolerance.
      GoRoute(
        path: RouteNames.resetOtpVerification,
        builder: (context, state) {
          final email = (state.extra as String?) ?? '';
          return ResetOtpVerificationScreen(
            displayEmail: email,
            fromChangePassword: false,
            onRequestOtp: () =>
                ref.read(authProvider.notifier).requestPasswordReset(email),
            onVerify: (code) => ref
                .read(authProvider.notifier)
                .verifyPasswordResetOtp(email: email, code: code),
          );
        },
      ),
      // Beautica OTP task Phase B5 — the SAME generalized OTP screen,
      // authenticated (settings "change password") entry point. Pushed from
      // the account settings screen's "Змінити пароль" row — no extra needed,
      // the caller's identity comes from the authenticated session.
      // [displayEmail] is sourced from the already-loaded session user purely
      // for display; the backend resolves the authoritative identity from the
      // JWT for the request-otp call itself.
      GoRoute(
        path: RouteNames.changePassword,
        builder: (context, state) {
          final session = ref.read(authProvider).value;
          final email = session is Authenticated ? session.user.email : '';
          return ResetOtpVerificationScreen(
            displayEmail: email,
            fromChangePassword: true,
            onRequestOtp: () =>
                ref.read(authProvider.notifier).requestChangePasswordOtp(),
            onVerify: (code) => ref
                .read(authProvider.notifier)
                .verifyPasswordResetOtp(email: email, code: code),
          );
        },
      ),
      // Beautica OTP task Phase B4 — the single-use reset ticket (minted by
      // `POST /auth/verify-password-reset-otp`) now arrives via in-app
      // navigation as a [ResetPasswordArgs] in `GoRouterState.extra`, NOT the
      // old `?token=` deep-link query parameter (there is no more emailed
      // link to deep-link from). A missing/invalid extra still loads the
      // screen with an empty ticket — the first submit then surfaces the
      // invalid-link state via the backend's generic 400, mirroring the old
      // missing-token tolerance.
      GoRoute(
        path: RouteNames.resetPassword,
        pageBuilder: (context, state) {
          final args = state.extra as ResetPasswordArgs?;
          return _instantPage(
            state,
            ResetPasswordScreen(
              resetTicket: args?.resetTicket ?? '',
              fromChangePassword: args?.fromChangePassword ?? false,
            ),
          );
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
        //
        // mobile-debugger fix (same latent bug as `/salons/:salonId` and
        // `/masters/:masterId`): the login screen's EMAIL_NOT_VERIFIED banner
        // action reaches this route via `context.push`, so it needs `builder:`
        // (MaterialPage) for the theme's CupertinoPageTransitionsBuilder to
        // install the left-edge swipe-back gesture — `pageBuilder: _instantPage`
        // silently suppressed it. `context.go(RouteNames.verification, ...)`
        // from register step 3 is unaffected — `.go` replaces the whole stack
        // regardless of page type, so there is nothing below it to swipe back to
        // in that flow.
        path: RouteNames.verification,
        builder: (context, state) {
          final email = (state.extra as String?) ?? '';
          return VerificationScreen(email: email);
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
            navigatorKey: clientBranchNavigatorKeys[kClientHomeBranch],
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
            navigatorKey: clientBranchNavigatorKeys[kClientFavoritesBranch],
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
            navigatorKey: clientBranchNavigatorKeys[kClientSearchBranch],
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
                  // returns to the still-populated filters). Phase 13.4 — real
                  // paged results list replaces the placeholder.
                  GoRoute(
                    path: 'results',
                    builder: (context, state) => SearchResultsScreen(
                      initialFilters: state.extra as SearchFilters?,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: clientBranchNavigatorKeys[kClientBookingsBranch],
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
            navigatorKey: clientBranchNavigatorKeys[kClientPassportBranch],
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
      // Phase 13.5 — Public master profile (CLIENT-facing, read-only). A
      // top-level route (full-screen, over the client bottom nav) pushed from
      // the search-results / favourites master cards. CLIENT-guarded: an
      // INDEPENDENT_MASTER that lands here is redirected to /master/profile; any
      // other non-CLIENT role to its own home. Registered with exported:false so
      // it is reachable only by an in-app push, never an external deep link.
      GoRoute(
        path: '/masters/:masterId',
        redirect: clientOnlyGuard,
        // MaterialPage (builder:), NOT `pageBuilder: _instantPage` — same
        // mobile-debugger fix as `/salons/:salonId` immediately below (see
        // that route's comment for the full investigation). This route was
        // the sibling instance of the identical defect, deferred at the time
        // of the salon fix; this is that follow-up.
        builder: (context, state) => PublicMasterProfileScreen(
          masterId: state.pathParameters['masterId'] ?? '',
        ),
      ),
      // Phase 13.6 — Public salon profile (CLIENT-facing, read-only). Same
      // lifecycle/guard as `/masters/:masterId` above: a top-level route
      // pushed from the search-results / favourites salon cards, CLIENT-
      // guarded, in-app-push-only (exported:false — never an external deep
      // link).
      //
      // MaterialPage (builder:), NOT `pageBuilder: _instantPage` (mobile-debugger
      // fix — left-edge swipe-back was dead on this route). `_instantPage` builds
      // a `CustomTransitionPage`, and go_router's `_CustomTransitionPageRoute`
      // overrides `buildTransitions` with the page's own `transitionsBuilder`
      // (go_router's `custom_transition_page.dart`), which completely bypasses
      // `Theme.of(context).pageTransitionsTheme` — the `CupertinoPageTransitionsBuilder`
      // wired for every platform in `app_theme.dart` that installs Flutter's
      // `_CupertinoBackGestureDetector` (the widget actually responsible for the
      // full-width, drag-to-dismiss swipe-back gesture used everywhere else in
      // this app; see the `builder:` routes below). With `_instantPage`, the ONLY
      // thing that ever popped this route on a left-edge swipe was Android's own
      // `systemGestureInsets` edge interception (Q+ gesture nav) — a narrow ~24dp
      // OS-reserved strip at the *true* screen edge (confirmed empirically: a
      // swipe starting past that strip does nothing on this route, with or
      // without this fix's sibling `/masters/:masterId` above, which carried the
      // exact same defect but was easier to hit by accident because its content
      // sits behind `ProfileScaffold`'s `SafeArea` + `Padding(horizontal: lg)`,
      // which visually cues the true edge; `PublicSalonProfileScreen`'s
      // edge-to-edge `SalonCover` has no such margin, so a natural swipe
      // habitually starts a few dp further in — just past that OS strip — and
      // is silently swallowed). Switching to `builder:` matches the
      // established, precedented pattern already used by every other "needs
      // swipe-back" route in this file (`SettingsHubScreen`,
      // `ServicesListScreen`, etc. below) and gives this route the same
      // full-width gesture instead of relying on the OS's unreliable,
      // content-agnostic edge sliver. `/masters/:masterId` above received the
      // identical `builder:` treatment in a follow-up fix — see its own route
      // registration comment above for details.
      GoRoute(
        path: '/salons/:salonId',
        redirect: clientOnlyGuard,
        builder: (context, state) => PublicSalonProfileScreen(
          salonId: state.pathParameters['salonId'] ?? '',
        ),
      ),
      // Phase 14.1 — booking flow Step 1 (service selection). The public
      // master profile's «Записатись до майстра» CTA pushes here with
      // the target master id (a bare String) in `extra`. CLIENT-guarded like
      // the profile route. Swaps the former `BookingNewPlaceholderScreen`
      // placeholder for the real `ServiceSelectorSheet`.
      // A missing/wrong-typed/empty `extra` (e.g. a stray direct navigation)
      // redirects to the CLIENT home shell instead of rendering the screen
      // with an empty masterId, matching the fail-safe shape already used by
      // the nested `bookingSlots`/`bookingSlots/time` routes below.
      GoRoute(
        path: RouteNames.bookingNew,
        redirect: (context, state) {
          final roleRedirect = clientOnlyGuard(context, state);
          if (roleRedirect != null) return roleRedirect;
          final Object? extra = state.extra;
          if (extra is! String || extra.isEmpty) {
            return RouteNames.clientHome;
          }
          return null;
        },
        builder: (context, state) =>
            ServiceSelectorSheet(masterId: state.extra! as String),
      ),
      // Phase 14.1 — booking flow Step 2 (calendar + time grid), TWO
      // sequential screens sharing the same `slotPickerProvider` state:
      //   • bookingSlots      → SlotDateScreen ("Оберіть дату")
      //   • bookingSlots/time → SlotTimeScreen ("Оберіть час"), nested so the
      //     date screen stays mounted underneath (keeps the shared autoDispose
      //     provider alive across the push — see slot_picker_notifier.dart).
      // Both require a `BookingSlotPickerArgs` in `extra`; a missing/invalid
      // extra (e.g. a stray direct navigation) redirects back to
      // [RouteNames.bookingNew] rather than crashing on a bad cast.
      GoRoute(
        path: RouteNames.bookingSlots,
        redirect: (context, state) {
          final roleRedirect = clientOnlyGuard(context, state);
          if (roleRedirect != null) return roleRedirect;
          if (state.extra is! BookingSlotPickerArgs) {
            return RouteNames.bookingNew;
          }
          return null;
        },
        builder: (context, state) =>
            SlotDateScreen(args: state.extra! as BookingSlotPickerArgs),
        routes: [
          GoRoute(
            path: 'time',
            redirect: (context, state) {
              final roleRedirect = clientOnlyGuard(context, state);
              if (roleRedirect != null) return roleRedirect;
              if (state.extra is! BookingSlotPickerArgs) {
                return RouteNames.bookingNew;
              }
              return null;
            },
            builder: (context, state) =>
                SlotTimeScreen(args: state.extra! as BookingSlotPickerArgs),
          ),
        ],
      ),
      // Phase 14.2 — booking confirmation (final review before submit).
      // `SlotTimeScreen`'s «Підтвердити» CTA pushes here with a
      // `BookingConfirmArgs` in `extra`. Replaces the Phase 14.1
      // `BookingConfirmPlaceholderScreen` stub at this same path. A missing/
      // wrong-typed `extra` redirects to [RouteNames.bookingNew] — mirrors
      // the `bookingSlots` guard above rather than crashing on a bad cast.
      GoRoute(
        path: RouteNames.bookingConfirm,
        redirect: (context, state) {
          final roleRedirect = clientOnlyGuard(context, state);
          if (roleRedirect != null) return roleRedirect;
          if (state.extra is! BookingConfirmArgs) {
            return RouteNames.bookingNew;
          }
          return null;
        },
        builder: (context, state) =>
            BookingConfirmScreen(args: state.extra! as BookingConfirmArgs),
      ),
      // Phase 14.2 — booking success celebration screen.
      // `BookingConfirmScreen`'s «Записатись» CTA `pushReplacement`s here
      // with a `BookingSuccessArgs` in `extra` once `POST /bookings`
      // succeeds — this REPLACES `/booking/confirm` in the nav stack rather
      // than pushing on top of it, so back/swipe from this screen can never
      // reach the confirmation screen again (there is nothing left to land
      // on but whatever was mounted BELOW confirm, and `BookingSuccessScreen`
      // additionally blocks that via `PopScope(canPop: false)` — see
      // `route_names.dart`'s doc comment). A `GoRouter.redirect` aimed at
      // "prevent back navigation to confirm after success" would therefore be
      // unreachable dead code: `redirect` only runs on a NAVIGATION
      // transition, and there is no transition left that could land back on
      // `/booking/confirm` from here for it to intercept. This route's own
      // `redirect` below only guards role + a missing/invalid `extra` (the
      // same shape every other booking route uses), same as the others.
      GoRoute(
        path: RouteNames.bookingSuccess,
        redirect: (context, state) {
          final roleRedirect = clientOnlyGuard(context, state);
          if (roleRedirect != null) return roleRedirect;
          if (state.extra is! BookingSuccessArgs) {
            return RouteNames.clientHome;
          }
          return null;
        },
        builder: (context, state) =>
            BookingSuccessScreen(args: state.extra! as BookingSuccessArgs),
      ),
      // Phase 14.12 — Salon booking flow step 1 (service selection). The
      // public salon profile's «Записатись на послугу» CTA pushes here with
      // the target salon id (a bare String) in `extra` — CLOSES the reported
      // bug where that CTA pushed [RouteNames.bookingNew] with `salon.id`
      // misused as a `masterId`, 404ing server-side. CLIENT-guarded like the
      // profile route. A missing/empty/wrong-typed `extra` redirects to the
      // CLIENT home shell, mirroring [RouteNames.bookingNew]'s guard.
      GoRoute(
        path: RouteNames.salonBookingServices,
        redirect: (context, state) {
          final roleRedirect = clientOnlyGuard(context, state);
          if (roleRedirect != null) return roleRedirect;
          final Object? extra = state.extra;
          if (extra is! String || extra.isEmpty) {
            return RouteNames.clientHome;
          }
          return null;
        },
        builder: (context, state) =>
            SalonServiceSelectionScreen(salonId: state.extra! as String),
      ),
      // Phase 14.13 — Salon booking flow step 2 (master assignment).
      // `SalonServiceSelectionScreen`'s «Далі» CTA pushes here with a
      // `SalonBookingMasterSelectionArgs` in `extra`. A missing/wrong-typed
      // extra has no natural upstream salon id to chain-redirect through (the
      // preceding step's own route ALSO requires an extra), so this bounces
      // straight to the CLIENT home shell rather than the [bookingSlots]-style
      // upstream hop — mirrors [RouteNames.bookingConfirm]/[bookingSuccess]'s
      // "no natural upstream" fallback shape.
      GoRoute(
        path: RouteNames.salonBookingMasters,
        redirect: (context, state) {
          final roleRedirect = clientOnlyGuard(context, state);
          if (roleRedirect != null) return roleRedirect;
          if (state.extra is! SalonBookingMasterSelectionArgs) {
            return RouteNames.clientHome;
          }
          return null;
        },
        builder: (context, state) => SalonMasterSelectionScreen(
          args: state.extra! as SalonBookingMasterSelectionArgs,
        ),
      ),
      // Phase 14.16/14.17 — Salon booking flow step 3 (per-master date/time
      // picker). `SalonMasterSelectionScreen`'s «Підтвердити» CTA now pushes
      // here (with a `SalonBookingTimeArgs` in `extra`) instead of directly
      // hopping to [salonBookingComingSoon] — same "no natural upstream
      // extra" fallback shape as [salonBookingMasters] above, since a
      // missing/wrong-typed extra has nothing to chain-redirect through.
      GoRoute(
        path: RouteNames.salonBookingTime,
        redirect: (context, state) {
          final roleRedirect = clientOnlyGuard(context, state);
          if (roleRedirect != null) return roleRedirect;
          if (state.extra is! SalonBookingTimeArgs) {
            return RouteNames.clientHome;
          }
          return null;
        },
        builder: (context, state) =>
            SalonTimeScreen(args: state.extra! as SalonBookingTimeArgs),
      ),
      // Phase 14.13 — Salon booking flow step 4 PLACEHOLDER. Step 4
      // (confirmation/submit) is unscoped; `SalonTimeScreen`'s «Підтвердити»
      // CTA (Phase 14.17) routes here instead — carrying the salon id (a
      // bare String) in `extra` for the "back to profile" action — never
      // into the independent-master `SlotPickerScreen` (single-master flow,
      // wrong model for a salon booking), and never a `POST /bookings` call.
      GoRoute(
        path: RouteNames.salonBookingComingSoon,
        redirect: (context, state) {
          final roleRedirect = clientOnlyGuard(context, state);
          if (roleRedirect != null) return roleRedirect;
          final Object? extra = state.extra;
          if (extra is! String || extra.isEmpty) {
            return RouteNames.clientHome;
          }
          return null;
        },
        builder: (context, state) =>
            SalonBookingComingSoonScreen(salonId: state.extra! as String),
      ),
      // Phase 14.18 — Salon booking flow step 4 (confirmation + submit).
      // `SalonTimeScreen`'s «Підтвердити» CTA pushes here with a
      // `SalonBookingConfirmArgs` (the N resolved per-master appointments) in
      // `extra`; this screen submits one `POST /bookings` per master. A
      // missing/wrong-typed extra has no natural upstream to chain through, so
      // it bounces to the CLIENT home shell — same fallback shape as
      // [salonBookingMasters]/[salonBookingTime] above.
      GoRoute(
        path: RouteNames.salonBookingConfirm,
        redirect: (context, state) {
          final roleRedirect = clientOnlyGuard(context, state);
          if (roleRedirect != null) return roleRedirect;
          if (state.extra is! SalonBookingConfirmArgs) {
            return RouteNames.clientHome;
          }
          return null;
        },
        builder: (context, state) => SalonBookingConfirmScreen(
          args: state.extra! as SalonBookingConfirmArgs,
        ),
      ),
      // Phase 14.18 — Salon booking flow step 4b (success recap). Reached ONLY
      // via `SalonBookingConfirmScreen`'s `pushReplacement` once every
      // appointment's booking succeeded, carrying a `SalonBookingSuccessArgs`
      // in `extra`. `pushReplacement` drops the confirm screen from the stack;
      // `SalonBookingSuccessScreen` additionally blocks back via
      // `PopScope(canPop: false)` — mirrors [bookingSuccess]. A missing/
      // invalid extra bounces to the CLIENT home shell.
      GoRoute(
        path: RouteNames.salonBookingSuccess,
        redirect: (context, state) {
          final roleRedirect = clientOnlyGuard(context, state);
          if (roleRedirect != null) return roleRedirect;
          if (state.extra is! SalonBookingSuccessArgs) {
            return RouteNames.clientHome;
          }
          return null;
        },
        builder: (context, state) => SalonBookingSuccessScreen(
          args: state.extra! as SalonBookingSuccessArgs,
        ),
      ),
      // Phase 4.2 — Master profile (read-only). The INDEPENDENT_MASTER's
      // home/tab-root — always first in its Navigator stack (only ever
      // reached via `context.go(...)`, never pushed). `builder:` (MaterialPage)
      // rather than `pageBuilder: _instantPage`, matching the precedent set by
      // `/salons/:salonId` above and closing the follow-up gap noted there:
      // `MasterProfileScreen` renders no back affordance for a stack-root
      // (`showBack: false`), so this is purely about giving the route the
      // same theme-driven page-transition builder as its sibling stack-root
      // screens (`SettingsHubScreen`, `ServicesListScreen`, etc.) — it does
      // NOT enable a swipe-back gesture, which Flutter correctly disarms for
      // any `isFirst` route regardless of page type.
      GoRoute(
        path: RouteNames.masterProfile,
        builder: (context, state) => const MasterProfileScreen(),
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
      //
      // mobile-debugger fix (same latent bug as `/salons/:salonId` and
      // `/masters/:masterId`): the profile bottom-nav "Календар" tile reaches
      // this route via `context.push`, so it needs `builder:` (MaterialPage)
      // for the theme's CupertinoPageTransitionsBuilder to install the
      // left-edge swipe-back gesture — `pageBuilder: _instantPage` silently
      // suppressed it. `context.go(RouteNames.masterSchedule)` elsewhere (the
      // weekly editor's save/cancel returns) is unaffected — `.go` replaces the
      // stack regardless of page type.
      GoRoute(
        path: RouteNames.masterSchedule,
        builder: (context, state) => const MasterScheduleScreen(),
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
