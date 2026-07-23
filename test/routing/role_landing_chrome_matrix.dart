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
}

/// THE matrix — single source of truth. Verified against the real code:
///   • role_home.dart      — roleHomePath() switch
///   • auth_redirect.dart  — role-gate bounce targets (all via roleHomePath)
///   • app_router.dart     — `/home` → ClientShell(StatefulShellRoute),
///                           `/master/profile` → MasterProfileScreen
///                           (hosts VelvetBottomNavBar), `/` → _Placeholder
///                           (NO chrome).
///
/// ┌─────────────────────┬──────────────────┬──────────────────────────────┐
/// │ Role                │ Landing path     │ Expected nav chrome           │
/// ├─────────────────────┼──────────────────┼──────────────────────────────┤
/// │ CLIENT              │ /home            │ ClientBottomNav  (REQUIRED)   │
/// │ INDEPENDENT_MASTER  │ /master/profile  │ VelvetBottomNavBar (REQUIRED) │
/// │ SALON_OWNER         │ /  (placeholder) │ none — coming soon (intended) │
/// │ SALON_ADMIN         │ /  (placeholder) │ none — coming soon (intended) │
/// │ SALON_MASTER        │ /  (placeholder) │ none — coming soon (intended) │
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
  // ── Intentional no-chrome rows (MVP "coming soon"). These are NOT gaps —
  // they pin the CURRENT intended state so a future shell that ships for a
  // salon role flips the row (hasChrome → true + a chromeFinder) and is caught.
  const RoleLandingExpectation(
    role: UserRole.salonOwner,
    expectedLandingPath: RouteNames.home, // '/'
    hasChrome: false,
    comingSoonReason:
        'SALON_OWNER has no mobile shell yet (MVP). Lands on the `/` '
        'placeholder by design until the owner dashboard ships.',
  ),
  const RoleLandingExpectation(
    role: UserRole.salonAdmin,
    expectedLandingPath: RouteNames.home, // '/'
    hasChrome: false,
    comingSoonReason:
        'SALON_ADMIN (invited) has no mobile shell yet (MVP). Lands on `/` '
        'by design.',
  ),
  const RoleLandingExpectation(
    role: UserRole.salonMaster,
    expectedLandingPath: RouteNames.home, // '/'
    hasChrome: false,
    comingSoonReason:
        'SALON_MASTER (invited, read-only calendar) has no /master shell '
        '(that surface is INDEPENDENT_MASTER-only). Lands on `/` by design.',
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
