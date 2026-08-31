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
import '../features/booking/domain/booking_entry_args.dart';
import '../features/booking/domain/booking_slot_picker_args.dart';
import '../features/booking/domain/booking_success_args.dart';
import '../features/booking/domain/create_master_booking_request.dart'
    show WalkInGuest;
import '../features/booking/domain/salon_booking_args.dart';
import '../features/booking/domain/salon_booking_confirm_args.dart';
import '../features/booking/presentation/booking_confirm_screen.dart';
import '../features/booking/presentation/booking_detail_screen.dart';
import '../features/booking/presentation/leave_client_feedback_screen.dart';
import '../features/booking/presentation/leave_review_screen.dart';
import '../features/booking/presentation/master_archive_screen.dart';
import '../features/booking/presentation/master_bookings_screen.dart';
import '../features/booking/presentation/booking_success_screen.dart';
import '../features/booking/presentation/my_bookings_screen.dart';
import '../features/booking/presentation/salon_booking_confirm_screen.dart';
import '../features/booking/presentation/salon_booking_success_screen.dart';
import '../features/booking/presentation/salon_create_booking_screen.dart';
import '../features/booking/presentation/salon_master_selection_screen.dart';
import '../features/booking/presentation/salon_service_selection_screen.dart';
import '../features/booking/presentation/salon_time_screen.dart';
import '../features/booking/presentation/service_selector_sheet.dart';
import '../features/booking/presentation/slot_picker_screen.dart';
import '../features/booking/presentation/walk_in_guest_step_screen.dart';
import '../features/booking/presentation/walk_in_service_step_screen.dart';
import '../features/discovery/domain/search_filters.dart';
import '../features/discovery/presentation/search_filters_screen.dart';
import '../features/discovery/presentation/search_results_screen.dart';
import '../features/master/presentation/contacts_edit_screen.dart';
import '../features/master/presentation/location_edit_screen.dart';
import '../features/master/presentation/master_profile_screen.dart';
import '../features/master/presentation/master_received_reviews_screen.dart';
import '../features/master/presentation/personal_info_edit_screen.dart';
import '../features/master/presentation/public_master_profile_screen.dart';
import '../features/master/presentation/public_master_reviews_screen.dart';
import '../features/master/presentation/settings_hub_screen.dart';
import '../features/services/presentation/service_edit_screen.dart';
import '../features/services/presentation/service_setup_screen.dart';
import '../features/services/presentation/services_list_screen.dart';
import '../features/settings/domain/account_settings_extras.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/home/presentation/client_contacts_edit_screen.dart';
import '../features/home/presentation/client_location_edit_screen.dart';
import '../features/home/presentation/client_personal_info_edit_screen.dart';
import '../features/home/presentation/client_settings_hub_screen.dart';
import '../features/favorites/presentation/favorites_screen.dart';
import '../features/home/presentation/home_hub_screen.dart';
import '../features/passport/presentation/passport_screen.dart';
import '../features/wishlist/presentation/wishlist_screen.dart';
import '../features/rating/presentation/my_rating_screen.dart';
import '../features/salon/application/my_salons_notifier.dart';
import '../features/salon/domain/salon.dart';
import '../features/salon/presentation/my_salons_screen.dart';
import '../features/salon/presentation/owner_own_profile_screen.dart';
import '../features/salon/presentation/admin_settings_screen.dart';
import '../features/salon/presentation/invite_staff_screen.dart';
import '../features/salon/presentation/move_admin_salon_screen.dart';
import '../features/salon/presentation/public_salon_profile_screen.dart';
import '../features/salon/presentation/register_salon_screen.dart';
import '../features/salon/presentation/salon_home_resolver_screen.dart';
import '../features/salon/presentation/salon_address_edit_screen.dart';
import '../features/salon/presentation/salon_contacts_edit_screen.dart';
import '../features/salon/presentation/salon_management_profile_screen.dart';
import '../features/salon/presentation/salon_pending_invites_screen.dart';
import '../features/salon/presentation/salon_profile_edit_screen.dart';
import '../features/salon/presentation/salon_settings_screen.dart';
import '../features/salon/presentation/salon_shell_screen.dart';
import '../features/salon/presentation/salon_staff_profile_screen.dart';
import '../features/shell/presentation/client_shell.dart';
import '../features/support/presentation/contact_support_screen.dart';
import '../features/schedule/presentation/master_schedule_screen.dart';
import '../features/schedule/presentation/schedule_editor_stubs.dart';
import '../features/schedule/presentation/weekly_template_editor_screen.dart';
import '../features/services/domain/category_slug.dart';
import '../shared/formatters/api_date.dart';
import 'auth_redirect.dart';
import 'auth_refresh_notifier.dart';
import 'booking_reschedule_seed.dart';
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

  // Phase 21.2 — per-route SALON_OWNER/SALON_ADMIN gate for the owner/admin
  // salon management surfaces (`/salons/:salonId/manage`,
  // `/salons/:salonId/manage/settings`). These sit under the SAME literal
  // `/salons/:salonId` segment [clientOnlyGuard] gates immediately above (the
  // CLIENT-facing public profile), not the `/salon/*` (singular) prefix
  // `auth_redirect.dart` gates for the Phase 250 staff-booking surfaces — so
  // neither existing gate covers this path and it needs its own, mirroring
  // [clientOnlyGuard]'s exact shape but for the inverse role set. An
  // unauthenticated visitor is left to the global [authRedirect] (→ /login).
  //
  // mobile-security MEDIUM follow-up (2026-08-27): role-only was not
  // ownership-bound — a SALON_ADMIN could open ANY salon's `:salonId`, not
  // just their own (not a privilege-escalation: only public salon data
  // renders here, and PATCH/DELETE are backend-gated — but a real UX/exposure
  // gap). `User.salonId` (from `UserProfileResponse.salonId`, mapped in
  // `UserMapper.fromProfileDto`) now lets SALON_ADMIN be checked for an EXACT
  // match against the route's `:salonId`.
  //
  // SALON_OWNER is bound to `mySalonsProvider` (Phase 21.1, `GET
  // /salons/mine`) below, mirroring the admin arm above but against a LIST
  // (an owner can own many salons, so no single session-wide `salonId` can
  // authorize them the way `User.salonId` does for an admin).
  String? salonManageGuard(BuildContext context, GoRouterState state) {
    final session = ref.read(authProvider).value;
    if (session is! Authenticated) return null;
    final UserRole role = session.user.role;
    if (role != UserRole.salonOwner && role != UserRole.salonAdmin) {
      return roleHomePath(role);
    }
    if (role == UserRole.salonAdmin) {
      final String? routeSalonId = state.pathParameters['salonId'];
      if (session.user.salonId != routeSalonId) {
        return roleHomePath(role);
      }
    }
    if (role == UserRole.salonOwner) {
      // `redirect:` is synchronous — NEVER await the network here. Bind
      // against `mySalonsProvider`'s ALREADY-RESOLVED value only:
      //   • resolved AND the route's salonId is not in the owner's list →
      //     redirect (this is the actual authorization check Phase 21.2 left
      //     as a TODO — `GET /salons/mine` now exists to answer it).
      //   • not resolved yet (e.g. a cold deep link that never visited the
      //     hub, so nothing has triggered `mySalonsProvider` before now) →
      //     ADMIT and let `SalonManagementProfileScreen` itself surface a
      //     404/error from the backend. Backend `@authz.canManageSalon` is
      //     the real security boundary regardless — this check is UX-only,
      //     same as the admin arm above.
      //
      // mobile-perf HIGH follow-up (2026-08-28) — `mySalonsProvider` is now
      // `@Riverpod(keepAlive: true)` (`my_salons_notifier.dart`), so this
      // `ref.read` genuinely reads an ALREADY-RESOLVED value on every
      // navigation after the first, instead of re-initializing (and
      // immediately auto-disposing) a fresh fetch on every hub→manage→
      // settings hop and every `authProvider` re-emission while parked
      // there. The "not resolved yet" branch below now fires at most ONCE
      // per session — a true cold deep link that never visited the hub —
      // and `SalonManagementProfileScreen` itself closes that residual
      // window once `mySalonsProvider` resolves (mobile-security LOW
      // follow-up, same date — see that screen's own doc for the bounce).
      //
      // mobile-security MEDIUM follow-up (2026-08-28) — a bare `.value` read
      // is NOT the same as "resolved". Riverpod's `copyWithPrevious` keeps
      // the previous `AsyncData`'s `.value` attached to a LATER `AsyncError`
      // / `AsyncLoading` (e.g. `AsyncLoading(retrying: true)` mid-retry), so
      // right after a cross-account login on the same device (owner A logs
      // out, owner B logs in, no app restart) `.value` can still be owner
      // A's list for one frame while the state itself is not `AsyncData`.
      // Trusting that stale `.value` would ADMIT a deep link to an ID that
      // only matched owner A's (no-longer-current) list — the inverse of
      // this guard's intent. Gate on the concrete `AsyncData` subtype so
      // only a GENUINELY resolved state is ever trusted; an error/loading
      // state — stale `.value` or not — falls through to the documented
      // "not resolved yet" ADMIT fallback below, same as a true cold deep
      // link.
      final String? routeSalonId = state.pathParameters['salonId'];
      final AsyncValue<List<Salon>> mySalonsState = ref.read(mySalonsProvider);
      final List<Salon>? salons = mySalonsState is AsyncData<List<Salon>>
          ? mySalonsState.value
          : null;
      if (salons != null &&
          !salons.any((Salon salon) => salon.id == routeSalonId)) {
        return roleHomePath(role);
      }
    }
    return null;
  }

  // mobile-security HIGH follow-up (2026-08-29) — owner-only gate for the
  // three Phase 21.10 edit-form routes (`/manage/settings/profile-edit`,
  // `/address-edit`, `/contacts-edit`). The approved design is explicit
  // (`docs/signup-designs/SalonManagementDesign/lib/screens/
  // salon_settings_screen.dart:274`: "Owner-only: admins cannot edit salon
  // info.") and `salon_settings_screen.dart` already gates the three rows
  // that push these routes behind `isOwner` — but [salonManageGuard] itself
  // does not distinguish these routes from the admin-permitted ones
  // (`/manage`, `/manage/settings`, `/manage/invite`, `/manage/staff/
  // :memberId`, `/shell`): a SALON_ADMIN of the salon passes it cleanly via
  // deep link or back-stack and can reach a form that actually persists
  // (`PATCH /salons/{salonId}` is `@PreAuthorize("hasAnyRole('SALON_OWNER',
  // 'SALON_ADMIN') and ...")` backend-side).
  //
  // REUSE-FIRST: delegates to [salonManageGuard] FIRST — it already owns the
  // role check, the admin `User.salonId` binding, and the owner
  // `mySalonsProvider` ownership binding (including its documented
  // "unresolved -> ADMIT" cold-deep-link fallback). This wrapper only adds
  // the ADDITIONAL owner-only restriction these three routes need, rather
  // than re-implementing any of that.
  //
  // Fail-closed on the unresolved-ownership window: [salonManageGuard]'s own
  // SALON_OWNER arm deliberately ADMITS while `mySalonsProvider` has not
  // resolved yet (`salons == null` below) — a UX-only tradeoff acceptable for
  // `/manage`/`/manage/settings` because [SalonManagementProfileScreen]
  // itself self-heals via `_bounceIfNotOwned` once the list resolves, and the
  // backend is the real boundary regardless. These three routes are the
  // actual PATCH-triggering forms, so this guard does NOT inherit that
  // admit-while-unresolved tolerance: an owner whose `mySalonsProvider` has
  // not resolved yet is bounced the same as an unowned salon, until
  // ownership can be confirmed synchronously. A non-`Authenticated` session
  // reaching this point (should be unreachable — the top-level [authRedirect]
  // already requires a settled, authenticated session before any per-route
  // redirect runs) is likewise bounced to `/login` rather than silently
  // admitted.
  String? salonManageOwnerOnlyGuard(BuildContext context, GoRouterState state) {
    final String? baseRedirect = salonManageGuard(context, state);
    if (baseRedirect != null) return baseRedirect;

    final session = ref.read(authProvider).value;
    if (session is! Authenticated) {
      // Defensive fail-closed only — see doc above on why this should be
      // unreachable in practice.
      return RouteNames.login;
    }
    final UserRole role = session.user.role;
    if (role != UserRole.salonOwner) {
      // SALON_ADMIN already passed [salonManageGuard]'s ownership binding
      // above but these three forms are owner-only regardless.
      return roleHomePath(role);
    }

    final String? routeSalonId = state.pathParameters['salonId'];
    final AsyncValue<List<Salon>> mySalonsState = ref.read(mySalonsProvider);
    final List<Salon>? salons = mySalonsState is AsyncData<List<Salon>>
        ? mySalonsState.value
        : null;
    if (salons == null ||
        !salons.any((Salon salon) => salon.id == routeSalonId)) {
      return roleHomePath(role);
    }
    return null;
  }

  // Phase 21.1 — per-route SALON_OWNER-only gate for the My Salons Hub
  // (`/salons/mine`). Mirrors [clientOnlyGuard]'s exact shape but for a
  // single role: any other authenticated role — including SALON_ADMIN, who
  // always belongs to exactly one salon and has no use for this hub — is
  // bounced to its own landing. Unauthenticated access is left to the global
  // [authRedirect] (-> /login).
  String? mySalonsGuard(BuildContext context, GoRouterState state) {
    final session = ref.read(authProvider).value;
    if (session is Authenticated && session.user.role != UserRole.salonOwner) {
      return roleHomePath(session.user.role);
    }
    return null;
  }

  // Phase 21.8 — per-route role gate for the shared SALON_OWNER/SALON_ADMIN
  // landing (`/salons/home`, [SalonHomeResolverScreen]). A role-only sibling
  // of [mySalonsGuard] — admits BOTH salon roles (the resolver itself
  // branches on which one), bounces every other authenticated role to its
  // own landing. Unauthenticated access is left to the global [authRedirect]
  // (-> /login).
  String? salonHomeGuard(BuildContext context, GoRouterState state) {
    final session = ref.read(authProvider).value;
    if (session is Authenticated &&
        session.user.role != UserRole.salonOwner &&
        session.user.role != UserRole.salonAdmin) {
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
        // Phase 2.19 MEDIUM-2 (PII screen-protection coverage; the finding's
        // FLAG_SECURE half was REVERSED on 2026-08-20 by product decision —
        // screenshots are allowed, see the header of
        // `lib/core/security/screen_protection.dart`. What the manager still
        // drives is the iOS app-switcher blur plus the shared reference count,
        // and the coverage argument below is unchanged for that):
        // /verification renders OUTSIDE the RegisterFlowShell, so it is NOT
        // covered by the shell's acquire. It instead acquires the
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
              // Phase 111 — real FavoritesScreen replaces the placeholder.
              // Carries the placeholder's `client-branch-favorites` Key
              // forward (see `forbid_missing_client_branch_key.sh`).
              GoRoute(
                path: RouteNames.clientFavorites,
                pageBuilder: (context, state) =>
                    _instantPage(state, const FavoritesScreen()),
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
              // Phase 14.3 — real MyBookingsScreen replaces the placeholder.
              GoRoute(
                path: RouteNames.clientBookings,
                pageBuilder: (context, state) =>
                    _instantPage(state, const MyBookingsScreen()),
                routes: [
                  // MO-8 [mobile-security MEDIUM, fixed] — the
                  // `visit/:appointmentId` GoRoute (and its nested `review`
                  // child) was REMOVED here; it backed the whole-visit detail
                  // screen's cancel, which had no UI entry point since MO-7
                  // deleted `VisitCard` but stayed reachable via an explicit
                  // component-targeted intent. Its backing screens
                  // (`VisitDetailScreen`/`AppointmentReviewScreen`) were
                  // themselves deleted once the "1 booking = 1 feedback"
                  // product decision closed off any whole-visit review
                  // journey — see the mobile-dev deletion-sweep commit that
                  // removed `visit_detail_screen.dart` /
                  // `appointment_review_screen.dart`. Re-adding a whole-visit
                  // entry point starts from scratch, not from those files.
                  // /bookings/:bookingId — «Деталі запису» (14.3/14.4),
                  // pushed onto this branch's own navigator (swipe-back
                  // returns to the still-scrolled list) from a BookingCard
                  // tap. `builder:` (not `pageBuilder: _instantPage`) so the
                  // default Material transition + swipe-back gesture apply,
                  // matching every other pushed-detail route in this file.
                  GoRoute(
                    path: ':bookingId',
                    builder: (context, state) => BookingDetailScreen(
                      bookingId: state.pathParameters['bookingId']!,
                    ),
                    routes: [
                      // Phase 14.6 — «ВІДГУК ПРО МАЙСТРА» (leave-review),
                      // nested under the detail so it pushes onto the Записи
                      // branch's own navigator (swipe-back returns to the
                      // detail). Reached from the detail's `canReview` entry CTA
                      // AND as the backend 18.5 `reviewUrl` push deep-link
                      // target. CLIENT-only via the `/bookings` prefix gate in
                      // [authRedirect]. `builder:` (not `pageBuilder:
                      // _instantPage`) so the default Material transition +
                      // left-edge swipe-back apply, matching the detail route.
                      GoRoute(
                        path: 'review',
                        builder: (context, state) => LeaveReviewScreen(
                          bookingId: state.pathParameters['bookingId']!,
                        ),
                      ),
                    ],
                  ),
                ],
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
                routes: [
                  // Phase 239 — /passport/wishlist, «Усі збережені». Pushed
                  // from the section's «Показати всі (N)» outline button.
                  // Nested under the passport branch so it lands on that
                  // branch's own navigator and swipe-back returns to the
                  // still-scrolled passport page.
                  //
                  // `builder:`, NOT `pageBuilder: _instantPage` — the default
                  // Material transition and the swipe-back gesture apply, which
                  // is what every other pushed-detail route in this file does.
                  // `_instantPage` is for branch ROOTS, where a transition
                  // would animate a tab switch.
                  GoRoute(
                    path: 'wishlist',
                    builder: (context, state) => const WishlistScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      // Phase 21.13 — `extra` is OPTIONAL: every existing caller pushes with
      // none at all, which resolves `state.extra` to `null` here and falls
      // through to `SettingsScreen`'s own all-`false`/`null` defaults,
      // rendering EXACTLY as before this phase. Only a caller that already
      // knows a salonId (the owner-only «Загальне» row, Phase 21.9) passes
      // an [AccountSettingsExtras].
      GoRoute(
        path: RouteNames.settings,
        builder: (context, state) {
          final extras = state.extra as AccountSettingsExtras?;
          return SettingsScreen(
            salonId: extras?.salonId,
            showDeleteSalon: extras?.showDeleteSalon ?? false,
          );
        },
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
      // Phase 4.x — Public master reviews (CLIENT-facing, read-only). Pushed
      // from the public master profile's «Відгуки» stat tile. Same
      // lifecycle/guard as `/masters/:masterId` above — CLIENT-guarded,
      // in-app-push-only. Deliberately NOT `RouteNames.masterReceivedReviews`
      // (param-less, always resolves the AUTHENTICATED master's own
      // reviews) — this route carries the target masterId as a path param so
      // `PublicMasterReviewsScreen` queries the correct master's reviews.
      GoRoute(
        path: '/masters/:masterId/reviews',
        redirect: clientOnlyGuard,
        builder: (context, state) => PublicMasterReviewsScreen(
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
      // Phase 21.1 — My Salons Hub, the SALON_OWNER's landing. STANDALONE
      // top-level route registered as a LITERAL path segment ('/salons/mine')
      // DECLARED BEFORE the dynamic '/salons/:salonId' route immediately
      // below — go_router resolves literal-vs-dynamic purely by declaration
      // order, so this ordering is the ONLY thing preventing 'mine' from
      // being swallowed as a `:salonId` value (see `RouteNames.mySalons`'s
      // own doc). Not nested under '/salons/:salonId' for the same "an
      // ancestor route's own redirect always runs" reason [RouteNames
      // .salonManage] documents two routes down.
      GoRoute(
        path: RouteNames.mySalons,
        redirect: mySalonsGuard,
        builder: (context, state) => const MySalonsScreen(),
      ),
      // Phase 21.8 — the shared SALON_OWNER/SALON_ADMIN landing
      // (`roleHomePath`). A SECOND literal under the `/salons/` prefix,
      // registered BEFORE the dynamic `/salons/:salonId` route immediately
      // below for the identical "declaration order, not specificity" reason
      // [RouteNames.mySalons] documents — otherwise `/salons/home` resolves
      // to the public-profile route with `salonId == 'home'`.
      GoRoute(
        path: RouteNames.salonHome,
        redirect: salonHomeGuard,
        builder: (context, state) => const SalonHomeResolverScreen(),
      ),
      // Phase 21.3 — the «+ Додати салон» form ([RouteNames.registerSalon]).
      // A THIRD literal under the `/salons/` prefix, registered BEFORE the
      // dynamic `/salons/:salonId` route immediately below for the identical
      // "declaration order, not specificity" reason [RouteNames.mySalons] /
      // [RouteNames.salonHome] document — otherwise `/salons/register` would
      // resolve to the public-profile route with `salonId == 'register'`.
      // Reuses [mySalonsGuard] VERBATIM — identical SALON_OWNER-only
      // semantics, so no second guard closure was written.
      GoRoute(
        path: RouteNames.registerSalon,
        redirect: mySalonsGuard,
        builder: (context, state) => const RegisterSalonScreen(),
      ),
      // Phase 21.14 — the owner's own first-person profile
      // ([RouteNames.ownerOwnProfile]), pushed STAND-ALONE (`embedded: false`
      // → keeps a back chevron). The SAME screen is hosted as the owner
      // shell's «Профіль» tab with `embedded: true`, but that is an
      // `IndexedStack` slot built directly by `SalonShellScreen`, not a nested
      // route — so this registration is the stand-alone entry only.
      //
      // `/profile` is a fresh top-level prefix with no dynamic sibling, so
      // unlike the three `/salons/` literals above there is no
      // literal-vs-dynamic shadowing to order around here. A future
      // `/profile/:id` would have to be declared AFTER this route.
      //
      // Reuses [mySalonsGuard] VERBATIM — identical SALON_OWNER-only
      // semantics, so no second guard closure was written.
      //
      // DOUBLE MOUNT (mobile-perf LOW, 2026-08-31) — pushed from INSIDE the
      // shell this mounts a second `OwnerOwnProfileScreen` alongside the
      // retained `IndexedStack` slot-2 instance (that stack never disposes a
      // visited child). That is now BALANCED BY CONSTRUCTION rather than by
      // luck, which is why the route is kept rather than deleted:
      //   • screen protection is REF-COUNTED and each instance holds exactly
      //     one reference while it is visible, releasing it on its own
      //     visibility flip or dispose (`OwnerOwnProfileScreen.visible`), so
      //     count 2 → 1 on pop is correct, not a leak;
      //   • the shell's instance has already spent its one-shot entrance and
      //     is `TickerMode`-muted by go_router while covered, so its
      //     `AnimationController` costs nothing;
      //   • both instances watch the SAME keepAlive `ownerOwnProfileProvider`,
      //     so the second subscription issues no extra request.
      // A future caller must still pass through [mySalonsGuard]; nothing
      // links here today, so this is the stand-alone entry only.
      GoRoute(
        path: RouteNames.ownerOwnProfile,
        redirect: mySalonsGuard,
        builder: (context, state) => const OwnerOwnProfileScreen(),
      ),
      GoRoute(
        path: '/salons/:salonId',
        redirect: clientOnlyGuard,
        builder: (context, state) => PublicSalonProfileScreen(
          salonId: state.pathParameters['salonId'] ?? '',
        ),
      ),
      // Phase 21.2 — owner/admin editable salon profile + its settings page.
      //
      // Registered as STANDALONE top-level routes, NOT nested under
      // `/salons/:salonId` above, even though the path literally extends it.
      // go_router's redirect resolution walks the WHOLE match list and runs
      // every ancestor route's own `redirect` (see `RouteConfiguration
      // ._processRouteLevelRedirects` → `visitRouteMatches`), not just the
      // leaf's — nesting here would mean `/salons/:salonId`'s own
      // `clientOnlyGuard` ALSO ran on every `.../manage` navigation and
      // bounced every owner/admin away before `salonManageGuard` below ever
      // got a chance to run. Mirrors [RouteNames.salonStaffBookingNew]'s own
      // "no shell to nest under" precedent, just for a different reason (a
      // conflicting ANCESTOR guard, not a missing one).
      // NOTE: the path below is a literal `:salonId` GoRouter placeholder,
      // NOT built via `RouteNames.salonManage(...)` — that helper
      // URL-encodes its argument (`Uri.encodeComponent`), which would mangle
      // the literal colon into `%3A` and break route matching. Mirrors how
      // `/salons/:salonId` immediately above is registered as a raw literal
      // for the same reason.
      GoRoute(
        path: '/salons/:salonId/manage',
        redirect: salonManageGuard,
        builder: (context, state) => SalonManagementProfileScreen(
          salonId: state.pathParameters['salonId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/salons/:salonId/manage/settings',
        redirect: salonManageGuard,
        builder: (context, state) =>
            SalonSettingsScreen(salonId: state.pathParameters['salonId'] ?? ''),
      ),
      // Phase 21.4 — invite an admin/master to this salon. Literal `/invite`
      // leaf below the ALREADY-RESOLVED `:salonId` capture, so no
      // literal-vs-dynamic shadowing applies (that concern is limited to a
      // literal declared after a dynamic SIBLING at the SAME segment, e.g.
      // /salons/mine vs /salons/:salonId). STANDALONE top-level route for
      // the same "an ancestor's own redirect always runs" reason /manage and
      // /manage/settings document — nesting under /salons/:salonId would let
      // clientOnlyGuard bounce every owner/admin first. Reuses
      // salonManageGuard VERBATIM: it already binds SALON_OWNER (against
      // mySalonsProvider) and SALON_ADMIN (against User.salonId).
      GoRoute(
        path: '/salons/:salonId/manage/invite',
        redirect: salonManageGuard,
        builder: (context, state) =>
            InviteStaffScreen(salonId: state.pathParameters['salonId'] ?? ''),
      ),
      // Phase 21.11 — «Надіслані запрошення», the sent-but-unaccepted staff
      // invitations. Reuses [salonManageGuard] VERBATIM (owner + admin, each
      // bound to their own salon) rather than
      // [salonManageOwnerOnlyGuard]: this surface is admin-permitted by
      // design — the Phase 21.9 settings hub renders its entry row OUTSIDE
      // the owner-only block, and backend 23.1's
      // `GET/DELETE /salons/{salonId}/invites/...` pair is itself owner+admin
      // scoped. The owner-only guard exists for the three Phase 21.10 salon
      // EDIT forms ("admins cannot edit salon info"), which this is not.
      // STANDALONE top-level route for the same "an ancestor's own redirect
      // always runs" reason `/manage` and `/manage/invite` document — nesting
      // under `/salons/:salonId` would let `clientOnlyGuard` bounce every
      // owner/admin first.
      GoRoute(
        path: '/salons/:salonId/pending-invites',
        redirect: salonManageGuard,
        builder: (context, state) => SalonPendingInvitesScreen(
          salonId: state.pathParameters['salonId'] ?? '',
        ),
      ),
      // Phase 21.5 — staff member (master OR admin) management profile.
      // STANDALONE for the same reason as `/manage/invite` directly above:
      // go_router runs every ancestor's redirect, so nesting under
      // `/salons/:salonId` would let clientOnlyGuard bounce owners/admins
      // first.
      GoRoute(
        path: '/salons/:salonId/manage/staff/:memberId',
        redirect: salonManageGuard,
        builder: (context, state) => SalonStaffProfileScreen(
          salonId: state.pathParameters['salonId'] ?? '',
          memberId: state.pathParameters['memberId'] ?? '',
        ),
      ),
      // Phase 21.6 — the admin-settings page and its rotate-destination
      // picker. Two literal leaves (`/settings`, `/move`) below the
      // ALREADY-RESOLVED `:salonId`/`:memberId` captures, so declaration
      // order among them carries no shadowing risk (that concern applies
      // only to a literal declared after a dynamic SIBLING at the SAME
      // segment, e.g. `/salons/mine` vs `/salons/:salonId`). STANDALONE
      // top-level routes for the same "an ancestor's own redirect always
      // runs" reason `/manage/staff/:memberId` directly above documents.
      //
      // Gated by `salonManageGuard`, NOT `salonManageOwnerOnlyGuard`: all
      // three backend endpoints these screens call
      // (`DELETE|PATCH /salons/{salonId}/admins/{userId}` and
      // `GET /salons/{salonId}/sibling-salons`) are
      // `hasAnyRole('SALON_OWNER','SALON_ADMIN') and @authz.canManageSalon`
      // — an assigned admin may manage a fellow admin. The owner-only guard
      // exists for the Phase 21.10 salon EDIT forms, which these are not.
      GoRoute(
        path: '/salons/:salonId/manage/staff/:memberId/settings',
        redirect: salonManageGuard,
        builder: (context, state) => AdminSettingsScreen(
          salonId: state.pathParameters['salonId'] ?? '',
          memberId: state.pathParameters['memberId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/salons/:salonId/manage/staff/:memberId/move',
        redirect: salonManageGuard,
        builder: (context, state) => MoveAdminSalonScreen(
          salonId: state.pathParameters['salonId'] ?? '',
          memberId: state.pathParameters['memberId'] ?? '',
        ),
      ),
      // Phase 21.10 — the three lightweight edit-form screens the Phase 21.9
      // settings hub pushes to. STANDALONE top-level routes,
      // same "an ancestor's own redirect always runs" reason
      // [salonManage]/[salonManageSettings] document immediately above — and
      // literal children of the ALREADY-literal `.../manage/settings` chain,
      // so there is no dynamic `:salonId`-shadowing risk at this level (that
      // concern only applies to a literal declared AFTER a dynamic SIBLING at
      // the SAME segment, e.g. `/salons/mine` vs `/salons/:salonId` above —
      // these three segments sit strictly BELOW the already-resolved
      // `:salonId` capture, so declaration order among them doesn't matter).
      //
      // mobile-security HIGH follow-up (2026-08-29) — these three routes are
      // owner-only (design: "Owner-only: admins cannot edit salon info.") but
      // were still gated by the shared [salonManageGuard], which admits any
      // SALON_ADMIN of the salon. Now Phase 21.9 wired real in-app entry
      // points (the settings hub's owner-only rows), a SALON_ADMIN could
      // reach these actually-persisting PATCH forms by deep link or
      // back-stack. [salonManageOwnerOnlyGuard] composes [salonManageGuard]
      // (unchanged) with an additional owner-only check — see its own doc.
      GoRoute(
        path: '/salons/:salonId/manage/settings/profile-edit',
        redirect: salonManageOwnerOnlyGuard,
        builder: (context, state) => SalonProfileEditScreen(
          salonId: state.pathParameters['salonId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/salons/:salonId/manage/settings/address-edit',
        redirect: salonManageOwnerOnlyGuard,
        builder: (context, state) => SalonAddressEditScreen(
          salonId: state.pathParameters['salonId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/salons/:salonId/manage/settings/contacts-edit',
        redirect: salonManageOwnerOnlyGuard,
        builder: (context, state) => SalonContactsEditScreen(
          salonId: state.pathParameters['salonId'] ?? '',
        ),
      ),
      // Phase 21.8 — the salon-scoped bottom-nav shell
      // ([RouteNames.salonShell]). Reuses [salonManageGuard] VERBATIM — it
      // already binds ownership for both SALON_OWNER (against
      // `mySalonsProvider`) and SALON_ADMIN (against `User.salonId`), the
      // exact authorization this route needs. A STANDALONE top-level route,
      // same "an ancestor's own redirect always runs" reason
      // [salonManage]/[salonManageSettings] document — nesting under
      // `/salons/:salonId` would let that route's own `clientOnlyGuard` run
      // first and bounce every owner/admin away.
      GoRoute(
        path: '/salons/:salonId/shell',
        redirect: salonManageGuard,
        builder: (context, state) =>
            SalonShellScreen(salonId: state.pathParameters['salonId'] ?? ''),
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
      //
      // Phase 241 — ADDITIVE second `extra` shape: a [BookingEntryArgs] for a
      // caller that already knows exactly which service to book (the
      // wish-list rebook CTA). The bare-`String` shape above is UNCHANGED and
      // every existing call site keeps working verbatim — this is the "add a
      // pre-selection argument rather than forking the flow" seam, not a
      // second route.
      GoRoute(
        path: RouteNames.bookingNew,
        redirect: (context, state) {
          final roleRedirect = clientOnlyGuard(context, state);
          if (roleRedirect != null) return roleRedirect;
          final Object? extra = state.extra;
          final bool validExtra = switch (extra) {
            String s => s.isNotEmpty,
            BookingEntryArgs args => args.masterId.isNotEmpty,
            _ => false,
          };
          if (!validExtra) return RouteNames.clientHome;
          return null;
        },
        builder: (context, state) {
          final Object? extra = state.extra;
          if (extra is BookingEntryArgs) {
            return ServiceSelectorSheet(
              masterId: extra.masterId,
              initialServiceId: extra.preselectedServiceId,
              autoAdvance: true,
            );
          }
          return ServiceSelectorSheet(masterId: extra! as String);
        },
      ),
      // Booking flow Step 2 — the single date→time picker for the WHOLE visit
      // (MO-3). The client picks ONE date then ONE start time; availability is
      // fetched for the full ordered service selection (summed-duration block)
      // and the whole visit is submitted as ONE `POST /appointments`.
      //
      //   • bookingSlots      → SlotDateScreen — «Оберіть дату»
      //   • bookingSlots/time → SlotTimeScreen — «Оберіть час»
      // Both share `slotPickerProvider` and require a `BookingSlotPickerArgs` in
      // `extra` (reached from `ServiceSelectorSheet`'s «Далі», and from the
      // reschedule surface with a non-null `rescheduleBookingId`); a missing/
      // invalid extra redirects back to [RouteNames.bookingNew] rather than
      // crashing on a bad cast.
      GoRoute(
        path: RouteNames.bookingSlots,
        redirect: (context, state) {
          // Phase 27.2 follow-up — a PROVIDER rescheduling its own booking
          // re-enters this CLIENT picker rather than forking a provider-only
          // copy of it, so the role bounce is skipped for a reschedule-shaped
          // seed only. A CREATE-shaped `BookingSlotPickerArgs` still bounces.
          // See `booking_reschedule_seed.dart` for the SEC rationale.
          if (!isBookingProviderSeed(state.extra)) {
            final roleRedirect = clientOnlyGuard(context, state);
            if (roleRedirect != null) return roleRedirect;
          }
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
              // Same Phase 27.2 reschedule admission as the parent route.
              if (!isBookingProviderSeed(state.extra)) {
                final roleRedirect = clientOnlyGuard(context, state);
                if (roleRedirect != null) return roleRedirect;
              }
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
          // Same Phase 27.2 reschedule admission as `bookingSlots` above.
          if (!isBookingProviderSeed(state.extra)) {
            final roleRedirect = clientOnlyGuard(context, state);
            if (roleRedirect != null) return roleRedirect;
          }
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
          // Same Phase 27.2 reschedule admission as `bookingSlots` above —
          // keyed off `BookingSuccessArgs.isReschedule` here.
          if (!isBookingProviderSeed(state.extra)) {
            final roleRedirect = clientOnlyGuard(context, state);
            if (roleRedirect != null) return roleRedirect;
          }
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
      // MO-4 — Salon booking flow step 3 (single date/time picker).
      // `SalonMasterSelectionScreen`'s «Далі» CTA pushes here with a
      // `SalonBookingTimeArgs` (the resolved single-master visit) in `extra` —
      // same "no natural upstream extra" fallback shape as [salonBookingMasters]
      // above, since a missing/wrong-typed extra has nothing to chain-redirect
      // through.
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
      // MO-4 — Salon booking flow step 4 (confirmation + submit).
      // `SalonTimeScreen`'s «Підтвердити» CTA pushes here with a
      // `SalonBookingConfirmArgs` (the single resolved visit) in `extra`; this
      // screen submits ONE `POST /appointments` via the shared
      // `AppointmentSubmit`. A missing/wrong-typed extra has no natural upstream
      // to chain through, so it bounces to the CLIENT home shell — same
      // fallback shape as [salonBookingMasters]/[salonBookingTime] above.
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
      // Phase 7.6 — the master's «Мої записи», the bottom-nav tab-1 destination
      // that had no route until this phase (see `profile_avatar.dart`).
      //
      // Registered as a TOP-LEVEL route alongside its `/master/*` siblings
      // rather than inside a `StatefulShellBranch`: the master surface is not a
      // StatefulShellRoute at all — unlike the CLIENT shell above, the master's
      // four "tabs" are four flat routes that each render their own
      // `VelvetBottomNavBar` and navigate by `context.go` (a deliberate
      // reversal of the earlier `context.push` decision — see
      // `velvet_bottom_nav_bar.dart`'s `onTap` comment for why stacking a
      // route per tab tap grew the back stack unboundedly). The Phase 7.6
      // phase doc's "register in the master shell branch, mirroring
      // `app_router.dart:455-490`" describes a structure that does not exist
      // here; mirroring the /bookings + :bookingId NESTING (which is the part
      // that matters) is what is done instead.
      //
      // `builder:` (MaterialPage), not `pageBuilder: _instantPage` — the tab is
      // reached by `context.go`, which makes it a stack ROOT, so there is no
      // swipe-back gesture to arm here (Flutter disarms it for any `isFirst`
      // route regardless of page type). `builder:` is kept so the route gets
      // the same theme-driven page-transition builder as its sibling
      // stack-root screens, exactly as `RouteNames.masterProfile` above
      // documents. Same shape as `/master/schedule` and `/masters/:masterId`.
      GoRoute(
        path: RouteNames.masterBookings,
        builder: (context, state) => const MasterBookingsScreen(),
        routes: [
          // Phase 231 — /master/bookings/archive, the master «Архів» page.
          // Registered BEFORE the `:bookingId` sibling below so the literal
          // segment is never shadowed by the dynamic one (go_router matches
          // in declaration order among siblings). `builder:` (MaterialPage)
          // so the theme's CupertinoPageTransitionsBuilder installs the
          // left-edge swipe-back gesture, matching every other pushed
          // /master/* sub-route.
          GoRoute(
            path: 'archive',
            builder: (context, state) => const MasterArchiveScreen(),
          ),
          // Phase 247 — /master/bookings/new, the master «Новий запис» walk-in
          // booking entry point. Registered BEFORE the `:bookingId` sibling
          // below for the same reason `archive` is (go_router matches
          // literal segments before dynamic ones only by declaration order
          // among siblings) — `new` must never be shadowed by `:bookingId`.
          // `pageBuilder` + `MaterialPage(fullscreenDialog: true)` per the
          // phase doc; reached via `context.push` (never `Navigator`).
          //
          // Phase 264 — builder swapped from the retired single-screen
          // walk-in wizard to [WalkInGuestStepScreen], the first thin screen
          // of the ROUTED walk-in chain (see `route_names.dart`'s
          // [RouteNames.masterBookingNewServices] doc and phase-264's D4).
          // The old wizard screen was deleted outright in Phase 265.
          GoRoute(
            path: 'new',
            pageBuilder: (context, state) => const MaterialPage<void>(
              fullscreenDialog: true,
              child: WalkInGuestStepScreen(),
            ),
            routes: [
              // Phase 264 — /master/bookings/new/services, the walk-in
              // chain's service multi-select step. A NESTED child of `new`,
              // never a second top-level literal — this introduces no new
              // sibling under [masterBookings], so the `archive` / `new` /
              // `:bookingId` literal-before-dynamic ordering above is
              // untouched (mirrors how `time` nests under [bookingSlots]
              // elsewhere in this file). Reached with `context.push` from
              // [WalkInGuestStepScreen]'s «Далі», carrying the minted
              // [WalkInGuest] in `extra`. A missing/wrong-typed `extra`
              // (e.g. a direct deep link) bounces back to
              // [RouteNames.masterBookingNew] — a two-hop bounce to a safe
              // place once that screen's own guard sends a non-master
              // there too (phase-264 D9, pinned by test).
              GoRoute(
                path: 'services',
                redirect: (context, state) => state.extra is WalkInGuest
                    ? null
                    : RouteNames.masterBookingNew,
                // `builder:` (MaterialPage, not fullscreenDialog) — mirrors
                // how `time` nests under [bookingSlots] elsewhere in this
                // file: a normal forward push within the already-modal
                // chain, carrying the theme's swipe-back gesture.
                builder: (context, state) =>
                    WalkInServiceStepScreen(guest: state.extra! as WalkInGuest),
              ),
            ],
          ),
          // /master/bookings/:bookingId — the PROVIDER view of «Деталі
          // запису» (Phase 7.2). The SAME `BookingDetailScreen` the client
          // route renders: one screen, role-branched off the session (locked
          // decision D5), never a second screen and never a constructor flag.
          //
          // Nested so it pushes onto the master's own navigator stack and pops
          // back to the still-scrolled list — mirroring the client's
          // `/bookings/:bookingId` nesting exactly.
          GoRoute(
            path: ':bookingId',
            builder: (context, state) => BookingDetailScreen(
              bookingId: state.pathParameters['bookingId']!,
            ),
          ),
        ],
      ),
      // Phase 250 — /salon/bookings/new, the SALON «Новий запис» wizard.
      //
      // Registered as a STANDALONE top-level route, NOT nested under a
      // `/salon/bookings` parent `GoRoute` — unlike [masterBookings]
      // (`/master/bookings`), there is no parent SCREEN yet for the bare
      // `/salon/bookings` path (that is Phase 251's Розклад entry point);
      // mirrors [RouteNames.clientReview]'s own "standalone top-level route,
      // not nested under a plain content screen" precedent (see that route's
      // registration comment further down for the full go_router-matcher
      // rationale). `salonId` travels via `extra` (a bare `String`) — this
      // route's own path carries no id, mirroring [salonBookingServices]'s
      // identical "no natural upstream salon id" shape.
      //
      // Role gate: the `/salon/*` prefix gate added to `auth_redirect.dart`
      // for this phase (SALON_OWNER / SALON_ADMIN only) — no per-route
      // `clientOnlyGuard`-style duplicate needed here, unlike the CLIENT
      // salon-booking routes above (those sit under `/booking/salon/*`,
      // which carries NO prefix gate in `auth_redirect.dart`, hence their
      // own redirect closures).
      //
      // ⚠ SHADOWING — if a future phase nests a dynamic sibling (most likely
      // `/salon/bookings/:bookingId`) under a shared `/salon/bookings`
      // parent, this literal `new` MUST be declared before it — see
      // [RouteNames.salonStaffBookingNew]'s own doc and
      // `master_bookings_route_shadowing_test.dart` for why the ordering,
      // not the path string, is what actually resolves the request.
      // `test/routing/salon_bookings_route_shadowing_test.dart` pins the
      // resolved page TYPE for this route today (no dynamic sibling exists
      // yet, so nothing can shadow it) and documents the same guard for
      // whichever phase adds one.
      //
      // `pageBuilder` + `MaterialPage(fullscreenDialog: true)`, matching
      // [masterBookingNew]. Reached via `context.push` (never `Navigator`).
      GoRoute(
        path: RouteNames.salonStaffBookingNew,
        redirect: (context, state) {
          final Object? extra = state.extra;
          if (extra is! String || extra.isEmpty) {
            // No natural upstream to chain-redirect through — same shape as
            // [salonBookingServices]'s own missing-extra fallback, but the
            // landing is role-derived (this route's callers are staff, not
            // CLIENT) rather than a fixed `clientHome`.
            final session = ref.read(authProvider).value;
            return session is Authenticated
                ? roleHomePath(session.user.role)
                : RouteNames.login;
          }
          return null;
        },
        pageBuilder: (context, state) => MaterialPage<void>(
          fullscreenDialog: true,
          child: SalonCreateBookingScreen(salonId: state.extra! as String),
        ),
      ),
      // Track 7.x Wave B — «ВІДГУК ПРО КЛІЄНТА» (leave-client-feedback).
      // Registered as a STANDALONE top-level route carrying the SAME full
      // path [RouteNames.clientReview] resolves to
      // (`/master/bookings/:bookingId/review`), rather than nested under
      // `masterBookingDetail` above — mirrors the `/masters/:masterId` +
      // `/masters/:masterId/reviews` sibling pair further up this file.
      //
      // WHY: go_router's matcher inserts every ANCESTOR route's own
      // `RouteMatch` into a pushed match list for a nested `GoRoute`
      // (`match.dart`) so it can build the full page stack in one shot. That
      // is correct when the ancestor is a shell wrapping shared chrome, but
      // `masterBookingDetail` is a plain content screen, not chrome — nesting
      // `review` under it meant EVERY push, including the one from the
      // archive list (`master_archive_screen.dart`), silently built and
      // mounted a full, invisible `BookingDetailScreen` underneath the
      // review screen. Popping then landed the user on that shadow detail
      // screen instead of back on whatever they actually came from (the
      // archive list, in that case) — a real navigation bug, not just
      // wasted work.
      //
      // As a standalone route this path produces exactly ONE match, so a
      // push here only ever adds ONE page on top of whatever is already on
      // the (shared, non-shell) master Navigator stack:
      //   • from the archive (`/master/bookings/archive` pushed) → pop
      //     returns to the archive list.
      //   • from the detail (`/master/bookings/:bookingId` pushed) → pop
      //     returns to the detail screen, which is legitimately on the
      //     stack there via the user's own navigation.
      //
      // SHELL CHECK: the master surface (`masterBookings` and everything
      // under it) is NOT a `StatefulShellRoute` — see the doc above
      // `RouteNames.masterBookings` and this file's own `masterBookings`
      // registration comment ("the master's four 'tabs' are four flat
      // routes"). So there is no shell chrome to preserve or lose here: both
      // before and after this change, `LeaveClientFeedbackScreen` renders as
      // a plain full-screen page on the root Navigator, with the master
      // bottom nav supplied by the tab-root screen itself, not by any shell.
      // Moving this route out of the nested position changes nothing about
      // that.
      //
      // `builder:` (not `pageBuilder: _instantPage`) so the default Material
      // transition + left-edge swipe-back apply, matching the detail route
      // and its CLIENT-side `review` twin ([RouteNames.bookingReview]).
      //
      // `extra` carries the ENTRY POINT ([ClientReviewEntry]) — never a path
      // or query segment, because it is not part of the resource's identity
      // and must not survive into a deep link or a shared URL. It decides one
      // thing on the destination: whether a successful submit invalidates
      // `bookingDetailProvider` before popping (required for the detail entry,
      // pure waste for the archive entry — see that enum's own doc). An absent
      // or unexpected `extra` falls back to [ClientReviewEntry.bookingDetail],
      // the direction whose failure mode is one wasted fetch rather than a
      // resurrected stale CTA.
      GoRoute(
        path: '/master/bookings/:bookingId/review',
        builder: (context, state) => LeaveClientFeedbackScreen(
          bookingId: state.pathParameters['bookingId']!,
          entry: switch (state.extra) {
            final ClientReviewEntry entry => entry,
            _ => ClientReviewEntry.bookingDetail,
          },
        ),
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
      // Phase 4.6 — Master received-reviews («Мої відгуки»). Pushed from the
      // profile "Відгуки" stat tile. MaterialPage (builder:) so the theme's
      // CupertinoPageTransitionsBuilder installs the left-edge swipe-back
      // gesture, matching the sibling /master/* sub-routes above.
      GoRoute(
        path: RouteNames.masterReceivedReviews,
        builder: (context, state) => const MasterReceivedReviewsScreen(),
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
      // Service setup (INDEPENDENT_MASTER) — the ONE "add services" surface,
      // reached from both the services-list empty state and the «Додати
      // послугу» FAB. (The Phase 5.3 single-create form at /services/create was
      // removed when the two flows collapsed onto this screen.)
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
      // `?date=yyyy-MM-dd` — pre-selects a date instead of today (see
      // `RouteNames.masterSchedule`'s doc). Malformed/absent → `null` →
      // [MasterScheduleScreen] opens on today, unchanged.
      GoRoute(
        path: RouteNames.masterSchedule,
        builder: (context, state) {
          final String? raw = state.uri.queryParameters['date'];
          DateTime? initialDate;
          if (raw != null) {
            try {
              initialDate = parseApiDate(raw);
            } on FormatException {
              initialDate = null;
            } on ArgumentError {
              // Defence in depth (mobile-security HIGH). `parseApiDate`
              // itself now bound-checks before ever constructing a
              // `DateTime`, so this branch should be unreachable — but this
              // route is reachable from an explicit, component-targeted deep
              // link an attacker fully controls (`MainActivity` is
              // `exported="true"`; see this route's doc), so a second net
              // against `DateTime`'s own `ArgumentError` costs nothing and
              // survives a future regression in that bound check.
              initialDate = null;
            }
          }
          return MasterScheduleScreen(initialDate: initialDate);
        },
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
