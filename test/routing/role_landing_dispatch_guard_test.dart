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

    // ── No-chrome rows really do resolve to the placeholder. Pins the intended
    // current state so a future shell that quietly redirects a salon role
    // elsewhere (without updating the matrix) is caught.
    test('every intentional no-chrome role resolves to "/" (coming-soon)', () {
      for (final row in roleLandingMatrix.where((e) => !e.hasChrome)) {
        expect(
          roleHomePath(row.role),
          equals(RouteNames.home),
          reason:
              '${row.role.name} is declared coming-soon (no chrome) and must '
              'land on "${RouteNames.home}". If this changed, update the matrix '
              'row to reflect the new shell. Reason on record: '
              '${row.comingSoonReason}',
        );
      }
    });

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
