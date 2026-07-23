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
  });
}
