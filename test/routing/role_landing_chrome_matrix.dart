// Role → landing → expected-nav-chrome matrix (shared source of truth).
//
// THE BUG CLASS THIS GUARDS (commit f929caf)
// ------------------------------------------
// A logged-in role was dispatched to the wrong screen — specifically a CLIENT
// landed on `/` (a bare "Скоро…" placeholder with NO bottom bar) instead of
// `/home` (the ClientShell that hosts ClientBottomNav). The navigation element
// existed and rendered fine; the navigation simply never delivered the user to
// the screen that hosts it. The dispatch sites (done_screen.dart, the
// auth_redirect role-gate bounces) had hardcoded `RouteNames.home` for a CLIENT
// instead of routing through the shared `roleHomePath()` helper.
//
// The old tests missed it because they asserted route STRINGS in isolation —
// never "did the expected chrome actually appear for this role". This matrix is
// the durable fix: it pins, for every role, (a) the path roleHomePath() must
// resolve to, and (b) the navigation-chrome widget the user must actually see
// once landed there.
//
// HOW TO ADD A ROW (do this whenever a new role-shell or bottom-bar ships)
// ------------------------------------------------------------------------
// 1. Add one [RoleLandingExpectation] to [roleLandingMatrix] below.
// 2. Set [expectedLandingPath] to the route roleHomePath() should return.
// 3. EITHER set [chromeFinder] to the nav-chrome widget the role must SEE
//    (e.g. `find.byType(ClientBottomNav)`) and leave [hasChrome] = true,
//    OR — for an intentional no-chrome "coming soon" landing — leave
//    [chromeFinder] null and set [hasChrome] = false with a [comingSoonReason].
// 4. That single row is consumed by BOTH tiers automatically:
//      • the pure-fn dispatch guard (role_landing_dispatch_guard_test.dart)
//        asserts roleHomePath(role) == expectedLandingPath, and that every
//        chrome-bearing landing is a real chrome host, not the bare `/`;
//      • the router-tier chrome guard (role_landing_chrome_test.dart) boots the
//        REAL appRouter for that role, drives it to the landing, and asserts the
//        chrome widget is present (or, for no-chrome rows, asserts it is absent
//        AND documents why).
// No per-role copy-paste — one row, both nets. This mirrors the cheap-to-extend
// provider-cycle / leaked-timer guards.
//
// Note: `test/` is excluded from the `no_raw_ui_strings` lint. Every assertion
// keys off route constants and widget TYPES — never raw Ukrainian text — so an
// l10n key move cannot mask a regression (mobile-qa M2).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/profile_avatar.dart';
import 'package:beautica_mobile/features/shell/presentation/widgets/client_bottom_nav.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/salon_bottom_nav.dart';
import 'package:flutter_test/flutter_test.dart';

/// One row of the role → landing → chrome contract.
class RoleLandingExpectation {
  const RoleLandingExpectation({
    required this.role,
    required this.expectedLandingPath,
    required this.hasChrome,
    this.chromeFinder,
    this.chromeDescription,
    this.comingSoonReason,
    this.locationIsTransient = false,
  }) : assert(
         hasChrome == (chromeFinder != null),
         'a chrome-bearing row must supply a chromeFinder; a no-chrome row '
         'must omit it',
       ),
       assert(
         hasChrome || comingSoonReason != null,
         'an intentional no-chrome row must document its comingSoonReason',
       );

  /// The authenticated role being dispatched.
  final UserRole role;

  /// The path [roleHomePath] must resolve to for this role.
  final String expectedLandingPath;

  /// Whether this landing is REQUIRED to display navigation chrome.
  ///
  /// `true`  → the role's landing screen hosts a nav bar; [chromeFinder] points
  ///           at it and the router tier asserts `findsOneWidget`.
  /// `false` → intentional "coming soon" landing with no chrome (by design,
  ///           current MVP state); the router tier asserts the bar is ABSENT and
  ///           [comingSoonReason] documents why. A FUTURE change that gives the
  ///           role a shell will flip this row and be caught.
  final bool hasChrome;

  /// Finds the expected nav-chrome widget once the role has landed. Non-null iff
  /// [hasChrome] is true.
  final Finder? chromeFinder;

  /// Human-readable name of the chrome widget (for failure messages).
  final String? chromeDescription;

  /// Why this role has no chrome yet (for the no-chrome rows). Non-null iff
  /// [hasChrome] is false.
  final String? comingSoonReason;

  /// Phase 21.8 — `true` when [expectedLandingPath] is a TRANSIENT resolver
  /// stopover (`SalonHomeResolverScreen`, `RouteNames.salonHome`) that
  /// forwards elsewhere the instant its data resolves, rather than a
  /// destination the viewer lingers on. The pure-fn tier
  /// (`role_landing_dispatch_guard_test.dart`) still asserts
  /// `roleHomePath(role) == expectedLandingPath` unconditionally — that
  /// contract does not change. The router tier
  /// (`role_landing_chrome_test.dart`) does NOT assert the router's FINAL
  /// settled location equals [expectedLandingPath] for a transient row (it
  /// will have moved on to the real shell by the time chrome renders); it
  /// only asserts the expected chrome eventually appears.
  final bool locationIsTransient;
}

/// THE matrix — single source of truth. Verified against the real code:
///   • role_home.dart      — roleHomePath() switch
///   • auth_redirect.dart  — role-gate bounce targets (all via roleHomePath)
///   • app_router.dart     — `/home` → ClientShell(StatefulShellRoute),
///                           `/master/profile` → MasterProfileScreen
///                           (hosts VelvetBottomNavBar), `/` → _Placeholder
///                           (NO chrome), `/salons/home` (Phase 21.8) →
///                           SalonHomeResolverScreen, a TRANSIENT stopover
///                           that forwards to `/salons/:salonId/shell` →
///                           SalonShellScreen (hosts SalonBottomNav),
///                           `/staff/profile` → SalonMasterProfileScreen
///                           (hosts VelvetBottomNavBar, 2026-09-01).
///
/// "No chrome" and "lands on the bare `/` placeholder" are NOT the same
/// thing (Phase 21.1 split them) — a no-chrome row's `expectedLandingPath`
/// is checked per-row below, not collapsed onto one shared literal.
///
/// ┌─────────────────────┬──────────────────┬──────────────────────────────┐
/// │ Role                │ Landing path     │ Expected nav chrome           │
/// ├─────────────────────┼──────────────────┼──────────────────────────────┤
/// │ CLIENT              │ /home            │ ClientBottomNav  (REQUIRED)   │
/// │ INDEPENDENT_MASTER  │ /master/profile  │ VelvetBottomNavBar (REQUIRED) │
/// │ SALON_OWNER         │ /salons/home     │ SalonBottomNav (REQUIRED) —   │
/// │                     │ (resolver, 21.8) │ via the shell it forwards to  │
/// │ SALON_ADMIN         │ /salons/home     │ SalonBottomNav (REQUIRED) —   │
/// │                     │ (resolver, 21.8) │ same shared shell as owner    │
/// │ SALON_MASTER        │ /staff/profile   │ VelvetBottomNavBar (REQUIRED) │
/// │                     │                  │ — same shared bar as          │
/// │                     │                  │ INDEPENDENT_MASTER (2026-09-01)│
/// └─────────────────────┴──────────────────┴──────────────────────────────┘
final List<RoleLandingExpectation> roleLandingMatrix = <RoleLandingExpectation>[
  RoleLandingExpectation(
    role: UserRole.client,
    expectedLandingPath: RouteNames.clientHome, // '/home'
    hasChrome: true,
    chromeFinder: find.byType(ClientBottomNav),
    chromeDescription: 'ClientBottomNav (the CLIENT 5-tab shell bar)',
  ),
  RoleLandingExpectation(
    role: UserRole.independentMaster,
    expectedLandingPath: RouteNames.masterProfile, // '/master/profile'
    hasChrome: true,
    chromeFinder: find.byType(VelvetBottomNavBar),
    chromeDescription: 'VelvetBottomNavBar (the master-profile 4-tile bar)',
  ),
  // Phase 21.8 — both salon roles now share ONE landing: the resolver at
  // `/salons/home` (roleHomePath), which forwards to `/salons/:salonId
  // /shell` (SalonShellScreen, hosting SalonBottomNav) the instant its data
  // resolves. `expectedLandingPath` is what `roleHomePath` itself returns
  // (the resolver's own path — needed by the pure-fn tier and by
  // auth_redirect_test.dart's direct assertions); `locationIsTransient:
  // true` tells the router tier not to expect the FINAL settled location to
  // still be the resolver once its chrome-bearing shell has rendered.
  RoleLandingExpectation(
    role: UserRole.salonOwner,
    expectedLandingPath: RouteNames.salonHome, // '/salons/home'
    hasChrome: true,
    chromeFinder: find.byType(SalonBottomNav),
    chromeDescription: 'SalonBottomNav (the Salon Shell bar, Phase 21.8)',
    locationIsTransient: true,
  ),
  RoleLandingExpectation(
    role: UserRole.salonAdmin,
    expectedLandingPath: RouteNames.salonHome, // '/salons/home'
    hasChrome: true,
    chromeFinder: find.byType(SalonBottomNav),
    chromeDescription: 'SalonBottomNav (the Salon Shell bar, Phase 21.8)',
    locationIsTransient: true,
  ),
  // Fixes the "blank home" bug: SALON_MASTER used to fall through
  // `roleHomePath`'s `_` wildcard onto the bare `_Placeholder('home')` at
  // `/`. It now lands on a REAL screen — `SalonMasterProfileScreen`, the
  // role's own read-only personal-profile self-view (no salon profile, no
  // team surface — still a later increment) — which, as of 2026-09-01, hosts
  // the SAME `VelvetBottomNavBar` INDEPENDENT_MASTER's `MasterProfileScreen`
  // does, `activeIndex: 3`. This row previously pinned `hasChrome: false`;
  // this is the flip that comment predicted.
  RoleLandingExpectation(
    role: UserRole.salonMaster,
    expectedLandingPath: RouteNames.salonMasterProfile, // '/staff/profile'
    hasChrome: true,
    chromeFinder: find.byType(VelvetBottomNavBar),
    chromeDescription:
        'VelvetBottomNavBar (the master-profile 4-tile bar, shared with '
        'INDEPENDENT_MASTER)',
  ),
];

/// Sanity check used by both tiers: the matrix must cover EVERY [UserRole].
/// If a new role is added to the enum, this fails until a row is added — the
/// matrix can never silently miss a role.
void assertMatrixCoversAllRoles() {
  final covered = roleLandingMatrix.map((e) => e.role).toSet();
  final all = UserRole.values.toSet();
  expect(
    covered,
    equals(all),
    reason:
        'roleLandingMatrix must have exactly one row per UserRole. Missing: '
        '${all.difference(covered)}. Add a row in '
        'test/routing/role_landing_chrome_matrix.dart (see "HOW TO ADD A ROW").',
  );
  expect(
    roleLandingMatrix.length,
    equals(UserRole.values.length),
    reason: 'exactly one matrix row per role — no duplicates',
  );
}
