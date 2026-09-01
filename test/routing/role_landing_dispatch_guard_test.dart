// Pure-fn dispatch guard — the cheap net for the f929caf bug class.
//
// This tier asserts the HELPER CONTRACT without standing up any widget tree:
// for EVERY role, `roleHomePath(role)` must resolve to the destination the
// role→landing→chrome matrix declares, AND no role whose landing is supposed to
// host chrome may resolve to the bare `/` placeholder.
//
// WHY THIS WOULD HAVE CAUGHT THE ORIGINAL BUG
// -------------------------------------------
// The bug was a CLIENT being sent to `RouteNames.home` ('/') — the no-chrome
// placeholder — instead of `RouteNames.clientHome` ('/home'). The matrix row for
// CLIENT declares expectedLandingPath = RouteNames.clientHome AND hasChrome =
// true. The first test below asserts roleHomePath(client) == '/home' (would have
// failed on the buggy '/' mapping), and the second asserts that a chrome-bearing
// role NEVER lands on the bare placeholder '/' (an independent angle that fails
// even if someone "fixes" the matrix to match a wrong helper). This is the
// cheapest possible reproduction of the defect — no router, no pump.
//
// Note: `test/` is excluded from the no_raw_ui_strings lint; assertions key off
// route constants only (mobile-qa M2).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/routing/role_home.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter_test/flutter_test.dart';

import 'role_landing_chrome_matrix.dart';

/// The known, closed set of intentional "coming-soon"/no-persistent-
/// bottom-nav-chrome landing paths (Phase 21.1 — see the invariant test
/// below for why this replaced a single shared literal). An addition here
/// must be deliberate, paired with a matrix row update.
const Set<String> kChromelessLandingPaths = <String>{
  RouteNames.home,
  RouteNames.mySalons,
  RouteNames.salonMasterProfile,
};

void main() {
  group('roleHomePath dispatch contract (matrix-driven)', () {
    test('matrix covers every UserRole exactly once', () {
      assertMatrixCoversAllRoles();
    });

    // ── Per-role: roleHomePath resolves to the matrix's declared landing ────
    // Data-driven: one assertion per row, no copy-paste. The CLIENT row alone
    // is the f929caf regression — roleHomePath(client) must be '/home', never
    // '/'.
    for (final row in roleLandingMatrix) {
      test(
        'roleHomePath(${row.role.name}) resolves to ${row.expectedLandingPath}',
        () {
          expect(
            roleHomePath(row.role),
            equals(row.expectedLandingPath),
            reason:
                '${row.role.name} must land on ${row.expectedLandingPath}. A '
                'mismatch here is the f929caf bug class: the role is dispatched '
                'to the wrong screen (e.g. CLIENT → "/" instead of "/home").',
          );
        },
      );
    }

    // ── Cross-cutting invariant: chrome-bearing roles never land on the bare
    // placeholder. This is the INDEPENDENT angle — it does not read the helper
    // through the matrix's own expectedLandingPath, it checks the actual
    // resolved path against the known-no-chrome route. So even a matrix that was
    // wrongly edited to match a buggy helper would still trip this.
    test(
      'no chrome-bearing role resolves to the bare "/" placeholder (no-chrome '
      'route)',
      () {
        for (final row in roleLandingMatrix.where((e) => e.hasChrome)) {
          final resolved = roleHomePath(row.role);
          expect(
            resolved,
            isNot(equals(RouteNames.home)),
            reason:
                '${row.role.name} is declared to host nav chrome '
                '(${row.chromeDescription}) but roleHomePath resolves it to '
                '"${RouteNames.home}" — the chrome-less placeholder. This is '
                'exactly the f929caf defect: the role can never see its bottom '
                'bar because it is delivered to the wrong screen.',
          );
        }
      },
    );

    // ── No-chrome rows resolve to a KNOWN chromeless landing path. Pins the
    // intended current state so a future shell that quietly redirects a
    // salon role elsewhere (without updating the matrix) is caught.
    //
    // Phase 21.1 REVISION: this used to assert every no-chrome row collapsed
    // onto the ONE bare `/` placeholder — true before Phase 21.1, when all
    // three no-chrome roles (SALON_OWNER/SALON_ADMIN/SALON_MASTER) genuinely
    // rendered `_Placeholder('home')` at `/`. SALON_OWNER now lands on a REAL
    // screen (`MySalonsScreen`, the My Salons Hub, `/salons/mine`) that
    // simply has no persistent bottom-nav bar of its own — "no chrome" and
    // "the bare `/` placeholder" are no longer the same concept, so the old
    // single-literal assertion is not a real invariant any more.
    //
    // What replaces it is NOT weaker: [kChromelessLandingPaths] enumerates
    // the CLOSED set of chromeless destinations (an addition here must be
    // deliberate), AND every row is still cross-checked against its OWN
    // matrix-declared `expectedLandingPath` — a row silently drifting onto a
    // DIFFERENT already-enumerated chromeless path (e.g. SALON_OWNER quietly
    // resolving to `RouteNames.home` instead of its declared
    // `RouteNames.mySalons`) still fails the second `expect` below, even
    // though `RouteNames.home` is itself a known chromeless path.
    test(
      'every intentional no-chrome role resolves to a KNOWN chromeless '
      'landing path — and specifically to the one its matrix row declares',
      () {
        for (final row in roleLandingMatrix.where((e) => !e.hasChrome)) {
          final String resolved = roleHomePath(row.role);
          expect(
            kChromelessLandingPaths,
            contains(resolved),
            reason:
                '${row.role.name} is declared coming-soon (no chrome) but '
                'roleHomePath resolved it to "$resolved", which is NOT one '
                'of the known chromeless landing paths '
                '($kChromelessLandingPaths). If this role now has a real '
                'landing screen, add its path to kChromelessLandingPaths '
                'AND update the matrix row\'s expectedLandingPath. Reason '
                'on record: ${row.comingSoonReason}',
          );
          expect(
            resolved,
            equals(row.expectedLandingPath),
            reason:
                '${row.role.name} resolved to a KNOWN chromeless path '
                '($resolved) but not the ONE its own matrix row declares '
                '(${row.expectedLandingPath}) — a cross-role mix-up that '
                'set-membership alone would not catch.',
          );
        }
      },
    );

    // ── Exhaustiveness backstop: roleHomePath must return a non-empty path for
    // every role (no role falls through to '' / an unregistered route).
    test('roleHomePath returns a registered-looking path for every role', () {
      for (final role in UserRole.values) {
        final path = roleHomePath(role);
        expect(
          path,
          startsWith('/'),
          reason: 'roleHomePath(${role.name}) must be an absolute route path',
        );
        expect(path, isNotEmpty);
      }
    });
  });
}
