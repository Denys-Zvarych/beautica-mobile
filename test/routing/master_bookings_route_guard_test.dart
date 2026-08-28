// Phase 7.2/7.6 — the TWO-WAY authorization fence around the booking-detail
// screen (mobile-qa, G4 of the Phase 7.2/7.6 audit).
//
// WHY THIS FILE EXISTS
// --------------------
// `BookingDetailScreen` is ONE screen serving both sides of a booking on TWO
// routes:
//
//   `/bookings/:bookingId`         — the CLIENT's view  (clientBookings branch)
//   `/master/bookings/:bookingId`  — the PROVIDER's view (/master/* subtree)
//
// Which footer and which counterparty render is decided by
// `bookingViewerRoleProvider`, derived from the session. The ROUTE is what
// decides whether the viewer gets to the screen at all, and that is a separate
// property with a separate failure mode: the router's role gates.
//
// `auth_redirect_test.dart` covers the two gates GENERICALLY — it iterates the
// `/master/*` list and the client-shell branch list. Neither list contains a
// booking-DETAIL path. `booking_route_guard_test.dart` covers `/booking/*`
// (the client's booking-CREATION funnel), which is a different prefix
// entirely. So the exact pair of paths this phase shipped had no gate test at
// all, in either direction.
//
// The regression that leaves is quiet and bad: a CLIENT reaching
// `/master/bookings/<someone-else's-id>` is a horizontal-privilege path onto a
// PII surface (client full name + free-text notes), and the screen itself
// would render the CLIENT branch — no error, no empty state, just the wrong
// person's appointment behind a plausible-looking UI. The server is the real
// authority, but the router gate is the layer that is supposed to make the
// request never happen, and a refactor of `auth_redirect.dart` can remove it
// without failing anything.
//
// DEEP LINKS ARE COVERED SEPARATELY FROM IN-APP NAVIGATION on purpose: the
// gate runs on `redirect`, which fires for BOTH, but only the deep-link case
// exercises it as the FIRST routing decision of the session (cold start, no
// stack to pop back to). The `_loadingSession` cases below are that same cold
// window.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/routing/auth_redirect.dart';
import 'package:beautica_mobile/routing/route_names.dart';

const User _masterUser = User(
  id: 'u1',
  email: 'master@example.com',
  role: UserRole.independentMaster,
);
const User _clientUser = User(
  id: 'u2',
  email: 'client@example.com',
  role: UserRole.client,
);
const User _salonOwnerUser = User(
  id: 'u3',
  email: 'owner@example.com',
  role: UserRole.salonOwner,
);

const AsyncValue<AuthSession> _master = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _masterUser, accessToken: 't'),
);
const AsyncValue<AuthSession> _client = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _clientUser, accessToken: 't'),
);
const AsyncValue<AuthSession> _salonOwner = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _salonOwnerUser, accessToken: 't'),
);
const AsyncValue<AuthSession> _signedOut = AsyncData<AuthSession>(
  AuthSession.unauthenticated(),
);
const AsyncValue<AuthSession> _stillLoading = AsyncLoading<AuthSession>();

void main() {
  // The concrete instantiated paths, not the `:bookingId` patterns — the gate
  // matches on the LOCATION, so an id-bearing path is what must be tested.
  const String masterList = RouteNames.masterBookings; // /master/bookings
  final String masterDetail = RouteNames.masterBookingDetail('bk-1');
  // Phase 231 — the master «Архів» page (/master/bookings/archive), a sibling
  // of masterDetail under the same /master/bookings parent. Added to this
  // loop rather than a standalone test: it inherits the SAME `/master/*`
  // prefix gate `auth_redirect.dart` already applies, and this file is the
  // one place that gate is pinned per-route (see the file header — the
  // generic `/master/*` prefix sweep lives in `auth_redirect_test.dart`, but
  // neither list contained a booking sub-route until this file existed).
  const String masterArchive = RouteNames.masterBookingsArchive;
  const String clientList = RouteNames.clientBookings; // /bookings
  final String clientDetail = RouteNames.bookingDetail('bk-1');

  group('the PROVIDER route (/master/bookings/**) admits only '
      'INDEPENDENT_MASTER', () {
    for (final String route in <String>[
      masterList,
      masterDetail,
      masterArchive,
    ]) {
      test('INDEPENDENT_MASTER at $route is admitted', () {
        expect(
          authRedirectForLocation(_master, route),
          isNull,
          reason: 'the master must reach their own booking surface',
        );
      });

      test('CLIENT at $route is bounced to the client shell', () {
        expect(
          authRedirectForLocation(_client, route),
          RouteNames.clientHome,
          reason:
              'a CLIENT on the PROVIDER booking route is a horizontal-'
              'privilege path onto a PII surface (client names + free-text '
              'notes) that would render the CLIENT branch with no error at all',
        );
      });

      test('SALON_OWNER at $route is bounced to the My Salons Hub', () {
        expect(
          authRedirectForLocation(_salonOwner, route),
          RouteNames.mySalons,
          reason:
              'salon roles have no /master/* surface in MVP — the gate admits '
              'INDEPENDENT_MASTER only; a SALON_OWNER lands on its own '
              'Phase 21.1 landing (RouteNames.mySalons), not the bare home '
              'shell',
        );
      });

      // Auth-gate PRECEDENCE: a signed-out or not-yet-resolved session must be
      // forwarded to /login BEFORE the role gate is consulted, so a cold-start
      // deep link can never flash the screen.
      test('a signed-out deep link to $route lands on /login', () {
        expect(authRedirectForLocation(_signedOut, route), RouteNames.login);
      });

      test('a deep link to $route during the cold-start window (session still '
          'loading) does not fall through to the screen', () {
        expect(
          authRedirectForLocation(_stillLoading, route),
          isNot(isNull),
          reason:
              'an unresolved session must redirect somewhere (splash/login) — '
              'falling through renders the PII surface before anyone has been '
              'authenticated',
        );
      });
    }
  });

  group('the CLIENT route (/bookings/**) admits only CLIENT', () {
    for (final String route in <String>[clientList, clientDetail]) {
      test('CLIENT at $route is admitted', () {
        expect(authRedirectForLocation(_client, route), isNull);
      });

      test('INDEPENDENT_MASTER at $route is bounced to /master/profile', () {
        expect(
          authRedirectForLocation(_master, route),
          RouteNames.masterProfile,
          reason:
              'the master has their OWN detail route (/master/bookings/:id); '
              'landing on the client one would render the client footer — '
              '«Скасувати», «Записатись знову» — over their own appointment',
        );
      });

      test('SALON_OWNER at $route is bounced to the My Salons Hub', () {
        expect(
          authRedirectForLocation(_salonOwner, route),
          RouteNames.mySalons,
        );
      });

      test('a signed-out deep link to $route lands on /login', () {
        expect(authRedirectForLocation(_signedOut, route), RouteNames.login);
      });
    }
  });

  group('the two routes are genuinely distinct surfaces', () {
    // A guard against the cheapest possible way to break all of the above: if
    // the master detail path were ever nested under `/bookings`, the client
    // gate would swallow it and every assertion in the first group would be
    // evaluating the WRONG gate.
    test('the master detail path is NOT under the client bookings prefix', () {
      expect(
        masterDetail.startsWith('$clientList/'),
        isFalse,
        reason:
            'the provider route must not live under the CLIENT-only prefix — '
            'the two role gates would collapse into one',
      );
      expect(masterDetail, startsWith('/master/'));
      expect(clientDetail, startsWith('/bookings/'));
    });

    test('no session is admitted to BOTH detail routes', () {
      for (final AsyncValue<AuthSession> session in <AsyncValue<AuthSession>>[
        _master,
        _client,
        _salonOwner,
        _signedOut,
      ]) {
        final bool masterOk =
            authRedirectForLocation(session, masterDetail) == null;
        final bool clientOk =
            authRedirectForLocation(session, clientDetail) == null;
        expect(
          masterOk && clientOk,
          isFalse,
          reason:
              'one session reached both sides of the booking-detail fence — '
              'the CLIENT and PROVIDER views are mutually exclusive by role',
        );
      }
    });
  });
}
