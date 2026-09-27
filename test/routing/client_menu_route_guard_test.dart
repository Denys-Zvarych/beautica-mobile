// Route-guard tests for the CLIENT settings hub + edit routes (/client/*).
//
// Mirrors the master /master/* role-gate tests: a CLIENT may reach /client/menu
// and the /client/edit/* pages, while a non-CLIENT authenticated role
// (INDEPENDENT_MASTER) is bounced away to its own landing. These routes are NOT
// opened to other roles.
//
// Exercises the @visibleForTesting pure seam `authRedirectForLocation` directly
// — no widget tree needed.

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/routing/auth_redirect.dart';
import 'package:beautica_mobile/routing/role_home.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _clientUser = User(
  id: 'u2',
  email: 'client@example.com',
  role: UserRole.client,
  firstName: 'Client',
  lastName: 'User',
);

const _masterUser = User(
  id: 'u1',
  email: 'master@example.com',
  role: UserRole.independentMaster,
  firstName: 'Master',
  lastName: 'User',
);

const _clientSession = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _clientUser, accessToken: 'token'),
);

const _masterSession = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _masterUser, accessToken: 'token'),
);

// Phase 356 D3 — a SALON_ADMIN gets its OWN `/profile/admin/settings/*`
// leaves (`RouteNames.adminEditPersonal`/`adminEditContacts`) that reuse the
// SAME `ClientPersonalInfoEditScreen`/`ClientContactsEditScreen` widgets
// these `/client/edit/*` routes render — precisely BECAUSE this `/client/*`
// prefix gate below bounces every non-CLIENT role, admin included, off the
// CLIENT-owned path. This session pins that invariant: it must stay true
// after Phase 356, or the admin routes would have been an unneeded fork.
const _adminUser = User(
  id: 'u3',
  email: 'admin@example.com',
  role: UserRole.salonAdmin,
  firstName: 'Admin',
  lastName: 'User',
);

const _adminSession = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _adminUser, accessToken: 'token'),
);

void main() {
  group('/client/* route gate', () {
    const clientRoutes = <String>[
      RouteNames.clientMenu,
      RouteNames.clientEditPersonal,
      RouteNames.clientEditContacts,
      RouteNames.clientEditLocation,
    ];

    for (final route in clientRoutes) {
      test('CLIENT may reach $route (no redirect)', () {
        expect(
          authRedirectForLocation(_clientSession, route),
          isNull,
          reason: 'a CLIENT must be allowed to reach $route',
        );
      });

      test('INDEPENDENT_MASTER is bounced off $route to its own landing', () {
        final redirect = authRedirectForLocation(_masterSession, route);
        expect(
          redirect,
          isNotNull,
          reason: 'a non-CLIENT role must NOT reach the CLIENT route $route',
        );
        expect(
          redirect,
          equals(RouteNames.masterProfile),
          reason: 'INDEPENDENT_MASTER bounces to its own profile landing',
        );
      });
    }

    // Phase 356 D3 — see the fixture's own doc above. `RouteNames.
    // clientEditPersonal` stands in for the whole `/client/edit/*` family:
    // the prefix check above already proves every route under it is gated
    // identically, so a SECOND route here would only repeat the same
    // assertion.
    test('SALON_ADMIN is bounced off ${RouteNames.clientEditPersonal} to '
        'roleHomePath(salonAdmin), never admitted onto the CLIENT route', () {
      final redirect = authRedirectForLocation(
        _adminSession,
        RouteNames.clientEditPersonal,
      );
      expect(
        redirect,
        isNotNull,
        reason:
            'a SALON_ADMIN must NOT reach the CLIENT-owned '
            '${RouteNames.clientEditPersonal} — it has its own '
            '${RouteNames.adminEditPersonal} instead (Phase 356 D3)',
      );
      expect(redirect, equals(roleHomePath(UserRole.salonAdmin)));
    });
  });
}
