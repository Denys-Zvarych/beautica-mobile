// Phase 379 (24.1b) — the SALON_OWNER-only `/owner/master/*` prefix gate in
// `auth_redirect.dart`.
//
// Exercises the production pure seam `authRedirectForLocation` (the same seam
// `auth_redirect_test.dart` drives) for every role. The WIRED half — the real
// `appRouterProvider` admitting an owner onto `/owner/master/profile` and
// bouncing an INDEPENDENT_MASTER — lives in
// `test/features/salon/presentation/owner_own_profile_screen_test.dart`'s
// «master mode» group, next to the screen it mounts.
//
// Layer: Unit (pure redirect function).

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/routing/auth_redirect.dart';
import 'package:beautica_mobile/routing/role_home.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AsyncValue<AuthSession> _sessionFor(UserRole role) => AsyncData<AuthSession>(
  AuthSession.authenticated(
    user: User(
      id: 'u-${role.name}',
      email: '${role.name}@beautica.test',
      role: role,
      // A SALON_ADMIN's landing is salon-scoped — give it a salon so
      // roleHomePath resolves to its real shell, not a fallback.
      salonId: role == UserRole.salonAdmin ? 'salon-1' : null,
    ),
    accessToken: 'token',
  ),
);

const AsyncValue<AuthSession> _unauthenticated = AsyncData<AuthSession>(
  AuthSession.unauthenticated(),
);

/// Every `/owner/master/*` location the gate must cover — the routes 379/380
/// register plus the 381/383 paths, proving the gate is a PREFIX fence (later
/// phases add routes, never gates).
final List<String> _gatedLocations = <String>[
  RouteNames.ownerMasterProfile,
  // Phase 380 (24.1c) — the «Послуги» tab and its two drill-ins.
  RouteNames.ownerMasterServices,
  RouteNames.ownerMasterServiceSetup,
  RouteNames.ownerMasterServiceEdit('svc-1'),
  // Phase 381 (24.1d) — the «Графік» tab.
  RouteNames.ownerMasterSchedule,
  // Phase 383 (24.1f) — the «Записи» tab and its «Архів».
  RouteNames.ownerMasterBookings,
  RouteNames.ownerMasterBookingsArchive,
  // Phase 383 (decision 2026-10-07) — «Новий запис» walk-in chain.
  RouteNames.ownerMasterBookingNew,
  RouteNames.ownerMasterBookingNewServices,
];

void main() {
  group('/owner/master/* — SALON_OWNER only (phase 379)', () {
    for (final String location in _gatedLocations) {
      test('SALON_OWNER is ADMITTED at $location (no redirect)', () {
        expect(
          authRedirectForLocation(_sessionFor(UserRole.salonOwner), location),
          isNull,
        );
      });

      for (final UserRole role in <UserRole>[
        UserRole.client,
        UserRole.salonAdmin,
        UserRole.salonMaster,
        UserRole.independentMaster,
      ]) {
        test('${role.name} is BOUNCED off $location to roleHomePath', () {
          final AsyncValue<AuthSession> session = _sessionFor(role);
          final String home = roleHomePath(role);
          expect(
            authRedirectForLocation(session, location),
            equals(home),
            reason:
                'the owner master-mode subtree reads the owner\'s own '
                '/masters/me row and catalogue — no other role may land here',
          );
          expect(home, isNot(startsWith('/owner/master/')));
        });
      }

      test('unauthenticated is sent to login from $location', () {
        expect(
          authRedirectForLocation(_unauthenticated, location),
          equals(RouteNames.login),
        );
      });
    }

    test('INDEPENDENT_MASTER still reaches its own /master/bookings/new '
        '(the owner chain added routes, never re-gated the master one)', () {
      expect(
        authRedirectForLocation(
          _sessionFor(UserRole.independentMaster),
          RouteNames.masterBookingNew,
        ),
        isNull,
      );
      expect(
        authRedirectForLocation(
          _sessionFor(UserRole.independentMaster),
          RouteNames.masterBookingNewServices,
        ),
        isNull,
      );
    });

    test('the gate is scoped to /owner/master/, NOT /owner/ — '
        '/owner/edit/personal keeps its per-route mySalonsGuard and is not '
        'decided by this prefix gate', () {
      expect(
        authRedirectForLocation(
          _sessionFor(UserRole.client),
          RouteNames.ownerEditPersonal,
        ),
        isNull,
      );
    });
  });
}
